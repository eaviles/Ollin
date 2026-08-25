// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Drawing.md, drawEllipse): an ellipse with its
// two radii drawn as rays from the dotted center (radii, not diameters), and
// one with equal radii reading as a circle.
import Ollin
import OllinDiagram

final class DrawEllipse: Sketch {
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

        // rx runs across, ry runs down; both are radii.
        let c = Vector2(235, 150)
        let rx = 135.0, ry = 75.0
        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawEllipse(center: c, rx: rx, ry: ry)

        stroke(accent)
        strokeWeight(2)
        drawLine(c.x, c.y, c.x + rx, c.y)
        drawLine(c.x, c.y, c.x, c.y + ry)
        noStroke()
        fill(accent)
        drawCircle(center: c, radius: 3.5)
        textSize(16)
        textAlign(.left, .middle)
        drawText("rx", c.x + rx / 2 - 8, c.y - 14)
        drawText("ry", c.x + 10, c.y + ry / 2 + 6)

        // Equal radii close back into a circle.
        let c2 = Vector2(655, 150)
        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawEllipse(center: c2, rx: 84, ry: 84)
        noStroke()
        fill(accent)
        drawCircle(center: c2, radius: 3.5)

        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText("rx across, ry down", 235, 272)
        drawText("equal radii: a circle", 655, 272)
    }
}
