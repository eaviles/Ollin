import Foundation
import Testing
import simd
import COllinShaders   // OllinSPHParams, OllinSoftBody, OllinSoftBodyParams
@testable import Ollin

/// The GPU particle fluid and soft bodies. Like the artificial-life sims they share
/// the `SpatialHash` with, their neighbor sums are GPU-race-ordered and the systems
/// are chaotic, so these tests check only order-independent, macroscopic facts:
/// struct layouts, the seeded derivations, that the fluid stays finite and inside
/// its box, that a blob coheres, and that an isolated body conserves momentum (the
/// regression net for the rest-centroid bug, where mis-centered rest offsets made
/// every body silently thrust itself around).
@Suite
@MainActor
struct FluidDynamicsTests {

    // MARK: GPU-free: layout & derivations

    @Test func paramStridesMatchHeader() {
        // Shared CPU/GPU structs; a drift here corrupts every dispatch.
        #expect(MemoryLayout<OllinSPHParams>.stride == 112)
        #expect(MemoryLayout<OllinSoftBodyParams>.stride == 64)
        #expect(MemoryLayout<OllinSoftBody>.stride == 32)
    }

    @Test func latticeDensityScalesWithPacking() {
        let loose = ParticleFluid.latticeDensity(radius: 12, spacing: 6)
        let dense = ParticleFluid.latticeDensity(radius: 12, spacing: 3)
        #expect(loose.density > 0 && loose.near > 0)
        #expect(dense.density > loose.density)   // tighter packing reads denser
        #expect(dense.near > loose.near)
    }

    @Test func fluidDerivations() {
        let box = Rectangle(x: 0, y: 0, width: 400, height: 400)
        let fluid = ParticleFluid(count: 500, bounds: box, radius: 16, seed: 3)
        #expect(fluid.count == 500)
        #expect(fluid.spacing == 16 * 0.45)
        #expect(fluid.bounds.width == 400)
    }

    @Test func softBodyDerivations() {
        let box = Rectangle(x: 0, y: 0, width: 500, height: 500)
        let blobs = SoftBodies(bodies: 3, bounds: box, radius: 60, seed: 5)
        #expect(blobs.bodies == 3)
        #expect(blobs.count > 3)   // each blob carries a lattice of particles
        #expect(blobs.spacing > 0 && blobs.spacing < 60)
    }

    // MARK: Metal-gated: macroscopic behavior

    @Test(.enabled(if: Snapshot.hasMetal))
    func fluidStaysFiniteAndBoxed() throws {
        let probe = FluidProbe()
        _ = OllinApp.image(of: probe, frame: 40)
        guard let ps = probe.fluid.current.snapshot() else {
            Issue.record("fluid never realized"); return
        }
        let box = probe.box
        #expect(ps.allSatisfy {
            $0.position.x.isFinite && $0.position.y.isFinite &&
            $0.velocity.x.isFinite && $0.velocity.y.isFinite
        })
        let tolerance: Float = 1
        #expect(ps.allSatisfy {
            $0.position.x >= Float(box.x) - tolerance &&
            $0.position.x <= Float(box.x + box.width) + tolerance &&
            $0.position.y >= Float(box.y) - tolerance &&
            $0.position.y <= Float(box.y + box.height) + tolerance
        })
        // Pressure keeps the fluid a fluid: it spreads, never collapses to a clump.
        let xs = ps.map(\.position.x)
        #expect((xs.max()! - xs.min()!) > Float(box.width) / 4)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func softBodiesCohere() throws {
        let probe = SoftBodyProbe()
        _ = OllinApp.image(of: probe, frame: 60)
        guard let ps = probe.blobs.current.snapshot() else {
            Issue.record("soft bodies never realized"); return
        }
        #expect(ps.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite })

        // Group particles by their body tag and check each body stayed a blob:
        // every particle within a couple of rest radii of its own centroid.
        var groups: [Int: [SIMD2<Float>]] = [:]
        for p in ps { groups[Int(p.life + 0.5), default: []].append(p.position) }
        #expect(groups.count == 3)
        let maxRest = Float(60 * 1.15)
        for (_, points) in groups {
            let cm = points.reduce(SIMD2<Float>.zero, +) / Float(points.count)
            let worst = points.map { simd_length($0 - cm) }.max() ?? 0
            #expect(worst < maxRest * 2.2)
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func isolatedBodyConservesMomentum() throws {
        // One blob, gravity off, touching nothing: the shape-match pull must sum
        // to zero, so its centroid stays put. (This is the regression test for the
        // rest-offset centering: offsets taken about anything but the rest
        // centroid give the body a permanent self-thrust.)
        let probe = DriftProbe()
        _ = OllinApp.image(of: probe, frame: 60)
        guard let ps = probe.blobs.current.snapshot() else {
            Issue.record("soft bodies never realized"); return
        }
        let cm = ps.map(\.position).reduce(SIMD2<Float>.zero, +) / Float(ps.count)
        let drift = simd_length(cm - probe.startCenter)
        #expect(drift < 5, "isolated body drifted \(drift) pt with no external force")
    }
}

@MainActor
private final class FluidProbe: Sketch {
    let box = Rectangle(x: 40, y: 40, width: 400, height: 400)
    var fluid: ParticleFluid!
    override func setup() {
        fluid = ParticleFluid(count: 1_500, bounds: box, radius: 16, seed: 7)
    }
    override func draw() { updateParticleFluid(fluid) }
}

@MainActor
private final class SoftBodyProbe: Sketch {
    var blobs: SoftBodies!
    override func setup() {
        blobs = SoftBodies(bodies: 3, bounds: Rectangle(x: 0, y: 0, width: 500, height: 500),
                           radius: 60, seed: 5)
    }
    override func draw() { updateSoftBodies(blobs) }
}

@MainActor
private final class DriftProbe: Sketch {
    var blobs: SoftBodies!
    var startCenter: SIMD2<Float> {
        let c = blobs.seededCenters[0]   // rest offsets are centroid-centered, so
        return SIMD2<Float>(Float(c.x), Float(c.y))   // the seeded centroid is exact
    }
    override func setup() {
        blobs = SoftBodies(bodies: 1, bounds: Rectangle(x: 0, y: 0, width: 600, height: 600),
                           radius: 70, seed: 9)
        blobs.gravity = Vector2(0, 0)
    }
    override func draw() { updateSoftBodies(blobs) }
}
