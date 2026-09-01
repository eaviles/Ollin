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

    /// Whether this body is a detector volume rather than a solid one: it
    /// reports what overlaps it and pushes nothing. Fixed when the body is
    /// added (see `World3D.addBody(_:at:kind:isSensor:)`).
    public let isSensor: Bool

    /// How hard `World3D.water` pushes this body up, against what its own
    /// weight and volume already say. `1`, the default, floats it exactly where
    /// its `density` puts it; above 1 rides it higher than it should; `0` sinks
    /// it whatever it is made of. Reach for `density` first and keep this for
    /// the one crate that has to bob higher than the rest.
    public var buoyancyScale: Double = 1

    /// Free-form tag so a sketch can hang its own data off a body (its color,
    /// its mesh, a group id) without a parallel array.
    public var userData: Any?

    /// A name for the geometry this body's collider was cut from, so a
    /// snapshot can write the name down instead of every vertex of it. Only a
    /// `.mesh` or `.heightfield` collider has anything heavy to name; on
    /// anything else it is carried as a label and nothing more.
    ///
    /// ```swift
    /// island.assetName = "island"
    /// // …and when the world comes back:
    /// world.restore(saved) { $0 == "island" ? .heightfield(terrain) : nil }
    /// ```
    ///
    /// `userData` is the sibling for everything that is not going in a file.
    public var assetName: String?

    /// The mass the body was created with, when one was given instead of being
    /// worked out from the shape. Restricting `freedom` has to re-derive the
    /// body's mass properties, and a body whose travel is already locked
    /// reports no mass of its own, so this is what it is rebuilt from.
    let overriddenMass: Double?

    /// Backing store for `kind` (the solver is told on set).
    private var storedKind: Kind

    init(world: World3D, id: CJoltBodyID, collider: Collider3D, kind: Kind,
         density: Double, isSensor: Bool = false, overriddenMass: Double? = nil) {
        self.world = world
        self.id = id
        self.collider = collider
        self.storedKind = kind
        self.density = density
        self.isSensor = isSensor
        self.overriddenMass = overriddenMass
    }

    /// The body's center, in world units.
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

    /// The body's mass (from its collider's volume and `density`, or whatever
    /// it was created with). Read-only; `0` for static and kinematic bodies.
    public var mass: Double {
        let reported = Double(cjolt_body_get_mass(world.handle, id))
        // Static and kinematic bodies have no mass to report.
        guard reported > 0 else { return reported }
        // A body with every direction of travel locked is infinitely heavy to
        // push, so the solver keeps no mass for it and the bridge falls back to
        // what the shape's volume says. A body handed its own mass instead is
        // the one case that answer is wrong for.
        return overriddenMass ?? reported
    }

    /// Whether the body is dynamic, static, or kinematic. Switching to
    /// `.static` freezes it in place (an anchor); back to `.dynamic` lets
    /// forces move it.
    public var kind: Kind {
        get { storedKind }
        set {
            // A sensor holds its own motion type: it is kinematic and awake so
            // that a body asleep inside it keeps being reported.
            guard !isSensor else {
                world.noteOnce("a sensor body's kind is fixed; move it by "
                               + "setting its position")
                return
            }
            storedKind = newValue
            cjolt_body_set_motion(world.handle, id, newValue.cjolt)
        }
    }

    /// Which ways the body is allowed to move. `.all` (the default) leaves it
    /// free; restricting it is how a body is kept flat, kept upright, or kept
    /// from spinning at all.
    ///
    /// ```swift
    /// coin.freedom = .plane()      // travels in x and y, spins about z
    /// crate.freedom = .upright     // slides and turns, never tips over
    /// ```
    ///
    /// A locked direction is one the solver gives the body infinite mass along,
    /// so nothing can push it that way: not gravity, not a contact, not a
    /// joint, not `applyForce`. Setting this rebuilds how the body's weight is
    /// spread and wakes it.
    public var freedom: Freedom3D {
        get { Freedom3D(rawValue: cjolt_body_get_freedom(world.handle, id)) }
        set {
            cjolt_body_set_freedom(world.handle, id, newValue.rawValue,
                                   Float(overriddenMass ?? 0))
        }
    }

    /// How hard the world's gravity pulls on this body, against what everything
    /// else feels. `1` is the default; `0` leaves it weightless (it still gets
    /// pushed around by everything else), and a negative value makes it rise.
    ///
    /// ```swift
    /// balloon.gravityScale = -0.3   // drifts upward
    /// feather.gravityScale = 0.15   // falls slowly
    /// ```
    public var gravityScale: Double {
        get { Double(cjolt_body_get_gravity_factor(world.handle, id)) }
        set { cjolt_body_set_gravity_factor(world.handle, id, Float(newValue)) }
    }

    /// Whether the solver checks the body's whole path each step rather than
    /// only where it ends up. Off by default, and worth turning on for anything
    /// small and quick: a body that covers more than its own width between two
    /// steps can be on one side of a thin wall at one step and past it at the
    /// next, having never touched it.
    ///
    /// ```swift
    /// let pellet = world.addBody(.sphere(radius: 0.05), at: muzzle,
    ///                            checksPath: true)
    /// pellet.velocity = Vector3(0, 0, 120)
    /// ```
    ///
    /// (This is continuous collision detection. It costs nothing while the body
    /// is moving slowly, since the check only runs once a body covers a good
    /// fraction of its own size in one step; a body that hits something at
    /// speed gives up the rest of its step at the impact, so it can read as
    /// briefly slowing down where a body that tunnelled would not have.)
    public var checksPath: Bool {
        get { cjolt_body_get_continuous(world.handle, id) }
        set { cjolt_body_set_continuous(world.handle, id, newValue) }
    }

    /// How much the body's surface grips what it slides against, `0` slick …
    /// `1` grippy. Two touching bodies' frictions combine, so a puck on ice
    /// needs both of them low.
    public var friction: Double {
        get { Double(cjolt_body_get_friction(world.handle, id)) }
        set { cjolt_body_set_friction(world.handle, id, Float(newValue)) }
    }

    /// How much speed survives a bounce off this body, `0` dead … `1` lively.
    /// Defaults to the world's `bounce` unless `addBody` was given its own.
    public var restitution: Double {
        get { Double(cjolt_body_get_restitution(world.handle, id)) }
        set { cjolt_body_set_restitution(world.handle, id, Float(newValue)) }
    }

    /// Whether the body is awake (a settled body sleeps until touched).
    public var isAwake: Bool { cjolt_body_is_active(world.handle, id) }

    /// Wake a settled body, so it feels a rule that changed under it.
    public func wake() {
        cjolt_body_activate(world.handle, id)
    }

    /// Put a body to sleep where it stands, as though it had settled there.
    /// Anything that touches it wakes it again.
    public func sleep() {
        cjolt_body_deactivate(world.handle, id)
    }

    /// Which collision group the body is in. Set it to move the body between
    /// groups; what it then passes through is whatever the world's
    /// `ignoreCollisions(between:and:)` rules say about that group.
    ///
    /// ```swift
    /// crate.group = "debris"        // now ignored by whatever ignores debris
    /// ```
    public var group: CollisionGroup {
        get { world.group(at: cjolt_body_get_group(world.handle, id)) }
        set {
            cjolt_body_set_group(world.handle, id, world.groupIndex(newValue))
            // A vehicle's wheels feel the road through their own testers, which
            // are built against the chassis's group and so are rebuilt here.
            world.bodyChangedGroup(self)
        }
    }

    // MARK: Touching

    /// Everything currently in contact with this body, in a stable order. For a
    /// sensor that is everything inside it, including bodies that have settled
    /// and fallen asleep there:
    ///
    /// ```swift
    /// let load = plate.touching.count      // how many crates are on the plate
    /// ```
    ///
    /// A cloth lying on it is in the list too, as the `SoftBody3D` it is.
    public var touching: [any Colliding3D] {
        (world.touchingIDs[id] ?? []).compactMap { world.colliding(at: $0) }
    }

    /// Whether the two are touching right now (for a sensor, whether `other` is
    /// inside it). `other` may be a soft body.
    public func isTouching(_ other: any Colliding3D) -> Bool {
        guard let otherID = world.identifier(of: other) else { return false }
        return world.touchingIDs[id]?.contains(otherID) ?? false
    }

    /// The touches involving this body that started or stopped during the last
    /// `step`, out of the world's whole list.
    public var contacts: [Contact3D] {
        world.contacts.filter { $0.involves(self) }
    }

    /// What started touching this body during the last `step`: the arrivals.
    /// For a sensor, what just came in.
    ///
    /// ```swift
    /// score += goal.arrivals.count
    /// ```
    public var arrivals: [any Colliding3D] {
        world.contacts.compactMap { $0.phase == .began ? $0.other(than: self) : nil }
    }

    /// What stopped touching this body during the last `step`: the departures.
    /// For a sensor, what just left.
    public var departures: [any Colliding3D] {
        world.contacts.compactMap { $0.phase == .ended ? $0.other(than: self) : nil }
    }

    /// Push the body's center of mass with a steady force (units/s² · mass),
    /// accumulated for the next `step`. Use for thrust, wind, attraction.
    public func applyForce(_ force: Vector3) {
        withFloats3(world.meters(from: force)) {
            cjolt_body_add_force(world.handle, id, $0)
        }
    }

    /// Kick the body's center of mass with an instantaneous impulse (a sudden
    /// change in velocity · mass): a hit, a launch.
    public func applyImpulse(_ impulse: Vector3) {
        withFloats3(world.meters(from: impulse)) {
            cjolt_body_add_impulse(world.handle, id, $0)
        }
    }

    /// Apply a torque (spin) about each axis through the center of mass.
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
/// so a collider is just its local geometry, centered on the body's origin.
public enum Collider3D {
    /// A ball of the given radius.
    case sphere(radius: Double)
    /// A box of the given size, before the body's rotation.
    case box(width: Double, height: Double, depth: Double)
    /// A capsule standing along the body's y axis: a segment of `height`
    /// between the two cap centers, thickened to `radius` with rounded ends.
    case capsule(height: Double, radius: Double)
    /// A flat-capped cylinder standing along the body's y axis.
    case cylinder(height: Double, radius: Double)
    /// A capsule whose two caps differ in radius (a club, a bowling-pin
    /// segment): cap centers at `±height/2` along y, the wall sloping between
    /// `bottomRadius` and `topRadius`. Both radii must be positive; a cap the
    /// other fully contains collapses to that sphere.
    case taperedCapsule(height: Double, topRadius: Double, bottomRadius: Double)
    /// A flat-capped cylinder whose radius slopes from `bottomRadius` at
    /// `-height/2` to `topRadius` at `+height/2` (a frustum; equal radii make
    /// a plain cylinder).
    case taperedCylinder(height: Double, topRadius: Double, bottomRadius: Double)
    /// A cone standing on its base: the base disk at `-height/2` tapering to
    /// an apex at `+height/2`, matching `drawCone`.
    case cone(height: Double, radius: Double)
    /// The convex hull of local-space points. Pass at least four points that
    /// aren't all on one plane.
    case hull([Vector3])
    /// The exact triangles of a `Mesh` (its local positions and indices).
    /// Static bodies only: a mesh collider has no volume for mass, so a
    /// dynamic body created with one is pinned in place. Use `hull` (or a
    /// compound of primitives) for moving shapes.
    case mesh(Mesh)
    /// A `Heightfield` as solid terrain, sized exactly like its
    /// `mesh(width:depth:height:)`: a `width` × `depth` grid centered on the
    /// body's origin in the ground plane, each sample lifted to
    /// `height · value` on +y, so the collider and the drawn mesh trace one
    /// surface. The field is resampled onto a square power-of-two grid (at
    /// least the source resolution, capped at 1024 per side). Static bodies
    /// only, like `mesh`.
    case heightfield(Heightfield, width: Double, depth: Double, height: Double)
    /// Several colliders fused rigidly into one body (a hammer, a table, a
    /// blade cross), each part posed in the body's local space. Mass, balance,
    /// and inertia come from the whole assembly (see `Part.density` for
    /// heavy-headed tools). Parts should be solid shapes: `mesh` and
    /// `heightfield` parts pin the body in place, like a bare `mesh` does.
    case compound([Part])

