import Foundation
import Ollin

/// Held notes played one at a time, in an order, against the beat.
///
/// An ``Arpeggio`` is a figure worked out once from a fixed set of notes. An
/// arpeggiator is the live thing: the notes are whatever is held right now,
/// from a keyboard over the wire or from the sketch's own hand, and the
/// figure follows them as they change. Hold a chord and it cycles through the
/// notes; add a note and it joins the ladder on the next pass; let go of
/// everything and it stops, or keeps going if it latches.
///
/// ```swift
/// var arp = Arpeggiator(.upDown, octaves: 2, rate: .sixteenth)
///
/// override func draw() {
///     arp.notes = midi.heldNotes.map { Pitch(Double($0.note)) }
///     let now = tempo.beats(at: time)
///     synth.play(arp.events(upTo: tempo.beats(at: time + deltaTime)), tempo: tempo, from: now)
/// }
/// ```
///
/// Like everything else here it owns no clock: hand it where the music has
/// got to, in beats, and it hands back the notes that fall before that
/// point, each with the beat it lands on.
public struct Arpeggiator: Sendable, Hashable {

    /// The notes held right now, in the order they arrived.
    ///
    /// Set it to the keys a controller reports each frame, or ``hold(_:)``
    /// and ``release(_:)`` one at a time. A new chord after silence starts
    /// the figure again from its first note; a note added or taken away
    /// while the others are still held keeps the figure's place.
    public var notes: [Pitch] {
        didSet {
            guard notes != oldValue, !notes.isEmpty else { return }
            if oldValue.isEmpty { cursor = 0 }
            latched = notes
        }
    }

    /// The order the notes are played in.
    public var pattern: Arpeggio.Pattern

    /// How many octaves the figure climbs before it turns around.
    public var octaves: Int

    /// How long one step lasts, in beats.
    public var rate: NoteLength

    /// How much of a step a note sounds for, as a fraction of the step.
    public var gate: Double

    /// How far the second step of each pair leans late, `0...1`, 0.5 for
    /// straight. The same rule as ``StepSequencer/swing``.
    public var swing: Double

    /// How hard every note is struck, `0...1`.
    public var velocity: Double

    /// Whether letting go of every note keeps the last chord playing.
    ///
    /// Off, silence follows the last release. On, the figure carries on
    /// until a new note is held, which then starts a new chord: the hold
    /// switch on a hardware arpeggiator.
    public var latches: Bool

    /// Which sequence ``Arpeggio/Pattern/random`` picks.
    public var seed: Int

    /// The most steps to hand out for one frame before deciding that time
    /// jumped rather than passed. Sixteen by default; see ``StepCounter``.
    public var maxCatchUp: Int

    /// The last chord held, which is what plays on while latched.
    private var latched: [Pitch]
    /// Which note of the figure comes next.
    private var cursor = 0
    private var counter: StepCounter
    private var rateInUse: Double
    private var lastBeats = 0.0

    /// An arpeggiator, with nothing held yet.
    ///
    /// - Parameters:
    ///   - pattern: the order to play the held notes in.
    ///   - octaves: how many octaves to climb.
    ///   - rate: how long one step lasts.
    ///   - gate: how much of a step a note sounds for.
    ///   - swing: how far the offbeats lean, 0.5 for straight.
    ///   - velocity: how hard every note is struck.
    ///   - latches: whether the last chord plays on after every note is let go.
    ///   - seed: which sequence a random pattern picks.
    public init(
        _ pattern: Arpeggio.Pattern = .up, octaves: Int = 1, rate: NoteLength = .sixteenth, gate: Double = 0.5,
        swing: Double = 0.5, velocity: Double = 0.8, latches: Bool = false, seed: Int = 0
    ) {
        self.notes = []
        self.latched = []
        self.pattern = pattern
        self.octaves = max(1, octaves)
        self.rate = rate
        self.gate = gate
        self.swing = swing
        self.velocity = velocity
        self.latches = latches
        self.seed = seed
        self.maxCatchUp = 16
        self.rateInUse = max(1e-6, rate.beats)
        self.counter = StepCounter(perBeat: 1 / max(1e-6, rate.beats))
    }

