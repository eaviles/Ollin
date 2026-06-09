import Ollin
import OllinVision

/// The Mac's camera, drawn to the canvas. A `Camera` captures frames; `start()`
/// asks for camera permission the first time (the system prompts on first run
/// from `swift run`), and `camera.frame` is the latest frame as a drawable
/// `Image`. It's drawn letterboxed into the canvas with `fittedRect(in:)`, so the
/// picture keeps its proportions whatever the camera's aspect ratio.
///
/// This is the foundation the trackers build on: attach a `FaceTracker` (or any
/// of the recognizers) to the same camera and read its results in `draw()`.
@main
final class WebcamFeed: Sketch {
    let camera = Camera()

    override func setup() {
        textFont(OutlineFont.system)
        try? camera.start()
    }

    override func draw() {
        background(Color(white: 0.07))

        if let frame = camera.frame {
            let rect = camera.fittedRect(in: bounds) ?? bounds
            drawImage(frame, in: rect)
        } else {
            // Before the first frame (or while permission is pending).
            fill(Color(white: 0.5))
            textAlign(.center, .middle)
            textSize(22 * scale)
            drawText("Waiting for camera…", width / 2, height / 2)
        }

        // Screen-space label.
        fill(.white)
        textAlign(.center, .bottom)
        textSize(15 * scale)
        drawText("WebcamFeed", width / 2, height - 28 * scale)
    }
}
