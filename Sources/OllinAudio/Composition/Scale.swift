import Foundation
import Ollin

/// A set of pitches to choose from, and a root they are measured from.
///
/// A scale turns whole numbers into notes, which is what makes generated music
/// sound like music: pick a number any way you like and the scale keeps it in
/// key.
///
/// ```swift
/// let scale = Scale(.minorPentatonic, root: "A3")
/// synth.play(scale[step])          // 0 is the root, 5 is an octave up
/// ```
///
/// Degrees run in both directions and past the ends. Degree 0 is the root, and
/// for a five note scale degree 5 is the root an octave higher, degree -1 the
/// note below it. So a wandering number never leaves the key, however far it
/// wanders.
///
/// Where a pitch has already been decided by something else, a picture or a
/// sensor, ``snap(_:)`` moves it to the nearest note of the scale instead.
public struct Scale: Sendable, Hashable {

    /// The note the scale is measured from, and the pitch of degree 0.
    public var root: Pitch

    /// The scale's notes as semitones above the root, ascending, starting at 0.
    public private(set) var intervals: [Int]

    /// A named scale on a root.
    public init(_ mode: Mode = .major, root: Pitch = "C4") {
        self.root = root
        self.intervals = mode.intervals
    }

    /// A scale of your own, as semitones above the root.
    ///
    /// The values are taken within one octave, sorted, and duplicates dropped,
    /// so `[0, 4, 7]` and `[7, 0, 16, 4]` describe the same three note scale.
    public init(intervals: [Int], root: Pitch = "C4") {
        self.root = root
        let folded = Set(intervals.map { (($0 % 12) + 12) % 12 }).sorted()
        self.intervals = folded.isEmpty ? [0] : folded
    }

    // MARK: Reading it

    /// How many notes there are before the scale repeats an octave up.
    public var degreeCount: Int { intervals.count }

    /// The pitch of a degree, where 0 is the root.
    ///
    /// Degrees past the end of the scale carry on into the next octave, and
    /// negative degrees run down into the one below, so this never fails and
    /// never needs a number kept in range.
    public subscript(degree: Int) -> Pitch { pitch(degree) }

    /// The pitch of a degree, the long way of writing the subscript.
    public func pitch(_ degree: Int) -> Pitch {
        let size = intervals.count
        let octave = Int((Double(degree) / Double(size)).rounded(.down))
        let index = degree - octave * size
        return Pitch(root.midi + Double(12 * octave + intervals[index]))
    }

    /// A run of pitches, starting from a degree.
    public func pitches(_ count: Int, from degree: Int = 0) -> [Pitch] {
        guard count > 0 else { return [] }
        return (0..<count).map { pitch(degree + $0) }
    }

    /// Whether a pitch is one of the scale's notes, whatever octave it is in.
    public func contains(_ pitch: Pitch) -> Bool {
        let offset = pitch.midi - root.midi
        let within = offset - 12 * (offset / 12).rounded(.down)
        return intervals.contains { abs(Double($0) - within) < 1e-6 }
    }

    /// The scale note nearest a pitch.
    ///
    /// This is how something that was not written as music, a mouse position or
    /// a measurement, joins the key. A pitch exactly between two notes moves to
    /// the lower one.
    public func snap(_ pitch: Pitch) -> Pitch {
        let offset = pitch.midi - root.midi
        let octave = (offset / 12).rounded(.down)
        let within = offset - 12 * octave

        // The octave above has to be a candidate too: a pitch just under the
        // root of the next octave is nearer to it than to the scale's top note.
        var best = Double(intervals[0])
        var bestDistance = Double.infinity
        for interval in intervals + [intervals[0] + 12] {
            let distance = abs(Double(interval) - within)
            if distance < bestDistance {
                bestDistance = distance
                best = Double(interval)
            }
        }
        return Pitch(root.midi + 12 * octave + best)
    }

    /// The degree nearest a pitch, the number that ``pitch(_:)`` would turn
    /// back into it.
    public func degree(nearest pitch: Pitch) -> Int {
        let snapped = snap(pitch)
        let offset = snapped.midi - root.midi
        let octave = Int((offset / 12).rounded(.down))
        let within = Int((offset - 12 * Double(octave)).rounded())
        let index = intervals.firstIndex { $0 == within % 12 } ?? 0
        return octave * intervals.count + index
    }

