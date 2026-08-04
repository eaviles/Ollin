import Foundation
import Ollin
internal import CJolt

/// A rigid body in a `World3D`: a shape with mass that the solver moves,
/// rotates, stacks, and joins, the spatial sibling of the 2D `Body`. It has a
/// full 3D orientation, spins about any axis, rests in stable piles, and
/// bounces off other bodies with real contact response. Measured in the 3D
/// scene's world units (the world converts to the solver's meters through
/// `World3D.unitsPerMeter`).
///
/// Create one with `World3D.addBody(_:at:)`, hang drawing data off `userData`,
/// and draw it each frame with `withBody(_:)`, which moves the 3D transform
/// stack to the body's pose:
///
/// ```swift
/// let box = world.addBody(.box(width: 1, height: 1, depth: 1),
///                         at: Vector3(0, 4, 0))
/// // each frame:
/// withBody(box) { drawBox(width: 1, height: 1, depth: 1) }
/// ```
public final class Body3D {

    /// How the solver treats a body: `dynamic` (moved by forces and contacts),
    /// `static` (immovable: walls, ground), or `kinematic` (moved only by a
    /// velocity you set, unaffected by forces).
    public enum Kind { case dynamic, `static`, kinematic }

    /// The world this body lives in. Unowned: the world holds its bodies, not
    /// the other way around.
    unowned let world: World3D

    /// The underlying solver body handle.
    let id: CJoltBodyID

    /// The local shape this body was created with, so a drawing loop can match
    /// its mesh to its collider without a parallel array.
    public let collider: Collider3D

    /// The relative density the body was created with.
    public let density: Double

    /// Free-form tag so a sketch can hang its own data off a body (its colour,
    /// its mesh, a group id) without a parallel array.
    public var userData: Any?

    /// Backing store for `kind` (the solver is told on set).
    private var storedKind: Kind

    init(world: World3D, id: CJoltBodyID, collider: Collider3D, kind: Kind,
         density: Double) {
        self.world = world
        self.id = id
        self.collider = collider
        self.storedKind = kind
        self.density = density
    }

    /// The body's centre, in world units.
    public var position: Vector3 {
        get {
            let out = readFloats3 { cjolt_body_get_position(world.handle, id, $0) }
            return world.units(from: out.0, out.1, out.2)
        }
        set {
            withFloats3(world.meters(from: newValue)) {
                cjolt_body_set_position(world.handle, id, $0, true)
            }
        }
    }

    /// The body's orientation as an angle (radians) about `rotationAxis`.
    /// The two properties read the same pose; use them together.
    public var rotationAngle: Double {
        let q = quaternion
        return 2 * acos(max(-1, min(1, Double(q.3))))
    }

    /// The axis of the body's current rotation (unit length; `unitY` when the
    /// body is unrotated).
    public var rotationAxis: Vector3 {
        let q = quaternion
        let s = (1 - Double(q.3) * Double(q.3)).squareRoot()
        guard s > 1e-6 else { return .unitY }
        return Vector3(Double(q.0) / s, Double(q.1) / s, Double(q.2) / s)
    }

    /// Set the body's orientation to a rotation of `angle` radians about `axis`.
    public func setRotation(_ angle: Double, axis: Vector3) {
        let unit = axis.normalized
        let half = angle / 2
        let s = sin(half)
        withFloats4((Float(unit.x * s), Float(unit.y * s), Float(unit.z * s),
                     Float(cos(half)))) {
            cjolt_body_set_rotation(world.handle, id, $0, true)
        }
    }

    /// Linear velocity, in world units per second.
    public var velocity: Vector3 {
        get {
            let out = readFloats3 { cjolt_body_get_linear_velocity(world.handle, id, $0) }
            return world.units(from: out.0, out.1, out.2)
        }
        set {
            withFloats3(world.meters(from: newValue)) {
                cjolt_body_set_linear_velocity(world.handle, id, $0)
            }
        }
    }

    /// Spin rate about each axis, in radians per second.
    public var angularVelocity: Vector3 {
        get {
            let out = readFloats3 { cjolt_body_get_angular_velocity(world.handle, id, $0) }
            return Vector3(Double(out.0), Double(out.1), Double(out.2))
        }
        set {
            withFloats3((Float(newValue.x), Float(newValue.y), Float(newValue.z))) {
                cjolt_body_set_angular_velocity(world.handle, id, $0)
            }
        }
    }

    /// The body's mass (from its collider's volume and `density`). Read-only;
    /// `0` for static and kinematic bodies.
    public var mass: Double { Double(cjolt_body_get_mass(world.handle, id)) }

