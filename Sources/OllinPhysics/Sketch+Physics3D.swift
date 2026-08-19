import Foundation
import Ollin
internal import CJolt

// Drawing and mouse sugar for `World3D`: pose the transform stack from a body,
// and grab bodies through the camera with the cursor. All of it rides the
// public core surface (`withState`, the 3D transforms, `activeCamera`), so
// exports, batches, and every renderer rule apply with no new machinery.
extension Sketch {

    /// Run `draw` with the 3D transform stack moved to `body`'s pose, so the
    /// block draws in the body's local space:
    ///
    /// ```swift
    /// withBody(box) { drawBox(width: 1, height: 1, depth: 1) }
    /// ```
    public func withBody(_ body: Body3D, _ draw: () -> Void) {
        let position = body.position
        let q = body.quaternion
        let w = max(-1, min(1, Double(q.3)))
        let angle = 2 * acos(w)
        let s = (1 - w * w).squareRoot()
        withState {
            translate(position)
            if s > 1e-6 {
                rotate(angle, axis: Vector3(Double(q.0) / s, Double(q.1) / s,
                                            Double(q.2) / s))
            }
            draw()
        }
    }

    /// Run `draw` with the 3D transform stack moved to `character`'s feet and
    /// turned to its `facing`, so the block draws a figure standing on the
    /// ground at the origin:
    ///
    /// ```swift
    /// withCharacter(walker) {
    ///     translate(0, 0.9, 0)                 // the capsule's middle
    ///     drawCapsule(height: 1.2, radius: 0.3)
    /// }
    /// ```
    public func withCharacter(_ character: Character3D, _ draw: () -> Void) {
        withState {
            translate(character.position)
            if character.facing != 0 { rotate(character.facing, axis: .unitY) }
            draw()
        }
    }

    /// Run `draw` with the 3D transform stack moved to `wheel`'s pose, so the
    /// block draws in the wheel's local space: steered, spinning, and riding
    /// its suspension. A tire modeled as a cylinder along +y lands right:
    ///
    /// ```swift
    /// for wheel in car.wheels {
    ///     withWheel(wheel) { drawCylinder(height: wheel.width, radius: wheel.radius) }
    /// }
    /// ```
    public func withWheel(_ wheel: Wheel3D, _ draw: () -> Void) {
        withState {
            translate(wheel.center)
            let angle = wheel.rotationAngle
            if abs(angle) > 1e-6 { rotate(angle, axis: wheel.rotationAxis) }
            draw()
        }
    }

    /// Run `draw` with the 3D transform stack moved to a ragdoll limb's fitted
    /// *shape*: its body's pose, then the offset and turn that put the capsule
    /// on the bone. A capsule modeled along +y lands exactly where the solver
    /// thinks the limb is, which is how a figure's collision shapes are drawn
    /// beside the mesh they carry:
    ///
    /// ```swift
    /// for limb in ragdoll.limbs {
    ///     withLimb(limb) {
    ///         if case .capsule(let height, let radius) = limb.collider {
    ///             drawCapsule(height: height, radius: radius)
    ///         }
    ///     }
    /// }
    /// ```
    public func withLimb(_ limb: Ragdoll3D.Limb, _ draw: () -> Void) {
        withBody(limb.body) {
            translate(limb.shapeCenter)
            if abs(limb.shapeAngle) > 1e-9 { rotate(limb.shapeAngle, axis: limb.shapeAxis) }
            draw()
        }
    }

    /// Run `draw` with the 3D transform stack standing in the middle of one of
    /// a rope's segments, turned so that **+y runs along the rope**, which is
    /// the axis Ollin's cylinders, capsules, and cones stand on. So a primitive
    /// drawn inside the block lies along the rope with no turning of its own,
    /// and anything else riding the rope is placed the same way a rigid body is
    /// by `withBody(_:)`:
    ///
    /// ```swift
    /// for segment in vine.segments where segment.index % 3 == 0 {
    ///     withSegment(segment) {
    ///         translate(0, 0, 0.12)
    ///         drawSphere(radius: 0.06)     // a leaf, carried and twisted by the stem
    ///     }
    /// }
    /// ```
    ///
    /// The turn is the rod's own, not one worked out from the neighboring
    /// points, so it carries the rope's twist as well as its bend.
    public func withSegment(_ segment: RopeSegment, _ draw: () -> Void) {
        let q = segment.rotation.normalized
        let w = max(-1, min(1, q.real))
        let angle = 2 * acos(w)
        let s = (1 - w * w).squareRoot()
        withState {
            translate(segment.center)
            if s > 1e-6 {
                rotate(angle, axis: Vector3(q.imag.x / s, q.imag.y / s, q.imag.z / s))
            }
            draw()
        }
    }

