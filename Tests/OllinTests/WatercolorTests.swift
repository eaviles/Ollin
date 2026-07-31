import Ollin
import Testing

/// Pure-CPU checks on `Watercolor`: subdivision doubles vertices and keeps
/// the parents fixed, per-edge variance decays as it inherits, the detail
/// floor bounds growth, layers never mutate the shared base, the layer
/// shape is wound non-zero, and everything reproduces from a seed. No GPU.
@Suite
struct WatercolorTests {
    private let triangle = [Vector2(0, 0), Vector2(200, 0), Vector2(100, 160)]

    @Test func subdivisionDoublesAndKeepsParents() {
        var rng = SplitMix64(seed: 1)
        let base = Watercolor(polygon: triangle, variance: 10, rounds: 0,
                              detail: 0, using: &rng)
        let layer = base.layer(rounds: 1, using: &rng)
        #expect(layer.count == 6)
        // Original vertices survive at even indices; only midpoints moved.
        for (i, p) in triangle.enumerated() {
            #expect(layer[i * 2] == p)
        }
    }

    @Test func varianceDecaysAsItInherits() {
        var rng = SplitMix64(seed: 2)
        let base = Watercolor(polygon: triangle, variance: 12, rounds: 6,
                              detail: 0, using: &rng)
        // Six rounds of 0.4...0.8 decay from at most 12 × 1.8.
        let ceiling = 12.0 * 1.8 * pow(0.8, 6)
        for v in base.variances {
            #expect(v > 0 && v < ceiling + 1e-9)
        }
    }

    @Test func detailFloorBoundsGrowth() {
        var rng = SplitMix64(seed: 3)
        let unbounded = Watercolor(polygon: triangle, variance: 4, rounds: 8,
                                   detail: 0, using: &rng)
        #expect(unbounded.polygon.count == 3 * 256)
        var rng2 = SplitMix64(seed: 3)
        let floored = Watercolor(polygon: triangle, variance: 4, rounds: 8,
                                 detail: 6, using: &rng2)
        #expect(floored.polygon.count < unbounded.polygon.count / 2)
    }

    @Test func layersDoNotMutateTheBase() {
        var rng = SplitMix64(seed: 4)
        let base = Watercolor(around: Vector2(100, 100), radius: 80, using: &rng)
        let snapshot = base.polygon
        _ = base.layers(3, using: &rng)
        #expect(base.polygon == snapshot)
    }

    @Test func layerShapeIsWoundNonZero() {
        var rng = SplitMix64(seed: 5)
        let base = Watercolor(around: Vector2(0, 0), radius: 60, using: &rng)
        let shape = base.layerShape(using: &rng)
        #expect(shape.winding == .nonZero)
        #expect(shape.contours.count == 1 && shape.contours[0].isClosed)
    }

    @Test func sameSeedSamePainting() {
        var rngA = SplitMix64(seed: 9)
        var rngB = SplitMix64(seed: 9)
        let a = Watercolor(around: Vector2(50, 50), radius: 70, using: &rngA)
        let b = Watercolor(around: Vector2(50, 50), radius: 70, using: &rngB)
        #expect(a.polygon == b.polygon)
        #expect(a.layer(using: &rngA) == b.layer(using: &rngB))
        var rngC = SplitMix64(seed: 10)
        let c = Watercolor(around: Vector2(50, 50), radius: 70, using: &rngC)
        #expect(a.polygon != c.polygon)
    }
}
