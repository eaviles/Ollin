// figure: frame=0
//
// Guide diagram (Chapter 8): the four places the one-glyph-per-letter idea
// breaks. A Devanagari syllable is one piece drawn out of order; an Arabic line
// runs the other way; an emoji is a picture with no outline to fill; and
// Japanese has no spaces to break a line at.
import Ollin

final class EveryScript: Sketch {
    override var canvasSize: CanvasSize { .size(880, 560) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.4)
    let accent = Color(hex: 0xE4572E)
    let green = Color(hex: 0x0CA678)

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textFont(.system)

        oneSyllable(at: Vector2(60, 60))
        rightToLeft(at: Vector2(470, 60))
        aPicture(at: Vector2(60, 320))
        noSpaces(at: Vector2(470, 320))
    }

    /// One piece, three glyphs, and the vowel sign drawn before the letter it
    /// follows. The box is what the per-piece closure hands over.
    private func oneSyllable(at origin: Vector2) {
        label("ONE PIECE, THREE GLYPHS", at: origin)
        noStroke()
        fill(ink)
        textSize(96)
        textAlign(.left, .baseline)
        let baseline = origin.y + 140
        drawText("क्षि", origin.x, baseline)

        // The piece the closure sees, drawn around it.
        noFill()
        stroke(accent)
        strokeWeight(1.5)
        drawText("क्षि", origin.x, baseline) { g in
            drawRect(corner: Vector2(g.position.x, g.position.y - 96),
                     width: g.bounds.width, height: 118)
        }
        noStroke()
        fill(accent)
        textSize(17)
        drawText("one call of the closure", origin.x, baseline + 46)
        fill(faint)
        drawText("g.text is the whole syllable", origin.x, baseline + 70)
    }

    /// The pieces come out left to right on the canvas, which for Arabic is the
    /// reverse of the reading.
    private func rightToLeft(at origin: Vector2) {
        label("READS RIGHT TO LEFT", at: origin)
        noStroke()
        textSize(76)
        textAlign(.left, .baseline)
        let baseline = origin.y + 130
        drawText("مرحبا", origin.x, baseline) { g in
            fill(g.index == 0 ? accent : ink)
            g.draw()
            fill(faint)
            textSize(16)
            drawText("\(g.index)", g.center.x - 4, baseline + 28)
            textSize(76)
        }
        fill(accent)
        textSize(17)
        drawText("g.index 0 is the LAST letter read", origin.x, baseline + 62)
        fill(faint)
        drawText("the order is the canvas, not the reading", origin.x, baseline + 86)
    }

    /// An emoji has no contours, so geometry comes back empty while drawText
    /// still puts it on the canvas.
    private func aPicture(at origin: Vector2) {
        label("A PICTURE, NOT AN OUTLINE", at: origin)
        textSize(84)
        textAlign(.left, .baseline)
        let baseline = origin.y + 116

        // Drawn: both arrive.
        noStroke()
        fill(ink)
        drawText("O 👋", origin.x, baseline)

        // Asked for geometry: only the letter has any.
        noFill()
        stroke(green)
        strokeWeight(1.5)
        for shape in textToShapes("O 👋", origin.x + 210, baseline) { drawShape(shape) }

        noStroke()
        fill(faint)
        textSize(17)
        drawText("drawText", origin.x, baseline + 34)
        fill(green)
        drawText("textToShapes: the emoji has none", origin.x + 210, baseline + 34)
    }

    /// A paragraph with nothing to split on still fits its box.
    private func noSpaces(at origin: Vector2) {
        label("NO SPACES TO BREAK AT", at: origin)
        noStroke()
        fill(ink)
        textSize(26)
        textAlign(.left, .top)
        let box = Rectangle(x: origin.x, y: origin.y + 34, width: 330, height: 130)
        drawText(String(repeating: "日本語のテキストです。", count: 3), in: box)
        noFill()
        stroke(faint)
        strokeWeight(1)
        drawRect(corner: Vector2(box.x - 8, box.y - 6), width: box.width + 16, height: 124)
        noStroke()
        fill(faint)
        textSize(17)
        drawText("the system says where a line may end", origin.x, box.y + 130)
    }

    private func label(_ text: String, at origin: Vector2) {
        noStroke()
        fill(faint)
        textSize(15)
        textAlign(.left, .top)
        drawText(text, origin.x, origin.y)
    }
}