    /// Draw a soft body's simulated surface.
    ///
    /// Unlike `withBody(_:)`, which moves the transform stack to a rigid body's
    /// pose and lets the sketch draw whatever it likes there, a soft body *is*
    /// its mesh: the simulation's answer arrives already in world space, so
    /// this draws it where it is, under the current fill, stroke, and material.
    ///
    /// ```swift
    /// fill(.crimson)
    /// material(.dielectric(roughness: 0.6))
    /// drawSoftBody(cloth)
    /// ```
    public func drawSoftBody(_ softBody: SoftBody3D) {
        drawMesh(softBody.mesh)
    }

    /// A hold on one particle of a soft body, from `grabSoftBody(at:in:)`.
    public struct SoftGrip {
        /// The body being held.
        public let body: SoftBody3D
        /// Which of its source mesh's vertices is in hand.
        public let vertex: Int
        /// Whether that particle was already pinned before it was picked up, so
        /// letting go can put it back the way it was.
        let wasPinned: Bool
        /// How deep into the view the grip sits, so dragging moves it in the
        /// plane through that point rather than toward the camera.
        let viewDepth: Double
    }

    /// Take hold of the nearest particle of the soft body under a canvas point.
    /// `nil` when the cursor is not on one.
    ///
    /// A soft body has no single pose to hang a joint from, so a grip is a
    /// *pinned particle* the sketch drives instead. Drag it with
    /// `dragSoftGrab(_:to:)` each frame and `releaseSoftGrab(_:)` to let go:
    ///
    /// ```swift
    /// var grip: SoftGrip?
    /// override func mousePressed() {
    ///     grip = grabSoftBody(at: Vector2(mouseX, mouseY), in: world)
    /// }
    /// override func mouseReleased() {
    ///     if let grip { releaseSoftGrab(grip) }
    ///     grip = nil
    /// }
    /// // in draw():
    /// if let grip { dragSoftGrab(grip, to: Vector2(mouseX, mouseY)) }
    /// ```
    public func grabSoftBody(at canvasPoint: Vector2, in world: World3D) -> SoftGrip? {
        guard let camera = activeCamera,
              let ray = cameraRay(through: canvasPoint, camera: camera) else {
            return nil
        }
        let reach = ray.direction * (camera.far - camera.near)
        let forward = (camera.target - camera.eye).normalized
        if let hit = world.raycast(from: ray.origin, to: ray.origin + reach),
           let soft = hit.body as? SoftBody3D,
           let vertex = soft.nearestVertex(to: hit.point) {
            return SoftGrip(body: soft, vertex: vertex, wasPinned: soft.isPinned(vertex),
                            viewDepth: (hit.point - camera.eye).dot(forward))
        }
        // A rope has no surface for a ray to strike, so nothing above can find
        // one. What the cursor means on a rope is still perfectly clear, so the
        // fallback is to take the nearest particle to the line of sight, within
        // the rope's own thickness of it.
        var best: (rope: Rope3D, vertex: Int, point: Vector3, distance: Double)?
        for rope in world.softBodies.compactMap({ $0 as? Rope3D }) {
            for (index, point) in rope.particlePositions.enumerated() {
                let along = (point - ray.origin).dot(ray.direction)
                guard along > 0 else { continue }
                let distance = (point - (ray.origin + ray.direction * along)).length
                guard distance <= max(rope.thickness, 1e-6) * 3 else { continue }
                if best == nil || along < (best!.point - ray.origin).dot(ray.direction) {
                    best = (rope, index, point, distance)
                }
            }
        }
        guard let best else { return nil }
        return SoftGrip(body: best.rope, vertex: best.vertex,
                        wasPinned: best.rope.isPinned(best.vertex),
                        viewDepth: (best.point - camera.eye).dot(forward))
    }

    /// Drag a soft-body grip toward a canvas point, keeping the particle at the
    /// view depth where it was picked up.
    public func dragSoftGrab(_ grip: SoftGrip, to canvasPoint: Vector2) {
        guard let camera = activeCamera,
              let ray = cameraRay(through: canvasPoint, camera: camera) else {
            return
        }
        let forward = (camera.target - camera.eye).normalized
        let along = ray.direction.dot(forward)
        guard along > 1e-6 else { return }
        grip.body.move(grip.vertex, to: ray.origin + ray.direction * (grip.viewDepth / along))
    }

