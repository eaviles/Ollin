import Foundation
import simd

/// A camera for 3D drawing: an eye looking at a target, plus how it flattens
/// space onto the canvas (perspective or orthographic).
///
/// 2D is Ollin's default, and a 2D sketch never makes one of these. Setting a
/// camera — `camera(...)`, `perspective(...)`, or `ortho(...)` on a `Sketch` —
/// is what puts a frame into 3D: the renderer then allocates a depth buffer and
/// draws 3D geometry (a point cloud today) through this camera's view and
/// projection. Omit the camera and nothing changes; the 2D path is untouched.
///
/// World space is right-handed with **y up**: x runs right, y up, and the camera
/// looks down its local −z. Distances are in world units — whatever the geometry
/// uses (meters for a depth cloud, say). This is a different convention from the
/// 2D canvas (top-left origin, y-down, points); 3D geometry lives in its own
/// world space and reaches the screen through the camera, not the 2D mapping.
public struct Camera3D: Equatable, Sendable {

    /// How the camera flattens space onto the canvas.
    public enum Projection: Equatable, Sendable {
        /// Perspective: nearer is bigger, framed by a vertical field of view in
        /// radians (the full top-to-bottom angle).
        case perspective(fieldOfView: Double)
        /// Orthographic: no foreshortening, framing `height` world units tall.
        case orthographic(height: Double)
        /// A real camera's pinhole calibration: an off-axis perspective frustum
        /// built straight from `CameraIntrinsics` (focal length and principal
        /// point), so a depth feed's own lens drives the projection. This is what
        /// lets a drawn point cloud and a depth scene share one *metric* space — a
        /// point made by `CameraIntrinsics.unproject` reprojects to its own pixel.
        /// The intrinsics carry the image size and aspect, so the viewport aspect is
        /// ignored for this case. Build it with `Camera3D.fromIntrinsics(_:)`.
        case intrinsic(CameraIntrinsics)
    }

    /// The camera position — where you look *from*.
    public var eye: Vector3
    /// The point the camera looks *at*.
    public var target: Vector3
    /// Which way is up for the camera (usually `.unitY`).
    public var up: Vector3
    /// The near clip distance; geometry nearer than this is cut away. Must be > 0
    /// for a perspective camera.
    public var near: Double
    /// The far clip distance; geometry beyond this is cut away.
    public var far: Double
    /// Perspective or orthographic, with its parameter.
    public var projection: Projection

    /// The thin-lens aperture radius in world units, read by the path-traced export
    /// (`--path-traced`) for real depth of field: 0 (the default) is a pinhole and
    /// everything is sharp; larger values blur away from the focus plane. The live
    /// raster view ignores it (screen-space defocus stays the live-preview blur).
    public var aperture: Double = 0
    /// The distance from the camera at which the path-traced export focuses, along
    /// the view axis. `nil` (the default) focuses on the `target`, so an orbiting
    /// camera keeps its subject sharp with no extra bookkeeping.
    public var focusDistance: Double? = nil

    /// How far this camera has already stepped sideways off the center line of a
    /// stereo pair, in world units, and the distance at which the two eyes agree.
    /// Zero for every ordinary camera, which is what leaves the projection of one
    /// untouched. Set by `stereoEye(lateral:convergence:)`; see `Stereo.swift`.
    var stereoLateral: Double = 0
    var stereoConvergence: Double = 1

    public init(eye: Vector3, target: Vector3, up: Vector3 = .unitY,
                near: Double = 0.1, far: Double = 1000,
                projection: Projection = .perspective(fieldOfView: .pi / 3)) {
        self.eye = eye
        self.target = target
        self.up = up
        self.near = near
        self.far = far
        self.projection = projection
    }
}

