// figure: frame=0 themed
//
// Guide diagram: one catalog curve and what the two derive helpers make of it.
// easeInQuad, the same curve reversed (its ease-out), the same curve mirrored
// (its ease-in-out), and an ease-out mirrored, the out-in the catalog lacks.
import Ollin
import OllinDiagram

final class DerivedCurves: Sketch {
    override var canvasSize: CanvasSize { .size(920, 290) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.28) }
    var accent: Color { theme.accent }

    override func draw() {
        background(paper)
        textSize(19)

        drawPanel(x: 50, y: 40, name: "easeInQuad", curve: Easing.easeInQuad)
        drawPanel(x: 260, y: 40, name: ".reversed()", curve: Easing.easeInQuad.reversed())
        drawPanel(x: 470, y: 40, name: ".mirrored()", curve: Easing.easeInQuad.mirrored())
        drawPanel(x: 680, y: 40, name: "easeOutQuad.mirrored()", curve: Easing.easeOutQuad.mirrored())
    }

    func drawPanel(x: Double, y: Double, name: String, curve: Easing) {
        let size = 150.0
        let top = y + 26, bottom = top + size

        noFill()
        stroke(faint)
        strokeWeight(2)
        drawRect(x, top, size, size)
        drawLine(x, bottom, x + size, top)

        var points: [Vector2] = []
        var t = 0.0
        while t <= 1.0001 {
            points.append(Vector2(x + t * size, bottom - curve(t) * size))
            t += 0.004
        }
        stroke(ink)
        strokeWeight(3)
        drawPolyline(points)

        noStroke()
        fill(ink)
        textAlign(.center, .bottom)
        drawText(name, x + size / 2, top - 8)

        let stripY = bottom + 26
        stroke(faint)
        strokeWeight(2)
        drawLine(x, stripY, x + size, stripY)
        noStroke()
        fill(accent)
        for i in 0...12 {
            drawCircle(x + curve(Double(i) / 12) * size, stripY, 5.5)
        }
    }
}
