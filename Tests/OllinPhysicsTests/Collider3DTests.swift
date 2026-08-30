import Foundation
import Testing
import Ollin
@testable import OllinPhysics

/// Correctness for the wider collider catalog: compound bodies carry the
/// mass and balance of their whole assembly, offset parts pose their shapes,
/// tapered shapes weigh and rest as their geometry says, a `Heightfield`
/// collider traces the same surface its mesh draws, and a loaded `Scene`
/// becomes static scenery in one call. Behavioral (the no-pixel-snapshot
/// policy for physics), each knob pinned against a counterfactual twin where
/// one exists; parallel-safe like the rigid-body suite.
struct Collider3DTests {

    func run(_ world: World3D, steps: Int, dt: Double = 1.0 / 60) {
        for _ in 0 ..< steps { world.advance(by: dt) }
    }

    // MARK: Compound bodies

    @Test func compoundMassIsTheSumOfItsParts() {
        let world = World3D()
        let pair = world.addBody(.compound([
            .part(.box(width: 1, height: 1, depth: 1), at: Vector3(-1, 0, 0)),
            .part(.box(width: 1, height: 1, depth: 1), at: Vector3(1, 0, 0)),
        ]), at: Vector3(0, 5, 0))

        // Two unit boxes of the default material: 2 m³ at 1000 kg/m³.
        #expect(abs(pair.mass - 2000) < 1)

        // A part's own density multiplies the body's.
        let weighted = world.addBody(.compound([
            .part(.box(width: 1, height: 1, depth: 1), at: Vector3(-1, 0, 0)),
            .part(.box(width: 1, height: 1, depth: 1), at: Vector3(1, 0, 0),
                  density: 4),
        ]), at: Vector3(6, 5, 0))
        #expect(abs(weighted.mass - 5000) < 1)
    }

    /// The Windmill proof, distilled: a two-box bar hinged at its middle. With
    /// equal part densities it balances; make one end heavy and the assembly's
    /// center of mass moves off the pivot, so gravity tips it. A welded pair
    /// of separate bodies can fake the pose but the compound carries the true
    /// mass properties in one body.
    @Test func compoundBalanceFollowsPartDensity() {
        func makeBar(endDensity: Double) -> (World3D, Joint3D) {
            let world = World3D()
            let anchor = world.addBody(.sphere(radius: 0.1), at: Vector3(0, 5, 0),
                                       kind: .static)
            let bar = world.addBody(.compound([
                .part(.box(width: 1, height: 0.2, depth: 0.2), at: Vector3(-0.8, 0, 0)),
                .part(.box(width: 1, height: 0.2, depth: 0.2), at: Vector3(0.8, 0, 0),
                      density: endDensity),
            ]), at: Vector3(0, 5, 0))
            let hinge = world.connect(anchor, bar,
                                      .revolute(at: Vector3(0, 5, 0), axis: .unitZ))
            return (world, hinge)
        }

        let (balanced, level) = makeBar(endDensity: 1)
        run(balanced, steps: 90)
        #expect(abs(level.angle) < 0.02)

        let (lopsided, tipped) = makeBar(endDensity: 8)
        run(lopsided, steps: 90)
        // The heavy +x end swings down: a negative turn about the +z hinge.
        #expect(tipped.angle < -0.15)
    }

    @Test func anOffsetPartPosesItsShape() {
        let world = World3D()
        world.ground = 0
        // One sphere held a unit below the body's origin: the origin should
        // come to rest a unit above the resting sphere.
        let body = world.addBody(.compound([
            .part(.sphere(radius: 0.5), at: Vector3(0, -1, 0)),
        ]), at: Vector3(0, 3, 0))

        run(world, steps: 240)
        #expect(abs(body.position.y - 1.5) < 0.05)
    }

