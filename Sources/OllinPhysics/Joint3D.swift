import Foundation
import Ollin
internal import CJolt

/// A constraint linking two rigid `Body3D`s (a hinge, a ball-and-socket, a
/// rod, a weld, a slider, a track, a rope over pulleys), two other joints (a
/// gear pair, a rack and pinion), or a body to a moving target (a grab).
/// Create the structural kinds with `World3D.connect(_:_:_:)` and a grab with
/// `World3D.grab(_:at:)` (or the mouse-driven `grabBody(at:in:)` sketch
/// sugar). Hold onto the returned joint to retarget a grab (`target`), power
/// its motor (`drive(at:)` / `drive(to:)`), or cut the link (`remove()`).
public final class Joint3D {

    /// The world this joint lives in.
    unowned let world: World3D

    /// The underlying solver constraint (nil once removed, or if creation
    /// failed on a stale body).
    private(set) var constraint: OpaquePointer?

    /// The bodies this joint connects, so removing a body can cascade.
    let a: CJoltBodyID
    let b: CJoltBodyID

    /// The kind this joint was connected as (nil for a grab, and for a link
    /// between two joints), so the motor parameters know whether they drive an
    /// angle or an offset.
    public let kind: JointKind3D?

    /// Which link this is, when it was made by `connect(_:_:_:)` over two
    /// joints rather than two bodies; nil for every other joint.
    public let link: JointLink3D?

    /// Whether this is a grab joint, so `target` knows to drive it.
    let isGrab: Bool

    /// For a mouse-driven grab, the view depth the sketch sugar drags in.
    var grabViewDepth: Double?

    /// The poses the two bodies held when the joint was made. Every joint's
    /// zero is measured from there (a hinge's angle, a slider's offset, a
    /// weld's relative pose, the point on a track a body joined at), so this
    /// is what lets a snapshot put a jointed machine back exactly rather than
    /// re-zeroing it wherever it had swung to.
    let connectPoseA: Pose3D
    let connectPoseB: Pose3D

    /// The other bodies a link between two joints reaches, so removing any of
    /// the four cuts it.
    private let alsoTouches: [CJoltBodyID]

    /// The two joints a link was written against, so cutting either cuts it.
    weak var linkedA: Joint3D?
    weak var linkedB: Joint3D?

    init(world: World3D, constraint: OpaquePointer?,
         a: CJoltBodyID, b: CJoltBodyID, kind: JointKind3D? = nil,
         isGrab: Bool = false, alsoTouches: [CJoltBodyID] = [],
         linking: (Joint3D, Joint3D)? = nil, link: JointLink3D? = nil,
         connectPoseA: Pose3D = .identity, connectPoseB: Pose3D = .identity) {
        self.world = world
        self.constraint = constraint
        self.a = a
        self.b = b
        self.kind = kind
        self.link = link
        self.isGrab = isGrab
        self.alsoTouches = alsoTouches
        self.linkedA = linking?.0
        self.linkedB = linking?.1
        self.connectPoseA = connectPoseA
        self.connectPoseB = connectPoseB
    }

    /// Whether this joint holds onto `body` in any way.
    func touches(_ body: CJoltBodyID) -> Bool {
        a == body || b == body || alsoTouches.contains(body)
    }

    /// Whether this joint is a link written against `other`.
    func links(_ other: Joint3D) -> Bool {
        linkedA === other || linkedB === other
    }

    /// For a grab joint (from `World3D.grab`), the world point the body is
    /// pulled toward; set it each frame to drag the body around. No effect on
    /// the structural joints.
    public var target: Vector3 = .zero {
        didSet {
            if isGrab { world.dragGrab(self) }
        }
    }

    // MARK: Motors

