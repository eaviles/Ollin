import Foundation
import Ollin
internal import CJolt

/// A constraint linking two rigid `Body3D`s (a hinge, a ball-and-socket, a
/// rod, a weld, a slider) or a body to a moving target (a grab). Create the
/// structural kinds with `World3D.connect(_:_:_:)` and a grab with
/// `World3D.grab(_:at:)` (or the mouse-driven `grabBody(at:in:)` sketch
/// sugar). Hold onto the returned joint to retarget a grab (`target`) or cut
/// the link (`remove()`).
public final class Joint3D {

    /// The world this joint lives in.
    unowned let world: World3D

    /// The underlying solver constraint (nil once removed, or if creation
    /// failed on a stale body).
    private(set) var constraint: OpaquePointer?

    /// The bodies this joint connects, so removing a body can cascade.
    let a: CJoltBodyID
    let b: CJoltBodyID

    /// Whether this is a grab joint, so `target` knows to drive it.
    private let isGrab: Bool

    /// For a mouse-driven grab, the view depth the sketch sugar drags in.
    var grabViewDepth: Double?

    init(world: World3D, constraint: OpaquePointer?,
         a: CJoltBodyID, b: CJoltBodyID, isGrab: Bool = false) {
        self.world = world
        self.constraint = constraint
        self.a = a
        self.b = b
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
    /// through it. The building block of doors, wheels, and swings.
    case revolute(at: Vector3, axis: Vector3)

    /// A ball-and-socket: both bodies share the pivot `at` and rotate freely
    /// about it in every direction. The 3D pendulum and ragdoll joint.
    case ball(at: Vector3)

    /// A rod holding the world anchors `from` (on the first body) and `to` (on
    /// the second) a fixed distance apart. `length` defaults to their current
    /// spacing; `stiffness` below `1` softens the rod into a spring.
    case distance(from: Vector3, to: Vector3, length: Double? = nil,
                  stiffness: Double = 1)

    /// Lock the two bodies rigidly together at their current relative pose.
    case weld

    /// A slider: the second body may translate only along `axis` relative to
    /// the first, pinned at the world point `at`.
    case prismatic(at: Vector3, axis: Vector3)
}
