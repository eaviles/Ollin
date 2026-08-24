// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Drawing.md, drawVesica): the pointed lens of
// two overlapping circles. The tips ride the longer axis, so a tall lens
// points up and down and a wide one left and right; cornerRadius eases the
// tips toward an ellipse.
import Ollin

final class DrawVesica: Sketch {
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

        // Tall: the tips sit on the longer axis.
        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawVesica(176, cy, 110, 200)
        dot(176, cy - 100)
        dot(176, cy + 100)
        caption("tall: tips up and down", 176)

        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawVesica(452, cy, 220, 116)
        dot(452 - 110, cy)
        dot(452 + 110, cy)
        caption("wide: tips left and right", 452)

        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawVesica(722, cy, 220, 116, cornerRadius: 30)
        caption("cornerRadius: 30", 722)
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
