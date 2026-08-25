// figure: frame=0 themed
//
// Guide diagram (Chapter 12): the cohesion rule. One boid, the neighbors it
// can see, the center of the group, and the drift toward it.
import Ollin
import OllinDiagram

final class RuleCohesion: Sketch {
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

        let focal = Vector2(310, 230)

        noFill()
        stroke(soft)
        strokeWeight(2)
        drawCircle(center: focal, radius: 150)
        label("what it can see", focal + Vector2(-72, -168))

        // The group drifts up and to the right of the focal boid.
        let neighbors = [Vector2(400, 130), Vector2(455, 190), Vector2(430, 260),
                         Vector2(350, 120)]
        var centerSum = Vector2.zero
        for p in neighbors {
            boid(at: p, angle: -0.4, color: faint, size: 13)
            centerSum = centerSum + p
        }
        let center = centerSum / Double(neighbors.count)

        // The center of the group, and the drift toward it.
        noStroke()
        fill(accent)
        drawCircle(center: center, radius: 6)
        noFill()
        stroke(accent)
        strokeWeight(2)
        drawCircle(center: center, radius: 14)
        label("the center of the group", center + Vector2(120, -26), color: accent)

        boid(at: focal, angle: -0.4, color: ink, size: 16)
        arrow(from: focal, to: center - (center - focal).normalized * 22, color: accent, weight: 5)

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("cohesion: drift toward the center of the group", width / 2, 340)
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
