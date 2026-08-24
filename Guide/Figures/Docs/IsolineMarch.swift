// figure: frame=0 themed
//
// Docs diagram (Generators/Isolines.md): what marching squares actually
// reads. The field is sampled at grid points, drawn as dots shaded by
// value, and the traced contour threads between them wherever the field
// crosses the level: closed around a bump that fits inside the bounds,
// open where the crossing runs off the edge.
import Ollin

final class IsolineMarch: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var faint: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.4) }
    var soft: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.12) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }

    let panel = Rectangle(x: 120, y: 64, width: 640, height: 320)

    func field(_ p: Vector2) -> Double {
        let inner = 1 - smoothstep(22, 150, p.distance(to: Vector2(330, 224)))
        let edge = 1 - smoothstep(26, 170, p.distance(to: Vector2(820, 150)))
        return inner + edge
    }

    override func draw() {
        background(paper)
        textSize(17)

        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(panel)

        // The field, sampled: one shaded dot per grid point.
        noStroke()
        for point in Grid(in: panel, columns: 13, rows: 7,
                          padding: .all(26)).points {
            let v = min(1, field(point.position))
            fill(Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.08 + 0.72 * v))
            drawCircle(center: point.position, radius: 6)
        }

        // The contour the same field yields, traced finely with the real call.
        noFill()
        stroke(accent)
        strokeWeight(3.5)
        for contour in isolines(at: 0.5, in: panel, resolution: 256,
                                field: field) {
            drawPolyline(contour.points, closed: contour.isClosed)
        }

        label("the field, sampled at grid points", Vector2(258, 44), color: faint)
        label("closed where it fits", Vector2(330, 358), color: accent)
        label("open where it runs", Vector2(636, 250), color: accent)
        label("off the edge", Vector2(636, 272), color: accent)

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("the contour threads between the samples, wherever the field crosses the level",
                 width / 2, 420)
    }

    func label(_ text: String, _ at: Vector2, color: Color) {
        noStroke()
        fill(color)
        textAlign(.center, .middle)
        drawText(text, at: at)
    }
}
