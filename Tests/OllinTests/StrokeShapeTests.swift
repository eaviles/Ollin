import Ollin
import Testing

/// Pure-geometry checks on stroke-as-shape (`stroked(width:join:cap:)`) and
/// the convex hull.
@Suite
struct StrokeShapeTests {
    /// The signed area of a shape's region: outers and holes are oppositely
    /// wound, so summing shoelace areas gives the net covered area.
    private func area(of shape: Shape) -> Double {
        var total = 0.0
        for contour in shape.contours where contour.isClosed {
            let pts = contour.points
            var a = 0.0
            for i in pts.indices {
                let p = pts[i], q = pts[(i + 1) % pts.count]
                a += p.x * q.y - q.x * p.y
            }
            total += a / 2
        }
        return abs(total)
    }

    /// A straight open line stroked with butt caps covers length × width.
    @Test func straightStrokeArea() {
        let line = Contour([Vector2(0, 0), Vector2(200, 0)], closed: false)
        let stroke = line.stroked(width: 20, cap: .butt)
        #expect(!stroke.contours.isEmpty)
        #expect(abs(area(of: stroke) - 4000) < 40)   // 200 × 20, within 1%
    }

    /// Round caps add roughly a disk (two half circles) to the butt area;
    /// square caps add a square (width × width).
    @Test func capsAddTheirArea() {
        let line = Contour([Vector2(0, 0), Vector2(200, 0)], closed: false)
        let butt = area(of: line.stroked(width: 20, cap: .butt))
        let round = area(of: line.stroked(width: 20, cap: .round))
        let square = area(of: line.stroked(width: 20, cap: .square))
        #expect(abs((round - butt) - .pi * 100) < 12)   // π r², r = 10
        #expect(abs((square - butt) - 400) < 8)          // 20 × 20
    }

    /// A closed contour's stroke is a band: an outer boundary plus a hole,
    /// with the area of the ring between the two offsets.
    @Test func closedStrokeIsABand() {
        let square = Contour([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)],
                             closed: true)
        let band = square.stroked(width: 10, join: .miter)
        #expect(band.contours.count == 2)
        // Outer 110×110 minus inner 90×90.
        #expect(abs(area(of: band) - (110 * 110 - 90 * 90)) < 30)
    }

    /// Overlapping strokes in one shape merge into a single region.
    @Test func overlappingStrokesMerge() {
        let cross = Shape(contours: [
            Contour([Vector2(-100, 0), Vector2(100, 0)], closed: false),
            Contour([Vector2(0, -100), Vector2(0, 100)], closed: false),
        ], winding: .nonZero)
        let stroke = cross.stroked(width: 20, cap: .butt)
        // Two 200×20 bars minus the shared 20×20 middle.
        #expect(abs(area(of: stroke) - (4000 + 4000 - 400)) < 60)
    }

    /// A stroke region feeds the booleans like any other shape.
    @Test func strokeFeedsBooleans() {
        let line = Contour([Vector2(0, 50), Vector2(200, 50)], closed: false)
        let stroke = line.stroked(width: 30, cap: .butt)
        let block = Shape(contours: [Contour([Vector2(80, 0), Vector2(120, 0),
                                              Vector2(120, 100), Vector2(80, 100)], closed: true)],
                          winding: .nonZero)
        let cut = stroke.subtracting(block)
        // The block removes a 40 × 30 bite from the middle.
        #expect(abs(area(of: cut) - (6000 - 1200)) < 60)
    }
}

@Suite
struct ConvexHullTests {
    /// The hull of a square plus interior points is exactly the four corners.
    @Test func hullFindsTheCorners() {
        let corners = [Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)]
        let inside = [Vector2(50, 50), Vector2(20, 70), Vector2(80, 30)]
        let hull = convexHull(of: corners + inside)
        #expect(hull.count == 4)
        #expect(Set(hull.map { "\($0.x),\($0.y)" }) == Set(corners.map { "\($0.x),\($0.y)" }))
    }

    /// Collinear edge points are dropped; duplicates don't confuse it.
    @Test func hullDropsCollinearAndDuplicates() {
        let points = [Vector2(0, 0), Vector2(50, 0), Vector2(100, 0), Vector2(100, 100),
                      Vector2(0, 0), Vector2(0, 100), Vector2(50, 100)]
        let hull = convexHull(of: points)
        #expect(hull.count == 4)
    }

    /// Every input point sits inside or on the hull (convexity check via
    /// consistent turn signs along the boundary).
    @Test func hullIsConvexAndContainsAll() {
        var rng = SplitMix64(seed: 9)
        let points = (0 ..< 200).map { _ in
            Vector2(Double.random(in: 0 ..< 400, using: &rng),
                    Double.random(in: 0 ..< 400, using: &rng))
        }
        let hull = convexHull(of: points)
        #expect(hull.count >= 3)

        // All turns along the hull agree in sign.
        var signs = Set<Bool>()
        for i in hull.indices {
            let a = hull[i], b = hull[(i + 1) % hull.count], c = hull[(i + 2) % hull.count]
            let turn = (b - a).cross(c - a)
            if abs(turn) > 1e-9 { signs.insert(turn > 0) }
        }
        #expect(signs.count == 1)

        // Every point is on the inner side of every hull edge.
        let inwardSign = signs.first ?? true
        for p in points {
            for i in hull.indices {
                let a = hull[i], b = hull[(i + 1) % hull.count]
                let side = (b - a).cross(p - a)
                #expect(inwardSign ? side >= -1e-9 : side <= 1e-9)
            }
        }
    }

    /// Degenerate inputs return what there is.
    @Test func hullHandlesTinyInputs() {
        #expect(convexHull(of: []).isEmpty)
        #expect(convexHull(of: [Vector2(5, 5)]).count == 1)
        #expect(convexHull(of: [Vector2(5, 5), Vector2(5, 5)]).count == 1)
        #expect(convexHull(of: [Vector2(0, 0), Vector2(10, 0)]).count == 2)
    }
}
