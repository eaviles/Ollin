import Ollin
import OllinVision

/// The Mac's camera, drawn to the canvas. A `Camera` captures frames; `start()`
/// asks for camera permission the first time (the system prompts on first run
/// from `swift run`), and `drawFrame(camera)` draws the latest frame letterboxed
/// into the canvas, so the picture keeps its proportions whatever the camera's
/// aspect ratio — and shows a standard waiting notice until the first frame
/// arrives (or while permission is pending).
///
/// This is the foundation the trackers build on: attach a `FaceTracker` (or any
/// of the recognizers) to the same camera and read its results in `draw()`.
@main
final class WebcamFeed: Sketch {
    let camera = Camera()

    override func setup() {
        try? camera.start()
    }

    override func draw() {
        background(Color(white: 0.07))
        drawFrame(camera)
        drawCaption("WebcamFeed")
    }
}
