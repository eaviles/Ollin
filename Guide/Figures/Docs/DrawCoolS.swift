// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Drawing.md, drawCoolS): the notebook doodle
// as its filled silhouette, and with a stroke tracing its outline.
import Ollin
import OllinDiagram

final class DrawCoolS: Sketch {
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

        let cy = 132.0

        fill(ink)
        noStroke()
        drawCoolS(300, cy, 196)

        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawCoolS(580, cy, 196)

        noStroke()
        fill(accent)
        drawCircle(300, cy, 3.5)
        drawCircle(580, cy, 3.5)

        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText("filled", 300, 262)
        drawText("with a stroke", 580, 262)
    }
}
