// figure: frame=0
//
// Guide diagram (Chapter 14): the low-discrepancy property. The first 40,
// 160, and 640 points of one Halton sequence. The earlier points (dark) are
// in exactly the same places in all three panels; the new ones (orange)
// only fill the gaps that were left.
import Ollin

final class HaltonGrowth: Sketch {
    override var canvasSize: CanvasSize { .size(880, 400) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x232020)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)
    let accent = Color(hex: 0xE4572E)

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
