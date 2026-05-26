import Foundation

/// A small, fast, seedable PRNG (SplitMix64) backing `Sketch.random` /
/// `Sketch.randomSeed`. Lives on the `Sketch` instance rather than as global
/// mutable state. The default seed is entropy-based, so an unseeded sketch
/// varies per run; call `randomSeed(_:)` for reproducible output.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

public extension Sketch {
    /// Seed the generator behind `random()` for reproducible runs — the same
    /// seed yields the same sequence. (Ollin's `random`/`noise` are their own
    /// implementations, so a seed reproduces Ollin's output.)
    func randomSeed(_ seed: Int) {
        rng = SplitMix64(seed: UInt64(bitPattern: Int64(seed)))
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
}
