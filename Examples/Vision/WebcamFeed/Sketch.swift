import Ollin
import OllinSamplePhotos
import OllinVision

/// The Mac's camera, drawn to the canvas. A `Camera` captures frames; `start()`
/// asks for camera permission the first time (the system prompts on first run
/// from `swift run`), and `drawFrame(feed)` draws the latest frame letterboxed
/// into the canvas, so the picture keeps its proportions whatever the camera's
/// aspect ratio — and shows a standard waiting notice until the first frame
/// arrives (or while permission is pending).
///
/// This is the foundation the trackers build on: attach a `FaceTracker` (or any
/// of the recognizers) to the same camera and read its results in `draw()`.
@main
final class WebcamFeed: Sketch {
    // A camera where this Mac has one, and a bundled photograph where it does
    // not, so there is always a picture to show. `--photo` takes the picture even
    // where a camera would have worked, which is how a still of this sketch is made.
    let feed = Camera.orStill(SamplePhoto.portrait.load())

    override func draw() {
        background(Color(white: 0.07))
        drawFrame(feed)
        drawCaption("WebcamFeed")
    }
}
