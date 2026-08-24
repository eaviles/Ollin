// figure: frame=0 themed
//
// Guide diagram (Chapter 14): how a streamline is traced. Ask the field for
// a direction, take a small step, ask again from the new spot. The enlarged
// arrows show the first few asks; the fine line is the same walk carried on
// with small steps.
import Ollin

final class TraceSteps: Sketch {
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
        seed(4)
        let field = flowField(scale: 0.0014, z: 0.7)

        // The field everywhere, as faint needles.
        stroke(soft)
        strokeWeight(2)
        noFill()
        for point in grid(columns: 22, rows: 14, padding: .symmetric(horizontal: 50, vertical: 50)).points {
            let dir = field.direction(at: point.position)
            drawLine(point.position - dir * 9, point.position + dir * 9)
        }

        // The full streamline, traced finely.
        let start = Vector2(835, 75)
        let line = field.streamline(from: start, stepLength: 3, steps: 200,
                                    bounds: Rectangle(x: 40, y: 60, width: 800, height: 420))
        noFill()
        stroke(soft)
        strokeWeight(3)
        drawPolyline(line)

        // The same walk, exaggerated: ask, step, ask again.
        var p = start
        for i in 0 ..< 6 {
            let dir = field.direction(at: p)
            let next = p + dir * 64
            arrow(from: p, to: next, color: i == 0 ? accent : ink)
            noStroke()
            fill(ink)
            drawCircle(center: p, radius: 5)
            p = next
        }
        noStroke()
        fill(accent)
        drawCircle(center: start, radius: 8)
        label("start anywhere", start + Vector2(-112, 2), color: accent)
        label("ask the field, step, ask again", Vector2(width / 2 + 55, 250))

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("a streamline is ask, step, repeat", width / 2, 495)
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
