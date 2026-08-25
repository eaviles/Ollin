// figure: frame=0 probe themed
//
// Guide figure (Chapter 13): space colonization, four moments of the same
// growth. Dots are attraction points; the structure branches toward them,
// and every dot a branch reaches is consumed. The same input always grows
// the same veins.
import Ollin
import OllinDiagram

final class ClaimingSpace: Sketch {
    override var canvasSize: CanvasSize { .size(880, 340) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.4) }
    var soft: Color { theme.ink(0.12) }
    var accent: Color { theme.accent }

    let steps = [6, 18, 40, 200]
    var growths: [SpaceColonization] = []

    override func setup() {
        growths = []
        seed(9)
        for (i, count) in steps.enumerated() {
            let r = panelRect(i)
            let attractors = poissonDisk(in: r.inset(by: .all(16)), radius: 15)
            let growth = SpaceColonization(attractors: attractors,
                                           roots: [Vector2(r.x + r.width / 2, r.y + r.height - 8)],
                                           influenceRadius: 70, killRadius: 11, stepLength: 5.5)
            growth.step(count)
            growths.append(growth)
        }
    }

    func panelRect(_ i: Int) -> Rectangle {
        Rectangle(x: 40 + Double(i) * 206, y: 55, width: 190, height: 190)
    }

    override func draw() {
        background(paper)
        textSize(17)

        for (i, growth) in growths.enumerated() {
            let r = panelRect(i)
            noFill()
            stroke(soft)
            strokeWeight(2)
            drawRect(r)

            noStroke()
            fill(accent.withAlpha(0.55))
            drawCircles(growth.attractors, radius: 2.5)

            let widths = growth.thicknesses(leafWidth: 0.9, exponent: 2.2)
            stroke(ink)
            strokeCap(.round)
            for (n, node) in growth.nodes.enumerated() {
                guard let parent = node.parent else { continue }
                strokeWeight(widths[n])
                drawLine(growth.nodes[parent].position, node.position)
            }

            noStroke()
            fill(faint)
            textAlign(.center, .top)
            drawText(i == steps.count - 1 ? "grown" : "step \(steps[i])",
                     r.x + r.width / 2, r.y + r.height + 14)
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("branches chase the dots; every dot reached is consumed", width / 2, 288)
    }
}
