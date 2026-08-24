// figure: frame=0 themed
//
// Guide figure (Chapter 14): free streamlines versus evenly-spaced ones.
// Same field, same seed points. On the left every line runs to its full
// length, crossing and bunching; on the right each line stops when it comes
// within the separation distance of one already traced, so the flow reads
// as combed fibers.
import Ollin

final class EvenSpacing: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var soft: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.12) }

    override func draw() {
        background(paper)
        textSize(17)
        seed(6)

        let left = Rectangle(x: 50, y: 60, width: 370, height: 340)
        let right = Rectangle(x: 470, y: 60, width: 370, height: 340)
        let field = flowField(scale: 0.003, z: 0.2)

        panel(left, title: "free: lines cross and bunch")
        let leftSeeds = poissonDisk(in: left.inset(by: .all(14)), radius: 30)
        noFill()
        stroke(ink)
        strokeWeight(1.4)
        for line in field.streamlines(from: leftSeeds, stepLength: 4, steps: 120,
                                      bounds: left.inset(by: .all(8))) {
            drawPolyline(line)
        }

        panel(right, title: "spaced: each line yields to the others")
        // The same field, shifted into the right panel, so both panels show
        // one flow pattern.
        let rightField = FlowField { p in field.angle(Vector2(p.x - 420, p.y)) }
        let rightSeeds = leftSeeds.map { Vector2($0.x + 420, $0.y) }
        for line in rightField.streamlines(from: rightSeeds, stepLength: 4, steps: 120,
                                           bounds: right.inset(by: .all(8)), separation: 13) {
            drawPolyline(line)
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("one rule added on the right: stop when you get too close", width / 2, 428)
    }

    func panel(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textAlign(.left, .middle)
        drawText(title, r.x + 2, r.y - 20)
        noFill()
        stroke(ink)
        strokeWeight(1.4)
    }
}
