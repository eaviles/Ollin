// figure: frame=0
//
// Guide figure (Chapter 16): a film look. A night street drawn plain and
// through halation and film grain; under them the same lamp magnified four
// times, plain and halated, so the white core can be seen to hold while the
// ring lands around it, and a gray ramp plain above and grained below, so
// the grain's law shows: nothing at either end, most in the middle.
import Ollin

final class FilmLook: Sketch {
    override var canvasSize: CanvasSize { .size(1440, 900) }

    override func draw() {
        background(Color(hex: 0x0C0E13))

        // The street, plain on the left and filmed on the right.
        let street = makeRenderTarget(width: 700, height: 700)
        withTarget(street) { drawStreet(700, 700) }
        let halation = Filter.halation(threshold: 0.8, radius: 18)
        let halated = street.filtered(halation)
        let filmed = halated.filtered(.filmGrain(amount: 0.05, size: 2, seed: 3))
        drawImage(street.image, in: Rectangle(x: 10, y: 10, width: 700, height: 700))
        drawImage(filmed.image, in: Rectangle(x: 730, y: 10, width: 700, height: 700))

        // The second lamp, magnified four times: plain, then halated. The
        // whole picture is drawn at four times its size and clipped to a
        // window centered on the lamp.
        let lamp = Vector2(700 * 0.38, 700 * 0.5)
        let scale = 4.0
        for (index, image) in [street.image, halated.image].enumerated() {
            let x = 10 + Double(index) * 355, y = 730.0, w = 345.0, h = 150.0
            withClip(Rectangle(x: x, y: y, width: w, height: h)) {
                drawImage(image, in: Rectangle(x: x + w / 2 - lamp.x * scale, y: y + h / 2 - lamp.y * scale,
                                               width: 700 * scale, height: 700 * scale))
            }
        }

        // A gray ramp, plain above and grained below.
        let ramp = makeRenderTarget(width: 710, height: 70)
        withTarget(ramp) {
            noStroke()
            for x in 0 ..< 710 {
                fill(Color(white: Double(x) / 709))
                drawRect(Double(x), 0, 1, 70)
            }
        }
        drawImage(ramp.image, in: Rectangle(x: 720, y: 730, width: 710, height: 70))
        drawImage(ramp.filtered(.filmGrain(amount: 0.12, size: 2, seed: 3)).image,
                  in: Rectangle(x: 720, y: 810, width: 710, height: 70))
    }

    /// A sky ramp, a moon, facades with a few lit windows, and four lamps
    /// with pools of light on the pavement.
    private func drawStreet(_ w: Double, _ h: Double) {
        noStroke()
        for y in stride(from: 0.0, to: h, by: 2) {
            let t = y / h
            fill(Color(red: 0.02 + 0.03 * t, green: 0.03 + 0.04 * t, blue: 0.08 + 0.14 * t))
            drawRect(0, y, w, 2)
        }
        fill(Color(white: 0.96))
        drawCircle(w * 0.8, h * 0.16, 28)

        seed(3)
        let ground = h * 0.72
        var x = 0.0
        while x < w {
            let fw = random(60, 130), fh = random(90, 240)
            fill(Color(red: random(0.14, 0.2), green: random(0.12, 0.17), blue: random(0.11, 0.15)))
            drawRect(x, ground - fh, fw, fh)
            for row in stride(from: ground - fh + 18, to: ground - 24, by: 38) {
                for col in stride(from: x + 12, to: x + fw - 20, by: 28) where random() < 0.35 {
                    fill(Color(red: 0.55, green: 0.42, blue: 0.24))
                    drawRect(col, row, 10, 16)
                }
            }
            x += fw + random(4, 14)
        }
        fill(Color(red: 0.24, green: 0.22, blue: 0.21))
        drawRect(0, ground, w, h - ground)

        for i in 0 ..< 4 {
            let lx = w * (0.14 + 0.24 * Double(i)), ly = h * 0.5
            fill(Color(red: 0.12, green: 0.11, blue: 0.1))
            drawRect(lx - 2, ly, 4, ground - ly)
            for ring in 1 ... 10 {
                fill(Color(red: 0.9, green: 0.7, blue: 0.4, alpha: 0.045))
                drawCircle(lx, ground + 6, 12 + Double(ring) * 11)
            }
            fill(Color(red: 1, green: 0.96, blue: 0.85))
            drawCircle(lx, ly, 9)
        }
    }
}
