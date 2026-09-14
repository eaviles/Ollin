import Foundation
import Ollin

/// A bar of steps, each with its own note, loudness, and chance of playing,
/// read out against the beat.
///
/// The drum machine's grid: sixteen steps to a bar, one note or a rest on
/// each, and the whole thing coming round again. A step can be struck harder
/// or softer than its neighbors, left to chance, or split into a ratchet of
/// repeated strikes, and the bar as a whole can swing.
///
/// ```swift
/// var drums: StepSequencer = "36 . . 36 . . 36 . 38 . . 36 . 38 . ."
/// drums.swing = 0.6
///
/// override func draw() {
///     let now = tempo.beats(at: time)
///     let ahead = tempo.beats(at: time + deltaTime)
///     synth.play(drums.events(upTo: ahead), tempo: tempo, from: now)
/// }
/// ```
///
/// Like everything else here it owns no clock. You hand it where the music
/// has got to, in beats, and it hands back the notes that fall before that
/// point, each with the beat it lands on, so a note a few milliseconds into
/// the next frame is asked for now and played then. A ``StepCounter`` inside
/// does the counting, with the same rules for time that jumps or comes round.
public struct StepSequencer: Sendable, Hashable, CustomStringConvertible {

    /// One step of the bar.
    public struct Step: Sendable, Hashable {
        /// The note, or nil for a rest.
        public var pitch: Pitch?
        /// How hard it is struck, `0...1`.
        public var velocity: Double
        /// The chance it plays when its turn comes, `0...1`. One is always.
        public var probability: Double
        /// How many strikes the step is split into, evenly across its length.
        /// One is the plain step; three or four is the roll a drum machine
        /// calls a ratchet.
        public var ratchet: Int

        public init(_ pitch: Pitch?, velocity: Double = 0.8, probability: Double = 1, ratchet: Int = 1) {
            self.pitch = pitch
            self.velocity = min(max(velocity, 0), 1)
            self.probability = min(max(probability, 0), 1)
            self.ratchet = max(1, ratchet)
        }

        /// A step that plays nothing.
        public static let rest = Step(nil)

        /// Whether the step is silent.
        public var isRest: Bool { pitch == nil }
    }

    /// The bar, one entry per step.
    public var steps: [Step]

    /// How long one step lasts, in beats. A sixteenth is the usual grid.
    public var rate: NoteLength

    /// How far the second step of each pair leans late, `0...1`.
    ///
    /// At 0.5 the steps are straight. At two thirds the offbeats land on the
    /// last triplet of their pair, the classic shuffle, and 0.55 to 0.6 is a
    /// lean you feel more than hear. The first step of a pair never moves.
    public var swing: Double

    /// How much of a step a note sounds for, as a fraction of the step.
    /// Half is short and separate; one runs each note into the next.
    public var gate: Double

    /// Which steps with a chance on them play. The same seed plays the same
    /// bars the same way.
    public var seed: Int

    /// The most steps to hand out for one frame before deciding that time
    /// jumped rather than passed. Sixteen by default; see ``StepCounter``.
    public var maxCatchUp: Int

    private var counter: StepCounter
    private var rateInUse: Double
    private var lastBeats = 0.0

    /// A sequencer over a bar of steps.
    ///
    /// - Parameters:
    ///   - steps: the bar. Sixteen is the usual length; any length cycles.
    ///   - rate: how long one step lasts.
    ///   - swing: how far the offbeats lean, 0.5 for straight.
    ///   - gate: how much of a step a note sounds for.
    ///   - seed: which bars the steps left to chance play on.
    public init(
        steps: [Step], rate: NoteLength = .sixteenth, swing: Double = 0.5, gate: Double = 0.5, seed: Int = 0
    ) {
        self.steps = steps
        self.rate = rate
        self.swing = swing
        self.gate = gate
        self.seed = seed
        self.maxCatchUp = 16
        self.rateInUse = max(1e-6, rate.beats)
        self.counter = StepCounter(perBeat: 1 / max(1e-6, rate.beats))
    }

    /// An empty bar of `count` rests, to fill in.
    public init(count: Int = 16, rate: NoteLength = .sixteenth, swing: Double = 0.5, gate: Double = 0.5, seed: Int = 0) {
        self.init(steps: Array(repeating: .rest, count: max(0, count)), rate: rate, swing: swing, gate: gate, seed: seed)
    }

    /// A bar of notes, nil for a rest, every one struck the same.
    public init(
        _ pitches: [Pitch?], velocity: Double = 0.8, rate: NoteLength = .sixteenth, swing: Double = 0.5,
        gate: Double = 0.5, seed: Int = 0
    ) {
        self.init(steps: pitches.map { Step($0, velocity: velocity) }, rate: rate, swing: swing, gate: gate, seed: seed)
    }

