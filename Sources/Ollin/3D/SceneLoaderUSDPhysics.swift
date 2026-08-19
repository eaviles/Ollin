import Foundation
import simd

// The UsdPhysics leg of USD scene import: rigid-body, collider, and joint
// annotations authored somewhere else become a `ScenePhysics` description the
// physics satellite turns into a live world. Reading is lossy on purpose,
// which is why this direction works where writing the format would not: a
// solver's own notion of a body is far richer than the file's, and everything
// here is a description of what the file said rather than of what any
// particular solver would do with it.
//
// What a prim has to say to be picked up, all verified against the schema
// rather than remembered:
//
//   PhysicsRigidBodyAPI on a prim   → a body that falls. Everything under it
//                                     belongs to it, so several colliders in
//                                     one subtree make one compound body.
//   PhysicsCollisionAPI, no body    → a static collider: scenery.
//   physics:kinematicEnabled        → driven rather than simulated
//   physics:rigidBodyEnabled false  → static after all
//   PhysicsMassAPI                  → mass, density, center of mass
//   PhysicsMaterialAPI (bound)      → friction and restitution
//   PhysicsMeshCollisionAPI         → how a mesh is approximated
//   PhysicsScene                    → gravity
//
// The shape of a collider is the prim's *own geometry*: there is no shape
// attribute, so a Cube with a collider on it is a box and a Sphere is a ball.
// Two things there are easy to get wrong and are handled deliberately. USD's
// Capsule, Cylinder, and Cone stand on **z** by default (`axis`, which may
// also be x or y) where Ollin's stand on y, so the difference is baked into
// the shape's pose inside its body. And a Cube is sized by one `size` rather
// than three extents, which any authored scale then stretches.
//
// The stage's `upAxis` and `metersPerUnit` are deliberately not applied, the
// same contract the rest of USD import keeps: a scene arrives as authored.

/// Everything the physics annotations of a USD stage say, in the vocabulary
/// the physics satellite reads. Attached to a `Scene` at load, so
/// `world.addBodies(from: scene)` has something to build from.
package struct ScenePhysics: Sendable {
    /// The bodies, in the order their prims were authored.
    package var bodies: [ScenePhysicsBody] = []
    /// The joints between them.
    package var joints: [ScenePhysicsJoint] = []
    /// The gravity a `PhysicsScene` prim asked for, when one did.
    package var gravity: Vector3?

    package var isEmpty: Bool { bodies.isEmpty && joints.isEmpty && gravity == nil }
}

/// How one body is simulated.
package enum ScenePhysicsMotion: Sendable {
    case dynamic, `static`, kinematic
}

/// One shape inside a body, in the body's own local space.
package struct ScenePhysicsShape: Sendable {
    package enum Form: Sendable {
        case box(width: Double, height: Double, depth: Double)
        case sphere(radius: Double)
        /// A capsule standing on y, `height` between the cap centers.
        case capsule(height: Double, radius: Double)
        case cylinder(height: Double, radius: Double)
        case cone(height: Double, radius: Double)
        /// The exact triangles, for a mesh a file asked to keep exact.
        case mesh(Mesh)
        /// The points a mesh a file asked to approximate is wrapped around.
        case hull([Vector3])
    }

    package var form: Form
    /// Where the shape sits inside its body.
    package var position: Vector3
    /// How it is turned there, as a unit quaternion `(x, y, z, w)`.
    package var rotation: SIMD4<Double>
    /// The physics material bound to this shape, when one was.
    package var friction: Double?
    package var restitution: Double?
    package var density: Double?
}

/// One rigid body the file describes.
package struct ScenePhysicsBody: Sendable {
    /// The prim's name, which is what a sketch recognizes it by.
    package var name: String
    /// The prim's path, which is what a joint names it by.
    package var path: String
    package var motion: ScenePhysicsMotion
    /// Where the body stands, and which way it faces.
    package var position: Vector3
    package var rotation: SIMD4<Double>
    /// The shapes it wears, each posed inside it.
    package var shapes: [ScenePhysicsShape]
    package var mass: Double?
    package var density: Double?
    package var centerOfMass: Vector3?
    package var velocity: Vector3
    package var angularVelocity: Vector3
    package var startsAsleep: Bool
}

