// figure: frame=0 probe
//
// Guide figure (Chapter 20): the design filters that work on a picture. One
// bundled photograph, a hillside town, goes behind ribbed glass, under rippling
// water, and onto a creased sheet of paper. A strong refraction samples past
// the layer's edge, so each tile fills its frame corner to corner and `edges`
// is held low.
import Ollin
import OllinSamplePhotos

final class PaperGlassWater: Sketch {
    override var canvasSize: CanvasSize { .size(880, 340) }

    override func draw() {
        background(Color(hex: 0x0C0E13))
        let tile = 268.0, gap = 12.0
        let left = (width - tile * 3 - gap * 2) / 2

        func backdrop() -> RenderTarget {
            let layer = makeRenderTarget(width: 268, height: 268)
            withTarget(layer) {
                drawImage(SamplePhoto.city.load(),
                          in: Rectangle(x: 0, y: 0, width: 268, height: 268), fit: .cover)
            }
            return layer
        }

        // Pushed past their defaults, which are tuned for full-canvas use and
        // read almost identically on a 268-point tile.
        let tiles: [(String, RenderTarget)] = [
            ("flutedGlass", backdrop().filtered(
                .flutedGlass(flutes: 16, distortion: 0.6, edges: 0, angle: 0.35))),
            ("water", backdrop().filtered(
                .water(scale: 0.8, waves: 0.7, refraction: 0.5, edges: 0.4, phase: 2.1))),
            ("paperTexture", backdrop().filtered(
                .paperTexture(contrast: 0.8, crumples: 0.7, folds: 0.9))),
        ]

        textFont(.system)
        let y = 24.0
        for (column, entry) in tiles.enumerated() {
            let x = left + Double(column) * (tile + gap)
            drawImage(entry.1.image, x, y)
            noStroke()
            fill(Color(white: 0.5))
            textSize(17)
            textAlign(.center, .top)
            drawText(entry.0, x + tile / 2, y + tile + 7)
        }
    }
}
