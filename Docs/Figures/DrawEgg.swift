// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Drawing.md, drawEgg): the egg at three radius
// pairs, from the classic taper to the equal-radii circle, each centered on
// its marked anchor.
import Ollin
import OllinDiagram

final class DrawEgg: Sketch {
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

        panel(cx: 176, bottom: 72, top: 38, name: "bottom 72, top 38")
        panel(cx: 452, bottom: 72, top: 16, name: "a narrower tip")
        panel(cx: 722, bottom: 55, top: 55, name: "equal radii: a circle")
    }

    func panel(cx: Double, bottom: Double, top: Double, name: String) {
        let cy = 148.0
        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawEgg(cx, cy, bottom, top)

        noStroke()
        fill(accent)
        drawCircle(cx, cy, 3.5)

        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText(name, cx, 262)
    }
}
