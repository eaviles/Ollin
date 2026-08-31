import Foundation
import Ollin
import OllinVision
import OllinRecord3D

/// Depth-aware compositing against a live depth feed: 2D suspended *in the
/// room* and hidden by whatever is nearer. Two feeds share the one idea, and
/// **M** switches between them: a webcam plane hung at a normalized 0...1
/// depth, and a tethered iPhone's LiDAR feed measured in real meters.
///
/// The Mac has no depth camera, so by default a `ModelTracker` estimates depth
/// from one plain webcam. `drawDepthScene` draws that camera frame as the
/// backdrop *and* writes its depth map into the depth buffer, so anything
/// drawn afterward at a normalized `depth(_:)` is occluded by the scene: a
/// field of discs hung at a depth plane is hidden where you (nearer) pass in
/// front of them, and shows where the wall behind is farther. Drag up and down
/// to move the plane toward and away from the camera.
///
/// The metric mode swaps estimation for measurement.
/// `camera(.intrinsic(frame.intrinsics))` makes a metric camera from the
/// stream's own calibration, and `drawDepthScene(frame)` lays down the color
/// picture and writes the frame's metric depth (meters) into the depth buffer.
/// So a marker placed at a world point a fixed number of meters away
/// (`withBillboard(at:)` puts it there with correct occlusion) is hidden the
/// instant something nearer than that distance passes in front of it. Drag up
/// and down to push the plane of markers from 0.3 m to 3 m; walk toward the
/// camera and you cross each marker's distance and start blocking it. The feed
/// is letterboxed into the canvas by its own aspect (no stretch, whatever the
/// phone's orientation), and the metric camera letterboxes to match, so the
/// markers always land on the picture. Setup: open **Record3D** on a LiDAR
/// iPhone, enable **USB streaming** in its Settings, keep it on the live
/// screen, and connect the cable; the connection retries on its own.
///
/// The model weights aren't in the repo: run `Scripts/fetch-models.sh` once
/// and relaunch (the sketch says so on the canvas until then).
///
/// Model: Depth Anything V2 (small), Apple's official Core ML conversion,
/// Apache-2.0. Lihe Yang et al., "Depth Anything V2" (2024),
/// https://huggingface.co/apple/coreml-depth-anything-v2-small, downloaded by
/// the fetch script, never bundled. Record3D is by Marek Šimoník
/// (record3d.app), credited as the capture app and the source of the stream
/// format, read clean-room from its public structure.
/// The fetched weights live in `Models/` at the repo root. This sketch runs both
/// from there (the gallery compiles it where it sits) and from `Examples/` (a
/// direct `swift run`), so the folder is found by walking up from this file
/// instead of trusting whatever the working directory happens to be.
private func modelsPath(_ name: String) -> String {
    sketchResource(name) ?? ("Models" as NSString).appendingPathComponent(name)
}

@main
final class DepthOcclusion: Sketch {
    static let modelPath = modelsPath("DepthAnythingV2SmallF16.mlpackage")

    let camera = Camera()
    lazy var depth = ModelTracker(camera, modelAt: URL(fileURLWithPath: Self.modelPath))

    /// The metric feed: a tethered iPhone streaming RGBD over USB.
    let device = Record3DDevice()
    /// True while the metric (meters) mode is on; **M** toggles it.
    var metric = false
    /// The metric marker plane's distance in meters, eased so it glides as you drag.
    var planeMeters = 1.0

    override func setup() {
        try? camera.start()
        device.start()
    }

    override func keyPressed() {
        if key == "m" || key == "M" { metric.toggle() }
    }

    override func draw() {
        background(Color(white: 0.03))
        if metric {
            drawMetric()
        } else {
            drawNormalized()
        }
    }

    // MARK: - The normalized plane (webcam, estimated depth)

