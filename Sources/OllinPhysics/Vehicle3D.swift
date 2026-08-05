import Foundation
import Ollin
internal import CJolt

/// A driveable machine in a `World3D`: a chassis body carried on sprung wheels,
/// with an engine and a gearbox behind the throttle. Unlike a `Body3D` you push
/// around with forces, you drive it: set `throttle`, `steering`, and `brake`
/// each frame the way you set a character's walking velocity, and the wheels
/// find their own grip on whatever they are rolling over.
///
/// A vehicle is not a body of its own. It is a *constraint* on the chassis
/// body, which is why `body` is an ordinary `Body3D` that stacks, collides, and
/// can be hit like any other, while the wheels are the vehicle's.
///
/// ```swift
/// let car = world.addVehicle(.box(width: 1.8, height: 0.6, depth: 4),
///                            at: Vector3(0, 2, 0),
///                            wheels: [
///                                .wheel(at: Vector3( 0.9, -0.1,  1.3), steers: true),
///                                .wheel(at: Vector3(-0.9, -0.1,  1.3), steers: true),
///                                .wheel(at: Vector3( 0.9, -0.1, -1.3), driven: true),
///                                .wheel(at: Vector3(-0.9, -0.1, -1.3), driven: true),
///                            ])
/// // each frame:
/// car.throttle = isKeyDown(.upArrow) ? 1 : 0
/// car.steering = isKeyDown(.rightArrow) ? 1 : 0
/// world.step(dt: deltaTime)
/// withBody(car.body) { drawBox(width: 1.8, height: 0.6, depth: 4) }
/// for wheel in car.wheels {
///     withWheel(wheel) { drawCylinder(height: wheel.width, radius: wheel.radius) }
/// }
/// ```
///
/// The vehicle drives along its chassis's local **+z**, with +y up, so model
/// whatever you draw facing that way.
public final class Vehicle3D {

    /// How a wheel finds the ground each step.
    public enum WheelContact {
        /// A single ray straight down from the mounting point: the cheapest,
        /// and a narrow wheel drops into gaps it should have ridden over.
        case ray
        /// A swept ball the width of the tire, which rounds off edges.
        case sphere
        /// A swept cylinder, the wheel's real footprint. The steadiest over
        /// rough ground, and the default.
        case cylinder
    }

    /// The world this vehicle drives in. Unowned: the world holds it.
    unowned let world: World3D

    /// The underlying solver vehicle.
    let handle: OpaquePointer

    /// The chassis: an ordinary rigid body, so it collides, takes impulses,
    /// reports contacts, and can be drawn with `withBody(_:)`. It is in
    /// `world.bodies` like anything else the sketch added.
    public let body: Body3D

    /// The wheels, in the order they were given.
    public private(set) var wheels: [Wheel3D]

    /// Free-form tag so a sketch can hang its own data off a vehicle.
    public var userData: Any?

    // MARK: The controls

    /// How hard the gas pedal is pressed, `-1…1`. Positive drives forward,
    /// negative reverses. It holds until changed, so set it every frame.
    ///
    /// Asking for the other direction while the vehicle is still rolling
    /// brakes first and only takes the new direction once it has stopped,
    /// which is how a car with an automatic gearbox behaves.
    public var throttle: Double = 0

    /// Which way the wheels are turned, `-1` hard left … `1` hard right. How
    /// far that actually turns them is each wheel's `maxSteerAngle`.
    public var steering: Double = 0

    /// The brake pedal, `0…1`. Slows every wheel that has `brakeTorque`.
    public var brake: Double = 0

    /// The hand brake, `0…1`. Locks the wheels that have `handBrakeTorque`
    /// (the rear pair, normally), which is what makes a car slide.
    public var handBrake: Double = 0

    // MARK: The machine

    /// How hard the engine pulls, in newton-metres at the crank. More torque
    /// spins the wheels sooner rather than accelerating harder: grip is the
    /// ceiling, not power.
    public var engineTorque: Double {
        didSet { cjolt_vehicle_set_engine_torque(handle, Float(max(1, engineTorque))) }
    }