    /// One shape of a `compound` collider: a child collider at a fixed
    /// position and rotation inside the body. Build parts with
    /// `.part(_:at:rotated:axis:density:)`.
    public struct Part {
        /// The part's shape (any collider; a nested compound is allowed).
        public var collider: Collider3D
        /// The part's center in the body's local space.
        public var position: Vector3
        /// The part's local rotation: `angle` radians about `axis`.
        public var angle: Double
        public var axis: Vector3
        /// The part's relative density, multiplying the body's own: `10` makes
        /// a hammer head heavy against a `1` handle.
        public var density: Double

        /// A part for a `compound` collider, posed in the body's local space.
        public static func part(_ collider: Collider3D, at position: Vector3 = .zero,
                                rotated angle: Double = 0, axis: Vector3 = .unitY,
                                density: Double = 1) -> Part {
            Part(collider: collider, position: position, angle: angle, axis: axis,
                 density: density)
        }
    }
}

extension Collider3D {
    /// Whether the solver can only hold this shape still (a mesh or height
    /// field anywhere in it): a dynamic body created with one is pinned.
    var mustBeStatic: Bool {
        switch self {
        case .mesh, .heightfield:
            return true
        case .compound(let parts):
            return parts.contains { $0.collider.mustBeStatic }
        default:
            return false
        }
    }

