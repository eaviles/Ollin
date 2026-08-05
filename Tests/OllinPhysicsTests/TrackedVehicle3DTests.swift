import Foundation
import Testing
import Ollin
@testable import OllinPhysics

/// Correctness for the tracked machine: the road wheels split into two bands by
/// which side of the hull they sit on, steering reaches the ground through
/// those bands rather than through a steering rack, full lock spins the machine
/// on the spot, and the brakes slow both tracks. Behavioral (the
/// no-pixel-snapshot policy for physics), each knob pinned against a
/// counterfactual twin: the same machine run twice with one thing changed.
/// Parallel-safe like the rest of the 3D suite.
struct TrackedVehicle3DTests {

    /// A crawler: five road wheels a side on a hull five units long. `sprocket`
    /// names which wheel of each band the engine turns (`nil` leaves it to the
    /// rearmost), and `grip` slicks the tracks so a slope test has something to
    /// vary.
    static func crawler(in world: World3D, at position: Vector3 = Vector3(0, 1.2, 0),
                        mass: Double = 4000, engineTorque: Double = 500,
                        topSpeed: Double = 10, grip: Double = 1,
                        sprocket: Int? = nil, oneSided: Bool = false) -> Vehicle3D? {
        var wheels: [Wheel3D] = []
        for side in [1.05, oneSided ? 0.85 : -1.05] {
            for i in 0 ..< 5 {
                let wheel = Wheel3D.wheel(at: Vector3(side, -0.3, -1.8 + Double(i) * 0.9),
                                          radius: 0.42, width: 0.5,
                                          driven: sprocket == i)
                wheel.suspensionLength = 0.35
                wheel.suspensionTravel = 0.25
                wheel.suspensionFrequency = 2
                wheel.grip = grip
                wheels.append(wheel)
            }
        }
        return world.addVehicle(.box(width: 2.6, height: 1, depth: 5),
                                at: position, wheels: wheels, mass: mass,
                                engineTorque: engineTorque, topSpeed: topSpeed,
                                friction: 0.9, tracked: true)
    }

    func run(_ world: World3D, steps: Int) {
        for _ in 0 ..< steps { world.step(dt: 1.0 / 60) }
    }

    /// A world with a floor and a settled crawler standing on it.
    func standing(grip: Double = 1, engineTorque: Double = 500,
                  topSpeed: Double = 10) -> (World3D, Vehicle3D) {
        let world = World3D()
        world.ground = 0
        let crawler = Self.crawler(in: world, engineTorque: engineTorque,
                                   topSpeed: topSpeed, grip: grip)!
        run(world, steps: 120)
        return (world, crawler)
    }

    /// Which way the machine is pointing, in radians about the world up.
    func heading(_ vehicle: Vehicle3D) -> Double {
        let forward = vehicle.forward
        return atan2(forward.x, forward.z)
    }

    // MARK: Standing on its tracks

    @Test func restsOnItsRoadWheelsWithEveryOneDown() {
        let (world, crawler) = standing()

        #expect(crawler.isTracked)
        #expect(crawler.isOnGround)
        #expect(crawler.wheels.allSatisfy { $0.isOnGround })
        for wheel in crawler.wheels {
            #expect(abs(wheel.center.y - wheel.radius) < 0.03)
            #expect(wheel.groundBody === world.groundBody)
        }
        #expect(abs(crawler.body.mass - 4000) < 1)
    }

    /// The bands are worked out from where the wheels sit, not from the order
    /// they were listed: the driver's right is -x, so the left band carries the
    /// wheels at positive x.
    @Test func theWheelsSplitIntoTwoBandsBySideOfTheHull() {
        let (_, crawler) = standing()

        let left = crawler.wheels(on: .left)
        let right = crawler.wheels(on: .right)
        #expect(left.count == 5)
        #expect(right.count == 5)
        #expect(left.allSatisfy { $0.position.x > 0 })
        #expect(right.allSatisfy { $0.position.x < 0 })
        // Front of the machine first, so a drawing loop can lay a band around
        // them in order.
        #expect(left.map(\.position.z) == left.map(\.position.z).sorted(by: >))
    }

