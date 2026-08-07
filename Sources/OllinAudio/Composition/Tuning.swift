import Foundation

/// A set of pitches described by ratios rather than by semitones.
///
/// ``Scale`` divides the octave into twelve, because almost all the music a
/// sketch is likely to make does. A `Tuning` does not assume that. It is a list
/// of frequency ratios and the interval they repeat over, which covers the
/// twelve equal steps as one case among many.
///
/// ```swift
/// let tuning = Tuning.just                    // whole number ratios
/// synth.play(tuning[degree])
/// ```
///
/// It has the same shape as a `Scale`, so a sketch that indexes degrees and
/// snaps stray pitches works the same way with either.
///
/// The reason to reach for it is that equal temperament is a compromise: it
/// makes every key equally usable by making every interval except the octave
/// slightly wrong. A drone piece that never changes key gives up nothing by
/// being tuned in whole number ratios, and gets back intervals that lock
/// together instead of beating.
public struct Tuning: Sendable, Hashable {

    /// The pitches of one period, as frequency ratios above the root, starting
    /// at 1. Sorted, deduplicated, and folded into one period.
    public private(set) var ratios: [Double]

    /// The interval the ratios repeat over. Two is an octave; nearly every
    /// tuning uses it, and the ones that do not are the interesting ones.
    public private(set) var period: Double

    /// The pitch of degree 0.
    public var root: Pitch

    /// A tuning from ratios you have worked out.
    ///
    /// Ratios outside one period are folded into it, so `[1, 3/2, 3]` and
    /// `[1, 3/2]` describe the same tuning.
    public init(ratios: [Double], period: Double = 2, root: Pitch = "C4") {
        self.period = max(1.0001, period)
        self.root = root
        var folded: [Double] = []
        for ratio in ratios where ratio > 0 {
            var value = ratio
            while value >= self.period { value /= self.period }
            while value < 1 { value *= self.period }
            // Ratios that land on each other to within a hundredth of a cent
            // are the same pitch arrived at two ways.
            if !folded.contains(where: { abs(1200 * log2($0 / value)) < 0.01 }) {
                folded.append(value)
            }
        }
        self.ratios = folded.isEmpty ? [1] : folded.sorted()
    }

    /// The period divided into `count` equal steps.
    ///
    /// `Tuning.equal(12)` is the ordinary keyboard. The others are the ones
    /// people actually build instruments for: 19 has a usable minor third and
    /// distinguishes the notes a piano spells the same, 24 is the quarter tones
    /// of a great deal of music outside western Europe, and 31 gets very close
    /// to whole number thirds.
    public static func equal(_ count: Int, period: Double = 2, root: Pitch = "C4") -> Tuning {
        let steps = max(1, count)
        return Tuning(ratios: (0..<steps).map { pow(period, Double($0) / Double(steps)) },
                      period: period, root: root)
    }

    // MARK: Reading it

    /// How many pitches there are before it repeats.
    public var degreeCount: Int { ratios.count }

    /// The pitch of a degree, where 0 is the root.
    ///
    /// Degrees past the end carry on into the next period and negative ones run
    /// down into the one below, exactly as a `Scale`'s do, so a wandering
    /// number never leaves the tuning.
    public subscript(degree: Int) -> Pitch { pitch(degree) }

    /// The pitch of a degree, the long way of writing the subscript.
    public func pitch(_ degree: Int) -> Pitch {
        let size = ratios.count
        let period = Int((Double(degree) / Double(size)).rounded(.down))
        let within = degree - period * size
        let ratio = ratios[within] * pow(self.period, Double(period))
        // A pitch is a position on a continuous line rather than a key, so a
        // ratio that lands between two keys simply lands between them.
        return Pitch(root.midi + 12 * log2(ratio))
    }

    /// The frequency of a degree, in Hz.
    public func frequency(_ degree: Int) -> Double { pitch(degree).frequency }

    /// The tuning's nearest pitch to one decided by something else.
    ///
    /// The way a mouse position or a measurement joins the tuning, and the
    /// reason this type has the same shape as a `Scale`.
    public func snap(_ pitch: Pitch) -> Pitch {
        let periods = (pitch.midi - root.midi) / (12 * log2(period))
        let whole = Int(periods.rounded(.down))
        // The period above has to be a candidate too: a pitch just under the
        // next root is nearer to it than to this period's top note.
        var best = self.pitch(whole * ratios.count)
        var bestDistance = Double.infinity
        for offset in 0...ratios.count {
            let candidate = self.pitch(whole * ratios.count + offset)
            let distance = abs(candidate.midi - pitch.midi)
            if distance < bestDistance {
                bestDistance = distance
                best = candidate
            }
        }
        return best
    }

    /// How far each degree sits above the root, in cents.
    ///
    /// A hundred cents is one equally tempered semitone, so this is the way to
    /// see what a tuning is doing: `Tuning.just` reads 0, 204, 386, 498, 702,
    /// 884, 1088, where the equal one reads round hundreds.
    public var cents: [Double] { ratios.map { 1200 * log2($0) } }

    /// The same tuning on another root.
    public func rooted(at pitch: Pitch) -> Tuning {
        var moved = self
        moved.root = pitch
        return moved
    }

    // MARK: Named tunings

    /// The ordinary keyboard: twelve equal steps to the octave.
    public static let equalTemperament = Tuning.equal(12)

    /// Five limit just intonation, the major scale in whole number ratios.
    ///
    /// The intervals lock together instead of beating, which is the whole point
    /// of it and is audible immediately on a held chord. The cost is that it is
    /// only in tune in one key.
    public static let just = Tuning(
        ratios: [1, 9.0 / 8, 5.0 / 4, 4.0 / 3, 3.0 / 2, 5.0 / 3, 15.0 / 8]
    )

    /// Built entirely out of stacked fifths, which is the oldest way to tune
    /// and gives a very pure fifth and a noticeably wide third.
    public static let pythagorean = Tuning(
        ratios: [1, 9.0 / 8, 81.0 / 64, 4.0 / 3, 3.0 / 2, 27.0 / 16, 243.0 / 128]
    )

    /// Quarter tones: twenty four equal steps, so everything a keyboard has
    /// plus the pitches between its keys.
    public static let quarterTones = Tuning.equal(24)

    /// Nineteen equal steps, which is close to the tuning keyboard music was
    /// written for before equal temperament won, and has a sweeter third.
    public static let nineteen = Tuning.equal(19)

    /// Thirty one equal steps, near enough to whole number thirds that chords
    /// stop beating while every key stays usable.
    public static let thirtyOne = Tuning.equal(31)

    /// Thirteen equal steps of a *tritave*, which is a third rather than an
    /// octave, so it has no octave in it at all.
    ///
    /// Doubling a frequency is so familiar that a tuning without it sounds
    /// wrong before it sounds strange, and then stops sounding wrong. It works
    /// because odd harmonics still line up, so it suits sounds that have only
    /// odd harmonics, and ``BlownTube`` is exactly that.
    public static let bohlenPierce = Tuning.equal(13, period: 3)
}
