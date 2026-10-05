import Foundation
import Testing
import Ollin
@testable import OllinPhysics

/// A number a sketch hands the 3D solver is checked where it crosses into the
/// bridge: one the solver cannot hold (not a number, an infinity, a magnitude
/// past a billion units) leaves the thing as it was with a one-time note, or
/// throws where the call already throws for what it cannot build. Before the
/// checks, 28 of the 37 cases probed here stopped a debug build inside the
/// solver one step later (its integrator asserts on a position that is not a
/// number) and poisoned a release build's broad phase. GPU-free, and parallel
/// safe like the rest of the Jolt suites.
struct SolverNumberTests {

    static let bad: [Double] = [.nan, .infinity, -.infinity, 1e30]

    func world() -> World3D { let w = World3D(); w.ground = 0; return w }
    func box(_ w: World3D, at p: Vector3 = Vector3(0, 2, 0)) -> Body3D {
        w.addBody(.box(width: 1, height: 1, depth: 1), at: p)
    }
    func step(_ w: World3D, _ n: Int = 30) { for _ in 0 ..< n { w.advance(by: 1.0 / 60) } }
    func noted(_ w: World3D, _ what: String) -> Bool {
        w.worldNotes.contains { $0.hasPrefix("\(what) was given") }
    }

    @Test func aBodyKeepsItsPoseAndMotion() {
        let w = world()
        let b = box(w)
        let position = b.position
        for v in Self.bad {
            b.position = Vector3(v, 1, 0)
            b.velocity = Vector3(0, v, 0)
            b.angularVelocity = Vector3(v, 0, 0)
        }
        // A rotation can never carry a bad number: its initializer makes a
        // unit rotation of anything else, so these two are the identity by
        // the time they reach the bridge, and the bridge's own check on a
        // rotation is a backstop.
        b.rotation = Rotation3D(x: .nan, y: 0, z: 0, w: 1)
        b.rotation = Rotation3D(x: 0, y: 0, z: 0, w: 0)
        #expect(b.position == position)
        #expect(b.rotation == .identity)
        #expect(b.velocity == .zero)
        #expect(b.angularVelocity == .zero)
        step(w)
        #expect(SolverNumber.holds(b.position))
        #expect(noted(w, "body.position"))
        #expect(noted(w, "body.velocity"))
        #expect(noted(w, "body.angularVelocity"))
        // A number the solver holds still goes through.
        b.position = Vector3(3, 2, 0)
        #expect(b.position.x == 3)
    }

    @Test func aForceThatIsNotANumberDoesNothing() {
        let w = world()
        let control = box(w, at: Vector3(-3, 2, 0))
        let b = box(w, at: Vector3(3, 2, 0))
        b.applyForce(Vector3(.nan, 0, 0))
        b.applyImpulse(Vector3(.infinity, 0, 0))
        b.applyTorque(Vector3(0, 1e30, 0))
        step(w)
        #expect(b.position.y == control.position.y)
        #expect(b.position.x == 3)
        #expect(noted(w, "applyForce"))
        #expect(noted(w, "applyImpulse"))
        #expect(noted(w, "applyTorque"))
    }

    @Test func aMaterialNumberIsKept() {
        let w = world()
        let b = box(w)
        let friction = b.friction, restitution = b.restitution, gravityScale = b.gravityScale
        for v in Self.bad {
            b.friction = v
            b.restitution = v
            b.gravityScale = v
        }
        #expect(b.friction == friction)
        #expect(b.restitution == restitution)
        #expect(b.gravityScale == gravityScale)
        step(w)
        #expect(SolverNumber.holds(b.position))
        #expect(noted(w, "body.gravityScale"))
    }

    @Test func theWorldKeepsItsOwnNumbers() {
        let w = world()
        let b = box(w)
        for v in Self.bad {
            w.gravity = Vector3(0, v, 0)
            w.ground = v
            w.restitution = v
            w.maxTimestep = v
            w.unitsPerMeter = v
        }
        w.unitsPerMeter = 0
        w.unitsPerMeter = -1
        #expect(w.gravity == Vector3(0, -9.8, 0))
        #expect(w.ground == 0)
        #expect(w.restitution == 0.2)
        #expect(w.maxTimestep == 1.0 / 30)
        #expect(w.unitsPerMeter == 1)
        let before = b.position
        w.advance(by: .nan)
        w.advance(by: .infinity)
        #expect(b.position == before)
        step(w, 120)
        // The floor is still there: the box lands on it.
        #expect(b.position.y > 0.4 && b.position.y < 0.6)
        #expect(noted(w, "world.gravity"))
        #expect(noted(w, "world.ground"))
        #expect(noted(w, "world.unitsPerMeter"))
        #expect(noted(w, "advance(by:)"))
    }