    /// A band is turned at one sprocket however many wheels were marked, and
    /// with nothing marked it is the rearmost.
    @Test func eachBandIsTurnedAtOneSprocket() {
        let (_, byDefault) = standing()
        let driven = byDefault.wheels.filter(\.driven)
        #expect(driven.count == 2)
        #expect(driven.allSatisfy { $0.position.z == -1.8 })

        let world = World3D()
        world.ground = 0
        let asked = Self.crawler(in: world, sprocket: 4)!
        #expect(asked.wheels.filter(\.driven).count == 2)
        #expect(asked.wheels.filter(\.driven).allSatisfy { $0.position.z == 1.8 })
    }

    /// Both bands are needed: a machine whose wheels all sit on one side of the
    /// hull is refused rather than half-built.
    @Test func aMachineWithOnlyOneBandIsRefused() {
        let world = World3D()
        world.ground = 0
        #expect(Self.crawler(in: world, oneSided: true) == nil)
        // And the chassis body it would have ridden on goes with it.
        #expect(world.bodies.isEmpty)
    }

    // MARK: Driving

    @Test func theThrottleDrivesItForward() {
        let (drivenWorld, driven) = standing()
        driven.throttle = 1
        run(drivenWorld, steps: 300)

        let (idleWorld, idle) = standing()
        run(idleWorld, steps: 300)

        #expect(driven.body.position.z > 15)
        #expect(driven.speed > 8)
        #expect(abs(idle.body.position.z) < 0.1)
    }

    /// Both bands run together in a straight line, at the speed the machine is
    /// travelling: what a drawn track is scrolled by.
    @Test func bothBandsRunTogetherInAStraightLine() {
        let (world, crawler) = standing()
        crawler.throttle = 1
        run(world, steps: 300)

        #expect(abs(crawler.trackSpeed(.left) - crawler.trackSpeed(.right)) < 0.05)
        #expect(abs(crawler.trackSpeed(.left) - crawler.speed) < 0.5)
    }

    @Test func aLowerTopSpeedGearsItDownToASlowerCeiling() {
        let (slowWorld, slow) = standing(topSpeed: 5)
        slow.throttle = 1
        run(slowWorld, steps: 900)

        let (fastWorld, fast) = standing(topSpeed: 16)
        fast.throttle = 1
        run(fastWorld, steps: 900)

        #expect(slow.speed < 6)
        #expect(fast.speed > 12)
    }

    // MARK: Steering, which is the drivetrain

    /// The headline difference: a machine with nothing to steer turns by
    /// running one band against the other, so full lock spins it where it
    /// stands. Its twin, given the same throttle and no steering, drives away.
    @Test func fullLockSpinsItOnTheSpot() {
        let (pivotWorld, pivot) = standing()
        pivot.throttle = 1
        pivot.steering = 1
        let pivotStart = pivot.body.position
        var turned = 0.0
        var was = heading(pivot)
        for _ in 0 ..< 300 {
            pivotWorld.step(dt: 1.0 / 60)
            let now = heading(pivot)
            turned += abs(atan2(sin(now - was), cos(now - was)))
            was = now
        }
        let wandered = Vector2(pivot.body.position.x - pivotStart.x,
                               pivot.body.position.z - pivotStart.z).length

        let (straightWorld, straight) = standing()
        straight.throttle = 1
        run(straightWorld, steps: 300)
        let travelled = straight.body.position.z

        // It turns through more than a full circle without leaving its own
        // length, where the twin covers ground and barely changes heading.
        #expect(turned > 2 * .pi)
        #expect(wandered < 1.5)
        #expect(travelled > 15)
        #expect(abs(heading(straight)) < 0.05)
    }

    @Test func theTwoBandsRunOppositeWaysInAPivot() {
        let (world, crawler) = standing()
        crawler.throttle = 1
        crawler.steering = 1
        run(world, steps: 60)

        #expect(crawler.trackSpeed(.left) > 1)
        #expect(crawler.trackSpeed(.right) < -1)
    }

    /// Half lock stops the inside band instead of reversing it, which is the
    /// turn a machine makes about its own inside track.
    @Test func halfLockStopsTheInsideBand() {
        let (world, crawler) = standing()
        crawler.throttle = 1
        crawler.steering = 0.5
        run(world, steps: 90)

        #expect(crawler.trackSpeed(.left) > 1)
        #expect(abs(crawler.trackSpeed(.right)) < 0.5)
    }

