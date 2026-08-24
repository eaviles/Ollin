import Foundation
import Ollin
import Testing

/// Laws for the power diagram. The definition is one comparison ("which site has
/// the least power here"), so the tests ask the polygons to agree with that
/// comparison, and ask the cells to behave the way the definition forces them to.
@Suite
struct PowerDiagramTests {
    private let box = Rectangle(x: 0, y: 0, width: 400, height: 300)

    private func scatter(_ count: Int, seed: UInt64, weighted: Bool = true) -> [WeightedSite] {
        var rng = SplitMix64(seed: seed)
        return (0 ..< count).map { _ in
            WeightedSite(Vector2(Double.random(in: 20 ... 380, using: &rng),
                                 Double.random(in: 20 ... 280, using: &rng)),
                         weight: weighted ? Double.random(in: 0 ... 4000, using: &rng) : 0)
        }
    }

    /// The law the diagram is defined by, asked at a grid of points: whichever cell
    /// holds a point, that cell's site has the least power there.
    @Test func everyPointBelongsToTheSiteWithTheLeastPower() {
        let sites = scatter(14, seed: 4)
        let diagram = PowerDiagram(sites: sites, bounds: box)

        for row in 0 ..< 30 {
            for column in 0 ..< 40 {
                let point = Vector2(5 + Double(column) * 9.9, 4 + Double(row) * 9.9)
                guard let owner = diagram.site(owning: point) else { continue }
                // The polygon that claims the point has to be the owner's, and the
                // owner's has to claim it.
                #expect(diagram.cells[owner].contains(point),
                        "\(point) belongs to site \(owner) but is not in its cell")
                for i in sites.indices where i != owner {
                    let power = sites[i].power(to: point)
                    if power > sites[owner].power(to: point) + 1e-6 {
                        #expect(!diagram.cells[i].contains(point),
                                "\(point) is in cell \(i), which is not its owner")
                    }
                }
            }
        }
    }

    /// With every weight the same, the power diagram is the plain Voronoi diagram.
    /// Checked against the shipped one, which is built a completely different way
    /// (a Delaunay triangulation and its dual).
    @Test func equalWeightsGiveThePlainVoronoiDiagram() {
        let sites = scatter(18, seed: 9, weighted: false)
        let points = sites.map(\.point)
        let power = PowerDiagram(sites: sites, bounds: box)
        let voronoi = Voronoi(sites: points, bounds: box)

        for row in 0 ..< 24 {
            for column in 0 ..< 32 {
                let point = Vector2(7 + Double(column) * 12.3, 6 + Double(row) * 12.2)
                let inPower = sites.indices.filter { power.cells[$0].contains(point) }
                let inVoronoi = sites.indices.filter { voronoi.cells[$0].contains(point) }
                // Skip the hairline where a point sits on a shared edge and the two
                // constructions can round it either way.
                guard inPower.count == 1, inVoronoi.count == 1 else { continue }
                #expect(inPower == inVoronoi, "\(point) landed in different cells")
            }
        }
    }

    /// Only the differences between weights matter, so lifting every weight by the
    /// same amount cannot move a single edge.
    @Test func addingTheSameWeightToEverySiteChangesNothing() {
        let sites = scatter(12, seed: 21)
        let lifted = sites.map { WeightedSite($0.point, weight: $0.weight + 1234.5) }
        let before = PowerDiagram(sites: sites, bounds: box)
        let after = PowerDiagram(sites: lifted, bounds: box)

        for i in sites.indices {
            let a = before.cells[i].contours.flatMap(\.points)
            let b = after.cells[i].contours.flatMap(\.points)
            #expect(a.count == b.count, "cell \(i) changed shape")
            for (p, q) in zip(a, b) {
                #expect(p.distance(to: q) < 1e-9, "cell \(i) moved")
            }
        }
    }

    /// Every cell is convex, which is what makes the diagram a diagram rather than
    /// a pile of regions: each one is a stack of half-plane cuts.
    @Test func everyCellIsConvex() {
        let diagram = PowerDiagram(sites: scatter(16, seed: 33), bounds: box)
        for (index, cell) in diagram.cells.enumerated() {
            for contour in cell.contours {
                let points = contour.points
                guard points.count >= 3 else { continue }
                var positive = 0, negative = 0
                for i in points.indices {
                    let a = points[i]
                    let b = points[(i + 1) % points.count]
                    let c = points[(i + 2) % points.count]
                    let turn = (b - a).cross(c - b)
                    if turn > 1e-9 { positive += 1 }
                    if turn < -1e-9 { negative += 1 }
                }
                #expect(positive == 0 || negative == 0, "cell \(index) turns both ways")
            }
        }
    }

    /// The cells tile the region: nothing is claimed twice and nothing is left out,
    /// so the areas have to add up to the area of the bounds.
    @Test func theCellsTileTheWholeRegion() {
        for seed in UInt64(1) ... 6 {
            let diagram = PowerDiagram(sites: scatter(11, seed: seed), bounds: box)
            let total = diagram.cells.reduce(0.0) { sum, cell in
                sum + cell.contours.reduce(0.0) { $0 + abs(signedArea($1.points)) }
            }
            #expect(abs(total - box.width * box.height) < 1e-6,
                    "seed \(seed) covered \(total) of \(box.width * box.height)")
        }
    }

    /// A site can lose everything, which a plain Voronoi diagram never allows. A
    /// small circle inside a much larger one is the everyday case.
    @Test func aSwallowedSiteGetsNoCellAtAll() {
        let big = Circle(center: Vector2(200, 150), radius: 120)
        let small = Circle(center: Vector2(210, 150), radius: 2)
        let diagram = PowerDiagram(sites: [big, small].map(WeightedSite.init), bounds: box)
        #expect(diagram.cells[1].contours.isEmpty)
        #expect(!diagram.cells[0].contours.isEmpty)
        // And the survivor takes the whole region.
        let area = diagram.cells[0].contours.reduce(0.0) { $0 + abs(signedArea($1.points)) }
        #expect(abs(area - box.width * box.height) < 1e-6)
    }

    /// The reason the square of the radius is the weighting worth having: a circle
    /// that touches no other lies inside its own cell, every point of it.
    @Test func aCircleThatTouchesNoOtherLiesInsideItsOwnCell() {
        // One pair is deliberately lopsided and nearly touching. Sizes that differ
        // are what the weighting is for, and a weight applied the wrong way round
        // moves the boundary into the big circle, which even sizes never show.
        let circles = [Circle(center: Vector2(110, 150), radius: 90),
                       Circle(center: Vector2(215, 150), radius: 12),
                       Circle(center: Vector2(300, 70), radius: 40),
                       Circle(center: Vector2(320, 220), radius: 55)]
        // The circles have to be apart for the claim to hold at all.
        for i in circles.indices {
            for j in (i + 1) ..< circles.count {
                let gap = circles[i].center.distance(to: circles[j].center)
                #expect(gap > circles[i].radius + circles[j].radius, "\(i) and \(j) overlap")
            }
        }

        let diagram = PowerDiagram(sites: circles.map(WeightedSite.init), bounds: box)
        for (index, circle) in circles.enumerated() {
            for step in 0 ..< 36 {
                let angle = Double(step) / 36 * .tau
                let onRim = circle.center + Vector2(angle: angle, length: circle.radius * 0.999)
                #expect(diagram.cells[index].contains(onRim),
                        "circle \(index) leaves its cell at \(onRim)")
            }
        }
    }

    /// Nothing to divide, nothing to hand back.
    @Test func noSitesMakeNoCells() {
        #expect(PowerDiagram(sites: [], bounds: box).cells.isEmpty)
        #expect(PowerDiagram(sites: [WeightedSite(Vector2(10, 10))], bounds: box).cells.count == 1)
    }

    private func signedArea(_ points: [Vector2]) -> Double {
        guard points.count >= 3 else { return 0 }
        var total = 0.0
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            total += a.x * b.y - b.x * a.y
        }
        return total / 2
    }
}
