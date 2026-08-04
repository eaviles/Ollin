import Foundation
import Ollin
internal import CJolt

/// A constraint linking two rigid `Body3D`s (a hinge, a ball-and-socket, a
/// rod, a weld, a slider) or a body to a moving target (a grab). Create the
/// structural kinds with `World3D.connect(_:_:_:)` and a grab with
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

    /// The kind this joint was connected as (nil for a grab), so the motor
    /// knobs know whether they drive an angle or an offset.
    public let kind: JointKind3D?

    /// Whether this is a grab joint, so `target` knows to drive it.
    private let isGrab: Bool

    /// For a mouse-driven grab, the view depth the sketch sugar drags in.
    var grabViewDepth: Double?

    init(world: World3D, constraint: OpaquePointer?,
         a: CJoltBodyID, b: CJoltBodyID, kind: JointKind3D? = nil,
         isGrab: Bool = false) {
        self.world = world
        self.constraint = constraint
        self.a = a
        self.b = b
        self.kind = kind
        self.isGrab = isGrab
    }

    /// For a grab joint (from `World3D.grab`), the world point the body is
    /// pulled toward; set it each frame to drag the body around. No effect on
    /// the structural joints.
    public var target: Vector3 = .zero {
        didSet {
            if isGrab { world.dragGrab(self) }
        }
    }

    // MARK: Motors (hinges and sliders)

    /// Spin the joint at a constant rate: radians per second about a hinge's
    /// axis, world units per second along a slider. The windmill and the
    /// conveyor. `strength` caps how hard the motor may push (torque in N·m
    /// for a hinge, force in N for a slider); the unlimited default reaches
    /// the rate almost instantly, a small value lets the load win.
    public func drive(at velocity: Double, strength: Double = .infinity) {
        guard let scale = motorScale(for: "drive(at:)") else { return }
        guard let constraint else { return }
        cjolt_constraint_set_motor(world.handle, constraint, CJOLT_MOTOR_VELOCITY,
                                   Float(velocity * scale), 0, 0, Float(strength))
    }

    /// Pull the joint toward a target (an angle in radians for a hinge, 0
    /// being the pose at connect; an offset in world units for a slider) with
    /// a spring servo. `frequency` is how fast it pulls: 2 a lazy door closer,
    /// 20 a snappy servo. `damping` at 1 settles clean, lower overshoots and
    /// bounces. `strength` caps the torque (N·m) or force (N).
    public func drive(to target: Double, frequency: Double = 2,
                      damping: Double = 1, strength: Double = .infinity) {
        guard let scale = motorScale(for: "drive(to:)") else { return }
        guard let constraint else { return }
        cjolt_constraint_set_motor(world.handle, constraint, CJOLT_MOTOR_POSITION,
                                   Float(target * scale), Float(frequency),
                                   Float(damping), Float(strength))
    }

    /// Cut motor power; the joint swings free again (minus any `friction`).
    public func stopMotor() {
        guard let constraint, kind != nil else { return }
        cjolt_constraint_set_motor(world.handle, constraint, CJOLT_MOTOR_OFF,
                                   0, 0, 0, 0)
    }

    /// Passive resistance while the motor is off: a constant drag torque
    /// (N·m, hinge and swing-twist) or force (N, slider) the joint's motion
    /// must overcome. The stiff old hinge; the drawer that stays put; the
    /// shoulder that does not flop. Default 0 (free).
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

    /// The target scale for a motor call (1 for angles, world-units to meters
    /// for a slider), or nil, with a one-time note, when the joint's kind has
    /// no motor.
    private func motorScale(for call: String) -> Double? {
        switch kind {
        case .revolute?:
            return 1
        case .prismatic?:
            return 1 / world.unitsPerMeter
        case .swingTwist?:
            // A swing-twist motor pulls toward a whole orientation, not a
            // number, which is what a ragdoll's `drive(toward:)` hands it.
            world.noteOnce("\(call) drives only .revolute and .prismatic joints; a "
                           + "swing-twist is powered by driving a Ragdoll3D toward a pose.")
            return nil
        default:
            world.noteOnce("\(call) drives only .revolute and .prismatic joints; ignoring.")
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

    /// Lock the two bodies rigidly together at their current relative pose.
    case weld

    /// A slider: the second body may translate only along `axis` relative to
    /// the first, pinned at the world point `at`. `limits` bounds the travel,
    /// in world units relative to the pose at connect (0 = as connected), so
    /// the range must straddle 0: a drawer that pulls out 2 units is
    /// `-0.01...2`. Power it with the joint's `drive(at:)` / `drive(to:)`.
    case prismatic(at: Vector3, axis: Vector3, limits: ClosedRange<Double>? = nil)
}
