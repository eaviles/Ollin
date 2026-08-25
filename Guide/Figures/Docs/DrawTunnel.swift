// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Drawing.md, drawTunnel): the archway as a
// doorway, at its squattest (height right at half the width), and turned to
// aim the opening with the transform stack.
import Ollin
import OllinDiagram

final class DrawTunnel: Sketch {
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

        let cy = 140.0

        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawTunnel(176, cy, 128, 190)
        drawTunnel(452, cy, 190, 96)
        withState {
            translate(722, cy)
            rotate(.pi / 2)
            drawTunnel(0, 0, 128, 190)
        }

        noStroke()
        fill(accent)
        drawCircle(176, cy, 3.5)
        drawCircle(452, cy, 3.5)
        drawCircle(722, cy, 3.5)

        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText("a doorway", 176, 262)
        drawText("height at width / 2", 452, 262)
        drawText("aimed with rotate", 722, 262)
    }
}