    /// A chord built on a degree by stacking notes from the scale itself.
    ///
    /// Taking every other note of the scale is how chords are built from a key,
    /// and it is why the same move sounds major on one degree and minor on
    /// another: the quality falls out of where in the scale you started rather
    /// than being chosen.
    ///
    /// - Parameters:
    ///   - degree: the degree the chord is built on.
    ///   - noteCount: how many notes to stack. Three is a triad, four adds a
    ///     seventh.
    ///   - spacing: how many degrees to skip between them. Two takes every
    ///     other note, which is the usual one.
    public func chord(on degree: Int, noteCount: Int = 3, spacing: Int = 2) -> [Pitch] {
        guard noteCount > 0 else { return [] }
        return (0..<noteCount).map { pitch(degree + $0 * spacing) }
    }

    /// The same scale moved by a number of semitones.
    public func transposed(by semitones: Double) -> Scale {
        var moved = self
        moved.root = root.transposed(by: semitones)
        return moved
    }

    // MARK: - Named scales

    /// The scales worth having by name.
    ///
    /// The seven church modes come first, and they are all the same seven notes
    /// started in different places: `.major` and `.minor` are the two everyone
    /// knows, and the others sit between them, each with one note moved. The
    /// pentatonics drop the two notes that can clash, which is why nearly
    /// anything played on them sounds intentional.
    public enum Mode: String, Sendable, Hashable, Codable, CaseIterable {
        /// The bright one. Also called ionian.
        case major
        /// Minor with a raised sixth, so it is sad without being heavy.
        case dorian
        /// Minor with a lowered second, the flamenco color.
        case phrygian
        /// Major with a raised fourth, floating and unresolved.
        case lydian
        /// Major with a lowered seventh, the one that sounds like a blues band.
        case mixolydian
        /// The dark one. Also called aeolian, or the natural minor.
        case minor
        /// Unstable in a way nothing else here is, because its fifth is flat.
        case locrian
        /// Minor with the seventh raised back up, which pulls hard to the root.
        case harmonicMinor
        /// Minor going up, major coming down, written here as the ascending form.
        case melodicMinor
        /// Five notes of the major scale, with the two that can clash removed.
        case majorPentatonic
        /// Five notes of the minor scale, the same removal.
        case minorPentatonic
        /// The minor pentatonic with the flattened fifth put back between.
        case blues
        /// Six notes evenly spaced, so it has no root of its own to return to.
        case wholeTone
        /// Alternating whole and half steps, the sound of things going wrong.
        case octatonic
        /// Every note. Nothing is out of key, which is also the problem.
        case chromatic
        /// A five note Japanese scale, dark and open.
        case hirajoshi
        /// Another, with the second lowered and the third missing.
        case inSen
        /// A third, built entirely of half steps and minor thirds.
        case iwato

        /// The scale's notes as semitones above its root.
        public var intervals: [Int] {
            switch self {
            case .major:           return [0, 2, 4, 5, 7, 9, 11]
            case .dorian:          return [0, 2, 3, 5, 7, 9, 10]
            case .phrygian:        return [0, 1, 3, 5, 7, 8, 10]
            case .lydian:          return [0, 2, 4, 6, 7, 9, 11]
            case .mixolydian:      return [0, 2, 4, 5, 7, 9, 10]
            case .minor:           return [0, 2, 3, 5, 7, 8, 10]
            case .locrian:         return [0, 1, 3, 5, 6, 8, 10]
            case .harmonicMinor:   return [0, 2, 3, 5, 7, 8, 11]
            case .melodicMinor:    return [0, 2, 3, 5, 7, 9, 11]
            case .majorPentatonic: return [0, 2, 4, 7, 9]
            case .minorPentatonic: return [0, 3, 5, 7, 10]
            case .blues:           return [0, 3, 5, 6, 7, 10]
            case .wholeTone:       return [0, 2, 4, 6, 8, 10]
            case .octatonic:       return [0, 2, 3, 5, 6, 8, 9, 11]
            case .chromatic:       return Array(0..<12)
            case .hirajoshi:       return [0, 2, 3, 7, 8]
            case .inSen:           return [0, 1, 5, 7, 10]
            case .iwato:           return [0, 1, 5, 6, 10]
            }
        }
    }
}

/// So a scale can be picked from a menu while the sketch runs.
extension Scale.Mode: ParamOption {}
