import Foundation

/// A cycle of steps, each one either struck or silent.
///
/// The quick way to one is to ask for a number of strikes spread over a number
/// of steps, which spaces them as evenly as the two numbers allow:
///
/// ```swift
/// let rhythm = Rhythm(3, in: 8)     // x . . x . . x .
/// if rhythm[step] { drum.play(36) }
/// ```
///
/// That spacing is Bjorklund's algorithm, which turns out to produce a great
/// many of the rhythms people already play: `Rhythm(3, in: 8)` is the Cuban
/// tresillo, `Rhythm(5, in: 8)` the cinquillo, and `Rhythm(7, in: 12)` started
/// three onsets in is the bell pattern heard across west Africa. The named ones
/// are collected under ``tresillo`` and its neighbors.
///
/// A rhythm can also be written out, which is what you want when you have a
/// pattern in mind rather than a count:
///
/// ```swift
/// let clave: Rhythm = "x..x..x...x.x..."
/// ```
///
/// The subscript wraps, so a step number can climb forever and the cycle
/// repeats under it. Nothing here knows what a beat is or how fast one goes
/// past: a rhythm answers a step number, and turning musical time into step
/// numbers is ``StepCounter``'s job.
public struct Rhythm: Sendable, Hashable, CustomStringConvertible {

    /// The cycle, one entry per step. True is a strike.
    public private(set) var steps: [Bool]

    /// Spreads `pulses` strikes over `steps` steps as evenly as they go.
    ///
    /// When the two divide evenly the answer is the obvious one: three strikes
    /// over twelve steps land on every fourth. When they do not, the strikes
    /// come out unevenly spaced but as close to even as whole steps permit,
    /// which is where the interesting rhythms live.
    ///
    /// - Parameters:
    ///   - pulses: how many strikes. Zero gives silence, and anything at or
    ///     past `steps` fills every step.
    ///   - steps: the length of the cycle.
    ///   - rotation: how many steps later to start, so the same set of
    ///     spacings can begin somewhere other than its first strike.
    public init(_ pulses: Int, in steps: Int, rotation: Int = 0) {
        self.steps = Rhythm.spread(pulses: pulses, over: steps)
        if rotation != 0 { self = rotated(by: rotation) }
    }

    /// A rhythm from a cycle you have already worked out.
    public init(steps: [Bool]) {
        self.steps = steps
    }

    /// A rhythm written out, where `x` is a strike and `.` is a rest.
    ///
    /// `x`, `X`, `1`, and `*` all mean struck; `.`, `-`, `_`, `0`, and spaces
    /// all mean silent. Returns nil for anything else, which is what separates
    /// this from the literal form.
    public init?(pattern: String) {
        var steps = [Bool]()
        steps.reserveCapacity(pattern.count)
        for character in pattern {
            switch character {
            case "x", "X", "1", "*":                steps.append(true)
            case ".", "-", "_", "0", " ":           steps.append(false)
            default:                                return nil
            }
        }
        self.steps = steps
    }

    // MARK: Reading it

    /// Whether the step is struck. The cycle repeats, and negative steps count
    /// backwards through it, so a step number never has to be kept in range.
    public subscript(step: Int) -> Bool {
        guard !steps.isEmpty else { return false }
        return steps[((step % steps.count) + steps.count) % steps.count]
    }

    /// How many steps go by before the cycle comes round again.
    public var length: Int { steps.count }

    /// How many of them are struck.
    public var pulseCount: Int { steps.count(where: { $0 }) }

    /// The step numbers that are struck, in order.
    public var onsets: [Int] { steps.indices.filter { steps[$0] } }

    /// The gaps between strikes, counting the wrap from the last back to the
    /// first, which is the compact way to compare two rhythms: the tresillo is
    /// (3 3 2) whatever step it starts on.
    public var intervals: [Int] {
        let onsets = onsets
        guard !onsets.isEmpty else { return [] }
        return onsets.indices.map { index in
            let next = index + 1 < onsets.count ? onsets[index + 1] : onsets[0] + steps.count
            return next - onsets[index]
        }
    }

