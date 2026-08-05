import Foundation
import Testing
import Ollin
@testable import OllinPhysics

/// Correctness for the joints beyond the basic set: a track a body rides, a
/// rope over two pulleys, a joint written as the freedoms it allows, and the
/// two links that tie one joint's motion to another's (gears, and a rack and
/// pinion). Plus the swing-twist motors, which used to be refused.
///
/// Behavioral (the no-pixel-snapshot policy for physics), each answer pinned
/// against a counterfactual twin: the same scene run twice with one thing
/// changed, so a passing test can't be explained by the geometry alone.
/// Parallel-safe like the rest of the 3D suite.
struct JointKind3DTests {

    func run(_ world: World3D, steps: Int, dt: Double = 1.0 / 60) {
        for _ in 0 ..< steps { world.step(dt: dt) }
    }

    /// A ring of points on a circle of `radius`, which is the shape most of
    /// these tracks take (its length is a number we can check progress against).
    func ring(radius: Double, count: Int = 16) -> [Vector3] {
        (0 ..< count).map { i in
            let a = Double(i) / Double(count) * 2 * .pi
            return Vector3(cos(a) * radius, 0, sin(a) * radius)
        }
    }

    // MARK: A track to ride

    /// A body threaded onto a track and a loose twin, both thrown the same way:
    /// the loose one leaves, the threaded one is still on its circle.
    @Test func aTrackHoldsItsBodyOnTheCurve() {
        let world = World3D()
        world.ground = nil
        let rails = world.addBody(.box(width: 0.2, height: 0.2, depth: 0.2),
                                  at: .zero, kind: .static)
        let loose = world.addBody(.box(width: 0.6, height: 0.4, depth: 0.6),
                                  at: Vector3(4, 0, 0))
        let railed = world.addBody(.box(width: 0.6, height: 0.4, depth: 0.6),
                                   at: Vector3(4, 0, 0))
        world.connect(rails, railed, .path(through: ring(radius: 4), looping: true))
        for body in [loose, railed] { body.velocity = Vector3(0, -3, 6) }
        run(world, steps: 120)

        let onTrack = Vector2(railed.position.x, railed.position.z).length
        #expect(abs(onTrack - 4) < 0.05, "the railed body holds its circle")
        #expect(abs(railed.position.y) < 0.05, "and its height")
        #expect(loose.position.y < -20, "where the loose twin falls away")
    }

    /// Driven along its track at a known rate, a body's progress is the
    /// distance it has covered over the length of the whole curve.
    @Test func progressCountsTheDistanceCovered() {
        let world = World3D()
        world.ground = nil
        let rails = world.addBody(.box(width: 0.2, height: 0.2, depth: 0.2),
                                  at: .zero, kind: .static)
        let cart = world.addBody(.box(width: 0.6, height: 0.4, depth: 0.6),
                                 at: Vector3(4, 0, 0), gravityScale: 0)
        let ride = world.connect(rails, cart,
                                 .path(through: ring(radius: 4), looping: true))
        ride.drive(at: 4)
        run(world, steps: 120)
        // Two seconds at four units a second, on a circle of circumference 8pi.
        #expect(abs(ride.progress - 8 / (8 * .pi)) < 0.01)
    }

    /// A looping track wraps back past its end; an open one stops there.
    @Test func aLoopingTrackWrapsAndAnOpenOneStops() {
        func finalProgress(looping: Bool) -> Double {
            let world = World3D()
            world.ground = nil
            let rails = world.addBody(.box(width: 0.2, height: 0.2, depth: 0.2),
                                      at: .zero, kind: .static)
            let cart = world.addBody(.box(width: 0.6, height: 0.4, depth: 0.6),
                                     at: Vector3(4, 0, 0), gravityScale: 0)
            let ride = world.connect(rails, cart,
                                     .path(through: ring(radius: 4), looping: looping))
            ride.drive(at: 6)
            run(world, steps: 360)
            return ride.progress
        }
        #expect(finalProgress(looping: false) > 0.99, "an open track ends at its end")
        let looped = finalProgress(looping: true)
        #expect(looped >= 0 && looped < 0.9, "a loop is round again and past 0")
    }

