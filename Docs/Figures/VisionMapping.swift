// figure: frame=0 themed
//
// Docs diagram (Vision/Vision.md, coordinate mapping): a recognizer's point
// lands in normalized space, 0...1 from a lower-left origin with y up; the
// canvas is pixels from the top left with y down, so the same point is
// flipped in y and scaled into the rectangle the frame was drawn in.
import Ollin
import OllinDiagram

final class VisionMapping: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.6) }
    var faint: Color { theme.ink(0.4) }
    var accent: Color { theme.accent }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        let w = 240.0, h = 178.0

        // What a tracker reports: normalized, lower-left origin, y up.
        let n = Rectangle(x: 55, y: 44, width: w, height: h)
        noFill()
        stroke(faint)
        strokeWeight(1.5)
        drawRect(n)
        axis(from: Vector2(n.x, n.y + n.height), dx: 34, dy: 0)
        axis(from: Vector2(n.x, n.y + n.height), dx: 0, dy: -34)
        noStroke()
        fill(accent)
        drawCircle(n.x + 0.62 * n.width, n.y + n.height - 0.7 * n.height, 6)
        fill(ink)
        textSize(15)
        textAlign(.left, .top)
        drawText("(0, 0)", n.x + 2, n.y + n.height + 8)
        textAlign(.right, .bottom)
        drawText("(1, 1)", n.x + n.width - 2, n.y - 6)
        fill(soft)
        textAlign(.center, .top)
        drawText("what a tracker reports:", n.x + n.width / 2, n.y + n.height + 34)
        drawText("0…1, origin bottom left, y up", n.x + n.width / 2, n.y + n.height + 54)

        // Where you drew the frame: canvas pixels, top-left origin, y down.
        let c = Rectangle(x: 585, y: 44, width: w, height: h)
        noFill()
        stroke(faint)
        strokeWeight(1.5)
        drawRect(c)
        let rect = Rectangle(x: c.x + 28, y: c.y + 24,
                             width: c.width - 56, height: c.height - 48)
        stroke(ink)
        drawRect(rect)
        axis(from: Vector2(c.x, c.y), dx: 34, dy: 0)
        axis(from: Vector2(c.x, c.y), dx: 0, dy: 34)
        noStroke()
        fill(accent)
        drawCircle(rect.x + 0.62 * rect.width, rect.y + 0.3 * rect.height, 6)
        fill(ink)
        textSize(15)
        textAlign(.left, .bottom)
        drawText("(0, 0)", c.x + 40, c.y - 6)
        fill(soft)
        textAlign(.center, .top)
        drawText("where you drew the frame:", c.x + c.width / 2, c.y + c.height + 34)
        drawText("pixels, origin top left, y down", c.x + c.width / 2, c.y + c.height + 54)
        textSize(13)
        textAlign(.center, .bottom)
        drawText("rect", rect.x + rect.width / 2, rect.y + rect.height - 6)

        // The mapping: flip y, scale into the frame's rectangle.
        arrow(from: Vector2(330, 133), to: Vector2(560, 133))
        noStroke()
        fill(soft)
        textSize(15)
        textAlign(.center, .bottom)
        drawText("VisionSpace.point(0.62, 0.7, in: rect)", 445, 112)
        textAlign(.center, .top)
        drawText("flipped in y, scaled into rect", 445, 141)
    }

    // A small axis arrow, drawn in the current ink for its space.
    func axis(from a: Vector2, dx: Double, dy: Double) {
        let b = a + Vector2(dx, dy)
        let dir = (b - a).normalized
        stroke(ink)
        strokeWeight(2)
        drawLine(a, b - dir * 8)
        noStroke()
        fill(ink)
        drawPolygon([b, b - dir * 10 + dir.perpendicular * 4,
                        b - dir * 10 - dir.perpendicular * 4])
    }

    func arrow(from a: Vector2, to b: Vector2) {
        let dir = (b - a).normalized
        stroke(accent)
        strokeWeight(3)
        drawLine(a, b - dir * 12)
        noStroke()
        fill(accent)
        drawPolygon([b, b - dir * 15 + dir.perpendicular * 6,
                        b - dir * 15 - dir.perpendicular * 6])
    }
}
