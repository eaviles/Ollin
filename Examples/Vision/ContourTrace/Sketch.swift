import Ollin
import OllinVision

/// A camera frame, made *vector*. `ContourDetector` traces the boundaries between
/// light and dark into closed contours, and `shapes(in:)` hands them back as
/// Ollin `Shape`s — so a live scene becomes black line art on white, the kind you
/// could send straight to a pen plotter (or hatch, or reshape).
///
/// This is where Vision meets Ollin's vector core: the traced `Shape`s ride the
/// same path as any other geometry, so `drawShape`, SVG export, and the hatching
/// transform all just work on them. Point the camera at high-contrast subjects —
/// a face, hands, objects on a light desk — for the cleanest lines.
@main
final class ContourTrace: Sketch {
    let camera = Camera()
    lazy var contours = ContourDetector(camera)

    override func setup() {
        try? camera.start()
    }

    override func draw() {
        background(.white)

        let margin = 40 * scale
        let container = Rectangle(x: margin, y: margin, width: width - 2 * margin, height: height - 2 * margin)

        // The feed, faint, so it's clear what's being traced.
        tint(Color(white: 1, alpha: 0.16))
        guard let rect = drawFrame(camera, in: container) else { return noTint() }
        noTint()

        // The traced contours as black line work — each is an Ollin Shape.
        noFill()
        stroke(Color(white: 0.1))
        strokeWeight(1.5 * scale)
        for shape in contours.shapes(in: rect) {
            drawShape(shape)
        }

        // Screen-space label with the live contour count (dark by hand — the
        // standard caption is white, and this canvas is paper).
        fill(Color(white: 0.1))
        noStroke()
        textAlign(.center, .bottom)
        textSize(15 * scale)
        drawText("ContourTrace — \(contours.count) contours", width / 2, height - 28 * scale)
    }
}
