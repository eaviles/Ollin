import Ollin
import Testing

/// Pure-geometry checks on the Voronoi/Delaunay tessellation — no GPU, so these
/// run everywhere (including CI). The load-bearing property is that Voronoi cells
/// *partition* their bounds: every cell contains its own site, and the cells'
/// areas sum to the bounds area (no gaps, no overlaps).
@Suite
struct TessellationTests {
    private let bounds = Rectangle(x: 0, y: 0, width: 100, height: 100)

    /// A generic, non-degenerate scatter of sites inside `bounds`.
    private let sites = [
        Vector2(20, 25), Vector2(70, 18), Vector2(55, 60), Vector2(15, 80),
        Vector2(85, 82), Vector2(45, 40), Vector2(30, 55), Vector2(78, 48),
    ]

    private func polygonArea(_ pts: [Vector2]) -> Double {
        guard pts.count >= 3 else { return 0 }
        var sum = 0.0
        for i in pts.indices {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    /// Point-in-convex-polygon, winding-agnostic (every edge cross has one sign).
    private func convexContains(_ poly: [Vector2], _ p: Vector2) -> Bool {
        guard poly.count >= 3 else { return false }
        var positive = false, negative = false
        for i in poly.indices {
            let a = poly[i], b = poly[(i + 1) % poly.count]
            let cross = (b - a).cross(p - a)
            if cross > 1e-9 { positive = true }
            if cross < -1e-9 { negative = true }
        }
        return !(positive && negative)
    }

    private func cellPoints(_ shape: Shape) -> [Vector2] { shape.contours.first?.points ?? [] }

    // MARK: - Delaunay

    @Test func squareTriangulatesIntoTwoTrianglesCoveringIt() {
        let d = Delaunay([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
        #expect(d.triangles.count == 2)
        let area = d.triangles.map(\.area).reduce(0, +)
        #expect(abs(area - 100) < 1e-6)
    }

    @Test func collinearPointsYieldNoTriangles() {
        let d = Delaunay([Vector2(0, 0), Vector2(1, 1), Vector2(2, 2), Vector2(3, 3)])
        #expect(d.triangles.isEmpty)
    }

    @Test func coincidentPointsDoNotCorruptTheMesh() {
        // A duplicate site is skipped at insertion, leaving a valid triangulation.
        let d = Delaunay([Vector2(0, 0), Vector2(10, 0), Vector2(5, 8), Vector2(5, 8)])
        let area = d.triangles.map(\.area).reduce(0, +)
        #expect(abs(area - 40) < 1e-6)   // the single non-degenerate triangle
    }

    @Test func indicesComeOutInCanonicalOrder() {
        // The Bowyer-Watson refan iterates a Dictionary, so the raw triangle
        // order is process-varying; the public `indices` promise a canonical
        // form instead: each triple starts at its smallest index, winds with
        // non-negative signed area in canvas space, and the list is sorted.
        // (Same-process rebuilds share the Dictionary seed, so the real-world
        // symptom is cross-run churn; the canonical form is checkable here.)
        let d = Delaunay(sites)
        var previous: (Int, Int, Int)? = nil
        var i = 0
        while i + 2 < d.indices.count {
            let (a, b, c) = (d.indices[i], d.indices[i + 1], d.indices[i + 2])
            #expect(a < b && a < c, "triple should lead with its smallest index")
            let cross = (d.points[b] - d.points[a]).cross(d.points[c] - d.points[a])
            #expect(cross >= 0, "triple should wind with non-negative area")
            if let p = previous {
                #expect(p < (a, b, c), "triples should be sorted")
            }
            previous = (a, b, c)
            i += 3
        }
        #expect(previous != nil)
    }

    @Test func triangleCircumcirclePassesThroughEveryCorner() {
        let t = Triangle(Vector2(0, 0), Vector2(4, 0), Vector2(0, 3))
        let circle = t.circumcircle
        for corner in t.points {
            #expect(abs(circle.center.distance(to: corner) - circle.radius) < 1e-6)
        }
    }

    // MARK: - Voronoi

    @Test func cellsAreOnePerSiteAndNonDegenerate() {
        let v = Voronoi(sites: sites, bounds: bounds)
        #expect(v.cells.count == sites.count)
        for cell in v.cells { #expect(cellPoints(cell).count >= 3) }
    }

    @Test func eachCellContainsItsSite() {
        let v = Voronoi(sites: sites, bounds: bounds)
        for i in sites.indices {
            #expect(convexContains(cellPoints(v.cells[i]), sites[i]), "cell \(i) should contain its site")
        }
    }

    @Test func cellsPartitionTheBounds() {
        // The strong correctness pin: a Voronoi diagram clipped to a box tiles it
        // exactly, so the cell areas sum to the box area (no gaps, no overlaps).
        let v = Voronoi(sites: sites, bounds: bounds)
        let total = v.cells.map { polygonArea(cellPoints($0)) }.reduce(0, +)
        #expect(abs(total - bounds.width * bounds.height) < 1e-3, "total cell area \(total)")
    }

    @Test func twoSitesSplitTheBoxInHalf() {
        let v = Voronoi(sites: [Vector2(25, 50), Vector2(75, 50)], bounds: bounds)
        for cell in v.cells {
            #expect(abs(polygonArea(cellPoints(cell)) - 5000) < 1e-3)
        }
    }

    @Test func singleSiteFillsTheWholeBounds() {
        let v = Voronoi(sites: [Vector2(40, 60)], bounds: bounds)
        #expect(abs(polygonArea(cellPoints(v.cells[0])) - 10000) < 1e-3)
    }

    // MARK: - Lloyd relaxation

    @Test func lloydKeepsSitesInsideBounds() {
        let relaxed = Voronoi(sites: sites, bounds: bounds).relaxed(iterations: 5)
        #expect(relaxed.count == sites.count)
        for p in relaxed {
            #expect(p.x >= -1e-9 && p.x <= 100 + 1e-9 && p.y >= -1e-9 && p.y <= 100 + 1e-9)
        }
    }

    @Test func lloydMovesSitesTowardTheirCentroids() {
        let before = Voronoi(sites: sites, bounds: bounds)
        let beforeResidual = sites.indices
            .map { sites[$0].distance(to: before.centroid($0)) }.reduce(0, +)
        let relaxed = before.relaxed(iterations: 8)
        let after = Voronoi(sites: relaxed, bounds: bounds)
        let afterResidual = relaxed.indices
            .map { relaxed[$0].distance(to: after.centroid($0)) }.reduce(0, +)
        #expect(afterResidual < beforeResidual, "Lloyd should reduce site-to-centroid distance")
    }
}
