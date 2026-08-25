// figure: frame=0 themed
//
// Guide figure (Chapter 7): one hitomezashi design, both faces. Left, the
// stitches alone: dashes phased by one bit per line, joining into steps and
// loops. Right, the same design with its two-tone parity fill underneath,
// every tone boundary landing exactly on a stitch.
import Ollin
import OllinDiagram

final class HitomezashiFaces: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    let cloth = Color(hex: 0x101A33)
    let thread = Color(hex: 0xF2E9DC)

    override func draw() {
        background(paper)
        textSize(21)

        drawPanel(Rectangle(x: 80, y: 90, width: 330, height: 330),
                  filled: false, note: ".stitches")
        drawPanel(Rectangle(x: 470, y: 90, width: 330, height: 330),
                  filled: true, note: ".stitches over .parities")
    }

    func drawPanel(_ rect: Rectangle, filled: Bool, note: String) {
        randomSeed(11)
        noStroke()
        fill(cloth)
        drawRect(rect, cornerRadius: 10)

        let design = hitomezashi(in: rect.inset(by: 26), columns: 12, rows: 12)

        if filled {
            for (cell, tone) in zip(design.grid.cells, design.parities) {
                fill(tone ? Color(hex: 0x2C4A7F) : Color(hex: 0x18264A))
                drawRect(cell.frame)
            }
        }

        stroke(thread)
        strokeWeight(5)
        strokeCap(.round)
        for dash in design.stitches {
            drawPolyline(dash.points, closed: false)
        }

        noStroke()
        fill(ink)
        textAlign(.center, .top)
        drawText(note, rect.center.x, rect.y + rect.height + 16)
    }
}