    @Test func aRotatedPartPosesItsShape() {
        let world = World3D()
        world.ground = 0
        // A tall box turned onto its side inside the compound: it rests at
        // half its *width*, not half its height.
        let body = world.addBody(.compound([
            .part(.box(width: 0.4, height: 2, depth: 0.4),
                  rotated: .pi / 2, axis: .unitZ),
        ]), at: Vector3(0, 3, 0))

        run(world, steps: 240)
        #expect(abs(body.position.y - 0.2) < 0.05)
    }

    // MARK: Tapered shapes

    @Test func aConeWeighsAThirdOfItsCylinder() {
        let world = World3D()
        let cone = world.addBody(.cone(height: 1, radius: 0.5),
                                 at: Vector3(0, 5, 0))
        let cylinder = world.addBody(.cylinder(height: 1, radius: 0.5),
                                     at: Vector3(3, 5, 0))
        #expect(abs(cone.mass / cylinder.mass - 1.0 / 3) < 0.01)
    }

    @Test func aTaperedCapsuleWeighsBetweenItsBoundingCapsules() {
        let world = World3D()
        let thin = world.addBody(.capsule(height: 1, radius: 0.2),
                                 at: Vector3(-3, 5, 0))
        let tapered = world.addBody(.taperedCapsule(height: 1, topRadius: 0.2,
                                                    bottomRadius: 0.4),
                                    at: Vector3(0, 5, 0))
        let fat = world.addBody(.capsule(height: 1, radius: 0.4),
                                at: Vector3(3, 5, 0))
        #expect(thin.mass < tapered.mass)
        #expect(tapered.mass < fat.mass)
    }

    @Test func anUprightConeRestsOnItsBase() {
        let world = World3D()
        world.ground = 0
        let cone = world.addBody(.cone(height: 1, radius: 0.4),
                                 at: Vector3(0, 2, 0))
        run(world, steps: 300)
        #expect(abs(cone.position.y - 0.5) < 0.05)
    }

    // MARK: Heightfield terrain

    @Test func aBallRestsOnAFlatHeightfieldAtItsLevel() {
        let world = World3D()
        let plateau = Heightfield(columns: 33, rows: 33, repeating: 0.5)
        world.addBody(.heightfield(plateau, width: 8, depth: 8, height: 2),
                      at: .zero, kind: .static)
        // Surface at 0.5 · 2 = 1; the ball's center rests a radius above it,
        // away from the middle so the extent mapping is exercised too.
        let ball = world.addBody(.sphere(radius: 0.3), at: Vector3(1.4, 3, -2.1))

        run(world, steps: 300)
        #expect(abs(ball.position.y - 1.3) < 0.05)
        // The landing nudges the sphere into a slow roll it has no rolling
        // friction to shed, so the lateral bound is loose; it stays near the
        // drop (a mis-mapped surface would slide it away or off the field)
        // and, above all, exactly on the level.
        #expect(abs(ball.position.x - 1.4) < 0.6)
        #expect(abs(ball.position.z + 2.1) < 0.6)
    }

    @Test func aNonSquareFieldResamplesOntoItsSquareGrid() {
        let world = World3D()
        // 200 × 50 source samples; the collider must still trace level ground.
        let strip = Heightfield(columns: 200, rows: 50, repeating: 0.25)
        world.addBody(.heightfield(strip, width: 10, depth: 4, height: 2),
                      at: .zero, kind: .static)
        let ball = world.addBody(.sphere(radius: 0.3), at: Vector3(-3.2, 3, 0.9))

        run(world, steps: 300)
        #expect(abs(ball.position.y - 0.8) < 0.05)
    }

