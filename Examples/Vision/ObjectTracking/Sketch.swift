import Ollin
import OllinSamplePhotos
import OllinVision

/// Tracking, not detecting. The other Vision examples find things on their own —
/// faces, rectangles, text. This one follows whatever *you* point at: click
/// somewhere on the feed and an `ObjectTracker` locks onto the patch under the
/// cursor and follows it frame to frame as it (or you) moves. Click again to grab
/// something else.
///
/// It's a classical tracker — no neural model — so it runs on any Mac. The box
/// fades as the tracker grows unsure (`confidence`), which is what happens when
/// the thing leaves the frame or moves too fast; click to re-lock.
@main
final class ObjectTracking: Sketch {
    // The tracker needs something to lock onto, so with no feed it reads the bundled picture.
    let feed = Camera.orStill(SamplePhoto.wrestler.load())
    lazy var tracker = ObjectTracker(feed)

    /// The rectangle the frame was last drawn into — kept so `mousePressed()` can
    /// seed the tracker in the same space the overlay maps back through.
    var view = Rectangle(x: 0, y: 0, width: 1, height: 1)

    /// The side of the square we grab on a click, relative to the frame.
    var seedSize: Double { min(view.width, view.height) * 0.2 }

    override func draw() {
        background(Color(white: 0.06))

        guard let rect = drawFrame(feed) else { return }
        view = rect

        if let object = tracker.trackedObject {
            // Green when sure, warming toward orange as confidence drops.
            let c = object.confidence
            let accent = Color(red: 1.0 - c, green: 0.4 + 0.6 * c, blue: 0.3)
            let box = object.bounds(in: view)

            noFill()
            stroke(accent)
            strokeWeight(3 * scale)
            drawRect(box)

            // A crosshair at the center.
            let center = box.center
            let r = 10.0 * scale
            drawLine(center.x - r, center.y, center.x + r, center.y)
            drawLine(center.x, center.y - r, center.x, center.y + r)

            fill(.white)
            noStroke()
            textAlign(.center, .bottom)
            textSize(13 * scale)
            drawText("\(Int(c * 100))%", center.x, box.y - 8 * scale)
        } else {
            // Nothing locked yet — show the patch a click would grab.
            noFill()
            stroke(Color(red: 0.3, green: 1.0, blue: 0.6))
            strokeWeight(2 * scale)
            drawRect(Rectangle(center: mouse,
                               width: seedSize, height: seedSize))
        }

        drawCaption(tracker.isTracking ? "ObjectTracking — click to re-lock"
                                       : "ObjectTracking — click to lock onto what's under the cursor")
    }

    override func mousePressed() {
        guard feed.frame != nil else { return }
        tracker.track(centeredAt: mouse, size: seedSize, in: view)
    }
}
