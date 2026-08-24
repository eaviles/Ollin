// figure: frame=0 themed
//
// Guide figure (Chapter 7): the two built-in Truchet tiles over the same
// grid. Arcs join into meandering loops; diagonals read as a maze.
import Ollin

final class TruchetTiles: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    let panel = Color(hex: 0x1C1F26)

    override func draw() {
        background(paper)
        textSize(21)

        drawTilePanel(Rectangle(x: 80, y: 90, width: 330, height: 330),
                      tile: .arcs, note: ".arcs")
        drawTilePanel(Rectangle(x: 470, y: 90, width: 330, height: 330),
                      tile: .diagonals, note: ".diagonals")
    }

    func drawTilePanel(_ rect: Rectangle, tile: Truchet.Tile, note: String) {
        randomSeed(4)
        noStroke()
        fill(panel)
        drawRect(rect, cornerRadius: 10)

        stroke(.white)
        strokeWeight(7)
        strokeCap(.round)
        noFill()
        drawTruchet(in: rect.inset(by: 26), columns: 8, rows: 8, tile: tile)

        noStroke()
        fill(ink)
        textAlign(.center, .top)
        drawText(note, rect.center.x, rect.y + rect.height + 16)
    }
}
