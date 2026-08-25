// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Drawing.md, drawTrapezoid): the two widths at
// work: a narrow top over a wide base, equal widths giving a rectangle, and
// a zero top width giving a triangle.
import Ollin
import OllinDiagram

final class DrawTrapezoid: Sketch {
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

        panel(cx: 176, top: 84, bottom: 176, label: "top 84, bottom 176")
        panel(cx: 452, top: 150, bottom: 150, label: "equal widths, a rectangle")
        panel(cx: 728, top: 0, bottom: 176, label: "top 0, a triangle")
    }

    func panel(cx: Double, top: Double, bottom: Double, label: String) {
        let cy = 148.0
        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawTrapezoid(cx, cy, top, bottom, 128)

        noStroke()
        fill(accent)
        drawCircle(cx, cy, 3.5)

        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText(label, cx, 252)
    }
}
