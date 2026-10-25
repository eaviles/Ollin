// figure: frame=0 themed
//
// Guide diagram (Chapter 39): two parameters shaped by hand. Above, a
// `ResponseCurve` drawn the way its inspector row draws it (a graph whose
// points drag) beside the rings it shades: each ring's gray is `falloff(t)`
// at its distance from the middle. Below, a list of numbers drawn as its row
// of bars beside the step pattern it sizes, one circle per bar. The curve is
// the real type, so the line is the one the sketch reads.
import Foundation
import Ollin
import OllinDiagram

final class ShapedByHand: Sketch {
    override var canvasSize: CanvasSize { .size(880, 560) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.4) }
    var soft: Color { theme.ink(0.62) }
    var accent: Color { theme.accent }

    let falloff = ResponseCurve([(0, 1), (0.3, 0.86), (0.65, 0.22), (1, 0)])
    let accents = [1, 0.25, 0.6, 0.25, 0.85, 0.25, 0.45, 0.1]

    override func draw() {
        background(paper)

        textFont(.systemMedium)
        fill(ink)
        textSize(21)
        textAlign(.left)
        drawText("a curve and a row of bars, shaped by hand", 50, 52)

        fill(soft)
        textSize(14)
        drawText("drag in the inspector; the sketch reads falloff(t) and accents[i]", 50, 76)

        graph(in: Rectangle(x: 50, y: 116, width: 330, height: 170))
        rings(center: Vector2(640, 201), radius: 112)
        bars(in: Rectangle(x: 50, y: 372, width: 330, height: 120))
        steps(in: Rectangle(x: 450, y: 372, width: 380, height: 120))
    }

    // MARK: - The curve

    private func graph(in box: Rectangle) {
        let inset = 12.0
        func place(_ x: Double, _ y: Double) -> Vector2 {
            Vector2(box.x + inset + x * (box.width - inset * 2),
                    box.y + inset + (1 - y) * (box.height - inset * 2))
        }
        noFill()
        stroke(faint)
        strokeWeight(1.5)
        drawRect(box, cornerRadius: 10)
        stroke(faint.withAlpha(0.45))
        strokeWeight(1)
        for q in [0.25, 0.5, 0.75] {
            drawLine(place(q, 0), place(q, 1))
            drawLine(place(0, q), place(1, q))
        }

        let line = (0...96).map { step -> Vector2 in
            let x = Double(step) / 96
            return place(x, falloff(x))
        }
        noStroke()
        fill(accent.withAlpha(0.14))
        drawPolygon([place(0, 0)] + line + [place(1, 0)])
        noFill()
        stroke(accent)
        strokeWeight(2.5)
        drawPolyline(line)

        for (index, point) in falloff.points.enumerated() {
            let at = place(point.x, point.y)
            strokeWeight(2)
            if index == 2 {
                fill(accent)
                stroke(paper)
            } else {
                fill(paper)
                stroke(accent)
            }
            drawCircle(center: at, radius: 7)
        }

        noStroke()
        fill(soft)
        textSize(12)
        textAlign(.left)
        drawText("ResponseCurve: a point drags, a press adds one on the curve", box.x, (box.y + box.height) + 24)
    }

    private func rings(center: Vector2, radius: Double) {
        // Outside in, each ring a disc of paper mixed toward ink by the
        // curve at its distance, so the middle is the curve's left end.
        noStroke()
        for ring in stride(from: 14, through: 1, by: -1) {
            let t = Double(ring) / 14
            fill(Color.mix(paper, ink, falloff(t - 0.5 / 14)))
            drawCircle(center: center, radius: radius * t)
        }
        fill(soft)
        textSize(12)
        textAlign(.center)
        drawText("each ring's ink is falloff(t), t its distance out", center.x, center.y + radius + 41)
    }

    // MARK: - The bars

    private func bars(in box: Rectangle) {
        let gap = 6.0
        let width = (box.width - gap * Double(accents.count - 1)) / Double(accents.count)
        for (index, value) in accents.enumerated() {
            let x = box.x + Double(index) * (width + gap)
            noStroke()
            fill(faint.withAlpha(0.25))
            drawRect(x, box.y, width, box.height, cornerRadius: 4)
            fill(index == 4 ? accent : accent.withAlpha(0.55))
            drawRect(x, (box.y + box.height) - box.height * value, width, box.height * value, cornerRadius: 4)
        }
        fill(soft)
        textSize(12)
        textAlign(.left)
        drawText("[1, 0.25, 0.6, 0.25, 0.85, 0.25, 0.45, 0.1]: drag across to paint", box.x, (box.y + box.height) + 24)
    }

    private func steps(in box: Rectangle) {
        let slot = box.width / Double(accents.count)
        noStroke()
        for (index, value) in accents.enumerated() {
            fill(index == 4 ? accent : ink)
            drawCircle(center: Vector2(box.x + slot * (Double(index) + 0.5), box.y + box.height / 2),
                       radius: 4 + 18 * value)
        }
        fill(soft)
        textSize(12)
        textAlign(.center)
        drawText("one circle per bar, sized by accents[i]", box.x + box.width / 2, (box.y + box.height) + 24)
    }
}
