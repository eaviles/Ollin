import Foundation

/// A cycle of chords, built out of a key.
///
/// A progression is written as scale degrees rather than as chord names,
/// because that is the fact that survives changing key. `I vi IV V` is the same
/// progression in every key there is, and naming it that way means the chords'
/// qualities fall out of the scale instead of having to be said.
///
/// ```swift
/// let changes = Progression("I vi IV V", in: Scale(.major, root: "C3"))
///
/// override func draw() {
///     for step in counter.steps(upTo: time * 2) {
///         synth.play(chord: changes.pitches(at: step), for: 1.8)
///     }
/// }
/// ```
///
/// Like everything else in this tier it answers a step number and owns no
/// clock, and the cycle wraps, so a step number can climb forever.
public struct Progression: Sendable, Hashable {

    /// The scale degrees the chords are built on, in order. Degree 0 is the
    /// chord on the key's own root.
    public private(set) var degrees: [Int]

    /// The key the chords are built out of.
    public var scale: Scale

    /// How many notes each chord has. Three is triads, four is sevenths.
    public var notes: Int

    /// How far apart the stacked notes are, in scale degrees. Two is the usual
    /// stack of thirds; three gives the open, fourth-stacked sound.
    public var spacing: Int

    /// Chords named outright rather than built from a key.
    ///
    /// A progression is degrees in a key by default, because that is the fact
    /// that survives changing key. Written as chord symbols instead, the
    /// chords carry their own qualities and this holds them; the degrees are
    /// then unused.
    public internal(set) var written: [Chord]?

    // MARK: Making one

    /// A progression from scale degrees you have already worked out.
    public init(_ degrees: [Int], in scale: Scale, notes: Int = 3, spacing: Int = 2) {
        self.degrees = degrees.isEmpty ? [0] : degrees
        self.scale = scale
        self.notes = max(1, notes)
        self.spacing = max(1, spacing)
    }

    /// A progression written the way progressions are usually written.
    ///
    /// ```swift
    /// Progression("I vi IV V", in: key)
    /// Progression("i - VII - VI - V", in: minorKey)
    /// ```
    ///
    /// Roman numerals `I` to `VII`, separated by spaces or anything that is not
    /// a numeral. Case is accepted and ignored: whether a chord comes out major
    /// or minor is decided by the key it is built from, which is the whole
    /// reason to write a progression this way. Anything unreadable is skipped,
    /// and a line with nothing readable in it gives the key's own chord.
    public init(_ text: String, in scale: Scale, notes: Int = 3, spacing: Int = 2) {
        self.init(Progression.parse(text), in: scale, notes: notes, spacing: spacing)
    }

    // MARK: Reading it

    /// How many chords there are before it repeats.
    public var count: Int { written?.count ?? degrees.count }

    /// The chord at a step. The cycle wraps, so any step number works.
    public subscript(step: Int) -> [Pitch] { pitches(at: step) }

    /// The notes of the chord at a step, lowest first.
    public func pitches(at step: Int) -> [Pitch] {
        if let chord = chord(at: step) { return chord.pitches }
        return scale.chord(on: degree(at: step), notes: notes, spacing: spacing)
    }

    /// The chord at a step, for a progression written as chord symbols. Nil
    /// for one written as degrees, whose chords come out of the key instead.
    public func chord(at step: Int) -> Chord? {
        guard let written, !written.isEmpty else { return nil }
        return written[((step % written.count) + written.count) % written.count]
    }

    /// The scale degree the chord at a step is built on.
    public func degree(at step: Int) -> Int {
        guard !degrees.isEmpty else { return 0 }
        let index = ((step % degrees.count) + degrees.count) % degrees.count
        return degrees[index]
    }

    /// The root of the chord at a step, for a bass line under the chords.
    public func root(at step: Int) -> Pitch {
        chord(at: step)?.root ?? scale[degree(at: step)]
    }

    // MARK: Changing it

    /// The same progression in another key.
    public func transposed(by semitones: Double) -> Progression {
        var moved = self
        moved.scale = scale.transposed(by: semitones)
        moved.written = written?.map { $0.transposed(by: semitones) }
        return moved
    }

