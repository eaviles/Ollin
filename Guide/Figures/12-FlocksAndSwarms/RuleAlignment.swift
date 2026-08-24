// figure: frame=0 themed
//
// Guide diagram (Chapter 12): the alignment rule. One boid, the neighbors it
// can see, each with its own heading, and the turn toward their average.
import Ollin

final class RuleAlignment: Sketch {
    override var canvasSize: CanvasSize { .size(880, 400) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var faint: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.4) }
    var soft: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.12) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }

    override func draw() {
        background(paper)
        textSize(17)

        let focal = Vector2(360, 195)

        // What the boid can see.
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawCircle(center: focal, radius: 150)
        label("what it can see", focal + Vector2(-58, -168))

        // Neighbors, each flying its own way (but roughly together).
        let neighbors: [(Vector2, Double)] = [
            (Vector2(255, 130), -0.35), (Vector2(430, 110), -0.65),
            (Vector2(475, 235), -0.3), (Vector2(280, 265), -0.7),
        ]
        var headingSum = Vector2.zero
        for (p, a) in neighbors {
            boid(at: p, angle: a, color: faint, size: 13)
            arrow(from: p, to: p + Vector2(angle: a, length: 52), color: faint, weight: 2)
            headingSum = headingSum + Vector2(angle: a)
        }

        // The focal boid's own heading, and the average it turns toward.
        boid(at: focal, angle: 0.55, color: ink, size: 16)
        arrow(from: focal, to: focal + Vector2(angle: 0.55, length: 68), color: ink)
        label("its heading", focal + Vector2(angle: 0.55, length: 68) + Vector2(20, 30))
        let average = headingSum.normalized
        arrow(from: focal, to: focal + average * 120, color: accent, weight: 5)
        label("the neighbors' average", focal + average * 120 + Vector2(64, -22), color: accent)

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("alignment: match the average heading of the neighbors", width / 2, 340)
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