public extension Camera3D {
    /// A perspective camera at `eye` looking at `target`.
    static func perspective(eye: Vector3, target: Vector3 = .zero, up: Vector3 = .unitY,
                            fieldOfView: Double = .pi / 3,
                            near: Double = 0.1, far: Double = 1000) -> Camera3D {
        Camera3D(eye: eye, target: target, up: up, near: near, far: far,
                 projection: .perspective(fieldOfView: fieldOfView))
    }

    /// An orthographic camera at `eye` looking at `target`, framing `height`
    /// world units from top to bottom.
    static func orthographic(eye: Vector3, target: Vector3 = .zero, up: Vector3 = .unitY,
                             height: Double, near: Double = 0.1, far: Double = 1000) -> Camera3D {
        Camera3D(eye: eye, target: target, up: up, near: near, far: far,
                 projection: .orthographic(height: height))
    }

    /// A camera built from a depth frame's pinhole `intrinsics`, placed at the
    /// origin looking down −z — exactly where `CameraIntrinsics.unproject` puts the
    /// points it lifts. So a point cloud unprojected from the frame, a 2D mark
    /// placed with `depth(at:)`, and a metric `drawDepthScene` all share one metric
    /// world space (meters), and an object placed at true world coordinates lands
    /// inside the depth feed with correct occlusion.
    ///
    /// `near`/`far` are the metric clip range in meters — the depth scene maps its
    /// metric depth into the same range, so keep them spanning the scene's depths
    /// (the defaults, 1 cm … 100 m, cover an indoor LiDAR feed). Move `eye`/`target`
    /// afterward to orbit a *drawn* cloud; the default pose is the one that aligns
    /// with a depth-scene backdrop.
    static func fromIntrinsics(_ intrinsics: CameraIntrinsics,
                               near: Double = 0.01, far: Double = 100) -> Camera3D {
        Camera3D(eye: .zero, target: Vector3(0, 0, -1), up: .unitY,
                 near: near, far: far, projection: .intrinsic(intrinsics))
    }

    /// A perspective camera orbiting `target` on a sphere of `radius`, at
    /// `azimuth` (turn around the up axis, 0 looking down +z) and `elevation`
    /// (tilt above the horizontal), both in radians. The easy way to spin a
    /// camera around a scene from a sketch.
    static func orbiting(target: Vector3 = .zero, radius: Double,
                         azimuth: Double = 0, elevation: Double = 0,
                         fieldOfView: Double = .pi / 3,
                         near: Double = 0.1, far: Double = 1000) -> Camera3D {
        let ce = cos(elevation)
        let eye = target + Vector3(radius * ce * sin(azimuth),
                                   radius * sin(elevation),
                                   radius * ce * cos(azimuth))
        return Camera3D(eye: eye, target: target, up: .unitY,
                        near: near, far: far,
                        projection: .perspective(fieldOfView: fieldOfView))
    }
}

// MARK: - Orbit decomposition (internal; the camera rig seeds from an authored camera)

extension Camera3D {
    /// This camera's pose as the rig's orbit parameters: the target as the
    /// pivot, the eye's offset split into radius / azimuth / elevation, and a
    /// vertical field of view. An orthographic camera maps its frame height to
    /// the equivalent field of view at the target distance, so the rig's
    /// projection toggle holds the scale; an intrinsic one keeps its lens
    /// angle. The rig orbits y-up, so any authored roll is dropped.
    var orbitPose: (target: Vector3, radius: Double, azimuth: Double,
                    elevation: Double, fieldOfView: Double, orthographic: Bool) {
        let offset = eye - target
        let radius = Swift.max(offset.length, 1e-3)
        let elevation = asin(Swift.min(Swift.max(offset.y / radius, -1), 1))
        let azimuth = (offset.x != 0 || offset.z != 0) ? atan2(offset.x, offset.z) : 0
        switch projection {
        case .perspective(let fov):
            return (target, radius, azimuth, elevation, fov, false)
        case .orthographic(let height):
            // The field of view that frames `height` at the target distance,
            // so the seeded pose shows the extent the authored camera did.
            let fov = 2 * atan(Swift.max(height, 1e-6) / (2 * radius))
            return (target, radius, azimuth, elevation, fov, true)
        case .intrinsic(let k):
            let fov = k.height > 0 && k.fy > 0
                ? 2 * atan(Double(k.height) / (2 * k.fy)) : .pi / 3
            return (target, radius, azimuth, elevation, fov, false)
        }
    }
}

