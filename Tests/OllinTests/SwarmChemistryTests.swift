import Foundation
import Testing
import simd
import COllinShaders   // OllinSwarmChemistryParams
@testable import Ollin

/// Recipes that spread by contact. No pixel snapshot, for the reason the whole compute
/// path carries none: a neighbor sum depends on the order an atomic race produced, and a
/// run that has differed by one contact has changed who inherits from whom.
///
/// What is pinned is each piece against the run with that piece taken away: transmission
/// is the only thing that moves a recipe between particles, mutation is the only thing
/// that makes one differ from where it came from, the competition function decides which
/// recipes spread, and the conversion out of the published units is what makes a recipe
/// mean the same thing at any density.
@Suite
@MainActor
struct SwarmChemistryTests {

    // MARK: GPU-free

    @Test func paramStrideMatchesHeader() {
        // Shared CPU/GPU struct; a drift here corrupts every dispatch.
        #expect(MemoryLayout<OllinSwarmChemistryParams>.stride == 48)
    }

    @Test func aRecipeRoundTripsThroughItsEightValues() {
        // A recipe is data people write down and pass around, so the eight values have
        // to survive going out and coming back in the published order.
        let r = SwarmChemistry.Recipe(perception: 150.39, normalSpeed: 15.89, maxSpeed: 23.54,
                                      cohesion: 0.74, alignment: 0.45, separation: 62.65,
                                      randomSteering: 0.33, pace: 0.13)
        #expect(SwarmChemistry.Recipe(r.values) == r)
        #expect(r.values == [150.39, 15.89, 23.54, 0.74, 0.45, 62.65, 0.33, 0.13])
        // Anything short of eight is refused rather than filled in.
        #expect(SwarmChemistry.Recipe([1, 2, 3]) == nil)
    }

