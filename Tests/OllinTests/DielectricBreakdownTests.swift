import Foundation
import Ollin
import Testing

/// Dielectric-breakdown invariants: seeded determinism, lattice-adjacent
/// parent links, the eta regime (higher exponent reaches further on the same
/// budget), arcing to ground, and the branch decomposition covering every
/// grown edge exactly once.
@Suite struct DielectricBreakdownTests {
    private let frame = Rectangle(x: 0, y: 0, width: 240, height: 240)

    private func bolt(eta: Double, seed: UInt64 = 7,
                      maxSites: Int = 220) -> DielectricBreakdown {
        DielectricBreakdown(seeds: [frame.center], in: frame, resolution: 60,
                            eta: eta, maxSites: maxSites, seed: seed)
    }

    /// The same seed grows the same figure, site for site.
    @Test func seededGrowthReproduces() {
        let a = bolt(eta: 1.7), b = bolt(eta: 1.7)
        a.step(150); b.step(150)
        #expect(a.count == b.count)
        for (x, y) in zip(a.sites, b.sites) {
            #expect(x.position == y.position && x.parent == y.parent)
        }
    }

    /// Every grown site attaches to an already-grown lattice neighbor: the
    /// parent came earlier, and sits exactly one cell away on an axis.
    @Test func sitesAttachToLatticeNeighbors() {
        let a = bolt(eta: 1.5)
        a.step(120)
        let cell = frame.width / 60
        for (i, site) in a.sites.enumerated() {
            guard let parent = site.parent else { continue }
            #expect(parent < i)
            let d = site.position - a.sites[parent].position
            #expect(abs(min(abs(d.x), abs(d.y))) < 1e-9)
            #expect(abs(max(abs(d.x), abs(d.y)) - cell) < 1e-9)
        }
    }

    /// The exponent picks the regime: on the same site budget, a high-eta
    /// discharge reaches much further from the seed than a low-eta bush
    /// (the field's favorites win harder, so growth is directed instead of
    /// even). Deterministic for these seeds.
    @Test func higherEtaReachesFurther() {
        let bush = bolt(eta: 0.4, seed: 11)
        let spark = bolt(eta: 3.0, seed: 11)
        bush.step(200); spark.step(200)
        func reach(_ d: DielectricBreakdown) -> Double {
            d.positions.map { $0.distance(to: frame.center) }.max() ?? 0
        }
        #expect(reach(spark) > reach(bush) * 1.5)
    }

    /// Left to run, the discharge arcs to the border ground and finishes,
    /// with its furthest site beside the rim.
    @Test func theArcReachesGround() {
        let a = bolt(eta: 2.0, maxSites: 4000)
        a.grow()
        #expect(a.isFinished)
        let cell = frame.width / 60
        let reach = a.positions.map { $0.distance(to: frame.center) }.max() ?? 0
        #expect(reach > frame.width / 2 - 3 * cell)
    }

    /// The branch decomposition covers every grown edge exactly once: the
    /// channel polylines' segment counts sum to the edge count, and every
    /// channel is an open polyline at least one segment long.
    @Test func branchesCoverEveryEdgeOnce() {
        let a = bolt(eta: 1.2)
        a.step(150)
        let channels = a.branches()
        let edges = a.sites.filter { $0.parent != nil }.count
        let covered = channels.reduce(0) { $0 + $1.points.count - 1 }
        #expect(covered == edges)
        #expect(channels.allSatisfy { !$0.isClosed && $0.points.count >= 2 })
    }

    /// The read-back field behaves like a potential: exactly 0 on the
    /// discharge, near 1 beside the border ground, strictly between
    /// elsewhere, and 0 outside the bounds.
    @Test func theFieldReadsBack() {
        let a = bolt(eta: 1.7)
        a.step(80)
        for p in a.positions {
            #expect(a.potential(at: p) == 0)
        }
        let nearRim = a.potential(at: Vector2(frame.width - 6, frame.height / 2))
        #expect(nearRim > 0.9)
        let between = a.potential(at: Vector2(frame.width * 0.3, frame.height * 0.3))
        #expect(between > 0 && between < 1)
        #expect(a.potential(at: Vector2(-10, -10)) == 0)
    }

    /// The pipe-model widths thicken toward the seed: a parent is never
    /// thinner than any of its children, and tips carry the tip width.
    @Test func thicknessesGrowTowardTheSeed() {
        let a = bolt(eta: 1.7)
        a.step(150)
        let widths = a.thicknesses(tipWidth: 1.2)
        var hasChild = [Bool](repeating: false, count: a.count)
        for (i, site) in a.sites.enumerated() {
            if let parent = site.parent {
                #expect(widths[parent] >= widths[i] - 1e-9)
                hasChild[parent] = true
            }
        }
        for (i, isParent) in hasChild.enumerated() where !isParent {
            #expect(abs(widths[i] - 1.2) < 1e-9)
        }
    }
}
