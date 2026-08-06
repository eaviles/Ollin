import Foundation
import simd
import Ollin

// Picking up physics somebody else authored. A `.usd` scene may carry
// UsdPhysics annotations saying which of its prims are rigid bodies, which are
// colliders and what shape, and how they are jointed together, and this turns
// those into the ordinary `addBody` and `connect` calls.
//
// The direction matters. Reading is lossy and that is fine: a file's notion of
// a body is a description, and anything it does not say has a sensible answer
// here. Writing would not be, which is why the snapshot stays Ollin's own
// format and this is the interchange leg.

extension World3D {

    /// Add every rigid body, collider, and joint a loaded scene's physics
    /// annotations describe, and return the bodies made.
    ///
    /// A `.usd` file can say which of its prims are physical: which fall,
    /// which are scenery, what shape each collides as, and how they are
    /// jointed. That is the `UsdPhysics` schema, and a scene carrying it comes
    /// into a world in one call:
    ///
    /// ```swift
    /// let scene = loadScene("crates.usdz")!
    /// world.addBodies(from: scene)
    /// // …then draw the scene as usual, or drive it from world.bodies
    /// ```
    ///
    /// Each body's `assetName` is set to the name of the prim it came from,
    /// which is how a drawing loop matches a body to the part of the scene it
    /// is moving, and how a snapshot of this world names its geometry.
    ///
    /// What comes across: rigid bodies (falling, driven, or scenery) with
    /// their mass, density, centre of mass, velocity, and whether they start
    /// asleep; colliders as boxes, balls, capsules, cylinders, cones, hulls,
    /// and exact meshes, several in one subtree fusing into one compound body;
    /// friction and restitution from a bound physics material; the fixed,
    /// revolute, prismatic, spherical, and distance joints, with their limits;
    /// and the scene's gravity when it authored one.
    ///
    /// What does not: articulations, joint drives and their limit API,
    /// collision groups and filtered pairs, and anything a solver would have
    /// invented rather than read. Those are said in the file's own vocabulary
    /// rather than one this world has, so they are left alone.
    ///
    /// - Parameters:
    ///   - scene: a scene loaded from a `.usd`, `.usdc`, `.usda`, or `.usdz`
    ///     file carrying `UsdPhysics` annotations.
    ///   - applyGravity: whether a `PhysicsScene` prim's gravity replaces this
    ///     world's. Off by default: a sketch's own gravity is usually the one
    ///     it wants.
    ///   - group: which collision group everything joins.
    @discardableResult
    public func addBodies(from scene: Scene, applyGravity: Bool = false,
                          group: CollisionGroup = .default) -> [Body3D] {
        let description = scene.physics
        guard !description.isEmpty else {
            noteOnce("this scene carries no physics annotations, so there was "
                     + "nothing to add; a file has to say which of its prims "
                     + "are bodies (the UsdPhysics schema) for them to come "
                     + "across as any")
            return []
        }
        if applyGravity, let authored = description.gravity { gravity = authored }

        var made: [Body3D] = []
        var byPath: [String: Body3D] = [:]
        for described in description.bodies {
            guard let collider = collider(for: described.shapes) else { continue }
            let material = described.shapes.first
            let body = addBody(collider, at: described.position,
                               kind: kind(of: described.motion), isSensor: false,
                               rotated: 0, axis: .unitY,
                               density: described.density ?? material?.density ?? 1,
                               friction: material?.friction ?? 0.5,
                               restitution: material?.restitution,
                               mass: described.mass,
                               centerOfMass: described.centerOfMass ?? .zero,
                               group: group,
                               orientation: described.rotation,
                               velocity: described.velocity,
                               angularVelocity: described.angularVelocity,
                               asleep: described.startsAsleep)
            body.assetName = described.name
            body.userData = described.name
            made.append(body)
            byPath[described.path] = body
        }

        for described in description.joints {
            // A joint naming only one body holds it to the world, which is
            // what the floor slab is for; a joint naming neither has nothing
            // to hold.
            let first = described.body0.flatMap { byPath[$0] }
            let second = described.body1.flatMap { byPath[$0] }
            guard let anchor = first ?? second else { continue }
            let other = first == nil ? nil : second
            connectDescribed(described, anchor: anchor, other: other)
        }
        return made
    }

    private func kind(of motion: ScenePhysicsMotion) -> Body3D.Kind {
        switch motion {
        case .dynamic: return .dynamic
        case .static: return .static
        case .kinematic: return .kinematic
        }
    }

