import CoreImage
import CoreImage.CIFilterBuiltins
import Ollin
import OllinVision

/// Barcodes and QR codes, read from the live feed. A `BarcodeScanner` finds them
/// and decodes their payload; the sketch outlines each one and prints what it
/// says. Point a phone showing a QR code at the camera.
///
/// It's a classical detector, so it runs on any Mac. A QR code is a simple way to
/// hand a running sketch some input from the world — a URL, a name, a number.
/// With no camera, or under `--photo`, it reads a code it made for itself.
@main
final class BarcodeReader: Sketch {
    let feed = Camera.orStill(BarcodeReader.card())
    lazy var scanner = BarcodeScanner(feed)

    override func draw() {
        background(Color(white: 0.06))

        guard let rect = drawFrame(feed) else { return }

        let accent = Color(red: 1.0, green: 0.85, blue: 0.3)
        let codes = scanner.barcodes
        for code in codes {
            let corners = code.corners(in: rect)

            // The code's outline.
            noFill()
            stroke(accent)
            strokeWeight(3 * scale)
            drawPolygon(corners)

            // The decoded payload, above the code's highest corner.
            if let payload = code.payload {
                let center = code.center(in: rect)
                let top = corners.map(\.y).min() ?? center.y
                fill(accent)
                noStroke()
                textAlign(.center, .bottom)
                textSize(16 * scale)
                drawText(payload, center.x, top - 12 * scale)
            }
        }

        let n = codes.count
        drawCaption("BarcodeReader — \(n) code\(n == 1 ? "" : "s")")
    }

    /// A QR code on a dark card, drawn with Core Image: the stand-in for a
    /// phone held up to the camera.
    static func card() -> Image {
        let generator = CIFilter.qrCodeGenerator()
        generator.message = Data("A code this sketch made for itself".utf8)
        generator.correctionLevel = "M"
        guard let modules = generator.outputImage else { return Image(width: 1280, height: 720, color: .white) }
        let code = modules.transformed(by: CGAffineTransform(scaleX: 14, y: 14))
        let paper = CGRect(x: 0, y: 0, width: 1280, height: 720)
        let placed = code.transformed(by: CGAffineTransform(translationX: (paper.width - code.extent.width) / 2,
                                                            y: (paper.height - code.extent.height) / 2))
        let card = placed.composited(over: CIImage(color: CIColor(red: 0.16, green: 0.16, blue: 0.18)).cropped(to: paper))
        guard let picture = CIContext().createCGImage(card, from: paper) else {
            return Image(width: 1280, height: 720, color: .white)
        }
        return Image(cgImage: picture)
    }
}
