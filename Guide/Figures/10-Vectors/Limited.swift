// figure: frame=0 themed
//
// Guide diagram (Chapter 10): what limited(to:) does. The circle is the cap.
// An arrow that reaches past it is cut back to the circle and keeps its
// heading; one already inside would come back unchanged.
import Ollin
import OllinDiagram

final class Limited: Sketch {
    override var canvasSize: CanvasSize { .size(880, 330) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.4) }
    var ghost: Color { theme.ink(0.25) }
    var soft: Color { theme.ink(0.12) }
    var accent: Color { theme.accent }

    let cap = 90.0
    let long = 200.0
    let heading = Vector2(1.7, -0.95).normalized

    override func draw() {
        background(paper)
        textSize(17)

        beforePanel(Rectangle(x: 50, y: 45, width: 370, height: 230))
        afterPanel(Rectangle(x: 470, y: 45, width: 370, height: 230))
    }

    func beforePanel(_ r: Rectangle) {
        frame(r, title: "v: longer than the cap")
        let o = Vector2(r.x + 110, r.y + 128)
        capCircle(at: o)
        arrow(from: o, to: o + heading * long, color: ink)
        origin(o)
        label("v", o + heading * long + Vector2(22, 12))
        label("the cap, 90", o + Vector2(125, 72))
    }

    func afterPanel(_ r: Rectangle) {
        frame(r, title: "v.limited(to: 90): cut back, heading kept")
        let o = Vector2(r.x + 110, r.y + 128)
        capCircle(at: o)
        arrow(from: o, to: o + heading * long, color: ghost)
        arrow(from: o, to: o + heading * cap, color: accent, weight: 5)
        origin(o)
        label("v", o + heading * long + Vector2(22, 12), color: ghost)
        label("v.limited(to: 90)", o + heading * cap + Vector2(40, 34), color: accent)
    }

    func capCircle(at o: Vector2) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawCircle(center: o, radius: cap)
    }

    func origin(_ o: Vector2) {
        noStroke()
        fill(ink)
        drawCircle(center: o, radius: 6)
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textAlign(.left, .middle)
        drawText(title, r.x + 2, r.y - 20)
    }

    func arrow(from a: Vector2, to b: Vector2, color: Color, weight: Double = 3) {
        let dir = (b - a).normalized
        stroke(color)
        strokeWeight(weight)
        drawLine(a, b - dir * 12)
        noStroke()
        fill(color)
        drawPolygon([b, b - dir * 16 + dir.perpendicular * 6,
                        b - dir * 16 - dir.perpendicular * 6])
    }

    func label(_ text: String, _ at: Vector2, color: Color? = nil) {
        noStroke()
        fill(color ?? faint)
        textAlign(.center, .middle)
        drawText(text, at: at)
    }
}
