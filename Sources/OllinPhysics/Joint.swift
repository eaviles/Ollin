import Foundation
import Ollin
internal import CBox2D

/// A constraint linking two rigid `Body`s — a hinge, a rod, a weld, a slider — or
/// a body to a moving target (a cursor grab). Create the structural kinds with
/// `World.connect(_:_:_:)` and a grab with `World.grab(_:at:)`. Hold onto the
/// returned joint to retarget a grab (`target`) or cut the link (`remove()`).
public final class Joint {

    /// The world this joint lives in.
    unowned let world: World

    /// The underlying Box2D joint handle.
    let id: b2JointId

    /// Whether this is a grab (mouse) joint, so `target` knows to drive it.
    private let isGrab: Bool

    init(world: World, id: b2JointId, isGrab: Bool = false) {
        self.world = world
        self.id = id
        self.isGrab = isGrab
    }

    /// For a grab joint (from `World.grab`), the world point the body is pulled
    /// toward — set it each frame to drag the body around. No effect on the
    /// structural joints.
    public var target: Vector2 = .zero {
        didSet {
            if isGrab { b2MouseJoint_SetTarget(id, world.meters(from: target)) }
        }
    }

    /// Cut the joint, freeing the two bodies (or releasing a grab).
    public func remove() {
        world.removeJoint(self)
    }
}

/// A structural constraint between two rigid bodies, for `World.connect(_:_:_:)`.
/// Anchors are given in world points at the moment of connecting.
public enum JointKind {
    /// A hinge: both bodies share a pivot at the world point `at` and rotate
    /// freely about it. The building block of chains, ragdolls, and pendulums.
    case revolute(at: Vector2)

    /// A rod holding the world anchors `from` (on the first body) and `to` (on the
    /// second) a fixed distance apart. `length` defaults to their current spacing;
    /// `stiffness` below `1` softens the rod into a spring.
    case distance(from: Vector2, to: Vector2, length: Double? = nil, stiffness: Double = 1)

    /// Lock the two bodies rigidly together at their current relative pose.
    case weld

    /// A slider: the second body may translate only along `axis` (world space)
    /// relative to the first, pinned at the world point `at`.
    case prismatic(at: Vector2, axis: Vector2)
}
