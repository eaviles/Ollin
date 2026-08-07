import Foundation
import Ollin

/// A chord played one note at a time, in an order.
///
/// ```swift
/// let arp = Arpeggio(Chord("A3", .minorSeventh), .upDown, octaves: 2)
/// synth.play(arp[step], for: 0.1)
/// ```
///
/// Like ``Rhythm``, an arpeggio answers a step number and wraps, so the step
/// can climb forever. Nothing about it moves on its own.
///
/// The whole cycle is worked out once when the arpeggio is made, and ``order``
/// hands it back, so a sketch can draw the figure it is about to play.
public struct Arpeggio: Sendable, Hashable {

    /// The notes to play, as given.
    public let pitches: [Pitch]

    /// The order they are played in.
    public let pattern: Pattern

    /// How many octaves the figure climbs before it turns around.
    public let octaves: Int

    /// Which sequence ``Pattern/random`` picks. The same seed always picks the
    /// same notes in the same order.
    public let seed: Int

    /// The notes spread over the octaves the arpeggio covers, lowest first.
    public let notes: [Pitch]

    /// One full pass, in playing order.
    ///
    /// For ``Pattern/random`` there is no fixed pass, so this is the pool of
    /// notes it draws from rather than the order they will come out in.
    public let order: [Pitch]

    /// An arpeggio over a set of notes.
    ///
    /// - Parameters:
    ///   - pitches: the notes to play. Any set will do; a chord's usually.
    ///   - pattern: the order to play them in.
    ///   - octaves: how many octaves to climb. Two is the usual reach.
    ///   - seed: which sequence a random pattern picks.
    public init(_ pitches: [Pitch], _ pattern: Pattern = .up, octaves: Int = 1, seed: Int = 0) {
        self.pitches = pitches
        self.pattern = pattern
        self.octaves = max(1, octaves)
        self.seed = seed

        // `asPlayed` is the one pattern that keeps the notes in the order they
        // arrived; every other one is defined against the ladder, so the ladder
        // is sorted before the octaves are stacked on it.
        let single = pattern == .asPlayed ? pitches : pitches.sorted()
        self.notes = (0..<max(1, octaves)).flatMap { octave in
            single.map { $0.transposed(by: Double(12 * octave)) }
        }
        self.order = Arpeggio.order(of: notes, pattern: pattern)
    }

    /// An arpeggio over a chord's notes.
    public init(_ chord: Chord, _ pattern: Pattern = .up, octaves: Int = 1, seed: Int = 0) {
        self.init(chord.pitches, pattern, octaves: octaves, seed: seed)
    }

    /// The note at a step. The figure repeats, so the step can be any number.
    public subscript(step: Int) -> Pitch {
        guard !notes.isEmpty else { return Pitch(60) }
        if pattern == .random {
            return notes[Arpeggio.draw(step: step, seed: seed, count: notes.count)]
        }
        guard !order.isEmpty else { return notes[0] }
        return order[((step % order.count) + order.count) % order.count]
    }

    /// How many steps go by before the figure comes round again.
    ///
    /// A random arpeggio never does come round, so this reports how many notes
    /// it is drawing from instead.
    public var length: Int { max(1, order.count) }

    /// The orders a chord's notes can be played in.
    public enum Pattern: String, Sendable, Hashable, Codable, CaseIterable {
        /// Lowest to highest, then round again from the bottom.
        case up
        /// Highest to lowest.
        case down
        /// Up and back down, without playing either end twice in a row.
        case upDown
        /// Down and back up, the same way.
        case downUp
        /// In the order the notes were given, which is the only way to hear a
        /// voicing you arranged by hand.
        case asPlayed
        /// From the outside in: lowest, highest, second lowest, and so on.
        case converge
        /// From the inside out, which is the same order backwards.
        case diverge
        /// A note at a time, drawn from the whole set. Seeded, so it repeats.
        case random
    }

    // MARK: Working out the order

    private static func order(of notes: [Pitch], pattern: Pattern) -> [Pitch] {
        guard notes.count > 1 else { return notes }
        switch pattern {
        case .up, .asPlayed:
            return notes
        case .down:
            return notes.reversed()
        case .upDown:
            // Dropping both ends of the way back is what keeps the turnaround
            // from sounding like a stutter: the top note is played once, not
            // twice in a row.
            return notes + notes.dropFirst().dropLast().reversed()
        case .downUp:
            let down = Array(notes.reversed())
            return down + down.dropFirst().dropLast().reversed()
        case .converge:
            return converged(notes)
        case .diverge:
            return converged(notes).reversed()
        case .random:
            return notes
        }
    }

    private static func converged(_ notes: [Pitch]) -> [Pitch] {
        var result = [Pitch]()
        result.reserveCapacity(notes.count)
        var low = 0
        var high = notes.count - 1
        while low <= high {
            result.append(notes[low])
            if low != high { result.append(notes[high]) }
            low += 1
            high -= 1
        }
        return result
    }

    /// Picks a note for a step.
    ///
    /// A pure function of the step and the seed rather than a running
    /// generator, so the same step always gives the same note however a sketch
    /// jumps around, and adding an arpeggio never shifts anything else the
    /// sketch was drawing at random.
    private static func draw(step: Int, seed: Int, count: Int) -> Int {
        var z = UInt64(bitPattern: Int64(step)) &* 0x9E37_79B9_7F4A_7C15
        z ^= UInt64(bitPattern: Int64(seed)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Int(z % UInt64(count))
    }
}

/// So a figure's shape can be picked from a menu while the sketch runs.
extension Arpeggio.Pattern: ParamOption {}
