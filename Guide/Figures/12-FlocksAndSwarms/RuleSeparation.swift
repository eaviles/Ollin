// figure: frame=0 themed
//
// Guide diagram (Chapter 12): the separation rule. One boid, three neighbors
// crowding inside its personal-space circle, and the push away from them,
// stronger for closer neighbors, summed into one force.
import Ollin
import OllinDiagram

final class RuleSeparation: Sketch {
    override var canvasSize: CanvasSize { .size(880, 400) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.4) }
    var soft: Color { theme.ink(0.12) }
    var accent: Color { theme.accent }

    override func draw() {
        background(paper)
        textSize(17)

        let focal = Vector2(330, 200)

        // Personal space.
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawCircle(center: focal, radius: 120)
        label("personal space", focal + Vector2(0, -142))

        // The crowding neighbors, each with its push on the focal boid.
        let neighbors = [Vector2(255, 145), Vector2(275, 265), Vector2(400, 250)]
        var push = Vector2.zero
        for n in neighbors {
            boid(at: n, angle: (focal - n).angle, color: faint, size: 13)
            let offset = focal - n
            push = push + offset * (5200 / offset.lengthSquared)
            arrow(from: n, to: focal - (focal - n).normalized * 24, color: soft, weight: 2)
        }
        boid(at: focal, angle: -0.5, color: ink, size: 16)
        arrow(from: focal, to: focal + push.limited(to: 130), color: accent, weight: 5)
        label("away from the crowd", focal + push.limited(to: 130) + Vector2(96, -8), color: accent)

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("separation: steer away from anyone too close", width / 2, 340)
    }

    func boid(at p: Vector2, angle: Double, color: Color, size: Double) {
        noStroke()
        fill(color)
        withState {
            translate(p)
            rotate(angle)
            drawTriangle(Vector2(size, 0),
                         Vector2(-size * 0.65, size * 0.5),
                         Vector2(-size * 0.65, -size * 0.5))
        }
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
