import Foundation
import Testing
import Ollin
@testable import OllinPhysics

/// Correctness for the per-body motion parameters: which ways a body is allowed to
/// move, how hard gravity pulls on it, and whether the solver checks its whole
/// path. Behavioral (the no-pixel-snapshot policy for physics), each answer
/// pinned against a counterfactual twin: the same scene run twice with one
/// thing changed, so a passing test can't be explained by the geometry alone.
/// Parallel-safe like the rest of the 3D suite.
struct Motion3DTests {

    func run(_ world: World3D, steps: Int, dt: Double = 1.0 / 60) {
        for _ in 0 ..< steps { world.advance(by: dt) }
    }

    // MARK: Which plane the body lives in

    /// A body given a plane and one that isn't, both shoved the same way out of
    /// it: the restricted one doesn't budge, and it is the restriction saying
    /// so, since the free twin is thrown five units.
    @Test func aFlatBodyCannotBeShovedOutOfItsPlane() {
        func shove(_ freedom: Freedom3D) -> Double {
            let world = World3D()
            world.ground = 0
            let target = world.addBody(.box(width: 1, height: 1, depth: 1),
                                       at: Vector3(0, 0.5, 0), freedom: freedom)
            let hammer = world.addBody(.sphere(radius: 0.4),
                                       at: Vector3(0, 0.5, -3), gravityScale: 0)
            hammer.velocity = Vector3(0, 0, 30)
            run(world, steps: 120)
            return target.position.z
        }
        #expect(shove(.all) > 4, "the free twin should be knocked well away")
        #expect(abs(shove(.plane())) < 1e-4, "the flat one holds its plane")
    }

    /// The plane is a choice, not a fixed one: a body flattened onto the ground
    /// plane is free in exactly the direction the upright one is locked.
    @Test func thePlaneFacesWhicheverWayIsAsked() {
        let world = World3D()
        world.ground = 0
        let facingCamera = world.addBody(.box(width: 1, height: 1, depth: 1),
                                         at: Vector3(0, 0.5, 0),
                                         freedom: .plane())
        let onTheGround = world.addBody(.box(width: 1, height: 1, depth: 1),
                                        at: Vector3(6, 0.5, 0),
                                        freedom: .plane(normal: .unitY))
        for body in [facingCamera, onTheGround] { body.velocity = Vector3(0, 0, 4) }
        run(world, steps: 60)
        #expect(abs(facingCamera.position.z) < 1e-4, "z is locked in the xy plane")
        #expect(onTheGround.position.z > 1, "z is free in the xz plane")
    }

