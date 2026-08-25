// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Drawing.md, drawTriangle): the three call
// forms side by side, each anchored differently: equilateral centered on its
// point, isosceles hung from its apex, and any triangle from three corners.
import Ollin
import OllinDiagram

final class DrawTriangle: Sketch {
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

        // Equilateral: centered at (x, y), circumradius, point up.
        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawTriangle(176, 148, 98)
        dot(176, 148)
        caption("center + radius", 176)

        // Isosceles: apex at (x, y), opening toward +y.
        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawTriangle(452, 62, 150, 170)
        dot(452, 62)
        caption("apex + base and height", 452)

        // Three points: the corners placed directly.
        let a = Vector2(636, 216), b = Vector2(816, 178), c = Vector2(700, 56)
        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawTriangle(a, b, c)
        dot(a.x, a.y)
        dot(b.x, b.y)
        dot(c.x, c.y)
        caption("three corners", 726)
    }

    func dot(_ x: Double, _ y: Double) {
        noStroke()
        fill(accent)
        drawCircle(x, y, 3.5)
    }

    func caption(_ text: String, _ x: Double) {
        noStroke()
        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText(text, x, 262)
    }
}
