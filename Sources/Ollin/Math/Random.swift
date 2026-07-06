import Foundation

/// A small, fast, seedable PRNG (SplitMix64) backing `Sketch.random` /
/// `Sketch.randomSeed`. Lives on the `Sketch` instance rather than as global
/// mutable state. The default seed is entropy-based, so an unseeded sketch
/// varies per run; call `randomSeed(_:)` for reproducible output.
///
/// It's public so the seedable geometry generators (like `poissonDisk`) can be
/// driven reproducibly outside a `Sketch` too — hand one a seeded `SplitMix64`
/// and the same seed always yields the same result.
public struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

public extension Sketch {
    /// Seed the generator behind `random()` for reproducible runs: the same
    /// seed yields the same sequence. (Ollin's `random`/`noise` are their own
    /// implementations, so a seed reproduces Ollin's output.)
    func randomSeed(_ seed: Int) {
        rng = SplitMix64(seed: UInt64(bitPattern: Int64(seed)))
        gaussianSpare = nil   // so a reseed restarts a deterministic sequence
    }

    /// Seed *both* `random` and `noise` from one value, locking the whole
    /// sketch's randomness so it reproduces exactly. Use `randomSeed` or
    /// `noiseSeed` to reseed just one.
    func seed(_ seed: Int) {
        randomSeed(seed)
        noiseSeed(seed)
    }

    /// A random `Double` in `0 ..< 1`.
    func random() -> Double { Double.random(in: 0 ..< 1, using: &rng) }

    /// A random `Double` from `0` up to `max` (the other way if `max` is negative).
    func random(_ max: Double) -> Double { random(0, max) }

    /// A random `Double` between `min` and `max` (order-independent).
    func random(_ min: Double, _ max: Double) -> Double {
        let lo = Swift.min(min, max), hi = Swift.max(min, max)
        guard lo < hi else { return lo }
        return Double.random(in: lo ..< hi, using: &rng)
    }

    /// A random `Double` from a standard normal distribution (mean `0`, standard
    /// deviation `1`): most samples land within ±1, rarely past ±3. Uses the
    /// Marsaglia polar method, which produces two normals at a time, so the spare
    /// is cached for the next call.
    func randomGaussian() -> Double {
        if let spare = gaussianSpare {
            gaussianSpare = nil
            return spare
        }
        var v1 = 0.0, v2 = 0.0, s = 0.0
        repeat {
            v1 = 2 * random() - 1
            v2 = 2 * random() - 1
            s = v1 * v1 + v2 * v2
        } while s >= 1 || s == 0
        let multiplier = (-2 * log(s) / s).squareRoot()
        gaussianSpare = v2 * multiplier
        return v1 * multiplier
    }

    /// A random `Double` from a normal distribution with the given `mean` and
    /// `deviation` (standard deviation).
    func randomGaussian(mean: Double, deviation: Double) -> Double {
        mean + randomGaussian() * deviation
    }

    /// A random point inside `rect`, each coordinate uniform within the bounds.
    /// Handy for scattering: `randomVector(in: Rectangle(x: 0, y: 0, width: width, height: height))`.
    func randomVector(in rect: Rectangle) -> Vector2 {
        Vector2(random(rect.x, rect.x + rect.width),
                random(rect.y, rect.y + rect.height))
    }

    /// A random point in the annulus (ring) between `innerRadius` and
    /// `outerRadius`, centered on the origin. Add a center to place it: e.g.
    /// `center + ring(innerRadius: 50, outerRadius: 100)`.
    func ring(innerRadius: Double, outerRadius: Double) -> Vector2 {
        let radius = random(innerRadius, outerRadius)
        let angle = random(.tau)
        return Vector2(cos(angle) * radius, sin(angle) * radius)
    }

    /// A random element of `choices`, each equally likely. The everyday
    /// palette pick: `fill(randomChoice(palette))`. Seeded like everything
    /// `random`, so `randomSeed` makes the picks reproducible. `choices` must
    /// not be empty.
    func randomChoice<T>(_ choices: [T]) -> T {
        precondition(!choices.isEmpty, "randomChoice needs at least one choice")
        return choices[Int.random(in: 0 ..< choices.count, using: &rng)]
    }

    /// A random element of `choices`, biased by `weights`: one non-negative
    /// weight per choice, in any scale (they need not sum to 1), and a choice
    /// weighted 0 is never picked. `randomChoice(palette, weights: [6, 3, 1])`
    /// picks the first color six times as often as the last.
    func randomChoice<T>(_ choices: [T], weights: [Double]) -> T {
        precondition(!choices.isEmpty, "randomChoice needs at least one choice")
        precondition(choices.count == weights.count,
                     "randomChoice needs one weight per choice")
        let total = weights.reduce(0, +)
        precondition(weights.allSatisfy { $0 >= 0 } && total > 0,
                     "randomChoice weights must be non-negative, with at least one above zero")
        let roll = random(total)
        var cumulative = 0.0
        for (choice, weight) in zip(choices, weights) {
            cumulative += weight
            if roll < cumulative { return choice }
        }
        // Floating-point summation can leave the roll a hair past the last
        // threshold; land it on the final pickable choice.
        return choices[weights.lastIndex(where: { $0 > 0 })!]
    }

    /// The elements of `array` in a random order, drawn from the sketch's
    /// seeded generator, so a seeded shuffle reproduces. (An array's own
    /// `shuffled()` rolls the system's dice instead and differs every run.)
    func shuffled<T>(_ array: [T]) -> [T] {
        array.shuffled(using: &rng)
    }
}
