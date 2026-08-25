// figure: frame=0 themed
//
// Guide diagram (Chapter 12): how a spatial index finds neighbors. The plane is
// cut into cells one perception radius across, so every true neighbor of the
// dark boid has to be in the block of nine cells around it. Everything outside
// that block is never measured at all.
import Ollin
import OllinDiagram

final class NeighborCells: Sketch {
    override var canvasSize: CanvasSize { .size(880, 440) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.4) }
    var soft: Color { theme.ink(0.12) }
    var accent: Color { theme.accent }

    override func draw() {
        background(paper)
        textSize(17)
        seed(4)

        let cell = 78.0
        let origin = Vector2(90, 40)
        let columns = 8, rows = 4
        let field = Rectangle(x: origin.x, y: origin.y,
                              width: Double(columns) * cell, height: Double(rows) * cell)

        // The flock, and the one creature asking the question.
        var flock: [Vector2] = []
        for _ in 0 ..< 150 { flock.append(randomVector(in: field.inset(by: 6))) }
        let focal = origin + Vector2(cell * 3.5, cell * 2.5)
        let index = SpatialIndex(flock, cellSize: cell)

        // The block of nine cells the search reads.
        let column = Int((focal.x - origin.x) / cell), row = Int((focal.y - origin.y) / cell)
        noStroke()
        fill(theme.accent(0.07))
        drawRect(corner: origin + Vector2(Double(column - 1) * cell, Double(row - 1) * cell),
                 width: cell * 3, height: cell * 3)

        // The cells themselves.
        stroke(soft)
        strokeWeight(1.5)
        noFill()
        for c in 0 ... columns {
            drawLine(origin + Vector2(Double(c) * cell, 0),
                     origin + Vector2(Double(c) * cell, Double(rows) * cell))
        }
        for r in 0 ... rows {
            drawLine(origin + Vector2(0, Double(r) * cell),
                     origin + Vector2(Double(columns) * cell, Double(r) * cell))
        }

        // How far the creature can see: one cell.
        stroke(faint)
        strokeWeight(2)
        drawCircle(center: focal, radius: cell)

        // Everyone else, then the neighbors it really found.
        let found = Set(index.neighbors(of: focal, within: cell))
        noStroke()
        for (i, p) in flock.enumerated() where !found.contains(i) {
            fill(soft)
            drawCircle(center: p, radius: 5)
        }
        for i in found {
            fill(accent)
            drawCircle(center: flock[i], radius: 6)
        }

        noStroke()
        fill(ink)
        drawCircle(center: focal, radius: 8)

        label("nine cells read", origin + Vector2(Double(column - 1) * cell + cell * 1.5,
                                                  Double(row - 1) * cell - 16), color: accent)
        label("never measured", origin + Vector2(cell * 6.6, cell * 0.5))

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("a cell one radius across: every neighbor is in the block of nine",
                 width / 2, 382)
    }

    func label(_ text: String, _ at: Vector2, color: Color? = nil) {
        noStroke()
        fill(color ?? faint)
        textAlign(.center, .middle)
        drawText(text, at: at)
    }
}
