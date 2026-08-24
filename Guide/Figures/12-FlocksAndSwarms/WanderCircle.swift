// figure: frame=0 themed
//
// Guide diagram (Chapter 12): the wander recipe. Left, the anatomy: a circle
// floats ahead of the creature, a target point sits on its rim, and each step
// the point jitters a little around the rim while the creature seeks it.
// Right, what that produces: seven hundred steps of one wanderer.
import Ollin

final class WanderCircle: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var faint: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.4) }
    var soft: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.12) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }

    override func draw() {
        background(paper)
        textSize(17)

        anatomyPanel(Rectangle(x: 50, y: 60, width: 370, height: 400))
        trailPanel(Rectangle(x: 470, y: 60, width: 370, height: 400))
    }

    func anatomyPanel(_ r: Rectangle) {
        frame(r, title: "a circle floats ahead of the creature")
        let body = Vector2(r.x + 80, r.y + 260)
        let heading = Vector2(1, -0.35).normalized
        let center = body + heading * 165
        let radius = 62.0
        let rim = center + heading.rotated(by: 0.9) * radius

        // The projected circle and its center.
        noFill()
        stroke(faint)
        strokeWeight(2)
        drawCircle(center: center, radius: radius)
        noStroke()
        fill(faint)
        drawCircle(center: center, radius: 4)

        // The creature and its heading.
        noStroke()
        fill(ink)
        drawCircle(center: body, radius: 12)
        arrow(from: body, to: body + heading * 70, color: ink)
        label("heading", body + heading * 70 + Vector2(6, 28))

        // The jittering target on the rim, and the seek toward it.
        noStroke()
        fill(accent)
        drawCircle(center: rim, radius: 8)
        arrow(from: body, to: rim, color: accent)
        label("the wandering target", rim + Vector2(30, -24), color: accent)

        // Jitter marks along the rim.
        for spin in [-0.45, 0.45] {
            let ghost = center + heading.rotated(by: 0.9 + spin) * radius
            noStroke()
            fill(soft)
            drawCircle(center: ghost, radius: 6)
        }
        label("each step it slides a little", center + Vector2(0, radius + 34))
        label("around the rim", center + Vector2(0, radius + 56))
    }

    func trailPanel(_ r: Rectangle) {
        frame(r, title: "what that produces")
        let creature = Vehicle(at: Vector2(r.x + 185, r.y + 200),
                               velocity: Vector2(1.4, 0.4),
                               maxSpeed: 2.4, maxForce: 0.09, seed: 3)
        var trail: [Vector2] = [creature.position]
        for _ in 0 ..< 700 {
            creature.applyForce(creature.wander(radius: 20, distance: 55, jitter: 0.25))
            creature.applyForce(creature.contain(in: Rectangle(x: r.x + 30, y: r.y + 30,
                                                               width: r.width - 60, height: r.height - 60),
                                                 margin: 40) * 1.5)
            creature.step()
            trail.append(creature.position)
        }
        noFill()
        stroke(ink)
        strokeWeight(2)
        drawPolyline(trail)
        noStroke()
        fill(faint)
        drawCircle(center: trail[0], radius: 7)
        fill(accent)
        drawVehicle(creature, size: 10)
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
