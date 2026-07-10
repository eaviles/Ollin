import Ollin
import Testing

/// Pure-CPU checks on the random-walk family: step-length contracts hold,
/// the self-avoiding walk really is self-avoiding, and a seed reproduces.
@Suite
struct WalkTests {
    /// Every step of a plain walk has exactly the requested length.
    @Test func randomWalkStepLengths() {
        var rng = SplitMix64(seed: 9)
        let path = randomWalk(from: Vector2(10, 20), steps: 200, stepLength: 7, using: &rng)
        #expect(path.count == 201)
        #expect(path[0] == Vector2(10, 20))
        for i in 1 ..< path.count {
            #expect(abs(path[i - 1].distance(to: path[i]) - 7) < 1e-9)
        }
    }

    /// Lévy steps stay inside [minStep, maxStep] for the general exponent and
    /// for the μ = 1 special case.
    @Test func levyStepBounds() {
        for exponent in [1.0, 1.6, 2.0, 3.0] {
            var rng = SplitMix64(seed: 4)
            let path = levyFlight(from: .init(0, 0), steps: 500,
                                  minStep: 3, maxStep: 120, exponent: exponent, using: &rng)
            #expect(path.count == 501)
            for i in 1 ..< path.count {
                let step = path[i - 1].distance(to: path[i])
                #expect(step >= 3 - 1e-9 && step <= 120 + 1e-9)
            }
        }
    }

    /// Heavy tail sanity: with μ near 1 the long steps dominate far more than
    /// with μ near 3, so the mean step length orders accordingly.
    @Test func levyExponentShapesTheTail() {
        func meanStep(_ exponent: Double) -> Double {
            var rng = SplitMix64(seed: 11)
            let path = levyFlight(from: .init(0, 0), steps: 4000,
                                  minStep: 1, maxStep: 1000, exponent: exponent, using: &rng)
            var total = 0.0
            for i in 1 ..< path.count { total += path[i - 1].distance(to: path[i]) }
            return total / Double(path.count - 1)
        }
        #expect(meanStep(1.2) > 3 * meanStep(2.8))
    }

    /// The self-avoiding walk visits each lattice cell at most once, steps
    /// only to orthogonal neighbors, and stays in bounds.
    @Test func selfAvoidingWalkIsSelfAvoiding() {
        let bounds = Rectangle(x: 0, y: 0, width: 400, height: 300)
        var rng = SplitMix64(seed: 5)
        let path = selfAvoidingWalk(in: bounds, cellSize: 25, using: &rng)
        #expect(path.count > 20)
        var seen = Set<String>()
        for p in path {
            #expect(bounds.contains(p))
            let key = "\(Int(p.x.rounded())),\(Int(p.y.rounded()))"
            #expect(!seen.contains(key))
            seen.insert(key)
        }
        for i in 1 ..< path.count {
            #expect(abs(path[i - 1].distance(to: path[i]) - 25) < 1e-9)
        }
    }

    /// `maxLength` caps the path exactly.
    @Test func selfAvoidingWalkHonorsMaxLength() {
        var rng = SplitMix64(seed: 5)
        let path = selfAvoidingWalk(in: Rectangle(x: 0, y: 0, width: 400, height: 400),
                                    cellSize: 20, maxLength: 30, using: &rng)
        #expect(path.count == 30)
    }

    /// The same seed reproduces every walk exactly; a different seed doesn't.
    @Test func seededWalksReproduce() {
        let bounds = Rectangle(x: 0, y: 0, width: 300, height: 300)
        func saw(_ seed: UInt64) -> [Vector2] {
            var rng = SplitMix64(seed: seed)
            return selfAvoidingWalk(in: bounds, cellSize: 30, using: &rng)
        }
        func levy(_ seed: UInt64) -> [Vector2] {
            var rng = SplitMix64(seed: seed)
            return levyFlight(from: .init(0, 0), steps: 100, minStep: 2, maxStep: 50, using: &rng)
        }
        #expect(saw(8) == saw(8))
        #expect(saw(8) != saw(9))
        #expect(levy(8) == levy(8))
        #expect(levy(8) != levy(9))
    }
}
