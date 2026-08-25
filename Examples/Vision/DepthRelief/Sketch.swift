import Foundation
import Ollin
import OllinVision

/// Depth from a plain webcam, painted as relief: a `ModelTracker` runs a
/// monocular depth model over the live feed, and a grid of disks reads the map
/// through `value(at:in:)` — nearer is bigger and warmer, farther smaller and
/// cooler. The Mac has no depth sensor; a neural model estimates one from any
/// camera. The model weights aren't in the repo — run `Scripts/fetch-models.sh`
/// once and relaunch (the sketch says so on the canvas until then).
///
/// Model: Depth Anything V2 (small) — Apple's official Core ML conversion,
/// Apache-2.0. Lihe Yang et al., "Depth Anything V2" (2024),
/// https://huggingface.co/apple/coreml-depth-anything-v2-small — downloaded by
/// the fetch script, never bundled.
/// The fetched weights live in `Models/` at the repo root. This sketch runs both
/// from there (the gallery compiles it where it sits) and from `Examples/` (a
/// direct `swift run`), so the folder is found by walking up from this file
/// instead of trusting whatever the working directory happens to be.
private func modelsPath(_ name: String) -> String {
    sketchResource(name) ?? ("Models" as NSString).appendingPathComponent(name)
}

@main
final class DepthRelief: Sketch {
    static let modelPath = modelsPath("DepthAnythingV2SmallF16.mlpackage")

    let camera = Camera()
    lazy var depth = ModelTracker(camera, modelAt: URL(fileURLWithPath: Self.modelPath))

    override func setup() {
        try? camera.start()
    }

    override func draw() {
        background(Color(white: 0.04))

        // The weights are fetched, not committed — point at the script instead
        // of failing silently when they aren't there yet.
        guard FileManager.default.fileExists(atPath: Self.modelPath) else {
            return drawStatus("The depth model isn't downloaded yet.\n" +
                              "Run Scripts/fetch-models.sh, then relaunch.",
                              style: .warning)
        }

        // The room, dimmed — the relief carries the picture.
        tint(Color(white: 0.35))
        guard let rect = drawFrame(camera) else { return noTint() }
        noTint()

        if let reason = depth.unavailableReason {
            return drawStatus(reason, style: .warning)
        }
        if !depth.isLoaded {
            return drawStatus("Loading the depth model…\n" +
                              "The first run prepares it for this Mac; " +
                              "after that it starts instantly.")
        }

        // The relief: sample the depth under a grid of points and let each
        // disk's size and color carry it. The map reads 0 (far) … 1 (near).
        noStroke()
        let step = 26 * scale
        var y = rect.y + step / 2
        while y < rect.y + rect.height {
            var x = rect.x + step / 2
            while x < rect.x + rect.width {
                let p = Vector2(x, y)
                let near = depth.value(at: p, in: rect)
                fill(Colormap.turbo.color(at: near))
                drawCircle(center: p, radius: map(near, 0, 1, 0.4, step * 0.62))
                x += step
            }
            y += step
        }

        drawCaption("DepthRelief — depth from one webcam: nearer is bigger and warmer")
    }
}