    @Test func aBallRollsToTheBottomOfABowl() {
        let world = World3D()
        let bowl = Heightfield(columns: 65, rows: 65) { u, v in
            0.1 + 2 * ((u - 0.5) * (u - 0.5) + (v - 0.5) * (v - 0.5))
        }
        world.addBody(.heightfield(bowl, width: 8, depth: 8, height: 2),
                      at: .zero, kind: .static, friction: 0.2)
        let ball = world.addBody(.sphere(radius: 0.25), at: Vector3(1.5, 2, -1),
                                 friction: 0.2)

        run(world, steps: 900)
        // Rolled into the middle and settled at the bowl's floor.
        #expect(ball.position.x * ball.position.x
                + ball.position.z * ball.position.z < 0.3)
        #expect(abs(ball.position.y - (0.1 * 2 + 0.25)) < 0.1)
    }

    @Test func beyondTheFieldEdgeThereIsNothing() {
        let world = World3D()
        let plateau = Heightfield(columns: 33, rows: 33, repeating: 0.5)
        world.addBody(.heightfield(plateau, width: 8, depth: 8, height: 2),
                      at: .zero, kind: .static)
        // Past the half-width: no terrain, no ground, a long fall.
        let ball = world.addBody(.sphere(radius: 0.3), at: Vector3(5.5, 3, 0))

        run(world, steps: 240)
        #expect(ball.position.y < -5)
    }

    @Test func aDynamicHeightfieldBodyIsPinned() {
        let world = World3D()
        let field = Heightfield(columns: 9, rows: 9, repeating: 0.5)
        let terrain = world.addBody(.heightfield(field, width: 4, depth: 4, height: 1),
                                    at: Vector3(0, 2, 0))   // asked dynamic

        run(world, steps: 120)
        #expect(abs(terrain.position.y - 2) < 1e-4)
        #expect(terrain.mass == 0)
    }

    @Test func heightfieldSampleCountsCoverTheSourceGrid() {
        #expect(Collider3D.heightfieldSamples(
            for: Heightfield(columns: 257, rows: 257, repeating: 0)) == 256)
        #expect(Collider3D.heightfieldSamples(
            for: Heightfield(columns: 129, rows: 129, repeating: 0)) == 128)
        #expect(Collider3D.heightfieldSamples(
            for: Heightfield(columns: 2, rows: 2, repeating: 0)) == 4)
        #expect(Collider3D.heightfieldSamples(
            for: Heightfield(columns: 4000, rows: 2, repeating: 0)) == 1024)
    }

    // MARK: Scene colliders

    @Test func sceneMeshesBecomeStaticColliders() {
        // A floor slab authored two nodes deep, each contributing half the
        // lift, so the collider only lands right if the walk composes the
        // node transforms.
        let slab = Heightfield(columns: 2, rows: 2, repeating: 0.5)
            .mesh(width: 4, depth: 4, height: 1)
        let inner = SceneNode(name: "slab", mesh: slab,
                              position: Vector3(0, 0.75, 0))
        let outer = SceneNode(name: "root", position: Vector3(0, 0.75, 0),
                              children: [inner])
        let scene = Scene(nodes: [outer])

        let world = World3D()
        let colliders = world.addStaticBodies(from: scene)
        #expect(colliders.count == 1)

        // Local surface 0.5, lifted 0.75 twice: the slab sits at y = 2.
        let ball = world.addBody(.sphere(radius: 0.3), at: Vector3(0.6, 4, 0.4))
        run(world, steps: 300)
        #expect(abs(ball.position.y - 2.3) < 0.05)
    }

    // MARK: Determinism

    @Test func compoundOnTerrainReplaysByteIdentically() {
        func build() -> (World3D, Body3D) {
            let world = World3D()
            let slope = Heightfield(columns: 33, rows: 33) { u, _ in 0.8 * (1 - u) }
            world.addBody(.heightfield(slope, width: 10, depth: 10, height: 2),
                          at: .zero, kind: .static)
            let tumbler = world.addBody(.compound([
                .part(.box(width: 0.8, height: 0.25, depth: 0.25)),
                .part(.box(width: 0.25, height: 0.8, depth: 0.25),
                      at: Vector3(0.2, 0.3, 0), density: 3),
            ]), at: Vector3(-3, 3, 0), rotated: 0.4, axis: .unitZ)
            return (world, tumbler)
        }

        let (first, a) = build()
        let (second, b) = build()
        run(first, steps: 240)
        run(second, steps: 240)

        #expect(a.position == b.position)
        #expect(a.quaternion == b.quaternion)
    }
}
