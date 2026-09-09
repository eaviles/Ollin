import Ollin
import OllinSamplePhotos
import OllinVision

/// Faces, found and drawn over the live feed. A `FaceTracker` attached to the
/// `Camera` analyzes each frame on a background thread and publishes the faces it
/// finds; `draw()` reads them and overlays a bounding box and the landmark
/// outlines (jaw, brows, eyes, nose, lips) plus a dot on each pupil.
///
/// The crux is coordinate mapping: the tracker reports normalized points, and the
/// `in:` helpers place them on the canvas. `drawFrame` returns the rectangle the
/// frame landed in, and mapping the results into the *same* rectangle (`rect`) is
/// what keeps the overlay glued to the face. Set `mirrored: true` everywhere for
/// the natural selfie orientation.
@main
final class FaceTracking: Sketch {
    // A camera where this Mac has one, and a bundled photograph where it does
    // not, so there is always a face to find. `--photo` takes the picture even
    // where a camera would have worked, which is how a still of this sketch is made.
    let feed = Camera.orStill(SamplePhoto.portrait.load())
    lazy var faces = FaceTracker(feed)

    override func draw() {
        background(Color(white: 0.06))

        guard let rect = drawFrame(feed) else { return }

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
                drawPolyline(face.landmarks(region, in: rect), closed: true)
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

        let n = detected.count
        drawCaption("FaceTracking — \(n) face\(n == 1 ? "" : "s")")
    }
}
