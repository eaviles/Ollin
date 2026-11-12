import Testing
@testable import Ollin

/// A seed is any `Int`. A negative one builds the simulation, builds it the
/// same way twice, and builds another than its neighbor does. The seeding
/// functions take a seed as its bit pattern, and one that converts that
/// pattern through a signed integer again traps on every seed below zero.
@Suite
@MainActor
struct SimSeedTests {
    nonisolated static let below = UInt64(bitPattern: Int64(-1))
    nonisolated static let neighbor = UInt64(bitPattern: Int64(-2))

    @Test func aNegativeSeedOpensAGenePool() {
        let once = Evolution.seedGenomes(count: 12, genes: 5, seed: Self.below)
        #expect(once.count == 60)
        #expect(once == Evolution.seedGenomes(count: 12, genes: 5, seed: Self.below))
        #expect(once != Evolution.seedGenomes(count: 12, genes: 5, seed: Self.neighbor))
    }

    @Test func aNegativeSeedPlacesTheLeniaParticles() {
        let once = ParticleLenia.seedPositions(count: 30, center: Vector2(32, 32), spacing: 2.5, seed: Self.below)
        #expect(once.count == 30)
        #expect(once == ParticleLenia.seedPositions(count: 30, center: Vector2(32, 32), spacing: 2.5, seed: Self.below))
        #expect(once != ParticleLenia.seedPositions(count: 30, center: Vector2(32, 32), spacing: 2.5,
                                                    seed: Self.neighbor))
    }

    /// The same seeds through the calls a sketch writes, the rule matrix of
    /// particle life included, which is only built on the GPU's side.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aNegativeSeedBuildsEachSimulationFromASketch() throws {
        let sketch = Seeded()
        _ = try OllinApp.image(of: sketch, frame: 0)
        #expect(sketch.built == 3)
    }
}

@MainActor
private final class Seeded: Sketch {
    var built = 0

    override var canvasSize: CanvasSize { .square(64) }

    override func setup() {
        _ = makeEvolution(count: 16, genes: 4, from: Vector2(8, 8), to: Vector2(50, 50), seed: -1)
        built += 1
        let life = makeParticleLife(count: 24, kinds: 3, radius: 8, seed: -7)
        life.randomizeMatrix(seed: .min)
        built += 1
        _ = makeParticleLenia(count: 20, spacing: 2.5, seed: -5)
        built += 1
    }
}
