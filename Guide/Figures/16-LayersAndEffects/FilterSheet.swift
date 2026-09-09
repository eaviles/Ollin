// figure: frame=0
//
// Guide figure (Chapter 16): one picture through a sample of the filter
// catalog, one tile per family. A photograph (one of the bundled sample
// photographs) is drawn once into a layer; every tile is that same layer
// through a different filter.
import Ollin
import OllinSamplePhotos

final class FilterSheet: Sketch {
    // Four columns by three rows of square cells, so the square photograph
    // keeps its shape in every tile and the sheet lies across the page.
    override var canvasSize: CanvasSize { .size(1440, 1080) }

    var photograph = Image(width: 1, height: 1)

    override func setup() {
        photograph = SamplePhoto.portrait.load()
    }

    override func draw() {
        background(Color(hex: 0x0C0E13))

        // A face with smooth skin, fine lace, and saturated embroidery, so every
        // filter family has something to bite on.
        let scene = makeRenderTarget(width: 1080, height: 1080)
        withTarget(scene) {
            drawImage(photograph, in: Rectangle(x: 0, y: 0, width: 1080, height: 1080))
        }

        let tiles: [(String, Filter?)] = [
            ("the layer", nil),
            ("gaussianBlur", .gaussianBlur(radius: 22)),
            ("bloom", .bloom(threshold: 0.5, amount: 1.6, radius: 22)),
            ("posterize", .posterize(levels: 4)),
            ("duotone", .duotone(dark: Color(hex: 0x1B1040), light: Color(hex: 0xFFD98A))),
            ("halftone", .halftone(scale: 52)),
            ("pixelate", .pixelate(size: 26)),
            ("edges", .edges(amount: 2.2)),
            ("oilPaint", .oilPaint(radius: 5)),
            ("glitch", .glitch(amount: 0.12, seed: 3)),
            ("swirl", .swirl(angle: 2.6, radius: 0.55)),
            ("crosshatch", .crosshatch(scale: 90, foreground: Color(hex: 0x1B1040),
                                       background: Color(hex: 0xF3EBDD))),
        ]

        let cols = 4, rows = 3
        let gutter = width * 0.012
        let cell = min((width - gutter * Double(cols + 1)) / Double(cols),
                       (height - gutter * Double(rows + 1)) / Double(rows))
        let cellW = cell, cellH = cell
        let left = (width - cellW * Double(cols) - gutter * Double(cols + 1)) / 2
        let top = (height - cellH * Double(rows) - gutter * Double(rows + 1)) / 2
        let font = OutlineFont.system
        for (i, tile) in tiles.enumerated() {
            let x = left + gutter + Double(i % cols) * (cellW + gutter)
            let y = top + gutter + Double(i / cols) * (cellH + gutter)
            let layer = tile.1.map { scene.filtered($0) } ?? scene
            drawImage(layer.image, in: Rectangle(x: x, y: y, width: cellW, height: cellH), fit: .cover)
            withState {
                blendMode(.normal)
                noStroke()
                fill(Color(white: 0, alpha: 0.55))
                drawRect(x, y + cellH - 26, cellW, 26)
                fill(.white)
                textFont(font); textSize(14); textAlign(.left, .middle)
                drawText(tile.0, x + 8, y + cellH - 13)
            }
        }
    }
}