/// One joint the file describes, naming the two prims it holds together.
package struct ScenePhysicsJoint: Sendable {
    package enum Kind: Sendable {
        case fixed
        case revolute(axis: Vector3, limits: ClosedRange<Double>?)
        case prismatic(axis: Vector3, limits: ClosedRange<Double>?)
        /// A ball joint. `coneAngle` is how far the bone may lean, in radians,
        /// when the file said.
        case spherical(axis: Vector3, coneAngle: Double?)
        case distance(minimum: Double?, maximum: Double?)
    }

    package var name: String
    package var kind: Kind
    /// The prim paths of the two bodies. A missing one means the world.
    package var body0: String?
    package var body1: String?
    /// Where the joint attaches inside each body, and how it is turned there.
    package var localPosition0: Vector3
    package var localRotation0: SIMD4<Double>
    package var localPosition1: Vector3
    package var localRotation1: SIMD4<Double>
}

extension Scene {

    /// The UsdPhysics annotations this scene was loaded with, if any.
    package var physics: ScenePhysics { physicsDescription ?? ScenePhysics() }

    /// The prim type names that carry a collider's shape.
    static let usdCollisionShapeTypes: Set<String> = [
        "Cube", "Sphere", "Capsule", "Cylinder", "Cone", "Mesh", "Plane",
    ]

    /// Reads every physics annotation on a stage.
    static func resolveUSDPhysics(_ stage: USDStage) -> ScenePhysics {
        var physics = ScenePhysics()

        // Which prims are bodies, and where each one stands. A body owns
        // everything under it, so the walk records the deepest body above each
        // prim and hangs that prim's collider on it.
        var bodyOfPath: [String: Int] = [:]
        var worldOfBody: [Int: simd_double4x4] = [:]
        var materials: [String: (friction: Double?, restitution: Double?, density: Double?)] = [:]

        // Materials first: a collider may be bound to one authored anywhere.
        stage.visitPrims { prim, path, _ in
            guard prim.applies("PhysicsMaterialAPI") else { return }
            materials[path] = (prim.physicsScalar("physics:dynamicFriction"),
                                    prim.physicsScalar("physics:restitution"),
                                    prim.physicsScalar("physics:density"))
        }

        stage.visitPrims { prim, path, world in
            if prim.typeName == "PhysicsScene", physics.gravity == nil {
                physics.gravity = usdGravity(prim)
            }
            guard prim.applies("PhysicsRigidBodyAPI") else { return }
            // `physics:rigidBodyEnabled = false` is a body that has been told
            // to stop being one, which is a static collider.
            let enabled = prim.physicsBool("physics:rigidBodyEnabled") ?? true
            let kinematic = prim.physicsBool("physics:kinematicEnabled") ?? false
            let pose = usdPose(of: world)
            let index = physics.bodies.count
            physics.bodies.append(ScenePhysicsBody(
                name: prim.name, path: path,
                motion: !enabled ? .static : (kinematic ? .kinematic : .dynamic),
                position: pose.position, rotation: pose.rotation, shapes: [],
                mass: prim.physicsScalar("physics:mass").flatMap { $0 > 0 ? $0 : nil },
                density: prim.physicsScalar("physics:density").flatMap { $0 > 0 ? $0 : nil },
                centerOfMass: prim.physicsPoint("physics:centerOfMass"),
                velocity: prim.physicsVector("physics:velocity") ?? .zero,
                angularVelocity: prim.physicsVector("physics:angularVelocity") ?? .zero,
                startsAsleep: prim.physicsBool("physics:startsAsleep") ?? false))
            bodyOfPath[path] = index
            worldOfBody[index] = world
        }

        // Then the colliders, each hung on the body above it, or standing on
        // its own as scenery when there is none.
        stage.visitPrims { prim, path, world in
            guard prim.applies("PhysicsCollisionAPI"),
                  prim.physicsBool("physics:collisionEnabled") ?? true,
                  usdCollisionShapeTypes.contains(prim.typeName) else { return }
            guard var shape = usdShape(prim) else { return }

            let bound = prim.relationship("material:binding:physics")?.targets.first
                ?? prim.relationship("material:binding")?.targets.first
            if let bound, let material = materials[bound] {
                shape.friction = material.friction
                shape.restitution = material.restitution
                shape.density = material.density
            }

            // A shape's size is whatever the prim's *world* transform scales
            // it to, always. Taking it from the collider's transform inside
            // its body loses it entirely whenever the collider prim is the
            // body prim, which is the common case: that local transform is
            // the identity.
            shape = scaled(shape, by: usdScale(of: world))

            if let owner = deepestBody(above: path, in: bodyOfPath),
               let bodyWorld = worldOfBody[owner] {
                // Where the collider stands inside its body, measured against
                // the body's own rotation and place rather than against any
                // scale it carries, since that scale is already in the sizes.
                let body = usdPose(of: bodyWorld)
                let here = usdPose(of: world)
                shape.position = inverse(body, applyingTo: here.position)
                shape.rotation = combine(combine(conjugate(body.rotation),
                                                 here.rotation), shape.rotation)
                physics.bodies[owner].shapes.append(shape)
            } else {
                // Scenery: a collider with no body over it is a static body of
                // its own, standing where the prim stands.
                let pose = usdPose(of: world)
                physics.bodies.append(ScenePhysicsBody(
                    name: prim.name, path: path, motion: .static,
                    position: pose.position, rotation: pose.rotation,
                    shapes: [shape],
                    mass: nil, density: nil, centerOfMass: nil,
                    velocity: .zero, angularVelocity: .zero, startsAsleep: false))
            }
        }

        stage.visitPrims { prim, _ in
            guard let joint = usdJoint(prim) else { return }
            physics.joints.append(joint)
        }
        return physics
    }

