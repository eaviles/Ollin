// figure: frame=0 themed
//
// Guide diagram (Chapter 18): the chaos game condensing. The same four maps
// played the same way, stopped after 400, 6,000, and 80,000 jumps. The fern
// is not drawn by anyone; it is where the random walk is allowed to be.
import Ollin

final class ChaosGame: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var soft: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.12) }
    var frond: Color { Color(hex: darkTheme ? 0x5E9C6B : 0x2E5E3A) }

    override func draw() {
        background(paper)
        seed(4)

        let counts = [400, 6_000, 80_000]
        for (i, count) in counts.enumerated() {
            let panel = Rectangle(x: 25 + Double(i) * 284, y: 66,
                                  width: 262, height: 262)
            let cloud = ifsPoints(.barnsleyFern, count: count)
                .map { Vector2($0.x, -$0.y) }        // the fern grows upward

            noStroke()
            fill(frond.withAlpha(count > 20_000 ? 0.55 : 0.85))
            drawPoints(fitted(cloud, in: panel.inset(by: .all(10))),
                       size: count > 20_000 ? 1.1 : 1.8)

            frame(panel, title: "\(count.formatted()) jumps")
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("nobody draws the fern; the random walk just can't leave it",
                 width / 2, 364)
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
