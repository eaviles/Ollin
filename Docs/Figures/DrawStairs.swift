// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Drawing.md, drawStairs): the staircase at two
// step counts and with wide, shallow treads, always ascending to the right.
import Ollin
import OllinDiagram

final class DrawStairs: Sketch {
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
        drawStairs(176, cy, 46, 46, steps: 4)
        drawStairs(452, cy, 24, 24, steps: 8)
        drawStairs(722, cy, 60, 24, steps: 4)

        noStroke()
        fill(accent)
        drawCircle(176, cy, 3.5)
        drawCircle(452, cy, 3.5)
        drawCircle(722, cy, 3.5)

        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText("steps: 4", 176, 262)
        drawText("steps: 8", 452, 262)
        drawText("wide, shallow treads", 722, 262)
    }
}
