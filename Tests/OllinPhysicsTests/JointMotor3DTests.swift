import Foundation
import Testing
import Ollin
@testable import OllinPhysics

/// Correctness for the 3D joint motors, limits, and springs: a velocity motor
/// spins at its target rate, a position motor settles on its target, limits
/// stop a swing and a slide, friction holds an unpowered hinge, soft limits
/// give and pull back, and driving an undrivable joint is a safe no-op. All
/// behavioral (the no-pixel-snapshot policy for physics); parallel-safe like
/// the rigid-body suite.
struct JointMotor3DTests {

    func run(_ world: World3D, steps: Int, dt: Double = 1.0 / 60) {
        for _ in 0 ..< steps { world.step(dt: dt) }
    }

    /// A bar hinged at its own center of mass, so gravity exerts no torque
    /// about the pivot and the motor's effect is unconfounded.
    func makeWheel(_ world: World3D,
                   limits: ClosedRange<Double>? = nil) -> (Body3D, Joint3D) {
        let anchor = world.addBody(.sphere(radius: 0.1), at: Vector3(0, 5, 0),
                                   kind: .static)
        let bar = world.addBody(.box(width: 2, height: 0.2, depth: 0.2),
                                at: Vector3(0, 5, 0))
        let joint = world.connect(anchor, bar,
                                  .revolute(at: Vector3(0, 5, 0), axis: .unitZ,
                                            limits: limits))
        return (bar, joint)
    }

    /// A pendulum: the bar reaches +x from the pivot, so gravity swings it
    /// down (a negative angle about the +z hinge axis).
    func makePendulum(_ world: World3D,
                      limits: ClosedRange<Double>? = nil) -> (Body3D, Joint3D) {
        let anchor = world.addBody(.sphere(radius: 0.1), at: Vector3(0, 5, 0),
                                   kind: .static)
        let bob = world.addBody(.box(width: 1, height: 0.2, depth: 0.2),
                                at: Vector3(1.5, 5, 0))
        let joint = world.connect(anchor, bob,
                                  .revolute(at: Vector3(0, 5, 0), axis: .unitZ,
                                            limits: limits))
        return (bob, joint)
    }

    @Test func velocityMotorSpinsAtItsTargetRate() {
        let world = World3D()
        let (bar, joint) = makeWheel(world)

        joint.drive(at: 2)
        run(world, steps: 30)   // half a second: one radian of turn

        // The bar spins about +z at the asked rate, and the readback angle
        // tracks it (still inside the wrapped ±pi window here).
        #expect(abs(bar.angularVelocity.z - 2) < 0.05)
        #expect(abs(joint.angle - 1) < 0.1)
    }

    @Test func positionMotorSettlesOnItsTarget() {
        let world = World3D()
        let (bar, joint) = makeWheel(world)

        joint.drive(to: .pi / 2, frequency: 8)
        run(world, steps: 300)

        #expect(abs(joint.angle - .pi / 2) < 0.02)
        #expect(bar.angularVelocity.length < 0.05)   // arrived, and calm
    }

    @Test func velocityMotorStrengthCapsItsTorque() {
        // The bar's inertia is ~27 kg·m², so a 1 N·m motor can add at most
        // ~0.04 rad/s of spin per second; the unlimited default hits the
        // target rate in a step. One second of driving separates them.
        let capped = World3D()
        let (cappedBar, weak) = makeWheel(capped)
        weak.drive(at: 2, strength: 1)
        run(capped, steps: 60)
        #expect(cappedBar.angularVelocity.z < 0.2)

        let unlimited = World3D()
        let (freeBar, strong) = makeWheel(unlimited)
        strong.drive(at: 2)
        run(unlimited, steps: 60)
        #expect(abs(freeBar.angularVelocity.z - 2) < 0.05)
    }

    @Test func hingeLimitsStopTheSwing() {
        let limited = World3D()
        let (_, joint) = makePendulum(limited, limits: -0.4 ... 0.4)
        let free = World3D()
        let (_, unlimited) = makePendulum(free)

        var limitedMin = 0.0
        var freeMin = 0.0
        for _ in 0 ..< 300 {
            limited.step(dt: 1.0 / 60)
            free.step(dt: 1.0 / 60)
            limitedMin = min(limitedMin, joint.angle)
            freeMin = min(freeMin, unlimited.angle)
        }

        // The stop caught the fall where the free hinge swung on past.
        #expect(limitedMin > -0.45)
        #expect(freeMin < -1)
    }