    /// The speed the gearing tops out at, in world units per second: top gear
    /// at the engine's redline turns the driven wheels this fast. It is a
    /// ceiling the vehicle approaches on a flat straight rather than a
    /// promise, since drag and hills keep it under. Lowering it gears the
    /// vehicle down, which gives it more pull at low speed.
    public var topSpeed: Double {
        didSet { cjolt_vehicle_set_top_speed(handle, world.meters(from: topSpeed)) }
    }

    /// How the wheels find the ground. `.cylinder` (the default) is the
    /// steadiest over rough terrain; `.ray` is the cheapest.
    public var wheelContact: WheelContact = .cylinder {
        didSet { cjolt_vehicle_set_wheel_contact(handle, wheelContact.cjolt) }
    }

    /// Which collision group the whole machine is in: the chassis body and the
    /// wheels alike, so a car in a group that ignores the barriers drives
    /// through them rather than sitting on them with its bodywork clipping.
    public var group: CollisionGroup {
        get { body.group }
        set { body.group = newValue }   // the world rebuilds the wheels' testers
    }

    /// Rebuild the wheels' collision testers against the chassis's group. Each
    /// tester is made against one object layer, so a chassis that changed group
    /// needs a new set; the world calls this when that happens.
    func syncGroupToChassis() {
        cjolt_vehicle_set_group(world.handle, handle,
                                cjolt_body_get_group(world.handle, body.id))
    }

    /// The furthest the chassis may tilt away from upright, in radians. `nil`
    /// (the default) lets it roll over like any other body; a value around
    /// `.pi / 3` keeps a car on its wheels through anything.
    public var maxTilt: Double? {
        didSet { cjolt_vehicle_set_max_pitch_roll(handle, Float(maxTilt ?? .pi)) }
    }

    /// How stiffly the two wheels of an axle are tied together, in newtons per
    /// metre: the outside wheel's compression lifts the inside one, which is
    /// what keeps a vehicle flat through a corner. `0` unties them.
    public var antiRollStiffness: Double = 1000 {
        didSet { cjolt_vehicle_set_anti_roll(handle, Float(max(0, antiRollStiffness))) }
    }

    // MARK: Where it is and what it is doing

    /// How fast the vehicle is travelling along its own forward axis, in world
    /// units per second. Negative while reversing.
    public var speed: Double {
        body.velocity.dot(forward)
    }

    /// The chassis's forward direction in world space (its local +z).
    public var forward: Vector3 { rotate(Vector3(0, 0, 1)) }

    /// The chassis's up direction in world space (its local +y). It tips as
    /// the vehicle leans, so a chase camera can roll with it.
    public var up: Vector3 { rotate(Vector3(0, 1, 0)) }

    /// How fast the engine is turning, in revolutions per minute: the number
    /// to drive an engine sound or a rev counter from.
    public var rpm: Double { Double(cjolt_vehicle_get_rpm(handle)) }

    /// The gear the box has picked: `-1` reverse, `0` neutral, `1` first, up.
    public var gear: Int { Int(cjolt_vehicle_get_gear(handle)) }

    /// Whether any wheel is touching something. `false` means every wheel is
    /// in the air, and nothing the driver does will change anything.
    public var isOnGround: Bool { wheels.contains { $0.isOnGround } }

    /// The direction the vehicle last accepted, so reversing has to pass
    /// through a stop (the gearbox model, mirroring the solver's own sample).
    private var acceptedDirection: Double = 1