    /// Spin the joint at a constant rate: radians per second about a hinge's
    /// axis or a swing-twist's own axis, world units per second along a slider
    /// or a track. The windmill and the conveyor. `strength` caps how hard the
    /// motor may push (torque in N·m for a hinge, force in N for a slider);
    /// the unlimited default reaches the rate almost instantly, a small value
    /// lets the load win.
    public func drive(at velocity: Double, strength: Double = .infinity) {
        guard let scale = motorScale(.velocity, "drive(at:)") else { return }
        guard let constraint else { return }
        cjolt_constraint_set_motor(world.handle, constraint, CJOLT_MOTOR_VELOCITY,
                                   Float(velocity * scale), 0, 0, Float(strength))
    }

    /// Pull the joint toward a target with a spring servo: an angle in radians
    /// for a hinge or a swing-twist's roll (0 being the pose at connect), an
    /// offset in world units for a slider, a 0…1 fraction of the whole curve
    /// for a track. `frequency` is how fast it pulls: 2 a lazy door closer,
    /// 20 a snappy servo. `damping` at 1 settles clean, lower overshoots and
    /// bounces. `strength` caps the torque (N·m) or force (N).
    public func drive(to target: Double, frequency: Double = 2,
                      damping: Double = 1, strength: Double = .infinity) {
        guard let scale = motorScale(.position, "drive(to:)") else { return }
        guard let constraint else { return }
        cjolt_constraint_set_motor(world.handle, constraint, CJOLT_MOTOR_POSITION,
                                   Float(target * scale), Float(frequency),
                                   Float(damping), Float(strength))
    }

    /// Point a `.swingTwist` joint's bone along a world direction, rolled
    /// `twist` radians about itself: the powered shoulder, the head that turns
    /// to look, the tentacle segment that reaches. A scalar cannot say which
    /// way a joint that bends in every direction should bend, so this is the
    /// form that drives the whole thing.
    ///
    /// ```swift
    /// neck.drive(toward: (target - head.position).normalized, frequency: 6)
    /// ```
    ///
    /// The target is clamped to the joint's own cone and twist limits, so a
    /// direction outside them leans as far as it is allowed. Set it each frame
    /// to follow something. `stopMotor()` lets go.
    public func drive(toward direction: Vector3, twist: Double = 0,
                      frequency: Double = 4, damping: Double = 1,
                      strength: Double = .infinity) {
        guard let constraint else { return }
        guard case .swingTwist? = kind else {
            world.noteOnce("drive(toward:) points a .swingTwist joint; ignoring.")
            return
        }
        let unit = direction.normalized
        withFloats3((Float(unit.x), Float(unit.y), Float(unit.z))) {
            cjolt_constraint_set_orientation_motor(world.handle, constraint, $0,
                                                   Float(twist), Float(frequency),
                                                   Float(damping), Float(strength))
        }
    }

    /// Cut motor power; the joint swings free again (minus any `friction`).
    public func stopMotor() {
        guard let constraint, kind != nil else { return }
        cjolt_constraint_set_motor(world.handle, constraint, CJOLT_MOTOR_OFF,
                                   0, 0, 0, 0)
    }

    /// Passive resistance while the motor is off: a constant drag torque
    /// (N·m, hinge and swing-twist) or force (N, slider and track) the joint's
    /// motion must overcome. The stiff old hinge; the drawer that stays put;
    /// the shoulder that does not flop. Default 0 (free).
    public var friction: Double = 0 {
        didSet {
            guard let constraint else { return }
            cjolt_constraint_set_friction(world.handle, constraint,
                                          Float(max(0, friction)))
        }
    }

    /// Soften the joint's `limits` into springs: past an end, a spring at
    /// `frequency`/`damping` pulls back instead of a hard stop (the bouncy
    /// door stop). `frequency` 0 restores the hard stop.
    public func softenLimits(frequency: Double, damping: Double = 1) {
        guard let constraint else { return }
        cjolt_constraint_set_limit_spring(world.handle, constraint,
                                          Float(frequency), Float(damping))
    }

