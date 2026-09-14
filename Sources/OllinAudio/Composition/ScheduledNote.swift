import Foundation
import Ollin

/// A note and the beat it lands on.
///
/// What a ``StepSequencer`` or an ``Arpeggiator`` hands back for a frame: a
/// ``Note``, with its pitch, loudness, and length, and the beat it belongs on.
/// Beats rather than seconds, because nothing in this tier knows how fast the
/// music is going. The synth joins the tempo when it plays them, and turns
/// the beat into a wait, so a note a few milliseconds after its neighbor lands
/// a few milliseconds after it rather than on the same frame:
///
/// ```swift
/// let now = tempo.beats(at: time)
/// let ahead = tempo.beats(at: time + deltaTime)
/// synth.play(sequencer.events(upTo: ahead), tempo: tempo, from: now)
/// ```
public struct ScheduledNote: Sendable, Hashable {
    /// The note itself: pitch, loudness, and length in beats.
    public var note: Note
    /// Where it lands, in beats from the start of the music.
    public var beat: Double
    /// The step of the pattern that asked for it. The strikes of a ratchet
    /// share one.
    public var step: Int

    public init(_ note: Note, beat: Double, step: Int) {
        self.note = note
        self.beat = beat
        self.step = step
    }

    /// Which note.
    public var pitch: Pitch { note.pitch }
    /// How hard it is struck, `0...1`.
    public var velocity: Double { note.velocity }
    /// How long it lasts, in beats.
    public var length: NoteLength { note.length }
}

extension Synth {
    /// Plays what a sequencer or an arpeggiator handed back, each note on its
    /// beat.
    ///
    /// Ask the pattern for the notes up to where the music will be at the end
    /// of this frame, and hand them over with where it is now. A note whose
    /// beat is still ahead then waits for it, to the sample; one already past
    /// plays at once. Leave `from:` out and every note plays with the frame
    /// that asked, where a note with no wait lands, which is fine for a
    /// pattern with no swing in it.
    ///
    /// - Parameters:
    ///   - notes: the notes, each with the beat it lands on.
    ///   - tempo: how fast the music is going, which turns a beat into
    ///     seconds. A plain number is beats per minute.
    ///   - beats: where the music is now, in beats. The same clock the
    ///     notes were asked against.
    public func play(_ notes: [ScheduledNote], tempo: Tempo = 120, from beats: Double? = nil) {
        for scheduled in notes {
            let wait = beats.map { tempo.seconds(beats: scheduled.beat - $0) } ?? 0
            play(scheduled.pitch, velocity: scheduled.velocity,
                 for: scheduled.length.seconds(at: tempo), after: max(0, wait))
        }
    }
}

/// The timing rules the sequencer and the arpeggiator share.
enum StepTiming {

    /// Where a step lands, in beats.
    ///
    /// Every step has a straight place, `step * rate`. Swing moves the second
    /// step of each pair later, by how far past the middle of the pair the
    /// swing puts it: at 0.5 it stays where it was, at two thirds it lands on
    /// the last triplet of the pair, the shuffle a drummer plays without
    /// thinking about it. The first step of a pair never moves, so the
    /// downbeats keep the grid however hard the pattern leans.
    static func beat(of step: Int, rate: Double, swing: Double) -> Double {
        let straight = Double(step) * rate
        guard step & 1 == 1 else { return straight }
        let lean = min(max(swing, 0), 1)
        return straight + (2 * lean - 1) * rate
    }

    /// Whether a step with a chance on it plays this time round.
    ///
    /// A pure function of the step and the seed rather than a running
    /// generator, so a bar replays the same way when the music comes round
    /// to it again, and a pattern that leaves some strikes to chance never
    /// shifts anything else the sketch draws at random.
    static func plays(step: Int, seed: Int, probability: Double) -> Bool {
        guard probability < 1 else { return true }
        guard probability > 0 else { return false }
        var z = UInt64(bitPattern: Int64(step)) &* 0x9E37_79B9_7F4A_7C15
        z ^= UInt64(bitPattern: Int64(seed)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        // The top 53 bits, so the fraction is exact and evenly spread.
        let fraction = Double(z >> 11) / Double(1 << 53)
        return fraction < probability
    }
}
