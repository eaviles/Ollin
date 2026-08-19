// figure: frame=0
//
// Guide diagram (Chapter 7): why Truchet tiles always connect. The arc tile
// only ever touches its cell at the four edge midpoints, so either spin of a
// neighbor lands on the same doorway, and marks flow across borders.
import Ollin

final class TruchetJoins: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.28)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(19)

        // Left: the tile's two spins, doorways marked.
        drawTile(Rectangle(x: 80, y: 120, width: 150, height: 150), flipped: false)
        drawTile(Rectangle(x: 260, y: 120, width: 150, height: 150), flipped: true)
        noStroke()
        fill(ink)
        textAlign(.center, .top)
        drawText("one tile, two spins: the arcs", 245, 300)
        drawText("always end at the edge midpoints", 245, 328)

        // Right: neighbors join at the shared midpoints, whatever their spins.
        let spins = [false, true, true, false, false, true]
        let cells = Grid(in: Rectangle(x: 520, y: 95, width: 300, height: 200),
                         columns: 3, rows: 2).cells
        for (i, cell) in cells.enumerated() {
            drawTile(cell.frame, flipped: spins[i], doorways: false)
        }
        noFill()
        stroke(faint)
        strokeWeight(2)
        for cell in cells { drawRect(cell.frame) }
        // Ring the interior doorways where neighbors meet.
        stroke(accent)
        strokeWeight(2.5)
        for cell in cells {
            let f = cell.frame
            if cell.column < 2 { drawCircle(f.x + f.width, f.y + f.height / 2, 11) }
            if cell.row < 1 { drawCircle(f.x + f.width / 2, f.y + f.height, 11) }
        }
        noStroke()
        fill(ink)
        textAlign(.center, .top)
        drawText("random spins still meet", 670, 300)
        drawText("at every doorway", 670, 328)

        textAlign(.center, .top)
        textSize(21)
        drawText("agree at the edges, and any arrangement connects", width / 2, 440)
    }

    /// One arc tile at the chosen spin, its arcs ending on the cell's four
    /// edge midpoints.
    func drawTile(_ rect: Rectangle, flipped: Bool, doorways: Bool = true) {
        if doorways {
            noFill()
            stroke(faint)
            strokeWeight(2)
            drawRect(rect)
        }

        noFill()
        stroke(ink)
        strokeWeight(5)
        strokeCap(.round)
        for arc in Truchet.contours(in: rect, tile: .arcs, flipped: flipped) {
            drawPolyline(arc.points)
        }

        if doorways {
            noStroke()
            fill(accent)
            drawCircle(rect.x + rect.width / 2, rect.y, 6)
            drawCircle(rect.x + rect.width / 2, rect.y + rect.height, 6)
            drawCircle(rect.x, rect.y + rect.height / 2, 6)
            drawCircle(rect.x + rect.width, rect.y + rect.height / 2, 6)
        }
    }
}
