import Ollin
import Testing

/// Pure-math checks on the 1€ filter — no GPU, so these run everywhere (including
/// CI). They confirm the first sample passes through, a constant settles, noise
/// is attenuated, a bigger `beta` tracks a jump faster, `dt <= 0` holds, `reset`
/// clears history, and the `Vector2` form tracks both components.
@Suite
struct OneEuroFilterTests {

    static let dt = 1.0 / 60.0

    /// A deterministic zero-ish-mean noise sequence, so the tests don't depend on
    /// a random generator.
    static func noise(_ i: Int) -> Double {
        let x = (Double(i) * 127.1).truncatingRemainder(dividingBy: 1_000)
        let h = (x * 43_758.5453).truncatingRemainder(dividingBy: 1)
        return h - 0.5            // ~[-0.5, 0.5)
    }

    @Test func firstSamplePassesThrough() {
        var filter = OneEuroFilter<Double>()
        #expect(filter.filter(42, deltaTime: Self.dt) == 42)
    }

    @Test func constantInputSettlesOnTheConstant() {
        var filter = OneEuroFilter<Double>()
        _ = filter.filter(0, deltaTime: Self.dt)             // seed away from the target
        var out = 0.0
        for _ in 0..<300 { out = filter.filter(5, deltaTime: Self.dt) }
        #expect(abs(out - 5) < 1e-3)
    }

    @Test func noiseIsAttenuated() {
        var filter = OneEuroFilter<Double>(minCutoff: 1, beta: 0)
        let mean = 50.0
        var inputs: [Double] = []
        var outputs: [Double] = []
        for i in 0..<400 {
            let x = mean + Self.noise(i) * 20            // ±10 of jitter
            let y = filter.filter(x, deltaTime: Self.dt)
            if i >= 100 {                                // skip warmup
                inputs.append(x)
                outputs.append(y)
            }
        }
        #expect(variance(outputs) < variance(inputs) * 0.25,
                "smoothing should cut the jitter's variance well below the raw signal")
    }

    @Test func higherBetaTracksAJumpFaster() {
        var lazy = OneEuroFilter<Double>(minCutoff: 1, beta: 0)
        var eager = OneEuroFilter<Double>(minCutoff: 1, beta: 1)
        _ = lazy.filter(0, deltaTime: Self.dt)
        _ = eager.filter(0, deltaTime: Self.dt)
        var lazyOut = 0.0, eagerOut = 0.0
        for _ in 0..<5 {                                 // a sudden jump to 100
            lazyOut = lazy.filter(100, deltaTime: Self.dt)
            eagerOut = eager.filter(100, deltaTime: Self.dt)
        }
        #expect(eagerOut > lazyOut, "a larger beta opens the cutoff and catches up sooner")
    }

    @Test func nonPositiveDtHolds() {
        var filter = OneEuroFilter<Double>()
        _ = filter.filter(0, deltaTime: Self.dt)
        let settled = filter.filter(10, deltaTime: Self.dt)
        #expect(filter.filter(999, deltaTime: 0) == settled, "no time passed; hold the last value")
    }

    @Test func resetClearsHistory() {
        var filter = OneEuroFilter<Double>()
        _ = filter.filter(0, deltaTime: Self.dt)
        _ = filter.filter(7, deltaTime: Self.dt)
        filter.reset()
        #expect(filter.filter(99, deltaTime: Self.dt) == 99, "after reset the next sample passes through")
    }

    @Test func vectorFormTracksBothComponents() {
        var filter = OneEuroFilter<Vector2>()
        _ = filter.filter(.zero, deltaTime: Self.dt)
        var out = Vector2.zero
        for _ in 0..<300 { out = filter.filter(Vector2(10, -4), deltaTime: Self.dt) }
        #expect(abs(out.x - 10) < 1e-3)
        #expect(abs(out.y + 4) < 1e-3)
    }

    private func variance(_ xs: [Double]) -> Double {
        let mean = xs.reduce(0, +) / Double(xs.count)
        return xs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(xs.count)
    }
}