    /// Whether the body is dynamic, static, or kinematic. Switching to
    /// `.static` freezes it in place (an anchor); back to `.dynamic` lets
    /// forces move it.
    public var kind: Kind {
        get { storedKind }
        set {
            storedKind = newValue
            cjolt_body_set_motion(world.handle, id, newValue.cjolt)
        }
    }

    /// Whether the body is awake (a settled body sleeps until touched).
    public var isAwake: Bool { cjolt_body_is_active(world.handle, id) }

    /// Push the body's centre of mass with a steady force (units/s² · mass),
    /// accumulated for the next `step`. Use for thrust, wind, attraction.
    public func applyForce(_ force: Vector3) {
        withFloats3(world.meters(from: force)) {
            cjolt_body_add_force(world.handle, id, $0)
        }
    }

    /// Kick the body's centre of mass with an instantaneous impulse (a sudden
    /// change in velocity · mass): a hit, a launch.
    public func applyImpulse(_ impulse: Vector3) {
        withFloats3(world.meters(from: impulse)) {
            cjolt_body_add_impulse(world.handle, id, $0)
        }
    }

    /// Apply a torque (spin) about each axis through the centre of mass.
    public func applyTorque(_ torque: Vector3) {
        let scale = 1 / (world.unitsPerMeter * world.unitsPerMeter)
        withFloats3((Float(torque.x * scale), Float(torque.y * scale),
                     Float(torque.z * scale))) {
            cjolt_body_add_torque(world.handle, id, $0)
        }
    }

    /// The body's orientation quaternion `(x, y, z, w)`, for the drawing sugar.
    var quaternion: (Float, Float, Float, Float) {
        readFloats4 { cjolt_body_get_rotation(world.handle, id, $0) }
    }
}

extension Body3D.Kind {
    var cjolt: CJoltMotionType {
        switch self {
        case .dynamic: return CJOLT_MOTION_DYNAMIC
        case .static: return CJOLT_MOTION_STATIC
        case .kinematic: return CJOLT_MOTION_KINEMATIC
        }
    }
}

/// The shape of a rigid `Body3D`. Position and orientation come from the body,
/// so a collider is just its local geometry, centred on the body's origin.
public enum Collider3D {
    /// A ball of the given radius.
    case sphere(radius: Double)
    /// A box of the given size, before the body's rotation.
    case box(width: Double, height: Double, depth: Double)
    /// A capsule standing along the body's y axis: a segment of `height`
    /// between the two cap centres, thickened to `radius` with rounded ends.
    case capsule(height: Double, radius: Double)
    /// A flat-capped cylinder standing along the body's y axis.
    case cylinder(height: Double, radius: Double)
    /// The convex hull of local-space points. Pass at least four points that
    /// aren't all on one plane.
    case hull([Vector3])
    /// The exact triangles of a `Mesh` (its local positions and indices).
    /// Static bodies only: a mesh collider has no volume for mass, so a
    /// dynamic body created with one is pinned in place. Use `hull` (or a
    /// compound of primitives) for moving shapes.
    case mesh(Mesh)
}

extension Collider3D {
    /// The C shape description plus the flat vertex/index storage it points
    /// into (returned so the caller can keep the arrays alive while binding).
    func shapeDesc(unitsPerMeter: Double) -> (CJoltShapeDesc, [Float], [UInt32]) {
        var desc = CJoltShapeDesc()
        var points: [Float] = []
        var indices: [UInt32] = []
        let m = { (v: Double) in Float(v / unitsPerMeter) }
        switch self {
        case .sphere(let radius):
            desc.type = CJOLT_SHAPE_SPHERE
            desc.a = m(radius)
        case .box(let width, let height, let depth):
            desc.type = CJOLT_SHAPE_BOX
            desc.a = m(width / 2)
            desc.b = m(height / 2)
            desc.c = m(depth / 2)
        case .capsule(let height, let radius):
            desc.type = CJOLT_SHAPE_CAPSULE
            desc.a = m(height / 2)
            desc.b = m(radius)
        case .cylinder(let height, let radius):
            desc.type = CJOLT_SHAPE_CYLINDER
            desc.a = m(height / 2)
            desc.b = m(radius)
        case .hull(let corners):
            desc.type = CJOLT_SHAPE_CONVEX_HULL
            points.reserveCapacity(corners.count * 3)
            for corner in corners {
                points.append(m(corner.x))
                points.append(m(corner.y))
                points.append(m(corner.z))
            }
        case .mesh(let mesh):
            desc.type = CJOLT_SHAPE_MESH
            points.reserveCapacity(mesh.positions.count * 3)
            for position in mesh.positions {
                points.append(m(position.x))
                points.append(m(position.y))
                points.append(m(position.z))
            }
            indices = mesh.indices.isEmpty
                ? Array(0 ..< UInt32(mesh.positions.count))
                : mesh.indices
        }
        return (desc, points, indices)
    }
}
