// figure: frame=0
//
// Guide diagram (Chapter 7): polyominoes. The twelve pentominoes along the top,
// one fit of all twelve into a six by ten board on the left, and on the right the
// board that refuses dominoes, with the coloring that says why.
import Ollin

final class FittingPieces: Sketch {
    override var canvasSize: CanvasSize { .size(880, 560) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let accent = Color(hex: 0xE07A5F)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)

    override func draw() {
        background(paper)

        catalog(at: Vector2(64, 62), cellSize: 15)

        let fit = Rectangle(x: 64, y: 210, width: 400, height: 240)
        let cut = Rectangle(x: 528, y: 210, width: 288, height: 240)
        board(fit)
        cutBoard(cut)

        label("the twelve pentominoes", at: Vector2(64, 42))
        label("all twelve, fitted", at: Vector2(fit.x, fit.y - 20))
        label("this one refuses dominoes", at: Vector2(cut.x, cut.y - 20))

        fill(ink)
        noStroke()
        textSize(21)
        textAlign(.center, .top)
        drawText("every cell covered once, every piece used once", width / 2, 476)
        textSize(17)
        fill(Color(hex: 0x6E6A63))
        drawText("a domino always covers one light square and one dark one, and this board has two more light",
                 width / 2, 510)
    }

    /// The pieces themselves, drawn as outlines.
    func catalog(at origin: Vector2, cellSize: Double) {
        var penX = origin.x
        strokeWeight(2)
        for piece in Polyomino.pentominoes {
            fill(Color(white: 0.86))
            stroke(ink)
            for outline in piece.outlines(cellSize: cellSize, origin: Vector2(penX, origin.y)) {
                drawShape(Shape(outline.points))
            }
            penX += Double(piece.columns) * cellSize + cellSize * 1.6
        }
    }

    /// One fit of the twelve into a six by ten board.
    func board(_ box: Rectangle) {
        let columns = 10, rows = 6
        let cell = min(box.width / Double(columns), box.height / Double(rows))
        let origin = Vector2(box.x, box.y + (box.height - cell * Double(rows)) / 2)
        guard let fit = tilePolyominoes(Polyomino.pentominoes,
                                        covering: .rectangle(columns: columns, rows: rows)) else { return }
        strokeWeight(2)
        for (index, placement) in fit.enumerated() {
            fill(Color(white: 0.94 - Double(index % 3) * 0.09))
            stroke(ink)
            for outline in placement.outlines(cellSize: cell, origin: origin) {
                drawShape(Shape(outline.points))
            }
        }
    }

    /// A six by six board with two opposite corners taken out, colored the way the
    /// argument is usually told.
    func cutBoard(_ box: Rectangle) {
        let side = 6
        let cell = min(box.width, box.height) / Double(side)
        let origin = Vector2(box.x, box.y + (box.height - cell * Double(side)) / 2)
        noStroke()
        for row in 0 ..< side {
            for column in 0 ..< side {
                let gone = (column == 0 && row == 0) || (column == side - 1 && row == side - 1)
                let dark = (column + row) % 2 == 0
                fill(gone ? paper : Color(white: dark ? 0.72 : 0.93))
                drawRect(Rectangle(x: origin.x + Double(column) * cell,
                                   y: origin.y + Double(row) * cell,
                                   width: cell, height: cell))
                if gone {
                    noFill()
                    stroke(accent)
                    strokeWeight(2)
                    drawRect(Rectangle(x: origin.x + Double(column) * cell + 3,
                                       y: origin.y + Double(row) * cell + 3,
                                       width: cell - 6, height: cell - 6))
                    noStroke()
                }
            }
        }
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(Rectangle(x: origin.x, y: origin.y, width: cell * Double(side), height: cell * Double(side)))
    }

    func label(_ text: String, at point: Vector2) {
        noStroke()
        fill(ink)
        textSize(17)
        textAlign(.left, .middle)
        drawText(text, point.x, point.y)
    }
}
