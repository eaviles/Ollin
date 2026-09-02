import Foundation
import Testing
import Ollin
import CJolt
@testable import OllinPhysics

/// Correctness for the 3D rigid `Body3D` sub-system (Jolt-backed): a dynamic
/// body falls under gravity, the ground slab stops it, stacks settle, joints
/// hold, grabs pull, and the same build stepped twice reproduces byte-equal
/// poses. These run in world units and convert through `unitsPerMeter`, so the
/// asserts are in scene units. GPU-free. Unlike Box2D, the solver keeps no
/// global world pool (only an init-once type registry), so this suite runs in
/// parallel safely.
struct RigidBody3DTests {

    func run(_ world: World3D, steps: Int, dt: Double = 1.0 / 60) {
        for _ in 0 ..< steps { world.advance(by: dt) }
    }

    /// Low-level certification that the vendored Jolt library builds, links,
    /// and steps from Swift through the raw C bridge (the typed `Body3D` path
    /// is built on this and exercised by the tests below).
    @Test func rawCJoltStepsAndReadsBack() {
        let world = cjolt_world_create(0, -10, 0, 256)!
        defer { cjolt_world_destroy(world) }

        var desc = CJoltBodyDesc()
        desc.shape.type = CJOLT_SHAPE_SPHERE
        desc.shape.a = 0.5
        desc.position = (0, 0, 0)
        desc.rotation = (0, 0, 0, 1)
        desc.motion = CJOLT_MOTION_DYNAMIC
        desc.gravityFactor = 1
        desc.allowSleep = true
        let body = withUnsafePointer(to: &desc) { cjolt_body_create(world, $0) }
        #expect(body != CJOLT_BODY_INVALID)

        for _ in 0 ..< 60 { _ = cjolt_world_step(world, 1.0 / 60, 1) }
        var position: (Float, Float, Float) = (0, 0, 0)
        withUnsafeMutableBytes(of: &position) {
            cjolt_body_get_position(world, body, $0.baseAddress!.assumingMemoryBound(to: Float.self))
        }
        #expect(position.1 < -4)   // ½·10·1² ≈ 5 m of fall
    }

    @Test func dynamicBodyFallsUnderGravity() {
        let world = World3D()
        let body = world.addBody(.box(width: 1, height: 1, depth: 1),
                                 at: Vector3(0, 10, 0))

        run(world, steps: 60)   // ~one second of fall

        // ½·9.8·1² ≈ 4.9 units down, minus a touch of damping.
        #expect(body.position.y < 10 - 3.5)
        #expect(abs(body.position.x) < 1e-3)
        #expect(abs(body.position.z) < 1e-3)
    }

    @Test func groundStopsAFallingSphere() {
        let world = World3D()
        world.ground = 0
        let ball = world.addBody(.sphere(radius: 0.5), at: Vector3(0, 3, 0),
                                 restitution: 0)

        run(world, steps: 300)   // fall and settle

        // Resting on the floor, the center sits one radius above it.
        #expect(abs(ball.position.y - 0.5) < 0.05)
    }

    @Test func aStackOfBoxesSettles() {
        let world = World3D()
        world.ground = 0
        var boxes: [Body3D] = []
        for level in 0 ..< 3 {
            boxes.append(world.addBody(.box(width: 1, height: 1, depth: 1),
                                       at: Vector3(0, 0.5 + Double(level), 0),
                                       restitution: 0))
        }

        run(world, steps: 420)   // seven simulated seconds

        // Each box rests on the one below: centers near 0.5, 1.5, 2.5.
        for (level, box) in boxes.enumerated() {
            #expect(abs(box.position.y - (0.5 + Double(level))) < 0.1)
            #expect(abs(box.position.x) < 0.2)
            #expect(abs(box.position.z) < 0.2)
        }
    }

    @Test func aRevoluteJointSwingsAboutItsPivot() {
        let world = World3D()
        let anchor = world.addBody(.box(width: 0.2, height: 0.2, depth: 0.2),
                                   at: Vector3(0, 5, 0), kind: .static)
        let bob = world.addBody(.box(width: 1, height: 0.2, depth: 0.2),
                                at: Vector3(1.5, 5, 0))
        world.connect(anchor, bob, .revolute(at: Vector3(0, 5, 0), axis: .unitZ))

        let pivot = Vector3(0, 5, 0)
        let armLength = (bob.position - pivot).length
        run(world, steps: 90)

        // It swung (fell from horizontal) but stayed on its arm.
        #expect(bob.position.y < 4.9)
        let swungLength = (bob.position - pivot).length
        #expect(abs(swungLength - armLength) < 0.05)
        // A z-axis hinge keeps the swing in the xy plane.
        #expect(abs(bob.position.z) < 1e-3)
    }

    @Test func aDistanceRodHoldsItsLength() {
        let world = World3D()
        let anchor = world.addBody(.sphere(radius: 0.1), at: Vector3(0, 6, 0),
                                   kind: .static)
        let bob = world.addBody(.sphere(radius: 0.3), at: Vector3(2, 6, 0))
        world.connect(anchor, bob, .distance(from: Vector3(0, 6, 0),
                                             to: Vector3(2, 6, 0)))

        run(world, steps: 240)

        // The bob hangs on the rod: two units from the anchor point.
        let spacing = (bob.position - Vector3(0, 6, 0)).length
        #expect(abs(spacing - 2) < 0.1)
    }

