import Ollin

/// The design filters: six image effects in the same family as the
/// design-pattern generators. Three read the layer's alpha shape (draw a
/// shape, filter it): liquid chrome, a thermal heatmap, and gem smoke. Three
/// transform the whole layer: fluted glass, rippling water, and a paper sheet
/// the image is laid onto.
///
/// Each takes a `phase` fed `time` where it animates; the top row's shape is
/// a plain heart drawn into a transparent layer.
@main
final class DesignFilters_Example: Sketch {
    private let labelFont = OutlineFont.system

    override func draw() {
        background(Color(white: 0.06))
        let t = time

        // The alpha shape the top-row filters read.
        func heartLayer() -> RenderTarget {
            let layer = renderTarget()
            withTarget(layer) {
                noStroke(); fill(.white)
                drawHeart(width / 2, height / 2, width * 0.5)
            }
            return layer
        }
        // The colorful backdrop the bottom-row filters transform.
        let backdrop = generate(.meshGradient(phase: 2.4))

        let tiles: [(String, RenderTarget)] = [
            ("liquidMetal", heartLayer().filtered(.liquidMetal(phase: t))),
            ("heatmap", heartLayer().filtered(.heatmap(phase: t))),
            ("gemSmoke", heartLayer().filtered(.gemSmoke(phase: t))),
            ("flutedGlass", backdrop.filtered(.flutedGlass(angle: 0.35))),
            ("water", backdrop.filtered(.water(phase: t))),
            ("paperTexture", heartLayer().filtered(.paperTexture())),
        ]

        let gutter = width * 0.015
        let g = grid(columns: 3, rows: 2, padding: .all(gutter), gutter: gutter)
        for (cell, tile) in zip(g.cells, tiles) {
            let rect = cell.frame
            drawImage(tile.1.image, in: rect)
            withState {
                fill(Color(white: 0, alpha: 0.55)); noStroke()
                drawRect(rect.x, rect.y + rect.height - 32, rect.width, 32)
                fill(.white)
                textFont(labelFont); textSize(18); textAlign(.left, .middle)
                drawText(tile.0, rect.x + 10, rect.y + rect.height - 16)
            }
        }
    }
}
