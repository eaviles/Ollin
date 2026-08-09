import Foundation
import Testing
import simd
import COllinShaders   // OllinLeniaParams
@testable import Ollin

/// The energy-field particle sim. Like the rest of the compute path it carries no pixel
/// snapshot: the neighbor sort's within-cell order comes out of an atomic race, so a sum
/// over neighbors is reproducible only to float rounding, and a structure that has parted
/// company by one particle never comes back together. What is pinned instead is that each
/// term does the one thing it is in the model for, measured against the same run with
/// that term made inert.
///
/// The two force terms pull against each other on one measurable quantity, how far a
/// particle sits from its closest neighbor, so that is what both counterfactuals read.
/// Growth is the attractive term and repulsion the opposing one, and taking either away
/// moves that distance in its own direction.
@Suite
@MainActor
struct ParticleLeniaTests {

    // MARK: GPU-free

    @Test func paramStrideMatchesHeader() {
        // Shared CPU/GPU struct; a drift here corrupts every dispatch.
        #expect(MemoryLayout<OllinLeniaParams>.stride == 112)
    }

    @Test func theKernelWeightIsTheIntegralsReciprocalRatherThanATabulatedConstant() {
        // The weight is whatever makes the kernel integrate to one over the plane, and
        // the closed form is checked against a numeric integration done here, so this
        // fails if the derivation is edited into something that merely happens to give
        // 0.022 at the published pair.
        func numeric(_ mu: Double, _ sigma: Double) -> Double {
            let steps = 400_000, rmax = mu + 10 * sigma
            let h = rmax / Double(steps)
            var total = 0.0
            for i in 0...steps {
                let r = Double(i) * h
                let w = (i == 0 || i == steps) ? 0.5 : 1.0
                total += w * 2 * .pi * r * exp(-pow((r - mu) / sigma, 2))
            }
            return 1 / (total * h)
        }
        for (mu, sigma) in [(4.0, 1.0), (2.5, 0.7), (6.0, 1.8)] {
            let closed = ParticleLenia.normalization(mu, sigma)
            #expect(abs(closed / numeric(mu, sigma) - 1) < 1e-6,
                    "closed form disagrees with the integral at mu=\(mu), sigma=\(sigma)")
        }
        // And at the published pair it comes out as the number the paper prints.
        #expect(abs(ParticleLenia.normalization(4, 1) - 0.022) < 0.0005)
    }

    @Test func aWiderReachIsWorthLessPerNeighbor() {
        // The counterfactual for deriving the weight at all: if it were a constant, a
        // sketch that moved the ring outward would silently multiply its whole field,
        // and the crowding the growth function is tuned to would stop meaning anything.
        let near = ParticleLenia.normalization(3, 1)
        let far = ParticleLenia.normalization(6, 1)
        #expect(far < near, "a ring twice as far around must weigh less per neighbor")
        // Roughly in proportion to the circumference it is spread around.
        #expect(abs(near / far - 2) < 0.15)
    }

    @Test func theOpeningDiscHoldsAboutOneParticlePerUnitOfArea() {
        // The opening state is a design decision, not a detail: the model only does
        // anything where particles are inside each other's kernels. This pins the
        // density that claim rests on, in the model's own units.
        let count = 4000, spacing = 7.0
        let placed = ParticleLenia.seedPositions(count: count, center: Vector2(500, 500),
                                                 spacing: spacing, seed: 3)
        #expect(placed.count == count)
        let reach = placed.map { hypot(Double($0.x) - 500, Double($0.y) - 500) }.max() ?? 0
        let areaInModelUnits = .pi * pow(reach / spacing, 2)
        #expect(abs(Double(count) / areaInModelUnits - 1) < 0.05,
                "seeded at \(Double(count) / areaInModelUnits) particles per unit of area")
    }

    @Test func theOpeningIsReproducibleEvenThoughTheRunIsNot() {
        // Worth stating which half of this is promised. The opening scatter is ordinary
        // seeded CPU work and repeats exactly. The run does not: a step sums a field
        // over neighbors, the neighbor sort's order within a cell is settled by an
        // atomic race, and float addition is not associative, so two runs of the same
        // seed part company and stay parted. That is why this path carries no pixel
        // snapshot, and why the tests below measure what a term does rather than
        // compare frames.
        let a = ParticleLenia.seedPositions(count: 300, center: Vector2(0, 0), spacing: 5, seed: 4)
        let b = ParticleLenia.seedPositions(count: 300, center: Vector2(0, 0), spacing: 5, seed: 4)
        let c = ParticleLenia.seedPositions(count: 300, center: Vector2(0, 0), spacing: 5, seed: 5)
        #expect(a == b)
        #expect(a != c)
    }

    // MARK: On the GPU

    @Test(.enabled(if: Snapshot.hasMetal))
    func growthIsTheTermThatPullsParticlesTowardEachOther() throws {
        // Growth is the model's only attractive term, so with it made inert nothing is
        // left but a repulsion that reaches one unit, and particles must end up further
        // apart than when it is working. The counterfactual is the same run with the
        // growth peak widened until its slope is flat, which is how this model expresses
        // "no preference about crowding".
        //
        // Measured as the distance to a nearest neighbor rather than as the size of the
        // population: the opening disc is already close to the size these forces settle
        // at, so the outline barely moves in either run and reads almost the same. What
        // changes is how tightly packed it is inside.
        let held = try measure { _ in }
        let inert = try measure { $0.sigmaG = 500 }
        #expect(held.nearest < inert.nearest * 0.88,
                "nearest neighbor \(held.nearest) with growth against \(inert.nearest) without")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func repulsionIsTheTermThatKeepsThemOffEachOther() throws {
        // The opposing half, on the same measurement. Repulsion is the only term with an
        // opinion at very short range: the kernel is a ring, so two particles in the same
        // place add almost nothing to each other's field and growth is perfectly happy to
        // let them coincide.
        let held = try measure { _ in }
        let heaped = try measure { $0.cRep = 0 }
        #expect(heaped.nearest < held.nearest * 0.6,
                "nearest neighbor \(heaped.nearest) with no repulsion against \(held.nearest) with it")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func everyPositionStaysFinite() throws {
        // The step divides by a distance and by two widths, and a single non-finite
        // position would spread through the next step's field to every neighbor.
        let probe = LeniaProbe()
        probe.steps = 90
        _ = OllinApp.image(of: probe, frame: probe.steps)
        let final = try #require(probe.finalPositions)
        #expect(final.count == LeniaProbe.population)
        #expect(final.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }

    // MARK: Harness

    private struct Shape {
        /// Mean distance to a particle's closest neighbor: how tightly the population is
        /// packed, which is the quantity both force terms act on.
        var nearest: Double
    }

    private func measure(_ configure: @escaping (ParticleLenia) -> Void) throws -> Shape {
        let probe = LeniaProbe()
        probe.configure = configure
        _ = OllinApp.image(of: probe, frame: probe.steps)
        let final = try #require(probe.finalPositions)
        var nearest = 0.0
        for i in final.indices {
            var best = Double.infinity
            for j in final.indices where j != i {
                let d = hypot(Double(final[i].x - final[j].x), Double(final[i].y - final[j].y))
                if d < best { best = d }
            }
            nearest += best
        }
        return Shape(nearest: nearest / Double(final.count))
    }
}

/// One population in a 600×600 world, stepped headlessly at a fixed frame rate. The pace
/// is set so one frame is exactly one *published* step, because that is the unit the
/// model's behavior is described in: at the default pace a frame is a sixth of one, and
/// a couple of hundred frames would show almost nothing happening.
@MainActor
private final class LeniaProbe: Sketch {
    static let population = 800
    var lenia: ParticleLenia!
    var steps = 300
    var seed: UInt64 = 11
    var configure: (ParticleLenia) -> Void = { _ in }
    /// Read one frame behind the last step, since a frame's dispatches run at render
    /// time rather than when `draw()` records them.
    var finalPositions: [SIMD2<Float>]?

    override var canvasSize: CanvasSize { .square(600) }

    override func setup() {
        lenia = ParticleLenia(count: LeniaProbe.population, bounds: bounds,
                              spacing: 7, seed: seed)
        // The published step per frame, at the headless driver's fixed 60 a second.
        lenia.speed = lenia.maxStep * 60
        configure(lenia)
    }

    override func draw() {
        background(.black)
        if frameCount >= steps, finalPositions == nil {
            finalPositions = lenia.current.snapshot()?.map(\.position)
        }
        updateParticleLenia(lenia)
        drawParticles(lenia)
    }
}
