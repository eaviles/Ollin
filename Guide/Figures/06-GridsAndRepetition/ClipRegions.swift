// figure: frame=0
//
// Guide diagram (Chapter 6): clipping. The same field of stripes drawn three
// times, confined first to a star, then to a circle, then to both at once,
// which is what nesting two clips does.
import Ollin

final class ClipRegions: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x232020)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(paper)

        let panels = (0 ..< 3).map {
            Rectangle(x: 25 + Double($0) * 284, y: 66, width: 262, height: 262)
        }
        let titles = ["clipped to a star", "clipped to a circle", "both, nested"]

        for (i, panel) in panels.enumerated() {
            let middle = Vector2(panel.x + panel.width / 2,
                                 panel.y + panel.height / 2)
            let star = Shape(starPoints(around: middle, outer: 108, inner: 46))
            let disc = Circle(center: middle + Vector2(26, 18), radius: 82)

            // The outlines of both regions, faint, so the nesting reads.
            noFill()
            stroke(soft)
            strokeWeight(1.5)
            drawShape(star)
            drawCircle(disc)

            switch i {
            case 0: withClip(star) { stripes(panel) }
            case 1: withClip(disc) { stripes(panel) }
            default: withClip(star) { withClip(disc) { stripes(panel) } }
            }

            frame(panel, title: titles[i])
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("everything inside the block lands only inside the region",
                 width / 2, 364)
    }

    func stripes(_ r: Rectangle) {
        noFill()
        stroke(accent)
        strokeWeight(7)
        var y = r.y - r.height
        while y < r.y + r.height * 2 {
            drawLine(r.x - 40, y, r.x + r.width + 40, y + r.width + 80)
            y += 18
        }
    }

    func starPoints(around c: Vector2, outer: Double, inner: Double) -> [Vector2] {
        (0 ..< 10).map { i in
            let a = Double(i) / 10 * .tau - .pi / 2
            let r = i.isMultiple(of: 2) ? outer : inner
            return c + Vector2(cos(a), sin(a)) * r
        }
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textSize(16)
        textAlign(.left, .middle)
        drawText(title, r.x, r.y - 20)
    }
}