    @Test func sliderLimitsStopTheTravel() {
        let world = World3D()
        let axis = Vector3(1, -1, 0).normalized
        let anchor = world.addBody(.sphere(radius: 0.1), at: Vector3(0, 5, 0),
                                   kind: .static)
        let start = Vector3(0, 5, 0) + axis * 1.5
        let block = world.addBody(.box(width: 0.5, height: 0.5, depth: 0.5),
                                  at: start)
        let joint = world.connect(anchor, block,
                                  .prismatic(at: start, axis: axis,
                                             limits: -0.01 ... 1))

        run(world, steps: 300)   // gravity pulls it down the tilted rail

        // It slid to the end of its travel and no farther.
        #expect(abs(joint.offset - 1) < 0.05)
        #expect((block.position - (start + axis)).length < 0.05)
    }

    @Test func sliderPositionMotorReachesItsOffset() {
        let world = World3D()
        let anchor = world.addBody(.sphere(radius: 0.1), at: Vector3(0, 5, 0),
                                   kind: .static)
        let block = world.addBody(.box(width: 0.5, height: 0.5, depth: 0.5),
                                  at: Vector3(1.5, 5, 0))
        let joint = world.connect(anchor, block,
                                  .prismatic(at: Vector3(1.5, 5, 0),
                                             axis: .unitX))

        // The rail is level, so gravity is orthogonal to the one free axis
        // and the servo's work shows plainly.
        joint.drive(to: 0.8, frequency: 8)
        run(world, steps: 300)

        #expect(abs(joint.offset - 0.8) < 0.02)
        #expect(abs(block.position.x - 2.3) < 0.05)
    }

    @Test func frictionHoldsAnUnpoweredHinge() {
        let sticky = World3D()
        let (_, held) = makePendulum(sticky)
        // Gravity's torque on the bar is ~mgr = 8·9.8·1.5 = 118 N·m; a drag
        // torque far above it pins the hinge where it started.
        held.friction = 1000
        let free = World3D()
        let (_, loose) = makePendulum(free)

        run(sticky, steps: 120)
        run(free, steps: 120)

        #expect(abs(held.angle) < 0.02)
        #expect(loose.angle < -0.5)
    }

    @Test func softLimitsGiveThenHoldNearTheStop() {
        let hard = World3D()
        let (_, hardJoint) = makePendulum(hard, limits: -0.3 ... 0.3)
        let soft = World3D()
        let (softBob, softJoint) = makePendulum(soft, limits: -0.3 ... 0.3)
        softJoint.softenLimits(frequency: 2)

        var hardMin = 0.0
        var softMin = 0.0
        for _ in 0 ..< 600 {
            hard.step(dt: 1.0 / 60)
            soft.step(dt: 1.0 / 60)
            hardMin = min(hardMin, hardJoint.angle)
            softMin = min(softMin, softJoint.angle)
        }

        // The hard stop is a wall; the spring gives past it, then carries the
        // load to rest hanging against it.
        #expect(hardMin > -0.35)
        #expect(softMin < -0.4)
        #expect(softBob.velocity.length < 0.1)
    }

    @Test func drivingAnUndrivableJointIsSafe() {
        let world = World3D()
        let anchor = world.addBody(.sphere(radius: 0.1), at: Vector3(0, 5, 0),
                                   kind: .static)
        let bob = world.addBody(.sphere(radius: 0.3), at: Vector3(1, 5, 0))
        let joint = world.connect(anchor, bob, .ball(at: Vector3(0, 5, 0)))

        joint.drive(at: 2)
        joint.drive(to: 1)
        joint.stopMotor()
        joint.friction = 5
        joint.softenLimits(frequency: 2)
        run(world, steps: 60)

        // Nothing to drive: the readbacks stay zero and the world still steps.
        #expect(joint.angle == 0)
        #expect(joint.offset == 0)
    }

    @Test func angleReadsZeroAtConnectThenFollowsTheSwing() {
        let world = World3D()
        let (bob, joint) = makePendulum(world)

        #expect(joint.angle == 0)   // the connect pose is the zero
        run(world, steps: 90)

        // Falling from +x is a negative turn about the +z hinge axis, and the
        // readback agrees with the geometry of where the bob went.
        #expect(joint.angle < -0.3)
        let geometric = atan2(5 - bob.position.y, bob.position.x)
        #expect(abs(-joint.angle - geometric) < 0.1)
    }
}
