import Ollin
import OllinSamplePhotos
import OllinVision

/// One webcam, but the skeleton lands in space: a `BodyTracker3D` places all 17
/// joints in meters — root at the origin, y up, z away from the camera — beside
/// their projection onto the picture. The feed gets the usual stick-figure
/// overlay; the inset re-draws the *same* skeleton from the side, a view no
/// camera is at, and the caption reads the person's distance straight off the
/// camera-space root.
///
/// Two ways the 3D model differs from `BodyTracker`: it follows one person (the
/// most prominent), and it always places the full skeleton — joints it can't
/// see are its best guess, projecting off-frame rather than disappearing (sit
/// at a desk and it still stands you up in the side view).
@main
final class BodyPose3D: Sketch {
    // A camera where this Mac has one, and a bundled photograph where it does
    // not, so there is always a body to place in space. `--photo` takes the picture even
    // where a camera would have worked, which is how a still of this sketch is made.
    let feed = Camera.orStill(SamplePhoto.reaching.load())
    lazy var tracker = BodyTracker3D(feed)

    override func draw() {
        background(Color(white: 0.06))

        guard let rect = drawFrame(feed) else { return }

        // If the model can't run on this Mac (no compute device), say so on the
        // canvas instead of silently showing no skeleton.
        if let reason = tracker.unavailableReason {
            return drawStatus(reason, style: .warning)
        }

        let body = tracker.body
        if let body {
            // Front view: the joints projected back onto the picture.
            stroke(Color(red: 0.4, green: 0.85, blue: 1.0))
            strokeWeight(4 * scale)
            for (a, b) in body.bones(in: rect) { drawLine(a, b) }
            noStroke()
            fill(.white)
            for (_, p) in body.points(in: rect) { drawCircle(p.x, p.y, 5 * scale) }
        }

        drawSideView(body)

        drawCaption(body?.distance.map {
            String(format: "BodyPose3D — %.1f m from the camera", $0)
        } ?? "BodyPose3D — no one in view")
    }

    /// The same skeleton seen from the person's side: model space `(z, y)` onto
    /// the panel, meters to pixels. Depth runs left-to-right (the camera is off
    /// the panel's left edge), and y up flips to screen y down.
    private func drawSideView(_ body: Body3D?) {
        let margin = 24 * scale
        let panel = Rectangle(x: width - 0.3 * width - margin,
                              y: height - 0.42 * height - margin,
                              width: 0.3 * width, height: 0.42 * height)
        fill(Color(white: 0.04, alpha: 0.82))
        stroke(Color(white: 0.35))
        strokeWeight(1 * scale)
        drawRect(panel, cornerRadius: 8 * scale)

        fill(Color(white: 0.55))
        noStroke()
        textAlign(.left, .top)
        textSize(12 * scale)
        drawText("side view", panel.x + 12 * scale, panel.y + 10 * scale)

        guard let body else { return }
        let metersToPixels = panel.height / 2.4   // a standing figure fits with air
        let center = panel.center
        func project(_ p: Vector3) -> Vector2 {
            center + Vector2(p.z * metersToPixels, -p.y * metersToPixels)
        }

        // A ground reference under the lower ankle.
        let ankles = [body.position(.leftAnkle)?.y, body.position(.rightAnkle)?.y].compactMap { $0 }
        if let groundY = ankles.min() {
            let y = center.y - groundY * metersToPixels + 4 * scale
            stroke(Color(white: 0.3))
            strokeWeight(1 * scale)
            drawLine(panel.x + 10 * scale, y, panel.x + panel.width - 10 * scale, y)
        }

        stroke(Color(red: 1.0, green: 0.62, blue: 0.3))
        strokeWeight(3 * scale)
        for (a, b) in body.bones() { drawLine(project(a), project(b)) }
        noStroke()
        fill(.white)
        for (_, p) in body.positions {
            let q = project(p)
            drawCircle(q.x, q.y, 3.5 * scale)
        }
    }
}
