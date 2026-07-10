import Foundation
import os

/// Follows MIDI clock so a sketch moves on the beat of whatever is playing: a
/// DAW, a drum machine, a DJ mixer, anything that sends the standard sync
/// messages (timing clock at 24 pulses per quarter note, plus the transport
/// messages start / stop / continue / song position). Create one over a
/// `MIDIInput`, start the input, then read musical time in `draw()`:
///
/// ```swift
/// let midi = MIDIInput()
/// lazy var clock = TempoClock(from: midi)
/// override func setup() { try? midi.start() }
/// override func draw() {
///     let throb = 1 + 0.2 * clock.beat                    // snaps on each beat, decays
///     drawCircle(width / 2, height / 2, 120 * throb)
///     let sweep = clock.progress(over: 8)                 // a 0…1 ramp every 8 beats
///     rotate(sweep * .tau)
/// }
/// ```
///
/// The reads: `tempo` (BPM), `beats` (continuous musical time in quarter notes),
/// `beatCount` / `phase` (its whole and fractional parts), `bar` / `barPhase`
/// (the same over `beatsPerBar`), `beat` (a ready-made 0…1 pulse, the shape the
/// audio analyzer's `beat` has), and `progress(over:)` for a ramp across any
/// number of beats.
///
/// How it stays honest under real-world clock: *position* comes from counting
/// ticks (each one is exactly 1/24 of a beat, so the beat grid can't drift), and
/// the *tempo* is a mean over a sliding window of recent tick intervals (about
/// two beats' worth), used only to glide `phase` between ticks and clamped so it
/// never runs backward. A tempo jump flushes the window so the new tempo locks
/// within a beat.
///
/// Transport follows the MIDI convention: `start` resets the position to zero
/// and the next tick is the downbeat; `continue` resumes from where `stop` froze
/// (or from a received song position). A master that only sends clock, with no
/// transport messages at all (common on DJ gear), free-runs: the first tick is
/// beat zero and the position advances from there. MIDI clock carries no meter,
/// so `beatsPerBar` (default 4) is declared here, and bar 0 is wherever the
/// position count began.
public final class TempoClock: @unchecked Sendable {

    /// Retained so the clock keeps listening even when the sketch only stores
    /// the `TempoClock` itself.
    private let input: MIDIInput
    private let engine = OSAllocatedUnfairLock(initialState: TempoEngine())
    private let meter = OSAllocatedUnfairLock(initialState: 4)

    /// Creates a clock fed by `input`. Remember to `start()` the input; the
    /// clock reads whatever sync messages arrive on it.
    public init(from input: MIDIInput) {
        self.input = input
        // Formed in this non-isolated init so the Core MIDI thread can call it
        // without tripping an executor assertion.
        input.addListener { [weak self] message, time in
            self?.engine.withLock { $0.handle(message.kind, at: time) }
        }
    }

    // MARK: Reading musical time

    /// The received tempo in beats per minute (smoothed), or `0` until enough
    /// ticks have arrived to measure one. Holds its last value if the clock
    /// pauses; check `isReceiving` for liveness.
    public var tempo: Double { engine.withLock { $0.tempo } }

    /// Whether the position is advancing: the transport is playing, or a
    /// transport-less master is free-running clock into us.
    public var isPlaying: Bool {
        let now = HostClock.now
        return engine.withLock { $0.isPlaying(at: now) }
    }

    /// Whether clock ticks have arrived within the last second.
    public var isReceiving: Bool {
        let now = HostClock.now
        return engine.withLock { $0.isReceiving(at: now) }
    }

    /// Continuous musical time in quarter notes since position zero: `2.5` is
    /// halfway through the third beat. Ticks set the grid; between ticks the
    /// value glides at the smoothed tempo. Frozen while stopped.
    public var beats: Double {
        let now = HostClock.now
        return engine.withLock { $0.beats(at: now) }
    }

    /// Which beat the position is on, counted from zero.
    public var beatCount: Int { Int(beats) }

    /// Progress through the current beat, `0…1`.
    public var phase: Double { beats.truncatingRemainder(dividingBy: 1) }

    /// A 0…1 pulse that snaps to 1 on each beat and decays over ~0.25 s: the
    /// ready-to-use "make it throb on the beat" value. `0` while stopped.
    public var beat: Double {
        let since = timeSinceBeat
        guard since.isFinite else { return 0 }
        return max(0, 1 - since / 0.25)
    }

    /// Seconds since the last beat landed (very large while stopped or before
    /// the first tick); drive a decaying flash from it, or read `beat` for the
    /// ready-made pulse.
    public var timeSinceBeat: Double {
        let now = HostClock.now
        return engine.withLock { engine in
            let bpm = engine.tempo
            guard bpm > 0, engine.isPlaying(at: now) else { return .greatestFiniteMagnitude }
            let position = engine.beats(at: now)
            return position.truncatingRemainder(dividingBy: 1) * (60 / bpm)
        }
    }

    // MARK: Bars

    /// Beats per bar for the `bar` / `barPhase` reads (default 4). MIDI clock
    /// carries no meter, so the sketch declares it.
    public var beatsPerBar: Int {
        get { meter.withLock { $0 } }
        set { meter.withLock { $0 = max(1, newValue) } }
    }

    /// Which bar the position is in, counted from zero.
    public var bar: Int { Int(beats) / beatsPerBar }

