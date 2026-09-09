import Ollin
import OllinSamplePhotos
import OllinVision

/// Hands, drawn as skeletons over the live feed. A `HandTracker` finds up to two
/// hands and their 21 joints; `bones(in:)` gives the finger chains as line
/// segments, `points(in:)` the joints, and `point(.indexTip, in:)` a single joint
/// for pointing and pinching. Each hand is tinted by which one it is.
///
/// The joints are the raw material for gesture sketches: the distance between
/// `.thumbTip` and `.indexTip` is a pinch, `.indexTip` alone is a cursor, the
/// spread of the fingertips is an open/closed hand.
///
/// The bundled photograph is two open palms on a dark ground, chosen because
/// every finger is separated and nothing overlaps: both hands come back with
/// all twenty-one joints, so ten chains run straight out to ten tips. A hand
/// that grips or rests still gives the tracker something to find, and gives
/// this drawing almost nothing to show.
@main
final class HandTracking: Sketch {
    // A camera where this Mac has one, and a bundled photograph where it does
    // not, so there are always hands to find. `--photo` takes the picture even
    // where a camera would have worked, which is how a still of this sketch is made.
    let feed = Camera.orStill(SamplePhoto.hands.load())
    lazy var hands = HandTracker(feed, maximumHandCount: 2)

    override func draw() {
        background(Color(white: 0.06))

        guard let rect = drawFrame(feed) else { return }

        let detected = hands.hands
        for hand in detected {
            let accent = hand.chirality == .left
                ? Color(red: 0.35, green: 0.7, blue: 1.0)
                : Color(red: 1.0, green: 0.6, blue: 0.3)

            // Finger bones.
            stroke(.white)
            strokeWeight(2 * scale)
            for (a, b) in hand.bones(in: rect) { drawLine(a, b) }

            // Joints.
            noStroke()
            fill(Color(white: 0.9))
            for (_, p) in hand.points(in: rect) { drawCircle(p.x, p.y, 4 * scale) }

            // Fingertips, highlighted.
            fill(accent)
            for tip in HandJoint.tips {
                if let p = hand.point(tip, in: rect) { drawCircle(p.x, p.y, 7 * scale) }
            }
        }

        let n = detected.count
        drawCaption("HandTracking — \(n) hand\(n == 1 ? "" : "s")")
    }
}
