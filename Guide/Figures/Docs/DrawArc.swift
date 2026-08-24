// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Drawing.md, drawArc): the same three-quarter
// sweep under the three closure modes, with the angle sense annotated on the
// first: angles start at the positive x-axis and increase clockwise, because
// y grows downward.
import Ollin

final class DrawArc: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var wash: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.10) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        let cy = 150.0
        let rx = 105.0, ry = 78.0
        let sweepStart = 0.0, sweepStop = 1.5 * Double.pi

        panel(cx: 176, cy: cy, rx: rx, ry: ry,
              start: sweepStart, stop: sweepStop, mode: .open, name: ".open")
        panel(cx: 452, cy: cy, rx: rx, ry: ry,
              start: sweepStart, stop: sweepStop, mode: .chord, name: ".chord")
        panel(cx: 722, cy: cy, rx: rx, ry: ry,
              start: sweepStart, stop: sweepStop, mode: .pie, name: ".pie")

        // The angle sense, on the first panel: 0 sits on +x, and the sweep
        // runs clockwise on the y-down canvas.
        let cx = 176.0
        stroke(accent)
        strokeWeight(2)
        drawLine(cx, cy, cx + rx + 34, cy)
        noFill()
        drawArc(cx, cy, 40, 40, start: 0.06, stop: 0.9)
        noStroke()
        fill(accent)
        let tip = Vector2(cx, cy) + Vector2(40, 0).rotated(by: 0.9)
        drawTriangle(tip + Vector2(9, 2).rotated(by: 0.9),
                     tip + Vector2(-4, -5).rotated(by: 0.9),
                     tip + Vector2(-4, 9).rotated(by: 0.9))
        textSize(16)
        textAlign(.left, .middle)
        drawText("0", cx + rx + 42, cy)
        drawText("clockwise", cx + 52, cy + 44)
    }

    func panel(cx: Double, cy: Double, rx: Double, ry: Double,
               start: Double, stop: Double, mode: ArcMode, name: String) {
        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawArc(cx, cy, rx, ry, start: start, stop: stop, mode: mode)

        noStroke()
        fill(accent)
        drawCircle(cx, cy, 3.5)

        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText(name, cx, cy + ry + 34)
    }
}
