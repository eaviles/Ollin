// figure: frame=0 themed
//
// Guide diagram: what a Command-drag actually does. Hold the modifier and the
// shape under the pointer is outlined and named by the line that drew it; drag
// it and let go, and those two numbers in the file are the ones that change.
import Ollin
import OllinDiagram

final class DragToSource: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    override func draw() {
        background(theme.paper)
        textFont(.system)

        let panel = Rectangle(x: 40, y: 66, width: 380, height: 250)
        let second = Rectangle(x: 460, y: 66, width: 380, height: 250)
        diagramFrame(panel, title: "hold Command", theme: theme)
        diagramFrame(second, title: "drag, and let go", theme: theme)

        // The same circle in both panels, moved between them. The numbers under
        // the panels are the ones the drag rewrites.
        let before = Vector2(panel.x + 120, panel.y + 150)
        let after = Vector2(second.x + 233, second.y + 136)
        drawShape(in: panel, at: before, outlined: true, ghost: nil)
        drawShape(in: second, at: after, outlined: false,
                  ghost: Vector2(second.x + 120, second.y + 150))

        code(before: true, at: Vector2(panel.x, 372))
        code(before: false, at: Vector2(second.x, 372))

        diagramCaption("the pointer moves the shape; the file is what changes",
                       at: 424, theme: theme)
    }

    /// One panel's circle: outlined and named while the modifier is held, and
    /// with a dashed trace of where it stood once it has been dragged.
    private func drawShape(in panel: Rectangle, at center: Vector2,
                           outlined: Bool, ghost: Vector2?) {
        let radius = 46.0
        if let ghost {
            withState {
                noFill()
                stroke(theme.ink(0.22))
                strokeWeight(2)
                drawCircle(center: ghost, radius: radius)
                // The step it took, ending at the shape's edge so the head shows.
                let direction = (center - ghost) / (center - ghost).length
                stroke(theme.ink(0.34))
                strokeWeight(2)
                drawArrow(from: ghost + direction * radius, to: center - direction * (radius + 6))
            }
        }
        noStroke()
        fill(theme.ink(0.82))
        drawCircle(center: center, radius: radius)

        if outlined {
            // The host's own highlight: the shape's box, and the place in the
            // file it came from, named above it.
            withState {
                noFill()
                stroke(theme.accent)
                strokeWeight(2)
                drawRect(center: center, width: radius * 2, height: radius * 2)
            }
            drawText("Sketch.swift:12", center.x - radius, center.y - radius - 14,
                     size: 17, color: theme.accent, align: .left, .bottom)
        }
    }

    /// The line of the sketch, with the two numbers that move set in the
    /// accent so the pair reads as one thing across the two panels.
    private func code(before: Bool, at origin: Vector2) {
        textFont(.systemMono)
        textSize(21)
        textAlign(.left, .top)
        let parts: [(String, Bool)] = [
            ("drawCircle(", false),
            (before ? "200" : "313", true), (", ", false),
            (before ? "300" : "286", true),
            (", 40)", false),
        ]
        var x = origin.x
        for (text, moved) in parts {
            fill(moved ? theme.accent : theme.ink)
            drawText(text, x, origin.y)
            x += textWidth(text)
        }
        textFont(.system)
    }
}