    /// The position motor seeks a fraction of the whole curve and holds there.
    @Test func aTrackMotorSeeksAFractionOfTheCurve() {
        let world = World3D()
        world.ground = nil
        let rails = world.addBody(.box(width: 0.2, height: 0.2, depth: 0.2),
                                  at: .zero, kind: .static)
        let cart = world.addBody(.box(width: 0.6, height: 0.4, depth: 0.6),
                                 at: Vector3(4, 0, 0), gravityScale: 0)
        let ride = world.connect(rails, cart, .path(through: ring(radius: 4)))
        ride.drive(to: 0.5, frequency: 3)
        run(world, steps: 180)
        #expect(abs(ride.progress - 0.5) < 0.01)
        // Half way round a circle from (4, 0, 0) is the far side.
        #expect(cart.position.x < -3.5)
    }

    /// The same ride with the track turning the body and without it: only the
    /// aligned one comes round facing a different way.
    @Test func alignmentDecidesWhetherTheBodyTurnsWithTheTrack() {
        func turn(_ alignment: JointKind3D.PathAlignment) -> Double {
            let world = World3D()
            world.ground = nil
            let rails = world.addBody(.box(width: 0.2, height: 0.2, depth: 0.2),
                                      at: .zero, kind: .static)
            let cart = world.addBody(.box(width: 0.6, height: 0.4, depth: 0.6),
                                     at: Vector3(4, 0, 0), gravityScale: 0)
            let ride = world.connect(rails, cart,
                                     .path(through: ring(radius: 4), looping: true,
                                           alignment: alignment))
            ride.drive(at: 6)
            run(world, steps: 90)
            return cart.rotationAngle
        }
        #expect(turn(.free) < 0.01, "left free, the body never turns")
        #expect(turn(.followsPath) > 1.5, "following the track, it swings round")
    }

    /// A track drawn as a flat contour lands in the world's ground plane: the
    /// contour's x is the world's x, and its y the world's z.
    @Test func aContourBecomesATrackOnTheGround() {
        let contour = Contour([Vector2(4, 0), Vector2(0, 4),
                               Vector2(-4, 0), Vector2(0, -4)], closed: true)
        guard case .path(let points, let looping, _) =
            JointKind3D.path(contour, atHeight: 1.5) else {
            Issue.record("the contour form should make a .path")
            return
        }
        #expect(looping, "a closed contour makes a looping track")
        #expect(points.count == 4)
        #expect(points[1] == Vector3(0, 1.5, 4), "contour y runs along world z")
    }

    /// Two points on top of each other say nothing about a curve, so a track
    /// that has no length is refused rather than silently drawn as a knot.
    @Test func aTrackNeedsTwoPointsThatAreApart() {
        let world = World3D()
        world.ground = nil
        let rails = world.addBody(.box(width: 0.2, height: 0.2, depth: 0.2),
                                  at: .zero, kind: .static)
        let cart = world.addBody(.box(width: 0.4, height: 0.4, depth: 0.4),
                                 at: Vector3(0, 3, 0))
        let dud = world.connect(rails, cart,
                                .path(through: [Vector3(1, 0, 0), Vector3(1, 0, 0)]))
        #expect(dud.constraint == nil)
        run(world, steps: 60)
        #expect(cart.position.y < 2, "and the body is simply left to fall")
    }

    // MARK: A rope over two pulleys

    /// One side of a rope rising is the other side falling, and the total
    /// length is what says so: the heavier body wins and hauls the lighter up.
    @Test func aPulleyTradesOneSideForTheOther() {
        let world = World3D()
        world.ground = nil
        let heavy = world.addBody(.box(width: 1, height: 1, depth: 1),
                                  at: Vector3(-3, 6, 0), density: 4)
        let light = world.addBody(.box(width: 1, height: 1, depth: 1),
                                  at: Vector3(3, 6, 0), density: 1)
        world.connect(heavy, light,
                      .pulley(from: Vector3(-3, 6.5, 0), over: Vector3(-3, 12, 0),
                              and: Vector3(3, 12, 0), to: Vector3(3, 6.5, 0)))
        run(world, steps: 90)
        let dropped = 6 - heavy.position.y
        let rose = light.position.y - 6
        #expect(dropped > 3, "the heavy side falls")
        #expect(abs(dropped - rose) < 0.3, "and the light side rises as far")
    }