    init?(world: World3D, chassis: Body3D, wheels: [Wheel3D], engineTorque: Double,
          topSpeed: Double, antiRollStiffness: Double, leans: Bool,
          maxLeanAngle: Double) {
        guard !wheels.isEmpty else { return nil }
        let axles = Vehicle3D.axles(of: wheels)
        let wheelDescs = wheels.map { $0.desc(world: world) }

        var desc = CJoltVehicleDesc()
        desc.maxEngineTorque = Float(max(1, engineTorque))
        desc.topSpeed = world.meters(from: topSpeed)
        desc.antiRollStiffness = Float(max(0, antiRollStiffness))
        desc.maxPitchRollAngle = Float.pi
        desc.contact = CJOLT_WHEEL_CONTACT_CYLINDER
        desc.leans = leans
        desc.maxLeanAngle = Float(maxLeanAngle)
        desc.wheelCount = Int32(wheels.count)
        desc.axleCount = Int32(axles.count)

        let arena = ShapeDescArena()
        desc.wheels = arena.store(wheelDescs)
        desc.axles = arena.store(axles)
        let created = withExtendedLifetime(arena) {
            withUnsafePointer(to: &desc) {
                cjolt_vehicle_create(world.handle, chassis.id, $0)
            }
        }
        guard let created else { return nil }

        self.world = world
        self.handle = created
        self.body = chassis
        self.wheels = wheels
        self.engineTorque = engineTorque
        self.topSpeed = topSpeed
        self.antiRollStiffness = antiRollStiffness
        // An axle the engine turns drives both of its wheels, so report back
        // what actually ended up driven rather than what was asked for. This
        // happens before the wheels are adopted, while `driven` is still the
        // build spec rather than a setting fixed in the gearbox.
        for axle in axles where axle.driven {
            for index in [axle.leftWheel, axle.rightWheel] where index >= 0 {
                wheels[Int(index)].driven = true
            }
        }
        for (index, wheel) in wheels.enumerated() {
            wheel.adopt(by: self, index: index)
        }
    }

    deinit {
        destroyBackingVehicle()
    }

    /// Take the constraint and its step listener off the world. Called before
    /// the chassis body is destroyed (a constraint may not outlive a body it
    /// holds) and again by `deinit`, so it has to be safe twice. The world
    /// also sets `isDestroyed` on the way out, so a vehicle a sketch is still
    /// holding when its world goes cannot reach into freed memory.
    func destroyBackingVehicle() {
        guard !isDestroyed else { return }
        isDestroyed = true
        cjolt_vehicle_destroy(world.handle, handle)
    }

    var isDestroyed = false

    // MARK: Driving it

    /// Set the three controls at once, the terse form for a keyboard:
    ///
    /// ```swift
    /// car.drive(throttle: gas, steering: turn, brake: stop)
    /// ```
    public func drive(throttle: Double, steering: Double = 0, brake: Double = 0) {
        self.throttle = throttle
        self.steering = steering
        self.brake = brake
    }

    /// Stop driving: pedals up, wheels straight. The vehicle keeps rolling.
    public func coast() {
        throttle = 0
        steering = 0
        brake = 0
        handBrake = 0
    }

    // MARK: Stepping (called by the world)

    /// Hand this frame's controls to the solver, which collides and drives the
    /// wheels inside the step that follows.
    func advance() {
        var forwardInput = throttle
        var brakeInput = brake
        // A car with an automatic box will not slam into reverse: asking for
        // the other direction while still rolling brakes instead, and the new
        // direction is taken once the vehicle has stopped.
        if acceptedDirection * forwardInput < 0 {
            let rolling = speed
            let threshold = 0.1 * world.unitsPerMeter
            if (forwardInput > 0 && rolling < -threshold)
                || (forwardInput < 0 && rolling > threshold) {
                forwardInput = 0
                brakeInput = 1
            } else {
                acceptedDirection = forwardInput
            }
        }
        // The hand brake overrides the gas: you cannot pull away against it.
        if handBrake > 0 { forwardInput = 0 }
        cjolt_vehicle_set_input(world.handle, handle, Float(forwardInput),
                                Float(steering), Float(brakeInput),
                                Float(handBrake))
    }

    // MARK: Internals

    /// Rotate a chassis-local direction into world space.
    private func rotate(_ local: Vector3) -> Vector3 {
        let q = body.quaternion
        let v = Vector3(Double(q.0), Double(q.1), Double(q.2))
        let t = v.cross(local) * 2
        return local + t * Double(q.3) + v.cross(t)
    }

