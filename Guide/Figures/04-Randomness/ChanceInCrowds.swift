// figure: frame=0 themed
//
// Guide figure (Chapter 4): percolation across the threshold. One fixed field
// of per-cell random values read at three probabilities: islands below the
// critical value, straining near it, and one spanning cluster just past it,
// lit warm with its traced outline.
import Ollin
import OllinDiagram

final class ChanceInCrowds: Sketch {
    override var canvasSize: CanvasSize { .size(880, 340) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }

    override func draw() {
        background(paper)
        seed(11)
        let columns = 46, rows = 46
        let values = (0 ..< columns * rows).map { _ in random() }

        let tile = 268.0, gap = 12.0
        let left = (width - tile * 3 - gap * 2) / 2
        let panels: [(String, Double)] = [
            ("p = 0.50, islands", 0.50),
            ("p = 0.56, straining", 0.56),
            ("p = 0.63, one cluster spans", 0.63),
        ]

        textFont(.system)
        for (index, panel) in panels.enumerated() {
            let rect = Rectangle(x: left + Double(index) * (tile + gap), y: 16,
                                 width: tile, height: tile)
            noStroke()
            fill(Color(hex: 0x131820))
            drawRect(rect)

            let grid = Percolation(columns: columns, rows: rows,
                                   openCells: values.map { $0 < panel.1 })
            let spanning = grid.spanningClusterIndex
            for k in 0 ..< grid.clusterCount where k != spanning {
                let t = min(Double(grid.clusterSizes[k]) / 200, 1)
                fill(Color.mix(Color(hex: 0x24506B), Color(hex: 0x88C7E8), t))
                for cell in grid.cellRects(of: k, in: rect) { drawRect(cell) }
            }
            if let spanning {
                fill(Color(hex: 0xE8B44A))
                for cell in grid.cellRects(of: spanning, in: rect) { drawRect(cell) }
                stroke(Color(hex: 0xF2E8DC))
                strokeWeight(1.4)
                noFill()
                for loop in grid.outlines(of: spanning, in: rect) {
                    drawPolygon(loop.points)
                }
            }

            noStroke()
            fill(theme.ink(0.62))
            textSize(16)
            textAlign(.center, .top)
            drawText(panel.0, rect.x + rect.width / 2, rect.y + rect.height + 10)
        }
    }
}