    @Test func everyLengthComesFromTheDensityRatherThanANumberAnyoneTyped() {
        // The reason the conversion exists at all. The published value ranges were
        // chosen for a world whose particles sit about fifty units apart, and they carry
        // length: separation is in length squared over step squared. What has to be held
        // constant across canvas sizes and populations is not the numbers but how many
        // others a particle can see, so this checks that figure directly and against the
        // published world's own.
        let canvas = Rectangle(x: 0, y: 0, width: 1080, height: 1080)
        func neighborsVisible(_ count: Int) -> Double {
            let sim = SwarmChemistry(count: count, bounds: canvas, kinds: 2, size: 2, seed: 1)
            return Double(count) * .pi * pow(sim.perceptionLimit, 2) / (1080 * 1080)
        }
        let sparse = neighborsVisible(1000)
        let dense = neighborsVisible(16_000)
        #expect(abs(sparse / dense - 1) < 1e-9,
                "a particle sees \(sparse) others when sparse and \(dense) when dense")
        // And it is the published world's figure: ten thousand particles over five
        // thousand units square, each seeing three hundred units around it.
        let published = 10_000 * Double.pi * pow(300, 2) / (5000 * 5000)
        #expect(abs(sparse / published - 1) < 1e-9)
    }

    @Test func theOpeningPopulationSharesAFewRecipesRatherThanOnePerParticle() {
        // The opening state is a design decision. A random recipe per particle gives
        // every particle a rule nobody else holds, and the structures this model is known
        // for are made of many particles agreeing, so there would be nothing to see and
        // nothing for a contest to be between.
        let sim = SwarmChemistry(count: 900, bounds: Rectangle(x: 0, y: 0, width: 600, height: 600),
                                 kinds: 6, size: 2, seed: 4)
        #expect(sim.openingRecipes.count == 6)
        #expect(Set(sim.openingRecipes.map(\.values.description)).count == 6,
                "the opening recipes must actually differ from each other")
        // Shared out evenly, so each line starts with a real share to defend.
        #expect(sim.snapshotLineageCounts() == [Int](repeating: 150, count: 6))
    }

    // MARK: On the GPU

    @Test(.enabled(if: Snapshot.hasMetal))
    func transmissionIsTheOnlyThingThatMovesARecipeBetweenParticles() throws {
        // With it off, every particle keeps what it opened with however much it mixes,
        // so the tally cannot move at all. With it on, it must.
        let frozen = try run { $0.transmits = false }
        #expect(frozen.tally == [Int](repeating: 200, count: 4),
                "recipes moved with transmission off: \(frozen.tally)")
        let spreading = try run { _ in }
        #expect(spreading.tally != [Int](repeating: 200, count: 4),
                "no recipe spread with transmission on")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func mutationIsTheOnlyThingThatMakesARecipeDifferFromTheOneItCameFrom() throws {
        // Transmission only ever *copies* a recipe across, so with mutation off every
        // recipe alive at the end has to be one of the opening ones, value for value.
        // That is the exact statement of what mutation is for here, and it is a stronger
        // claim than any measure of how much the population has changed.
        let copied = try run { $0.mutationRate = 0 }
        let opening = Set(copied.opening.map(Self.key))
        let unheardOf = copied.recipes.filter { !opening.contains(Self.key($0)) }
        #expect(unheardOf.isEmpty,
                "\(unheardOf.count) recipes exist that no opening recipe could have been copied into")
        // And with it on, recipes appear that were never opened with.
        let mutated = try run { $0.mutationRate = 0.5 }
        let openingMutated = Set(mutated.opening.map(Self.key))
        #expect(mutated.recipes.contains { !openingMutated.contains(Self.key($0)) },
                "mutation was on and yet nothing new appeared")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aLineIsCarriedThroughMutationSoLinesOnlyEverDieOut() throws {
        // A mutant belongs to the line it came from, which is what makes the tally a
        // contest rather than a count of how many mutations have happened. So the number
        // of lines still alive can only fall.
        let mutated = try run { $0.mutationRate = 0.5 }
        #expect(mutated.tally.reduce(0, +) == 800, "every particle must belong to some line")
        #expect(mutated.tally.filter { $0 > 0 }.count <= 4)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theCompetitionFunctionDecidesWhichRecipesSpread() throws {
        // The one knob that says what doing well even means here. Under "faster" the
        // recipes that spread are the ones whose particles are moving quickest, so the
        // population's preferred speed has to end up higher than under "slower", from the
        // same opening recipes and the same seed.
        let quick = try run { $0.competition = .faster }
        let slow = try run { $0.competition = .slower }
        let quickSpeed = quick.recipes.reduce(0) { $0 + $1.normalSpeed } / Double(quick.recipes.count)
        let slowSpeed = slow.recipes.reduce(0) { $0 + $1.normalSpeed } / Double(slow.recipes.count)
        #expect(quickSpeed > slowSpeed,
                "preferred speed \(quickSpeed) under faster against \(slowSpeed) under slower")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func everyRecipeStaysInsideItsPublishedRange() throws {
        // Mutation adds to a value rather than replacing it, so nothing but the clamp
        // stops a line walking out of range over enough copies. A perception past the
        // top of its range would quietly let one line see further than the model allows.
        let mutated = try run { $0.mutationRate = 0.9; $0.mutationAmount = 0.5 }
        for r in mutated.recipes {
            for (value, range) in zip(r.values, SwarmChemistry.Recipe.ranges) {
                #expect(value.isFinite)
                #expect(value >= range.lowerBound - 1e-4 && value <= range.upperBound + 1e-4,
                        "\(value) is outside \(range)")
            }
        }
    }

    // MARK: Harness

    /// A recipe's values as a comparable key, at the precision the GPU actually stores
    /// them in, so "came from this one untouched" means bit-for-bit and not nearly.
    private static func key(_ r: SwarmChemistry.Recipe) -> String {
        r.values.map { String(Float($0)) }.joined(separator: ",")
    }

    private struct Outcome {
        var tally: [Int]
        var recipes: [SwarmChemistry.Recipe]
        var opening: [SwarmChemistry.Recipe]
    }

    private func run(_ configure: @escaping (SwarmChemistry) -> Void) throws -> Outcome {
        let probe = ChemistryProbe()
        probe.configure = configure
        _ = OllinApp.image(of: probe, frame: probe.steps)
        let sim = try #require(probe.chem)
        return Outcome(tally: sim.snapshotLineageCounts(), recipes: sim.snapshotRecipes(),
                       opening: sim.openingRecipes)
    }
}

/// One world of 800 particles holding four opening recipes, stepped headlessly at a fixed
/// frame rate, which at the model's own rate is one step a frame.
@MainActor
private final class ChemistryProbe: Sketch {
    var chem: SwarmChemistry!
    var steps = 240
    var configure: (SwarmChemistry) -> Void = { _ in }

    override var canvasSize: CanvasSize { .square(600) }

    override func setup() {
        chem = SwarmChemistry(count: 800, bounds: bounds, kinds: 4, size: 2.5, seed: 9)
        configure(chem)
    }

    override func draw() {
        background(.black)
        updateSwarmChemistry(chem)
        drawParticles(chem)
    }
}
