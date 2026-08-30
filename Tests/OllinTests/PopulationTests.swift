import Foundation
import Testing
@testable import Ollin

/// Breeding by hand: the interactive half of evolution, which is all CPU values and so
/// is pinned exactly rather than statistically. Each rule is measured against the
/// counterfactual of the same population with that rule turned off, since almost
/// everything here is a claim about a *difference* (a chosen genome survives where an
/// unchosen one does not, a high score wins where a flat one does not).
@Suite
struct PopulationTests {

    // MARK: Genomes

    @Test func aGeneIsAlwaysBetweenZeroAndOne() {
        // A gene is read through mappings that assume the range, so anything outside it
        // would land a value outside whatever a sketch asked for.
        let g = Genome([-3, 0.25, 17, 1])
        #expect(g.genes == [0, 0.25, 1, 1])
    }

    @Test func theMappingsCoverTheirRangeAndBothEnds() {
        let low = Genome([0, 0, 0, 0])
        let high = Genome([1, 1, 1, 1])
        #expect(low.value(0, in: 20 ... 180) == 20)
        #expect(high.value(0, in: 20 ... 180) == 180)
        // A whole-number range has to reach both ends, or the last choice is unreachable
        // and a sketch quietly never draws it.
        #expect(low.value(0, in: 3 ... 9) == 3)
        #expect(high.value(0, in: 3 ... 9) == 9)
        #expect(Genome([0.5]).value(0, in: 0 ... 10) == 5)
        #expect(low.value(0, among: ["a", "b", "c"]) == "a")
        #expect(high.value(0, among: ["a", "b", "c"]) == "c")
        #expect(low.isSet(0) && !high.isSet(0))
    }

    @Test func everyWholeNumberInARangeIsReachable() {
        // The mapping divides 0…1 evenly, so no value in the range may be skipped and
        // none may take a wider slice than another.
        var seen = Set<Int>()
        for i in 0...1000 {
            seen.insert(Genome([Double(i) / 1000]).value(0, in: 3 ... 9))
        }
        #expect(seen == Set(3...9))
    }

    @Test func aGenePastTheEndWrapsRatherThanTrapping() {
        let g = Genome([0.1, 0.2, 0.3])
        #expect(g[3] == g[0])
        #expect(g[-1] == g[2])
        #expect(g[7] == g[1])
    }

    // MARK: The population

    @Test func aSeedReproducesAPopulationAndTwoSeedsDiffer() {
        let a = Population(count: 12, genes: 5, seed: 99)
        let b = Population(count: 12, genes: 5, seed: 99)
        let c = Population(count: 12, genes: 5, seed: 100)
        #expect(a.genomes == b.genomes)
        #expect(a.genomes != c.genomes)
        // And the whole chain reproduces, not just the opening: breeding runs on the
        // population's own stream, so the same seed breeds the same children.
        var x = a, y = b
        x.breed(from: [0, 3])
        y.breed(from: [0, 3])
        #expect(x.genomes == y.genomes)
    }

    @Test @MainActor func breedingNeverTouchesTheSketchRandom() {
        // The halton rule: a population owns its own stream, so adding one to a sketch
        // cannot shift any of the sketch's other rolls.
        // Both sketches pinned to one seed first: an unseeded `Sketch` rolls its own
        // `variation`, so two of them would differ before a population was anywhere near.
        let plain = RollingSketch()
        let breeding = RollingSketch()
        plain.seed(1234)
        breeding.seed(1234)
        var pool = Population(count: 8, genes: 4, seed: 3)

        var expected: [Double] = [], actual: [Double] = []
        for _ in 0..<20 {
            expected.append(plain.random(0, 1))
            actual.append(breeding.random(0, 1))
            pool.breed(from: [1, 2])
        }
        #expect(expected == actual)
    }

    @Test func choosingNothingChangesNothing() {
        // A generation nobody liked is still the only generation there is, so an empty
        // pick has to be a no-op rather than a reroll or a crash.
        var pool = Population(count: 8, genes: 4, seed: 1)
        let before = pool.genomes
        pool.breed(from: [])
        #expect(pool.genomes == before)
        #expect(pool.generation == 0)
        // Out-of-range picks are the same case, not an index error.
        pool.breed(from: [99, -4])
        #expect(pool.genomes == before)
    }

    @Test func aChosenGenomeSurvivesBeingChosen() {
        // With twenty candidates and a person judging, one breeding is a big step: the
        // thing you just picked must not be gone the moment you pick it. The
        // counterfactual is the same breeding with that guarantee switched off.
        var kept = Population(count: 10, genes: 6, seed: 8)
        kept.mutationRate = 1                     // mutate everything, so only the
        kept.mutationAmount = 1                   // carried parents can come through
        var lost = kept
        lost.keepsParents = false

        let favorite = kept[4]
        kept.breed(from: [4])
        lost.breed(from: [4])
        #expect(kept.genomes.contains(favorite), "the picked genome did not survive")
        #expect(!lost.genomes.contains(favorite), "it survived even with keepsParents off")
    }

    @Test func mutationIsWhatMakesAChildDifferFromItsParent() {
        // One parent, no mutation: every child is that parent exactly, because crossing
        // a genome with itself can only give it back. That is what makes mutation the
        // whole source of variation in the one-parent case.
        var copying = Population(count: 10, genes: 6, seed: 2)
        copying.mutationRate = 0
        let parent = copying[7]
        copying.breed(from: [7])
        #expect(copying.genomes.allSatisfy { $0 == parent })

        var mutating = Population(count: 10, genes: 6, seed: 2)
        mutating.mutationRate = 0.5
        mutating.keepsParents = false
        mutating.breed(from: [7])
        #expect(mutating.genomes.contains { $0 != parent })
    }

