import Ollin
import Testing

/// Pure-CPU checks on `medialAxis(of:spacing:prune:)`: the rectangle's
/// skeleton is its roof ridge with corner twigs, every radius matches the
/// true clearance, a disk collapses to its center, pruning trims twigs but
/// never a whole component, an annulus keeps a closed ring, and degenerate
/// inputs pass through. No GPU.
@Suite
struct MedialAxisTests {
    private let rect = Shape([Vector2(0, 0), Vector2(200, 0),
                              Vector2(200, 100), Vector2(0, 100)])

    /// A jittered near-circle, so cocircular degeneracies never decide a test.
    private func blob(center: Vector2, radius: Double, seed: UInt64) -> Shape {
        var rng = SplitMix64(seed: seed)
        let points = (0 ..< 48).map { i in
            let angle = Double(i) / 48 * 2 * .pi
            let r = radius + Double.random(in: -1...1, using: &rng)
            return center + Vector2(cos(angle), sin(angle)) * r
        }
        return Shape(points)
    }

    @Test func rectangleHasItsRoofRidge() {
        let axis = medialAxis(of: rect, spacing: 5)
        #expect(!axis.branches.isEmpty)
        // The ridge runs along y = 50; some skeleton point sits mid-shape
        // carrying the half-height clearance.
        var best: (point: Vector2, radius: Double)?
        for branch in axis.branches {
            for (p, r) in zip(branch.points, branch.radii)
            where (p - Vector2(100, 50)).length < 6 {
                best = (p, r)
            }
        }
        #expect(best != nil)
        if let best {
            #expect(abs(best.radius - 50) < 6)
        }
    }

    @Test func radiiMatchTheTrueClearance() {
        let spacing = 5.0
        let axis = medialAxis(of: rect, spacing: spacing)
        for branch in axis.branches {
            for (p, r) in zip(branch.points, branch.radii) {
                let clearance = min(min(p.x, 200 - p.x), min(p.y, 100 - p.y))
                #expect(abs(r - clearance) <= spacing)
            }
        }
    }

    @Test func diskSkeletonPeaksAtItsCenter() {
        // A polygonized disk's skeleton legitimately grows spokes toward its
        // convex corners, so pin the universal invariants instead: every
        // radius is the true clearance, and the deepest inscribed disk sits
        // at the center with the disk's own radius.
        let center = Vector2(100, 100)
        let shape = blob(center: center, radius: 80, seed: 5)
        let boundary = shape.contours[0].points
        func clearance(_ p: Vector2) -> Double {
            var best = Double.infinity
            for i in boundary.indices {
                let a = boundary[i], b = boundary[(i + 1) % boundary.count]
                let ab = b - a
                let t = min(max((p - a).dot(ab) / ab.dot(ab), 0), 1)
                best = min(best, (p - (a + ab * t)).length)
            }
            return best
        }
        let axis = medialAxis(of: shape, spacing: 6)
        #expect(!axis.branches.isEmpty)
        var deepest: (point: Vector2, radius: Double) = (center, 0)
        for branch in axis.branches {
            for (p, r) in zip(branch.points, branch.radii) {
                #expect(abs(r - clearance(p)) <= 6)
                if r > deepest.radius { deepest = (p, r) }
            }
        }
        #expect(deepest.radius > 70 && deepest.radius < 85)
        #expect((deepest.point - center).length < 15)
    }

    @Test func pruneTrimsCornerTwigsButNeverAWholeComponent() {
        let full = medialAxis(of: rect, spacing: 5)
        #expect(full.branches.count >= 5)   // the ridge plus four corner twigs
        // The corner twigs run about 70 units; prune past that and only the
        // ridge survives, merged back into one open branch. The ridge itself
        // is then a whole component, so it can never prune away.
        let pruned = medialAxis(of: rect, spacing: 5, prune: 90)
        #expect(pruned.branches.count == 1)
        if let ridge = pruned.branches.first {
            #expect(!ridge.isClosed)
            #expect(ridge.contour.length > 80 && ridge.contour.length < 120)
            for p in ridge.points {
                #expect(abs(p.y - 50) < 3)
            }
        }
    }

    @Test func annulusKeepsAClosedRing() {
        let center = Vector2(150, 150)
        var rng = SplitMix64(seed: 17)
        func ring(_ radius: Double) -> [Vector2] {
            (0 ..< 48).map { i in
                let angle = Double(i) / 48 * 2 * .pi
                let r = radius + Double.random(in: -1...1, using: &rng)
                return center + Vector2(cos(angle), sin(angle)) * r
            }
        }
        let annulus = Shape(outer: ring(100), holes: [ring(60)])
        let axis = medialAxis(of: annulus, spacing: 6, prune: 12)
        #expect(axis.branches.count == 1)
        if let loop = axis.branches.first {
            #expect(loop.isClosed)
            for (p, r) in zip(loop.points, loop.radii) {
                #expect(abs((p - center).length - 80) < 6)
                #expect(abs(r - 20) < 6)
            }
        }
    }

    @Test func axisIsDeterministic() {
        let shape = blob(center: Vector2(200, 150), radius: 120, seed: 29)
        #expect(medialAxis(of: shape, spacing: 4, prune: 8)
            == medialAxis(of: shape, spacing: 4, prune: 8))
    }

    @Test func degenerateInputsAreSafe() {
        #expect(medialAxis(of: Shape(contours: [])).branches.isEmpty)
        #expect(medialAxis(of: Shape([Vector2(0, 0), Vector2(10, 0)])).branches.isEmpty)
        let tiny = Shape([Vector2(0, 0), Vector2(2, 0), Vector2(1, 2)])
        #expect(medialAxis(of: tiny, spacing: 10).branches.isEmpty)
        #expect(medialAxis(of: rect, spacing: 0).branches.isEmpty)
        // An open contour is treated as the closed boundary it outlines.
        let open = Shape(contours: [Contour([Vector2(0, 0), Vector2(100, 0),
                                             Vector2(100, 60), Vector2(0, 60)],
                                            closed: false)])
        #expect(!medialAxis(of: open, spacing: 5).branches.isEmpty)
    }
}
