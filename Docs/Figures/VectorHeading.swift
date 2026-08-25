// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Geometry.md, length & direction): the 3-4-5
// triangle behind length, the angle measured from +x and growing clockwise
// on the y-down canvas, and perpendicular as a quarter turn.
import Ollin
import OllinDiagram

final class VectorHeading: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.55) }
    var faint: Color { theme.ink(0.25) }
    var accent: Color { theme.accent }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        // Panel 1: v = (3, 4) has length 5, the hypotenuse of its own legs.
        let o1 = Vector2(105, 72)
        let v1 = Vector2(90, 120)   // (3, 4) at 30 px per unit
        stroke(faint)
        strokeWeight(1.5)
        drawLine(o1, o1 + Vector2(v1.x, 0))
        drawLine(o1 + Vector2(v1.x, 0), o1 + v1)
        squareMark(at: o1 + Vector2(v1.x, 0), into: Vector2(-1, 1))
        arrow(from: o1, to: o1 + v1, color: ink, weight: 3)
        noStroke()
        fill(accent)
        drawCircle(center: o1, radius: 3.5)
        fill(soft)
        textSize(16)
        textAlign(.center, .bottom)
        drawText("3", o1.x + v1.x / 2, o1.y - 8)
        textAlign(.left, .middle)
        drawText("4", o1.x + v1.x + 10, o1.y + v1.y / 2)
        fill(ink)
        textAlign(.right, .middle)
        drawText("5", o1.x + v1.x / 2 - 14, o1.y + v1.y / 2 + 4)
        textAlign(.left, .top)
        drawText("(3, 4)", o1.x + v1.x + 8, o1.y + v1.y + 4)
        caption("v.length = 5", cx: 176)

        // Panel 2: the angle starts on +x and grows clockwise, y-down.
        let o2 = Vector2(400, 110)
        let theta = 0.7
        stroke(accent)
        strokeWeight(2)
        drawLine(o2, o2 + Vector2(150, 0))
        noFill()
        arc(center: o2, radius: 46, from: 0.05, to: theta - 0.12)
        arrow(from: o2, to: o2 + Vector2(angle: theta, length: 135),
              color: ink, weight: 3)
        noStroke()
        fill(accent)
        drawCircle(center: o2, radius: 3.5)
        textSize(16)
        textAlign(.left, .middle)
        drawText("0", o2.x + 158, o2.y)
        textAlign(.center, .top)
        drawText("clockwise", o2.x + 30, o2.y + 74)
        fill(ink)
        textAlign(.left, .top)
        drawText("v", o2.x + 138 * cos(theta) + 8, o2.y + 138 * sin(theta))
        caption("v.angle = atan2(y, x)", cx: 452)

        // Panel 3: perpendicular is a quarter turn, (x, y) to (-y, x).
        let o3 = Vector2(665, 95)
        stroke(faint)
        strokeWeight(1.5)
        noFill()
        squareMark(at: o3, into: Vector2(1, 1), size: 14)
        arc(center: o3, radius: 44, from: 0.09, to: 0.5 * Double.pi - 0.2,
            head: faint)
        arrow(from: o3, to: o3 + Vector2(130, 0), color: ink, weight: 3)
        arrow(from: o3, to: o3 + Vector2(0, 130), color: accent, weight: 3)
        noStroke()
        fill(accent)
        drawCircle(center: o3, radius: 3.5)
        fill(ink)
        textSize(16)
        textAlign(.left, .middle)
        drawText("v = (3, 0)", o3.x + 140, o3.y)
        fill(accent)
        textAlign(.left, .top)
        drawText("v.perpendicular = (0, 3)", o3.x + 14, o3.y + 138)
        caption("a quarter turn, clockwise", cx: 728)
    }

    func caption(_ text: String, cx: Double) {
        noStroke()
        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText(text, cx, 272)
    }

    // An arc with a small arrowhead at its end, showing a turn's sense.
    func arc(center: Vector2, radius: Double, from: Double, to: Double,
             head: Color? = nil) {
        drawArc(center: center, rx: radius, ry: radius, start: from, stop: to)
        let tip = center + Vector2(angle: to, length: radius)
        let dir = Vector2(angle: to + 0.5 * Double.pi)
        noStroke()
        fill(head ?? accent)
        drawPolygon([tip + dir * 10,
                     tip - dir * 3 + dir.perpendicular * 5,
                     tip - dir * 3 - dir.perpendicular * 5])
    }

    func squareMark(at corner: Vector2, into: Vector2, size: Double = 11) {
        let a = corner + Vector2(into.x * size, 0)
        let b = corner + Vector2(into.x * size, into.y * size)
        let c = corner + Vector2(0, into.y * size)
        drawPolyline([a, b, c])
    }

    func arrow(from a: Vector2, to b: Vector2, color: Color, weight: Double) {
        let dir = (b - a).normalized
        stroke(color)
        strokeWeight(weight)
        drawLine(a, b - dir * 12)
        noStroke()
        fill(color)
        drawPolygon([b, b - dir * 15 + dir.perpendicular * 6,
                        b - dir * 15 - dir.perpendicular * 6])
    }
}
