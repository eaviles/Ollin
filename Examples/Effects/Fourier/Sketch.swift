import Ollin
import OllinSamplePhotos

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
/// The picture is one of the bundled sample photographs, a woman before a wall
/// of marigolds: the petals are the fine detail out at the spectrum's edges, the
/// face and the blouse the broad tones near its middle. A photograph's spectrum
/// falls off from the center the way every natural picture's does, so the
/// mask's radius is a slider through that falloff.
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

    private var photograph = Image(width: 1, height: 1)

    override func setup() {
        photograph = SamplePhoto.marigolds.load().resized(width: 512, height: 512)
    }

    override func draw() {
        background(Color(hex: 0x0B0E14))

        // The picture, turned by `turn` so the spectrum can be seen turning
        // with it: a rotation of the picture is a rotation of its spectrum.
        let plate = makeRenderTarget(width: 512, height: 512)
        withTarget(plate) {
            background(Color(hex: 0x101010))
            withState {
                translate(256, 256)
                rotate(turn * .tau)
                translate(-256, -256)
                drawImage(photograph, 0, 0, 512, 512)
            }
        }

        // A round mask over the spectrum: inside it the slow waves, outside the
        // fast ones. Keeping one and dropping the other is a blur or an edge
        // finder, chosen by which side of the shape survives.
        let mask = makeRenderTarget(width: 512, height: 512)
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
