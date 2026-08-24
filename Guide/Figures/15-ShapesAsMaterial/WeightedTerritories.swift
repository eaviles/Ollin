// figure: frame=0
//
// Guide diagram (Chapter 15): a Voronoi diagram beside a power diagram over the
// same circles. On the left the boundaries fall halfway between the centers and
// cut through the big circles. On the right each circle carries its own size as a
// weight, and every circle ends up inside its own cell.
import Ollin

final class WeightedTerritories: Sketch {
    override var canvasSize: CanvasSize { .size(880, 460) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let accent = Color(hex: 0xE07A5F)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)

    override func draw() {
        background(paper)

        let left = Rectangle(x: 64, y: 66, width: 340, height: 250)
        let right = Rectangle(x: 476, y: 66, width: 340, height: 250)

        // Placed by hand, so the point being made is visible rather than lucky:
        // one large circle with small ones close around it, and every pair kept
        // apart, since the claim on the right is only about circles that touch
        // nothing.
        let sizes: [(Vector2, Double)] = [(Vector2(150, 125), 78),
                                          (Vector2(53, 181), 26),
                                          (Vector2(233, 56), 22),
                                          (Vector2(255, 174), 30),
                                          (Vector2(98, 35), 18)]

        panel(left, sizes: sizes, weighted: false)
        panel(right, sizes: sizes, weighted: true)

        frame(left, title: "halfway between the centers")
        frame(right, title: "weighted by size")

        fill(ink)
        noStroke()
        textSize(21)
        textAlign(.center, .top)
        drawText("a boundary halfway between two centers cuts through the bigger circle",
                 width / 2, 356)
        textSize(17)
        fill(Color(hex: 0x6E6A63))
        drawText("weight each site by the square of its radius and every circle keeps its own cell",
                 width / 2, 390)
    }

    func panel(_ box: Rectangle, sizes: [(Vector2, Double)], weighted: Bool) {
        let circles = sizes.map { place, size in
            Circle(center: Vector2(box.x + place.x, box.y + place.y), radius: size)
        }
        let cells = weighted
            ? powerDiagram(of: circles, in: box).cells
            : voronoi(circles.map(\.center), in: box).cells

        strokeWeight(2)
        for (index, cell) in cells.enumerated() {
            let tone = 0.86 - Double(index % 3) * 0.07
            fill(Color(white: tone))
            stroke(Color(white: 0.55))
            drawShape(cell)
        }

        noFill()
        stroke(accent)
        strokeWeight(2.5)
        for circle in circles { drawCircle(circle) }
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textSize(17)
        textAlign(.left, .middle)
        drawText(title, r.x, r.y - 20)
    }
}
