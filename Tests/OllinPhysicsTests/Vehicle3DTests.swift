import Foundation
import Testing
import Ollin
@testable import OllinPhysics

/// Correctness for the driveable vehicle: the throttle reaches the road through
/// the wheels marked driven and no others, steering curves the path the way the
/// driver asked, the brakes and hand brake do different things to different
/// wheels, the springs carry the weight, and a two-wheeler holds itself up.
/// Behavioral (the no-pixel-snapshot policy for physics), each knob pinned
/// against a counterfactual twin: the same scene run twice with one setting
/// changed, so a passing test can't be explained by the geometry alone.
/// Parallel-safe like the rest of the 3D suite.
struct Vehicle3DTests {

    /// A four-wheeled car on a flat floor, with every knob a test might want to
    /// vary. `drive` picks which axle the engine turns; `frontGrip` lets a test
    /// make the front tyres slick, which is how "the engine turns *these*
    /// wheels" is pinned without changing anything else.
    static func car(in world: World3D, at position: Vector3 = Vector3(0, 1, 0),
                    drive: Drive = .rear, topSpeed: Double = 30,
                    engineTorque: Double = 500, frontGrip: Double = 1,
                    suspensionFrequency: Double = 1.5) -> Vehicle3D {
        let front = drive != .rear
        let rear = drive != .front
        let wheels = [
            Wheel3D.wheel(at: Vector3(0.85, -0.1, 1.3), steers: true, driven: front),
            Wheel3D.wheel(at: Vector3(-0.85, -0.1, 1.3), steers: true, driven: front),
            Wheel3D.wheel(at: Vector3(0.85, -0.1, -1.3), driven: rear, handBrake: true),
            Wheel3D.wheel(at: Vector3(-0.85, -0.1, -1.3), driven: rear, handBrake: true),
        ]
        for wheel in wheels { wheel.suspensionFrequency = suspensionFrequency }
        wheels[0].grip = frontGrip
        wheels[1].grip = frontGrip
        return world.addVehicle(.box(width: 1.8, height: 0.7, depth: 4),
                                at: position, wheels: wheels,
                                engineTorque: engineTorque, topSpeed: topSpeed)!
    }

    enum Drive { case front, rear, all }

    func run(_ world: World3D, steps: Int) {
        for _ in 0 ..< steps { world.step(dt: 1.0 / 60) }
    }

    /// A world with a floor and a settled car on it.
    func standing(drive: Drive = .rear, topSpeed: Double = 30,
                  engineTorque: Double = 500, frontGrip: Double = 1,
                  suspensionFrequency: Double = 1.5) -> (World3D, Vehicle3D) {
        let world = World3D()
        world.ground = 0
        let car = Self.car(in: world, drive: drive, topSpeed: topSpeed,
                           engineTorque: engineTorque, frontGrip: frontGrip,
                           suspensionFrequency: suspensionFrequency)
        run(world, steps: 90)
        return (world, car)
    }

    // MARK: Standing on its wheels

    @Test func restsOnItsSuspensionWithEveryWheelDown() {
        let (world, car) = standing()

        #expect(car.isOnGround)
        #expect(car.wheels.allSatisfy { $0.isOnGround })
        // Each wheel sits its own radius above the floor, and below the point
        // it is bolted to, because the spring holds it there.
        for wheel in car.wheels {
            #expect(abs(wheel.center.y - wheel.radius) < 0.02)
            #expect(wheel.center.y < car.body.position.y + wheel.position.y)
            #expect(wheel.groundBody === world.groundBody)
        }
        // The chassis is an ordinary body carrying the mass it was given.
        #expect(world.bodies.contains { $0 === car.body })
        #expect(abs(car.body.mass - 1500) < 1)
    }