    @Test func positiveSteeringTurnsToTheMachinesRight() {
        let (world, crawler) = standing()
        crawler.throttle = 1
        crawler.steering = 0.6
        run(world, steps: 120)

        // Its own right is -x with forward +z, so turning right swings the
        // heading negative and carries it that way.
        #expect(heading(crawler) < -0.3)
        #expect(crawler.body.position.x < -0.2)
    }

    /// Steering without throttle does nothing, the way it does on a real one:
    /// the bands are turned by the engine, so with the engine idle there is
    /// nothing to run one against the other.
    @Test func steeringNeedsThrottle() {
        let (world, crawler) = standing()
        crawler.steering = 1
        run(world, steps: 180)

        #expect(abs(heading(crawler)) < 0.05)
    }

    /// A road wheel under a band never turns, whatever the steering asks and
    /// whatever `steers` said, and it has no slip to report: it only ever runs
    /// as fast as the band it rides.
    @Test func aRoadWheelNeitherSteersNorSlips() {
        let (world, crawler) = standing()
        crawler.throttle = 1
        crawler.steering = 1
        run(world, steps: 120)

        #expect(crawler.wheels.allSatisfy { $0.steerAngle == 0 })
        #expect(crawler.wheels.allSatisfy { $0.slip == 0 && $0.slideAngle == 0 })
        // The wheels are turning, though: they run with their band.
        #expect(crawler.wheels(on: .left).allSatisfy { $0.spinRate > 1 })
    }

    // MARK: The brake

    @Test func theBrakeStopsItSoonerThanCoasting() {
        func distanceAfterLettingGo(braking: Bool) -> Double {
            let (world, crawler) = standing()
            crawler.throttle = 1
            run(world, steps: 300)
            let from = crawler.body.position.z
            crawler.throttle = 0
            crawler.brake = braking ? 1 : 0
            run(world, steps: 180)
            return crawler.body.position.z - from
        }

        let braked = distanceAfterLettingGo(braking: true)
        let coasted = distanceAfterLettingGo(braking: false)
        #expect(braked < coasted)
        #expect(braked < 0.5 * coasted)
    }

