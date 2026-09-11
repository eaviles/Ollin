import Foundation
import Ollin

/// Several notes meant to sound together.
///
/// ```swift
/// let chord = Chord("C4", .minorSeventh)
/// synth.play(chord: chord.pitches, for: 2)
/// ```
///
/// A chord is a root and a shape stacked on it, so moving one is a matter of
/// moving its root and nothing else. ``Scale/chord(on:noteCount:spacing:)`` is the
/// other way to arrive at one: build it out of a key rather than name it, and
/// the quality comes out of where in the scale you started.
public struct Chord: Sendable, Hashable {

    /// The note the chord is built on and named after.
    public var root: Pitch

    /// The shape stacked on the root.
    public var quality: Quality

    /// How many of the lowest notes have been lifted an octave.
    ///
    /// Inverting a chord changes which note is at the bottom without changing
    /// which notes are in it, which is how one chord moves to the next without
    /// every part leaping. Turning it all the way round is the same chord an
    /// octave higher, and a negative inversion drops notes from the top down
    /// instead, which is how a close voicing is opened out.
    public var inversion: Int

    public init(_ root: Pitch, _ quality: Quality = .major, inversion: Int = 0) {
        self.root = root
        self.quality = quality
        self.inversion = inversion
    }

    /// The chord's notes, lowest first.
    public var pitches: [Pitch] {
        let intervals = quality.intervals
        guard !intervals.isEmpty else { return [] }
        // Every full turn is an octave, so the count and the leftover are kept
        // apart: inverting a four note chord four times has to arrive an octave
        // up rather than back where it started.
        let octaves = Int((Double(inversion) / Double(intervals.count)).rounded(.down))
        let turns = inversion - octaves * intervals.count
        return intervals.enumerated()
            .map { index, interval in
                Pitch(root.midi + Double(interval + 12 * (octaves + (index < turns ? 1 : 0))))
            }
            .sorted()
    }

    /// The same chord with `count` more of its notes lifted an octave.
    public func inverted(_ count: Int = 1) -> Chord {
        Chord(root, quality, inversion: inversion + count)
    }

    /// The same chord moved by a number of semitones.
    public func transposed(by semitones: Double) -> Chord {
        Chord(root.transposed(by: semitones), quality, inversion: inversion)
    }

    /// The chord's notes spread over several octaves, lowest first.
    ///
    /// A chord played inside a single octave is dense in a way that reads as
    /// crowded rather than rich. Spreading it is what an arranger does instead.
    public func spread(over octaves: Int = 2) -> [Pitch] {
        let notes = pitches
        guard !notes.isEmpty, octaves > 1 else { return notes }
        return (0..<octaves)
            .flatMap { octave in notes.map { $0.transposed(by: Double(12 * octave)) } }
            .sorted()
    }

    /// The shape a chord stacks on its root, as semitones above it.
    public enum Quality: String, Sendable, Hashable, Codable, CaseIterable {
        /// Root, major third, fifth. The plain one.
        case major
        /// Root, minor third, fifth. The plain sad one.
        case minor
        /// Both upper notes lowered, so nothing in it is settled.
        case diminished
        /// The fifth raised, which leaves it hanging.
        case augmented
        /// The third replaced by the note below it, neither major nor minor.
        case sus2
        /// The third replaced by the note above it, the same open quality.
        case sus4
        /// Root and fifth only, with no third to say major or minor.
        case fifth
        /// A major chord with a sixth added, bright and slightly old fashioned.
        case sixth
        /// The same addition on a minor chord.
        case minorSixth
        /// Major with a lowered seventh, the chord that wants to go somewhere.
        case dominantSeventh
        /// Major with the seventh left high, soft and unhurried.
        case majorSeventh
        /// Minor with a lowered seventh, the most usable four note chord here.
        case minorSeventh
        /// Minor with the seventh left high, and uneasy for it.
        case minorMajorSeventh
        /// A diminished triad with a lowered seventh on top.
        case halfDiminishedSeventh
        /// Minor thirds all the way up, so it sounds the same inverted.
        case diminishedSeventh
        /// A major chord with the ninth added and no seventh.
        case addNine
        /// A dominant seventh carried up to the ninth.
        case ninth
        /// The same reach on a major seventh.
        case majorNinth
        /// And on a minor seventh.
        case minorNinth
        /// Carried up one further.
        case eleventh
        /// And one further again, which is most of a scale at once.
        case thirteenth

        /// The chord's notes as semitones above its root.
        public var intervals: [Int] {
            switch self {
            case .major:                 return [0, 4, 7]
            case .minor:                 return [0, 3, 7]
            case .diminished:            return [0, 3, 6]
            case .augmented:             return [0, 4, 8]
            case .sus2:                  return [0, 2, 7]
            case .sus4:                  return [0, 5, 7]
            case .fifth:                 return [0, 7]
            case .sixth:                 return [0, 4, 7, 9]
            case .minorSixth:            return [0, 3, 7, 9]
            case .dominantSeventh:       return [0, 4, 7, 10]
            case .majorSeventh:          return [0, 4, 7, 11]
            case .minorSeventh:          return [0, 3, 7, 10]
            case .minorMajorSeventh:     return [0, 3, 7, 11]
            case .halfDiminishedSeventh: return [0, 3, 6, 10]
            case .diminishedSeventh:     return [0, 3, 6, 9]
            case .addNine:               return [0, 4, 7, 14]
            case .ninth:                 return [0, 4, 7, 10, 14]
            case .majorNinth:            return [0, 4, 7, 11, 14]
            case .minorNinth:            return [0, 3, 7, 10, 14]
            case .eleventh:              return [0, 4, 7, 10, 14, 17]
            case .thirteenth:            return [0, 4, 7, 10, 14, 21]
            }
        }
    }
}

/// So a chord's shape can be picked from a menu while the sketch runs.
extension Chord.Quality: ParamOption {}
