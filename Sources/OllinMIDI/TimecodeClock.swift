import Foundation
import os

/// A moment on a timeline as timecode: hours, minutes, seconds, and frames at
/// one of the four frame rates MIDI Time Code carries. This is what a video
/// deck, a show controller, a lighting desk, or a DAW chasing picture counts
/// in, and what a sketch reads back through a `TimecodeClock`.
///
/// ```swift
/// let cue = Timecode(hours: 0, minutes: 1, seconds: 30, frames: 12, frameRate: .fps25)
/// cue.totalSeconds       // 90.48
/// cue.frameNumber        // 2262
/// "\(cue)"               // "00:01:30:12"
/// ```
///
/// Drop-frame timecode (`.fps30Drop`) counts thirty frames a second over video
/// that runs at 29.97, so it skips frame numbers 0 and 1 at the top of every
/// minute except each tenth, and the wall clock stays honest. `frameNumber`
/// and `totalSeconds` account for that; `Timecode(frameNumber:frameRate:)`
/// and `Timecode(seconds:frameRate:)` go the other way.
public struct Timecode: Sendable, Equatable, Hashable {

    /// The four rates the protocol names, in the two bits it names them by.
    public enum FrameRate: Int, Sendable, CaseIterable {
        case fps24 = 0
        case fps25 = 1
        /// Thirty frames a second counted over 29.97 video, two numbers
        /// dropped at the top of most minutes.
        case fps30Drop = 2
        case fps30 = 3

        /// How many frames the count runs to in a second: 24, 25, or 30.
        public var framesPerSecond: Int {
            switch self {
            case .fps24: 24
            case .fps25: 25
            case .fps30Drop, .fps30: 30
            }
        }

        /// How long a frame lasts on the wall clock. Drop frame runs at 29.97,
        /// so a frame is a hair longer than a thirtieth.
        public var secondsPerFrame: Double {
            self == .fps30Drop ? 1001.0 / 30000.0 : 1 / Double(framesPerSecond)
        }

        public var isDropFrame: Bool { self == .fps30Drop }

        /// The rate's name as a broadcast engineer writes it.
        public var name: String {
            switch self {
            case .fps24: "24"
            case .fps25: "25"
            case .fps30Drop: "29.97 drop"
            case .fps30: "30"
            }
        }
    }

    public var hours: Int
    public var minutes: Int
    public var seconds: Int
    public var frames: Int
    public var frameRate: FrameRate

    public init(hours: Int, minutes: Int, seconds: Int, frames: Int, frameRate: FrameRate) {
        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
        self.frames = frames
        self.frameRate = frameRate
    }

    /// The timecode `frameNumber` frames from zero, counted at `frameRate`,
    /// with the dropped numbers left out of the count where the rate drops.
    public init(frameNumber: Int, frameRate: FrameRate) {
        var count = max(0, frameNumber)
        if frameRate.isDropFrame {
            // Every ten minutes hold 17,982 frames and every other minute 1,798:
            // put the dropped numbers back so the split into fields comes out
            // on the labels the tape shows.
            let tenMinutes = count / 17982
            let remainder = count % 17982
            count += 18 * tenMinutes
            if remainder >= 2 { count += 2 * ((remainder - 2) / 1798) }
        }
        let perSecond = frameRate.framesPerSecond
        frames = count % perSecond
        let wholeSeconds = count / perSecond
        seconds = wholeSeconds % 60
        minutes = (wholeSeconds / 60) % 60
        hours = wholeSeconds / 3600
        self.frameRate = frameRate
    }

    /// The timecode of the frame that holds `seconds` on the wall clock.
    public init(seconds: Double, frameRate: FrameRate) {
        let frame = Int((max(0, seconds) / frameRate.secondsPerFrame).rounded(.down))
        self.init(frameNumber: frame, frameRate: frameRate)
    }

    /// How many frames from zero this is, the dropped numbers not counted.
    public var frameNumber: Int {
        let perSecond = frameRate.framesPerSecond
        let totalMinutes = hours * 60 + minutes
        var count = ((hours * 3600 + minutes * 60 + seconds) * perSecond) + frames
        if frameRate.isDropFrame {
            count -= 2 * (totalMinutes - totalMinutes / 10)
        }
        return count
    }

    /// This moment on the wall clock, in seconds from zero.
    public var totalSeconds: Double { Double(frameNumber) * frameRate.secondsPerFrame }

    /// The same moment `frames` later (or earlier, negative).
    public func advanced(by frames: Int) -> Timecode {
        Timecode(frameNumber: frameNumber + frames, frameRate: frameRate)
    }
}

extension Timecode: CustomStringConvertible {
    /// `hh:mm:ss:ff`, with a semicolon before the frames where the rate drops,
    /// the way a broadcast display writes it.
    public var description: String {
        let separator = frameRate.isDropFrame ? ";" : ":"
        return String(format: "%02d:%02d:%02d%@%02d", hours, minutes, seconds, separator, frames)
    }
}

