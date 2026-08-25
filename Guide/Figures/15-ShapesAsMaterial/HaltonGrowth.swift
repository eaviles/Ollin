// figure: frame=0 themed
//
// Guide diagram (Chapter 15): the low-discrepancy property. The first 40,
// 160, and 640 points of one Halton sequence. The earlier points (dark) are
// in exactly the same places in all three panels; the new ones (orange)
// only fill the gaps that were left.
import Ollin
import OllinDiagram

final class HaltonGrowth: Sketch {
    override var canvasSize: CanvasSize { .size(880, 400) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }
    var accent: Color { theme.accent }

    override func draw() {
        background(paper)

        let counts = [40, 160, 640]
        for (i, count) in counts.enumerated() {
            let panel = Rectangle(x: 25 + Double(i) * 284, y: 62,
                                  width: 262, height: 262)
            let points = haltonPoints(count: count, in: panel.inset(by: .all(10)))
            // The same first 40 are dark in every panel, so the eye can check
            // that they never move as the count grows.
            noStroke()
            for (k, p) in points.enumerated() {
                fill(k < counts[0] ? ink : accent)
                drawCircle(center: p, radius: k < counts[0] ? 3.2 : 2.4)
            }
            frame(panel, title: "first \(count)")
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("asking for more never moves the points you already had",
                 width / 2, 348)
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
        drawText(title, r.x, r.y - 18)
    }
}
