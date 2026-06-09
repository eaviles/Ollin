import Ollin
import OllinVision

/// Faces, found and drawn over the live feed. A `FaceTracker` attached to the
/// `Camera` analyzes each frame on a background thread and publishes the faces it
/// finds; `draw()` reads them and overlays a bounding box and the landmark
/// outlines (jaw, brows, eyes, nose, lips) plus a dot on each pupil.
///
/// The crux is coordinate mapping: the tracker reports normalized points, and the
/// `in:` helpers place them on the canvas. Drawing the frame and mapping the
/// results into the *same* rectangle (`rect`) is what keeps the overlay glued to
/// the face. Set `mirrored: true` everywhere for the natural selfie orientation.
@main
final class FaceTracking: Sketch {
    let camera = Camera()
    lazy var faces = FaceTracker(camera)

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

        let accent = Color(red: 0.3, green: 1.0, blue: 0.6)
        let detected = faces.faces
        for face in detected {
            // Bounding box.
            noFill()
            stroke(Color(red: 0.3, green: 1.0, blue: 0.6, alpha: 0.9))
            strokeWeight(2 * scale)
            drawRect(face.bounds(in: rect))

            // Landmark outlines. Some regions are loops (eyes, lips) — close them;
            // the rest read as open strokes along the feature.
            stroke(.white)
            strokeWeight(1.5 * scale)
            for region in [FaceLandmark.faceContour, .leftEyebrow, .rightEyebrow, .noseCrest] {
                drawPolyline(face.landmarks(region, in: rect))
            }
            for region in [FaceLandmark.leftEye, .rightEye, .outerLips, .innerLips] {
                drawClosed(face.landmarks(region, in: rect))
            }

            // Pupils.
            fill(accent)
            noStroke()
            for region in [FaceLandmark.leftPupil, .rightPupil] {
                for p in face.landmarks(region, in: rect) {
                    drawCircle(p.x, p.y, 3 * scale)
                }
            }
        }

        // Screen-space label with the live count.
        fill(.white)
        noStroke()
        textAlign(.center, .bottom)
        textSize(15 * scale)
        let n = detected.count
        drawText("FaceTracking — \(n) face\(n == 1 ? "" : "s")", width / 2, height - 28 * scale)
    }

    /// Draw a polyline closed back to its first point (for loop regions).
    private func drawClosed(_ points: [Vector2]) {
        guard let first = points.first else { return }
        drawPolyline(points + [first])
    }
}
