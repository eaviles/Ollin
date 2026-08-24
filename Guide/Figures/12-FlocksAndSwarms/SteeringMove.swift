// figure: frame=0 probe themed
//
// Guide diagram (Chapter 12): the steering move. Left, a creature with a
// velocity and a target it wants. Right, the same two arrows drawn from one
// point: the correction is the arrow between where you're going and where
// you wish you were going, capped so nothing turns instantly.
import Ollin

final class SteeringMove: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var faint: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.4) }
    var soft: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.12) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }

    let velocity = Vector2(150, -55)
    let desired = Vector2(96, -168)     // toward the target, at full speed

    override func draw() {
        background(paper)
        textSize(17)

        wantsPanel(Rectangle(x: 50, y: 60, width: 370, height: 380))
        movePanel(Rectangle(x: 470, y: 60, width: 370, height: 380))

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("every behavior is this move with a different idea of desired",
                 width / 2, 495)
    }

    func wantsPanel(_ r: Rectangle) {
        frame(r, title: "a creature, its velocity, a target")
        let body = Vector2(r.x + 120, r.y + 300)
        let target = body + desired * 1.55
        drawBody(at: body)

        noFill()
        stroke(accent)
        strokeWeight(3)
        drawCircle(center: target, radius: 11)
        label("the target", target + Vector2(4, 30), color: accent)

        arrow(from: body, to: body + velocity, color: ink)
        label("velocity", body + velocity + Vector2(46, -8))
        arrow(from: body, to: body + desired, color: faint)
        label("desired", body + desired * 0.62 + Vector2(-52, 0))
    }

    func movePanel(_ r: Rectangle) {
        frame(r, title: "steer = desired − velocity, capped")
        let body = Vector2(r.x + 130, r.y + 300)
        drawBody(at: body)
        arrow(from: body, to: body + velocity, color: ink)
        arrow(from: body, to: body + desired, color: ink)
        arrow(from: body + velocity, to: body + desired, color: accent, weight: 5)
        label("velocity", body + velocity + Vector2(48, -8))
        label("desired", body + desired + Vector2(0, -20))
        label("steer", body + velocity + (desired - velocity) * 0.5 + Vector2(44, 8), color: accent)
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