    /// `.plane` reads its axes off the normal, rounding to the axis it points
    /// most nearly along (the solver takes away whole world axes; there is no
    /// tilted plane).
    @Test func aPlaneTakesItsAxesFromItsNormal() {
        #expect(Freedom3D.plane() == [.moveX, .moveY, .turnZ])
        #expect(Freedom3D.plane(normal: .unitY) == [.moveX, .moveZ, .turnY])
        #expect(Freedom3D.plane(normal: .unitX) == [.moveY, .moveZ, .turnX])
        #expect(Freedom3D.plane(normal: Vector3(0, -1, 0)) == .plane(normal: .unitY),
                "which way the normal points doesn't change the plane")
        #expect(Freedom3D.plane(normal: Vector3(0.2, 0.9, 0.3)) == .plane(normal: .unitY),
                "a tilted normal rounds to its nearest axis")
    }

    // MARK: Tipping and spinning

    /// An upright body turns about the world's up axis and nothing else: set
    /// tumbling, it comes to rest facing a new way rather than on its side.
    @Test func anUprightBodyTurnsButNeverTips() {
        func tumble(_ freedom: Freedom3D) -> (tilt: Double, axis: Vector3) {
            let world = World3D()
            world.ground = 0
            let box = world.addBody(.box(width: 1, height: 1, depth: 1),
                                    at: Vector3(0, 1, 0), freedom: freedom)
            box.velocity = Vector3(0, 0, 4)
            box.angularVelocity = Vector3(6, 3, 0)
            run(world, steps: 120)
            return (box.rotationAngle, box.rotationAxis)
        }
        let free = tumble(.all)
        #expect(free.tilt > 1, "the free twin ends up turned every which way")
        #expect(abs(free.axis.y) < 0.9, "and not about the up axis alone")

        let upright = tumble(.upright)
        #expect(upright.tilt > 0.5, "the upright one did turn")
        #expect(abs(abs(upright.axis.y) - 1) < 1e-3,
                "but only about up: axis was \(upright.axis)")
    }

    /// The same slide, with and without any turning at all: both travel exactly
    /// as far, and only one of them ends up facing a different way.
    @Test func aBodyThatCannotTurnSlidesJustAsFar() {
        func slide(_ freedom: Freedom3D) -> (z: Double, tilt: Double) {
            let world = World3D()
            world.ground = 0
            let box = world.addBody(.box(width: 1, height: 1, depth: 1),
                                    at: Vector3(0, 1, 0), freedom: freedom)
            box.velocity = Vector3(0, 0, 4)
            box.angularVelocity = Vector3(6, 3, 0)
            run(world, steps: 120)
            return (box.position.z, box.rotationAngle)
        }
        let turning = slide(.upright), fixed = slide(.noTurning)
        #expect(abs(turning.z - fixed.z) < 1e-3,
                "\(turning.z) vs \(fixed.z): the travel is the same")
        #expect(turning.tilt > 0.5 && fixed.tilt < 1e-3,
                "only the one allowed to turn turned")
    }

    /// A body with no travel at all hangs where it was put, and still spins:
    /// a turntable with no joint holding it.
    @Test func aPinnedBodyHoldsItsPlaceAndStillSpins() {
        let world = World3D()
        world.ground = 0
        let disc = world.addBody(.cylinder(height: 0.2, radius: 1),
                                 at: Vector3(0, 3, 0), freedom: .noMoving)
        disc.angularVelocity = Vector3(0, 4, 0)
        run(world, steps: 120)
        #expect(abs(disc.position.y - 3) < 1e-4, "it never fell")
        #expect(disc.angularVelocity.y > 1, "and it is still turning")
    }

    // MARK: What a restriction costs

    /// Locking travel and letting it go again leaves the body weighing exactly
    /// what it always did, on both mass paths: the shape's own, and a mass the
    /// body was handed instead.
    @Test func aRestrictedBodyKeepsTheWeightItWasBuiltWith() {
        let world = World3D()
        world.ground = 0
        let byShape = world.addBody(.box(width: 1, height: 1, depth: 1),
                                    at: Vector3(0, 3, 0), density: 2)
        let byMass = world.addBody(.box(width: 2, height: 1, depth: 4),
                                   at: Vector3(6, 3, 0), kind: .dynamic,
                                   isSensor: false, rotated: 0, axis: .unitY,
                                   density: 1, friction: 0.5, restitution: nil,
                                   mass: 1500, centerOfMass: .zero)
        let before = (byShape.mass, byMass.mass)
        #expect(abs(before.0 - 2000) < 1, "density 2 on a 1 m³ box")
        #expect(abs(before.1 - 1500) < 1e-3, "the mass it was handed")

        for body in [byShape, byMass] { body.freedom = .noMoving }
        #expect(abs(byShape.mass - before.0) < 1e-3,
                "a pinned body still weighs what it did")
        #expect(abs(byMass.mass - before.1) < 1e-3)

        for body in [byShape, byMass] { body.freedom = .all }
        #expect(abs(byShape.mass - before.0) < 1e-3, "and again once let go")
        #expect(abs(byMass.mass - before.1) < 1e-3)
    }

    /// Reading back what was set, including the library's one invalid case: no
    /// freedom at all would divide by a zero mass, so it reads as unrestricted
    /// rather than crashing. (Hold a body still with `kind = .static`.)
    @Test func freedomReadsBackAndTheEmptySetMeansUnrestricted() {
        let world = World3D()
        world.ground = 0
        let box = world.addBody(.box(width: 1, height: 1, depth: 1),
                                at: Vector3(0, 3, 0), freedom: [])
        #expect(box.freedom == .all, "an empty set at creation")
        box.freedom = .upright
        #expect(box.freedom == .upright)
        box.freedom = []
        #expect(box.freedom == .all, "and an empty set set live")
        run(world, steps: 60)
        #expect(box.position.y < 2, "it is still an ordinary falling body")
    }

    // MARK: Gravity, per body

    /// The three ways a body can answer gravity, against the ordinary one:
    /// weightless holds its height, negative rises, and a fraction falls that
    /// fraction as far (½·g·t² to the number).
    @Test func gravityScaleSetsHowFarABodyFalls() {
        func fall(_ scale: Double) -> Double {
            let world = World3D()
            let ball = world.addBody(.sphere(radius: 0.3), at: Vector3(0, 50, 0),
                                     gravityScale: scale)
            run(world, steps: 60)
            return 50 - ball.position.y
        }
        #expect(abs(fall(1) - 4.9) < 0.1, "an ordinary second of falling")
        #expect(abs(fall(0)) < 1e-4, "weightless: it stays where it was put")
        #expect(fall(-1) < -4.5, "and a negative scale rises instead")
        #expect(abs(fall(0.15) - 0.735) < 0.02, "a sixth of gravity, a sixth as far")
    }

    /// It is one body's answer, not the world's: a weightless body beside an
    /// ordinary one leaves the ordinary one falling.
    @Test func gravityScaleIsPerBodyNotPerWorld() {
        let world = World3D()
        let balloon = world.addBody(.sphere(radius: 0.3), at: Vector3(0, 10, 0),
                                    gravityScale: -0.5)
        let stone = world.addBody(.sphere(radius: 0.3), at: Vector3(3, 10, 0))
        run(world, steps: 60)
        #expect(balloon.position.y > 11, "the balloon went up")
        #expect(stone.position.y < 6, "the stone went down")
        #expect(balloon.gravityScale == -0.5 && stone.gravityScale == 1,
                "each reads back its own")
    }

    // MARK: Checking the whole path

    /// The headline: a pellet quick enough to clear a thin wall in one step
    /// goes straight through it, and the same pellet told to check its path
    /// bounces off. Same wall, same speed, one parameter.
    @Test func aSweptBodyCannotPassThroughAThinWall() {
        func fire(checksPath: Bool) -> Double {
            let world = World3D()
            world.addBody(.box(width: 6, height: 6, depth: 0.04), at: .zero,
                          kind: .static)
            let pellet = world.addBody(.sphere(radius: 0.05),
                                       at: Vector3(0, 0, -3), gravityScale: 0,
                                       checksPath: checksPath)
            pellet.velocity = Vector3(0, 0, 40)
            run(world, steps: 60)
            return pellet.position.z
        }
        #expect(fire(checksPath: false) > 5, "it went straight through")
        #expect(fire(checksPath: true) < 0, "swept, it never got past the wall")
    }

    /// And it costs the simulation nothing while the body is slow: the check
    /// only runs once a body covers a good fraction of its own size in a step,
    /// so an ordinary throw lands on exactly the same spot either way.
    @Test func checkingThePathChangesNothingWhileTheBodyIsSlow() {
        func throwIt(checksPath: Bool) -> Vector3 {
            let world = World3D()
            world.ground = 0
            let ball = world.addBody(.sphere(radius: 0.3), at: Vector3(0, 3, 0),
                                     checksPath: checksPath)
            ball.velocity = Vector3(1, 0, 0.5)
            run(world, steps: 240)
            return ball.position
        }
        let discrete = throwIt(checksPath: false), swept = throwIt(checksPath: true)
        #expect(discrete.x == swept.x && discrete.y == swept.y
                && discrete.z == swept.z,
                "\(discrete) vs \(swept)")
    }

    /// Reading it back, and setting it after the body is already moving (which
    /// is when a sketch usually knows the body turned out to be fast).
    @Test func checkingThePathCanBeTurnedOnAfterTheBodyIsMoving() {
        let world = World3D()
        world.addBody(.box(width: 6, height: 6, depth: 0.04), at: .zero,
                      kind: .static)
        let pellet = world.addBody(.sphere(radius: 0.05), at: Vector3(0, 0, -3),
                                   gravityScale: 0)
        #expect(!pellet.checksPath)
        pellet.checksPath = true
        #expect(pellet.checksPath)
        pellet.velocity = Vector3(0, 0, 40)
        run(world, steps: 60)
        #expect(pellet.position.z < 0, "the wall stopped it")
    }

    // MARK: The floor's own group

    /// The floor slab is rebuilt whenever the ground level or the unit scale
    /// moves, and it comes back in the group it was put in rather than the
    /// default one: what a bead was told to ignore, it still ignores.
    @Test func theFloorKeepsItsCollisionGroupWhenTheGroundMoves() {
        let world = World3D()
        world.ground = 0
        world.groundBody?.group = "road"
        world.ground = 2
        #expect(world.groundBody?.group == "road", "moving the floor kept it")
        world.unitsPerMeter = 10
        #expect(world.groundBody?.group == "road", "and so did rescaling")
    }

    /// Which is what makes the rule keep working: a body that ignores the
    /// floor's group falls through it, before and after the floor moves.
    @Test func aBodyIgnoringTheFloorsGroupStillFallsThroughItAfterAMove() {
        func drop(movingTheGroundFirst: Bool) -> Double {
            let world = World3D()
            world.ground = 0
            world.groundBody?.group = "road"
            world.ignoreCollisions(between: "road", and: "ghost")
            if movingTheGroundFirst { world.ground = 0.5 }
            let ball = world.addBody(.sphere(radius: 0.3), at: Vector3(0, 4, 0),
                                     group: "ghost")
            run(world, steps: 120)
            return ball.position.y
        }
        #expect(drop(movingTheGroundFirst: false) < -5, "it fell through")
        #expect(drop(movingTheGroundFirst: true) < -5,
                "and still does after the floor was rebuilt")
    }

    // MARK: Determinism

    /// The suite's standing rule: the same scene stepped twice in one binary
    /// lands on exactly the same numbers, parameters and all.
    @Test func aWorldWithMotionParametersReplaysIdentically() {
        func replay() -> [Vector3] {
            let world = World3D()
            world.ground = 0
            let flat = world.addBody(.box(width: 1, height: 1, depth: 1),
                                     at: Vector3(0, 3, 0), freedom: .plane())
            let light = world.addBody(.sphere(radius: 0.4), at: Vector3(1, 5, 0),
                                      gravityScale: 0.3)
            let quick = world.addBody(.sphere(radius: 0.05), at: Vector3(-2, 2, 0),
                                      checksPath: true)
            quick.velocity = Vector3(30, 0, 0)
            run(world, steps: 180)
            return [flat.position, light.position, quick.position]
        }
        let first = replay(), second = replay()
        for (a, b) in zip(first, second) {
            #expect(a.x == b.x && a.y == b.y && a.z == b.z, "\(a) vs \(b)")
        }
    }
}
