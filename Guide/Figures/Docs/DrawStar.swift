// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Drawing.md, drawStar): the inner radius sets
// the temper. The same five points spiky then gentle, and an eight-point
// burst, each with its center dotted.
import Ollin
import OllinDiagram

final class DrawStar: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var wash: Color { theme.ink(0.10) }
    var accent: Color { theme.accent }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        let cy = 148.0
        panel(cx: 176, cy: cy, outer: 96, inner: 34, points: 5,
              name: "5 points, inner 34")
        panel(cx: 452, cy: cy, outer: 96, inner: 72, points: 5,
              name: "5 points, inner 72")
        panel(cx: 722, cy: cy, outer: 96, inner: 68, points: 8,
              name: "8 points")
    }

    func panel(cx: Double, cy: Double, outer: Double, inner: Double,
               points: Int, name: String) {
        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawStar(cx, cy, outer, inner, points: points)

        noStroke()
        fill(accent)
        drawCircle(cx, cy, 3.5)

        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText(name, cx, cy + outer + 24)
    }
}
