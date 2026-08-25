// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Drawing.md, drawCross): a sharp plus, the
// rounded-plus look from cornerRadius (the inner notches stay sharp), and
// the same shape turned an eighth of a turn into an x.
import Ollin
import OllinDiagram

final class DrawCross: Sketch {
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

        style()
        drawCross(176, cy, 170, 58)
        mark(176, cy, "a plus")

        style()
        drawCross(452, cy, 170, 58, cornerRadius: 16)
        mark(452, cy, "cornerRadius 16")

        style()
        withState {
            translate(728, cy)
            rotate(.pi / 4)
            drawCross(0, 0, 170, 58)
        }
        mark(728, cy, "rotated .pi / 4")
    }

    func style() {
        fill(wash)
        stroke(ink)
        strokeWeight(3)
    }

    func mark(_ cx: Double, _ cy: Double, _ label: String) {
        noStroke()
        fill(accent)
        drawCircle(cx, cy, 3.5)
        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText(label, cx, 252)
    }
}
