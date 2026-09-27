// figure: frame=0 themed
//
// Guide diagram (Chapter 15): what a pen's lean is for. The same path drawn
// three times with a broad-edged nib laid across three different leans, so the
// stroke thickens where the path runs across the nib and thins where it runs
// along it. The nib is drawn as the quad a chisel lays down between two points,
// which is what a sketch reading `pen.tilt` writes.
import Ollin
import OllinDiagram

final class NibAndLean: Sketch {
    override var canvasSize: CanvasSize { .size(880, 330) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.5) }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        let panels = [Rectangle(x: 46, y: 44, width: 250, height: 190),
                      Rectangle(x: 315, y: 44, width: 250, height: 190),
                      Rectangle(x: 584, y: 44, width: 250, height: 190)]
        let leans: [(Vector2, String)] = [
            (Vector2(1, 0), "leaning right"),
            (Vector2(0.7, 0.7), "leaning down and right"),
            (Vector2(0, 1), "leaning down the page"),
        ]
        for (panel, lean) in zip(panels, leans) {
            diagramFrame(panel, title: lean.1, theme: theme)
            drawNibbed(in: panel, tilt: lean.0)
            drawNibMark(in: panel, tilt: lean.0)
        }

        diagramCaption("one path, one nib, three leans: the width is where the path crosses the edge",
                       at: 276, theme: theme)
    }

    /// The path, drawn as the chisel a pen with this lean lays down: a quad per
    /// step, its edge across the direction of the lean.
    private func drawNibbed(in panel: Rectangle, tilt: Vector2) {
        let angle = atan2(tilt.y, tilt.x) + .pi / 2
        let across = Vector2(cos(angle), sin(angle)) * 11
        noStroke()
        fill(ink)
        var previous: Vector2? = nil
        for step in 0...160 {
            let t = Double(step) / 160
            let point = pathPoint(t, in: panel)
            defer { previous = point }
            guard let from = previous else { continue }
            drawShape { path in
                path.move(to: from + across)
                path.line(to: point + across)
                path.line(to: point - across)
                path.line(to: from - across)
                path.close()
            }
        }
    }

    /// The nib itself, drawn once beside the stroke so the edge that made it is
    /// on the page too.
    private func drawNibMark(in panel: Rectangle, tilt: Vector2) {
        let angle = atan2(tilt.y, tilt.x) + .pi / 2
        let at = Vector2(panel.x + 34, panel.bottomRight.y - 32)
        let across = Vector2(cos(angle), sin(angle)) * 11
        stroke(soft)
        strokeWeight(3)
        strokeCap(.butt)
        drawLine(at - across, at + across)
        noStroke()
        fill(soft)
        textSize(11)
        textAlign(.left, .middle)
        drawText("the nib", at.x + 18, at.y)
    }

    /// A looping path that runs every which way, so each lean has something to
    /// be thick and thin along.
    private func pathPoint(_ t: Double, in panel: Rectangle) -> Vector2 {
        let angle = t * .pi * 2
        let radius = 52.0 + 22 * sin(angle * 2)
        return Vector2(panel.center.x + cos(angle) * radius * 1.15,
                       panel.center.y - 8 + sin(angle) * radius * 0.72)
    }
}
