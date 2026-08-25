// figure: frame=0 themed
//
// Guide figure (Chapter 13): differential growth, five moments of the same
// seeded ring. It starts as a small circle and folds because splitting edges
// keep adding length that repulsion won't let overlap.
import Ollin
import OllinDiagram

final class GrowthStrip: Sketch {
    override var canvasSize: CanvasSize { .size(880, 300) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.4) }
    var soft: Color { theme.ink(0.12) }

    let steps = [0, 80, 180, 320, 500]
    var rings: [[Vector2]] = []

    override func setup() {
        rings = []
        for (i, count) in steps.enumerated() {
            let r = panelRect(i)
            let growth = DifferentialGrowth.ring(
                center: Vector2(r.x + r.width / 2, r.y + r.height / 2),
                radius: 22, count: 24, seed: 7,
                maxSegmentLength: 6, repulsionRadius: 12, growthRate: 0.6,
                bounds: r.inset(by: .all(10)))
            growth.step(count)
            rings.append(growth.nodes)
        }
    }

    func panelRect(_ i: Int) -> Rectangle {
        Rectangle(x: 40 + Double(i) * 162, y: 55, width: 150, height: 150)
    }

    override func draw() {
        background(paper)
        textSize(17)

        for (i, nodes) in rings.enumerated() {
            let r = panelRect(i)
            noFill()
            stroke(soft)
            strokeWeight(2)
            drawRect(r)
            stroke(ink)
            strokeWeight(1.8)
            strokeJoin(.round)
            drawPolygon(nodes)
            noStroke()
            fill(faint)
            textAlign(.center, .top)
            drawText("step \(steps[i])", r.x + r.width / 2, r.y + r.height + 14)
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("a growing line folds because it refuses to crowd itself", width / 2, 252)
    }
}
