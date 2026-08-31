import Foundation
import Ollin
import OllinVideo
import OllinVision

/// A moving picture, made *vector*. `ContourDetector` traces the boundaries
/// between light and dark into closed contours, and `shapes(in:)` hands them
/// back as Ollin `Shape`s, so a live scene becomes black line art on white, the
/// kind you could send straight to a pen plotter (or hatch, or reshape).
///
/// By default the detector reads the camera; point it at high-contrast subjects
/// (a face, hands, objects on a light desk) for the cleanest lines. Pass a clip
/// path on launch and the same detector traces the footage as it plays instead:
///
/// ```
/// swift run Example-Vision-ContourTrace /path/to/your/clip.mp4
/// ```
///
/// The swap is one line, and that is the lesson: a tracker attaches to any
/// `FrameSource` (a `Camera`, a `VideoPlayer`) the same way, so vision over
/// recorded footage costs nothing beyond choosing the source.
///
/// This is where Vision meets Ollin's vector core: the traced `Shape`s ride the
/// same path as any other geometry, so `drawShape`, SVG export, and the
/// hatching transform all just work on them.
@main
final class ContourTrace: Sketch {
    var feed: (any FrameSource & VideoFeed)?
    var contours: ContourDetector?

    override func setup() {
        if let path = clipPath(), let player = try? VideoPlayer(path: path) {
            // Recorded footage benefits from a contrast boost before tracing.
            player.loops = true
            player.isMuted = true
            player.play()
            feed = player
            contours = ContourDetector(player, contrastAdjustment: 3)
        } else {
            let camera = Camera()
            try? camera.start()
            feed = camera
            contours = ContourDetector(camera)
        }
    }

    /// A readable file path passed on launch, if any; it swaps the camera for a
    /// video player.
    private func clipPath() -> String? {
        CommandLine.arguments.dropFirst().first(where: {
            !$0.hasPrefix("-") && FileManager.default.fileExists(atPath: $0)
        })
    }

    override func draw() {
        background(.white)

        let margin = 40 * scale
        let container = Rectangle(x: margin, y: margin, width: width - 2 * margin, height: height - 2 * margin)
        guard let feed, let contours else { return }

        // The feed, faint, so it's clear what's being traced.
        tint(Color(white: 1, alpha: 0.16))
        guard let rect = drawFrame(feed, in: container) else { return noTint() }
        noTint()

        // The traced contours as black line work; each is an Ollin Shape.
        noFill()
        stroke(Color(white: 0.1))
        strokeWeight(1.5 * scale)
        for shape in contours.shapes(in: rect) {
            drawShape(shape)
        }

        // Screen-space label with the live contour count (dark by hand; the
        // standard caption is white, and this canvas is paper).
        fill(Color(white: 0.1))
        noStroke()
        textAlign(.center, .bottom)
        textSize(15 * scale)
        drawText("ContourTrace: \(contours.count) contours", width / 2, height - 28 * scale)
    }
}
