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
/// world.advance(by: deltaTime)
/// withBody(car.body) { drawBox(width: 1.8, height: 0.6, depth: 4) }
/// for wheel in car.wheels {
///     withWheel(wheel) { drawCylinder(height: wheel.width, radius: wheel.radius) }
/// }
/// ```
///
/// The vehicle drives along its chassis's local **+z**, with +y up, so model
/// whatever you draw facing that way.
///
/// `tracked: true` builds the same machine on two tracks instead: the wheels
/// become road wheels, split into a left and a right band by which side of the
/// hull they sit on, and the three controls mean the same things. Steering is
/// the one that reaches the ground differently, since a track has nothing to
/// turn: full lock runs the inside band backwards and the machine spins on
/// the spot.
public final class Vehicle3D {

    /// Which side of a tracked machine a band is on, seen from the driver's
    /// seat looking along the vehicle's forward axis.
    public enum TrackSide {
        case left, right
    }

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

    /// Whether this machine runs on tracks rather than on steered wheels. A
    /// tracked one turns by running one band faster than the other, so
    /// `steering` reaches the ground through the drivetrain instead of through
    /// a steering rack, and full lock spins it on the spot.
    public let isTracked: Bool

    /// Whether this is a two-wheeler that holds itself up, leaning into turns
    /// instead of falling over.
    public let balances: Bool

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
    ///
    /// A tracked machine has nothing to turn, so the same number sets how much
    /// slower the inside band runs: half lock stops it, and full lock runs it
    /// backwards, which spins the machine on the spot. It needs throttle to do
    /// any of that, the way a real one does.
    public var steering: Double = 0

    /// The brake pedal, `0…1`. Slows every wheel that has `brakeTorque`; on a
    /// tracked machine it slows both bands, which is the only brake it has.
    public var brake: Double = 0

    /// The hand brake, `0…1`. Locks the wheels that have `handBrakeTorque`
    /// (the rear pair, normally), which is what makes a car slide. A tracked
    /// machine has one brake, so this pulls the same one.
    public var handBrake: Double = 0

    // MARK: The machine

    /// How hard the engine pulls, in newton-meters at the crank. More torque
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
    /// meter: the outside wheel's compression lifts the inside one, which is
    /// what keeps a vehicle flat through a corner. `0` unties them.
    public var antiRollStiffness: Double = 1000 {
        didSet { cjolt_vehicle_set_anti_roll(handle, Float(max(0, antiRollStiffness))) }
    }

    // MARK: Where it is and what it is doing

    /// How fast the vehicle is traveling along its own forward axis, in world
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

    /// How far the clutch is engaged, `0` slipping … `1` locked. It dips
    /// through a gear change and while pulling away.
    public var clutch: Double { Double(cjolt_vehicle_get_clutch(handle)) }

    /// Put the drivetrain back where it was turning: the engine's speed, the
    /// gear, the clutch, and each wheel's own rotation. This is what a restored
    /// machine needs to carry on rather than spin up from rest.
    func restoreDrivetrain(rpm: Double, gear: Int, clutch: Double,
                           wheelSpins: [(rate: Double, angle: Double)]) {
        cjolt_vehicle_set_drivetrain(handle, Float(rpm), Int32(gear), Float(clutch))
        for (index, spin) in wheelSpins.enumerated() where index < wheels.count {
            cjolt_vehicle_set_wheel_motion(handle, Int32(index),
                                           Float(spin.rate), Float(spin.angle))
        }
    }

    /// Whether any wheel is touching something. `false` means every wheel is
    /// in the air, and nothing the driver does will change anything.
    public var isOnGround: Bool { wheels.contains { $0.isOnGround } }

    /// How fast one band of a tracked machine is running over the ground, in
    /// world units per second: the number to scroll a drawn track by. The two
    /// differ through a turn, and run opposite ways in a pivot. Zero on a
    /// machine that is not tracked.
    public func trackSpeed(_ side: TrackSide) -> Double {
        guard isTracked else { return 0 }
        let metric = cjolt_vehicle_get_track_speed(handle, side == .left ? 0 : 1)
        return world.units(from: metric)
    }

    /// The road wheels one band carries, front of the machine first: what a
    /// drawing loop walks to lay a track around them. Empty on a machine that
    /// is not tracked.
    public func wheels(on side: TrackSide) -> [Wheel3D] {
        guard isTracked else { return [] }
        return wheels
            .filter { (side == .left) == ($0.position.x >= 0) }
            .sorted { $0.position.z > $1.position.z }
    }

    /// The direction the vehicle last accepted, so reversing has to pass
    /// through a stop (the gearbox model, mirroring the solver's own sample).
    private var acceptedDirection: Double = 1