    /// One note on every strike of a rhythm: a drum lane.
    public init(
        _ rhythm: Rhythm, pitch: Pitch, velocity: Double = 0.8, rate: NoteLength = .sixteenth, swing: Double = 0.5,
        gate: Double = 0.5, seed: Int = 0
    ) {
        self.init(
            steps: rhythm.steps.map { $0 ? Step(pitch, velocity: velocity) : .rest },
            rate: rate, swing: swing, gate: gate, seed: seed
        )
    }

    /// A bar written out, one token per step separated by spaces: a note
    /// name (`C3`), a MIDI number (`36`), or `.` for a rest.
    ///
    /// `-` and `_` are rests as well. Returns nil for anything else, which is
    /// what separates this from the literal form.
    public init?(
        pattern: String, velocity: Double = 0.8, rate: NoteLength = .sixteenth, swing: Double = 0.5,
        gate: Double = 0.5, seed: Int = 0
    ) {
        var steps = [Step]()
        for token in pattern.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }) {
            switch token {
            case ".", "-", "_":
                steps.append(.rest)
            default:
                if let midi = Int(token) {
                    steps.append(Step(Pitch(Double(midi)), velocity: velocity))
                } else if let pitch = Pitch(name: String(token)) {
                    steps.append(Step(pitch, velocity: velocity))
                } else {
                    return nil
                }
            }
        }
        self.init(steps: steps, rate: rate, swing: swing, gate: gate, seed: seed)
    }

    // MARK: Reading it

    /// The step at a position. The bar repeats, so the number can be any
    /// step the music has reached; setting through it writes the step in the
    /// bar that position falls on.
    public subscript(step: Int) -> Step {
        get {
            guard !steps.isEmpty else { return .rest }
            return steps[((step % steps.count) + steps.count) % steps.count]
        }
        set {
            guard !steps.isEmpty else { return }
            steps[((step % steps.count) + steps.count) % steps.count] = newValue
        }
    }

    /// How many steps go by before the bar comes round again.
    public var length: Int { steps.count }

    /// The next step that has not been handed out yet, counted from the
    /// start of the music. `nextStep % length` is where the playhead is.
    public var nextStep: Int { counter.nextStep }

    /// The bar written out the way ``init(pattern:velocity:rate:swing:gate:seed:)``
    /// reads it: note names, `.` for a rest.
    public var description: String {
        steps.map { $0.pitch.map { "\($0)" } ?? "." }.joined(separator: " ")
    }

    // MARK: Playing it

    /// The notes that fall before `beats`, each with the beat it lands on.
    ///
    /// Empty most frames. Hand it where the music will be at the end of the
    /// frame and every note comes back before its time, so `Synth.play(_:tempo:from:)`
    /// can land each one on its own sample. A swung offbeat, a ratchet's later
    /// strikes, and a note that plays this time or not are all decided here.
    public mutating func events(upTo beats: Double) -> [ScheduledNote] {
        let rate = max(1e-6, self.rate.beats)
        if rate != rateInUse {
            // A new rate starts counting again from where the music is, so
            // changing it mid-bar neither replays a stretch nor skips one.
            counter = StepCounter(perBeat: 1 / rate, maxCatchUp: maxCatchUp)
            counter.reset(to: lastBeats)
            rateInUse = rate
        }
        counter.maxCatchUp = maxCatchUp
        lastBeats = max(0, beats)
        guard !steps.isEmpty else {
            _ = counter.steps(upTo: beats)
            return []
        }

        var notes = [ScheduledNote]()
        for step in counter.steps(upTo: beats) {
            let entry = self[step]
            guard let pitch = entry.pitch,
                  StepTiming.plays(step: step, seed: seed, probability: entry.probability)
            else { continue }

            let onset = StepTiming.beat(of: step, rate: rate, swing: swing)
            let strikes = max(1, entry.ratchet)
            let spacing = rate / Double(strikes)
            let length = NoteLength(beats: max(1e-6, spacing * max(0, gate)))
            for strike in 0..<strikes {
                notes.append(ScheduledNote(
                    Note(pitch, velocity: entry.velocity, length: length),
                    beat: onset + Double(strike) * spacing, step: step
                ))
            }
        }
        return notes
    }

    /// Moves the sequencer to a position without playing the steps in between.
    public mutating func reset(to beats: Double = 0) {
        counter.reset(to: beats)
        lastBeats = max(0, beats)
    }
}

extension StepSequencer: ExpressibleByStringLiteral {
    /// `let bass: StepSequencer = "A1 . . A1 . . C2 ."` reads the string as a
    /// bar of sixteenths.
    ///
    /// A literal cannot fail, so a token that is not a note or a rest leaves
    /// an empty bar and says so once, rather than stopping the sketch
    /// mid-performance. Use ``init(pattern:velocity:rate:swing:gate:seed:)``
    /// where you want to be told in code instead.
    public init(stringLiteral value: String) {
        if let sequencer = StepSequencer(pattern: value) {
            self = sequencer
        } else {
            audioNoteOnce("\"\(value)\" is not a bar (try \"C3 . E3 . G3 . B3 .\"); using an empty one.")
            self.init(steps: [])
        }
    }
}
