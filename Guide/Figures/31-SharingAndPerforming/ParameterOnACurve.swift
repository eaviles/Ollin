// figure: frame=1 themed
//
// Guide diagram (Chapter 31): the same two keys read by four curves. Each
// panel builds a real Automation.Track and samples it, so the shapes are the
// shipped curves rather than a drawing of them; the dot marks one moment, and
// the circle above each panel is the value the parameter holds there.
import Ollin
import OllinDiagram

final class ParameterOnACurve: Sketch {
    override var canvasSize: CanvasSize { .size(880, 470) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.35) }
    var soft: Color { theme.ink(0.6) }
    var mark: Color { theme.accent }

    /// The moment every panel is read at, in seconds.
    let moment = 1.15
    let span = 2.0

    override func draw() {
        background(paper)

        panel(0, "linear", .linear)
        panel(1, "easeInOut", .easeInOut)
        panel(2, "hold", .hold)
        panel(3, "bezier", .bezier(x1: 0.85, y1: 0, x2: 0.15, y2: 1))

        noStroke()
        fill(soft)
        textSize(19)
        textAlign(.center, .top)
        drawText("two keys, 20 and 100, and the curve that leaves the first one",
                 width / 2, 412)
    }

    func panel(_ index: Int, _ name: String, _ curve: Automation.Curve) {
        let w = 180.0
        let x = 44 + Double(index) * (w + 24)
        let track = Automation.Track(name: "radius", keys: [
            .init(at: 0, .number(20), curve: curve),
            .init(at: span, .number(100)),
        ])

        // The value the parameter holds at the moment, drawn as its own circle.
        var value = 20.0
        if case .number(let held)? = track.value(at: moment) { value = held }
        noStroke()
        fill(mark)
        drawCircle(x + w / 2, 96, value * 0.52)

        // The curve itself, sampled across the panel.
        let box = Rectangle(x: x, y: 196, width: w, height: 150)
        var points: [Vector2] = []
        for step in 0...120 {
            let at = span * Double(step) / 120
            guard case .number(let held)? = track.value(at: at) else { continue }
            points.append(Vector2(box.x + box.width * at / span,
                                  box.y + box.height * (1 - (held - 20) / 80)))
        }
        noFill()
        stroke(faint)
        strokeWeight(1.5)
        drawRect(box)
        stroke(ink)
        strokeWeight(2.5)
        drawPolyline(points)

        // The moment, and where it lands on the curve.
        stroke(mark)
        strokeWeight(1.5)
        let head = box.x + box.width * moment / span
        drawLine(head, box.y, head, box.y + box.height)
        noStroke()
        fill(mark)
        drawCircle(head, box.y + box.height * (1 - (value - 20) / 80), 5)

        // The keys themselves.
        fill(soft)
        for key in track.keys {
            drawCircle(box.x + box.width * key.time / span, box.y + box.height + 12, 4)
        }
        fill(ink)
        textSize(17)
        textAlign(.center, .top)
        drawText(name, box.center.x, box.y + box.height + 28)
    }
}