    @Test func aStifferSpringSagsLess() {
        let (softWorld, soft) = standing(suspensionFrequency: 1.0)
        let (stiffWorld, stiff) = standing(suspensionFrequency: 2.5)
        #expect(softWorld.vehicles.count == 1 && stiffWorld.vehicles.count == 1)

        #expect(stiff.body.position.y > soft.body.position.y + 0.15)
        #expect(stiff.wheels[0].suspensionCompression
                < soft.wheels[0].suspensionCompression - 0.3)
        // The wheels themselves end up in the same place either way: it is the
        // body that rides higher.
        #expect(abs(stiff.wheels[0].center.y - soft.wheels[0].center.y) < 0.01)
    }

    @Test func wheelsInTheAirAreNotOnTheGround() {
        let world = World3D()
        world.ground = 0
        let car = Self.car(in: world, at: Vector3(0, 12, 0))
        world.step(dt: 1.0 / 60)

        #expect(!car.isOnGround)
        #expect(car.wheels.allSatisfy { !$0.isOnGround })
        #expect(car.wheels[0].groundBody == nil)

        run(world, steps: 240)
        #expect(car.isOnGround)
    }

    // MARK: The throttle

    @Test func theThrottleDrivesItForward() {
        let (world, car) = standing()
        car.throttle = 1
        run(world, steps: 300)
        let driven = car.body.position.z

        let (idleWorld, idle) = standing()
        run(idleWorld, steps: 300)

        #expect(driven > 10)
        #expect(car.speed > 3)
        #expect(abs(idle.body.position.z) < 0.5)
        // It drives along its own forward axis, and the wheels are turning.
        #expect(car.forward.z > 0.99)
        #expect(car.wheels[2].spinRate > 1)
    }

    /// The counterfactual that pins *which* wheels the engine turns: with the
    /// front tyres made slick, a front-driven car spins them and crawls while
    /// the same car driven from the back pulls away. Nothing else differs.
    @Test func theEngineTurnsTheWheelsMarkedDriven() {
        let (frontWorld, frontDriven) = standing(drive: .front, frontGrip: 0.02)
        frontDriven.throttle = 1
        run(frontWorld, steps: 300)

        let (rearWorld, rearDriven) = standing(drive: .rear, frontGrip: 0.02)
        rearDriven.throttle = 1
        run(rearWorld, steps: 300)

        #expect(rearDriven.body.position.z > 2 * frontDriven.body.position.z)
        #expect(rearDriven.speed > 2 * frontDriven.speed)
    }

    /// Wheels sharing an axle are driven together, so the engine reaches the
    /// pair of whichever one was marked.
    @Test func markingOneWheelOfAnAxleDrivesItsPair() {
        let world = World3D()
        world.ground = 0
        let wheels = [
            Wheel3D.wheel(at: Vector3(0.85, -0.1, 1.3), steers: true),
            Wheel3D.wheel(at: Vector3(-0.85, -0.1, 1.3), steers: true),
            Wheel3D.wheel(at: Vector3(0.85, -0.1, -1.3), driven: true),
            Wheel3D.wheel(at: Vector3(-0.85, -0.1, -1.3)),
        ]
        let car = world.addVehicle(.box(width: 1.8, height: 0.7, depth: 4),
                                   at: Vector3(0, 1, 0), wheels: wheels)!

        #expect(car.wheels[3].driven)
        #expect(!car.wheels[0].driven)
    }

    @Test func aLowerTopSpeedGearsItDownToASlowerCeiling() {
        let (shortWorld, short) = standing(topSpeed: 12)
        short.throttle = 1
        run(shortWorld, steps: 1200)

        let (longWorld, long) = standing(topSpeed: 30)
        long.throttle = 1
        run(longWorld, steps: 1200)

        #expect(short.speed < 14)
        #expect(long.speed > 20)
        #expect(long.speed > short.speed + 8)
        // Both are in top gear at the end, so the difference is the gearing.
        #expect(short.gear == long.gear)
    }

    // MARK: Steering

    @Test func steeringCurvesThePath() {
        let (straightWorld, straight) = standing()
        straight.throttle = 1
        run(straightWorld, steps: 360)

        let (turningWorld, turning) = standing()
        turning.throttle = 1
        turning.steering = 1
        run(turningWorld, steps: 360)

        #expect(abs(straight.body.position.x) < 0.5)
        #expect(abs(turning.body.position.x) > 5)
        // It is pointing somewhere else too, not just sliding sideways.
        #expect(turning.forward.z < 0.9)
    }

    /// The sign, pinned: a vehicle facing its local +z has its right hand at
    /// -x, so positive steering takes it that way.
    @Test func positiveSteeringTurnsToTheVehiclesRight() {
        let (world, car) = standing()
        car.throttle = 1
        car.steering = 1
        run(world, steps: 300)

        #expect(car.body.position.x < -2)
        #expect(car.wheels[0].steerAngle < 0)   // the solver measures left-positive
        #expect(!car.wheels[2].steers)
        #expect(abs(car.wheels[2].steerAngle) < 1e-6)
    }

    // MARK: Stopping

    @Test func theBrakeStopsItSoonerThanCoasting() {
        let (world, car) = standing()
        car.throttle = 1
        run(world, steps: 420)
        let entry = car.body.position.z
        car.throttle = 0
        car.brake = 1
        run(world, steps: 150)
        let braked = car.body.position.z - entry

        let (coastWorld, coasting) = standing()
        coasting.throttle = 1
        run(coastWorld, steps: 420)
        let coastEntry = coasting.body.position.z
        coasting.throttle = 0
        run(coastWorld, steps: 150)
        let coasted = coasting.body.position.z - coastEntry

        #expect(car.speed < 0.5)
        #expect(coasting.speed > 5)
        #expect(braked < 0.6 * coasted)
    }

    @Test func theHandBrakeLocksOnlyTheWheelsThatHaveIt() {
        let (world, car) = standing()
        car.throttle = 1
        run(world, steps: 300)
        #expect(car.wheels[2].spinRate > 5)

        car.throttle = 0
        car.handBrake = 1
        run(world, steps: 30)

        #expect(abs(car.wheels[2].spinRate) < 0.5)   // rear: hand brake fitted
        #expect(car.wheels[0].spinRate > 5)          // front: still rolling
        #expect(car.speed > 1)                       // and still moving
    }

    /// Asking for reverse while still rolling forward brakes rather than
    /// slamming into gear, so the vehicle slows where coasting would not.
    @Test func askingForReverseWhileRollingBrakesFirst() {
        let (world, car) = standing()
        car.throttle = 1
        run(world, steps: 300)
        let cruising = car.speed
        car.throttle = -1
        run(world, steps: 15)

        let (coastWorld, coasting) = standing()
        coasting.throttle = 1
        run(coastWorld, steps: 300)
        coasting.throttle = 0
        run(coastWorld, steps: 15)

        #expect(car.speed < cruising)
        #expect(car.speed < coasting.speed - 0.5)
        #expect(car.gear >= 0)          // still not in reverse while rolling on
    }

    @Test func itReversesOnceItHasStopped() {
        let (world, car) = standing()
        car.throttle = -1
        run(world, steps: 300)

        #expect(car.speed < -2)
        #expect(car.body.position.z < -5)
        #expect(car.gear == -1)
    }

    // MARK: Two wheels

    /// A two-wheeler with the balance controller holds itself up; the same
    /// machine without it falls over. `tilt` leans it at the start, which is
    /// the perturbation the balancing has to answer: running dead straight,
    /// even an unbalanced two-wheeler stays up, because nothing tips it.
    static func bike(in world: World3D, balances: Bool, tilt: Double = 0,
                     maxTilt: Double? = nil) -> Vehicle3D {
        let front = Wheel3D.wheel(at: Vector3(0, -0.27, 0.75), radius: 0.31,
                                  width: 0.05, steers: true)
        front.casterAngle = 30 * .pi / 180
        front.suspensionLength = 0.5
        front.suspensionTravel = 0.2
        let back = Wheel3D.wheel(at: Vector3(0, -0.27, -0.75), radius: 0.31,
                                 width: 0.05, driven: true)
        back.suspensionLength = 0.5
        back.suspensionTravel = 0.2
        back.suspensionFrequency = 2
        let bike = world.addVehicle(.box(width: 0.4, height: 0.6, depth: 0.8),
                                    at: Vector3(0, 1, 0), wheels: [front, back],
                                    mass: 240, engineTorque: 150, topSpeed: 30,
                                    centerOfMass: Vector3(0, -0.3, 0),
                                    rotated: tilt, axis: Vector3(0, 0, 1),
                                    balances: balances)!
        bike.maxTilt = maxTilt
        return bike
    }

    @Test func aTwoWheelerRightsItselfAndFallsOverWithoutIt() {
        let lean = 25 * Double.pi / 180
        let world = World3D()
        world.ground = 0
        let upright = Self.bike(in: world, balances: true, tilt: lean)
        upright.throttle = 1
        run(world, steps: 300)

        let looseWorld = World3D()
        looseWorld.ground = 0
        let falls = Self.bike(in: looseWorld, balances: false, tilt: lean)
        falls.throttle = 1
        run(looseWorld, steps: 300)

        #expect(upright.up.y > 0.95)      // stood back up and rode away
        #expect(upright.speed > 8)
        #expect(falls.up.y < 0.5)         // went over and stayed there
        #expect(abs(falls.speed) < 0.5)
    }

    @Test func aTwoWheelerLeansIntoATurn() {
        let world = World3D()
        world.ground = 0
        let bike = Self.bike(in: world, balances: true, maxTilt: 60 * .pi / 180)
        bike.throttle = 1
        run(world, steps: 420)
        let uprightY = bike.up.y

        bike.steering = 0.5
        run(world, steps: 180)

        #expect(bike.up.y < uprightY - 0.05)     // leaning over
        #expect(bike.up.y > 0.6)                 // but not fallen
        #expect(bike.body.position.x < -2)       // and turning right
    }

    // MARK: Shape of the machine

    /// Wheels are grouped by where they sit along the vehicle, not by the
    /// order they were listed, so a car pairs left with right and a
    /// two-wheeler ends up with two axles of one wheel each.
    @Test func wheelsArePairedIntoAxlesByWhereTheySit() {
        let carWheels = [
            Wheel3D.wheel(at: Vector3(0.85, 0, -1.3), driven: true),
            Wheel3D.wheel(at: Vector3(-0.85, 0, 1.3)),
            Wheel3D.wheel(at: Vector3(0.85, 0, 1.3)),
            Wheel3D.wheel(at: Vector3(-0.85, 0, -1.3), driven: true),
        ]
        let axles = Vehicle3D.axles(of: carWheels)
        #expect(axles.count == 2)
        #expect(axles.allSatisfy { $0.leftWheel >= 0 && $0.rightWheel >= 0 })
        // The front pair (listed second and third) share an axle.
        let front = axles.first { $0.leftWheel == 2 || $0.rightWheel == 2 }
        #expect(front?.leftWheel == 2 && front?.rightWheel == 1)
        #expect(front?.driven == false)
        #expect(axles.contains { $0.driven })

        let bikeWheels = [
            Wheel3D.wheel(at: Vector3(0, 0, 0.75), steers: true),
            Wheel3D.wheel(at: Vector3(0, 0, -0.75), driven: true),
        ]
        let bikeAxles = Vehicle3D.axles(of: bikeWheels)
        #expect(bikeAxles.count == 2)
        #expect(bikeAxles.allSatisfy { $0.rightWheel == -1 })
    }

    /// With nothing marked, the back axle is driven: an engine that reaches no
    /// wheel is not a vehicle.
    @Test func somethingIsAlwaysDriven() {
        let wheels = [
            Wheel3D.wheel(at: Vector3(0.85, 0, 1.3)),
            Wheel3D.wheel(at: Vector3(-0.85, 0, 1.3)),
            Wheel3D.wheel(at: Vector3(0.85, 0, -1.3)),
            Wheel3D.wheel(at: Vector3(-0.85, 0, -1.3)),
        ]
        let axles = Vehicle3D.axles(of: wheels)
        #expect(axles.count == 2)
        #expect(axles.filter(\.driven).count == 1)
        // The rear axle: the one whose wheels sit furthest back.
        let driven = axles.first { $0.driven }!
        #expect(wheels[Int(driven.leftWheel)].position.z < 0)
    }

    @Test func removingAVehicleTakesItsChassisWithIt() {
        let world = World3D()
        world.ground = 0
        let car = Self.car(in: world)
        run(world, steps: 30)
        #expect(world.vehicles.count == 1)
        #expect(world.bodies.count == 1)

        world.remove(car)
        #expect(world.vehicles.isEmpty)
        #expect(world.bodies.isEmpty)
        // The world keeps stepping with nothing left to drive.
        run(world, steps: 30)
    }

    // MARK: Determinism

    @Test func identicalVehiclesReplayIdentically() {
        func drive() -> [Double] {
            let (world, car) = standing()
            car.throttle = 1
            car.steering = 0.4
            var trace: [Double] = []
            for step in 0 ..< 300 {
                world.step(dt: 1.0 / 60)
                if step % 60 == 0 {
                    trace.append(car.body.position.x)
                    trace.append(car.body.position.z)
                    trace.append(car.wheels[2].spin)
                }
            }
            return trace
        }
        #expect(drive() == drive())
    }
}
