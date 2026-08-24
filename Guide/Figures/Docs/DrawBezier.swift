// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Drawing.md, drawBezier): one quadratic curve
// from start to end, leaning toward its single control point without ever
// reaching it, the control legs ghosted behind the stroke.
import Ollin

final class DrawBezier: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var soft: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.22) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        let start = Vector2(150, 244)
        let control = Vector2(444, 46)
        let end = Vector2(742, 244)

        // The control legs, ghosted: the curve leans toward where they meet.
        stroke(soft)
        strokeWeight(1.5)
        drawLine(start, control)
        drawLine(control, end)

        stroke(ink)
        strokeWeight(4)
        drawBezier(start, control, end)

        noStroke()
        fill(ink)
        drawCircle(start.x, start.y, 4.5)
        drawCircle(end.x, end.y, 4.5)
        fill(accent)
        drawCircle(control.x, control.y, 4.5)

        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText("start", start.x, start.y + 14)
        drawText("end", end.x, end.y + 14)
        fill(accent)
        textAlign(.center, .bottom)
        drawText("control: leaned toward, never reached", control.x, control.y - 12)
    }
}
