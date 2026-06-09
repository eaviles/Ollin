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
        textFont(OutlineFont.system)
        try? camera.start()
    }

    override func draw() {
        background(.white)

        guard let frame = camera.frame else {
            fill(Color(white: 0.5))
            textAlign(.center, .middle)
            textSize(22 * scale)
            drawText("Waiting for camera…", width / 2, height / 2)
            return
        }

        let margin = 40 * scale
        let container = Rectangle(x: margin, y: margin, width: width - 2 * margin, height: height - 2 * margin)
        let rect = camera.fittedRect(in: container) ?? container

        // The feed, faint, so it's clear what's being traced.
        tint(Color(white: 1, alpha: 0.16))
        drawImage(frame, in: rect)
        noTint()

        // The traced contours as black line work — each is an Ollin Shape.
        noFill()
        stroke(Color(white: 0.1))
        strokeWeight(1.5 * scale)
        for shape in contours.shapes(in: rect) {
            drawShape(shape)
        }

        // Screen-space label with the live contour count.
        fill(Color(white: 0.1))
        noStroke()
        textAlign(.center, .bottom)
        textSize(15 * scale)
        drawText("ContourTrace — \(contours.count) contours", width / 2, height - 28 * scale)
    }
}
