import Ollin
import OllinSamplePhotos
import OllinVision

/// Rectangles, found in the live feed. A `RectangleDetector` looks for
/// quadrilateral shapes — a sheet of paper, a phone, a screen, a card, a sign —
/// even seen at an angle, and reports their four corners. `corners(in:)` maps
/// them to the canvas as a closed quad, perspective and all.
///
/// It's a classical detector (no ML model), so it runs on any Mac. The four
/// corners are what a document scanner uses to flatten a page; here they're just
/// drawn as a highlight over whatever rectangle you point at.
@main
final class RectangleScan: Sketch {
    // A camera where this Mac has one, and a bundled photograph where it does
    // not, so there is always a sheet, a card and a screen to find. `--photo` takes the picture even
    // where a camera would have worked, which is how a still of this sketch is made.
    let feed = Camera.orStill(SamplePhoto.desk.load())
    lazy var rectangles = RectangleDetector(feed)

    override func draw() {
        background(Color(white: 0.06))

        guard let rect = drawFrame(feed) else { return }

        let accent = Color(red: 0.3, green: 1.0, blue: 0.6)
        let detected = rectangles.rectangles
        for r in detected {
            let corners = r.corners(in: rect)

            // The quad outline.
            noFill()
            stroke(accent)
            strokeWeight(3 * scale)
            drawPolygon(corners)

            // Corner dots.
            noStroke()
            fill(accent)
            for c in corners { drawCircle(c.x, c.y, 6 * scale) }
        }

        let n = detected.count
        drawCaption("RectangleScan — \(n) rectangle\(n == 1 ? "" : "s")")
    }
}
