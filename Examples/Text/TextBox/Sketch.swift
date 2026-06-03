import Foundation
import Ollin

/// Box layout with word wrap. `drawText(_:in:)` flows a paragraph inside a
/// rectangle: words break to the next line at the box width, and `textAlign`
/// positions the block within the box. The box *breathes* — its width oscillates
/// — so the lines rewrap every frame. Uses the system font.
@main
final class TextBox: Sketch {
    let font = OutlineFont.system
    let body = """
    Ollin draws text as vector geometry, so a paragraph wraps to any box and \
    stays crisp at any size. As the box width changes, the lines reflow every \
    frame — wrapping, measuring, and aligning all happen live.
    """

    override func setup() { textFont(font) }

    override func draw() {
        background(Color(white: 0.07))
        textFont(font)
        textSize(42 * scale)
        textAlign(.left, .top)

        // A box centered on the canvas whose width breathes.
        let w = width * 0.46 + sin(time * 0.6) * (width * 0.16)
        let box = Rectangle(center: Vector2(width / 2, height / 2),
                            width: w, height: height * 0.62)

        // The box outline.
        noFill()
        stroke(Color(white: 1, alpha: 0.18))
        strokeWeight(1.5 * scale)
        drawRect(corner: box.corner, width: box.width, height: box.height)

        // The wrapped paragraph.
        noStroke()
        fill(Color(white: 0.92))
        drawText(body, in: box)
    }
}
