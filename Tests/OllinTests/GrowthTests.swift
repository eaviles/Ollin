import Ollin
import Testing

/// Pure-CPU checks on the growth generators (space colonization and
/// diffusion-limited aggregation): structure invariants hold and a given
/// input reproduces exactly.
@Suite
struct SpaceColonizationTests {
    /// Growth marches toward a lone attractor, consumes it, and finishes.
    @Test func growsTowardAndConsumesAttractors() {
        let growth = SpaceColonization(attractors: [Vector2(200, 0)], roots: [Vector2(0, 0)],
                                       influenceRadius: 300, killRadius: 24, stepLength: 12)
        growth.grow()
        #expect(growth.isFinished)
        #expect(growth.attractors.isEmpty)
        #expect(growth.count > 10)   // it took steps to get there
        let closest = growth.nodes.map { $0.position.distance(to: Vector2(200, 0)) }.min() ?? .infinity
        #expect(closest < 24)
    }

    /// Every non-root node's parent comes earlier in the list; roots have none.
    @Test func nodesFormATree() {
        let growth = SpaceColonization(attractors: [Vector2(100, 80), Vector2(-60, 140), Vector2(40, -120)],
                                       roots: [Vector2(0, 0)],
                                       influenceRadius: 400, killRadius: 20, stepLength: 10)
        growth.grow()
        #expect(growth.nodes[0].parent == nil)
        for (i, node) in growth.nodes.enumerated().dropFirst() {
            #expect(node.parent != nil && node.parent! < i)
        }
    }

    /// An attractor beyond every node's reach is left standing, and growth
    /// still terminates.
    @Test func unreachableAttractorTerminates() {
        let growth = SpaceColonization(attractors: [Vector2(5000, 0)], roots: [.zero],
                                       influenceRadius: 100, killRadius: 24, stepLength: 12)
        growth.grow()
        #expect(growth.isFinished)
        #expect(growth.attractors.count == 1)
    }

    /// The same input grows the same structure, node for node.
    @Test func growthIsDeterministic() {
        func grown() -> [Vector2] {
            let attractors = (0 ..< 40).map { i -> Vector2 in
                let a = Double(i) * 0.7, r = 60 + Double(i % 7) * 30
                return Vector2(cos(a) * r, sin(a) * r)
            }
            let growth = SpaceColonization(attractors: attractors, roots: [.zero],
                                           influenceRadius: 150, killRadius: 18, stepLength: 9)
            growth.grow()
            return growth.nodes.map(\.position)
        }
        #expect(grown() == grown())
    }

    /// Pipe-model thickness: a parent is at least as thick as any child.
    @Test func thicknessesFollowThePipeModel() {
        let attractors = (0 ..< 30).map { i -> Vector2 in
            Vector2(cos(Double(i)) * 140, 60 + Double(i % 5) * 40)
        }
        let growth = SpaceColonization(attractors: attractors, roots: [Vector2(0, -80)],
                                       influenceRadius: 200, killRadius: 20, stepLength: 10)
        growth.grow()
        let widths = growth.thicknesses(leafWidth: 1.5)
        #expect(widths.count == growth.count)
        for (i, node) in growth.nodes.enumerated() {
            if let parent = node.parent {
                #expect(widths[parent] >= widths[i] - 1e-9)
            }
        }
    }
}

@Suite
struct DiffusionLimitedAggregationTests {
    /// Walkers keep sticking: the cluster grows by the requested count.
    @Test func clusterGrows() {
        let cluster = DiffusionLimitedAggregation(seeds: [.zero], particleRadius: 4, seed: 3)
        cluster.step(60)
        #expect(cluster.count == 61)
    }

    /// Every stuck particle touches its parent exactly (twice the radius).
    @Test func particlesTouchTheirParent() {
        let cluster = DiffusionLimitedAggregation(seeds: [.zero], particleRadius: 5, seed: 9)
        cluster.step(80)
        for particle in cluster.particles {
            guard let parent = particle.parent else { continue }
            let d = particle.position.distance(to: cluster.particles[parent].position)
            #expect(abs(d - 10) < 1e-6)
        }
    }

    /// The same seed freezes the same cluster; a different seed differs.
    @Test func clusterIsSeeded() {
        func grown(_ seed: UInt64) -> [Vector2] {
            let cluster = DiffusionLimitedAggregation(seeds: [.zero], particleRadius: 4, seed: seed)
            cluster.step(50)
            return cluster.positions
        }
        #expect(grown(7) == grown(7))
        #expect(grown(7) != grown(8))
    }

    /// A caged cluster stays inside its bounds.
    @Test func boundsCageHolds() {
        let cage = Rectangle(x: -100, y: -100, width: 200, height: 200)
        let cluster = DiffusionLimitedAggregation(seeds: [.zero], particleRadius: 4,
                                                  bounds: cage, seed: 5)
        cluster.step(80)
        for p in cluster.positions {
            #expect(p.x >= cage.x - 1e-6 && p.x <= cage.x + cage.width + 1e-6)
            #expect(p.y >= cage.y - 1e-6 && p.y <= cage.y + cage.height + 1e-6)
        }
    }
}