    /// Progress through the current bar, `0…1`.
    public var barPhase: Double {
        let length = Double(beatsPerBar)
        let wrapped = beats.truncatingRemainder(dividingBy: length)
        return wrapped / length
    }

    // MARK: Ramps

    /// A `0…1` sawtooth across `length` beats, the musical-time sibling of
    /// `loopProgress(over:phase:)`: `progress(over: 8)` ramps once every eight
    /// beats and wraps. `phase` is a fraction-of-cycle head start.
    public func progress(over length: Double, phase: Double = 0) -> Double {
        guard length > 0 else { return 0 }
        let raw = (beats / length + phase).truncatingRemainder(dividingBy: 1)
        return raw < 0 ? raw + 1 : raw
    }
}

// MARK: - The engine (pure, deterministic)

/// The tempo/position math behind `TempoClock`, kept free of Core MIDI and real
/// clocks so tests can drive it with synthetic timestamps. All times are in
/// seconds on one monotonic clock.
struct TempoEngine {

    enum Transport: Equatable {
        /// No transport message seen yet: clock free-runs the position.
        case idle
        /// `start` received: position is zero, the next tick is the downbeat.
        case armedStart
        /// `continue` received: the next tick resumes the frozen position.
        case armedContinue
        case playing
        case stopped
    }

    private(set) var transport: Transport = .idle

    /// The tick index of the most recent position-advancing clock: the position
    /// in 24ths of a beat.
    private(set) var lastPulseIndex = 0
    /// When that tick landed, or `nil` when the next tick should anchor the
    /// position without advancing it (after `start`, a song-position jump, or
    /// before the first tick ever).
    private var lastPulseTime: Double?

    /// The previous clock's time, for the interval chain. Separate from
    /// `lastPulseTime`: a master sending clock while stopped still reports
    /// tempo, and a position jump must not fake an interval.
    private var lastClockTime: Double?
    /// Recent tick intervals, newest last. About two beats' worth: enough to
    /// flatten the ±1 ms jitter typical of MIDI clock, short enough to track a
    /// tempo change within a beat.
    private var intervals: [Double] = []

    private static let windowSize = 48
    /// An interval longer than this (10 BPM) is a stream break, not a datum.
    private static let maximumInterval = 0.25
    /// An interval shorter than this is a burst artifact (batched delivery).
    private static let minimumInterval = 0.0005

    // MARK: Feeding

    mutating func handle(_ kind: MIDIMessage.Kind, at time: Double) {
        switch kind {
        case .clock:
            tick(at: time)
        case .start:
            transport = .armedStart
            lastPulseIndex = 0
            lastPulseTime = nil
        case .continue:
            if transport != .playing { transport = .armedContinue }
        case .stop:
            transport = .stopped
        case .songPosition(let sixteenths):
            lastPulseIndex = max(0, sixteenths) * 6
            lastPulseTime = nil
        default:
            break
        }
    }

    private mutating func tick(at time: Double) {
        // Tempo first; the interval chain runs in every transport state.
        if let previous = lastClockTime {
            let dt = time - previous
            if dt > Self.maximumInterval {
                intervals.removeAll(keepingCapacity: true)   // stream break: stale intervals would poison the mean
            } else if dt > Self.minimumInterval {
                if let mean = meanInterval, dt > mean * 1.5 || dt < mean * 0.6 {
                    intervals.removeAll(keepingCapacity: true)   // tempo jump: flush so the new tempo locks fast
                }
                intervals.append(dt)
                if intervals.count > Self.windowSize { intervals.removeFirst() }
            }
        }
        lastClockTime = time

        // Position second. An armed transport begins on this tick.
        switch transport {
        case .armedStart, .armedContinue: transport = .playing
        case .stopped: return
        case .idle, .playing: break
        }
        if lastPulseTime != nil { lastPulseIndex += 1 }
        lastPulseTime = time
    }

    // MARK: Reading

    private var meanInterval: Double? {
        guard !intervals.isEmpty else { return nil }
        return intervals.reduce(0, +) / Double(intervals.count)
    }

    /// Beats per minute from the smoothed tick interval, `0` until measurable.
    var tempo: Double {
        guard let interval = meanInterval else { return 0 }
        return 2.5 / interval   // 60 / (24 ticks · interval)
    }

    func isReceiving(at time: Double) -> Bool {
        guard let last = lastClockTime else { return false }
        return time - last < 1
    }

    func isPlaying(at time: Double) -> Bool {
        transport == .playing || (transport == .idle && isReceiving(at: time))
    }

    /// Continuous position in quarter notes. Ticks set the grid exactly; between
    /// ticks the fraction extrapolates at the smoothed tempo, clamped just short
    /// of the next tick so the position never runs backward when a tick is late.
    func beats(at time: Double) -> Double {
        let anchored = Double(lastPulseIndex) / 24
        guard let anchor = lastPulseTime,
              transport == .playing || transport == .idle,
              let interval = meanInterval else { return anchored }
        let fraction = min(max((time - anchor) / interval, 0), 0.999)
        return (Double(lastPulseIndex) + fraction) / 24
    }
}

// MARK: - Host time

/// Converts Core MIDI host-time stamps (mach ticks) to seconds, and reads the
/// same clock for "now", so tick timestamps and read-time extrapolation share
/// one time base.
enum HostClock {
    private static let secondsPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()

    static func seconds(_ ticks: UInt64) -> Double { Double(ticks) * secondsPerTick }

    static var now: Double { seconds(mach_absolute_time()) }
}
