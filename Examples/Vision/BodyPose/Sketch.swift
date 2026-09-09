import Ollin
import OllinSamplePhotos
import OllinVision

/// A person's pose, drawn as a stick figure over the live feed. A `BodyTracker`
/// finds people and their 19 joints; `bones(in:)` gives the skeleton as line
/// segments and `points(in:)` the joints. Joints that aren't in view (often the
/// legs at a desk) simply don't appear, so the figure is whatever Vision can see.
///
/// Whole-body pose is the input behind reach-and-lean interactions, mirror
/// pieces, and silhouette work — all of it a few joint positions away.
@main
final class BodyPose: Sketch {
    // A camera where this Mac has one, and a bundled photograph where it does
    // not, so there is always a body to find. `--photo` takes the picture even
    // where a camera would have worked, which is how a still of this sketch is made.
    let feed = Camera.orStill(SamplePhoto.reaching.load())
    lazy var bodies = BodyTracker(feed)

    override func draw() {
        background(Color(white: 0.06))

        guard let rect = drawFrame(feed) else { return }

        // If the body-pose model can't run on this Mac (no compute device), say so
        // on the canvas instead of silently showing no skeleton.
        if let reason = bodies.unavailableReason {
            return drawStatus(reason, style: .warning)
        }

        let detected = bodies.bodies
        let accent = Color(red: 0.4, green: 0.85, blue: 1.0)
        for body in detected {
            // Skeleton bones.
            stroke(accent)
            strokeWeight(4 * scale)
            for (a, b) in body.bones(in: rect) { drawLine(a, b) }

            // Joints.
            noStroke()
            fill(.white)
            for (_, p) in body.points(in: rect) { drawCircle(p.x, p.y, 6 * scale) }
        }

        let n = detected.count
        drawCaption("BodyPose — \(n) \(n == 1 ? "person" : "people")")
    }
}
