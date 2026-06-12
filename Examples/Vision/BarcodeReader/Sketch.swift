import Ollin
import OllinVision

/// Barcodes and QR codes, read from the live feed. A `BarcodeScanner` finds them
/// and decodes their payload; the sketch outlines each one and prints what it
/// says. Point a phone showing a QR code at the camera.
///
/// It's a classical detector, so it runs on any Mac. A QR code is a simple way to
/// hand a running sketch some input from the world — a URL, a name, a number.
@main
final class BarcodeReader: Sketch {
    let camera = Camera()
    lazy var scanner = BarcodeScanner(camera)

    override func setup() {
        try? camera.start()
    }

    override func draw() {
        background(Color(white: 0.06))

        guard let rect = drawFrame(camera) else { return }

        let accent = Color(red: 1.0, green: 0.85, blue: 0.3)
        let codes = scanner.barcodes
        for code in codes {
            let corners = code.corners(in: rect)

            // The code's outline.
            noFill()
            stroke(accent)
            strokeWeight(3 * scale)
            drawPolygon(corners)

            // The decoded payload, above the code.
            if let payload = code.payload {
                let center = code.center(in: rect)
                fill(accent)
                noStroke()
                textAlign(.center, .bottom)
                textSize(16 * scale)
                drawText(payload, center.x, center.y - 18 * scale)
            }
        }

        let n = codes.count
        drawCaption("BarcodeReader — \(n) code\(n == 1 ? "" : "s")")
    }
}