    func drawNormalized() {
        guard FileManager.default.fileExists(atPath: Self.modelPath) else {
            return drawStatus("The depth model isn't downloaded yet.\n" +
                              "Run Scripts/fetch-models.sh, then relaunch.", style: .warning)
        }
        guard let frame = camera.frame else { return drawStatus("Waiting for camera…") }
        if let reason = depth.unavailableReason { return drawStatus(reason, style: .warning) }
        if !depth.isLoaded {
            return drawStatus("Loading the depth model…\n" +
                              "The first run prepares it for this Mac; after that it starts instantly.")
        }

        guard let rect = camera.fittedRectangle(in: canvasRectangle) else { return }

        // Reading `map` arms it and returns the latest depth map (white = nearest);
        // until the first one lands, just show the camera.
        guard let depthMap = depth.map else {
            drawImage(frame, in: rect)
            return drawCaption("DepthOcclusion: estimating depth…")
        }

        // The backdrop is the frame the depth map was *computed from* (not the live
        // one), so the camera image and the depth mask are from the same instant and
        // the discs carve exactly around you; the whole picture lags by the
        // inference latency (~1 frame in a release build) instead of the mask
        // trailing the live image. Falls back to the live frame until the first
        // analyzed one lands. The depth map is primed into the depth buffer here.
        drawDepthScene(color: depth.sourceFrame ?? frame, depth: depthMap, in: rect)

        // The depth plane: drag up/down to move it toward (near) or away (far). The
        // discs hang at this depth, so you hide the ones you stand in front of.
        let plane = mouseIsPressed ? map(mouseY, 0, height, 0.05, 0.95) : 0.5
        depth(plane)

        // A field of discs suspended at the plane. Each is a 2D mark, occluded by
        // anything the depth scene placed nearer.
        noStroke()
        let cols = 9, rows = 6
        for j in 0..<rows {
            for i in 0..<cols {
                let x = rect.x + rect.width * (Double(i) + 0.5) / Double(cols)
                let y = rect.y + rect.height * (Double(j) + 0.5) / Double(rows)
                let hue = (Double(i) / Double(cols) + Double(j) / Double(rows) * 0.5 + time * 0.05)
                    .truncatingRemainder(dividingBy: 1)
                let r = rect.width / Double(cols) * (0.22 + 0.06 * sin(time * 2 + Double(i + j)))
                fill(Color(hue: hue, saturation: 0.7, brightness: 1.0, alpha: 0.92))
                drawCircle(x, y, r)
            }
        }

        // A HUD over everything (no depth), the default for 2D in a depth frame.
        drawCaption("DepthOcclusion: discs hung in the room; drag up/down to move their depth, " +
                    "lean in to hide them. M for meters")
    }

    // MARK: - The metric plane (LiDAR feed, real meters)

    func drawMetric() {
        guard let frame = device.latestFrame else {
            return drawStatus(device.waitingMessage + "\n\n" +
                              "Open Record3D on the iPhone, enable USB streaming in Settings,\n" +
                              "keep it on the live screen, and connect the cable.\n" +
                              "M returns to the webcam plane.", style: .info)
        }

        // A metric camera from the feed's own intrinsics: a point cloud, a depth
        // scene, and any placed object now share one space measured in meters.
        camera(.intrinsic(frame.intrinsics))

        // The backdrop picture + the frame's metric depth, written into the depth
        // buffer. Fills the canvas (the camera projects the scene across the canvas).
        drawDepthScene(frame)

        // Drag up/down to set the plane distance (0.3 m near … 3 m far), eased.
        let target = mouseIsPressed ? map(mouseY, 0, height, 0.3, 3.0) : planeMeters
        planeMeters += (target - planeMeters) * 0.15

        // A grid of markers, each placed at a screen position unprojected to the
        // plane's metric depth, so it sits exactly under that pixel, `planeMeters`
        // away. `withBillboard` lands it there with metric occlusion: hidden wherever
        // the depth scene wrote something nearer than the plane.
        let k = frame.intrinsics
        let cols = 5, rows = 4
        noStroke()
        for j in 0..<rows {
            for i in 0..<cols {
                let col = Double(k.width) * (Double(i) + 0.5) / Double(cols)
                let row = Double(k.height) * (Double(j) + 0.5) / Double(rows)
                let world = k.unproject(col: col, row: row, depth: planeMeters)
                withBillboard(at: world) {
                    let hue = (Double(i) / Double(cols) + Double(j) / Double(rows) * 0.5
                               + time * 0.05).truncatingRemainder(dividingBy: 1)
                    fill(Color(hue: hue, saturation: 0.7, brightness: 1.0, alpha: 0.92))
                    drawCircle(0, 0, 26)
                    fill(Color(white: 0.05))
                    drawCircle(0, 0, 9)
                }
            }
        }

        drawCaption(String(format: "DepthOcclusion: markers at %.2f m; drag to move the plane, " +
                           "step closer to block them. M for the webcam plane", planeMeters))
    }
}
