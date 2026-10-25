// figure: frame=0
//
// Guide figure (Chapter 21): three filters that read the layer as something
// other than a picture. A photograph of a street as a red-and-cyan anaglyph
// at one parallax, under a heat mirage with the facades mirrored into the
// road, and read by a schlieren knife as a density field.
import Ollin
import OllinSamplePhotos

final class OpticalLooks: Sketch {
    override var canvasSize: CanvasSize { .size(880, 340) }

    override func draw() {
        background(Color(hex: 0x0C0E13))
        let tile = 276.0, gap = 16.0, top = 14.0
        let left = (width - tile * 3 - gap * 2) / 2
        let photo = SamplePhoto.city.load()

        func picture() -> RenderTarget {
            let layer = makeRenderTarget(width: Int(tile), height: Int(tile))
            withTarget(layer) {
                drawImage(photo, in: Rectangle(x: 0, y: 0, width: tile, height: tile), fit: .cover)
            }
            return layer
        }

        drawImage(picture().filtered(.anaglyph(separation: 9)).image, left, top)
        drawImage(picture().filtered(.mirage(horizon: 0.72, faults: 0.5, amount: 10, phase: 2.1)).image,
                  left + tile + gap, top)
        drawImage(picture().filtered(.gaussianBlur(radius: 5)).filtered(.schlieren(angle: 0.5, amount: 1.2)).image,
                  left + (tile + gap) * 2, top)

        textFont(.system)
        noStroke()
        fill(Color(white: 0.5))
        textSize(17)
        textAlign(.center, .top)
        drawText("anaglyph", left + tile / 2, top + tile + 10)
        drawText("mirage", left + tile * 1.5 + gap, top + tile + 10)
        drawText("schlieren", left + tile * 2.5 + gap * 2, top + tile + 10)
    }
}
