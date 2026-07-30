import Ollin
import Testing

/// Pure-CPU checks on `concaveHull(of:concavity:)` and `alphaShape(of:alpha:)`:
/// zero concavity reproduces the convex hull, every point stays inside, the
/// polygon stays simple, erosion only shrinks, the alpha complex resolves
/// islands and holes with boundaries made of input points, and degenerate
/// inputs pass through. No GPU.
@Suite
struct HullTests {
    private func scatter(_ count: Int, seed: UInt64, size: Double = 400) -> [Vector2] {
        var rng = SplitMix64(seed: seed)
        return (0 ..< count).map { _ in
            Vector2(Double.random(in: 0...size, using: &rng),
                    Double.random(in: 0...size, using: &rng))
        }
    }

    private func area(_ points: [Vector2]) -> Double {
        guard points.count >= 3 else { return 0 }
        var sum = 0.0
        for i in points.indices {
            let p = points[i], q = points[(i + 1) % points.count]
            sum += p.x * q.y - q.x * p.y
        }
        return abs(sum) * 0.5
    }

    @Test func zeroConcavityIsTheConvexHull() {
        // Seed 7 is the regression scatter: its triangulation drops one
        // hairline hull sliver, so this also pins the notch-capping repair
        // that makes zero concavity the exact convex hull.
        let points = scatter(200, seed: 7)
        #expect(concaveHull(of: points, concavity: 0) == convexHull(of: points))
    }

    @Test func everyPointStaysInside() {
        let points = scatter(150, seed: 11)
        for concavity in [0.3, 0.6, 1.0] {
            let hull = concaveHull(of: points, concavity: concavity)
            let region = Shape(hull)
            for p in points {
                #expect(hull.contains(p) || region.contains(p))
            }
        }
    }

    @Test func hullStaysSimple() {
        let points = scatter(150, seed: 23)
        let hull = concaveHull(of: points, concavity: 1)
        // No two non-adjacent edges may cross: the chi-shape's one promise.
        func crosses(_ a: Vector2, _ b: Vector2, _ c: Vector2, _ d: Vector2) -> Bool {
            func side(_ p: Vector2, _ q: Vector2, _ r: Vector2) -> Double {
                (q - p).cross(r - p)
            }
            return side(a, b, c) * side(a, b, d) < 0 && side(c, d, a) * side(c, d, b) < 0
        }
        let m = hull.count
        for i in 0 ..< max(m - 2, 0) {
            for j in (i + 2) ..< m where !(i == 0 && j == m - 1) {
                #expect(!crosses(hull[i], hull[(i + 1) % m],
                                 hull[j], hull[(j + 1) % m]))
            }
        }
    }

    @Test func erosionOnlyShrinks() {
        let points = scatter(200, seed: 31)
        let loose = area(concaveHull(of: points, concavity: 0))
        let middle = area(concaveHull(of: points, concavity: 0.5))
        let tight = area(concaveHull(of: points, concavity: 1))
        #expect(loose >= middle)
        #expect(middle >= tight)
        #expect(tight > 0)
    }

    @Test func hullIsDeterministic() {
        let points = scatter(180, seed: 43)
        #expect(concaveHull(of: points, concavity: 0.7) == concaveHull(of: points, concavity: 0.7))
    }

    @Test func degenerateInputsAreSafe() {
        #expect(concaveHull(of: []).isEmpty)
        #expect(concaveHull(of: [Vector2(1, 2)]) == [Vector2(1, 2)])
        #expect(concaveHull(of: [Vector2(1, 2), Vector2(3, 4)]).count == 2)
        let collinear = (0 ..< 5).map { Vector2(Double($0) * 10, 5) }
        #expect(concaveHull(of: collinear) == convexHull(of: collinear))
        #expect(alphaShape(of: [], alpha: 10).isEmpty)
        #expect(alphaShape(of: collinear, alpha: 10).isEmpty)
        #expect(alphaShape(of: scatter(50, seed: 3), alpha: 0).isEmpty)
    }

    @Test func hugeAlphaIsTheConvexHull() {
        let points = scatter(200, seed: 55)
        let shapes = alphaShape(of: points, alpha: 10_000)
        #expect(shapes.count == 1)
        #expect(shapes[0].contours.count == 1)
        let hullArea = area(convexHull(of: points))
        #expect(abs(area(shapes[0].contours[0].points) - hullArea) < hullArea * 1e-9)
    }

    @Test func tinyAlphaDissolvesTheScatter() {
        #expect(alphaShape(of: scatter(100, seed: 61), alpha: 0.5).isEmpty)
    }

    @Test func alphaResolvesIslands() {
        var rng = SplitMix64(seed: 77)
        var points: [Vector2] = []
        for center in [Vector2(100, 100), Vector2(320, 260)] {
            for _ in 0 ..< 120 {
                let angle = Double.random(in: 0 ..< 2 * .pi, using: &rng)
                let radius = Double.random(in: 0...40, using: &rng)
                points.append(center + Vector2(cos(angle), sin(angle)) * radius)
            }
        }
        let shapes = alphaShape(of: points, alpha: 25)
        #expect(shapes.count == 2)
    }

    @Test func alphaResolvesHoles() {
        // A jittered polar grid of annulus points: even spacing, so a probe
        // between the local spacing and the hole radius must find the hole.
        var rng = SplitMix64(seed: 91)
        var points: [Vector2] = []
        for ring in 0 ... 5 {
            let radius = 60 + Double(ring) * 8
            let count = Int((2 * Double.pi * radius / 8).rounded())
            for i in 0 ..< count {
                let angle = Double(i) / Double(count) * 2 * .pi
                let r = radius + Double.random(in: -2...2, using: &rng)
                points.append(Vector2(200 + cos(angle) * r, 200 + sin(angle) * r))
            }
        }
        let shapes = alphaShape(of: points, alpha: 20)
        #expect(shapes.count == 1)
        #expect(shapes[0].contours.count == 2)
        let outer = area(shapes[0].contours[0].points)
        let hole = area(shapes[0].contours[1].points)
        #expect(outer > 27_000 && outer < 35_000)   // near pi * 100^2
        #expect(hole > 8_000 && hole < 14_000)      // near pi * 60^2
    }

    @Test func alphaBoundariesAreInputPoints() {
        let points = scatter(150, seed: 99)
        for shape in alphaShape(of: points, alpha: 60) {
            for contour in shape.contours {
                for p in contour.points {
                    #expect(points.contains(p))
                }
            }
        }
    }

    @Test func alphaIsDeterministic() {
        let points = scatter(160, seed: 101)
        #expect(alphaShape(of: points, alpha: 45) == alphaShape(of: points, alpha: 45))
    }
}
