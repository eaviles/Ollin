import Ollin
import OllinVision

/// Hands, drawn as skeletons over the live feed. A `HandTracker` finds up to two
/// hands and their 21 joints; `bones(in:)` gives the finger chains as line
/// segments, `points(in:)` the joints, and `point(.indexTip, in:)` a single joint
/// for pointing and pinching. Each hand is tinted by which one it is.
///
/// The joints are the raw material for gesture sketches: the distance between
/// `.thumbTip` and `.indexTip` is a pinch, `.indexTip` alone is a cursor, the
/// spread of the fingertips is an open/closed hand.
@main
final class HandTracking: Sketch {
    let camera = Camera()
    lazy var hands = HandTracker(camera, maximumHandCount: 2)

    override func setup() {
        textFont(OutlineFont.system)
        try? camera.start()
    }

    override func draw() {
        background(Color(white: 0.06))

        guard let frame = camera.frame else {
            fill(Color(white: 0.5))
            textAlign(.center, .middle)
            textSize(22 * scale)
            drawText("Waiting for camera…", width / 2, height / 2)
            return
        }

        let rect = camera.fittedRect(in: bounds) ?? bounds
        drawImage(frame, in: rect)

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

        // Screen-space label with the live count.
        fill(.white)
        noStroke()
        textAlign(.center, .bottom)
        textSize(15 * scale)
        let n = detected.count
        drawText("HandTracking — \(n) hand\(n == 1 ? "" : "s")", width / 2, height - 28 * scale)
    }
}
