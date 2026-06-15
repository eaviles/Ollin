import Foundation
import Ollin
import OllinVision

/// A live 3D point cloud from one plain webcam — the Mac-side preview of the
/// iPhone-LiDAR cloud to come.
///
/// The Mac has no depth sensor, so a `ModelTracker` estimates depth from the
/// camera with a neural model. Each cell of a sampling grid becomes a 3D point —
/// placed in z by its depth, colored by the camera image — and the whole cloud
/// orbits so the estimated depth reads as real space. Setting a `camera` is what
/// makes the frame 3D; drag left/right to spin the cloud yourself.
///
/// The model weights aren't in the repo — run `Scripts/fetch-models.sh` once and
/// relaunch (the sketch says so on the canvas until then).
///
/// Model: Depth Anything V2 (small) — Apple's official Core ML conversion,
/// Apache-2.0. Lihe Yang et al., "Depth Anything V2" (2024),
/// https://huggingface.co/apple/coreml-depth-anything-v2-small — downloaded by
/// the fetch script, never bundled.
@main
final class DepthCloud: Sketch {
    static let modelPath = "Models/DepthAnythingV2SmallF16.mlpackage"

    let camera = Camera()
    lazy var depth = ModelTracker(camera, modelAt: URL(fileURLWithPath: Self.modelPath))

    override func setup() { try? camera.start() }

    override func draw() {
        background(Color(white: 0.03))

        guard FileManager.default.fileExists(atPath: Self.modelPath) else {
            return drawStatus("The depth model isn't downloaded yet.\n" +
                              "Run Scripts/fetch-models.sh, then relaunch.", style: .warning)
        }
        guard let frame = camera.frame else {
            return drawStatus("Waiting for camera…")
        }
        if let reason = depth.unavailableReason { return drawStatus(reason, style: .warning) }
        if !depth.isLoaded {
            return drawStatus("Loading the depth model…\n" +
                              "The first run prepares it for this Mac; after that it starts instantly.")
        }

        // Sample the depth map and the camera image over a normalized grid, lifting
        // each cell into a 3D point: screen x/y across the plane, depth into z.
        let canvas = Rectangle(x: 0, y: 0, width: width, height: height)
        let cols = 96
        let imgAspect = Double(frame.width) / Double(max(1, frame.height))
        let rows = max(1, Int(Double(cols) / imgAspect))
        let worldW = 4.0, worldH = worldW / imgAspect

        var cloud = PointCloud()
        cloud.points.reserveCapacity(cols * rows)
        for j in 0..<rows {
            let v = (Double(j) + 0.5) / Double(rows)
            let py = min(frame.height - 1, Int(v * Double(frame.height)))
            for i in 0..<cols {
                let u = (Double(i) + 0.5) / Double(cols)
                let near = depth.value(at: Vector2(u * width, v * height), in: canvas)  // 0 far … 1 near
                let px = min(frame.width - 1, Int(u * Double(frame.width)))
                let world = Vector3((u - 0.5) * worldW, -(v - 0.5) * worldH, (near - 0.5) * 1.7)
                cloud.add(world, color: frame[px, py], size: worldW / Double(cols) * 1.5)
            }
        }

        // Orbit gently so the depth reads as space; drag left/right to spin it.
        let azimuth = mouseIsPressed ? map(mouseX, 0, width, .pi, -.pi) : sin(time * 0.4) * 0.6
        camera(.orbiting(target: .zero, radius: 4.4, azimuth: azimuth,
                         elevation: 0.1, fieldOfView: .pi / 3.2))
        drawPointCloud(cloud)

        drawCaption("DepthCloud — a live 3D point cloud from one webcam; drag to orbit")
    }
}
