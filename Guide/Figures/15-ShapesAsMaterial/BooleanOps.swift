// figure: frame=0 themed
//
// Guide diagram (Chapter 15): the four shape booleans. The same circle and
// star in every panel; only the operation changes. Faint outlines show the
// two originals, ink shows what survives.
import Ollin
import OllinDiagram

final class BooleanOps: Sketch {
    override var canvasSize: CanvasSize { .size(880, 340) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.35) }
    var soft: Color { theme.ink(0.12) }

    override func draw() {
        background(paper)
        textSize(17)

        let titles = ["union", "intersection", "subtracting", "symmetricDifference"]
        for i in 0 ..< 4 {
            let r = Rectangle(x: 40 + Double(i) * 206, y: 55, width: 190, height: 190)
            noFill()
            stroke(soft)
            strokeWeight(2)
            drawRect(r)

            let center = Vector2(r.x + r.width / 2, r.y + r.height / 2)
            let circle = circleShape(at: center + Vector2(-24, -14), radius: 52)
            let star = starShape(at: center + Vector2(26, 18), radius: 58)
            let result: Shape
            switch i {
            case 0: result = circle.union(star)
            case 1: result = circle.intersection(star)
            case 2: result = circle.subtracting(star)
            default: result = circle.symmetricDifference(star)
            }

            noStroke()
            fill(ink)
            drawShape(result)
            noFill()
            stroke(faint)
            strokeWeight(1.5)
            for shape in [circle, star] {
                for contour in shape.contours { drawPolygon(contour.points) }
            }

            noStroke()
            fill(ink)
            textAlign(.center, .top)
            drawText(titles[i], r.x + r.width / 2, r.y + r.height + 14)
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("the same two shapes, four sentences", width / 2, 288)
    }

    func circleShape(at center: Vector2, radius: Double) -> Shape {
        Shape((0 ..< 48).map { k in
            center + Vector2(angle: Double(k) / 48 * .tau, length: radius)
        })
    }

    func starShape(at center: Vector2, radius: Double) -> Shape {
        Shape((0 ..< 10).map { k in
            let r = k % 2 == 0 ? radius : radius * 0.45
            return center + Vector2(angle: Double(k) / 10 * .tau - .pi / 2, length: r)
        })
    }
}