// MARK: - The wire forms

public extension Timecode {
    /// The data nibble of quarter-frame message `piece` (0…7) for this
    /// timecode: the eight of them spell the whole time, two frames' worth of
    /// messages, four to a frame.
    func quarterFrameValue(piece: Int) -> Int {
        switch piece {
        case 0: return frames & 0xF
        case 1: return (frames >> 4) & 0x1
        case 2: return seconds & 0xF
        case 3: return (seconds >> 4) & 0x3
        case 4: return minutes & 0xF
        case 5: return (minutes >> 4) & 0x3
        case 6: return hours & 0xF
        default: return ((hours >> 4) & 0x1) | (frameRate.rawValue << 1)
        }
    }

    /// The timecode the eight quarter-frame nibbles spell, indexed by piece.
    init(quarterFrameValues nibbles: [Int]) {
        let rate = FrameRate(rawValue: (nibbles[7] >> 1) & 0x3) ?? .fps30
        self.init(hours: (nibbles[6] & 0xF) | ((nibbles[7] & 0x1) << 4),
                  minutes: (nibbles[4] & 0xF) | ((nibbles[5] & 0x3) << 4),
                  seconds: (nibbles[2] & 0xF) | ((nibbles[3] & 0x3) << 4),
                  frames: (nibbles[0] & 0xF) | ((nibbles[1] & 0x1) << 4),
                  frameRate: rate)
    }

    /// The body of the full-frame system exclusive message that carries this
    /// timecode whole (a locate: the sender jumped, or stopped here), the
    /// bytes between the exclusive's start and end.
    var fullFrameSysEx: [UInt8] {
        [0x7F, 0x7F, 0x01, 0x01,
         UInt8((frameRate.rawValue << 5) | (hours & 0x1F)),
         UInt8(minutes & 0x3F), UInt8(seconds & 0x3F), UInt8(frames & 0x1F)]
    }

    /// The timecode a full-frame exclusive carries, or nil for any other
    /// exclusive. `bytes` are the message between its start and end.
    init?(fullFrameSysEx bytes: [UInt8]) {
        guard bytes.count == 8, bytes[0] == 0x7F, bytes[2] == 0x01, bytes[3] == 0x01 else { return nil }
        let rate = FrameRate(rawValue: Int(bytes[4] >> 5) & 0x3) ?? .fps30
        self.init(hours: Int(bytes[4] & 0x1F), minutes: Int(bytes[5] & 0x3F),
                  seconds: Int(bytes[6] & 0x3F), frames: Int(bytes[7] & 0x1F), frameRate: rate)
    }
}

// MARK: - The clock

/// Follows MIDI Time Code so a sketch chases a timeline: a video deck, a show
/// controller, a lighting desk, or a DAW locked to picture. Create one over a
/// `MIDIInput`, start the input, then read the position in `draw()`:
///
/// ```swift
/// let midi = MIDIInput()
/// lazy var timecode = TimecodeClock(from: midi)
/// override func setup() { try? midi.start() }
/// override func draw() {
///     let t = timecode.seconds                      // where the timeline is, in seconds
///     if let code = timecode.timecode { drawText("\(code)", 40, 60) }
///     if timecode.isPlaying { /* the show is rolling */ }
/// }
/// ```
///
/// The reads: `timecode` (the frame the timeline is on), `seconds` (the same
/// as a continuous number, gliding between frames), `frameRate`, `isPlaying`
/// (quarter frames are arriving), and `isReceiving` (any timecode arrived
/// within the last second).
///
/// How it reads the wire: a running sender spells the time in eight
/// quarter-frame messages, four a frame, so a whole time takes two frames to
/// arrive; the clock counts every quarter frame as a quarter of a frame in
/// the direction the pieces run, and re-anchors on each completed set, so the
/// position is exact at every message and glides at the frame rate between
/// them. A full-frame exclusive (sent on a locate, or when the transport
/// stops) sets the position outright. Silence for half a second means the
/// transport stopped, and the position holds where it was.
public final class TimecodeClock: @unchecked Sendable {

    /// Retained so the clock keeps listening even when the sketch only stores
    /// the `TimecodeClock` itself.
    private let input: MIDIInput
    private let engine = OSAllocatedUnfairLock(initialState: TimecodeEngine())

    /// Creates a clock fed by `input`. Remember to `start()` the input; the
    /// clock reads whatever timecode arrives on it.
    public init(from input: MIDIInput) {
        self.input = input
        // Formed in this non-isolated init so the Core MIDI thread can call
        // them without tripping an executor assertion.
        input.addListener { [weak self] message, time in
            guard case .timecodeQuarterFrame(let piece, let value) = message.kind else { return }
            self?.engine.withLock { $0.handle(piece: piece, value: value, at: time) }
        }
        input.addSysExListener { [weak self] bytes, time in
            guard let code = Timecode(fullFrameSysEx: bytes) else { return }
            self?.engine.withLock { $0.locate(to: code, at: time) }
        }
    }

