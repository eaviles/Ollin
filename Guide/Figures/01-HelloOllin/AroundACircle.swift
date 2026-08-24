// figure: frame=0 themed
//
// Guide diagram: the one recipe Chapter 1 borrows from Chapter 3. An angle
// plus cos/sin names a point on a circle; grow the angle and the point walks
// around it.
import Ollin

final class AroundACircle: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var faint: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.28) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }

    override func draw() {
        background(paper)

        let center = Vector2(300, 285)
        let radius = 180.0
        let angle = -0.9
        let point = Vector2(center.x + cos(angle) * radius,
                            center.y + sin(angle) * radius)

        // The circle the point lives on, and the zero-angle reference line.
        noFill()
        stroke(faint)
        strokeWeight(2)
        drawCircle(center: center, radius: radius)
        drawLine(center.x, center.y, center.x + radius + 44, center.y)

        // The angle wedge between the reference line and the radius.
        stroke(ink)
        strokeWeight(2.5)
        drawArc(center.x, center.y, 52, 52, start: angle, stop: 0)
        noStroke()
        fill(ink)
        textSize(23)
        textAlign(.left, .middle)
        drawText("angle", center.x + 66, center.y - 30)

        // The radius arm out to the point.
        stroke(ink)
        strokeWeight(3)
        drawLine(center.x, center.y, point.x, point.y)

        // The two component guides: across, then up.
        stroke(faint)
        strokeWeight(2)
        drawLine(center.x, center.y, point.x, center.y)
        drawLine(point.x, center.y, point.x, point.y)
        noStroke()
        fill(ink)
        textAlign(.center, .top)
        drawText("cos(angle) × radius", (center.x + point.x) / 2, center.y + 14)
        textAlign(.left, .middle)
        drawText("sin(angle) × radius", point.x + 18, (center.y + point.y) / 2)

        // The center and the point itself.
        fill(ink)
        drawCircle(center: center, radius: 6)
        textAlign(.right, .middle)
        drawText("center", center.x - 16, center.y)
        fill(accent)
        drawCircle(center: point, radius: 9)
        textAlign(.left, .bottom)
        drawText("(x, y)", point.x + 16, point.y - 8)

        // The recipe, spelled out.
        fill(ink)
        textSize(20)
        textAlign(.left, .middle)
        drawText("x = center.x + cos(angle) × radius", 496, 402)
        drawText("y = center.y + sin(angle) × radius", 496, 438)
    }
}
