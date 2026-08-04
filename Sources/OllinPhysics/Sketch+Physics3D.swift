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
        var hitBody: CJoltBodyID = CJOLT_BODY_INVALID
        var fraction: Float = 0
        var hit = false
        withFloats3(world.meters(from: ray.origin)) { op in
            withFloats3(world.meters(from: reach)) { dp in
                hit = cjolt_world_ray_cast(world.handle, op, dp, &hitBody, &fraction)
            }
        }
        guard hit, let body = world.bodies.first(where: { $0.id == hitBody }) else {
            return nil
        }
        let point = ray.origin + reach * Double(fraction)
        return (body, point)
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
