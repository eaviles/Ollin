import Ollin
import Testing

/// Pure-CPU checks on the `Marbling` bath: the drop transform lands points
/// at the exact area-preserving distance, the stylus family displaces only
/// along the tool with the documented falloff, rotational tools preserve
/// radius, the comb repeats per tooth, stretched outlines refine to the
/// spacing, and the whole bath is deterministic. No GPU.
@Suite
struct MarblingTests {
    /// A square outline far from any singular spot, coarse enough that a
    /// huge spacing keeps refinement out of the way (so output points map
    /// 1:1 onto input points).
    private func square(at center: Vector2, half: Double = 40) -> Contour {
        Contour([center + Vector2(-half, -half), center + Vector2(half, -half),
                 center + Vector2(half, half), center + Vector2(-half, half)],
                closed: true)
    }

    @Test func dropDisplacesByTheExactAreaRule() {
        // A huge spacing keeps refinement out (refined midpoints sit on the
        // rim polygon's chords, a hair inside the exact circle), so every
        // output point is a transformed original rim vertex.
        var bath = Marbling(spacing: 10_000)
        bath.drop(at: .zero, radius: 100, color: .black)
        // Every rim vertex of the first drop sits at radius 100; a second
        // drop at the same center must push them all to exactly √(100²+100²).
        bath.drop(at: .zero, radius: 100, color: .white)
        let expected = (100.0 * 100 + 100 * 100).squareRoot()
        let rim = bath.inks[0].shape.contours[0].points
        #expect(!rim.isEmpty)
        for p in rim {
            #expect(abs(p.length - expected) < 1e-9)
        }
    }

    @Test func dropLeavesNoNeighborInsideTheNewDisk() {
        var bath = Marbling()
        bath.drop(at: Vector2(0, 0), radius: 60, color: .black)
        bath.drop(at: Vector2(20, 10), radius: 45, color: .white)
        for p in bath.inks[0].shape.contours[0].points {
            #expect(p.distance(to: Vector2(20, 10)) >= 45 - 1e-9)
        }
    }

    @Test func tineDisplacesAlongTheLineWithHalvingFalloff() {
        var bath = Marbling(spacing: 10_000)   // no refinement: points map 1:1
        bath.add(square(at: Vector2(0, 0)), color: .black)
        let before = bath.inks[0].shape.contours[0].points
        // A horizontal stylus through y = 0, pulled +x: displacement is
        // strength·2^(−|y|/falloff) along x, y untouched.
        bath.tine(through: .zero, direction: Vector2(1, 0),
                  strength: 80, falloff: 40)
        let after = bath.inks[0].shape.contours[0].points
        #expect(after.count == before.count)
        for (p, q) in zip(before, after) {
            #expect(abs(q.y - p.y) < 1e-9)
            let expected = 80 * exp2(-abs(p.y) / 40)
            #expect(abs((q.x - p.x) - expected) < 1e-9)
        }
    }

    @Test func combRepeatsEveryTooth() {
        var bath = Marbling(spacing: 10_000)
        bath.add(Contour([Vector2(0, 15), Vector2(110, 15), Vector2(55, 300)],
                         closed: true), color: .black)
        let before = bath.inks[0].shape.contours[0].points
        // Teeth every 110 along x: the first two points sit one tooth apart
        // at the same offset, so they must displace identically.
        bath.comb(through: .zero, direction: Vector2(0, 1),
                  spacing: 110, strength: 60, falloff: 20)
        let after = bath.inks[0].shape.contours[0].points
        let d0 = after[0] - before[0]
        let d1 = after[1] - before[1]
        #expect(abs(d0.x - d1.x) < 1e-9 && abs(d0.y - d1.y) < 1e-9)
        #expect(abs(d0.x) < 1e-9)   // displacement rides the tine direction
    }

    @Test func rotationalToolsPreserveRadius() {
        var bath = Marbling(spacing: 10_000)
        bath.add(square(at: Vector2(120, 0)), color: .black)
        let center = Vector2(30, -20)
        let before = bath.inks[0].shape.contours[0].points
        bath.swirl(at: center, strength: 500, falloff: 90)
        let mid = bath.inks[0].shape.contours[0].points
        for (p, q) in zip(before, mid) {
            #expect(abs(q.distance(to: center) - p.distance(to: center)) < 1e-9)
        }
        bath.tine(around: center, radius: 80, strength: 200, falloff: 30)
        let after = bath.inks[0].shape.contours[0].points
        for (p, q) in zip(mid, after) {
            #expect(abs(q.distance(to: center) - p.distance(to: center)) < 1e-9)
        }
    }

    @Test func stretchedOutlinesRefineToTheSpacing() {
        var bath = Marbling(spacing: 3)
        bath.drop(at: .zero, radius: 30, color: .black)
        // A strong nearby drop stretches the far side of the first rim.
        bath.drop(at: Vector2(25, 0), radius: 50, color: .white)
        let points = bath.inks[0].shape.contours[0].points
        #expect(points.count > 60)
        for i in points.indices {
            let next = points[(i + 1) % points.count]
            #expect(points[i].distance(to: next) <= 3 + 1e-6)
        }
    }

    @Test func floatedShapesKeepTheirHoles() {
        var bath = Marbling()
        let ring = Shape(outer: square(at: .zero, half: 50).points,
                         holes: [square(at: .zero, half: 20).points.reversed()])
        bath.add(ring, color: .black)
        bath.drop(at: Vector2(200, 0), radius: 30, color: .white)
        #expect(bath.inks[0].shape.contours.count == 2)
    }

    @Test func identicalOperationSequencesAreIdentical() {
        func marble(_ bath: inout Marbling) {
            bath.drop(at: Vector2(10, 20), radius: 40, color: .black)
            bath.drop(at: Vector2(-15, 5), radius: 30, color: .white)
            bath.tine(through: .zero, direction: Vector2(0.3, 1),
                      strength: 90, falloff: 35)
            bath.swirl(at: Vector2(5, 5), strength: 300, falloff: 80)
        }
        var a = Marbling()
        var b = Marbling()
        marble(&a)
        marble(&b)
        #expect(a == b)
    }
}