    /// Which wheels share an axle, worked out from where they sit rather than
    /// from the order they were listed: wheels at the same distance along the
    /// vehicle are on one axle, and a wheel on its own (a two-wheeler's) makes
    /// an axle by itself. An axle with any driven wheel is turned by the
    /// engine, and a pair is also tied by an anti-roll bar.
    static func axles(of wheels: [Wheel3D]) -> [CJoltAxleDesc] {
        let indices = wheels.indices.sorted {
            let a = wheels[$0].position, b = wheels[$1].position
            if a.z != b.z { return a.z > b.z }   // front of the vehicle first
            if a.x != b.x { return a.x > b.x }
            return $0 < $1
        }
        let zs = wheels.map(\.position.z)
        let wheelbase = (zs.max() ?? 0) - (zs.min() ?? 0)
        // A quarter of the wheelbase separates axles: wide enough that a
        // little stagger still pairs, narrow enough that front and back never
        // do. A single-axle vehicle groups everything together.
        let tolerance = max(wheelbase * 0.25, 1e-6)

        var groups: [[Int]] = []
        for index in indices {
            if let first = groups.last?.first,
               abs(wheels[index].position.z - wheels[first].position.z) <= tolerance {
                groups[groups.count - 1].append(index)
            } else {
                groups.append([index])
            }
        }

        var axles: [CJoltAxleDesc] = []
        for group in groups {
            var remaining = group
            while !remaining.isEmpty {
                let left = remaining.removeFirst()
                let right = remaining.isEmpty ? -1 : Int32(remaining.removeFirst())
                var axle = CJoltAxleDesc()
                axle.leftWheel = Int32(left)
                axle.rightWheel = right
                axle.driven = wheels[left].driven
                    || (right >= 0 && wheels[Int(right)].driven)
                axles.append(axle)
            }
        }
        // Something has to be driven for the engine to reach the road; with
        // nothing marked, the back axle takes it.
        if !axles.contains(where: \.driven), !axles.isEmpty {
            axles[axles.count - 1].driven = true
        }
        return axles
    }
}

extension Vehicle3D.WheelContact {
    var cjolt: CJoltWheelContact {
        switch self {
        case .ray: return CJOLT_WHEEL_CONTACT_RAY
        case .sphere: return CJOLT_WHEEL_CONTACT_SPHERE
        case .cylinder: return CJOLT_WHEEL_CONTACT_CYLINDER
        }
    }
}

/// One wheel of a `Vehicle3D`: where it is bolted to the chassis, how big it
/// is, whether it steers and whether the engine turns it, and the spring it
/// hangs on. Build the wheels first, then hand them to
/// `World3D.addVehicle(_:at:wheels:)`; afterwards the same objects report
/// where the wheel actually ended up, so a drawing loop reads them directly.
///
/// ```swift
/// let front = Wheel3D.wheel(at: Vector3(0.9, -0.1, 1.3), steers: true)
/// front.suspensionFrequency = 2      // a stiffer spring
/// ```
public final class Wheel3D {

    /// Where the suspension is bolted to the chassis, in the body's local
    /// space (the space the collider is described in). The wheel hangs
    /// `suspensionLength` below this.
    public var position: Vector3 { didSet { pushSettings() } }

    /// The tire's radius, in world units.
    public var radius: Double { didSet { pushSettings() } }

    /// How wide the tire is, in world units.
    public var width: Double { didSet { pushSettings() } }

    /// Whether steering turns this wheel.
    public var steers: Bool { didSet { pushSettings() } }

    /// Whether the engine turns this wheel. Wheels sharing an axle are driven
    /// together, so marking one marks its pair.
    ///
    /// This one is the gearbox rather than the wheel, so unlike everything
    /// else here it is fixed once the vehicle is built: to change which end
    /// drives, build the vehicle again.
    public var driven: Bool {
        didSet {
            guard vehicle != nil, driven != oldValue else { return }
            driven = oldValue
            noteOnce("which wheels are driven is fixed when the vehicle is "
                     + "built; make a new vehicle to change it")
        }
    }

    /// How far the steering can turn this wheel, in radians. Only wheels with
    /// `steers` set use it; raise it for a tighter lock.
    public var maxSteerAngle: Double = 30 * .pi / 180 { didSet { pushSettings() } }

    /// How far the fork is raked back from vertical, in radians. A car leaves
    /// it at `0`; a two-wheeler needs a real rake on its front wheel (around
    /// 30°), because the trail that comes with it is what lets it hold a line
    /// instead of flopping over at the first correction.
    public var casterAngle: Double = 0 { didSet { pushSettings() } }

    /// How far below its mounting point the wheel hangs with nothing pressing
    /// on it, in world units: the spring's natural length.
    public var suspensionLength: Double = 0.45 { didSet { pushSettings() } }

