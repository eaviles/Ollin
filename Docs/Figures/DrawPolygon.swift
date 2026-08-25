// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Drawing.md, drawPolygon): a list of points in
// order, and the filled convex polygon one call draws through them.
import Ollin
import OllinDiagram

final class DrawPolygon: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var wash: Color { theme.ink(0.10) }
    var faint: Color { theme.ink(0.25) }
    var accent: Color { theme.accent }

    func pentagon(cx: Double, cy: Double) -> [Vector2] {
        [Vector2(cx, cy - 92), Vector2(cx + 96, cy - 22),
         Vector2(cx + 62, cy + 84), Vector2(cx - 70, cy + 88),
         Vector2(cx - 98, cy - 14)]
    }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        // The points, joined faintly so their order reads.
        let left = pentagon(cx: 236, cy: 142)
        noFill()
        stroke(faint)
        strokeWeight(1.5)
        drawPolyline(left, closed: true)
        dots(left)
        label("the points, in order", 236, 260)

        // What the call draws through them.
        let right = pentagon(cx: 632, cy: 142)
        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawPolygon(right)
        dots(right)
        label("drawPolygon: filled, outlined", 632, 260)
    }

    func dots(_ points: [Vector2]) {
        noStroke()
        fill(accent)
        for p in points { drawCircle(center: p, radius: 4) }
    }

    func label(_ text: String, _ x: Double, _ y: Double) {
        noStroke()
        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText(text, x, y)
    }
}
