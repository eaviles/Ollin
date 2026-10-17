import Ollin
import OllinSamplePhotos
import OllinVideo
import OllinVision

/// Tracking, not detecting. The other Vision examples find things on their own:
/// faces, rectangles, text. This one follows whatever *you* point at. Click
/// somewhere on the feed and an `ObjectTracker` locks onto the patch under the
/// cursor and follows it frame to frame as it (or you) moves. Click again to
/// grab something else.
///
/// Where there is no camera it plays the dance film that ships with Ollin, and
/// with nobody there to click, a detector gives the first lock instead: a
/// `FaceTracker` finds the dancer's face, that box seeds the tracker, and from
/// then on the tracker follows the patch on its own. The face detector is asked
/// again only when the tracker's `confidence` says it has lost the patch, which
/// is what a cut or the film's loop does. A click still re-locks anywhere.
///
/// It's a classical tracker with no neural model, so it runs on any Mac. The
/// box fades as the tracker grows unsure, and a trail shows where the patch has
/// been since the last lock.
@main
final class ObjectTracking: Sketch {
    let feed: any FrameSource & VideoFeed = {
        if !CommandLine.arguments.contains("--photo") {
            let camera = Camera()
            if (try? camera.start()) != nil, camera.isRunning { return camera }
        }
        let film = try! VideoPlayer(url: SampleClip.dance.url)
        film.loops = true
        film.isMuted = true
        film.play()
        return film
    }()
    lazy var tracker = ObjectTracker(feed)
    /// The detector that hands the film its first lock; a camera has a hand to click.
    lazy var faces: FaceTracker? = feed is Camera ? nil : FaceTracker(feed)

    /// Below this the patch counts as lost.
    let lostBelow = 0.3

    /// The rectangle the frame was last drawn into, kept so `mousePressed()` can
    /// seed the tracker in the same space the overlay maps back through.
    var view = Rectangle(x: 0, y: 0, width: 1, height: 1)
    /// Where the patch has been since the last lock.
    var trail: [Vector2] = []
    var locks = 0
    var lockedBy = "click"

    /// The side of the square we grab on a click, relative to the frame.
    var seedSize: Double { min(view.width, view.height) * 0.2 }

    override func draw() {
        background(Color(white: 0.06))

        guard let rect = drawFrame(feed) else { return }
        view = rect
        lockFromTheFace()

        if let object = tracker.trackedObject {
            // Green when sure, warming toward orange as confidence drops.
            let c = object.confidence
            let accent = Color(red: 1.0 - c, green: 0.4 + 0.6 * c, blue: 0.3)
            let box = object.bounds(in: view)
            if c >= lostBelow { trail.append(box.center) }
            if trail.count > 90 { trail.removeFirst(trail.count - 90) }

            noFill()
            strokeWeight(2 * scale)
            for i in trail.indices.dropFirst() {
                stroke(accent.withAlpha(Double(i) / Double(trail.count) * 0.8))
                drawLine(trail[i - 1], trail[i])
            }

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
        } else if faces == nil {
            // Nothing locked yet: show the patch a click would grab.
            noFill()
            stroke(Color(red: 0.3, green: 1.0, blue: 0.6))
            strokeWeight(2 * scale)
            drawRect(Rectangle(center: mouse, width: seedSize, height: seedSize))
        }

        let how = locks == 0 ? "click to lock onto what's under the cursor"
            : "lock \(locks), from the \(lockedBy); click to re-lock"
        drawCaption("ObjectTracking: \(how)")
    }

    /// With the film, a face the detector finds seeds the tracker whenever the
    /// tracker has nothing, or has lost what it had.
    func lockFromTheFace() {
        guard let faces else { return }
        let lost = !tracker.isTracking || (tracker.trackedObject?.confidence ?? 1) < lostBelow
        guard lost, let face = faces.faces.first else { return }
        // A little more than the face, so the hair's edge gives it something to hold.
        let box = face.bounds(in: view)
        tracker.track(Rectangle(center: box.center, width: box.width * 1.3, height: box.height * 1.3),
                      in: view)
        relocked(by: "face detector")
    }

    override func mousePressed() {
        guard feed.frame != nil else { return }
        tracker.track(centeredAt: mouse, size: seedSize, in: view)
        relocked(by: "click")
    }

    func relocked(by source: String) {
        locks += 1
        lockedBy = source
        trail.removeAll()
    }
}
