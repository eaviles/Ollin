// figure: frame=0 themed
//
// Guide diagram (Chapter 31): what the G-code planner does to pen-up travel.
// The same line work twice: on the left the pen hops between paths in the
// order the sketch drew them, on the right in the planned order. The travel
// figures under the panels are measured from each plan, not written in.
import Ollin
import OllinDiagram

final class MachineRoute: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    override func draw() {
        background(theme.paper)
        let source = Rectangle(x: 0, y: 0, width: 100, height: 100)
        let work = lineWork()
        let drawn = GCode(.plotter(), width: 150, ordered: false, joinTolerance: 0)
            .toolpath(work, in: source)
        let planned = GCode(.plotter(), width: 150).toolpath(work, in: source)

        let left = Rectangle(x: 55, y: 50, width: 330, height: 330)
        let right = Rectangle(x: 495, y: 50, width: 330, height: 330)
        drawPlan(drawn, in: left, from: source, title: "drawn order")
        drawPlan(planned, in: right, from: source, title: "planned")
        diagramCaption("same line work, same machine: only the pen-up travel changes",
                       at: 432, theme: theme)
    }

    private func drawPlan(_ plan: Toolpath, in panel: Rectangle, from source: Rectangle,
                          title: String) {
        diagramFrame(panel, title: title, theme: theme)
        let inset = 26.0
        let scale = (panel.width - 2 * inset) / source.width
        func mapped(_ p: Vector2) -> Vector2 {
            Vector2(panel.x + inset + p.x * scale, panel.y + inset + p.y * scale)
        }
        noFill()
        stroke(theme.accent)
        strokeWeight(1.2)
        for hop in plan.travels { drawLine(mapped(hop.from), mapped(hop.to)) }
        stroke(theme.ink)
        strokeWeight(2.2)
        for path in plan.paths {
            drawShape(Shape(contours: [Contour(path.points.map(mapped),
                                               closed: path.isClosed)],
                            winding: .evenOdd))
        }
        drawText(String(format: "travel %.0f mm", plan.travelLength),
                 panel.x + panel.width / 2, panel.y + panel.height + 14,
                 size: 17, color: theme.muted, align: .center, .top)
    }

    /// A ring, ticks around it, and a wave, deliberately emitted in an order
    /// that ping-pongs across the page so the left panel has travel to waste.
    private func lineWork() -> [Contour] {
        var work: [Contour] = []
        let center = Vector2(50, 40)
        for i in 0..<12 {
            let slot = i % 2 == 0 ? i / 2 : 11 - i / 2
            let a = Double(slot) / 12 * 2 * .pi
            let direction = Vector2(angle: a)
            work.append(Contour([center + direction * 18, center + direction * 27],
                                closed: false))
        }
        work.append(Contour((0..<64).map { k in
            center + Vector2(angle: 2 * .pi * Double(k) / 64) * 13
        }, closed: true))
        for i in 0..<12 {
            let x0 = 100 * Double(i) / 12, x1 = 100 * Double(i + 1) / 12
            func wave(_ x: Double) -> Vector2 {
                Vector2(x, 84 + sin(x / 100 * 4 * .pi) * 6)
            }
            work.append(Contour([wave(x0), wave(x1)], closed: false))
        }
        return work
    }
}
