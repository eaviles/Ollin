import Foundation
import Testing
import simd
import COllinShaders   // OllinEvolutionParams
@testable import Ollin

/// The GPU population. Like the other systems on the compute path there is no pixel
/// snapshot: a hair of difference in one flight changes which individual wins a
/// tournament, and two populations that disagree by one tournament have parted company
/// for good. What is pinned instead is that each piece of the mechanism does the one
/// thing it is there for, measured against the counterfactual of the same run with that
/// piece taken away: selection makes a population better, mutation is what lets it keep
/// getting better, a wall costs a flight most of its score, an arrival beats every near
/// miss, and the pace is derived from the distance rather than named.
@Suite
@MainActor
struct EvolutionTests {

    // MARK: GPU-free

    @Test func paramStrideMatchesHeader() {
        // Shared CPU/GPU struct; a drift here corrupts every dispatch.
        #expect(MemoryLayout<OllinEvolutionParams>.stride == 272)
    }

    @Test func theDerivedPaceComesFromTheDistance() {
        let near = Evolution(count: 8, genes: 4,
                             start: Vector2(0, 0), target: Vector2(0, 200), seed: 1)
        let far = Evolution(count: 8, genes: 4,
                            start: Vector2(0, 0), target: Vector2(0, 800), seed: 1)
        // Four times the distance, four times the speed: both cross in the same two
        // seconds, which is what makes one set of numbers work at any canvas size.
        #expect(abs(far.resolvedMaxSpeed / near.resolvedMaxSpeed - 4) < 1e-9)
        #expect(abs(far.resolvedTrialDuration - near.resolvedTrialDuration) < 1e-9)
        // And moving the target re-derives rather than leaving the old pace in place.
        near.target = Vector2(0, 800)
        #expect(abs(near.resolvedMaxSpeed - far.resolvedMaxSpeed) < 1e-9)
    }

    @Test func aTargetOnTheStartIsSurvivedRatherThanDividedBy() {
        // Nothing promises a sketch will not put both points in the same place, and
        // every derived figure is a ratio of that distance: one non-finite number here
        // would spread to the speed, the trial, the thrust, and the score ramp at once.
        let stuck = Evolution(count: 4, genes: 4,
                              start: Vector2(50, 50), target: Vector2(50, 50), seed: 1)
        #expect(stuck.spanToTarget > 0)
        #expect(stuck.resolvedMaxSpeed.isFinite && stuck.resolvedMaxSpeed > 0)
        #expect(stuck.resolvedTrialDuration.isFinite && stuck.resolvedTrialDuration > 0)
        #expect(stuck.resolvedThrust.isFinite)
        #expect(stuck.progress.isFinite)
    }

    @Test func explicitPacingOverridesTheDerivedOne() {
        let run = Evolution(count: 4, genes: 4,
                            start: .zero, target: Vector2(0, 400), seed: 1)
        run.maxSpeed = 37
        run.trialDuration = 9
        run.thrust = 5
        #expect(run.resolvedMaxSpeed == 37)
        #expect(run.resolvedTrialDuration == 9)
        #expect(run.resolvedThrust == 5)
    }

