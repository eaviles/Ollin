import Ollin
import Testing

/// Pure-geometry checks on the packers, no GPU, so these run everywhere. The
/// load-bearing properties: packed circles never overlap, and a seeded pack is
/// reproducible.
@Suite
struct PackingTests {
    private let bounds = Rectangle(x: 0, y: 0, width: 400, height: 400)

    /// A `ContinuousPacking` with no shape bag packs plain circles; none of them
    /// may overlap (centers at least the sum of radii, plus padding, apart).
    @Test func continuousCirclesNeverOverlap() {
        let padding = 2.0
        let packer = ContinuousPacking(in: bounds, seed: 1, minRadius: 4, maxRadius: 60,
                                       padding: padding, attemptsPerStep: 40)
        packer.step(60)
        #expect(packer.count > 20)
        let circles = packer.circles
        for i in circles.indices {
            // Every circle sits inside the bounds.
            #expect(circles[i].radius >= 4)
            #expect(circles[i].center.x - circles[i].radius >= -1e-6)
            #expect(circles[i].center.x + circles[i].radius <= bounds.width + 1e-6)
            for j in (i + 1) ..< circles.count {
                let d = circles[i].center.distance(to: circles[j].center)
                #expect(d + 1e-6 >= circles[i].radius + circles[j].radius + padding)
            }
        }
    }

    /// The same seed grows the same packing, a different seed does not.
    @Test func continuousPackingIsReproducible() {
        func run(seed: UInt64) -> [Circle] {
            let packer = ContinuousPacking(in: bounds, seed: seed, minRadius: 4, maxRadius: 60,
                                           attemptsPerStep: 30)
            packer.step(40)
            return packer.circles
        }
        let a = run(seed: 7), b = run(seed: 7), c = run(seed: 8)
        #expect(a.count == b.count)
        #expect(zip(a, b).allSatisfy { $0.center == $1.center && $0.radius == $1.radius })
        #expect(a.count != c.count || !zip(a, c).allSatisfy { $0.center == $1.center })
    }

    /// The one-shot `packShapes` places valid, in-bounds shapes and is seeded.
    @Test func packShapesPlacesValidShapes() {
        let bag = [Shape([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)], closed: true),
                   Shape([Vector2(0, -1), Vector2(1, 1), Vector2(-1, 1)], closed: true)]
        var rng = SplitMix64(seed: 3)
        let shapes = packShapes(bag, in: bounds, count: 120, minRadius: 5, maxRadius: 70,
                                padding: 2, using: &rng)
        #expect(shapes.count > 10)
        for shape in shapes {
            for p in shape.contours.flatMap(\.points) {
                #expect(p.x >= -1e-6 && p.x <= bounds.width + 1e-6)
                #expect(p.y >= -1e-6 && p.y <= bounds.height + 1e-6)
            }
        }
    }
}
