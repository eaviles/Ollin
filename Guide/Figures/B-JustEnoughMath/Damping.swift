// figure: frame=0 themed
//
// Guide diagram (Appendix B): damping. The same spring, pulled one unit from
// its rest length and let go, over three seconds, with three amounts of
// damping. Each curve is stepped by hand at 600 steps a second: the spring
// pulls back in proportion to the stretch, and the damping pushes against
// the velocity. A little damping rings for a long time, the right amount
// settles without overshooting, and a lot crawls back slowly. The line
// through each panel is the rest length.
import Ollin
import OllinDiagram

final class Damping: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    let seconds = 3.0
    let stiffness = 4 * Double.pi * Double.pi     // one swing a second, for a mass of 1

    /// The stretch over time, from 1 at rest, for a damping amount per unit velocity.
    func stretch(damping: Double) -> [Double] {
        var x = 1.0, v = 0.0
        let dt = 1.0 / 600
        var out: [Double] = []
        for _ in 0...Int(seconds * 600) {
            out.append(x)
            v += (-stiffness * x - damping * v) * dt
            x += v * dt
        }
        return out
    }

    override func draw() {
        background(theme.paper)
        let critical = 2 * stiffness.squareRoot()
        panel(Rectangle(x: 40, y: 90, width: 250, height: 300), damping: critical * 0.08,
              title: "a little: it rings", accent: false)
        panel(Rectangle(x: 315, y: 90, width: 250, height: 300), damping: critical,
              title: "just enough: it settles", accent: true)
        panel(Rectangle(x: 590, y: 90, width: 250, height: 300), damping: critical * 4,
              title: "a lot: it crawls", accent: false)
        diagramCaption("the same spring let go from one unit of stretch, over three seconds",
                       at: 470, theme: theme)
    }

    func panel(_ r: Rectangle, damping: Double, title: String, accent: Bool) {
        diagramFrame(r, title: title, theme: theme)
        let rest = r.y + r.height / 2
        let amplitude = r.height * 0.42

        stroke(theme.ink(0.35))
        strokeWeight(1.5)
        drawLine(r.x, rest, r.x + r.width, rest)

        let values = stretch(damping: damping)
        let points = values.enumerated().map { i, x in
            Vector2(r.x + Double(i) / Double(values.count - 1) * r.width, rest - x * amplitude)
        }
        stroke(accent ? theme.accent : theme.ink)
        strokeWeight(3)
        drawPolyline(points)

        noStroke()
        fill(theme.muted)
        textSize(13)
        textAlign(.right, .bottom)
        drawText("rest", r.x + r.width - 6, rest - 4)
    }
}
