// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Drawing.md, drawTriangle): the three call
// forms side by side, each anchored differently: equilateral centered on its
// point, isosceles hung from its apex, and any triangle from three corners.
import Ollin

final class DrawTriangle: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var wash: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.10) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }

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
