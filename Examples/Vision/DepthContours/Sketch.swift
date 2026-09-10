import Foundation
import Ollin
import OllinSamplePhotos
import OllinVision

/// Depth that holds still: contour lines of depth drawn over the live feed,
/// from a *video* depth model that reads each frame against the ones before
/// it, so the lines move with the scene instead of shimmering. Flip the
/// `perFrame` parameter in the inspector (⌘/) to draw the same lines from the
/// single-image model instead and watch them crawl on a still scene; that
/// difference is the whole point of a video model. Press R to re-anchor the
/// depth scale when the feed moves to a different scene. The model weights
/// aren't in the repo: run `Scripts/fetch-models.sh` once and relaunch (the
/// sketch says so on the canvas until then).
///
/// Model: Video Depth Anything (small), converted to Core ML on this machine
/// by `Scripts/convert-video-depth.sh`, Apache-2.0. Sili Chen et al., "Video
/// Depth Anything: Consistent Depth Estimation for Super-Long Videos" (CVPR
/// 2025), https://github.com/DepthAnything/Video-Depth-Anything. The
/// comparison model is Depth Anything V2 (small) in Apple's official Core ML
/// conversion, Apache-2.0, Lihe Yang et al. (2024),
/// https://huggingface.co/apple/coreml-depth-anything-v2-small. Both are put
/// in place by the fetch script, never bundled.
/// The fetched weights live in `Models/` at the repo root. This sketch runs both
/// from there (the gallery compiles it where it sits) and from `Examples/` (a
/// direct `swift run`), so the folder is found by walking up from this file
/// instead of trusting whatever the working directory happens to be.
private func modelsPath(_ name: String) -> String {
    sketchResource(name) ?? ("Models" as NSString).appendingPathComponent(name)
}

@main
final class DepthContours: Sketch {
    static let videoModelPath = modelsPath("VideoDepthAnythingSmallF16.mlpackage")
    static let stillModelPath = modelsPath("DepthAnythingV2SmallF16.mlpackage")

    /// Draw the lines from the single-image model instead, for comparison.
    @Param(icon: "photo") var perFrame = false
    /// How many contour levels between far and near.
    @Param(3 ... 16, icon: "lines.measurement.horizontal") var levels = 8

    // Depth wants a scene with distance in it, so with no feed it reads the bundled street.
    let feed = Camera.orStill(SamplePhoto.street.load())
    lazy var depth = DepthTracker(feed, modelAt: URL(fileURLWithPath: Self.videoModelPath))
    /// Made on first use, so the comparison model runs only once asked for.
    lazy var still = ModelTracker(feed, modelAt: URL(fileURLWithPath: Self.stillModelPath))

    override func keyPressed() {
        if key == "r" || key == "R" { depth.reset() }
    }

    override func draw() {
        background(Color(white: 0.04))

        // The weights are fetched, not committed; point at the script instead
        // of failing silently when they aren't there yet.
        guard FileManager.default.fileExists(atPath: Self.videoModelPath) else {
            return drawStatus("The video depth model isn't built yet.\n" +
                              "Run Scripts/fetch-models.sh, then relaunch.",
                              style: .warning)
        }

        // The room, dimmed; the lines carry the picture.
        tint(Color(white: 0.3))
        guard let rect = drawFrame(feed) else { return noTint() }
        noTint()

        if perFrame {
            if let reason = still.unavailableReason {
                return drawStatus(reason, style: .warning)
            }
            if !still.isLoaded {
                return drawStatus("Loading the single-image model…")
            }
        } else {
            if let reason = depth.unavailableReason {
                return drawStatus(reason, style: .warning)
            }
            if !depth.isLoaded {
                return drawStatus("Loading the video depth model…\n" +
                                  "The first run prepares it for this Mac; " +
                                  "after that it starts instantly.")
            }
        }

        // The level curves of the depth map, far to near, each in the color
        // the depth reads at that level. The field samples the tracker under
        // canvas points, so the lines land on the picture by construction.
        let steps = (1...levels).map { Double($0) / Double(levels + 1) }
        let rings = isolines(at: steps, in: rect, resolution: 120) { p in
            perFrame ? still.value(at: p, in: rect) : depth.value(at: p, in: rect)
        }
        noFill()
        strokeWeight(2 * scale)
        for (level, contours) in zip(steps, rings) {
            stroke(Colormap.turbo.color(at: level))
            for contour in contours {
                drawPolyline(contour.points, closed: contour.isClosed)
            }
        }

        drawCaption(perFrame
            ? "DepthContours — the single-image model: the lines crawl on a still scene"
            : "DepthContours — depth that holds still: the lines move only with the scene (R re-anchors)")
    }
}
