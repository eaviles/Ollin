// figure: frame=0 themed
//
// Guide diagram (Chapter 11): forces accumulate. Left, three pushes acting on
// the same body at once. Right, the same three added tip to tail, the way
// arrows add, into the one push the body actually feels.
import Ollin
import OllinDiagram

final class ForceAccumulation: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.4) }
    var soft: Color { theme.ink(0.12) }
    var accent: Color { theme.accent }

    let gravity = Vector2(0, 150)
    let wind = Vector2(120, -20)
    let drag = Vector2(-45, -32)

    override func draw() {
        background(paper)
        textSize(17)

        pushesPanel(Rectangle(x: 50, y: 60, width: 370, height: 380))
        sumPanel(Rectangle(x: 470, y: 60, width: 370, height: 380))

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("the sum, divided by mass, is this frame's acceleration",
                 width / 2, 495)
    }

    func pushesPanel(_ r: Rectangle) {
        frame(r, title: "three pushes on one body")
        let body = Vector2(r.x + 160, r.y + 170)
        drawBody(at: body)
        arrow(from: body, to: body + gravity, color: ink)
        arrow(from: body, to: body + wind, color: ink)
        arrow(from: body, to: body + drag, color: ink)
        label("gravity", body + gravity + Vector2(0, 22))
        label("wind", body + wind + Vector2(40, 0))
        label("drag", body + drag + Vector2(-30, -16))
    }

    func sumPanel(_ r: Rectangle) {
        frame(r, title: "added tip to tail: one total push")
        let body = Vector2(r.x + 130, r.y + 150)
        let a = body + gravity
        let b = a + wind
        let c = b + drag
        drawBody(at: body)
        arrow(from: body, to: a, color: faint)
        arrow(from: a, to: b, color: faint)
        arrow(from: b, to: c, color: faint)
        arrow(from: body, to: c, color: accent, weight: 5)
        label("gravity", body + gravity * 0.5 + Vector2(-42, 0))
        label("wind", a + wind * 0.5 + Vector2(0, -18))
        label("drag", b + drag * 0.5 + Vector2(34, -12))
        label("the total", body.lerp(to: c, 0.55) + Vector2(58, 16), color: accent)
    }

    func drawBody(at p: Vector2) {
        noStroke()
        fill(ink)
        drawCircle(center: p, radius: 12)
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
