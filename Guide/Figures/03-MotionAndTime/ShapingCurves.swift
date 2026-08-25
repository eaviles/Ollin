// figure: frame=0 themed
//
// Guide diagram: the first three shaping curves, each drawn as its graph
// (progress in, progress out) with a spacing strip underneath: thirteen
// evenly spaced moments, placed where the curve sends them. Tight spacing
// reads as slow, wide spacing as fast.
import Ollin
import OllinDiagram

final class ShapingCurves: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.28) }
    var accent: Color { theme.accent }

    override func draw() {
        background(paper)
        textSize(21)

        drawPanel(x: 70, title: "linear", note: "steady all the way") { t in t }
        drawPanel(x: 340, title: "step", note: "nothing, then everything") { t in
            step(0.5, t)
        }
        drawPanel(x: 610, title: "smoothstep", note: "gentle, quick, gentle") { t in
            smoothstep(0, 1, t)
        }

        noStroke()
        fill(ink)
        textAlign(.center, .top)
        drawText("13 evenly spaced moments, placed where each curve sends them",
                 width / 2, 440)
    }

    func drawPanel(x: Double, title: String, note: String, curve: (Double) -> Double) {
        let size = 200.0
        let top = 90.0, bottom = top + size

        // Frame and the identity diagonal for reference.
        noFill()
        stroke(faint)
        strokeWeight(2)
        drawRect(x, top, size, size)
        drawLine(x, bottom, x + size, top)

        // The curve itself.
        var points: [Vector2] = []
        var t = 0.0
        while t <= 1.0001 {
            points.append(Vector2(x + t * size, bottom - curve(t) * size))
            t += 0.005
        }
        stroke(ink)
        strokeWeight(3.5)
        drawPolyline(points)

        // Axis labels.
        noStroke()
        fill(ink)
        textAlign(.center, .top)
        drawText("progress in", x + size / 2, bottom + 12)
        textAlign(.center, .bottom)
        drawText(title, x + size / 2, top - 40)
        fill(theme.ink(0.6))
        drawText(note, x + size / 2, top - 14)

        // The spacing strip: where the curve puts evenly spaced moments.
        let stripY = bottom + 70
        stroke(faint)
        strokeWeight(2)
        drawLine(x, stripY, x + size, stripY)
        noStroke()
        for i in 0...12 {
            let moment = Double(i) / 12
            fill(accent)
            drawCircle(x + curve(moment) * size, stripY, 7)
        }
    }
}
