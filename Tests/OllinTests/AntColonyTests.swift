import Foundation
import Ollin
import Testing

/// Ant-colony invariants: seeded determinism, tours as true permutations, a
/// best that never worsens, convergence on an easy ring, and the normalized
/// trail read-back.
@Suite struct AntColonyTests {

    private func ring(_ count: Int, radius: Double = 100) -> [Vector2] {
        (0..<count).map { Vector2(angle: Double($0) / Double(count) * .tau,
                                  length: radius) }
    }

    /// The same seed searches the same way, iteration for iteration.
    @Test func seededSearchReproduces() {
        let a = AntColony(cities: ring(14), seed: 9)
        let b = AntColony(cities: ring(14), seed: 9)
        a.step(6); b.step(6)
        #expect(a.bestTour == b.bestTour)
        #expect(a.bestLength == b.bestLength)
        #expect(a.stepCount == 6)
    }

    /// Every best tour is a true permutation: each city exactly once.
    @Test func toursVisitEveryCityOnce() {
        let colony = AntColony(cities: ring(17), seed: 3)
        colony.step(4)
        #expect(colony.bestTour.count == 17)
        #expect(Set(colony.bestTour) == Set(0..<17))
    }

    /// The best-so-far never worsens as the search runs.
    @Test func theBestNeverWorsens() {
        let colony = AntColony(cities: ring(12, radius: 80), seed: 5)
        var last = Double.infinity
        for _ in 0..<10 {
            colony.step()
            #expect(colony.bestLength <= last + 1e-12)
            last = colony.bestLength
        }
    }

    /// On a ring of cities the shortest tour is the ring itself, and the
    /// colony finds it (within a hair) in a few iterations.
    @Test func theColonySolvesARing() {
        let cities = ring(16, radius: 120)
        let perimeter = 16 * (cities[0].distance(to: cities[1]))
        let colony = AntColony(cities: cities, seed: 7)
        colony.step(20)
        #expect(colony.bestLength < perimeter * 1.02)
    }

    /// The trail read-back is normalized and symmetric: strengths peak at 1,
    /// none exceeds it, and the pairwise read matches either order.
    @Test func trailsReadBackNormalized() {
        let colony = AntColony(cities: ring(10), seed: 1)
        colony.step(5)
        let trails = colony.trails
        #expect(!trails.isEmpty)
        #expect(trails.allSatisfy { $0.strength > 0 && $0.strength <= 1 + 1e-12 })
        #expect(abs((trails.map(\.strength).max() ?? 0) - 1) < 1e-12)
        #expect(colony.pheromone(between: 2, and: 7) == colony.pheromone(between: 7, and: 2))
    }

    /// Degenerate colonies stay calm: one city has nothing to tour.
    @Test func degenerateColoniesAreCalm() {
        let colony = AntColony(cities: [Vector2(5, 5)], seed: 0)
        colony.step(3)
        #expect(colony.bestTour.isEmpty && colony.stepCount == 0)
    }
}
