import Foundation
import Ollin
import OllinVision

/// Depth-aware compositing against a live depth feed — 2D suspended *in the room*
/// and hidden by whatever is nearer.
///
/// The Mac has no depth camera, so a `ModelTracker` estimates depth from one plain
/// webcam. `drawDepthScene` draws that camera frame as the backdrop *and* writes
/// its depth map into the depth buffer, so anything drawn afterward at a normalized
/// `depth(_:)` is occluded by the scene: a field of discs hung at a depth plane is
/// hidden where you (nearer) pass in front of them, and shows where the wall behind
/// is farther. Drag up and down to move the plane toward and away from the camera.
///
/// The model weights aren't in the repo — run `Scripts/fetch-models.sh` once and
/// relaunch (the sketch says so on the canvas until then).
///
/// Model: Depth Anything V2 (small) — Apple's official Core ML conversion,
/// Apache-2.0. Lihe Yang et al., "Depth Anything V2" (2024),
/// https://huggingface.co/apple/coreml-depth-anything-v2-small — downloaded by the
/// fetch script, never bundled.
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

    override func setup() { try? camera.start() }

    override func draw() {
        background(Color(white: 0.03))

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

        guard let rect = camera.fittedRect(in: canvasRectangle) else { return }

        // Reading `map` arms it and returns the latest depth map (white = nearest);
        // until the first one lands, just show the camera.
        guard let depthMap = depth.map else {
            drawImage(frame, in: rect)
            return drawCaption("DepthOcclusion — estimating depth…")
        }

        // The backdrop is the frame the depth map was *computed from* (not the live
        // one), so the camera image and the depth mask are from the same instant and
        // the discs carve exactly around you — the whole picture lags by the
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

        // A HUD over everything (no depth) — the default for 2D in a depth frame.
        drawCaption("DepthOcclusion — discs hung in the room; drag up/down to move their depth, lean in to hide them")
    }
}