    /// A hinge's current angle in radians from the pose at connect (positive
    /// per the right-hand rule about its axis), or a swing-twist's current
    /// swing away from its axis (unsigned, the number its cone bounds); 0 for
    /// the other kinds.
    public var angle: Double {
        guard let constraint else { return 0 }
        switch kind {
        case .revolute?, .swingTwist?:
            return Double(cjolt_constraint_current(world.handle, constraint))
        default:
            return 0
        }
    }

    /// A slider's current offset in world units from the pose at connect
    /// (positive along its axis); 0 for the other kinds.
    public var offset: Double {
        guard case .prismatic? = kind, let constraint else { return 0 }
        return Double(cjolt_constraint_current(world.handle, constraint))
            * world.unitsPerMeter
    }

    /// How far along its track a `.path` joint's body has got: 0 at the first
    /// point of the curve, 1 at the last (and back to 0 on a looping one).
    /// 0 for the other kinds.
    public var progress: Double {
        guard case .path? = kind, let constraint else { return 0 }
        return Double(cjolt_constraint_current(world.handle, constraint))
    }

    /// A `.swingTwist` joint's current roll about its own axis, in radians
    /// (signed, 0 at the pose it was connected in), which is the number its
    /// `twist` range bounds where `angle` reads the bend its cone bounds.
    /// 0 for the other kinds.
    public var twist: Double {
        guard case .swingTwist? = kind, let constraint else { return 0 }
        return Double(cjolt_constraint_twist(world.handle, constraint))
    }

    /// Which of the two motor calls is being made, since a track takes a rate
    /// in world units and a target as a fraction of its whole length.
    private enum MotorMode { case velocity, position }

    /// The scale a motor target is given in (1 for angles and fractions,
    /// world units to meters for a slider or a track's rate), or nil, with a
    /// one-time note, when the joint's kind has no motor.
    private func motorScale(_ mode: MotorMode, _ call: String) -> Double? {
        switch kind {
        case .revolute?, .swingTwist?:
            return 1
        case .prismatic?:
            return 1 / world.unitsPerMeter
        case .path?:
            // A rate runs in world units per second, a target in fractions of
            // the whole curve.
            return mode == .velocity ? 1 / world.unitsPerMeter : 1
        default:
            world.noteOnce("\(call) drives hinges, sliders, swing-twist joints, "
                           + "and tracks; ignoring.")
            return nil
        }
    }

    // MARK: Removal

    /// Cut the joint, freeing the two bodies (or releasing a grab).
    public func remove() {
        world.removeJoint(self)
    }

    /// Destroy the solver constraint (grabs also clean up their hidden
    /// anchor). Called by the world; the joint is inert afterwards.
    func destroyBackingConstraint() {
        guard let constraint else { return }
        if isGrab {
            cjolt_grab_end(world.handle, constraint)
        } else {
            cjolt_constraint_destroy(world.handle, constraint)
        }
        self.constraint = nil
    }
}

/// A structural constraint between two rigid bodies, for
/// `World3D.connect(_:_:_:)`. Anchors and axes are given in world coordinates
/// at the moment of connecting.
public enum JointKind3D {
    /// A hinge: both bodies share the pivot `at` and rotate only about `axis`
    /// through it. The building block of doors, wheels, and swings. `limits`
    /// bounds the swing, in radians relative to the pose at connect (0 = as
    /// connected), so the range must straddle 0: a door that opens 100° one
    /// way is `-0.01...(100 * .pi / 180)`. The solver caps each side at a
    /// half turn (±π). Power it with the joint's `drive(at:)` / `drive(to:)`.
    case revolute(at: Vector3, axis: Vector3, limits: ClosedRange<Double>? = nil)

    /// A ball-and-socket: both bodies share the pivot `at` and rotate freely
    /// about it in every direction. The 3D pendulum, and the joint a limb
    /// hangs off when nothing should stop it.
    case ball(at: Vector3)

