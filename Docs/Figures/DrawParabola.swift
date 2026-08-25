// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Drawing.md, drawParabola): the filled arch at
// three width and height pairs, the curve peaking at the top and the flat
// base below, each centered on its marked anchor.
import Ollin
import OllinDiagram

final class DrawParabola: Sketch {
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

        panel(cx: 176, w: 170, h: 140, name: "width 170, height 140")
        panel(cx: 452, w: 190, h: 60, name: "a low arch")
        panel(cx: 722, w: 90, h: 170, name: "narrow and tall")
    }

    func panel(cx: Double, w: Double, h: Double, name: String) {
        let cy = 148.0
        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawParabola(cx, cy, w, h)

        noStroke()
        fill(accent)
        drawCircle(cx, cy, 3.5)

        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText(name, cx, 262)
    }
}
