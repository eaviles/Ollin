import Foundation
import Ollin

/// Box layout with word wrap. `drawText(_:in:)` flows a paragraph inside a
/// rectangle: words break to the next line at the box width, and `textAlign`
/// positions the block within the box. The box *breathes* (its width oscillates),
/// so the lines rewrap every frame. A faint grid of rules spaced by
/// `textLeading()` sits under the text: leading comes from the font, so the
/// grid holds still while the box and the wrap move. Uses the system font.
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

        // A box centered on the canvas whose width breathes: `wave` is the
        // one-call form of `center + sin(time * rate) * amplitude`.
        let w = wave(0.6, amplitude: width * 0.16, around: width * 0.46)
        let box = Rectangle(center: center,
                            width: w, height: height * 0.62)

        // The box outline.
        noFill()
        stroke(Color(white: 1, alpha: 0.18))
        strokeWeight(1.5 * scale)
        drawRect(corner: box.corner, width: box.width, height: box.height)

        // The line grid, one faint rule per `textLeading()` (the baseline-to-
        // baseline advance at the current font and size). Leading is a font
        // metric, not a box metric, so the rules hold still while the words
        // rewrap across them.
        let leading = textLeading()
        stroke(Color(white: 1, alpha: 0.07))
        strokeWeight(1 * scale)
        var ruleY = box.y + leading
        while ruleY < box.y + box.height {
            drawLine(box.x, ruleY, box.x + box.width, ruleY)
            ruleY += leading
        }

        // The wrapped paragraph.
        noStroke()
        fill(Color(white: 0.92))
        drawText(body, in: box)
    }
}
