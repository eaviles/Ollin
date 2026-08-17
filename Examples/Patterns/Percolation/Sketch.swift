import Ollin

/// **Percolation**: chance, acting together.
///
/// Every cell rolled one fixed random value at the start. A slowly breathing
/// probability decides which cells count as open, so the same landscape floods
/// and drains as the threshold sweeps. Below the critical probability (about
/// 0.5927) the open cells are scattered islands; just past it, one giant
/// cluster suddenly reaches from the top edge to the bottom. Clusters are
/// tinted by size, and the spanning cluster, when it exists, lights up warm
/// with its traced outline.
///
/// Try it: hold `probability` still just under 0.59 and watch how large the
/// islands get without ever connecting.
@main
final class Percolation_Example: Sketch {
    private let columns = 72, rows = 72
    private var values: [Double] = []

    override func setup() {
        seed(7)
        values = (0 ..< columns * rows).map { _ in random() }
    }

    override func draw() {
        background(Color(hex: 0x10141B))

        let p = Percolation.criticalProbability + 0.05 * sin(time * 0.3)
        let grid = Percolation(columns: columns, rows: rows,
                               openCells: values.map { $0 < p })
        let area = canvasRectangle.inset(by: .all(70))
        let spanning = grid.spanningClusterIndex

        noStroke()
        for k in 0 ..< grid.clusterCount {
            if k == spanning { continue }
            let size = Double(grid.clusterSizes[k])
            let t = min(size / 400, 1)
            fill(Color.mix(Color(hex: 0x24506B), Color(hex: 0x88C7E8), t: t))
            for cell in grid.cellRects(of: k, in: area) { drawRect(cell) }
        }
        if let spanning {
            fill(Color(hex: 0xE8B44A))
            for cell in grid.cellRects(of: spanning, in: area) { drawRect(cell) }
            stroke(Color(hex: 0xF2E8DC))
            strokeWeight(2)
            noFill()
            for loop in grid.outlines(of: spanning, in: area) {
                drawPolygon(loop.points)
            }
        }

        drawCaption(String(format: "p = %.3f, %@",
                           p, spanning == nil ? "islands" : "the grid spans"))
    }
}
