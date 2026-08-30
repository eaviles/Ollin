import Ollin
import Testing

/// Pure-CPU checks on the low-discrepancy samplers: the classic sequences
/// produce their known values, prefixes are stable, and everything stays in
/// bounds.
@Suite
struct SamplingTests {
    /// The base-2 radical inverse: the van der Corput sequence's first terms.
    @Test func haltonBase2KnownValues() {
        #expect(halton(0) == 0)
        #expect(halton(1) == 0.5)
        #expect(halton(2) == 0.25)
        #expect(halton(3) == 0.75)
        #expect(halton(4) == 0.125)
        #expect(halton(5) == 0.625)
    }

    /// The base-3 radical inverse.
    @Test func haltonBase3KnownValues() {
        #expect(abs(halton(1, base: 3) - 1.0 / 3) < 1e-12)
        #expect(abs(halton(2, base: 3) - 2.0 / 3) < 1e-12)
        #expect(abs(halton(3, base: 3) - 1.0 / 9) < 1e-12)
        #expect(abs(halton(4, base: 3) - 4.0 / 9) < 1e-12)
    }

    /// The 2D Sobol sequence's first points are the canonical dyadic values.
    @Test func sobolKnownValues() {
        let unit = Rectangle(x: 0, y: 0, width: 1, height: 1)
        let points = sobolPoints(count: 7, in: unit)
        let expected: [(Double, Double)] = [
            (0.5, 0.5), (0.75, 0.25), (0.25, 0.75),
            (0.375, 0.375), (0.875, 0.875), (0.625, 0.125), (0.125, 0.625),
        ]
        for (p, e) in zip(points, expected) {
            #expect(p.x == e.0 && p.y == e.1)
        }
    }

    /// The prefix property: a longer run begins with exactly the shorter one.
    @Test func prefixesAreStable() {
        let unit = Rectangle(x: 0, y: 0, width: 1, height: 1)
        #expect(Array(haltonPoints(count: 200, in: unit).prefix(50))
            == haltonPoints(count: 50, in: unit))
        #expect(Array(sobolPoints(count: 200, in: unit).prefix(50))
            == sobolPoints(count: 50, in: unit))
    }

    /// Points land inside the requested rectangle, wherever it sits.
    @Test func pointsStayInBounds() {
        let bounds = Rectangle(x: -40, y: 120, width: 300, height: 90)
        for p in haltonPoints(count: 500, in: bounds) + sobolPoints(count: 500, in: bounds) {
            #expect(bounds.contains(p))
        }
        #expect(haltonPoints(count: 500, in: bounds).count == 500)
        #expect(sobolPoints(count: 0, in: bounds).isEmpty)
    }
}

/// Pure-CPU checks on weighted-Voronoi stippling: dots follow the darkness,
/// reproduce for a seed, and the degenerate inputs stay graceful.
@Suite
struct StippleTests {
    /// A half-black, half-white image concentrates nearly all dots in the
    /// dark half.
    @Test func dotsFollowDarkness() {
        let image = Image(width: 64, height: 64, color: .white)
        for y in 0 ..< 64 {
            for x in 0 ..< 32 { image[x, y] = .black }
        }
        let bounds = Rectangle(x: 0, y: 0, width: 200, height: 200)
        var rng = SplitMix64(seed: 7)
        let dots = stipple(of: image, count: 300, in: bounds, iterations: 10, using: &rng)
        #expect(dots.count == 300)
        let inDark = dots.filter { $0.x < 100 }.count
        #expect(inDark > 280)
        for d in dots { #expect(bounds.contains(d)) }
    }

    /// The same seed reproduces the stipple exactly; a different seed doesn't.
    @Test func seededStippleReproduces() {
        let bounds = Rectangle(x: 0, y: 0, width: 100, height: 100)
        func run(_ seed: UInt64) -> [Vector2] {
            var rng = SplitMix64(seed: seed)
            return stipple(count: 120, in: bounds, iterations: 6, using: &rng) { p in
                p.x / 100
            }
        }
        #expect(run(3) == run(3))
        #expect(run(3) != run(4))
    }

    /// No ink anywhere (an all-white image, an all-zero density) yields no dots.
    @Test func emptyDensityYieldsNoDots() {
        let bounds = Rectangle(x: 0, y: 0, width: 100, height: 100)
        var rng = SplitMix64(seed: 1)
        #expect(stipple(of: Image(width: 8, height: 8, color: .white),
                        count: 50, in: bounds, using: &rng).isEmpty)
        #expect(stipple(count: 50, in: bounds, using: &rng) { _ in 0 }.isEmpty)
    }
}