    @Test func aBodyAddedWithANumberTheSolverCannotHoldTakesTheDefault() {
        let w = world()
        let control = box(w, at: Vector3(5, 2, 0))
        let atNaN = w.addBody(.box(width: 1, height: 1, depth: 1), at: Vector3(.nan, 2, 0))
        #expect(atNaN.position == .zero)
        let turned = w.addBody(.box(width: 1, height: 1, depth: 1), at: Vector3(-5, 2, 0),
                               rotated: .nan, axis: .unitY)
        #expect(turned.rotation == .identity)
        let noAxis = w.addBody(.box(width: 1, height: 1, depth: 1), at: Vector3(-5, 5, 0),
                               rotated: 1, axis: .zero)
        // The axis falls back to the parameter's default, straight up, and
        // the turn is kept.
        #expect(abs(noAxis.rotation.angle - 1) < 1e-3)
        #expect(abs(noAxis.rotation.axis.y - 1) < 1e-3)
        let dense = w.addBody(.box(width: 1, height: 1, depth: 1), at: Vector3(5, 5, 0),
                              density: .nan)
        #expect(dense.mass == control.mass)
        let sized = w.addBody(.box(width: .nan, height: 1, depth: 1), at: Vector3(0, 5, 0))
        if case .sphere(let radius) = sized.collider {
            #expect(radius == 1)
        } else {
            Issue.record("a collider with a number the solver cannot hold becomes a unit sphere")
        }
        let hull = w.addBody(.hull([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, .infinity, 0), Vector3(0, 0, 1)]),
                             at: Vector3(0, 8, 0))
        if case .sphere = hull.collider {} else { Issue.record("a hull with an infinite point becomes a unit sphere") }
        step(w, 120)
        for body in w.bodies { #expect(SolverNumber.holds(body.position)) }
        #expect(noted(w, "addBody(at:)"))
        #expect(noted(w, "addBody's angle"))
        #expect(noted(w, "addBody's axis"))
        #expect(noted(w, "addBody's density"))
        #expect(noted(w, "addBody's collider"))
    }

    @Test func aCharacterKeepsItsNumbers() {
        let w = world()
        let c = w.addCharacter(at: Vector3(0, 2, 0))
        let position = c.position
        c.position = Vector3(.nan, 2, 0)
        #expect(c.position == position)
        c.velocity = Vector3(.infinity, 0, 0)
        #expect(c.velocity == .zero)
        c.walk(x: .nan, z: 0)
        #expect(c.desiredVelocity == .zero)
        c.jump(.nan)
        c.mass = .nan
        #expect(c.mass == 70)
        c.stepHeight = 1e30
        #expect(c.stepHeight == 0.4)
        step(w)
        #expect(SolverNumber.holds(c.position))
        #expect(abs(c.position.x) < 1e-6)
        let elsewhere = w.addCharacter(at: Vector3(.nan, 2, 0), mass: .infinity)
        #expect(elsewhere.position == .zero)
        #expect(elsewhere.mass == 70)
        #expect(noted(w, "character.position"))
        #expect(noted(w, "walk(at:)"))
        #expect(noted(w, "jump"))
        #expect(noted(w, "addCharacter(at:)"))
    }

    @Test func aJointRefusesANumberItCannotDrive() {
        let w = world()
        let anchor = w.addBody(.box(width: 1, height: 1, depth: 1), at: Vector3(0, 5, 0), kind: .static)
        let arm = w.addBody(.box(width: 2, height: 0.2, depth: 0.2), at: Vector3(1, 5, 0))
        let hinge = w.connect(anchor, arm, .revolute(at: Vector3(0, 5, 0), axis: .unitZ))
        hinge.drive(at: .nan)
        hinge.drive(to: 1, frequency: .infinity)
        hinge.friction = .nan
        #expect(hinge.friction == 0)
        hinge.softenLimits(frequency: .nan)
        // An infinite strength is the default and means no limit, so it passes.
        hinge.drive(at: 2, strength: .infinity)
        let made = w.joints.count
        let unmade = w.connect(anchor, arm, .ball(at: Vector3(.nan, 5, 0)))
        #expect(unmade.constraint == nil)
        #expect(w.joints.count == made)
        let grab = w.grab(arm, at: Vector3(.nan, 0, 0))
        #expect(grab.target == arm.position)
        grab.target = Vector3(0, .infinity, 0)
        #expect(grab.target == arm.position)
        step(w)
        #expect(SolverNumber.holds(arm.position))
        #expect(noted(w, "drive(at:)"))
        #expect(noted(w, "joint.friction"))
        #expect(noted(w, "connect's joint"))
        #expect(noted(w, "grab(_:at:)"))
        #expect(noted(w, "joint.target"))
    }

