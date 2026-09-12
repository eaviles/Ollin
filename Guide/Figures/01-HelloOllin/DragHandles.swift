// figure: frame=0 themed
//
// Guide diagram: the three things a Command-drag can take hold of. The shape
// itself moves, a corner resizes, and the knob above it turns. Which of them
// appear depends on what the line of the file says about the shape.
import Ollin
import OllinDiagram

final class DragHandles: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    override func draw() {
        background(theme.paper)
        textFont(.system)

        let width = 250.0
        let panels = [Rectangle(x: 40, y: 74, width: width, height: 220),
                      Rectangle(x: 315, y: 74, width: width, height: 220),
                      Rectangle(x: 590, y: 74, width: width, height: 220)]
        let titles = ["the shape moves", "a corner resizes", "the knob turns"]
        for (panel, title) in zip(panels, titles) {
            diagramFrame(panel, title: title, theme: theme)
        }

        movedShape(in: panels[0])
        resizedShape(in: panels[1])
        turnedLine(in: panels[2])

        code(["drawCircle(", "200", ", ", "300", ", 40)"], accent: [1, 3], at: panels[0])
        code(["drawCircle(200, 300, ", "60", ")"], accent: [1], at: panels[1])
        code(["drawLine(", "50", ", ", "90", ", ", "250", ", ", "90", ")"],
             accent: [1, 3, 5, 7], at: panels[2])

        diagramCaption("the handles a shape offers are the ones its own line can answer for",
                       at: 424, theme: theme)
    }

    // MARK: The three panels

    /// The shape under the pointer, on its way somewhere else.
    private func movedShape(in panel: Rectangle) {
        let radius = 34.0
        let center = middle(of: panel) - Vector2(40, 24)
        let landing = center + Vector2(80, 48)
        ghost(at: center, radius: radius)
        noStroke()
        fill(theme.ink(0.72))
        drawCircle(center: landing, radius: radius)
        outline(at: landing, half: Vector2(radius, radius), corners: true, active: nil, knob: false)
        // From edge to edge, so the head is not buried in the shape.
        let step = (landing - center) / (landing - center).length
        arrow(from: center + step * radius, to: landing - step * (radius + 8))
    }

    /// The same shape, grown by the corner that is being pulled.
    private func resizedShape(in panel: Rectangle) {
        let center = middle(of: panel)
        noStroke()
        fill(theme.ink(0.72))
        drawCircle(center: center, radius: 52)
        // Where it stood, drawn over the fill so the growth reads.
        ghost(at: center, radius: 34)
        let corner = center + Vector2(52, 52)
        outline(at: center, half: Vector2(52, 52), corners: true, active: corner, knob: false)
        arrow(from: corner + Vector2(12, 12), to: corner + Vector2(30, 30))
    }

    /// A line, which has no size on its call and so offers the parameter alone.
    private func turnedLine(in panel: Rectangle) {
        let center = middle(of: panel) + Vector2(4, 10)
        let half = Vector2(78, 6)
        withState {
            strokeWeight(4)
            strokeCap(.round)
            stroke(theme.ink(0.72))
            drawLine(center + Vector2(-78, 0), center + Vector2(78, 0))
        }
        outline(at: center, half: half, corners: false, active: nil, knob: true)
        // The sweep the parameter makes on its way round, starting at the parameter.
        let reach = half.y + 26
        withState {
            noFill()
            stroke(theme.accent(0.5))
            strokeWeight(2)
            drawArc(center.x, center.y, reach, reach, start: -.pi / 2, stop: -0.28)
        }
        let head = center + Vector2(cos(-0.24) * reach, sin(-0.24) * reach)
        arrow(from: center + Vector2(cos(-0.5) * reach, sin(-0.5) * reach), to: head)
    }

    // MARK: The pieces every panel shares

    private func middle(of panel: Rectangle) -> Vector2 {
        Vector2(panel.x + panel.width / 2, panel.y + panel.height / 2)
    }

    /// Where the shape stood before the drag.
    private func ghost(at center: Vector2, radius: Double) {
        withState {
            noFill()
            stroke(theme.ink(0.32))
            strokeWeight(2)
            drawCircle(center: center, radius: radius)
        }
    }

    /// The host's own highlight: the shape's box, its corner squares, and the
    /// knob standing clear above it.
    private func outline(at center: Vector2, half: Vector2,
                         corners: Bool, active: Vector2?, knob: Bool) {
        withState {
            noFill()
            stroke(theme.accent)
            strokeWeight(2)
            drawRect(center: center, width: half.x * 2, height: half.y * 2)
        }
        if corners {
            for sx in [-1.0, 1.0] {
                for sy in [-1.0, 1.0] {
                    let at = center + Vector2(sx * half.x, sy * half.y)
                    let held = active.map { ($0 - at).length < 1 } ?? false
                    withState {
                        fill(held ? theme.accent : theme.paper)
                        stroke(theme.accent)
                        strokeWeight(2)
                        drawRect(center: at, width: held ? 14 : 11, height: held ? 14 : 11)
                    }
                }
            }
        }
        if knob {
            withState {
                fill(theme.accent)
                stroke(theme.accent)
                strokeWeight(2)
                drawCircle(center: center - Vector2(0, half.y + 26), radius: 7)
            }
        }
    }

    private func arrow(from a: Vector2, to b: Vector2) {
        withState {
            stroke(theme.ink(0.5))
            strokeWeight(2)
            drawArrow(from: a, to: b)
        }
    }

    /// The line of the sketch under its panel, with the numbers that gesture
    /// changes set in the accent.
    private func code(_ parts: [String], accent: Set<Int>, at panel: Rectangle) {
        textFont(.systemMono)
        textSize(17)
        textAlign(.left, .top)
        let total = parts.reduce(0.0) { $0 + textWidth($1) }
        var x = panel.x + (panel.width - total) / 2
        for (index, text) in parts.enumerated() {
            fill(accent.contains(index) ? theme.accent : theme.ink)
            drawText(text, x, 336)
            x += textWidth(text)
        }
        textFont(.system)
    }
}
