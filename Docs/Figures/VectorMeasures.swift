// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Geometry.md, measuring between two vectors):
// the dot product's sign against three headings, the cross product as the
// area of the spanned parallelogram plus its side-telling sign, and
// angle(to:) as a signed turn, all in y-down screen space.
import Ollin
import OllinDiagram

final class VectorMeasures: Sketch {
    override var canvasSize: CanvasSize { .size(880, 340) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.55) }
    var wash: Color { theme.ink(0.10) }
    var accent: Color { theme.accent }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        // Panel 1: the dot product's sign against one reference heading a.
        let o1 = Vector2(148, 130)
        arrow(from: o1, to: o1 + Vector2(120, 0), color: accent, weight: 3.5)
        arrow(from: o1, to: o1 + Vector2(angle: 0.7, length: 105),
              color: ink, weight: 2.5)
        arrow(from: o1, to: o1 + Vector2(0, 105), color: ink, weight: 2.5)
        arrow(from: o1, to: o1 + Vector2(angle: 2.75, length: 105),
              color: ink, weight: 2.5)
        noStroke()
        fill(accent)
        drawCircle(center: o1, radius: 3.5)
        textSize(16)
        textAlign(.left, .bottom)
        drawText("a", o1.x + 112, o1.y - 8)
        fill(soft)
        textAlign(.left, .top)
        drawText("dot > 0", o1.x + 88, o1.y + 76)
        textAlign(.center, .top)
        drawText("dot = 0", o1.x, o1.y + 116)
        textAlign(.center, .top)
        drawText("dot < 0", o1.x - 88, o1.y + 58)
        caption("a.dot(b)", cx: 176)
        note("the sign: same way, square, opposite", cx: 176)

        // Panel 2: the cross product. The magnitude is the area of the
        // parallelogram a and b span; here b lies clockwise from a, so the
        // sign is positive on the y-down canvas.
        let o2 = Vector2(352, 105)
        let a2 = Vector2(160, -25)
        let b2 = Vector2(55, 95)
        noStroke()
        fill(wash)
        drawPolygon([o2, o2 + a2, o2 + a2 + b2, o2 + b2])
        arrow(from: o2, to: o2 + a2, color: ink, weight: 2.5)
        arrow(from: o2, to: o2 + b2, color: ink, weight: 2.5)
        noStroke()
        fill(accent)
        drawCircle(center: o2, radius: 3.5)
        fill(ink)
        textSize(16)
        textAlign(.left, .bottom)
        drawText("a", o2.x + a2.x + 8, o2.y + a2.y + 4)
        textAlign(.right, .top)
        drawText("b", o2.x + b2.x - 2, o2.y + b2.y + 6)
        fill(soft)
        textAlign(.center, .middle)
        textSize(15)
        drawText("area = |a.cross(b)|", o2.x + 107, o2.y + 37)
        textSize(16)
        caption("a.cross(b)", cx: 452)
        note("here b is clockwise from a: cross > 0", cx: 452)

        // Panel 3: angle(to:) is the signed turn from a to b, and a positive
        // one turns clockwise on screen because y points down.
        let o3 = Vector2(672, 150)
        let angleA = -0.26, angleB = 0.96
        arrow(from: o3, to: o3 + Vector2(angle: angleA, length: 125),
              color: ink, weight: 2.5)
        arrow(from: o3, to: o3 + Vector2(angle: angleB, length: 120),
              color: ink, weight: 2.5)
        stroke(accent)
        strokeWeight(2)
        noFill()
        arc(center: o3, radius: 56, from: angleA + 0.06, to: angleB - 0.16)
        noStroke()
        fill(accent)
        drawCircle(center: o3, radius: 3.5)
        fill(ink)
        textSize(16)
        textAlign(.left, .middle)
        drawText("a", o3.x + 125 * cos(angleA) + 10, o3.y + 125 * sin(angleA))
        textAlign(.left, .top)
        drawText("b", o3.x + 122 * cos(angleB) + 6, o3.y + 122 * sin(angleB) + 2)
        fill(accent)
        textAlign(.left, .middle)
        drawText("+", o3.x + 74, o3.y + 26)
        caption("a.angle(to: b)", cx: 728)
        note("positive turns clockwise, y down", cx: 728)
    }

    func caption(_ text: String, cx: Double) {
        noStroke()
        fill(ink)
        textSize(17)
        textAlign(.center, .top)
        drawText(text, cx, 288)
    }

    func note(_ text: String, cx: Double) {
        noStroke()
        fill(soft)
        textSize(14)
        textAlign(.center, .top)
        drawText(text, cx, 312)
    }

    // An arc with a small arrowhead at its end, showing the turn's sense.
    func arc(center: Vector2, radius: Double, from: Double, to: Double) {
        drawArc(center: center, radiusX: radius, radiusY: radius, start: from, stop: to)
        let tip = center + Vector2(angle: to, length: radius)
        let dir = Vector2(angle: to + 0.5 * Double.pi)
        noStroke()
        fill(accent)
        drawPolygon([tip + dir * 10,
                     tip - dir * 3 + dir.perpendicular * 5,
                     tip - dir * 3 - dir.perpendicular * 5])
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