    /// How much further up the wheel can be pushed from there, in world units.
    /// Past it the suspension is bottomed out and the chassis takes the hit.
    public var suspensionTravel: Double = 0.3 { didSet { pushSettings() } }

    /// How stiff the spring is, in hertz, the same frequency-and-damping pair
    /// a joint's `drive(to:frequency:damping:)` takes. Around 1.5 is a road
    /// car; 3 and up is a go-kart that feels every stone.
    public var suspensionFrequency: Double = 1.5 { didSet { pushSettings() } }

    /// How quickly the spring stops bouncing, as a ratio: 1 settles without
    /// overshooting, and lower values wallow.
    public var suspensionDamping: Double = 0.5 { didSet { pushSettings() } }

    /// How hard the brakes bite on this wheel, in newton-metres.
    public var brakeTorque: Double = 1500 { didSet { pushSettings() } }

    /// How hard the hand brake bites on this wheel, in newton-metres. Zero on
    /// the front wheels of a car, so pulling it slides the back out.
    public var handBrakeTorque: Double = 0 { didSet { pushSettings() } }

    /// How much the tire grips, scaling its own friction: `1` is a normal
    /// tire, lower is slick, higher is a racing slick that never lets go. The
    /// ground's friction combines with this, so slippery ground still slides
    /// a grippy tire.
    public var grip: Double = 1 { didSet { pushSettings() } }

    /// Free-form tag so a sketch can hang its own data off a wheel.
    public var userData: Any?

    /// The vehicle this wheel belongs to, once it has been adopted. Weak, so a
    /// wheel a sketch still holds after its vehicle is gone reads its own
    /// resting values rather than trapping.
    private weak var vehicle: Vehicle3D?
    private var index: Int32 = 0

    /// A wheel bolted to the chassis at `position`.
    ///
    /// - Parameters:
    ///   - position: the suspension's mounting point in the chassis's local
    ///     space; the wheel hangs below it.
    ///   - radius: the tire's radius, in world units.
    ///   - width: how wide the tire is, in world units.
    ///   - steers: whether steering turns it (the front pair, normally).
    ///   - driven: whether the engine turns it.
    ///   - handBrake: whether the hand brake locks it (the back pair).
    public init(at position: Vector3, radius: Double = 0.35, width: Double = 0.25,
                steers: Bool = false, driven: Bool = false,
                handBrake: Bool = false) {
        self.position = position
        self.radius = radius
        self.width = width
        self.steers = steers
        self.driven = driven
        if handBrake { handBrakeTorque = 4000 }
    }

    /// A wheel bolted to the chassis at `position` (the terse form, so a
    /// vehicle's wheels read as a list).
    public static func wheel(at position: Vector3, radius: Double = 0.35,
                             width: Double = 0.25, steers: Bool = false,
                             driven: Bool = false,
                             handBrake: Bool = false) -> Wheel3D {
        Wheel3D(at: position, radius: radius, width: width, steers: steers,
                driven: driven, handBrake: handBrake)
    }

    // MARK: Where it ended up

    /// The wheel's center in world space. Before the vehicle is built it is
    /// the mounting point; afterwards it is where the wheel is now, suspension
    /// travel included.
    public var center: Vector3 {
        guard let vehicle else { return position }
        let state = readState()
        return vehicle.world.units(from: state.position.0, state.position.1,
                                   state.position.2)
    }

    /// How far the steering has turned this wheel, in radians (positive to the
    /// left).
    public var steerAngle: Double { Double(readState().steerAngle) }

    /// How far the wheel has rolled, in radians `0…2π`: the angle to spin a
    /// drawn tire by if you are posing it yourself.
    public var spin: Double { Double(readState().rotationAngle) }

    /// How fast the wheel is turning, in radians per second. Positive rolls
    /// the vehicle forward; zero under power means it is locked or in the air.
    public var spinRate: Double { Double(readState().angularVelocity) }

    /// Whether the wheel is touching anything.
    public var isOnGround: Bool { readState().hasContact }

