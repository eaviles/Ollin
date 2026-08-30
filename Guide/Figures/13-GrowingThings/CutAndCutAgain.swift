// figure: frame=0 themed
//
// Guide figure (Chapter 13): a shape grammar cutting up a frame. One rule, a
// cell becomes two cells parted by a straight line, applied to every cell at
// once. Four panels show the design after one, three, six, and nine sweeps.
// Warm cells are still big enough for the rule to take, so the color drains
// away as the design finishes: rewriting symbols grows forever, and rewriting
// shapes in place runs out of room.
import Ollin
import OllinDiagram

final class CutAndCutAgain: Sketch {
    override var canvasSize: CanvasSize { .size(880, 280) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var accent: Color { theme.accent }

    override func draw() {
        background(paper)
        textSize(16)

        let smallest = 900.0
        for (slot, sweeps) in [1, 3, 6, 9].enumerated() {
            let panel = Rectangle(x: 26 + Double(slot) * 212, y: 26, width: 186, height: 186)
            let grammar = ShapeGrammar.iceRay(in: panel, minArea: smallest, balance: 0.3)
            let cells = grammar.run(generations: sweeps, seed: 6)

            noFill()
            strokeWeight(1.2)
            for cell in cells {
                stroke(cell.area >= smallest ? accent : ink)
                drawPolyline(cell.corners, closed: true)
            }

            noStroke()
            fill(ink)
            textAlign(.center, .top)
            let left = cells.filter { $0.area >= smallest }.count
            drawText("\(sweeps) \(sweeps == 1 ? "sweep" : "sweeps"): \(cells.count) cells"
                     + (left == 0 ? ", done" : ""),
                     panel.center.x, panel.y + panel.height + 16)
        }
    }
}
