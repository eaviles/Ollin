// figure: frame=0 themed
//
// Guide figure (Chapter 7): a parquet deformation. Above, one sheet whose tile
// runs from a plain square on the left to an interlocking key on the right,
// every piece still meeting its neighbors exactly. Below, five tiles lifted out
// of that run and stood on their own, so the drift is legible as a sequence of
// shapes rather than only as a texture.
import Ollin
import OllinDiagram

final class ParquetRun: Sketch {
    override var canvasSize: CanvasSize { .size(880, 620) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    let cool = Color(hex: 0x2E5E6B)
    let warm = Color(hex: 0xE0A33C)

    let start = ParquetDeformation.Profile.straight
    let end = ParquetDeformation.Profile.tooth(depth: 0.3, width: 0.44)

    override func draw() {
        background(paper)
        textSize(21)

        let sheetFrame = Rectangle(x: 90, y: 60, width: 700, height: 350)
        let sheet = ParquetDeformation(grid: Grid(in: sheetFrame, columns: 14, rows: 7),
                                       from: start, to: end)
        noStroke()
        for tile in sheet.tiles {
            fill(Color.mix(cool, warm, tile.amount).withAlpha(0.55))
            drawShape(tile.shape)
        }
        stroke(ink)
        strokeWeight(1.6)
        strokeJoin(.round)
        for edge in sheet.edges {
            drawPolyline(edge.points, closed: false)
        }

        noStroke()
        fill(ink)
        textAlign(.center, .top)
        drawText("one sheet: the tile runs from square to key, and nothing comes apart",
                 sheetFrame.center.x, sheetFrame.y + sheetFrame.height + 18)

        let amounts = [0.0, 0.25, 0.5, 0.75, 1.0]
        for (i, amount) in amounts.enumerated() {
            let box = Rectangle(x: 120 + Double(i) * 130, y: 470, width: 96, height: 96)
            drawTile(at: amount, in: box)
        }
    }

    /// One tile of the run on its own: a single-cell lattice held at a fixed
    /// amount, so the piece is exactly what the sheet above puts at that point.
    func drawTile(at amount: Double, in box: Rectangle) {
        let one = ParquetDeformation(grid: Grid(in: box, columns: 1, rows: 1),
                                     from: start, to: end) { _ in amount }
        guard let tile = one.tiles.first else { return }

        noStroke()
        fill(Color.mix(cool, warm, amount).withAlpha(0.55))
        drawShape(tile.shape)
        stroke(ink)
        strokeWeight(1.6)
        strokeJoin(.round)
        drawPolyline(tile.contour.points, closed: true)

        noStroke()
        fill(ink)
        textAlign(.center, .top)
        drawText(String(format: "%.2f", amount), box.center.x, box.y + box.height + 26)
    }
}