    @Test func theOpeningGenerationIsArcsRatherThanARandomWalk() {
        // A genome of independent random impulses is a random walk, whose steps cancel:
        // every individual would mill about the start and selection would have nothing
        // to work with. The opening genomes are smooth arcs instead, which is a claim
        // about the *sum* of a genome, not about any one gene.
        let genes = 24, count = 400
        let seeded = Evolution.seedGenomes(count: count, genes: genes, seed: 5)
        #expect(seeded.count == count * genes)
        var travelled = 0.0, walked = 0.0
        for i in 0..<count {
            let own = Array(seeded[(i * genes)..<((i + 1) * genes)])
            travelled += Double(simd_length(own.reduce(SIMD2<Float>.zero, +)))
            walked += Double(own.map { simd_length($0) }.reduce(0, +))
        }
        // An arc keeps about half its length as displacement, against the fifth a walk
        // keeps (n independent steps hold on to about 1/sqrt(n) of theirs). It is not
        // more than half because the genomes are allowed to curl right round, which is
        // the whole point of them: a route past a wall is a curl.
        var rng = SplitMix64(seed: 5)
        var walkTravelled = 0.0, walkWalked = 0.0
        for _ in 0..<count {
            var sum = SIMD2<Float>.zero, length = 0.0
            for _ in 0..<genes {
                let a = Double.random(in: 0..<(2 * .pi), using: &rng)
                let step = SIMD2<Float>(Float(cos(a)), Float(sin(a)))
                sum += step
                length += 1
            }
            walkTravelled += Double(simd_length(sum))
            walkWalked += length
        }
        #expect(travelled / walked > 0.4,
                "opening genomes travelled \(travelled / walked) of their own length")
        #expect(travelled / walked > (walkTravelled / walkWalked) * 2.2,
                "arcs \(travelled / walked) against a random walk's \(walkTravelled / walkWalked)")
    }

    // MARK: Metal-gated: the mechanism against its counterfactuals

    @Test(.enabled(if: Snapshot.hasMetal))
    func selectionMakesThePopulationBetter() throws {
        // The whole claim of the tier, and the counterfactual is the same run with
        // selection removed: a tournament of one is a parent picked at random, which
        // is breeding with no selection in it at all.
        let evolved = try run(generations: 14) { _ in }
        let drifting = try run(generations: 14) { $0.tournament = 1 }
        let evolvedFirst = try #require(evolved.first)
        let evolvedLast = try #require(evolved.last)
        let driftingLast = try #require(drifting.last)

        #expect(evolvedLast.mean > evolvedFirst.mean * 1.5,
                "mean went \(evolvedFirst.mean) to \(evolvedLast.mean) over 14 generations")
        #expect(evolvedLast.mean > driftingLast.mean * 1.5,
                "selected \(evolvedLast.mean) vs unselected \(driftingLast.mean)")
        #expect(evolvedLast.closest < evolvedFirst.closest,
                "closest approach went \(evolvedFirst.closest) to \(evolvedLast.closest)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aStrongerTournamentSelectsHarder() throws {
        // Tournament size is the selection-pressure dial, so more rivals must move the
        // population along faster over the same number of generations.
        let gentle = try #require(try run(generations: 8) { $0.tournament = 2 }.last)
        let fierce = try #require(try run(generations: 8) { $0.tournament = 12 }.last)
        #expect(fierce.mean > gentle.mean,
                "tournament 12 reached \(fierce.mean), tournament 2 reached \(gentle.mean)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func mutationIsTheOnlySourceOfSomethingNew() throws {
        // Selection can only choose among what is there, and crossover only shuffles
        // genes between parents, copying each one across untouched. So with mutation
        // off, every gene alive after any number of generations has to be one that
        // generation 0 already held, bit for bit. That is the exact statement of what
        // mutation is for, and it is why a run without it can only narrow.
        //
        // (Improving is the wrong thing to measure over a short run: two thousand
        // individuals hold enough variety in generation 0 that selection alone climbs
        // just as fast for the first dozen generations. What mutation buys is the
        // ground past that, which costs far longer than a test should run.)
        let opening = Set(Evolution.seedGenomes(count: EvolutionProbe.population,
                                                genes: EvolutionProbe.genes, seed: 7))
        let frozen = try genomes(generations: 8) { $0.mutationRate = 0 }
        let mutating = try genomes(generations: 8) { _ in }

        #expect(frozen.allSatisfy { opening.contains($0) },
                "a gene appeared out of nowhere in a run with mutation off")
        let fresh = mutating.filter { !opening.contains($0) }.count
        #expect(fresh > mutating.count / 20,
                "mutation produced only \(fresh) new genes out of \(mutating.count)")
        // And the narrowing that follows: with nothing new arriving, copying whittles
        // the population down toward the few genomes that won.
        #expect(distinct(frozen) < distinct(mutating) / 2,
                "frozen kept \(distinct(frozen)) distinct genes, mutating \(distinct(mutating))")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aWallCostsAFlightMostOfItsScore() throws {
        // The same population, twice, differing only in whether the wall it is flying
        // into is there. A crash keeps a tenth of what it had earned, so the walled run
        // must score far worse without any of the other numbers changing.
        let wall = Rectangle(x: 0, y: 260, width: 600, height: 40)
        let open = try #require(try run(generations: 3) { _ in }.last)
        let blocked = try #require(try run(generations: 3) { $0.obstacles = [wall] }.last)
        #expect(blocked.mean < open.mean * 0.5,
                "walled run scored \(blocked.mean) against \(open.mean) in the open")
        #expect(blocked.closest > open.closest,
                "walled run got to \(blocked.closest), open run to \(open.closest)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func anArrivalOutscoresEveryNearMiss() throws {
        // The two bands must not overlap: anything that got there scores over 2, and
        // nothing that missed can reach 1, whatever it did. Otherwise a population that
        // has found the target can still be out-bred by one that has not.
        let probe = EvolutionProbe()
        probe.generations = 10
        probe.targetRadius = 60
        _ = OllinApp.image(of: probe, frame: probe.framesNeeded)
        let state = try #require(probe.run.current.snapshot())
        let arrived = state.filter { $0.seedB >= 2 }
        let missed = state.filter { $0.seedB < 2 }
        #expect(!arrived.isEmpty, "nobody reached the target in ten generations")
        #expect(missed.allSatisfy { $0.seedB <= 1.0001 },
                "a near miss scored \(missed.map(\.seedB).max() ?? 0), into the arrival band")
        // Arriving sooner is worth more, which is what turns a population that has
        // found the target toward finding the quick way to it.
        #expect(arrived.contains { $0.seedB > 2.0001 })
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aGenerationIsBredWhenTheTrialIsUpRatherThanEveryNFrames() throws {
        // Generations have to fall on the *clock*, so the same run at a different frame
        // rate breeds at the same moments. What that means frame by frame is that the
        // gaps between breedings are all one length, and that length is the trial.
        let probe = EvolutionProbe()
        probe.generations = 5
        _ = OllinApp.image(of: probe, frame: probe.framesNeeded)
        let bred = probe.bredAtFrame
        #expect(bred.count >= 4, "only \(bred.count) generations in \(probe.framesNeeded) frames")
        let gaps = Set(zip(bred.dropFirst(), bred).map { $0 - $1 })
        #expect(gaps.count == 1, "generations came \(gaps.sorted()) frames apart")
        // One frame of slack: the trial ends part way through a frame, and the breeding
        // pass takes the frame after it.
        let expected = Int((probe.run.resolvedTrialDuration * 60).rounded())
        #expect(abs((gaps.first ?? 0) - expected) <= 2,
                "generations came \(gaps.first ?? 0) frames apart, trial is \(expected)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func everyFlightStaysFiniteAndEveryGenomeStaysInRange() throws {
        // Mutation adds to a gene rather than replacing it, so nothing but the clamp
        // stops a lineage walking out of range over enough generations. A gene past 1
        // would quietly make one lineage push harder than any other could.
        let probe = EvolutionProbe()
        probe.generations = 12
        probe.configure = { $0.mutationRate = 1; $0.mutationAmount = 2 }
        _ = OllinApp.image(of: probe, frame: probe.framesNeeded)
        let genes = try #require(probe.run.currentGenes.snapshot())
        #expect(genes.allSatisfy { $0.x >= -1 && $0.x <= 1 && $0.y >= -1 && $0.y <= 1 },
                "a gene escaped the range genes are defined over")
        let state = try #require(probe.run.current.snapshot())
        #expect(state.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite })
        #expect(state.allSatisfy { $0.seedB.isFinite && $0.seedB >= 0 })
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aRunRepeatsFromItsSeedAndTwoSeedsDiffer() throws {
        // What a sketch relies on: the same seed gives the same run back. Compared gene
        // by gene rather than by the summary, because two runs can easily hold the same
        // average and not the same population. Nothing here is promised across GPUs, and
        // the seed reaches a run twice over (the opening genomes and the breeding
        // stream), so this pins the whole chain rather than either half of it.
        let a = try genomes(generations: 6, seed: 4242) { _ in }
        let b = try genomes(generations: 6, seed: 4242) { _ in }
        let c = try genomes(generations: 6, seed: 99) { _ in }
        #expect(a == b, "the same seed gave two different populations")
        #expect(a != c, "two seeds gave the same population")
        // And the reports agree, which is what the readout promises.
        let ra = try #require(try run(generations: 4, seed: 4242) { _ in }.last)
        let rb = try #require(try run(generations: 4, seed: 4242) { _ in }.last)
        #expect(ra == rb, "the same seed reported \(ra) and then \(rb)")
    }

    // MARK: Measurements

    private func distinct(_ genes: [SIMD2<Float>]) -> Int { Set(genes).count }

    /// The genomes a run holds after `generations` generations.
    private func genomes(generations: Int, seed: UInt64 = 7,
                         _ configure: @escaping (Evolution) -> Void) throws -> [SIMD2<Float>] {
        let probe = EvolutionProbe()
        probe.generations = generations
        probe.seed = seed
        probe.configure = configure
        _ = OllinApp.image(of: probe, frame: probe.framesNeeded)
        return try #require(probe.run.currentGenes.snapshot())
    }

    // MARK: Driving

    /// Run a population for `generations` generations and hand back what each one
    /// managed, so a test can compare a run against its counterfactual.
    private func run(generations: Int, seed: UInt64 = 7,
                     _ configure: @escaping (Evolution) -> Void) throws -> [Evolution.Report] {
        let probe = EvolutionProbe()
        probe.generations = generations
        probe.seed = seed
        probe.configure = configure
        _ = OllinApp.image(of: probe, frame: probe.framesNeeded)
        return probe.reports
    }
}

