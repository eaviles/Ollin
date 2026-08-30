// figure: frame=0 probe
//
// Guide figure (Chapter 16): the two kinds of design filter. The top row starts
// from one plain white heart on a transparent layer, and three filters read only
// that silhouette to build a material out of it. The bottom row starts from a
// picture, and three filters put something in front of it.
import Ollin

final class DesignFilters: Sketch {
    override var canvasSize: CanvasSize { .size(880, 706) }

    override func draw() {
        background(Color(hex: 0x0C0E13))
        let tile = 268.0, gap = 12.0
        let left = (width - tile * 3 - gap * 2) / 2

        // The silhouette the top row reads: nothing but a shape and its alpha.
        func heart() -> RenderTarget {
            let layer = makeRenderTarget(width: 268, height: 268)
            withTarget(layer) {
                noStroke()
                fill(.white)
                drawHeart(134, 140, 190)
            }
            return layer
        }

        // A picture for the bottom row to work on. A continuous field rather than
        // a pattern of discrete marks: a strong refraction samples past the
        // layer's edge, and on a field that reads as a stretch instead of as a
        // stray dark blot.
        func backdrop() -> RenderTarget {
            generate(.meshGradient(
                colors: [Color(hex: 0xE4572E), Color(hex: 0x2B6C8C),
                         Color(hex: 0xE8B44A), Color(hex: 0x7C3B5E)],
                phase: 5.1),
                width: 268, height: 268)
        }

        let rows: [(String, [(String, RenderTarget)])] = [
            ("these read the shape", [
                ("liquidMetal", heart().filtered(.liquidMetal(phase: 2.1))),
                ("heatmap", heart().filtered(.heatmap(phase: 2.1))),
                ("gemSmoke", heart().filtered(.gemSmoke(phase: 2.1))),
            ]),
            // Pushed past their defaults, which are tuned for full-canvas use and
            // read almost identically on a 268-point tile.
            ("these read the picture", [
                // `edges` held low on both: pushed hard, these sample past the
                // layer and drag its transparent surround in as black.
                ("flutedGlass", backdrop().filtered(
                    .flutedGlass(flutes: 16, distortion: 0.6, edges: 0, angle: 0.35))),
                ("water", backdrop().filtered(
                    .water(scale: 0.8, waves: 0.7, refraction: 0.5, edges: 0.4,
                           phase: 2.1))),
                ("paperTexture", backdrop().filtered(
                    .paperTexture(contrast: 0.8, crumples: 0.7, folds: 0.9))),
            ]),
        ]

        textFont(.system)
        for (rowIndex, row) in rows.enumerated() {
            let y = 44 + Double(rowIndex) * (tile + 76)
            noStroke()
            fill(Color(white: 0.62))
            textSize(19)
            textAlign(.left, .bottom)
            drawText(row.0, left, y - 10)

            for (columnIndex, tileEntry) in row.1.enumerated() {
                let x = left + Double(columnIndex) * (tile + gap)
                drawImage(tileEntry.1.image, x, y)
                fill(Color(white: 0.5))
                textSize(17)
                textAlign(.center, .top)
                drawText(tileEntry.0, x + tile / 2, y + tile + 7)
            }
        }
    }
}