    /// The same cycle beginning `offset` steps later.
    ///
    /// Rhythms that share a set of gaps but start in different places are close
    /// relatives, and the traditional ones are often each other rotated: the
    /// bell pattern is `Rhythm(7, in: 12)` begun at its third strike.
    public func rotated(by offset: Int) -> Rhythm {
        guard !steps.isEmpty else { return self }
        return Rhythm(steps: steps.indices.map { self[$0 + offset] })
    }

    /// The cycle with strikes and rests exchanged.
    public func inverted() -> Rhythm {
        Rhythm(steps: steps.map { !$0 })
    }

    /// The rhythm written out, `x` for a strike and `.` for a rest.
    public var description: String {
        String(steps.map { $0 ? "x" : "." })
    }

    // MARK: Bjorklund's algorithm

    /// Distributes `pulses` ones among `steps` places as evenly as possible.
    ///
    /// The construction starts with every one on the left and every zero on the
    /// right, then repeatedly folds the shorter group into the longer one, one
    /// element each, and carries whatever is left over into the next round. It
    /// stops when there is at most one leftover group, because the cycle has no
    /// beginning: distributing a single remainder would only rotate the answer.
    private static func spread(pulses: Int, over steps: Int) -> [Bool] {
        guard steps > 0 else { return [] }
        guard pulses > 0 else { return Array(repeating: false, count: steps) }
        guard pulses < steps else { return Array(repeating: true, count: steps) }

        var filled = Array(repeating: [true], count: pulses)
        var empty = Array(repeating: [false], count: steps - pulses)

        while empty.count > 1 {
            let pairs = min(filled.count, empty.count)
            var merged = [[Bool]]()
            merged.reserveCapacity(pairs)
            for index in 0..<pairs { merged.append(filled[index] + empty[index]) }

            // Whichever group had more than it could pair off becomes the
            // remainder the next round distributes.
            if filled.count > pairs {
                empty = Array(filled[pairs...])
            } else {
                empty = Array(empty[pairs...])
            }
            filled = merged
        }

        return (filled + empty).flatMap { $0 }
    }
}

extension Rhythm: ExpressibleByStringLiteral {
    /// `let clave: Rhythm = "x..x..x."` reads the string as a cycle.
    ///
    /// A literal cannot fail, so a character that is not part of the notation
    /// leaves an empty rhythm and says so once, rather than stopping the sketch
    /// mid-performance. Use ``init(pattern:)`` where you want to be told in
    /// code instead.
    public init(stringLiteral value: String) {
        if let rhythm = Rhythm(pattern: value) {
            self = rhythm
        } else {
            audioNoteOnce("\"\(value)\" is not a rhythm (try \"x..x..x.\"); using an empty one.")
            self.steps = []
        }
    }
}

// MARK: - Rhythms people already play

extension Rhythm {
    /// Three strikes over eight steps, the most widely traveled of these:
    /// the Cuban tresillo, and the left hand of a great deal of rock and roll.
    public static let tresillo = Rhythm(3, in: 8)

    /// Five over eight, the tresillo's close relative: the Cuban cinquillo,
    /// also found in Egyptian and Korean music.
    public static let cinquillo = Rhythm(5, in: 8)

    /// Seven over twelve begun at its third strike, the bell pattern played
    /// across west Africa and, through it, much of the Americas.
    public static let bellPattern = Rhythm(7, in: 12, rotation: 3)

    /// Five over sixteen begun at its third strike, the bossa nova.
    public static let bossaNova = Rhythm(5, in: 16, rotation: 6)

    /// Seven over sixteen begun at its last strike, a samba.
    public static let samba = Rhythm(7, in: 16, rotation: 14)

    /// Four over nine, the aksak of Turkey and Greece.
    public static let aksak = Rhythm(4, in: 9)

    /// Three over seven, the Bulgarian ruchenitza.
    public static let ruchenitza = Rhythm(3, in: 7)

    /// Five over six, the Arab york samai.
    public static let yorkSamai = Rhythm(5, in: 6)

    /// Five over seven, the Arab nawakhat.
    public static let nawakhat = Rhythm(5, in: 7)

    /// Five over nine, the Arab agsag samai.
    public static let agsagSamai = Rhythm(5, in: 9)

    /// Four over twelve, the flamenco fandango clapping pattern.
    public static let fandango = Rhythm(4, in: 12)
}
