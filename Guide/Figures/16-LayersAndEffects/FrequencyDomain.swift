// figure: frame=2
//
// Guide diagram (Chapter 16): a picture, the spectrum it is made of, and what
// comes back when only the slow waves are kept. The third panel is the
// low-pass: a circle drawn over the spectrum, and the ringing that a hard cut
// leaves around every edge.
import Ollin

final class FrequencyDomain_Figure: Sketch {
    override var canvasSize: CanvasSize { .size(1180, 460) }

    override func draw() {
        background(Color(hex: 0x0B0E14))

        // The picture: hard shapes for broad tones, fine stripes for detail.
        let plate = makeRenderTarget(width: 512, height: 512)
        withTarget(plate) {
            background(Color(hex: 0x101010))
            noStroke()
            fill(Color(hex: 0xF2E8D5))
            drawCircle(190, 210, 98)
            fill(Color(hex: 0x8FB6D4))
            drawRect(250, 250, 176, 176)
            fill(Color(hex: 0xE0684A))
            drawTriangle(Vector2(112, 424), Vector2(214, 330), Vector2(238, 452))
            fill(Color(white: 0.85))
            for i in 0 ..< 32 {
                drawRect(Double(i) * 16 + 4, 26, 6, 72)
            }
        }

        // Keep the middle of the spectrum: the slow, wide waves.
        let mask = makeRenderTarget(width: 512, height: 512)
        withTarget(mask) {
            background(.black)
            noStroke()
            fill(.white)
            drawCircle(256, 256, 22)
        }

        let spectrum = plate.filtered(.fourier())
        let kept = spectrum.combined(with: mask, .mask())

        let size = 330.0, gap = 26.0, top = 86.0
        let left = (Double(width) - (size * 3 + gap * 2)) / 2
        drawImage(plate.image, left, top, size, size)
        drawImage(spectrum.filtered(.spectrum()).image, left + size + gap, top, size, size)
        drawImage(kept.filtered(.inverseFourier()).image, left + (size + gap) * 2, top, size, size)

        fill(Color(white: 0.78))
        textSize(20)
        textAlign(.center)
        drawText("the picture", left + size / 2, 54)
        drawText("what it is made of", left + size * 1.5 + gap, 54)
        drawText("only the slow waves kept", left + size * 2.5 + gap * 2, 54)
    }
}