    /// A tracked machine has one brake, so the hand brake pulls the same one
    /// rather than doing nothing.
    @Test func theHandBrakePullsTheSameBrake() {
        func distanceAfterLettingGo(handBraking: Bool) -> Double {
            let (world, crawler) = standing()
            crawler.throttle = 1
            run(world, steps: 300)
            let from = crawler.body.position.z
            crawler.throttle = 0
            crawler.handBrake = handBraking ? 1 : 0
            run(world, steps: 180)
            return crawler.body.position.z - from
        }

        #expect(distanceAfterLettingGo(handBraking: true)
                < 0.5 * distanceAfterLettingGo(handBraking: false))
    }

    /// The brake belongs to the band rather than to a wheel, so a change to a
    /// road wheel's share of it has to reach the drivetrain to mean anything.
    @Test func softeningTheWheelsSoftensTheBandsBrake() {
        func distanceAfterLettingGo(brakeTorque: Double) -> Double {
            let (world, crawler) = standing()
            crawler.throttle = 1
            run(world, steps: 300)
            for wheel in crawler.wheels { wheel.brakeTorque = brakeTorque }
            let from = crawler.body.position.z
            crawler.throttle = 0
            crawler.brake = 1
            run(world, steps: 120)
            return crawler.body.position.z - from
        }

        #expect(distanceAfterLettingGo(brakeTorque: 3000)
                < 0.6 * distanceAfterLettingGo(brakeTorque: 30))
    }

    // MARK: Grip

    /// Slick tracks climb less of the same bank: the band's grip is a flat
    /// coefficient rather than a tire's slip curve, and scaling it scales what
    /// the machine can drag itself up.
    @Test func slickTracksClimbLessOfTheSameBank() {
        func climbed(grip: Double) -> Double {
            let world = World3D()
            world.ground = nil
            let angle = 30 * Double.pi / 180
            world.addBody(.box(width: 24, height: 1, depth: 20),
                          at: Vector3(0, -0.5, -10), kind: .static, friction: 1)
            let along = Vector3(0, sin(angle), cos(angle))
            let normal = Vector3(0, cos(angle), -sin(angle))
            world.addBody(.box(width: 24, height: 1, depth: 25),
                          at: along * 12.5 - normal * 0.5, kind: .static,
                          rotated: -angle, axis: .unitX, friction: 1)
            let crawler = Self.crawler(in: world, at: Vector3(0, 1.2, -6),
                                       grip: grip)!
            run(world, steps: 120)
            let from = crawler.body.position.y
            crawler.throttle = 1
            var highest = 0.0
            for _ in 0 ..< 480 {
                world.step(dt: 1.0 / 60)
                highest = max(highest, crawler.body.position.y - from)
            }
            return highest
        }

        let gripping = climbed(grip: 1)
        let slick = climbed(grip: 0.02)
        #expect(gripping > 10)
        #expect(slick < 2.5)
        #expect(gripping > 4 * slick)
    }

    // MARK: Changing which wheels are driven, live

    /// Moving the sprocket is the gearbox rather than the wheel, so it rebuilds
    /// the drive rather than being refused: the machine keeps driving, and the
    /// flags report what it settled on.
    @Test func movingTheSprocketRebuildsTheDrive() {
        let (world, crawler) = standing()
        #expect(crawler.wheels.filter(\.driven).allSatisfy { $0.position.z == -1.8 })

        // Which wheels drive is set a list at a time, so the drivetrain is
        // rebuilt on the step rather than on each assignment.
        for wheel in crawler.wheels { wheel.driven = wheel.position.z == 1.8 }
        run(world, steps: 1)
        #expect(crawler.wheels.filter(\.driven).count == 2)
        #expect(crawler.wheels.filter(\.driven).allSatisfy { $0.position.z == 1.8 })

        crawler.throttle = 1
        run(world, steps: 300)
        #expect(crawler.body.position.z > 15)
    }

    /// The same on a wheeled car, where it is the differentials that rebuild:
    /// with slick front tyres, a car switched to front drive after it was built
    /// goes nowhere, and its twin left on rear drive keeps its legs. (This is
    /// the construction-time routing test, run through the live path.)
    @Test func switchingWhichAxleDrivesReRoutesTheTorque() {
        func drivenDistance(switchToFront: Bool) -> Double {
            let world = World3D()
            world.ground = 0
            let car = Vehicle3DTests.car(in: world, drive: .rear, frontGrip: 0.02)
            for _ in 0 ..< 90 { world.step(dt: 1.0 / 60) }
            if switchToFront {
                for wheel in car.wheels { wheel.driven = wheel.position.z > 0 }
                world.step(dt: 1.0 / 60)
                #expect(car.wheels.filter(\.driven).count == 2)
                #expect(car.wheels.filter(\.driven).allSatisfy { $0.position.z > 0 })
            }
            car.throttle = 1
            for _ in 0 ..< 300 { world.step(dt: 1.0 / 60) }
            return car.body.position.z
        }

        let rear = drivenDistance(switchToFront: false)
        let front = drivenDistance(switchToFront: true)
        #expect(rear > 2 * front)
    }

    /// A wheeled machine has no bands to report on.
    @Test func trackSpeedIsZeroOnAWheeledMachine() {
        let world = World3D()
        world.ground = 0
        let car = Vehicle3DTests.car(in: world)
        run(world, steps: 60)

        #expect(!car.isTracked)
        #expect(car.trackSpeed(.left) == 0)
        #expect(car.wheels(on: .left).isEmpty)
    }

    // MARK: Determinism

    @Test func identicalCrawlersReplayIdentically() {
        func drive() -> [Double] {
            let (world, crawler) = standing()
            crawler.throttle = 1
            crawler.steering = 0.4
            var trace: [Double] = []
            for step in 0 ..< 300 {
                world.step(dt: 1.0 / 60)
                if step % 60 == 0 {
                    trace.append(crawler.body.position.x)
                    trace.append(crawler.body.position.z)
                    trace.append(crawler.trackSpeed(.left))
                    trace.append(crawler.trackSpeed(.right))
                }
            }
            return trace
        }
        #expect(drive() == drive())
    }
}
