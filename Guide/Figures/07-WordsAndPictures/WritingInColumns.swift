// figure: frame=0
//
// Guide diagram (Chapter 7): the same sentence set across a line and down a
// column, the three characters that change shape called out, and one box filled
// both ways so a justified column can be seen against a ragged one.
import Ollin

final class WritingInColumns: Sketch {
    override var canvasSize: CanvasSize { .size(880, 620) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.4)
    let accent = Color(hex: 0xE4572E)
    let paperTint = Color(hex: 0xE9E4D8)

    /// Chosen for its brackets and its comma: those are the characters that turn.
    let sentence = "「春」は、あけぼの（をかし）"

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textFont(.system)
        noStroke()

        sameSentenceBothWays()
        theCharactersThatTurn()
        justifiedAgainstRagged()
    }

    /// Top: one sentence across a line, then the opening of it down a column.
    private func sameSentenceBothWays() {
        label("ACROSS A LINE", at: Vector2(60, 40))
        fill(ink)
        textSize(34)
        textDirection(.automatic)
        textAlign(.left, .top)
        drawText(sentence, 60, 64)

        label("DOWN A COLUMN", at: Vector2(60, 128))
        fill(ink)
        textSize(34)
        textDirection(.topToBottom)
        textAlign(.left, .top)
        drawText("「春」は、あ", 60, 152)

        fill(faint)
        textSize(15)
        textDirection(.automatic)
        textAlign(.left, .top)
        drawText("the same string, the same call", 112, 156)
        drawText("a column is one em across", 112, 176)
        drawText("and the brackets have turned", 112, 196)
    }

    /// Middle right: the characters that keep a second shape, upright and turned.
    private func theCharactersThatTurn() {
        label("THE FONT'S OWN SIDEWAYS FORMS", at: Vector2(430, 128))
        var x = 430.0
        for character in ["「", "、", "（"] {
            fill(paperTint)
            drawRect(corner: Vector2(x, 152), width: 56, height: 56)
            drawRect(corner: Vector2(x, 216), width: 56, height: 56)

            fill(ink)
            textSize(44)
            textDirection(.automatic)
            textAlign(.left, .top)
            drawText(character, x + 6, 154)

            fill(accent)
            textDirection(.topToBottom)
            textAlign(.left, .top)
            drawText(character, x + 6, 218)
            x += 76
        }

        fill(faint)
        textSize(15)
        textDirection(.automatic)
        textAlign(.left, .top)
        drawText("upright", 664, 170)
        fill(accent)
        drawText("turned", 664, 234)
    }

    /// Bottom: one passage in one box, justified and not, with a rule under each
    /// so the flush ends can be told from the ragged ones.
    private func justifiedAgainstRagged() {
        let passage = "やうやう白くなりゆく山ぎは、すこしあかりて、むらさきだちたる雲のほそくたなびきたる。"
        label("JUSTIFIED TO THE BOX", at: Vector2(60, 372))
        label("LEFT AS IT FALLS", at: Vector2(470, 372))

        drawColumnBox(passage, at: Vector2(60, 396), justified: true)
        drawColumnBox(passage, at: Vector2(470, 396), justified: false)

        fill(faint)
        textSize(15)
        textDirection(.automatic)
        textAlign(.left, .top)
        drawText("every column ends on the rule", 60, 586)
        drawText("each column ends where it ran out", 470, 586)
    }

    private func drawColumnBox(_ passage: String, at origin: Vector2, justified: Bool) {
        let box = Rectangle(x: origin.x, y: origin.y, width: 340, height: 170)
        fill(paperTint)
        drawRect(corner: Vector2(box.x, box.y), width: box.width, height: box.height)

        let inner = box.inset(by: .all(12))
        fill(ink)
        textSize(21)
        textDirection(.topToBottom)
        textAlign(.right, .top)
        if justified { textJustify() } else { noTextJustify() }
        drawText(passage, in: inner)
        noTextJustify()

        // The line every full column is stretched to, drawn under both boxes so
        // the difference is a comparison rather than a claim.
        stroke(accent)
        strokeWeight(1)
        drawLine(inner.x, inner.y + inner.height, inner.x + inner.width, inner.y + inner.height)
        noStroke()
    }

    private func label(_ text: String, at position: Vector2) {
        fill(faint)
        textSize(13)
        textDirection(.automatic)
        textAlign(.left, .top)
        drawText(text, position.x, position.y)
    }
}
