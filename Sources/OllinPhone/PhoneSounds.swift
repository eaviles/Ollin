import Foundation
import Ollin
import os

/// The sounds a tethered iPhone hears, named as they happen, so a clap, a bark,
/// a siren, or a guitar in the room can drive a sketch on the Mac the way a
/// hand or a face on the phone's camera does.
///
/// The phone runs Apple's built-in sound classifier over its own microphone and
/// streams what it hears each window: every label it knows, with how sure it
/// is of each. This object is the Mac's end of that: the same two reads the
/// Mac's own `SoundClassifier` gives, so a sketch written against one reads
/// the other unchanged. *Is this music?* is a level that rises and falls:
/// `confidence(of:)`, `topClassification`, and `classifications` answer it.
/// *Did somebody just clap?* happens once: `events()` drains what crossed
/// `threshold` since the last call, and `timeSinceHearing(_:)` says how long
/// ago, for a mark that fades.
///
/// ```swift
/// let device = PhoneDevice()
/// override func setup() { device.start() }
/// override func draw() {
///     for event in device.sounds.events() where event.label == "clapping" { flash() }
///     let music = device.sounds.confidence(of: "music")     // a level, not an event
/// }
/// ```
///
/// The phone sends the whole judgment and the Mac decides what counts as a
/// sound starting, because the wire runs one way and the sketch is where a
/// threshold belongs. A label crossing `threshold` from below is an event; a
/// sound that keeps going is therefore one event, not one per window. The
/// classifier judges about a second and a half of audio at a time, so a short
/// sound is named a moment after it happens, and it is happy to guess:
/// `"music"` turns up faintly under almost anything, so read `threshold` and
/// `topClassification` rather than believing every small number.
///
/// Times run on the phone's audio clock, in seconds since it began listening.
/// Between readings the Mac carries that clock forward with its own, so a fade
/// on `timeSinceHearing(_:)` runs smoothly rather than stepping once a window.
///
/// The phone listens only while its **Hear** switch is on, and the microphone
/// asks its own permission there. Nothing arrives under a headless export, the
/// same as every other phone stream.
///
/// A sketch can be developed with no phone attached: `PhoneSounds()` stands
/// alone, and `hear(_:at:duration:)` feeds it what a phone would have sent,
/// which is how the tests and the Guide figure say exactly what was heard.
@MainActor
public final class PhoneSounds {

    struct State {
        var classifications: [SoundClassification] = []
        var top: SoundClassification?
        var confidences: [String: Double] = [:]
        var lastHeard: [String: Double] = [:]
        var pending: [SoundEvent] = []
        var above: Set<String> = []
        var threshold: Double = 0.6
        /// The end of the latest window on the phone's audio clock, and when
        /// it arrived on the Mac's, so the clock can be carried forward.
        var elapsed: Double = 0
        var arrived: TimeInterval?
        var readings = 0
    }

    nonisolated let state = OSAllocatedUnfairLock(initialState: State())

    /// The read the phone counts as still listening: a reading within this many
    /// seconds of now. A window is judged about twice a second, so a gap this
    /// long means the switch went off or the cable came out.
    private nonisolated static let listeningWindow: TimeInterval = 3

    /// A pair of ears with nothing heard yet. The device makes its own; make one
    /// here to develop or test a sketch with no phone attached, feeding it with
    /// `hear(_:at:duration:)`.
    public init() {}

    // MARK: The level

    /// Every label at or above `threshold` right now, most confident first.
    /// Empty before the first reading, and when nothing reaches the threshold.
    public var classifications: [SoundClassification] { state.withLock { $0.classifications } }

    /// The single most confident label right now, whatever the threshold, or
    /// `nil` before the first reading.
    public var topClassification: SoundClassification? { state.withLock { $0.top } }

    /// How sure the phone is about one label right now, `0...1`, and `0` for a
    /// label it has not reported.
    public func confidence(of label: String) -> Double {
        state.withLock { $0.confidences[label] ?? 0 }
    }