    init?(world: World3D, chassis: Body3D, wheels: [Wheel3D], engineTorque: Double,
          topSpeed: Double, antiRollStiffness: Double, leans: Bool,
          maxLeanAngle: Double, tracked: Bool, mass: Double,
          centerOfMass: Vector3) {
        guard !wheels.isEmpty else { return nil }
        let layout = Vehicle3D.driveLayout(of: wheels, tracked: tracked,
                                           mass: mass, world: world)
        guard !tracked || layout.tracks.count == 2 else { return nil }
        let wheelDescs = wheels.map { $0.desc(world: world) }

        var desc = CJoltVehicleDesc()
        desc.maxEngineTorque = Float(max(1, engineTorque))
        desc.topSpeed = world.meters(from: topSpeed)
        desc.antiRollStiffness = Float(max(0, antiRollStiffness))
        desc.maxPitchRollAngle = Float.pi
        desc.contact = CJOLT_WHEEL_CONTACT_CYLINDER
        desc.kind = tracked ? CJOLT_VEHICLE_TRACKED
            : (leans ? CJOLT_VEHICLE_LEANING : CJOLT_VEHICLE_WHEELED)
        desc.maxLeanAngle = Float(maxLeanAngle)
        desc.wheelCount = Int32(wheels.count)
        desc.axleCount = Int32(layout.axles.count)

        let arena = ShapeDescArena()
        desc.wheels = arena.store(wheelDescs)
        desc.axles = arena.store(layout.axles)
        if tracked {
            desc.tracks = (layout.tracks[0].desc(arena: arena),
                           layout.tracks[1].desc(arena: arena))
        }
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
        self.isTracked = tracked
        self.balances = leans
        self.chassisMass = mass
        self.centerOfMass = centerOfMass
        self.maxLeanAngle = maxLeanAngle
        self.engineTorque = engineTorque
        self.topSpeed = topSpeed
        self.antiRollStiffness = antiRollStiffness
        // An axle the engine turns drives both of its wheels, and a track is
        // turned at one sprocket however many wheels were marked, so report
        // back what actually ended up driven rather than what was asked for.
        // This happens before the wheels are adopted, while `driven` is still
        // the build spec rather than something to push at the solver.
        for (index, wheel) in wheels.enumerated() {
            wheel.driven = layout.driven[index]
            wheel.adopt(by: self, index: index)
        }
    }

    /// The machine's weight, kept because a track band's inertia is derived
    /// from it (see `driveLayout`), and because it is not something a chassis
    /// body can be asked for once its center of mass has been moved.
    let chassisMass: Double

    /// Where the weight hangs inside the chassis, in its local space: what
    /// keeps a vehicle from rolling over in a turn.
    let centerOfMass: Vector3

    /// The furthest a two-wheeler may lean, in radians. Inert on anything else.
    let maxLeanAngle: Double

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
        if driveNeedsRebuild { rebuildDrive() }
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

    /// How the engine reaches the ground: the axle pairs (which carry the
    /// anti-roll bars whatever drives the machine), the two bands of a tracked
    /// one, and which wheels end up driven once axle-mates and sprockets are
    /// resolved.
    struct DriveLayout {
        var axles: [CJoltAxleDesc]
        var tracks: [TrackBand]
        var driven: [Bool]
    }

    /// One band of a tracked machine: the road wheels it carries, which of them
    /// the engine turns, and how hard its brake bites.
    struct TrackBand {
        var wheels: [Int32]
        var drivenWheel: Int32
        var inertia: Double
        var brakeTorque: Double

        func desc(arena: ShapeDescArena) -> CJoltTrackDesc {
            var desc = CJoltTrackDesc()
            desc.wheels = arena.store(wheels)
            desc.wheelCount = Int32(wheels.count)
            desc.drivenWheel = drivenWheel
            desc.inertia = Float(inertia)
            // Enough that a band left alone winds down rather than coasting
            // forever, which is the library's own figure.
            desc.angularDamping = 0.5
            desc.maxBrakeTorque = Float(brakeTorque)
            return desc
        }
    }

    /// What share of the machine's weight one band's inertia at the sprocket
    /// stands for: a run of track plus its road wheels, swung at the sprocket's
    /// radius. Measured across a range of sizes rather than guessed.
    static let trackInertiaShare = 0.08

