// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Drawing.md, drawRhombus): the diamond is
// centered, its width and height are the full diagonals, and cornerRadius
// rounds it toward a circle without growing the footprint.
import Ollin

final class DrawRhombus: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var wash: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.10) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        let cy = 140.0

        // Tall: the diagonals are the full width and height.
        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawRhombus(176, cy, 130, 196)
        stroke(accent)
        strokeWeight(2)
        drawLine(176 - 65, cy, 176 + 65, cy)
        drawLine(176, cy - 98, 176, cy + 98)
        caption("width and height, the diagonals", 176)

        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawRhombus(452, cy, 196, 130)
        dot(452, cy)
        caption("wide", 452)

        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawRhombus(722, cy, 170, 170, cornerRadius: 40)
        dot(722, cy)
        caption("cornerRadius: 40", 722)
    }

    func dot(_ x: Double, _ y: Double) {
        noStroke()
        fill(accent)
        drawCircle(x, y, 3.5)
    }

    func caption(_ text: String, _ x: Double) {
        noStroke()
        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText(text, x, 262)
    }
}
