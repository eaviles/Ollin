// figure: frame=0 themed
//
// Guide diagram (Chapter 15): three answers to "what shape are these points?"
// One scatter (a dotted ring with a small island offshore) wrapped three
// ways: the convex hull bridges everything into one taut band, the concave
// hull sinks into the gulf while staying one simple polygon, and the alpha
// shape resolves what neither hull can say, two islands and the ring's hole.
import Ollin

final class HullTrio: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var soft: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.12) }
    var region: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.11) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }

    var scatter: [Vector2] = []

    override func setup() {
        scatter = []
        seed(9)
        // Panel-local coordinates: a ring of dots around a hub, plus a small
        // cluster moored off its upper right.
        let hub = Vector2(115, 185)
        for band in 0 ..< 4 {
            let radius = 52.0 + Double(band) * 15
            let count = Int(radius * .tau / 17)
            for i in 0 ..< count {
                let angle = Double(i) / Double(count) * .tau + random(-0.05, 0.05)
                let r = radius + random(-5, 5)
                scatter.append(hub + Vector2(cos(angle), sin(angle)) * r)
            }
        }
        for _ in 0 ..< 26 {
            scatter.append(Vector2(212, 76) + ring(innerRadius: 0, outerRadius: 32))
        }
    }

    override func draw() {
        background(paper)

        let panels = [Rectangle(x: 25, y: 62, width: 262, height: 300),
                      Rectangle(x: 309, y: 62, width: 262, height: 300),
                      Rectangle(x: 593, y: 62, width: 262, height: 300)]
        let titles = ["convexHull: one taut band",
                      "concaveHull: dips the gulf",
                      "alphaShape: islands and holes"]

        for (i, panel) in panels.enumerated() {
            frame(panel, title: titles[i])
            let points = scatter.map { $0 + Vector2(panel.x, panel.y) }

            switch i {
            case 0:
                let hull = convexHull(of: points)
                fill(region)
                noStroke()
                drawPolygon(hull)
                noFill()
                stroke(accent)
                strokeWeight(2.2)
                drawPolygon(hull)
            case 1:
                let hull = concaveHull(of: points, concavity: 0.62)
                fill(region)
                noStroke()
                drawPolygon(hull)
                noFill()
                stroke(accent)
                strokeWeight(2.2)
                drawPolygon(hull)
            default:
                for island in alphaShape(of: points, alpha: 26) {
                    fill(region)
                    noStroke()
                    drawShape(island)
                    noFill()
                    stroke(accent)
                    strokeWeight(2.2)
                    drawShape(island)
                }
            }

            noStroke()
            fill(ink)
            drawCircles(points, radius: 2.2)
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("the same points, wrapped loosely, snugly, and honestly",
                 width / 2, 400)
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
        drawText(title, r.x + 2, r.y - 20)
    }
}
