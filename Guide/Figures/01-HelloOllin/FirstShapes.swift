// figure: frame=0
//
// Guide diagram: a contact sheet of the first three shapes and the ink state
// that styles them (fill, stroke, strokeWeight).
import Ollin

final class FirstShapes: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let accent = Color(hex: 0xE4572E)
    let label = Color(hex: 0x2B2B2B, alpha: 0.55)

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(19)
        textAlign(.center, .top)

        // Top row: one call per shape, filled with the current fill. The two
        // closed shapes carry an anchor dot, because x, y means the center for
        // a circle and the top-left corner for a rectangle.
        noStroke()
        fill(ink)
        drawCircle(147, 140, 62)
        anchor(147, 140, "x, y is the center")
        caption("drawCircle(x, y, radius)", 147, 228)

        noStroke()
        fill(ink)
        drawRect(340, 78, 200, 124)
        anchor(340, 78, "x, y is the corner")
        caption("drawRect(x, y, w, h)", 440, 228)

        stroke(ink)
        strokeWeight(3)
        drawLine(645, 90, 820, 190)
        caption("drawLine(x1, y1, x2, y2)", 733, 228)

        // Bottom row: the same shapes wearing different ink.
        noFill()
        stroke(ink)
        strokeWeight(4)
        drawCircle(147, 350, 62)
        caption("noFill() + stroke(...)", 147, 438)

        fill(accent)
        stroke(ink)
        strokeWeight(5)
        drawRect(340, 288, 200, 124)
        caption("fill and stroke together", 440, 438)

        stroke(accent)
        strokeWeight(14)
        drawLine(645, 300, 820, 400)
        caption("strokeWeight(14)", 733, 438)
    }

    func caption(_ text: String, _ x: Double, _ y: Double) {
        noStroke()
        textSize(19)
        textAlign(.center, .top)
        fill(label)
        drawText(text, x, y)
    }

    /// Mark the point a shape's x, y actually refers to, and name it. The
    /// label sits clear of the shape with a leader line back to the dot, so it
    /// stays legible over both the dark fills and the light ground.
    func anchor(_ x: Double, _ y: Double, _ text: String) {
        stroke(accent)
        strokeWeight(1.5)
        drawLine(x, y, x, 54)
        noStroke()
        fill(accent)
        drawCircle(x, y, 7)
        textSize(15)
        textAlign(.center, .bottom)
        drawText(text, x, 48)
    }
}