    // MARK: The trigger

    /// The sounds that started since the last call, oldest first. Draining, so
    /// each event is handed out once: read it in one place per frame.
    public func events() -> [SoundEvent] {
        state.withLock { state in
            let events = state.pending
            state.pending.removeAll(keepingCapacity: true)
            return events
        }
    }

    /// Seconds since `label` was last heard at or above the threshold, on the
    /// phone's audio clock carried forward. Huge if it never has, so
    /// `timeSinceHearing("clapping") < 0.3` reads as a fading flash.
    public func timeSinceHearing(_ label: String) -> Double {
        let now = Date.timeIntervalSinceReferenceDate
        return state.withLock { state in
            guard let heard = state.lastHeard[label] else { return .greatestFiniteMagnitude }
            let carried = state.arrived.map { max(0, now - $0) } ?? 0
            return max(0, state.elapsed + carried - heard)
        }
    }

    /// The confidence a label must reach to count as heard, `0...1`. Settable
    /// live; it applies from the next reading on.
    public var threshold: Double {
        get { state.withLock { $0.threshold } }
        set { state.withLock { $0.threshold = min(max(newValue, 0), 1) } }
    }

    // MARK: Status

    /// Whether readings are arriving: `true` while the phone's Hear switch is
    /// on and the cable is in, `false` before the first reading and once they
    /// stop. The wire runs one way, so this is read off the readings themselves.
    public var isListening: Bool {
        let now = Date.timeIntervalSinceReferenceDate
        return state.withLock { state in
            guard let arrived = state.arrived else { return false }
            return now - arrived < Self.listeningWindow
        }
    }

    /// How many readings have arrived since the device started. One reading is
    /// one judged window of audio.
    public var readingCount: Int { state.withLock { $0.readings } }

    // MARK: Feeding it

    /// Take one reading, the way the phone sends one: every label with its
    /// confidence, strongest first, for the window of audio starting at `time`
    /// (seconds on the audio clock) and lasting `duration`.
    ///
    /// The device calls this for every reading off the wire. It is public so a
    /// sketch can be developed against staged sounds with no phone attached,
    /// and so a test or a figure can say exactly what was heard and when.
    nonisolated public func hear(_ classifications: [SoundClassification], at time: Double,
                                 duration: Double = 1.5) {
        let ranked = classifications.sorted { $0.confidence > $1.confidence }
        let end = time + max(0, duration)
        let now = Date.timeIntervalSinceReferenceDate
        state.withLock { state in
            state.top = ranked.first
            state.confidences = Dictionary(ranked.map { ($0.label, $0.confidence) },
                                           uniquingKeysWith: { a, _ in a })
            state.classifications = ranked.filter { $0.confidence >= state.threshold }
            state.elapsed = max(state.elapsed, end)
            state.arrived = now
            state.readings += 1

            // A label crossing the threshold from below is a sound starting.
            // Holding the set of what is currently above it is what keeps a
            // long note from firing once per window.
            var above: Set<String> = []
            for entry in ranked where entry.confidence >= state.threshold {
                above.insert(entry.label)
                if !state.above.contains(entry.label) {
                    state.pending.append(SoundEvent(label: entry.label,
                                                    confidence: entry.confidence,
                                                    time: end))
                }
                state.lastHeard[entry.label] = end
            }
            state.above = above
            if state.pending.count > 256 { state.pending.removeFirst(state.pending.count - 256) }
        }
    }

    /// Take one reading off the wire.
    nonisolated func hear(_ sample: PhoneSoundSample) {
        hear(sample.classifications.map {
            SoundClassification(label: $0.label, confidence: Double($0.confidence))
        }, at: sample.timestamp, duration: sample.duration)
    }

    /// Forget everything heard: the levels, the pending events, and the clock.
    /// The threshold stays. The phone keeps sending, so the next reading
    /// starts it again.
    public func reset() {
        state.withLock { state in
            let threshold = state.threshold
            state = State()
            state.threshold = threshold
        }
    }
}