    /// The same chords starting somewhere else in the cycle.
    public func rotated(by amount: Int) -> Progression {
        if let written, !written.isEmpty {
            let shift = ((amount % written.count) + written.count) % written.count
            var moved = self
            moved.written = Array(written[shift...] + written[..<shift])
            return moved
        }
        guard !degrees.isEmpty else { return self }
        let shift = ((amount % degrees.count) + degrees.count) % degrees.count
        var moved = self
        moved.degrees = Array(degrees[shift...] + degrees[..<shift])
        return moved
    }

    /// A longer progression that wanders, learned from this one.
    ///
    /// The chords this progression already moves between become the moves a new
    /// one is allowed to make, so what comes out belongs to the same music
    /// without being the same cycle. Two bars in, it is somewhere the original
    /// never went, but it got there by steps the original took.
    ///
    /// ```swift
    /// let changes = Progression("I vi IV V ii V", in: key).wandering(32)
    /// ```
    ///
    /// Seeded per call rather than from the sketch's randomness, so a
    /// progression a sketch likes can be asked for again and be the same one.
    ///
    /// - Parameters:
    ///   - length: how many chords to produce.
    ///   - order: how far back it looks when deciding. One follows single
    ///     moves; two keeps closer to the original's phrasing.
    ///   - seed: which wander. The same seed gives the same chords.
    public func wandering(_ length: Int, order: Int = 1, seed: Int = 0) -> Progression {
        guard length > 0, degrees.count > 1 else { return self }
        // Learned round the loop rather than off the end, because the last
        // chord moving back to the first is a move the progression makes.
        var chain = MarkovChain(learning: degrees, order: order, seed: seed, loops: true)

        var wandered: [Int] = []
        wandered.reserveCapacity(length)
        for _ in 0..<length {
            wandered.append(chain.next() ?? degrees[0])
        }
        var moved = self
        moved.degrees = wandered
        return moved
    }

    // MARK: Reading roman numerals

    /// The degrees a written progression names, zero based.
    ///
    /// Walked one character at a time rather than split on spaces, so `I-vi-IV`
    /// and `I vi IV` and `I, vi, IV` all read the same: anything that is not a
    /// numeral simply ends the one being read.
    static func parse(_ text: String) -> [Int] {
        var degrees: [Int] = []
        var current = ""
        func flush() {
            defer { current = "" }
            guard !current.isEmpty, let degree = numeral(current) else { return }
            degrees.append(degree)
        }
        for character in text {
            if "IViv".contains(character) {
                current.append(character)
            } else {
                flush()
            }
        }
        flush()
        return degrees
    }

    /// One numeral as a zero based scale degree, or nil.
    private static func numeral(_ text: String) -> Int? {
        switch text.uppercased() {
        case "I":   return 0
        case "II":  return 1
        case "III": return 2
        case "IV":  return 3
        case "V":   return 4
        case "VI":  return 5
        case "VII": return 6
        default:    return nil
        }
    }
}

// MARK: - Named progressions

public extension Progression {
    /// Four chords a great deal of popular music is made of.
    static func pop(in scale: Scale) -> Progression {
        Progression([0, 4, 5, 3], in: scale)
    }

    /// The one every doo-wop record is built on.
    static func fifties(in scale: Scale) -> Progression {
        Progression([0, 5, 3, 4], in: scale)
    }

    /// Two chords leaning on each other and resolving, the commonest move in
    /// tonal music and most of what jazz is holding together.
    static func twoFiveOne(in scale: Scale) -> Progression {
        Progression([1, 4, 0], in: scale, notes: 4)
    }

    /// A twelve bar blues, one chord per bar.
    static func blues(in scale: Scale) -> Progression {
        Progression([0, 0, 0, 0, 3, 3, 0, 0, 4, 3, 0, 4], in: scale, notes: 4)
    }

    /// The descending line heard through flamenco and a great deal else.
    static func andalusian(in scale: Scale) -> Progression {
        Progression([0, 6, 5, 4], in: scale)
    }

    /// A circle of falling fifths, which is the strongest way to move a long
    /// way and still sound as though it had to happen.
    static func circleOfFifths(in scale: Scale) -> Progression {
        Progression([0, 3, 6, 2, 5, 1, 4, 0], in: scale, notes: 4)
    }
}