/// One population in a 600×600 world, flying bottom to top, stepped headlessly at a
/// fixed frame rate so a trial takes the same number of steps every run.
@MainActor
private final class EvolutionProbe: Sketch {
    var run: Evolution!
    var reports: [Evolution.Report] = []
    // Set by the test before the headless run; `Sketch` owns `init()`, so the probe is
    // configured by assignment rather than by a custom initializer.
    static let population = 2000
    static let genes = 20
    var generations = 8
    var seed: UInt64 = 7
    var targetRadius = 30.0
    var configure: (Evolution) -> Void = { _ in }
    /// The frame each generation was bred on, for the pacing test.
    var bredAtFrame: [Int] = []

    override var canvasSize: CanvasSize { .square(600) }

    /// A trial is 1.7 crossings long and the headless driver runs at 60 frames a
    /// second, so a generation is about 100 frames at the doubled speed the probe uses.
    /// Rounded up generously rather than derived exactly: the count is a budget, and a
    /// test that computes it to the frame is testing its own arithmetic.
    var framesNeeded: Int { generations * 110 + 8 }

    override func setup() {
        run = Evolution(count: EvolutionProbe.population, genes: EvolutionProbe.genes,
                        start: Vector2(300, 560), target: Vector2(300, 60), seed: seed)
        // Twice the derived speed, so a trial is half as many frames and a test that
        // watches sixteen generations does not have to render five thousand of them.
        // The trial length still follows from it, so the flights are the same shape.
        run.maxSpeed = 500
        run.targetRadius = targetRadius
        run.measuresGenerations = true
        configure(run)
    }

    override func draw() {
        background(.black)
        let before = run.generation
        updateEvolution(run)
        if run.generation > before {
            bredAtFrame.append(frameCount)
            if let report = run.lastGeneration { reports.append(report) }
        }
        drawParticles(run)
    }
}