    /// The body the wheel is rolling on, or `nil` in the air. The world's
    /// floor slab reads as `world.groundBody`.
    public var groundBody: Body3D? {
        guard let vehicle else { return nil }
        let id = readState().contactBody
        guard id != CJOLT_BODY_INVALID else { return nil }
        return vehicle.world.bodyByID[id]
    }

    /// The surface normal under the tire (`.zero` in the air).
    public var groundNormal: Vector3 {
        let n = readState().contactNormal
        return Vector3(Double(n.0), Double(n.1), Double(n.2))
    }

    /// How compressed the spring is, `0` fully extended … `1` bottomed out.
    /// Watch it to see a car squat under power or dive under braking.
    public var suspensionCompression: Double {
        guard let vehicle, suspensionTravel > 0 else { return 0 }
        let length = Double(readState().suspensionLength) * vehicle.world.unitsPerMeter
        return min(max((suspensionLength - length) / suspensionTravel, 0), 1)
    }

    /// How much the tire is sliding along its own rolling direction: `0` is
    /// rolling cleanly, and it climbs as the wheel spins up or locks.
    public var slip: Double { abs(Double(readState().longitudinalSlip)) }

    /// How far the tire is being dragged sideways, in radians: the slip angle.
    /// It grows through a corner and spikes when the vehicle lets go.
    public var slideAngle: Double { abs(Double(readState().lateralSlip)) }

    /// The wheel's orientation as an angle (radians) about `rotationAxis`,
    /// posing a cylinder modeled along +y onto the wheel (steering and spin
    /// included). `withWheel(_:)` is the sugar over the pair.
    public var rotationAngle: Double {
        let q = readState().rotation
        return 2 * acos(max(-1, min(1, Double(q.3))))
    }

    /// The axis of the wheel's current orientation (unit length).
    public var rotationAxis: Vector3 {
        let q = readState().rotation
        let s = (1 - Double(q.3) * Double(q.3)).squareRoot()
        guard s > 1e-6 else { return .unitY }
        return Vector3(Double(q.0) / s, Double(q.1) / s, Double(q.2) / s)
    }

    // MARK: Internals

    func adopt(by vehicle: Vehicle3D, index: Int) {
        self.vehicle = vehicle
        self.index = Int32(index)
    }

    /// Hand the wheel's description back to a vehicle that is already driving.
    /// The solver reads all of it every step, so a slider on the suspension or
    /// the grip takes effect on the next one.
    private func pushSettings() {
        guard let vehicle else { return }
        var settings = desc(world: vehicle.world)
        withUnsafePointer(to: &settings) {
            cjolt_vehicle_set_wheel_settings(vehicle.handle, index, $0)
        }
    }

    private func noteOnce(_ message: String) {
        vehicle?.world.noteOnce(message)
    }

    private func readState() -> CJoltWheelState {
        var state = CJoltWheelState()
        guard let vehicle else { return state }
        cjolt_vehicle_get_wheel(vehicle.handle, index, &state)
        return state
    }

    /// The C description, in solver meters.
    func desc(world: World3D) -> CJoltWheelDesc {
        var desc = CJoltWheelDesc()
        let p = world.meters(from: position)
        desc.position = (p.0, p.1, p.2)
        desc.radius = world.meters(from: max(0.01, radius))
        desc.width = world.meters(from: max(0.01, width))
        desc.suspensionMaxLength = world.meters(from: max(0, suspensionLength))
        desc.suspensionMinLength =
            world.meters(from: max(0, suspensionLength - max(0, suspensionTravel)))
        desc.suspensionFrequency = Float(max(0.01, suspensionFrequency))
        desc.suspensionDamping = Float(max(0, suspensionDamping))
        desc.casterAngle = Float(casterAngle)
        desc.maxSteerAngle = Float(steers ? max(0, maxSteerAngle) : 0)
        // A torque scales with the square of the unit scale, the way a torque
        // does: newton-metres over a world whose metre is `unitsPerMeter`.
        let torqueScale = 1 / (world.unitsPerMeter * world.unitsPerMeter)
        desc.maxBrakeTorque = Float(max(0, brakeTorque) * torqueScale)
        desc.maxHandBrakeTorque = Float(max(0, handBrakeTorque) * torqueScale)
        desc.grip = Float(max(0, grip))
        return desc
    }
}