    /// Let go of a soft-body grip. A particle that was free before it was picked
    /// up is handed back to the simulation; one that was already pinned stays
    /// pinned where the drag left it.
    public func releaseSoftGrab(_ grip: SoftGrip) {
        if !grip.wasPinned { grip.body.unpin(grip.vertex) }
    }

    /// The dynamic body under a canvas point, seen through the active camera,
    /// with the world point where the ray touched it. `nil` when nothing is
    /// there (or no camera is active). Use it to probe; use
    /// `grabBody(at:in:)` to pick up.
    public func body(under canvasPoint: Vector2, in world: World3D)
        -> (body: Body3D, point: Vector3)? {
        guard let camera = activeCamera,
              let ray = cameraRay(through: canvasPoint, camera: camera) else {
            return nil
        }
        let reach = ray.direction * (camera.far - camera.near)
        // The ray sees everything the world holds, the ones kept out of
        // `bodies` included (a ragdoll's limbs, a character's stand-in, the
        // ground slab). A cloth in front of a crate answers for the crate: it
        // is what the cursor is on, and `grabSoftBody(at:in:)` is what takes
        // hold of one.
        guard let hit = world.raycast(from: ray.origin, to: ray.origin + reach),
              let body = hit.body as? Body3D else {
            return nil
        }
        return (body, hit.point)
    }

    /// Grab the body under a canvas point (through the active camera) and
    /// return the grab joint, or `nil` when the cursor isn't on a body. Drag
    /// with `dragGrab(_:to:)` each frame and `remove()` the joint to let go:
    ///
    /// ```swift
    /// var grabbed: Joint3D?
    /// override func mousePressed() {
    ///     grabbed = grabBody(at: Vector2(mouseX, mouseY), in: world)
    /// }
    /// override func mouseReleased() {
    ///     grabbed?.remove()
    ///     grabbed = nil
    /// }
    /// // in draw():
    /// if let grabbed { dragGrab(grabbed, to: Vector2(mouseX, mouseY)) }
    /// ```
    public func grabBody(at canvasPoint: Vector2, in world: World3D) -> Joint3D? {
        guard let camera = activeCamera,
              let hit = body(under: canvasPoint, in: world),
              hit.body.kind == .dynamic else {
            return nil
        }
        let joint = world.grab(hit.body, at: hit.point)
        // Remember how deep into the view the grip sits, so dragging moves the
        // body in the screen-parallel plane through the grab point.
        let forward = (camera.target - camera.eye).normalized
        joint.grabViewDepth = (hit.point - camera.eye).dot(forward)
        return joint
    }

    /// Drag a grab joint (from `grabBody(at:in:)`) toward a canvas point,
    /// keeping the body at the view depth where it was grabbed.
    public func dragGrab(_ joint: Joint3D, to canvasPoint: Vector2) {
        guard let camera = activeCamera, let depth = joint.grabViewDepth,
              let ray = cameraRay(through: canvasPoint, camera: camera) else {
            return
        }
        let forward = (camera.target - camera.eye).normalized
        let along = ray.direction.dot(forward)
        guard along > 1e-6 else { return }
        joint.target = ray.origin + ray.direction * (depth / along)
    }

    /// The world-space ray from the camera through a canvas point (unit
    /// direction). `nil` for a depth-feed (intrinsics) projection.
    private func cameraRay(through canvasPoint: Vector2, camera: Camera3D)
        -> (origin: Vector3, direction: Vector3)? {
        guard width > 0, height > 0 else { return nil }
        let ndcX = 2 * (canvasPoint.x / width) - 1
        let ndcY = 1 - 2 * (canvasPoint.y / height)
        let aspect = width / height
        let forward = (camera.target - camera.eye).normalized
        let right = forward.cross(camera.up).normalized
        let up = right.cross(forward)

        switch camera.projection {
        case .perspective(let fieldOfView):
            let tanHalf = tan(fieldOfView / 2)
            let direction = (forward
                + right * (ndcX * tanHalf * aspect)
                + up * (ndcY * tanHalf)).normalized
            return (camera.eye, direction)
        case .orthographic(let frameHeight):
            let origin = camera.eye
                + right * (ndcX * frameHeight / 2 * aspect)
                + up * (ndcY * frameHeight / 2)
            return (origin, forward)
        default:
            return nil
        }
    }
}