    /// An arpeggiator already holding a set of notes.
    public init(
        _ notes: [Pitch], _ pattern: Arpeggio.Pattern = .up, octaves: Int = 1, rate: NoteLength = .sixteenth,
        gate: Double = 0.5, swing: Double = 0.5, velocity: Double = 0.8, latches: Bool = false, seed: Int = 0
    ) {
        self.init(pattern, octaves: octaves, rate: rate, gate: gate, swing: swing, velocity: velocity,
                  latches: latches, seed: seed)
        self.notes = notes
        self.latched = notes
    }

    /// An arpeggiator already holding a chord.
    public init(
        _ chord: Chord, _ pattern: Arpeggio.Pattern = .up, octaves: Int = 1, rate: NoteLength = .sixteenth,
        gate: Double = 0.5, swing: Double = 0.5, velocity: Double = 0.8, latches: Bool = false, seed: Int = 0
    ) {
        self.init(chord.pitches, pattern, octaves: octaves, rate: rate, gate: gate, swing: swing,
                  velocity: velocity, latches: latches, seed: seed)
    }

    // MARK: Holding notes

    /// Holds a note: a key going down. A note already held is left as it is.
    public mutating func hold(_ pitch: Pitch) {
        guard !notes.contains(pitch) else { return }
        notes.append(pitch)
    }

    /// Lets a note go: a key coming up.
    public mutating func release(_ pitch: Pitch) {
        notes.removeAll { $0 == pitch }
    }

    /// The notes the figure is playing right now: what is held, or the last
    /// chord while latched. Empty when it is silent.
    public var playing: [Pitch] {
        notes.isEmpty && latches ? latched : notes
    }

    /// The figure as it stands, worked out from ``playing``, so a sketch can
    /// draw the ladder it is climbing.
    public var figure: Arpeggio {
        Arpeggio(playing, pattern, octaves: octaves, seed: seed)
    }

    /// The note the next step will play, or nil while nothing is held.
    public var next: Pitch? {
        let figure = figure
        guard !figure.spreadPitches.isEmpty else { return nil }
        if pattern == .random { return figure[counter.nextStep] }
        let order = figure.order
        return order[cursor % order.count]
    }

    /// The next step that has not been handed out yet, counted from the
    /// start of the music.
    public var nextStep: Int { counter.nextStep }

    // MARK: Playing it

    /// The notes that fall before `beats`, each with the beat it lands on.
    ///
    /// Empty most frames, and empty while nothing is held, though the count
    /// goes on underneath so the next note lands on the grid. Hand it where
    /// the music will be at the end of the frame and every note comes back
    /// before its time, for `Synth.play(_:tempo:from:)` to land on its sample.
    public mutating func events(upTo beats: Double) -> [ScheduledNote] {
        let rate = max(1e-6, self.rate.beats)
        if rate != rateInUse {
            counter = StepCounter(perBeat: 1 / rate, maxCatchUp: maxCatchUp)
            counter.reset(to: lastBeats)
            rateInUse = rate
        }
        counter.maxCatchUp = maxCatchUp
        lastBeats = max(0, beats)

        let figure = figure
        let order = figure.order
        guard !order.isEmpty, !figure.spreadPitches.isEmpty else {
            _ = counter.steps(upTo: beats)
            return []
        }

        let length = NoteLength(beats: max(1e-6, rate * max(0, gate)))
        var notes = [ScheduledNote]()
        for step in counter.steps(upTo: beats) {
            let pitch: Pitch
            if pattern == .random {
                pitch = figure[step]
            } else {
                pitch = order[cursor % order.count]
                cursor = (cursor + 1) % order.count
            }
            notes.append(ScheduledNote(
                Note(pitch, velocity: velocity, length: length),
                beat: StepTiming.beat(of: step, rate: rate, swing: swing), step: step
            ))
        }
        return notes
    }

    /// Moves the arpeggiator to a position without playing the steps in
    /// between, and starts the figure again from its first note.
    public mutating func reset(to beats: Double = 0) {
        counter.reset(to: beats)
        lastBeats = max(0, beats)
        cursor = 0
    }
}