    /// The body a prim belongs to: the nearest one at or above it.
    private static func deepestBody(above path: String,
                                    in bodies: [String: Int]) -> Int? {
        var current = path
        while !current.isEmpty {
            if let index = bodies[current] { return index }
            guard let slash = current.lastIndex(of: "/"), slash != current.startIndex
            else { return nil }
            current = String(current[current.startIndex ..< slash])
        }
        return nil
    }

    /// A `PhysicsScene`'s gravity, when it authored one. The schema's own
    /// "unset" markers are a zero direction and a magnitude of -inf.
    private static func usdGravity(_ prim: USDPrim) -> Vector3? {
        let direction = prim.physicsVector("physics:gravityDirection")
        let magnitude = prim.physicsScalar("physics:gravityMagnitude")
        guard let direction, direction.length > 1e-9 else { return nil }
        guard let magnitude, magnitude.isFinite, magnitude >= 0 else { return nil }
        return direction.normalized * magnitude
    }

    /// The shape a collider prim's own geometry describes, standing on y.
    private static func usdShape(_ prim: USDPrim) -> ScenePhysicsShape? {
        let upright = SIMD4<Double>(0, 0, 0, 1)
        switch prim.typeName {
        case "Cube":
            let size = prim.physicsScalar("size") ?? 2
            return ScenePhysicsShape(form: .box(width: size, height: size, depth: size),
                                     position: .zero, rotation: upright)
        case "Sphere":
            return ScenePhysicsShape(form: .sphere(radius: prim.physicsScalar("radius") ?? 1),
                                     position: .zero, rotation: upright)
        case "Capsule", "Cylinder", "Cone":
            let radius = prim.physicsScalar("radius") ?? (prim.typeName == "Capsule" ? 0.5 : 1)
            let height = prim.physicsScalar("height") ?? (prim.typeName == "Capsule" ? 1 : 2)
            let form: ScenePhysicsShape.Form = switch prim.typeName {
            case "Capsule": .capsule(height: height, radius: radius)
            case "Cylinder": .cylinder(height: height, radius: radius)
            default: .cone(height: height, radius: radius)
            }
            // USD stands these on z unless told otherwise; Ollin's stand on y,
            // so the difference becomes the shape's own turn inside its body.
            return ScenePhysicsShape(form: form, position: .zero,
                                     rotation: uprightFrom(prim.attribute("axis")?
                                        .value?.usdToken ?? "Z"))
        case "Plane":
            // A ground plane has no thickness a solver can use, so it comes in
            // as a wide, thin slab of the size the file gave it.
            let width = prim.physicsScalar("width") ?? 2
            let length = prim.physicsScalar("length") ?? 2
            return ScenePhysicsShape(form: .box(width: width, height: 0.01, depth: length),
                                     position: .zero,
                                     rotation: uprightFrom(prim.attribute("axis")?
                                        .value?.usdToken ?? "Z"))
        case "Mesh":
            guard let built = buildUSDMesh(prim, keepIndexed: false, material: nil)
            else { return nil }
            let mesh = built.mesh
            // `none` keeps the triangles, which only a static body may wear;
            // every other approximation is a hull, which any body may.
            let approximation = prim.attribute("physics:approximation")?
                .value?.usdToken ?? "none"
            let form: ScenePhysicsShape.Form = approximation == "none"
                ? .mesh(mesh) : .hull(mesh.positions)
            return ScenePhysicsShape(form: form, position: .zero, rotation: upright)
        default:
            return nil
        }
    }

