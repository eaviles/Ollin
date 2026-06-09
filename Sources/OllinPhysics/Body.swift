import Foundation
import Ollin
import CBox2D

/// A rigid body in a `World`: a shape with mass that the solver moves, rotates,
/// stacks, and joins. Where a `Particle` is a soft Verlet point (no orientation,
/// constraints that nudge positions), a `Body` is a proper rigid body — it has an
/// `angle`, spins, rests in stable stacks, and bounces off other bodies with real
/// contact response. It shares the world's `gravity`, `bounds` (as walls), and
/// `bounce`, and is measured in sketch points (the world converts to the solver's
/// meters through `World.pixelsPerMeter`).
///
/// Create one with `World.addBody(_:at:)`, hang drawing data off `userData`, and
/// draw it from `position`/`angle` each frame:
///
/// ```swift
/// let box = world.addBody(.box(width: 80, height: 40), at: Vector2(540, 120))
/// // each frame:
/// withState {
///     translate(box.position)
///     rotate(box.angle)
///     drawRect(center: .zero, width: 80, height: 40)
/// }
/// ```
public final class Body {

    /// How the solver treats a body: `dynamic` (moved by forces and contacts),
    /// `static` (immovable — walls, ground), or `kinematic` (moved only by a
    /// velocity you set, unaffected by forces).
    public enum Kind { case dynamic, `static`, kinematic }

    /// The world this body lives in. Unowned: the world holds its bodies, not the
    /// other way around.
    unowned let world: World

    /// The underlying Box2D body handle.
    let id: b2BodyId

    /// Free-form tag so a sketch can hang its own data off a body (its colour, its
    /// drawn size, a group id) without a parallel array — as `Particle` does.
    public var userData: Any?

    init(world: World, id: b2BodyId) {
        self.world = world
        self.id = id
    }

    /// The body's centre, in sketch points.
    public var position: Vector2 {
        get { world.points(from: b2Body_GetPosition(id)) }
        set { b2Body_SetTransform(id, world.meters(from: newValue), b2Body_GetRotation(id)) }
    }

    /// The body's orientation, in radians. Positive is clockwise on screen (the
    /// y-down convention Ollin's `rotate(_:)` already uses).
    public var angle: Double {
        get { Double(b2Rot_GetAngle(b2Body_GetRotation(id))) }
        set { b2Body_SetTransform(id, b2Body_GetPosition(id), b2MakeRot(Float(newValue))) }
    }

    /// Linear velocity, in points per second. (A real velocity, unlike a
    /// `Particle`'s per-step Verlet displacement.)
    public var velocity: Vector2 {
        get { world.points(from: b2Body_GetLinearVelocity(id)) }
        set { b2Body_SetLinearVelocity(id, world.meters(from: newValue)) }
    }

    /// Spin rate, in radians per second.
    public var angularVelocity: Double {
        get { Double(b2Body_GetAngularVelocity(id)) }
        set { b2Body_SetAngularVelocity(id, Float(newValue)) }
    }

    /// The body's mass (from its shapes' density and area). Read-only.
    public var mass: Double { Double(b2Body_GetMass(id)) }

    /// Whether the body is dynamic, static, or kinematic. Switching to `.static`
    /// freezes it in place (an anchor); back to `.dynamic` lets forces move it.
    public var kind: Kind {
        get { Kind(b2Body_GetType(id)) }
        set { b2Body_SetType(id, newValue.b2Type) }
    }

    /// Push the body's centre of mass with a steady force (points/s² · mass),
    /// accumulated for the next `step`. Use for thrust, wind, attraction.
    public func applyForce(_ force: Vector2) {
        b2Body_ApplyForceToCenter(id, world.meters(from: force), true)
    }

    /// Kick the body's centre of mass with an instantaneous impulse (a sudden
    /// change in velocity · mass) — a hit, a launch.
    public func applyImpulse(_ impulse: Vector2) {
        b2Body_ApplyLinearImpulseToCenter(id, world.meters(from: impulse), true)
    }

    /// Apply a torque (spin) about the centre of mass.
    public func applyTorque(_ torque: Double) {
        b2Body_ApplyTorque(id, Float(torque), true)
    }
}

extension Body.Kind {
    var b2Type: b2BodyType {
        switch self {
        case .dynamic: return b2_dynamicBody
        case .static: return b2_staticBody
        case .kinematic: return b2_kinematicBody
        }
    }

    init(_ type: b2BodyType) {
        if type == b2_staticBody { self = .static }
        else if type == b2_kinematicBody { self = .kinematic }
        else { self = .dynamic }
    }
}

/// The shape of a rigid `Body`. Position and rotation come from the `Body`, so a
/// collider is just its local geometry (centred on the body's origin).
public enum Collider {
    /// A disk of the given radius (points).
    case circle(radius: Double)
    /// An axis-aligned box of the given size (points), before the body's rotation.
    case box(width: Double, height: Double)
    /// A capsule (stadium): a line between two local-space points, thickened to
    /// `radius` with rounded ends.
    case capsule(from: Vector2, to: Vector2, radius: Double)
    /// A convex polygon from local-space points (its convex hull is taken, up to
    /// 8 vertices). Pass at least three points.
    case polygon([Vector2])
}