// MARK: - Matrices (internal — the renderer consumes these; sketches set the camera)

extension Camera3D {
    /// The view matrix (world → camera space), column-major for Metal.
    var viewMatrix: simd_float4x4 {
        Camera3D.lookAt(eye: eye.simd3, center: target.simd3, up: up.simd3)
    }

    /// The projection matrix (camera → clip space) for the given viewport
    /// `aspect` ratio (width ÷ height), column-major, with Metal's clip-space
    /// z ∈ [0, 1].
    ///
    /// An eye of a stereo pair carries one extra term. Having stepped sideways by
    /// `stereoLateral`, it must lean back in so both eyes agree at
    /// `stereoConvergence`, and the lean is a single entry: `[2][0]`, the term that
    /// mixes view-space z into clip-space x. That one entry covers all three
    /// projections, for two reasons that meet in the same place. A perspective (or
    /// intrinsic) frustum's clip w is the view distance, so premultiplying a
    /// constant shift of the flattened image lands entirely in `[2][0]`, which is
    /// exactly the asymmetric frustum a parallel stereo rig is defined by. An
    /// orthographic camera has no such w, and moving it sideways slides the whole
    /// image with no parallax at all, so what it needs is a shear: disparity
    /// proportional to depth. That is the same entry, and working the convergence
    /// condition through gives it the same value.
    func projectionMatrix(aspect: Double) -> simd_float4x4 {
        var m = symmetricProjectionMatrix(aspect: aspect)
        guard stereoLateral != 0, stereoConvergence > 0 else { return m }
        m.columns.2.x -= Float(Double(m.columns.0.x) * stereoLateral / stereoConvergence)
        return m
    }

    /// The projection this camera would have were it not one eye of a pair.
    private func symmetricProjectionMatrix(aspect: Double) -> simd_float4x4 {
        let a = Float(aspect <= 0 ? 1 : aspect)
        switch projection {
        case .perspective(let fov):
            return Camera3D.perspective(fovY: Float(fov), aspect: a,
                                        near: Float(near), far: Float(far))
        case .orthographic(let height):
            return Camera3D.orthographic(height: Float(height), aspect: a,
                                         near: Float(near), far: Float(far))
        case .intrinsic(let k):
            // The off-axis frustum maps the full image to full NDC. Letterbox that
            // into the viewport so the picture isn't stretched when the canvas aspect
            // differs from the image's — pillarbox (shrink x) when the viewport is
            // wider than the image, letterbox (shrink y) when it's taller. This is the
            // same fit `drawDepthScene(_ frame:)` draws the backdrop into, so backdrop
            // and projected geometry stay aligned. The z/w rows are untouched, so
            // metric depth stays exact.
            var m = Camera3D.perspective(intrinsics: k, near: Float(near), far: Float(far))
            if k.width > 0, k.height > 0, a > 0 {
                let imageAspect = Float(k.width) / Float(k.height)
                var sx: Float = 1, sy: Float = 1
                if a > imageAspect { sx = imageAspect / a } else { sy = a / imageAspect }
                m.columns.0.x *= sx; m.columns.2.x *= sx
                m.columns.1.y *= sy; m.columns.2.y *= sy
            }
            return m
        }
    }

    /// `projection · view` for the given viewport aspect — multiply a world-space
    /// point (as a `float4` with w = 1) by this to land it in clip space.
    func viewProjectionMatrix(aspect: Double) -> simd_float4x4 {
        projectionMatrix(aspect: aspect) * viewMatrix
    }