    /// The turn that stands a shape built along `axis` up on y.
    private static func uprightFrom(_ axis: String) -> SIMD4<Double> {
        let half = Double.pi / 4
        switch axis {
        case "X": return SIMD4(0, 0, sin(half), cos(half))    // +x onto +y
        case "Y": return SIMD4(0, 0, 0, 1)
        default: return SIMD4(-sin(half), 0, 0, cos(half))    // +z onto +y
        }
    }

    /// A world point in a pose's own frame.
    private static func inverse(_ pose: (position: Vector3, rotation: SIMD4<Double>),
                                applyingTo point: Vector3) -> Vector3 {
        let turn = simd_quatd(ix: pose.rotation.x, iy: pose.rotation.y,
                              iz: pose.rotation.z, r: pose.rotation.w).inverse
        let offset = point - pose.position
        let local = turn.act(SIMD3(offset.x, offset.y, offset.z))
        return Vector3(local.x, local.y, local.z)
    }

    private static func conjugate(_ q: SIMD4<Double>) -> SIMD4<Double> {
        SIMD4(-q.x, -q.y, -q.z, q.w)
    }

    /// One quaternion after another (`outer` applied to `inner`).
    private static func combine(_ outer: SIMD4<Double>,
                                _ inner: SIMD4<Double>) -> SIMD4<Double> {
        let a = simd_quatd(ix: outer.x, iy: outer.y, iz: outer.z, r: outer.w)
        let b = simd_quatd(ix: inner.x, iy: inner.y, iz: inner.z, r: inner.w)
        let product = (a * b).normalized
        return SIMD4(product.imag.x, product.imag.y, product.imag.z, product.real)
    }

