// figure: frame=0 themed
//
// Guide diagram (Chapter 22): the double pendulum. Left, one pendulum stepped
// twelve seconds on, with the path its second bob traced and its two arms
// where they ended. Right, sixteen pendulums whose first arms started a
// ten-thousandth of a radian apart, stepped eight seconds on: the faint pair
// of arms is where all of them began, and the colored arms are where each one
// is now. Every run is stepped with the default fixed interval, so the figure
// is the same on every render.
import Ollin
import OllinDiagram

final class PendulumFan: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }
    var accent: Color { theme.accent }

    override func draw() {
        background(paper)

        let panels = [Rectangle(x: 40, y: 50, width: 380, height: 360),
                      Rectangle(x: 460, y: 50, width: 380, height: 360)]

        // One pendulum, twelve seconds of its second bob.
        let pivot = Vector2(panels[0].x + 190, panels[0].y + 160)
        let one = DoublePendulum(length1: 80, length2: 70, angle1: 2.05, angle2: 2.6)
        var trail: [Vector2] = []
        for _ in 0 ..< 720 {
            one.advance()
            trail.append(pivot + one.bob2)
        }
        noFill()
        stroke(ink.withAlpha(0.35))
        strokeWeight(1.2)
        drawPolyline(trail)
        drawArms(one, at: pivot, color: ink, weight: 4)

        // Sixteen starts a ten-thousandth apart, eight seconds on.
        let hub = Vector2(panels[1].x + 190, panels[1].y + 160)
        let fan = (0 ..< 16).map { i in
            DoublePendulum(length1: 80, length2: 70,
                           angle1: 2.05 + Double(i) * 1e-4, angle2: 2.6)
        }
        drawArms(DoublePendulum(length1: 80, length2: 70, angle1: 2.05, angle2: 2.6),
                 at: hub, color: soft, weight: 6)
        for (i, pendulum) in fan.enumerated() {
            for _ in 0 ..< 480 { pendulum.advance() }
            let tone = Color.mix(accent, ink, Double(i) / 15)
            drawArms(pendulum, at: hub, color: tone, weight: 2.5)
        }

        let titles = ["one start, twelve seconds", "sixteen starts 0.0001 apart, eight seconds"]
        for (i, panel) in panels.enumerated() { frame(panel, title: titles[i]) }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("the same start replays exactly; a start a hair away does not",
                 width / 2, 432)
    }

    func drawArms(_ p: DoublePendulum, at pivot: Vector2, color: Color, weight: Double) {
        stroke(color)
        strokeWeight(weight)
        strokeCap(.round)
        drawLine(pivot, pivot + p.bob1)
        drawLine(pivot + p.bob1, pivot + p.bob2)
        noStroke()
        fill(color)
        drawCircle(center: pivot + p.bob1, radius: weight * 1.6)
        drawCircle(center: pivot + p.bob2, radius: weight * 1.6)
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
        drawText(title, r.x, r.y - 18)
    }
}
