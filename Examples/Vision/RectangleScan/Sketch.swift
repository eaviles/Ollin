import Ollin
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
    let camera = Camera()
    lazy var rectangles = RectangleDetector(camera)

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

        // Screen-space label.
        fill(.white)
        noStroke()
        textAlign(.center, .bottom)
        textSize(15 * scale)
        let n = detected.count
        drawText("RectangleScan — \(n) rectangle\(n == 1 ? "" : "s")", width / 2, height - 28 * scale)
    }
}
