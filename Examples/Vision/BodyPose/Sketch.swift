import Ollin
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
    let camera = Camera()
    lazy var bodies = BodyTracker(camera)

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

        // If the body-pose model can't run on this Mac (no compute device), say so
        // on the canvas instead of silently showing no skeleton.
        if let reason = bodies.unavailableReason {
            fill(Color(red: 1.0, green: 0.5, blue: 0.4))
            noStroke()
            textAlign(.center, .middle)
            textSize(18 * scale)
            drawText(reason, in: Rectangle(x: width * 0.1, y: height / 2 - 60 * scale,
                                           width: width * 0.8, height: 120 * scale))
            return
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

        // Screen-space label with the live count.
        fill(.white)
        noStroke()
        textAlign(.center, .bottom)
        textSize(15 * scale)
        let n = detected.count
        drawText("BodyPose — \(n) \(n == 1 ? "person" : "people")", width / 2, height - 28 * scale)
    }
}