    @Test func theThreeMixesMixDifferently() {
        // Independent and split both *copy* genes, so every gene in a child is one of
        // its parents' exactly; blend makes new values in between. Getting this wrong is
        // invisible in a picture and total in a search. Every child is bred from the same
        // two genomes, all zeros against all ones, so where a gene came from is readable
        // straight off its value.
        let independent = children(mixedBy: .independent)
        let split = children(mixedBy: .split)
        let blended = children(mixedBy: .blend)

        for (kind, brood) in [("independent", independent), ("split", split)] {
            #expect(brood.allSatisfy { $0.genes.allSatisfy { $0 == 0 || $0 == 1 } },
                    "\(kind) invented a gene value neither parent held")
        }
        // Split keeps a run together: every gene from one parent comes before every gene
        // from the other, which is the whole difference from independent. Independent
        // must therefore cross back and forth somewhere in the brood.
        #expect(split.allSatisfy { crossings(in: $0) <= 1 },
                "split crossed over \(split.map(crossings).max() ?? 0) times")
        #expect(independent.contains { crossings(in: $0) > 1 },
                "independent never crossed more than once, which is split's behavior")
        // Blend mixes the whole genome by one amount, so a blended child is flat, and
        // some of them land between the parents rather than on one.
        #expect(blended.allSatisfy { Set($0.genes).count == 1 },
                "blend mixed each gene by a different amount")
        #expect(blended.contains { $0.genes.allSatisfy { $0 > 0.001 && $0 < 0.999 } },
                "blend always landed on a parent rather than between them")
    }

    // MARK: Scoring

    @Test func theWheelFavorsWhoeverScoresWell() {
        // Scored breeding against its counterfactual: the same population bred on a flat
        // score, where nothing is better than anything and the mean must simply drift.
        var climbing = Population(count: 60, genes: 3, seed: 12)
        var flat = climbing
        let opening = climbing.map { $0[0] }.reduce(0, +) / 60

        for _ in 0..<25 {
            climbing.breed { $0[0] }        // gene 0 is worth exactly itself
            flat.breed { _ in 1 }
        }
        let climbed = climbing.map { $0[0] }.reduce(0, +) / 60
        let drifted = flat.map { $0[0] }.reduce(0, +) / 60
        #expect(climbed > opening + 0.25,
                "gene 0 went \(opening) to \(climbed) under selection")
        #expect(climbed > drifted + 0.2,
                "selected \(climbed) against an unselected \(drifted)")
    }

    @Test func aScoreOfZeroEverywhereStillPicksEvenly() {
        // Nothing to choose between is a real state at the start of a search, and the
        // wheel divides by the total, so this is where a naive one freezes on genome 0
        // or divides by nothing at all.
        var pool = Population(count: 20, genes: 4, seed: 6)
        pool.mutationRate = 0
        let openingGenes = Set(pool.genomes.flatMap(\.genes))
        pool.breed { _ in 0 }
        // Children are recombinations, so it is the genes that must all be accounted
        // for: with mutation off nothing new can appear, whatever the scores said.
        #expect(pool.genomes.flatMap(\.genes).allSatisfy { openingGenes.contains($0) })
        #expect(Set(pool.genomes).count > 1, "a flat score collapsed onto one genome")
    }

    @Test func aScoreBelowZeroCountsAsNoScore() {
        // A share of the parents cannot be negative, and one negative score would
        // otherwise drag the total down and hand a *worse* genome a bigger slice.
        var pool = Population(count: 40, genes: 2, seed: 4)
        pool.mutationRate = 0
        pool.breed { $0[0] > 0.5 ? 1 : -1000 }
        #expect(pool.genomes.allSatisfy { $0[0] > 0.5 },
                "a genome scoring below zero was still bred from")
    }

    @Test func rerollingReplacesEverythingAndCountsAsAGeneration() {
        var pool = Population(count: 8, genes: 4, seed: 5)
        let before = pool.genomes
        pool.reroll()
        #expect(pool.genomes != before)
        #expect(pool.count == 8)
        #expect(pool.generation == 1)
    }

    @Test func breedingKeepsTheSizeAndTheGeneCount() {
        var pool = Population(count: 9, genes: 7, seed: 5)
        for _ in 0..<5 { pool.breed(from: [0, 1, 2]) }
        #expect(pool.count == 9)
        #expect(pool.genomes.allSatisfy { $0.count == 7 })
        #expect(pool.genomes.allSatisfy { $0.genes.allSatisfy { $0 >= 0 && $0 <= 1 } })
        #expect(pool.generation == 5)
    }

    // MARK: Helpers

    /// A brood bred from all-zeros against all-ones under one mixing, with mutation off
    /// so the mixing is the only thing that moved a gene.
    private func children(mixedBy kind: Population.Crossover) -> [Genome] {
        let mum = Genome([Double](repeating: 0, count: 8))
        let dad = Genome([Double](repeating: 1, count: 8))
        var pool = Population((0..<40).map { $0.isMultiple(of: 2) ? mum : dad }, seed: 77)
        pool.mutationRate = 0
        pool.keepsParents = false
        pool.crossover = kind
        pool.breed(from: 0..<40)
        return pool.genomes
    }

    /// How many times a genome switches parent as you read along it: 0 or 1 for a split,
    /// more for gene-by-gene mixing.
    private func crossings(in genome: Genome) -> Int {
        zip(genome.genes, genome.genes.dropFirst()).filter { $0 != $1 }.count
    }
}

/// A sketch that does nothing but roll, for the rule that a population's breeding must
/// never reach into `random`.
@MainActor private final class RollingSketch: Sketch {}