    /// The same fall with the light side threaded twice: it moves half as far,
    /// which is the whole point of a block and tackle.
    @Test func aPulleyRatioIsHowManyFallsHoldTheSecondSide() {
        func rise(ratio: Double) -> (dropped: Double, rose: Double) {
            let world = World3D()
            world.ground = nil
            let heavy = world.addBody(.box(width: 1, height: 1, depth: 1),
                                      at: Vector3(-3, 6, 0), density: 4)
            let light = world.addBody(.box(width: 1, height: 1, depth: 1),
                                      at: Vector3(3, 6, 0), density: 1)
            world.connect(heavy, light,
                          .pulley(from: Vector3(-3, 6.5, 0), over: Vector3(-3, 12, 0),
                                  and: Vector3(3, 12, 0), to: Vector3(3, 6.5, 0),
                                  ratio: ratio))
            run(world, steps: 90)
            return (6 - heavy.position.y, light.position.y - 6)
        }
        let single = rise(ratio: 1)
        let doubled = rise(ratio: 2)
        #expect(abs(single.dropped - single.rose) < 0.3)
        #expect(abs(doubled.dropped / 2 - doubled.rose) < 0.3,
                "threaded twice, the light side moves half as far")
    }

    /// A rope can be let slack but not stretched; a taut one is a linkage, so
    /// lifting one end pushes the other end down.
    @Test func aTautRopePushesWhereALooseOneOnlyPulls() {
        func otherEnd(taut: Bool) -> Double {
            let world = World3D()
            world.ground = nil
            let lifted = world.addBody(.box(width: 1, height: 1, depth: 1),
                                       at: Vector3(-3, 4, 0), gravityScale: 0)
            let other = world.addBody(.box(width: 1, height: 1, depth: 1),
                                      at: Vector3(3, 4, 0), gravityScale: 0)
            world.connect(lifted, other,
                          .pulley(from: Vector3(-3, 4.5, 0), over: Vector3(-3, 10, 0),
                                  and: Vector3(3, 10, 0), to: Vector3(3, 4.5, 0),
                                  taut: taut))
            lifted.velocity = Vector3(0, 2, 0)
            run(world, steps: 60)
            return other.position.y
        }
        #expect(abs(otherEnd(taut: false) - 4) < 0.01, "a slack rope pushes nothing")
        #expect(otherEnd(taut: true) < 3.2, "a taut one drives the far end down")
    }

    /// The solver's pulley reads a kinematic body as an ordinary one, so that
    /// case is refused rather than left to misbehave.
    @Test func aPulleyRefusesAKinematicEnd() {
        let world = World3D()
        world.ground = nil
        let hoist = world.addBody(.box(width: 1, height: 1, depth: 1),
                                  at: Vector3(-3, 4, 0), kind: .kinematic)
        let load = world.addBody(.box(width: 1, height: 1, depth: 1),
                                 at: Vector3(3, 4, 0))
        let rope = world.connect(hoist, load,
                                 .pulley(from: Vector3(-3, 4.5, 0),
                                         over: Vector3(-3, 10, 0),
                                         and: Vector3(3, 10, 0),
                                         to: Vector3(3, 4.5, 0)))
        #expect(rope.constraint == nil)
        run(world, steps: 30)   // and the world still steps
        #expect(load.position.y < 4)
    }

    // MARK: The joint written as its freedoms

    /// A body on a joint that allows rising and spinning does exactly those
    /// two things: thrown sideways and tumbled, it keeps its post and its axis.
    @Test func allowingKeepsOnlyTheFreedomsItNames() {
        let world = World3D()
        world.ground = nil
        let post = world.addBody(.box(width: 0.3, height: 1, depth: 0.3),
                                 at: Vector3(0, 0.5, 0), kind: .static)
        let platter = world.addBody(.cylinder(height: 0.2, radius: 1),
                                    at: Vector3(0, 6, 0))
        world.connect(post, platter,
                      .allowing([.moveY, .turnY], at: Vector3(0, 6, 0),
                                travel: -2 ... 0.01))
        platter.velocity = Vector3(6, 0, 6)
        platter.angularVelocity = Vector3(3, 5, 3)
        run(world, steps: 180)

        #expect(abs(platter.position.x) < 1e-3, "no travel across")
        #expect(abs(platter.position.z) < 1e-3)
        #expect(abs(platter.angularVelocity.x) < 1e-3, "and no tumbling")
        #expect(abs(platter.angularVelocity.z) < 1e-3)
        #expect(platter.angularVelocity.y > 3, "but it keeps spinning about y")
        #expect(abs(platter.position.y - 4) < 0.01, "and stops at its travel limit")
    }

    /// The same joint with nothing allowed is a weld: a body given every kind
    /// of push does not move at all.
    @Test func allowingNothingIsAWeld() {
        let world = World3D()
        world.ground = nil
        let anchor = world.addBody(.box(width: 0.4, height: 0.4, depth: 0.4),
                                   at: .zero, kind: .static)
        let held = world.addBody(.box(width: 0.4, height: 0.4, depth: 0.4),
                                 at: Vector3(0, -2, 0))
        world.connect(anchor, held, .allowing([], at: Vector3(0, -2, 0)))
        held.velocity = Vector3(5, 0, 5)
        held.angularVelocity = Vector3(4, 4, 4)
        run(world, steps: 120)
        #expect(held.position.distance(to: Vector3(0, -2, 0)) < 1e-3)
        #expect(held.rotationAngle < 1e-3)
    }

    /// A turning freedom can be bounded too: a spinning vane runs up to its
    /// stop and holds there, where an unbounded twin keeps going.
    @Test func aTurningFreedomTakesItsOwnLimits() {
        func spun(rotation: ClosedRange<Double>?) -> (angle: Double, spin: Double) {
            let world = World3D()
            world.ground = nil
            let frame = world.addBody(.box(width: 0.3, height: 0.3, depth: 0.3),
                                      at: .zero, kind: .static)
            let vane = world.addBody(.box(width: 2, height: 0.2, depth: 0.4),
                                     at: .zero, gravityScale: 0)
            world.connect(frame, vane, .allowing([.turnY], at: .zero,
                                                 rotation: rotation))
            vane.angularVelocity = Vector3(0, 6, 0)
            run(world, steps: 120)
            return (vane.rotationAngle, vane.angularVelocity.y)
        }
        let bounded = spun(rotation: -0.5 ... 0.5)
        #expect(bounded.angle < 0.55 && bounded.angle > 0.35, "stopped at its limit")
        #expect(abs(bounded.spin) < 0.1, "and stopped turning")
        #expect(abs(spun(rotation: nil).spin) > 5, "where the free twin keeps going")
    }

    // MARK: Gears

    /// A hinge driving another through a gear, and the same pair with no gear
    /// between them: only the geared partner turns, and it turns the other way.
    @Test func aGearTurnsItsPartnerTheOtherWay() {
        func partnerSpin(geared: Bool) -> Double {
            let world = World3D()
            world.ground = nil
            let frame = world.addBody(.box(width: 0.2, height: 0.2, depth: 0.2),
                                      at: .zero, kind: .static)
            let driver = world.addBody(.cylinder(height: 0.2, radius: 0.5),
                                       at: Vector3(0, 2, 0), gravityScale: 0)
            let follower = world.addBody(.cylinder(height: 0.2, radius: 0.5),
                                         at: Vector3(2, 2, 0), gravityScale: 0)
            let hingeA = world.connect(frame, driver,
                                       .revolute(at: Vector3(0, 2, 0), axis: .unitZ))
            let hingeB = world.connect(frame, follower,
                                       .revolute(at: Vector3(2, 2, 0), axis: .unitZ))
            if geared { world.connect(hingeA, hingeB, .gear(ratio: 1)) }
            hingeA.drive(at: 2)
            run(world, steps: 60)
            return follower.angularVelocity.z
        }
        #expect(abs(partnerSpin(geared: false)) < 1e-3, "ungeared, it just sits")
        #expect(abs(partnerSpin(geared: true) + 2) < 0.01,
                "geared one to one, it turns as fast the other way")
    }

    /// The ratio is how many turns the first gear makes per turn of the second,
    /// whether it is given as a number or as two tooth counts.
    @Test func aGearRatioIsTurnsPerTurn() {
        func partnerSpin(_ link: JointLink3D) -> Double {
            let world = World3D()
            world.ground = nil
            let frame = world.addBody(.box(width: 0.2, height: 0.2, depth: 0.2),
                                      at: .zero, kind: .static)
            let driver = world.addBody(.cylinder(height: 0.2, radius: 0.5),
                                       at: Vector3(0, 2, 0), gravityScale: 0)
            let follower = world.addBody(.cylinder(height: 0.2, radius: 1.5),
                                         at: Vector3(2.2, 2, 0), gravityScale: 0)
            let hingeA = world.connect(frame, driver,
                                       .revolute(at: Vector3(0, 2, 0), axis: .unitZ))
            let hingeB = world.connect(frame, follower,
                                       .revolute(at: Vector3(2.2, 2, 0), axis: .unitZ))
            world.connect(hingeA, hingeB, link)
            hingeA.drive(at: 3)
            run(world, steps: 60)
            return follower.angularVelocity.z
        }
        #expect(abs(partnerSpin(.gear(ratio: 3)) + 1) < 0.01,
                "three to one: the big wheel turns a third as fast")
        #expect(abs(partnerSpin(.gear(teeth: 10, and: 30)) + 1) < 0.01,
                "and tooth counts say the same thing")
    }

    /// A gear needs two hinges. Anything else is refused rather than half
    /// applied, and the world keeps running.
    @Test func aGearRefusesWhatIsNotAPairOfHinges() {
        let world = World3D()
        world.ground = nil
        let frame = world.addBody(.box(width: 0.2, height: 0.2, depth: 0.2),
                                  at: .zero, kind: .static)
        let wheel = world.addBody(.cylinder(height: 0.2, radius: 0.5),
                                  at: Vector3(0, 2, 0), gravityScale: 0)
        let carriage = world.addBody(.box(width: 1, height: 0.2, depth: 0.2),
                                     at: Vector3(0, 5, 0), gravityScale: 0)
        let hinge = world.connect(frame, wheel,
                                  .revolute(at: Vector3(0, 2, 0), axis: .unitZ))
        let slider = world.connect(frame, carriage,
                                   .prismatic(at: Vector3(0, 5, 0), axis: .unitX))
        #expect(world.connect(slider, hinge, .gear(ratio: 1)).constraint == nil,
                "a gear cannot start from a slider")
        #expect(world.connect(hinge, slider, .gear(ratio: 1)).constraint == nil,
                "nor end at one")
        #expect(world.connect(hinge, slider,
                              .rackAndPinion(travelPerTurn: 1)).constraint != nil,
                "which is what a rack and pinion is for")
    }

    /// Removing a geared body takes the gear with it, and the survivor is
    /// still drivable.
    @Test func removingAGearCutsTheLink() {
        let world = World3D()
        world.ground = nil
        let frame = world.addBody(.box(width: 0.2, height: 0.2, depth: 0.2),
                                  at: .zero, kind: .static)
        let driver = world.addBody(.cylinder(height: 0.2, radius: 0.5),
                                   at: Vector3(0, 2, 0), gravityScale: 0)
        let follower = world.addBody(.cylinder(height: 0.2, radius: 0.5),
                                     at: Vector3(2, 2, 0), gravityScale: 0)
        let hingeA = world.connect(frame, driver,
                                   .revolute(at: Vector3(0, 2, 0), axis: .unitZ))
        let hingeB = world.connect(frame, follower,
                                   .revolute(at: Vector3(2, 2, 0), axis: .unitZ))
        world.connect(hingeA, hingeB, .gear(ratio: 1))
        #expect(world.joints.count == 3)
        hingeA.drive(at: 3)
        run(world, steps: 30)

        world.remove(follower)
        #expect(world.joints.count == 1, "the gear goes with its wheel")
        run(world, steps: 30)
        #expect(abs(driver.angularVelocity.z - 3) < 0.01, "the driver runs on")
    }

    // MARK: A rack and a pinion

    /// One turn of the pinion moves the rack exactly the distance asked for,
    /// and doubling that distance doubles the travel.
    @Test func aPinionMovesItsRackByTheTravelAsked() {
        func travelled(perTurn: Double) -> Double {
            let world = World3D()
            world.ground = nil
            let frame = world.addBody(.box(width: 0.2, height: 0.2, depth: 0.2),
                                      at: .zero, kind: .static)
            let pinion = world.addBody(.cylinder(height: 0.2, radius: 0.5),
                                       at: Vector3(0, 2, 0), gravityScale: 0)
            let rack = world.addBody(.box(width: 6, height: 0.2, depth: 0.2),
                                     at: Vector3(0, 1.4, 0), gravityScale: 0)
            let hinge = world.connect(frame, pinion,
                                      .revolute(at: Vector3(0, 2, 0), axis: .unitZ))
            let slider = world.connect(frame, rack,
                                       .prismatic(at: Vector3(0, 1.4, 0), axis: .unitX))
            world.connect(hinge, slider, .rackAndPinion(travelPerTurn: perTurn))
            hinge.drive(at: 2 * .pi)     // exactly one turn a second
            run(world, steps: 60)
            return slider.offset
        }
        #expect(abs(travelled(perTurn: 2) - 2) < 0.05)
        #expect(abs(travelled(perTurn: 4) - 4) < 0.05)
        #expect(abs(travelled(perTurn: -2) + 2) < 0.05, "a negative one runs back")
    }

    // MARK: Swing-twist motors

    /// A swing-twist joint told to roll to an angle rolls to it, and leaves the
    /// bend it is free to make alone.
    @Test func aSwingTwistMotorRollsWithoutBending() {
        let world = World3D()
        world.ground = nil
        world.ignoreCollisions(between: "hub", and: "bone")
        let anchor = world.addBody(.box(width: 0.4, height: 0.4, depth: 0.4),
                                   at: .zero, kind: .static, group: "hub")
        let bone = world.addBody(.capsule(height: 1.4, radius: 0.2),
                                 at: Vector3(0, -0.9, 0), group: "bone")
        let joint = world.connect(anchor, bone,
                                  .swingTwist(at: .zero, axis: Vector3(0, -1, 0),
                                              swing: 40 * .pi / 180,
                                              twist: -1.2 ... 1.2))
        joint.drive(to: 0.9, frequency: 10)
        run(world, steps: 240)
        #expect(abs(joint.twist - 0.9) < 0.01)
        #expect(joint.angle < 0.01, "the bone is still hanging straight")
    }

    /// The rate form runs the roll at the speed asked for.
    @Test func aSwingTwistMotorRollsAtTheRateAsked() {
        let world = World3D()
        world.ground = nil
        world.ignoreCollisions(between: "hub", and: "bone")
        let anchor = world.addBody(.box(width: 0.4, height: 0.4, depth: 0.4),
                                   at: .zero, kind: .static, group: "hub")
        let bone = world.addBody(.capsule(height: 1.4, radius: 0.2),
                                 at: Vector3(0, -0.9, 0), group: "bone")
        let joint = world.connect(anchor, bone,
                                  .swingTwist(at: .zero, axis: Vector3(0, -1, 0),
                                              swing: 40 * .pi / 180,
                                              twist: -1.2 ... 1.2))
        joint.drive(at: 1)
        run(world, steps: 60)
        #expect(abs(joint.twist - 1) < 0.02, "a radian a second for a second")
    }

    /// Pointed at a direction, the bone goes there and stays; asked past its
    /// cone, it leans as far as the cone allows; let go, it falls back.
    @Test func aSwingTwistJointCanBePointedSomewhere() {
        func lean(toward direction: Vector3, cone: Double) -> Double {
            let world = World3D()
            world.ground = nil
            world.ignoreCollisions(between: "hub", and: "bone")
            let anchor = world.addBody(.box(width: 0.4, height: 0.4, depth: 0.4),
                                       at: .zero, kind: .static, group: "hub")
            let bone = world.addBody(.capsule(height: 1.4, radius: 0.2),
                                     at: Vector3(0, -0.9, 0), gravityScale: 0,
                                     group: "bone")
            let joint = world.connect(anchor, bone,
                                      .swingTwist(at: .zero, axis: Vector3(0, -1, 0),
                                                  swing: cone, twist: -1.2 ... 1.2))
            joint.drive(toward: direction, frequency: 8)
            run(world, steps: 240)
            return joint.angle
        }
        let wide = 170 * Double.pi / 180
        #expect(abs(lean(toward: Vector3(sin(0.6), -cos(0.6), 0), cone: wide) - 0.6) < 0.01,
                "it goes exactly where it is pointed")
        let narrow = 80 * Double.pi / 180
        #expect(abs(lean(toward: Vector3(1, 0, 0), cone: narrow) - narrow) < 0.05,
                "and no further than its cone")
    }

    /// A powered joint holds its bone up; cut the power and gravity takes it.
    @Test func stoppingASwingTwistMotorLetsTheBoneFall() {
        let world = World3D()
        world.ground = nil
        world.ignoreCollisions(between: "hub", and: "bone")
        let anchor = world.addBody(.box(width: 0.4, height: 0.4, depth: 0.4),
                                   at: .zero, kind: .static, group: "hub")
        let bone = world.addBody(.capsule(height: 1.4, radius: 0.2),
                                 at: Vector3(0, -0.9, 0), group: "bone")
        let joint = world.connect(anchor, bone,
                                  .swingTwist(at: .zero, axis: Vector3(0, -1, 0),
                                              swing: 80 * .pi / 180,
                                              twist: -1.2 ... 1.2))
        joint.drive(toward: Vector3(1, 0, 0), frequency: 8)
        run(world, steps: 240)
        let held = joint.angle
        #expect(held > 1.2, "held up against gravity")

        joint.stopMotor()
        run(world, steps: 240)
        #expect(joint.angle < held - 0.5, "and it drops once the power is cut")
    }

    // MARK: Determinism

    /// The whole family, run twice in the same binary, lands on the same
    /// numbers: the arc's replay rule (no pixel snapshots, but exact replays).
    @Test func theseJointsReplayIdentically() {
        func once() -> [Double] {
            let world = World3D()
            world.ground = 0
            let frame = world.addBody(.box(width: 0.2, height: 0.2, depth: 0.2),
                                      at: Vector3(0, 3, 0), kind: .static)
            let small = world.addBody(.cylinder(height: 0.2, radius: 0.5),
                                      at: Vector3(0, 3, 0))
            let big = world.addBody(.cylinder(height: 0.2, radius: 1),
                                    at: Vector3(2, 3, 0))
            let hingeA = world.connect(frame, small,
                                       .revolute(at: Vector3(0, 3, 0), axis: .unitZ))
            let hingeB = world.connect(frame, big,
                                       .revolute(at: Vector3(2, 3, 0), axis: .unitZ))
            world.connect(hingeA, hingeB, .gear(ratio: 2))
            hingeA.drive(at: 4, strength: 40)

            let cart = world.addBody(.box(width: 0.4, height: 0.3, depth: 0.4),
                                     at: Vector3(3, 1, 0))
            let ride = world.connect(frame, cart,
                                     .path(through: ring(radius: 3, count: 12),
                                           looping: true))
            ride.drive(at: 3)
            run(world, steps: 180)
            return [big.rotationAngle, cart.position.x, cart.position.z, ride.progress]
        }
        #expect(once() == once())
    }
}
