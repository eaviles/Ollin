// figure: frame=0
//
// Guide figure (Chapter 21): bubble wrap over a picture. The left panel is a
// bundled photograph as it is; the right panel is the same photograph under
// the bubble wrap filter, every bubble a lens with its arcs and highlight.
import Ollin
import OllinSamplePhotos

final class BubbleWrap: Sketch {
    override var canvasSize: CanvasSize { .size(880, 470) }

    override func draw() {
        background(Color(hex: 0x0C0E13))
        let tile = 420.0, gap = 20.0, top = 14.0
        let left = (width - tile * 2 - gap) / 2
        let photo = SamplePhoto.city.load()

        func picture() -> RenderTarget {
            let layer = makeRenderTarget(width: Int(tile), height: Int(tile))
            withTarget(layer) {
                drawImage(photo, in: Rectangle(x: 0, y: 0, width: tile, height: tile), fit: .cover)
            }
            return layer
        }

        drawImage(picture().image, left, top)
        drawImage(picture().filtered(.bubbleWrap(radius: 22, gap: 5, lightAngle: -2.2)).image,
                  left + tile + gap, top)

        textFont(.system)
        noStroke()
        fill(Color(white: 0.5))
        textSize(17)
        textAlign(.center, .top)
        drawText("the picture", left + tile / 2, top + tile + 10)
        drawText("under bubble wrap", left + tile * 1.5 + gap, top + tile + 10)
    }
}
