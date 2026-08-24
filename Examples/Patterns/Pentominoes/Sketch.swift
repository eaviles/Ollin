import Ollin

/// Twelve pieces, sixty squares, and one board they all have to fit in.
///
/// A pentomino is five squares joined edge to edge, and there are exactly twelve
/// of them once a piece and its mirror count as one. Together they cover sixty
/// squares, which is why the boards they are set against are always six by ten,
/// five by twelve, four by fifteen, or three by twenty.
///
/// Finding a fit is an exact cover: every square covered once, every piece used
/// once. The search fills whichever square has the fewest ways left to be covered,
/// which is what makes it finish rather than wander, and the seed decides which of
/// the many fits comes back.
///
/// The pieces are drawn as outlines rather than as squares, since `outlines` hands
/// back the boundary of a placed piece as one closed contour. They arrive one at a
/// time over the loop, in the order the search laid them, so the order it worked in
/// is visible. Click for another fit.
@main
final class Pentominoes_Example: Sketch {
    override var loopDuration: Double? { 10 }

    private let columns = 10
    private let rows = 6
    private var fit: [PolyominoPlacement] = []

    override func setup() {
        seed(4)
        solve()
    }

    private func solve() {
        fit = tilePolyominoes(Polyomino.pentominoes,
                              covering: Polyomino.rectangle(columns: columns, rows: rows)) ?? []
    }

    override func mousePressed() {
        seed(Int(random(1, 100_000)))
        solve()
    }

    override func draw() {
        background(Color(hex: 0x0B0E14))

        let cell = min((width - 120) / Double(columns), (height - 220) / Double(rows))
        let origin = Vector2((width - cell * Double(columns)) / 2,
                             (height - cell * Double(rows)) / 2)

        // The board under the pieces, so the squares they are made of stay legible.
        stroke(Color(white: 0.16))
        strokeWeight(1)
        noFill()
        for row in 0 ... rows {
            drawLine(origin.x, origin.y + Double(row) * cell,
                     origin.x + Double(columns) * cell, origin.y + Double(row) * cell)
        }
        for column in 0 ... columns {
            drawLine(origin.x + Double(column) * cell, origin.y,
                     origin.x + Double(column) * cell, origin.y + Double(rows) * cell)
        }

        let arrived = Int((loopProgress(over: 10) * Double(fit.count + 3)).rounded(.down))
        strokeWeight(3)
        strokeJoin(.round)
        for (index, placement) in fit.enumerated() where index < arrived {
            let paint = CosinePalette.rainbow.color(at: Double(placement.piece) / 12)
            fill(paint.withAlpha(0.3))
            stroke(paint)
            for outline in placement.outlines(cellSize: cell, origin: origin) {
                drawShape(Shape(outline.points))
            }

            noStroke()
            fill(Color(white: 0.92))
            textSize(cell * 0.36)
            textAlign(.center, .middle)
            let middle = placement.cells.reduce(Vector2.zero) {
                $0 + Vector2(origin.x + (Double($1.column) + 0.5) * cell,
                             origin.y + (Double($1.row) + 0.5) * cell)
            } / Double(placement.cells.count)
            drawText(Polyomino.pentominoNames[placement.piece], at: middle)
            noFill()
        }

        // The twelve pieces themselves, in a tray under the board, going dim as
        // the search spends them.
        let placed = Set(fit.prefix(arrived).map(\.piece))
        // Sized from the pieces themselves, so the whole set fits the width.
        let spans = Polyomino.pentominoes.map { Double($0.columns) }.reduce(0, +)
        let tray = (width - 140) / (spans + 1.5 * Double(Polyomino.pentominoes.count))
        var penX = 70.0
        let penY = height - 100 - 5 * tray
        for (index, piece) in Polyomino.pentominoes.enumerated() {
            let paint = CosinePalette.rainbow.color(at: Double(index) / 12)
            let used = placed.contains(index)
            if used {
                noFill()
                stroke(paint.withAlpha(0.22))
            } else {
                fill(paint.withAlpha(0.65))
                stroke(paint)
            }
            strokeWeight(2)
            for outline in piece.outlines(cellSize: tray, origin: Vector2(penX, penY)) {
                drawShape(Shape(outline.points))
            }
            penX += Double(piece.columns) * tray + tray * 1.5
        }

        drawCaption("\(min(arrived, fit.count)) of \(fit.count) pentominoes laid on a "
            + "\(columns) by \(rows) board; click for another fit")
    }
}
