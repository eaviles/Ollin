// figure: frame=0
//
// Guide figure (Chapter 13): Wave Function Collapse. Left, the vocabulary:
// each tile's edges carry sockets (pipe or blank), and two tiles may sit
// side by side only when the touching sockets match. Right, a solved grid:
// every neighbor agrees, so the pipes connect everywhere.
import Ollin

final class TilesAgree: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.4)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)
    let accent = Color(hex: 0xE4572E)

    let tiles: [WFCTile] = {
        let blank = WFCTile([0, 0, 0, 0], weight: 1.1)
        let line = WFCTile([1, 0, 1, 0], weight: 1.5).rotations(2)
        let elbow = WFCTile([1, 1, 0, 0], weight: 1.2).rotations(4)
        let tee = WFCTile([1, 1, 1, 0], weight: 0.5).rotations(4)
        return [blank] + line + elbow + tee
    }()
    var grid: [[Int]] = []

    override func setup() {
        seed(2)
        grid = wfc(tiles: tiles, columns: 11, rows: 11) ?? []
    }

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(17)

        // Left: three sample tiles with their sockets marked.
        noStroke()
        fill(ink)
        textAlign(.left, .middle)
        drawText("a tile is its four edge sockets", 60, 48)

        let samples = [WFCTile([1, 0, 1, 0]), WFCTile([1, 1, 0, 0]), WFCTile([1, 1, 1, 0])]
        for (i, tile) in samples.enumerated() {
            let r = Rectangle(x: 78, y: 88 + Double(i) * 112, width: 88, height: 88)
            drawSampleTile(tile, in: r)
        }
        noStroke()
        fill(faint)
        textAlign(.left, .middle)
        drawText("orange marks a pipe socket;", 210, 160)
        drawText("touching edges must match,", 210, 184)
        drawText("pipe to pipe, blank to blank", 210, 208)

        // Right: a solved grid.
        noStroke()
        fill(ink)
        textAlign(.left, .middle)
        drawText("a solved grid: every neighbor agrees", 462, 48)
        let board = Rectangle(x: 462, y: 72, width: 360, height: 360)
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(board)
        strokeCap(.round)
        strokeJoin(.round)
        drawWFC(grid, in: board, padding: .all(10)) { index, cell in
            let sockets = tiles[index].sockets
            guard sockets.contains(where: { $0 != 0 }) else { return }
            stroke(ink)
            strokeWeight(4)
            let c = cell.center
            let mids = [Vector2(cell.center.x, cell.y),
                        Vector2(cell.x + cell.width, cell.center.y),
                        Vector2(cell.center.x, cell.y + cell.height),
                        Vector2(cell.x, cell.center.y)]
            for edge in 0 ..< 4 where sockets[edge] != 0 {
                drawLine(c, mids[edge])
            }
        }
    }

    /// One enlarged tile: its pipe strokes plus a socket dot on each edge,
    /// orange where the edge carries pipe, hollow where it's blank.
    func drawSampleTile(_ tile: WFCTile, in r: Rectangle) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)

        let c = Vector2(r.x + r.width / 2, r.y + r.height / 2)
        let mids = [Vector2(c.x, r.y), Vector2(r.x + r.width, c.y),
                    Vector2(c.x, r.y + r.height), Vector2(r.x, c.y)]
        stroke(ink)
        strokeWeight(7)
        strokeCap(.round)
        for edge in 0 ..< 4 where tile.sockets[edge] != 0 {
            drawLine(c, mids[edge])
        }
        for edge in 0 ..< 4 {
            if tile.sockets[edge] != 0 {
                noStroke()
                fill(accent)
                drawCircle(center: mids[edge], radius: 6)
            } else {
                noFill()
                stroke(faint)
                strokeWeight(2)
                drawCircle(center: mids[edge], radius: 5)
            }
        }
    }
}
