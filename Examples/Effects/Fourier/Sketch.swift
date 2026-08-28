import Ollin

/// A picture, what it is made of, and the way back.
///
/// The Fourier transform reads a layer as a sum of waves instead of a grid of
/// pixels. `.fourier()` writes that sum out: slow, wide gradients land near the
/// middle of the spectrum and fine detail out at the edges, so the second panel
/// is a map of the first one's scales. `.inverseFourier()` reads it back, and
/// with nothing in between it hands the picture back unchanged.
///
/// What makes it worth the trip is the *between*. A mask drawn over the
/// spectrum multiplies it, so keeping the middle throws the fine detail away
/// (the picture comes back soft) and keeping the outside throws the broad tones
/// away (only its edges come back). One shape, drawn once, does what a whole
/// family of blur and sharpen filters does, because scale is what the spectrum
/// is laid out by.
///
/// The transform works on a square layer whose side is a power of two, so the
/// panels here are 512, and it reads one channel: the linear brightness unless
/// another is named.
@main
final class FourierPanels: Sketch {

    @Param(4 ... 200, icon: "circle.dashed") var cut = 22.0
    @Param(icon: "arrow.up.left.and.arrow.down.right") var keepTheMiddle = true
    @Param(0 ... 1, icon: "rotate.right") var turn = 0.0

    override var canvasSize: CanvasSize { .size(1080, 520) }

    override func draw() {
        background(Color(hex: 0x0B0E14))

        // The picture: a few hard shapes and one fine grating, so the spectrum
        // has both broad tones and sharp detail to show.
        let plate = renderTarget(width: 512, height: 512)
        withTarget(plate) {
            background(Color(hex: 0x101010))
            noStroke()
            withState {
                translate(256, 256)
                rotate(turn * .tau)
                translate(-256, -256)
                fill(Color(hex: 0xF2E8D5))
                drawCircle(190, 200, 96)
                fill(Color(hex: 0x8FB6D4))
                drawRect(250, 250, 170, 170)
                fill(Color(hex: 0xE0684A))
                drawTriangle(Vector2(120, 420), Vector2(220, 330), Vector2(240, 450))
            }
            // Fine stripes: one wavelength, so it lands as one pair of spots.
            fill(Color(white: 0.85))
            for i in 0 ..< 32 {
                drawRect(Double(i) * 16 + 4, 24, 6, 70)
            }
        }

        // A round mask over the spectrum: inside it the slow waves, outside the
        // fast ones. Keeping one and dropping the other is a blur or an edge
        // finder, chosen by which side of the shape survives.
        let mask = renderTarget(width: 512, height: 512)
        withTarget(mask) {
            background(keepTheMiddle ? .black : .white)
            noStroke()
            fill(keepTheMiddle ? .white : .black)
            drawCircle(256, 256, cut)
        }

        let spectrum = plate.filtered(.fourier())
        let kept = spectrum.combined(with: mask, .mask())
        let back = kept.filtered(.inverseFourier())

        // Left to right: the picture, its spectrum, and what comes back through
        // the mask.
        let size = 340.0, gap = 22.0, top = 96.0
        let left = (Double(width) - (size * 3 + gap * 2)) / 2
        drawImage(plate.image, left, top, size, size)
        drawImage(spectrum.filtered(.spectrum()).image, left + size + gap, top, size, size)
        drawImage(back.image, left + (size + gap) * 2, top, size, size)

        fill(Color(white: 0.75))
        textSize(19)
        textAlign(.center)
        drawText("the picture", left + size / 2, 64)
        drawText("what it is made of", left + size * 1.5 + gap, 64)
        drawText(keepTheMiddle ? "the slow waves kept" : "the fast waves kept",
                 left + size * 2.5 + gap * 2, 64)
    }
}
