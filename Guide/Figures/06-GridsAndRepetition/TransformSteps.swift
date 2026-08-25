// figure: frame=0 themed
//
// Guide diagram (Chapter 6): transforms move the paper, not the shape. The
// same little flag is drawn with the same call in every panel; what changes
// is where the coordinate system was moved, turned, and stretched first.
import Ollin
import OllinDiagram

final class TransformSteps: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.28) }
    var accent: Color { theme.accent }

    override func draw() {
        background(paper)
        textSize(19)

        drawPanel(at: 55, note: "just draw()") {
            // No transform: the origin sits at the panel's top-left.
        }
        drawPanel(at: 265, note: "translate(70, 52)") {
            self.translate(70, 52)
        }
        drawPanel(at: 475, note: "+ rotate(.tau / 12)") {
            self.translate(70, 52)
            self.rotate(.tau / 12)
        }
        drawPanel(at: 685, note: "+ scale(1.5)") {
            self.translate(70, 52)
            self.rotate(.tau / 12)
            self.scale(1.5)
        }

        noStroke()
        fill(ink)
        textAlign(.center, .top)
        textSize(21)
        drawText("the drawing call never changes; the paper moves under it", width / 2, 460)
    }

    func drawPanel(at x: Double, note: String, transforms: @escaping () -> Void) {
        let top = 140.0, size = 170.0

        noFill()
        stroke(faint)
        strokeWeight(2)
        drawRect(x, top, size, size)

        withState {
            translate(x, top)
            transforms()

            // The moved coordinate frame: its x and y axes...
            stroke(faint)
            strokeWeight(2)
            drawLine(0, 0, 54, 0)
            drawLine(0, 0, 0, 54)

            // ...and the same flag, drawn at the same numbers every panel.
            noStroke()
            fill(accent)
            drawRect(0, 0, 56, 34, cornerRadius: 6)
            fill(ink)
            drawCircle(68, 17, 9)
        }

        noStroke()
        fill(ink)
        textAlign(.center, .bottom)
        drawText(note, x + size / 2, top - 16)
    }
}