    @Test func aGrabPullsABodyTowardItsTarget() {
        let world = World3D()
        world.ground = 0
        let box = world.addBody(.box(width: 1, height: 1, depth: 1),
                                at: Vector3(0, 0.5, 0))
        run(world, steps: 30)   // let it rest

        let grabPoint = box.position + Vector3(0, 0.5, 0)
        let joint = world.grab(box, at: grabPoint)
        let target = Vector3(2, 3, 1)
        for _ in 0 ..< 420 {
            joint.target = target
            world.advance(by: 1.0 / 60)
        }

        // The grip reached the target and the box dangles from it: its center
        // hangs half a unit (the grip's local offset) from the target, calm.
        #expect(abs((box.position - target).length - 0.5) < 0.2)
        #expect(box.velocity.length < 0.5)

        joint.remove()
        #expect(world.joints.isEmpty)
        run(world, steps: 300)
        #expect(abs(box.position.y - 0.5) < 0.1)   // released, it fell back
    }

    @Test func removingABodyCascadesToItsJoints() {
        let world = World3D()
        let a = world.addBody(.sphere(radius: 0.3), at: Vector3(0, 5, 0),
                              kind: .static)
        let b = world.addBody(.sphere(radius: 0.3), at: Vector3(1, 5, 0))
        world.connect(a, b, .ball(at: Vector3(0, 5, 0)))
        #expect(world.joints.count == 1)

        world.remove(b)
        #expect(world.bodies.count == 1)
        #expect(world.joints.isEmpty)
        run(world, steps: 10)   // stepping after the removal is safe
    }

    @Test func massFollowsVolumeAndDensity() {
        let world = World3D()
        let ball = world.addBody(.sphere(radius: 0.5), at: Vector3(0, 1, 0))
        // Density 1 is 1000 kg/m³; a 0.5 m sphere is (4/3)π·0.125 m³.
        let expected = 1000.0 * (4.0 / 3.0) * .pi * 0.125
        #expect(abs(ball.mass - expected) / expected < 0.05)

        let heavy = world.addBody(.sphere(radius: 0.5), at: Vector3(3, 1, 0),
                                  density: 2)
        #expect(abs(heavy.mass - 2 * ball.mass) / ball.mass < 0.01)

        let anchor = world.addBody(.sphere(radius: 0.5), at: Vector3(6, 1, 0),
                                   kind: .static)
        #expect(anchor.mass == 0)
    }

    @Test func orientationRoundTripsThroughAngleAndAxis() {
        let world = World3D()
        let box = world.addBody(.box(width: 1, height: 1, depth: 1),
                                at: Vector3(0, 2, 0),
                                rotated: 0.7, axis: Vector3(0, 0, 1))
        #expect(abs(box.rotationAngle - 0.7) < 1e-4)
        #expect((box.rotationAxis - Vector3(0, 0, 1)).length < 1e-4)

        box.setRotation(1.2, axis: .unitY)
        #expect(abs(box.rotationAngle - 1.2) < 1e-4)
        #expect((box.rotationAxis - .unitY).length < 1e-4)
    }

    @Test func orientationIsOneValueThatSetsReadsAndComposes() {
        let world = World3D()
        let box = world.addBody(.box(width: 1, height: 1, depth: 1),
                                at: Vector3(0, 2, 0))
        #expect(box.rotation == .identity)

        let tilt = Rotation3D(angle: 0.7, axis: .unitZ)
        box.rotation = tilt
        #expect(abs(box.rotation.angle - 0.7) < 1e-4)
        #expect((box.rotation.axis - .unitZ).length < 1e-4)
        // The angle/axis pair reads the same pose.
        #expect(abs(box.rotationAngle - 0.7) < 1e-4)

        // A turn composed onto the pose lands where the value says: a
        // quarter turn about y after the tilt takes the body's own x-axis
        // where the composed value takes it.
        box.rotation = .aboutY(.pi / 2) * tilt
        let expected = Vector3.unitX.rotated(by: .aboutY(.pi / 2) * tilt)
        #expect((Vector3.unitX.rotated(by: box.rotation) - expected).length < 1e-4)

        // The setter pair is sugar over the value.
        box.setRotation(1.2, axis: .unitY)
        #expect(box.rotation == Rotation3D(angle: 1.2, axis: .unitY)
                || (box.rotation.inverse * Rotation3D(angle: 1.2, axis: .unitY)).angle < 1e-4)
    }

    @Test func identicalWorldsStepIdentically() {
        func build() -> (World3D, [Body3D]) {
            let world = World3D()
            world.ground = 0
            var bodies: [Body3D] = []
            for i in 0 ..< 20 {
                let x = Double(i % 4) * 0.6 - 1
                let z = Double((i / 4) % 4) * 0.6 - 1
                bodies.append(world.addBody(.box(width: 0.5, height: 0.5, depth: 0.5),
                                            at: Vector3(x, 1 + Double(i) * 0.6, z),
                                            rotated: Double(i) * 0.3,
                                            axis: Vector3(0.3, 1, 0.2)))
            }
            return (world, bodies)
        }

        let (worldA, bodiesA) = build()
        let (worldB, bodiesB) = build()
        run(worldA, steps: 240)
        run(worldB, steps: 240)

        // The solver is deterministic: the same build stepped the same way
        // lands every body in exactly the same pose.
        for (a, b) in zip(bodiesA, bodiesB) {
            #expect(a.position == b.position)
            #expect(a.rotationAngle == b.rotationAngle)
        }
    }
}
