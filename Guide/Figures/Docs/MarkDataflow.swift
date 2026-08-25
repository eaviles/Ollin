// figure: frame=0 themed
//
// Docs diagram (Drawing/Marks.md): the stroke-dynamics dataflow. Pointer
// motion is measured into a StrokeInput, the brush's StrokeDynamics answers
// with a width and an opacity multiplier, and the mark keeps that answer at
// every recorded point.
import Ollin
import OllinDiagram

final class MarkDataflow: Sketch {
    override var canvasSize: CanvasSize { .size(880, 300) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.6) }
    var faint: Color { theme.ink(0.45) }
    var card: Color { darkTheme ? Color(hex: 0x2A2724) : .white }
    var accent: Color { theme.accent }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        box(x: 20, y: 62, w: 180, h: 116, title: "the hand",
            lines: ["moved 25 pt in 1/60 s", "pressing at 0.4"])
        box(x: 245, y: 62, w: 180, h: 116, title: "StrokeInput",
            lines: ["speed 1500 pt/s", "pressure 0.4"])
        box(x: 470, y: 62, w: 216, h: 116, title: "StrokeDynamics",
            lines: ["width: .pressure(light: 0.1)", "opacity: .speed(fast: 0.4)"],
            accented: true)
        box(x: 731, y: 62, w: 136, h: 116, title: "the mark",
            lines: ["width 0.62", "opacity 0.40"])

        arrow(from: Vector2(200, 120), to: Vector2(243, 120))
        arrow(from: Vector2(425, 120), to: Vector2(468, 120))
        arrow(from: Vector2(686, 120), to: Vector2(729, 120))

        noStroke()
        fill(soft)
        textSize(17)
        textAlign(.center, .top)
        drawText("every recorded point keeps the width and opacity the hand asked for",
                 width / 2, 234)
    }

    func box(x: Double, y: Double, w: Double, h: Double,
             title: String, lines: [String], accented: Bool = false) {
        fill(card)
        stroke(accented ? accent : faint)
        strokeWeight(accented ? 2.5 : 1.5)
        drawRect(x, y, w, h, cornerRadius: 10)
        noStroke()
        fill(ink)
        textSize(19)
        textAlign(.center, .bottom)
        drawText(title, x + w / 2, y + h / 2 - 4)
        fill(soft)
        textSize(14)
        textAlign(.center, .top)
        for (index, line) in lines.enumerated() {
            drawText(line, x + w / 2, y + h / 2 + 4 + Double(index) * 20)
        }
    }

    func arrow(from a: Vector2, to b: Vector2) {
        let dir = (b - a).normalized
        stroke(accent)
        strokeWeight(3)
        drawLine(a, b - dir * 12)
        noStroke()
        fill(accent)
        drawPolygon([b, b - dir * 15 + dir.perpendicular * 6,
                        b - dir * 15 - dir.perpendicular * 6])
    }
}