    /// The frame the timeline is on, or nil until any timecode has arrived.
    public var timecode: Timecode? {
        let now = HostClock.now
        return engine.withLock { $0.timecode(at: now) }
    }

    /// The position in seconds, gliding at the frame rate between messages.
    /// `0` until any timecode has arrived.
    public var seconds: Double {
        let now = HostClock.now
        return engine.withLock { $0.seconds(at: now) }
    }

    /// The rate the sender counts at, once known.
    public var frameRate: Timecode.FrameRate? { engine.withLock { $0.frameRate } }

    /// Whether the timeline is moving: quarter frames arrived within the last
    /// half second.
    public var isPlaying: Bool {
        let now = HostClock.now
        return engine.withLock { $0.isPlaying(at: now) }
    }

    /// Whether any timecode, running or a locate, arrived within the last second.
    public var isReceiving: Bool {
        let now = HostClock.now
        return engine.withLock { $0.isReceiving(at: now) }
    }

    /// Whether the timeline is running backward, as a deck shuttling in
    /// reverse sends its pieces in reverse.
    public var isReversed: Bool { engine.withLock { $0.direction < 0 } }
}

// MARK: - The engine (pure, deterministic)

/// The position math behind `TimecodeClock`, kept free of Core MIDI and real
/// clocks so tests can drive it with synthetic timestamps. All times are in
/// seconds on one monotonic clock; positions are in frames.
struct TimecodeEngine {

    private(set) var frameRate: Timecode.FrameRate?
    /// +1 running forward, -1 backward, from the order the pieces arrive in.
    private(set) var direction = 1.0

    /// The nibbles of the set being spelled, -1 where not yet heard.
    private var pieces = [Int](repeating: -1, count: 8)
    private var lastPiece: Int?
    private var lastQuarterTime: Double?
    private var lastAnyTime: Double?

    /// The position in frames at a moment: exact on every message, the base
    /// the glide runs from.
    private var anchor: (frames: Double, time: Double)?

    /// Quarter frames spell a frame in four; the eighth completes a set two
    /// frames after the first was sent, so the time a set spells is 1.75
    /// frames behind the moment its last piece lands (forward) or ahead of it
    /// (backward).
    private static let setSpan = 1.75
    private static let stopAfter = 0.5

    // MARK: Feeding

    mutating func handle(piece: Int, value: Int, at time: Double) {
        guard (0 ..< 8).contains(piece) else { return }
        if let last = lastPiece {
            if piece == (last + 1) % 8 {
                direction = 1
            } else if piece == (last + 7) % 8 {
                direction = -1
            } else {
                // A skip: the sender jumped, start the set over.
                pieces = [Int](repeating: -1, count: 8)
            }
        }
        pieces[piece] = value & 0xF
        lastPiece = piece
        lastQuarterTime = time
        lastAnyTime = time

        let complete = !pieces.contains(-1) && (direction > 0 ? piece == 7 : piece == 0)
        if complete {
            let code = Timecode(quarterFrameValues: pieces)
            frameRate = code.frameRate
            anchor = (Double(code.frameNumber) + Self.setSpan * direction, time)
            pieces = [Int](repeating: -1, count: 8)
        } else if let known = anchor {
            anchor = (known.frames + 0.25 * direction, time)
        }
    }

    /// A full-frame message: the sender is here, and holding.
    mutating func locate(to code: Timecode, at time: Double) {
        frameRate = code.frameRate
        anchor = (Double(code.frameNumber), time)
        pieces = [Int](repeating: -1, count: 8)
        lastPiece = nil
        lastQuarterTime = nil
        lastAnyTime = time
    }

    // MARK: Reading

    func isPlaying(at time: Double) -> Bool {
        guard let last = lastQuarterTime else { return false }
        return time - last < Self.stopAfter
    }

    func isReceiving(at time: Double) -> Bool {
        guard let last = lastAnyTime else { return false }
        return time - last < 1
    }

    /// The position in frames: the anchor, plus the glide since it at the
    /// frame rate while playing, held just short of the next quarter frame so
    /// a late message never runs the position backward.
    func frames(at time: Double) -> Double? {
        guard let anchor, let rate = frameRate else { return nil }
        guard isPlaying(at: time) else { return anchor.frames }
        let elapsed = (time - anchor.time) / rate.secondsPerFrame
        return anchor.frames + min(max(elapsed, 0), 0.249) * direction
    }

    func seconds(at time: Double) -> Double {
        guard let frames = frames(at: time), let rate = frameRate else { return 0 }
        return max(0, frames) * rate.secondsPerFrame
    }

    func timecode(at time: Double) -> Timecode? {
        guard let frames = frames(at: time), let rate = frameRate else { return nil }
        return Timecode(frameNumber: Int(max(0, frames).rounded(.down)), frameRate: rate)
    }
}
