// figure: frame=24
//
// Guide figure (Chapter 21): the tape and lens shelf. One photograph of a
// street eight ways, four across and two down: on a worn videotape, saved as
// a JPEG at quality 6, datamoshed while the camera pans, through a tilt-shift
// lens, blurring in from the bottom, fogged by a light leak, peeling from its
// corner over a dark ground, and in sepia under hairline scratches.
import Ollin
import OllinSamplePhotos

final class TapeAndLens: Sketch {
    override var canvasSize: CanvasSize { .size(880, 470) }

    private var photo = Image(width: 1, height: 1)
    private var mosh: SimField?
    private let tile = 206.0, gap = 12.0, top = 10.0, row = 232.0

    override func setup() {
        photo = SamplePhoto.street.load()
        mosh = makeSimField(.datamosh(amount: 0.7, blockSize: 12, period: 30, seed: 5),
                            width: Int(tile), height: Int(tile))
    }

    private var left: Double { (width - tile * 4 - gap * 3) / 2 }

    private func picture(pan: Double = 0) -> RenderTarget {
        let layer = makeRenderTarget(width: Int(tile), height: Int(tile))
        withTarget(layer) {
            drawImage(photo, in: Rectangle(x: -pan, y: 0, width: tile * 1.3, height: tile * 1.3), fit: .cover)
        }
        return layer
    }

    private func place(_ image: Image, _ column: Int, _ line: Int, _ label: String) {
        let x = left + Double(column) * (tile + gap), y = top + Double(line) * row
        drawImage(image, x, y)
        noStroke()
        fill(Color(white: 0.5))
        textAlign(.center, .top)
        drawText(label, x + tile / 2, y + tile + 4)
    }

    override func draw() {
        background(Color(hex: 0x0C0E13))
        textFont(.system)
        textSize(15)
        // The datamosh runs every frame up to the one shown, the camera panning.
        if let mosh {
            withField(mosh) {
                drawImage(photo, in: Rectangle(x: -Double(frameCount) * 2.5, y: -Double(frameCount),
                                               width: tile * 1.5, height: tile * 1.5), fit: .cover)
            }
        }
        place(picture().filtered(.vhs(smear: 8, jitter: 1.5, damage: 0.8, phase: 4.6)).image, 0, 0, "vhs")
        place(picture().filtered(.jpeg(quality: 6)).image, 1, 0, "jpeg")
        if let mosh { place(mosh.image, 2, 0, "datamosh") }
        place(picture().filtered(.tiltShift(focus: 0.62, band: 0.05, falloff: 0.25, radius: 6)).image, 3, 0, "tiltShift")
        place(picture().filtered(.progressiveBlur(start: 0.35, radius: 9)).image, 0, 1, "progressiveBlur")
        place(picture().filtered(.lightLeak(anchor: Vector2(0.98, 0.3), intensity: 0.45, phase: 1.2, seed: 2)).image,
              1, 1, "lightLeak")
        let x = left + 2 * (tile + gap), y = top + row
        fill(Color(hex: 0x23262D)); drawRect(x, y, tile, tile)
        place(picture().filtered(.pagePeel(amount: 0.3, radius: 0.08)).image, 2, 1, "pagePeel")
        let sepia = picture().filtered(.sepia(amount: 0.9)).filtered(.filmGrain(amount: 0.05))
        let lines = generate(.scratches(count: 12, thickness: 1.3, length: 0.8, flicker: 0.5, phase: 3.1, seed: 4),
                             width: Int(tile), height: Int(tile))
        place(sepia.image, 3, 1, "scratches")
        drawImage(lines.image, left + 3 * (tile + gap), top + row)
    }
}
