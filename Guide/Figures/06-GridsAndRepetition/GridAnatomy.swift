// figure: frame=0
//
// Guide diagram (Chapter 6): the anatomy of a Grid. Left, the cells: padding
// insets the whole grid from its rectangle, gutter is the gap between tiles,
// and each cell knows its frame and center. Right, the points: a dot per cell
// by default, or a lattice spanning the edges with `.spanning`.
import Ollin

final class GridAnatomy: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.28)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.08)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(19)

        drawCellsPanel(Rectangle(x: 80, y: 100, width: 330, height: 330))
        drawPointsPanel(Rectangle(x: 500, y: 100, width: 145, height: 145),
                        distribution: .center, note: "points  (.center)")
        drawPointsPanel(Rectangle(x: 500, y: 285, width: 145, height: 145),
                        distribution: .spanning, note: "points  (.spanning)")

        noStroke()
        fill(ink)
        textAlign(.center, .top)
        textSize(21)
        drawText("one grid, two things to loop: cells to tile, points to dot", width / 2, 480)
    }

    func drawCellsPanel(_ rect: Rectangle) {
        let grid = Grid(in: rect, columns: 4, rows: 4, padding: 34, gutter: 14)

        noFill()
        stroke(faint)
        strokeWeight(2)
        drawRect(rect)

        for cell in grid.cells {
            noStroke()
            fill(soft)
            drawRect(cell.frame)
        }

        // One cell called out, with its frame and center.
        let called = grid.cell(column: 2, row: 1)
        noFill()
        stroke(accent)
        strokeWeight(3)
        drawRect(called.frame)
        noStroke()
        fill(accent)
        drawCircle(center: called.center, radius: 5)

        // Callouts.
        noStroke()
        fill(ink)
        textAlign(.left, .middle)
        let firstCell = grid.cell(column: 0, row: 0)
        stroke(ink)
        strokeWeight(1.5)
        drawLine(rect.x + 8, rect.y + 14, rect.x - 14, rect.y - 24)
        noStroke()
        textAlign(.center, .bottom)
        drawText("padding", rect.x + 8, rect.y - 30)

        let gapX = firstCell.frame.x + firstCell.frame.width + grid.gutter / 2
        stroke(ink)
        strokeWeight(1.5)
        drawLine(gapX, firstCell.frame.y + 10, gapX + 26, rect.y - 24)
        noStroke()
        drawText("gutter", gapX + 30, rect.y - 30)

        textAlign(.left, .middle)
        drawText("cell.frame", called.frame.x + called.frame.width + 12, called.frame.y + 8)
        fill(accent)
        drawText("cell.center", called.frame.x + called.frame.width + 12, called.center.y)

        fill(ink)
        textAlign(.center, .top)
        drawText("cells", rect.center.x, rect.y + rect.height + 14)
    }

    func drawPointsPanel(_ rect: Rectangle, distribution: Grid.Distribution, note: String) {
        let grid = Grid(in: rect, columns: 4, rows: 4, distribution: distribution)

        noFill()
        stroke(faint)
        strokeWeight(2)
        drawRect(rect)

        noStroke()
        fill(distribution == .center ? ink : accent)
        for point in grid.points {
            drawCircle(center: point.position, radius: 6)
        }

        fill(ink)
        textAlign(.left, .middle)
        drawText(note, rect.x + rect.width + 24, rect.center.y)
    }
}