    /// The C shape description, in solver meters. Flat data (hull points, mesh
    /// indices, height samples, child descriptors) lands in `arena`, which the
    /// caller must keep alive across the create call.
    func shapeDesc(unitsPerMeter: Double, density: Double,
                   arena: ShapeDescArena) -> CJoltShapeDesc {
        var desc = CJoltShapeDesc()
        // `density` is relative (1 = the default material); the solver works
        // in kg/m³, where the default material is water-like at 1000.
        desc.density = Float(max(0.0001, density) * 1000)
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
        case .taperedCapsule(let height, let topRadius, let bottomRadius):
            desc.type = CJOLT_SHAPE_TAPERED_CAPSULE
            desc.a = m(height / 2)
            desc.b = m(topRadius)
            desc.c = m(bottomRadius)
        case .taperedCylinder(let height, let topRadius, let bottomRadius):
            desc.type = CJOLT_SHAPE_TAPERED_CYLINDER
            desc.a = m(height / 2)
            desc.b = m(topRadius)
            desc.c = m(bottomRadius)
        case .cone(let height, let radius):
            desc.type = CJOLT_SHAPE_TAPERED_CYLINDER
            desc.a = m(height / 2)
            desc.b = 0
            desc.c = m(radius)
        case .hull(let corners):
            var points: [Float] = []
            points.reserveCapacity(corners.count * 3)
            for corner in corners {
                points.append(m(corner.x))
                points.append(m(corner.y))
                points.append(m(corner.z))
            }
            desc.type = CJOLT_SHAPE_CONVEX_HULL
            desc.points = arena.store(points)
            desc.pointCount = Int32(corners.count)
        case .mesh(let mesh):
            var points: [Float] = []
            points.reserveCapacity(mesh.positions.count * 3)
            for position in mesh.positions {
                points.append(m(position.x))
                points.append(m(position.y))
                points.append(m(position.z))
            }
            let indices = mesh.indices.isEmpty
                ? Array(0 ..< UInt32(mesh.positions.count))
                : mesh.indices
            desc.type = CJOLT_SHAPE_MESH
            desc.points = arena.store(points)
            desc.pointCount = Int32(mesh.positions.count)
            desc.indices = arena.store(indices)
            desc.indexCount = Int32(indices.count)
        case .heightfield(let field, let width, let depth, let height):
            // Resample onto the square grid the solver stores: bilinear reads
            // of the source field at n × n normalized coordinates.
            let n = Collider3D.heightfieldSamples(for: field)
            var heights = [Float]()
            heights.reserveCapacity(n * n)
            for iz in 0 ..< n {
                let v = Double(iz) / Double(n - 1)
                for ix in 0 ..< n {
                    heights.append(Float(field.value(u: Double(ix) / Double(n - 1),
                                                     v: v)))
                }
            }
            desc.type = CJOLT_SHAPE_HEIGHT_FIELD
            desc.heights = arena.store(heights)
            desc.sampleCount = Int32(n)
            // Surface = offset + scale · (ix, height, iz): centered like the
            // drawn mesh, sample heights scaled by the mesh's own `height`.
            desc.fieldOffset = (m(-width / 2), 0, m(-depth / 2))
            desc.fieldScale = (m(width / Double(n - 1)), m(height),
                               m(depth / Double(n - 1)))
        case .compound(let parts):
            var children: [CJoltShapeChild] = []
            children.reserveCapacity(parts.count)
            for part in parts {
                let child = part.collider.shapeDesc(unitsPerMeter: unitsPerMeter,
                                                    density: density * part.density,
                                                    arena: arena)
                let unit = part.axis.normalized
                let half = part.angle / 2
                let s = sin(half)
                var posed = CJoltShapeChild()
                posed.shape = arena.store([child])
                posed.position = (m(part.position.x), m(part.position.y),
                                  m(part.position.z))
                posed.rotation = (Float(unit.x * s), Float(unit.y * s),
                                  Float(unit.z * s), Float(cos(half)))
                children.append(posed)
            }
            desc.type = CJOLT_SHAPE_COMPOUND
            desc.children = arena.store(children)
            desc.childCount = Int32(parts.count)
        }
        return desc
    }

    /// The square sample count a `heightfield` collider stores: the smallest
    /// power of two covering the source grid's cells, clamped to 4…1024 (a
    /// 257-sample diamond-square field maps onto its natural 256).
    static func heightfieldSamples(for field: Heightfield) -> Int {
        let target = max(field.columns, field.rows) - 1
        var n = 4
        while n < target && n < 1024 { n *= 2 }
        return n
    }
}