    /// The collider a body's shapes make: one shape on its own, or a compound
    /// of all of them, which is what a subtree of colliders under one body
    /// describes.
    private func collider(for shapes: [ScenePhysicsShape]) -> Collider3D? {
        guard !shapes.isEmpty else { return nil }
        if shapes.count == 1, shapes[0].position == .zero,
           shapes[0].rotation == SIMD4(0, 0, 0, 1) {
            return form(of: shapes[0])
        }
        let parts = shapes.compactMap { shape -> Collider3D.Part? in
            guard let inner = form(of: shape) else { return nil }
            let turn = angleAxis(of: shape.rotation)
            return .part(inner, at: shape.position, rotated: turn.angle,
                         axis: turn.axis)
        }
        guard !parts.isEmpty else { return nil }
        return parts.count == 1 && parts[0].position == .zero && parts[0].angle == 0
            ? parts[0].collider : .compound(parts)
    }

    private func form(of shape: ScenePhysicsShape) -> Collider3D? {
        switch shape.form {
        case .box(let width, let height, let depth):
            return .box(width: width, height: height, depth: depth)
        case .sphere(let radius):
            return .sphere(radius: radius)
        case .capsule(let height, let radius):
            return .capsule(height: height, radius: radius)
        case .cylinder(let height, let radius):
            return .cylinder(height: height, radius: radius)
        case .cone(let height, let radius):
            return .cone(height: height, radius: radius)
        case .mesh(let mesh):
            return .mesh(mesh)
        case .hull(let points):
            return points.count >= 4 ? .hull(points) : nil
        }
    }

    /// Make one described joint. The file gives an attachment frame inside
    /// each body, which is the point the joint acts at; a `connect` call wants
    /// that point in the world, so it is carried out through the anchor's own
    /// pose.
    private func connectDescribed(_ described: ScenePhysicsJoint,
                                  anchor: Body3D, other: Body3D?) {
        let attachment = worldPoint(described.localPosition0, on: anchor)
        let secondAttachment = other.map {
            worldPoint(described.localPosition1, on: $0)
        }
        // A joint that names only one body holds it to the world itself,
        // which is a thing the solver can do without a second body.
        let kind: JointKind3D
        switch described.kind {
        case .fixed:
            kind = .weld
        case .revolute(let axis, let limits):
            kind = .revolute(at: attachment, axis: turn(axis, by: anchor),
                             limits: limits)
        case .prismatic(let axis, let limits):
            kind = .prismatic(at: attachment, axis: turn(axis, by: anchor),
                              limits: limits)
        case .spherical(let axis, let cone):
            kind = cone.map {
                JointKind3D.swingTwist(at: attachment, axis: turn(axis, by: anchor),
                                       swing: $0)
            } ?? .ball(at: attachment)
        case .distance(let minimum, let maximum):
            // One rod of the length the file allowed. A range a solver would
            // slacken through is a single length here, so the longer end wins:
            // a rope that may reach that far.
            kind = .distance(from: attachment,
                             to: secondAttachment ?? attachment,
                             length: maximum ?? minimum)
        }
        if let other {
            connect(anchor, other, kind)
        } else {
            connect(anchor, toWorld: kind)
        }
    }

    /// A point in a body's own space, in the world.
    private func worldPoint(_ local: Vector3, on body: Body3D) -> Vector3 {
        let q = body.quaternion
        let turn = simd_quatd(ix: Double(q.0), iy: Double(q.1), iz: Double(q.2),
                              r: Double(q.3))
        let rotated = turn.act(SIMD3(local.x, local.y, local.z))
        return body.position + Vector3(rotated.x, rotated.y, rotated.z)
    }

    /// A direction in a body's own space, in the world.
    private func turn(_ axis: Vector3, by body: Body3D) -> Vector3 {
        let q = body.quaternion
        let turn = simd_quatd(ix: Double(q.0), iy: Double(q.1), iz: Double(q.2),
                              r: Double(q.3))
        let rotated = turn.act(SIMD3(axis.x, axis.y, axis.z))
        let result = Vector3(rotated.x, rotated.y, rotated.z)
        return result.length > 1e-9 ? result.normalized : Vector3(0, 1, 0)
    }

    /// A quaternion as the angle-about-an-axis the collider calls take.
    private func angleAxis(of rotation: SIMD4<Double>)
        -> (angle: Double, axis: Vector3) {
        let turn = simd_quatd(ix: rotation.x, iy: rotation.y, iz: rotation.z,
                              r: rotation.w).normalized
        let sine = simd_length(turn.imag)
        guard sine > 1e-9 else { return (0, Vector3(0, 1, 0)) }
        return (2 * atan2(sine, turn.real),
                Vector3(turn.imag.x / sine, turn.imag.y / sine, turn.imag.z / sine))
    }
}
