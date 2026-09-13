// figure: frame=0
//
// Guide figure (Chapter 16): a look from a .cube file. The bundled portrait
// plain and through the bundled warm print, and under them the two things a
// look is judged on, a gray ramp and a sweep of hues, each drawn plain above
// and through the same look beneath.
import Ollin
import OllinSamplePhotos

final class Look: Sketch {
    override var canvasSize: CanvasSize { .size(1440, 900) }

    var photograph = Image(width: 1, height: 1)

    override func setup() {
        photograph = SamplePhoto.portrait.load()
    }

    override func draw() {
        background(Color(hex: 0x0C0E13))

        // The portrait: skin, lace, and embroidery, so the look has tones and
        // hues alike to move.
        let plain = makeRenderTarget(width: 700, height: 700)
        withTarget(plain) {
            drawImage(photograph, in: Rectangle(x: 0, y: 0, width: 700, height: 700), fit: .cover)
        }
        drawImage(plain.image, in: Rectangle(x: 10, y: 10, width: 700, height: 700))
        drawImage(plain.filtered(.lut(.warmPrint)).image, in: Rectangle(x: 730, y: 10, width: 700, height: 700))

        // A gray ramp on the left and a sweep of hues on the right, one layer,
        // shown as drawn and through the look, so what it does to a neutral
        // and what it does to a color read side by side.
        let strip = makeRenderTarget(width: 1420, height: 70)
        withTarget(strip) {
            noStroke()
            for x in 0 ..< 710 {
                fill(Color(white: Double(x) / 709))
                drawRect(Double(x), 0, 1, 70)
                fill(Color(hue: Double(x) / 710, saturation: 0.85, brightness: 0.9))
                drawRect(710 + Double(x), 0, 1, 70)
            }
        }
        drawImage(strip.image, in: Rectangle(x: 10, y: 730, width: 1420, height: 70))
        drawImage(strip.filtered(.lut(.warmPrint)).image, in: Rectangle(x: 10, y: 810, width: 1420, height: 70))
    }
}