    static func driveLayout(of wheels: [Wheel3D], tracked: Bool, mass: Double,
                            world: World3D) -> DriveLayout {
        let axles = Vehicle3D.axles(of: wheels)
        guard tracked else {
            var driven = [Bool](repeating: false, count: wheels.count)
            for axle in axles where axle.driven {
                for index in [axle.leftWheel, axle.rightWheel] where index >= 0 {
                    driven[Int(index)] = true
                }
            }
            return DriveLayout(axles: axles, tracks: [], driven: driven)
        }

        // The driver's right is -x (forward × up), so the left band carries the
        // wheels at positive x. A wheel dead on the centerline has to ride one
        // of them; it rides the left.
        var sides: [[Int]] = [[], []]
        for (index, wheel) in wheels.enumerated() {
            sides[wheel.position.x >= 0 ? 0 : 1].append(index)
        }
        var bands: [TrackBand] = []
        var driven = [Bool](repeating: false, count: wheels.count)
        // Newton-meters over a world whose meter is `unitsPerMeter`, so a
        // torque scales with the square of it.
        let torqueScale = 1 / (world.unitsPerMeter * world.unitsPerMeter)
        for side in sides {
            guard !side.isEmpty else { continue }
            // Real tracks are turned at one sprocket, so one wheel per band is
            // driven: the one asked for, else the rearmost.
            let sprocket = side.filter { wheels[$0].driven }.min {
                wheels[$0].position.z < wheels[$1].position.z
            } ?? side.min { wheels[$0].position.z < wheels[$1].position.z }!
            driven[sprocket] = true
            // The band's inertia at the sprocket stands for the weight of the
            // whole run of track and its road wheels: a share of the machine
            // swung at the sprocket's radius.
            let radius = max(0.01, wheels[sprocket].radius)
            let metricRadius = radius / world.unitsPerMeter
            let inertia = Vehicle3D.trackInertiaShare * mass
                * metricRadius * metricRadius
            let brake = side.reduce(0.0) { $0 + max(0, wheels[$1].brakeTorque) }
            bands.append(TrackBand(wheels: side.map(Int32.init),
                                   drivenWheel: Int32(sprocket),
                                   inertia: max(0.01, inertia),
                                   brakeTorque: brake * torqueScale))
        }
        return DriveLayout(axles: axles, tracks: bands, driven: driven)
    }

    /// Set by a wheel whose `driven` changed. The rebuild waits for the step
    /// rather than happening on the assignment, because which wheels drive is
    /// usually set a whole list at a time and each wheel's flag is only half an
    /// answer while the loop is still running.
    var driveNeedsRebuild = false

    /// Push the current `driven` flags at a vehicle that is already built: the
    /// differentials of a wheeled machine, the sprocket of each band on a
    /// tracked one. The gearing is re-solved, so the top speed is kept.
    func rebuildDrive() {
        driveNeedsRebuild = false
        guard !isSyncingDrive, !isDestroyed else { return }
        isSyncingDrive = true
        defer { isSyncingDrive = false }
        let layout = Vehicle3D.driveLayout(of: wheels, tracked: isTracked,
                                           mass: chassisMass, world: world)
        guard !isTracked || layout.tracks.count == 2 else { return }
        let arena = ShapeDescArena()
        let tracks = layout.tracks.map { $0.desc(arena: arena) }
        withExtendedLifetime(arena) {
            layout.axles.withUnsafeBufferPointer { axles in
                tracks.withUnsafeBufferPointer { bands in
                    cjolt_vehicle_set_drive(handle, axles.baseAddress,
                                            Int32(axles.count),
                                            bands.baseAddress)
                }
            }
        }
        // Report back what the drivetrain settled on. The guard above swallows
        // the echo these assignments would otherwise send back through here.
        for (index, wheel) in wheels.enumerated() {
            wheel.driven = layout.driven[index]
        }
    }

    private var isSyncingDrive = false

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
    /// together, so marking one marks its pair; on a tracked machine it marks
    /// the sprocket its band is turned at, so marking one clears the other on
    /// that side.
    ///
    /// This one is the gearbox rather than the wheel, so changing it rebuilds
    /// the drive on the next step: the vehicle keeps its top speed, which is
    /// re-geared against whatever is now driven. Set the whole list, then step,
    /// and read these back to see what the drivetrain settled on.
    public var driven: Bool {
        didSet {
            guard driven != oldValue else { return }
            vehicle?.driveNeedsRebuild = true
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

    /// How hard the brakes bite on this wheel, in newton-meters. On a tracked
    /// machine the brake belongs to the whole band, so this is that band's
    /// share of it.
    public var brakeTorque: Double = 1500 {
        didSet {
            pushSettings()
            // A band's brake is the sum of its wheels', and it is carried by
            // the drivetrain rather than by the wheel's own settings.
            if vehicle?.isTracked == true { vehicle?.driveNeedsRebuild = true }
        }
    }

    /// How hard the hand brake bites on this wheel, in newton-meters. Zero on
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
    public var slipAngle: Double { abs(Double(readState().lateralSlip)) }

    /// Which way the wheel faces, as one value: the turn that poses a cylinder
    /// modeled along +y onto the wheel, steering and spin included.
    /// `withWheel(_:)` is the sugar over it.
    public var rotation: Rotation3D {
        let q = readState().rotation
        return Rotation3D(x: Double(q.0), y: Double(q.1), z: Double(q.2), w: Double(q.3))
    }

    /// The wheel's orientation as an angle (radians) about `rotationAxis`. The
    /// pair reads the same pose as `rotation`; use them together.
    public var rotationAngle: Double { rotation.angle }

    /// The axis of the wheel's current orientation (unit length).
    public var rotationAxis: Vector3 { rotation.axis }

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
        // does: newton-meters over a world whose meter is `unitsPerMeter`.
        let torqueScale = 1 / (world.unitsPerMeter * world.unitsPerMeter)
        desc.maxBrakeTorque = Float(max(0, brakeTorque) * torqueScale)
        desc.maxHandBrakeTorque = Float(max(0, handBrakeTorque) * torqueScale)
        desc.grip = Float(max(0, grip))
        return desc
    }
}