    /// A ball-and-socket with limits: the second body's `axis` (the bone
    /// direction, pointing away from the pivot) may lean away from where it
    /// started by at most `swing` radians in any direction, tracing a cone,
    /// while twisting about that axis within `twist`. The shoulder, the hip,
    /// the neck: everything that bends a long way but not all the way, and
    /// only rolls a little.
    ///
    /// ```swift
    /// world.connect(chest, upperArm,
    ///               .swingTwist(at: shoulder, axis: Vector3(-1, 0, 0),
    ///                           swing: 80 * .pi / 180, twist: -0.6...0.6))
    /// ```
    ///
    /// A `swing` of 0 locks the bone straight and π frees it, which is `.ball`
    /// with a twist limit. The solver caps each side of `twist` at a half turn.
    case swingTwist(at: Vector3, axis: Vector3, swing: Double,
                    twist: ClosedRange<Double> = -0.3...0.3)

    /// A rod holding the world anchors `from` (on the first body) and `to` (on
    /// the second) a fixed distance apart. `length` defaults to their current
    /// spacing; `stiffness` below `1` softens the rod into a spring.
    case distance(from: Vector3, to: Vector3, length: Double? = nil,
                  stiffness: Double = 1)

    /// A cable holding the world anchors `from` (on the first body) and `to`
    /// (on the second) no farther apart than `length`, and doing nothing when
    /// they come closer: a tether, a tendon, the tension member of a
    /// tensegrity. `length` defaults to their current spacing; shorter than
    /// that, the cable starts taut and pulls the anchors together. `stiffness`
    /// below `1` lets it stretch like a bungee.
    case cable(from: Vector3, to: Vector3, length: Double? = nil,
               stiffness: Double = 1)

    /// Lock the two bodies rigidly together at their current relative pose.
    case weld

    /// A slider: the second body may translate only along `axis` relative to
    /// the first, pinned at the world point `at`. `limits` bounds the travel,
    /// in world units relative to the pose at connect (0 = as connected), so
    /// the range must straddle 0: a drawer that pulls out 2 units is
    /// `-0.01...2`. Power it with the joint's `drive(at:)` / `drive(to:)`.
    case prismatic(at: Vector3, axis: Vector3, limits: ClosedRange<Double>? = nil)

    /// A track: the second body is threaded onto the smooth curve through
    /// `through` and may only travel along it. The rollercoaster car, the bead
    /// on a wire, the camera on a dolly rail. `looping` joins the last point
    /// back to the first.
    ///
    /// ```swift
    /// let ride = world.connect(rails, car,
    ///                          .path(through: track, looping: true,
    ///                                alignment: .followsPath))
    /// ride.drive(at: 6)          // units per second along the track
    /// ```
    ///
    /// The curve is a smooth spline *through* the points, not a polyline, so a
    /// handful of them describes a long track. Place the body on the track
    /// before connecting: it joins the curve at the point nearest to wherever
    /// it already is. `alignment` says how much of the body's turning the track
    /// takes over, and the joint's `progress` reads where along the curve it
    /// has got to (0 at the first point, 1 at the last).
    ///
    /// The track belongs to the *first* body, so hanging it off a moving one
    /// carries the whole ride along.
    case path(through: [Vector3], looping: Bool = false,
              alignment: PathAlignment = .free)

    /// A rope over two overhead points: the first body's rope end at `from`
    /// runs up over `over`, across to `and`, and down to the second body's end
    /// at `to`. The total length is fixed, so one side rising lowers the other:
    /// the bucket and the counterweight, the sash window, the lift.
    ///
    /// ```swift
    /// world.connect(bucket, weight,
    ///               .pulley(from: bucketTop, over: leftHook,
    ///                       and: rightHook, to: weightTop))
    /// ```
    ///
    /// `ratio` is how many falls of rope hold the second body: 2 is a block
    /// and tackle, where that side moves half as far and lifts twice as much.
    /// A rope resists being pulled longer but not being let slack, which is
    /// what lets both ends drop together; `taut: true` makes it a rigid
    /// linkage instead, holding the length it is created at exactly.
    case pulley(from: Vector3, over: Vector3, and: Vector3, to: Vector3,
                ratio: Double = 1, taut: Bool = false)