    /// A transform's translation and rotation, with any scale divided out.
    private static func usdPose(of matrix: simd_double4x4)
        -> (position: Vector3, rotation: SIMD4<Double>) {
        let scale = usdScale(of: matrix)
        var basis = simd_double3x3(columns: (matrix.columns.0.xyz, matrix.columns.1.xyz,
                                             matrix.columns.2.xyz))
        basis.columns.0 /= max(scale.x, 1e-9)
        basis.columns.1 /= max(scale.y, 1e-9)
        basis.columns.2 /= max(scale.z, 1e-9)
        let turn = simd_quatd(basis).normalized
        return (Vector3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z),
                SIMD4(turn.imag.x, turn.imag.y, turn.imag.z, turn.real))
    }

    private static func usdScale(of matrix: simd_double4x4) -> Vector3 {
        Vector3(simd_length(matrix.columns.0.xyz), simd_length(matrix.columns.1.xyz),
                simd_length(matrix.columns.2.xyz))
    }

    /// A shape grown by an authored scale. A solver's shapes have no scale of
    /// their own, so it is worked into their sizes; anything but a uniform
    /// scale on a round shape is a shape it cannot be, so the largest wins.
    private static func scaled(_ shape: ScenePhysicsShape,
                               by scale: Vector3) -> ScenePhysicsShape {
        var result = shape
        let widest = max(scale.x, max(scale.y, scale.z))
        // A shape turned onto y has already had its own axis swapped, so a
        // round one takes one number rather than trying to follow the swap.
        let round = max(scale.x, scale.z)
        switch shape.form {
        case .box(let width, let height, let depth):
            result.form = .box(width: width * scale.x, height: height * scale.y,
                               depth: depth * scale.z)
        case .sphere(let radius):
            result.form = .sphere(radius: radius * widest)
        case .capsule(let height, let radius):
            result.form = .capsule(height: height * scale.y, radius: radius * round)
        case .cylinder(let height, let radius):
            result.form = .cylinder(height: height * scale.y, radius: radius * round)
        case .cone(let height, let radius):
            result.form = .cone(height: height * scale.y, radius: radius * round)
        case .mesh(var mesh):
            mesh.positions = mesh.positions.map {
                Vector3($0.x * scale.x, $0.y * scale.y, $0.z * scale.z)
            }
            result.form = .mesh(mesh)
        case .hull(let points):
            result.form = .hull(points.map {
                Vector3($0.x * scale.x, $0.y * scale.y, $0.z * scale.z)
            })
        }
        return result
    }

    /// The joint a prim describes, when it describes one.
    private static func usdJoint(_ prim: USDPrim) -> ScenePhysicsJoint? {
        guard prim.physicsBool("physics:jointEnabled") ?? true else { return nil }
        let axis = usdAxis(prim.attribute("physics:axis")?.value?.usdToken ?? "X")
        let kind: ScenePhysicsJoint.Kind
        switch prim.typeName {
        case "PhysicsFixedJoint":
            kind = .fixed
        case "PhysicsRevoluteJoint":
            // The schema's limits are in degrees, and an infinite one is the
            // way it spells "no limit".
            kind = .revolute(axis: axis, limits: usdLimits(prim, degrees: true))
        case "PhysicsPrismaticJoint":
            kind = .prismatic(axis: axis, limits: usdLimits(prim, degrees: false))
        case "PhysicsSphericalJoint":
            let cone = prim.physicsScalar("physics:coneAngle0Limit")
            kind = .spherical(axis: axis,
                              coneAngle: cone.flatMap { $0 >= 0 ? $0 * .pi / 180 : nil })
        case "PhysicsDistanceJoint":
            let low = prim.physicsScalar("physics:minDistance")
            let high = prim.physicsScalar("physics:maxDistance")
            kind = .distance(minimum: low.flatMap { $0 >= 0 ? $0 : nil },
                             maximum: high.flatMap { $0 >= 0 ? $0 : nil })
        default:
            return nil
        }
        return ScenePhysicsJoint(
            name: prim.name, kind: kind,
            body0: prim.relationship("physics:body0")?.targets.first,
            body1: prim.relationship("physics:body1")?.targets.first,
            localPosition0: prim.physicsVector("physics:localPos0") ?? .zero,
            localRotation0: prim.physicsQuaternion("physics:localRot0"),
            localPosition1: prim.physicsVector("physics:localPos1") ?? .zero,
            localRotation1: prim.physicsQuaternion("physics:localRot1"))
    }

    private static func usdAxis(_ token: String) -> Vector3 {
        switch token {
        case "Y": return Vector3(0, 1, 0)
        case "Z": return Vector3(0, 0, 1)
        default: return Vector3(1, 0, 0)
        }
    }

    /// A joint's authored range, or nil when either end is the schema's
    /// infinite "no limit".
    private static func usdLimits(_ prim: USDPrim, degrees: Bool) -> ClosedRange<Double>? {
        guard let low = prim.physicsScalar("physics:lowerLimit"),
              let high = prim.physicsScalar("physics:upperLimit"),
              low.isFinite, high.isFinite, low <= high else { return nil }
        let scale = degrees ? Double.pi / 180 : 1
        return (low * scale)...(high * scale)
    }
}

// MARK: - Reading physics attributes

extension USDPrim {

    /// Whether an applied API schema is on this prim. The list is authored as
    /// `prepend apiSchemas = [...]`, which the parser records under the bare
    /// key, and its shape differs by container (tokens from crate, strings
    /// from text), so it reads through the shared accessor.
    func applies(_ schema: String) -> Bool {
        metadata["apiSchemas"]?.usdTokenArray?.contains { $0 == schema
            || $0.hasPrefix("\(schema):") } ?? false
    }

    func physicsScalar(_ name: String) -> Double? {
        attribute(name)?.value?.usdScalar
    }

    func physicsBool(_ name: String) -> Bool? {
        guard case .bool(let value)? = attribute(name)?.value else { return nil }
        return value
    }

    func physicsVector(_ name: String) -> Vector3? {
        guard let c = attribute(name)?.value?.usdComponents(count: 3) else { return nil }
        return Vector3(c[0], c[1], c[2])
    }

    /// A point whose "unset" marker is the schema's -inf triple.
    func physicsPoint(_ name: String) -> Vector3? {
        guard let point = physicsVector(name),
              point.x.isFinite, point.y.isFinite, point.z.isFinite else { return nil }
        return point
    }

    /// A quaternion as `(x, y, z, w)`. USD authors these real-first, and the
    /// parser hands both containers back that way, so the real part is the
    /// component that moves.
    func physicsQuaternion(_ name: String) -> SIMD4<Double> {
        guard let c = attribute(name)?.value?.usdComponents(count: 4) else {
            return SIMD4(0, 0, 0, 1)
        }
        return SIMD4(c[1], c[2], c[3], c[0])
    }
}

extension SIMD4 where Scalar == Double {
    fileprivate var xyz: SIMD3<Double> { SIMD3(x, y, z) }
}
