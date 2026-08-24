// figure: frame=0 themed
//
// Docs diagram (Generators/ShapeGrammar.md): one rule, applied until it
// stops. A cell becomes two cells, cut apart by one straight line; a
// sweep offers every cell to the rule, and the design grows out of the
// repetition until the pieces drop under the size the rule asks for.
import Ollin

final class ShapeGrammarLattice: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var soft: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.12) }

    override func draw() {
        background(paper)

        let panels = [Rectangle(x: 70, y: 70, width: 220, height: 220),
                      Rectangle(x: 330, y: 70, width: 220, height: 220),
                      Rectangle(x: 590, y: 70, width: 220, height: 220)]
        let sweeps = [0, 1, 9]
        let titles = ["the start", "after one sweep", "after nine sweeps"]

        for (index, panel) in panels.enumerated() {
            let cell = Rectangle(x: 0, y: 0, width: panel.width, height: panel.height)
            withState {
                translate(panel.x, panel.y)
                noFill()
                stroke(ink)
                strokeWeight(2)
                if sweeps[index] == 0 {
                    drawRect(cell)
                } else {
                    let grammar = ShapeGrammar(start: ShapeGrammar.Piece("cell", cell),
                                               rules: [.cut("cell", into: ("cell", "cell"),
                                                            minimumArea: 2_600)])
                    for piece in grammar.run(generations: sweeps[index], seed: 5) {
                        drawPolyline(piece.corners, closed: true)
                    }
                }
            }
            title(panel, titles[index])
        }

        noStroke()
        fill(ink)
        textFont(OutlineFont.system)
        textSize(21)
        textAlign(.center, .top)
        drawText("one rule: a cell becomes two cells, cut by one straight line",
                 width / 2, 336)
    }

    func title(_ r: Rectangle, _ text: String) {
        noStroke()
        fill(ink)
        textFont(OutlineFont.system)
        textSize(17)
        textAlign(.left, .middle)
        drawText(text, r.x, r.y - 20)
    }
}