    /// Right-handed look-at: world → camera space, camera looking down −z.
    /// Column-major (Metal). Written from the standard formula.
    static func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let z = simd_normalize(eye - center)        // +z points back toward the eye
        let x = simd_normalize(simd_cross(up, z))   // camera right
        let y = simd_cross(z, x)                     // camera up (re-orthogonalized)
        return simd_float4x4(columns: (
            SIMD4<Float>(x.x, y.x, z.x, 0),
            SIMD4<Float>(x.y, y.y, z.y, 0),
            SIMD4<Float>(x.z, y.z, z.z, 0),
            SIMD4<Float>(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye), 1)
        ))
    }

    /// Right-handed perspective with Metal's z ∈ [0, 1] clip range (near → 0,
    /// far → 1). `fovY` is the full vertical field of view in radians.
    static func perspective(fovY: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let f = 1 / tan(fovY / 2)
        let zRange = near - far
        return simd_float4x4(columns: (
            SIMD4<Float>(f / aspect, 0, 0, 0),
            SIMD4<Float>(0, f, 0, 0),
            SIMD4<Float>(0, 0, far / zRange, -1),
            SIMD4<Float>(0, 0, (near * far) / zRange, 0)
        ))
    }

    /// Right-handed off-axis perspective built from a pinhole camera's intrinsics,
    /// with Metal's z ∈ [0, 1] clip range (near → 0, far → 1). The principal point
    /// (`cx`, `cy`) need not be centered, and `fx`/`fy` may differ — so the frustum
    /// is asymmetric, matching the lens the depth was captured with.
    ///
    /// Derived from `CameraIntrinsics.unproject`'s exact convention (top-left pixel
    /// origin, camera looking down −z, so metric depth maps to −z): a camera-space
    /// point projects back to the pixel it came from, and NDC spans the full image
    /// (col 0…W → x −1…1, row 0…H → y +1…−1). It collapses to the symmetric
    /// `perspective(fovY:...)` when `cx = W/2`, `cy = H/2`, `fx = fy`.
    static func perspective(intrinsics k: CameraIntrinsics, near: Float, far: Float) -> simd_float4x4 {
        let w = Float(k.width), h = Float(k.height)
        guard w > 0, h > 0 else { return matrix_identity_float4x4 }
        let fx = Float(k.fx), fy = Float(k.fy), cx = Float(k.cx), cy = Float(k.cy)
        let zRange = near - far
        // clip.x = (2fx/W)·X + (1 − 2cx/W)·Z   clip.y = (2fy/H)·Y + (2cy/H − 1)·Z
        // clip.z = far/zRange·Z + near·far/zRange   clip.w = −Z   (w = metric depth)
        return simd_float4x4(columns: (
            SIMD4<Float>(2 * fx / w, 0, 0, 0),
            SIMD4<Float>(0, 2 * fy / h, 0, 0),
            SIMD4<Float>(1 - 2 * cx / w, 2 * cy / h - 1, far / zRange, -1),
            SIMD4<Float>(0, 0, (near * far) / zRange, 0)
        ))
    }

    /// Right-handed orthographic with Metal's z ∈ [0, 1] clip range, centered,
    /// framing `height` world units tall and `height · aspect` wide.
    static func orthographic(height: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let w = height * aspect
        let zRange = near - far
        return simd_float4x4(columns: (
            SIMD4<Float>(2 / w, 0, 0, 0),
            SIMD4<Float>(0, 2 / height, 0, 0),
            SIMD4<Float>(0, 0, 1 / zRange, 0),
            SIMD4<Float>(0, 0, near / zRange, 1)
        ))
    }
}

extension Vector3 {
    /// This vector as a single-precision SIMD triple (for the GPU/matrix side).
    var simd3: SIMD3<Float> { SIMD3<Float>(Float(x), Float(y), Float(z)) }
}