    /// The general joint, said the other way round: the two bodies share the
    /// frame `at` and may move *only* in the ways `freedom` allows, out of the
    /// same six a `Body3D` names. Every other kind is a choice of freedoms
    /// (`.weld` is none, `.ball` is the three turns, a hinge is one of them),
    /// so this is the one to reach for when none of them fits.
    ///
    /// ```swift
    /// // A post a platter rides: it may rise and spin, nothing else.
    /// world.connect(post, platter,
    ///               .allowing([.moveY, .turnY], at: top, travel: 0...1.4))
    /// ```
    ///
    /// `travel` bounds every direction it may move in and `rotation` every
    /// axis it may turn about, both measured from the pose at connect, so a
    /// range that allows nothing but 0 is the same as not allowing the freedom
    /// at all. Leave either out to let that half run unbounded. The axes are
    /// the world's at the moment of connecting, exactly as `Body3D.freedom`'s
    /// are.
    case allowing(Freedom3D, at: Vector3, travel: ClosedRange<Double>? = nil,
                  rotation: ClosedRange<Double>? = nil)
}

public extension JointKind3D {
    /// How much of a body's turning its track takes over, for `.path`.
    enum PathAlignment: Sendable {
        /// The track only carries the body along; it tumbles as it likes.
        case free
        /// The body may turn only about the direction of travel: a bead
        /// spinning on its wire, a barrel rolling down a rail.
        case rolls
        /// The body's frame follows the curve, so it banks and turns with the
        /// track. The rollercoaster car.
        case followsPath
        /// The body holds the first body's orientation the whole way round.
        case fixed
    }

    /// A track traced by a flat `Contour`, laid down at height `y`: the
    /// contour's x runs along the world's x and its y along the world's z, so
    /// a curve drawn in plan view becomes a track on the ground.
    ///
    /// ```swift
    /// let loop = Path { p in p.move(to: …); p.curve(…) }.contours[0]
    /// world.connect(ground, cart, .path(loop, atHeight: 0.3))
    /// ```
    ///
    /// The contour's coordinates are world units, not canvas pixels, and a
    /// closed contour makes a looping track unless `looping` says otherwise.
    static func path(_ contour: Contour, atHeight y: Double = 0,
                     looping: Bool? = nil,
                     alignment: PathAlignment = .free) -> JointKind3D {
        .path(through: contour.points.map { Vector3($0.x, y, $0.y) },
              looping: looping ?? contour.isClosed,
              alignment: alignment)
    }
}

/// One joint driving another: gears, and a rack and pinion. Hand two joints to
/// `World3D.connect(_:_:_:)` rather than two bodies, because what is tied
/// together is the *motion* the joints allow, and the joints are what know
/// which way each part turns or slides.
public enum JointLink3D: Sendable {
    /// Meshed gears: turning one hinge turns the other, in the opposite sense.
    /// `ratio` is how many turns the first makes for each turn of the second,
    /// so a small gear driving a big one has a ratio above 1. It counts teeth
    /// and has no sign; to turn a pair the same way, flip one hinge's axis.
    case gear(ratio: Double = 1)

    /// A pinion turning a rack: turning the hinge slides the slider.
    /// `travelPerTurn` is how far the rack travels, in world units, for one
    /// full turn of the pinion, which for a pinion of radius `r` rolling along
    /// the rack is `2 * .pi * r`. A negative value runs the rack the other way.
    case rackAndPinion(travelPerTurn: Double)

    /// Meshed gears given as tooth counts, which is how a gear train is
    /// usually written down.
    public static func gear(teeth: Int, and other: Int) -> JointLink3D {
        .gear(ratio: Double(other) / Double(max(teeth, 1)))
    }
}
