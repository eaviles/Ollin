@testable import Ollin
import Testing
import simd

/// Pure CPU checks on `Camera3D`'s view/projection math — the look-at frame, the
/// perspective and orthographic clip mappings (Metal's z ∈ [0, 1]), aspect
/// scaling, and the orbit helper. No Metal device, so these run everywhere
/// including CI.
@Suite
struct Camera3DTests {

    private func close(_ a: Float, _ b: Float, _ eps: Float = 1e-4) -> Bool {
        abs(a - b) <= eps
    }

    /// The view matrix takes the eye to the origin and the target onto the −z
    /// axis at minus the eye→target distance (camera looks down −z).
    @Test func viewMatrixFrame() {
        let cam = Camera3D(eye: Vector3(3, 4, 12), target: Vector3(0, 1, 0))
        let v = cam.viewMatrix

        let eye = v * SIMD4<Float>(3, 4, 12, 1)
        #expect(close(eye.x, 0))
        #expect(close(eye.y, 0))
        #expect(close(eye.z, 0))
        #expect(close(eye.w, 1))

        let d = Float(cam.eye.distance(to: cam.target))
        let target = v * SIMD4<Float>(0, 1, 0, 1)
        #expect(close(target.x, 0))
        #expect(close(target.y, 0))
        #expect(close(target.z, -d))
    }

    /// A point at the camera target projects to the center of the screen (NDC
    /// origin), under both projections.
    @Test func targetProjectsToCenter() {
        for projection: Camera3D.Projection in [.perspective(fieldOfView: .pi / 3),
                                                .orthographic(height: 6)] {
            let cam = Camera3D(eye: Vector3(2, 3, 8), target: Vector3(-1, 0.5, 1),
                               projection: projection)
            let clip = cam.viewProjectionMatrix(aspect: 16.0 / 9.0) * SIMD4<Float>(-1, 0.5, 1, 1)
            #expect(close(clip.x / clip.w, 0))
            #expect(close(clip.y / clip.w, 0))
        }
    }

    /// Perspective maps the near plane to NDC z = 0 and the far plane to z = 1
    /// (Metal's clip range). Camera-space points lie down −z.
    @Test func perspectiveDepthRange() {
        let p = Camera3D.perspective(fovY: .pi / 3, aspect: 1, near: 0.5, far: 50)
        let near = p * SIMD4<Float>(0, 0, -0.5, 1)
        let far  = p * SIMD4<Float>(0, 0, -50, 1)
        #expect(close(near.z / near.w, 0))
        #expect(close(far.z / far.w, 1))
    }

    /// Orthographic maps the near/far planes the same way, with no perspective
    /// divide (w stays 1), and frames `height` units top-to-bottom.
    @Test func orthographicMapping() {
        let p = Camera3D.orthographic(height: 4, aspect: 1, near: 0.5, far: 50)
        let near = p * SIMD4<Float>(0, 0, -0.5, 1)
        let far  = p * SIMD4<Float>(0, 0, -50, 1)
        #expect(close(near.w, 1))
        #expect(close(near.z, 0))
        #expect(close(far.z, 1))

        // The top edge of the frame (height/2 up at the target plane) is NDC y = 1.
        let cam = Camera3D.orthographic(eye: Vector3(0, 0, 10), target: .zero, height: 4)
        let top = cam.viewProjectionMatrix(aspect: 1) * SIMD4<Float>(0, 2, 0, 1)
        #expect(close(top.y / top.w, 1))
    }

    /// A wider aspect ratio compresses the x axis (the same horizontal angle
    /// covers more screen), so the projection's x scale shrinks.
    @Test func aspectScalesX() {
        let wide = Camera3D.perspective(fovY: .pi / 3, aspect: 2, near: 0.1, far: 100)
        let square = Camera3D.perspective(fovY: .pi / 3, aspect: 1, near: 0.1, far: 100)
        #expect(wide.columns.0.x < square.columns.0.x)
        // The y scale (set by the field of view) is unchanged by aspect.
        #expect(close(wide.columns.1.y, square.columns.1.y))
    }

    /// The orbit helper places the eye on a sphere around the target: azimuth 0
    /// and elevation 0 looks from +z, and the radius is the eye→target distance.
    @Test func orbiting() {
        let cam = Camera3D.orbiting(target: .zero, radius: 5)
        #expect(close(Float(cam.eye.x), 0))
        #expect(close(Float(cam.eye.y), 0))
        #expect(close(Float(cam.eye.z), 5))
        #expect(close(Float(cam.eye.distance(to: cam.target)), 5))

        // A quarter turn of azimuth swings the eye onto the +x side.
        let side = Camera3D.orbiting(target: .zero, radius: 5, azimuth: .pi / 2)
        #expect(close(Float(side.eye.x), 5))
        #expect(close(Float(side.eye.z), 0, 1e-3))
    }
}
