// figure: frame=0 themed
//
// Guide figure (Chapter 15): why shape packing is not circle packing wearing
// costumes. Both panels are the *same* packing. On the left each shape's
// bounding circle is drawn too, and those circles overlap freely, which a circle
// packing could never do. The fit was measured against the outlines, so a small
// star settles into a big one's notch. On the right, the same shapes alone.
import Ollin
import OllinDiagram

final class ShapePacking: Sketch {
    override var canvasSize: CanvasSize { .size(880, 460) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.34) }
    var soft: Color { theme.ink(0.13) }

    var shapes: [Shape] = []
    var circles: [Circle] = []

    override func setup() {
        let bag = [polygon(3), polygon(4), polygon(6), polygon(5, star: true),
                   polygon(4, star: true)]
        let packer = ContinuousPacking(shapes: bag, in: panelRect(0).inset(by: .all(6)),
                                       seed: 6, minRadius: 7, maxRadius: 62,
                                       padding: 2, scale: 0.95, attemptsPerStep: 12)
        packer.step(160)
        shapes = packer.shapes
        circles = packer.circles
    }

    /// A unit-radius regular polygon, or a star when `star` is set.
    func polygon(_ sides: Int, star: Bool = false) -> Shape {
        let count = star ? sides * 2 : sides
        let points = (0 ..< count).map { i -> Vector2 in
            let a = Double(i) / Double(count) * .tau - .pi / 2
            let r = (star && i % 2 == 1) ? 0.42 : 1.0
            return Vector2(cos(a) * r, sin(a) * r)
        }
        return Shape(points, closed: true)
    }

    func panelRect(_ index: Int) -> Rectangle {
        Rectangle(x: 34 + Double(index) * 418, y: 40, width: 394, height: 340)
    }

    override func draw() {
        background(paper)
        textSize(18)

        for panel in 0 ... 1 {
            let offset = Vector2(Double(panel) * 418, 0)
            noFill()
            stroke(soft)
            strokeWeight(2)
            drawRect(panelRect(panel))

            if panel == 0 {
                // The bounding circles, drawn only to be seen overlapping.
                stroke(faint)
                strokeWeight(1.4)
                for circle in circles {
                    drawCircle(center: circle.center + offset, radius: circle.radius)
                }
            }

            noStroke()
            fill(ink)
            for shape in shapes { drawShape(shape.mapPoints { $0 + offset }) }

            fill(faint)
            textAlign(.center, .top)
            let label = panel == 0 ? "with each shape's bounding circle" : "the packing itself"
            drawText(label, panelRect(panel).x + panelRect(panel).width / 2, 392)
        }

        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("the circles overlap, because the shapes were fitted to outlines",
                 width / 2, 424)
    }
}