    @Test func aVehicleKeepsItsControlsAndRefusesABadWheel() throws {
        let w = world()
        func wheels() -> [Wheel3D] {
            [Wheel3D.wheel(at: Vector3(0.85, -0.1, 1.3), steers: true, driven: true),
             Wheel3D.wheel(at: Vector3(-0.85, -0.1, 1.3), steers: true, driven: true),
             Wheel3D.wheel(at: Vector3(0.85, -0.1, -1.3)),
             Wheel3D.wheel(at: Vector3(-0.85, -0.1, -1.3))]
        }
        let car = try w.addVehicle(.box(width: 1.8, height: 0.6, depth: 3.6), at: Vector3(0, 1, 0),
                                   wheels: wheels())
        car.throttle = .nan
        #expect(car.throttle == 0)
        car.drive(throttle: 1, steering: .infinity)
        #expect(car.throttle == 1)
        #expect(car.steering == 0)
        car.engineTorque = .nan
        #expect(car.engineTorque == 500)
        car.wheels[0].radius = .nan
        step(w)
        #expect(SolverNumber.holds(car.body.position))
        #expect(noted(w, "vehicle.throttle"))
        #expect(noted(w, "a wheel's settings"))
        #expect(throws: PhysicsError.self) {
            try w.addVehicle(.box(width: 1.8, height: 0.6, depth: 3.6), at: Vector3(.nan, 1, 0),
                             wheels: wheels())
        }
        let badWheel = wheels()
        badWheel[1].radius = .infinity
        #expect(throws: PhysicsError.self) {
            try w.addVehicle(.box(width: 1.8, height: 0.6, depth: 3.6), at: Vector3(0, 1, 0),
                             wheels: badWheel)
        }
    }

    @Test func aSoftBodyKeepsItsNumbers() throws {
        let w = world()
        let cloth = try w.addSoftBody(from: Mesh.plane(width: 2, depth: 2, segments: 6),
                                      at: Vector3(0, 2, 0))
        cloth.pressure = .nan
        #expect(cloth.pressure == 0)
        cloth.vertexRadius = .infinity
        #expect(cloth.vertexRadius == 0)
        cloth.move(0, to: Vector3(.nan, 0, 0))
        cloth.applyForce(Vector3(0, 1e30, 0))
        step(w)
        for p in cloth.positions { #expect(SolverNumber.holds(p)) }
        #expect(noted(w, "softBody.pressure"))
        #expect(noted(w, "move(_:to:)"))
        #expect(noted(w, "applyForce"))
        #expect(throws: PhysicsError.self) {
            try w.addSoftBody(from: Mesh.plane(width: 2, depth: 2, segments: 6), at: Vector3(0, .nan, 0))
        }
        var torn = Mesh.plane(width: 2, depth: 2, segments: 6)
        torn.positions[3] = Vector3(.infinity, 0, 0)
        #expect(throws: PhysicsError.self) { try w.addSoftBody(from: torn, at: Vector3(0, 2, 0)) }
        #expect(throws: PhysicsError.self) {
            try w.addRope(through: [Vector3(0, 3, 0), Vector3(.nan, 3, 0), Vector3(2, 3, 0)])
        }
    }

    @Test func waterWithANumberTheSolverCannotHoldIsRefused() {
        let w = world()
        w.water = Water(level: 1)
        w.water = Water(level: .nan)
        #expect(w.water?.level == 1)
        w.water = Water(level: 1, flow: Vector3(.infinity, 0, 0))
        #expect(w.water?.flow == .zero)
        let b = box(w, at: Vector3(0, 3, 0))
        step(w)
        #expect(SolverNumber.holds(b.position))
        #expect(noted(w, "world.water"))
    }

    @Test func aSnapshotAndTheBridgeReadOneDefinition() {
        #expect(SolverNumber.holds(1e9))
        #expect(!SolverNumber.holds(1e9 + 1))
        #expect(!SolverNumber.holds(.nan))
        #expect(!SolverNumber.holds(-.infinity))
        #expect(SolverNumber.complaint(Rotation3D.identity) == nil)
        #expect(SolverNumber.axisComplaint(Vector3.zero) != nil)
        #expect(SolverNumber.axisComplaint(Vector3.unitX) == nil)
    }
}
