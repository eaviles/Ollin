// figure: frame=0 themed
//
// Guide diagram (Chapter 8): the other vertical writing. Top, one phrase set
// across a line and then the same phrase turned a quarter turn to stand as a
// column. Bottom, two blocks side by side, one filling left to right and the
// other right to left, so the column order is a comparison rather than a claim.
import Ollin
import OllinDiagram

final class ColumnsTheOtherWay: Sketch {
    override var canvasSize: CanvasSize { .size(880, 620) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.4) }
    var accent: Color { theme.accent }
    var paperTint: Color { theme.card }

    /// The script's own name for itself, "Mongol bichig". Two words, so the
    /// joined strokes and the gap between them both show.
    let phrase = "ᠮᠣᠩᠭᠣᠯ ᠪᠢᠴᠢᠭ"
    let japanese = "春はあけぼの"

    var mongolian: OutlineFont?

    override func setup() {
        mongolian = OutlineFont(name: "Noto Sans Mongolian")
    }

    override func draw() {
        background(paper)
        textFont(.system)
        noStroke()

        guard mongolian != nil else {
            fill(ink)
            textSize(20)
            textAlign(.center, .middle)
            drawText("This figure needs the Noto Sans Mongolian face.", 440, 280)
            return
        }
        theSameLineTurned()
        theTwoColumnOrders()
    }

    /// Top: the phrase across a line, then the same phrase standing as a column.
    private func theSameLineTurned() {
        label("ACROSS A LINE", at: Vector2(60, 40))
        fill(ink)
        textFont(mongolian!)
        textSize(30)
        textDirection(.automatic)
        textAlign(.left, .top)
        drawText(phrase, 60, 62)
        let lineEnd = 60 + textWidth(phrase)

        // The quarter turn itself: a quarter circle from the end of the line
        // round to the top of the column.
        stroke(accent)
        strokeWeight(1.5)
        noFill()
        drawArc(center: Vector2(lineEnd + 20, 130), rx: 52, ry: 52,
                start: -1.5708, stop: 0)
        noStroke()
        fill(accent)
        drawTriangle(Vector2(lineEnd + 72, 136), Vector2(lineEnd + 66, 124),
                     Vector2(lineEnd + 78, 124))

        label("THE SAME LINE, TURNED", at: Vector2(430, 150))
        fill(faint)
        textFont(.system)
        textSize(14)
        textAlign(.left, .top)
        drawText("nothing sits on a square,", 430, 174)
        drawText("so the letters stay joined", 430, 194)
        drawText("and a column runs as long", 430, 222)
        drawText("as the line was wide", 430, 242)

        fill(ink)
        textFont(mongolian!)
        textSize(30)
        textDirection(.topToBottomLeftToRight)
        textAlign(.left, .top)
        drawText(phrase, lineEnd + 46, 150)
    }

    /// Bottom: the same three columns under each writing system's own order.
    private func theTwoColumnOrders() {
        let top = 420.0
        block(font: mongolian!, text: phrase, direction: .topToBottomLeftToRight,
              at: Vector2(60, top), rightward: true,
              caption: "COLUMNS FILL LEFT TO RIGHT")
        block(font: .system, text: japanese, direction: .topToBottom,
              at: Vector2(500, top), rightward: false,
              caption: "AND THESE FILL RIGHT TO LEFT")
    }

    /// Three columns of one text, with an arrow over them running the way they
    /// fill and the first column marked.
    private func block(font: OutlineFont, text: String, direction: TextDirection,
                       at origin: Vector2, rightward: Bool, caption: String) {
        textFont(font)
        textDirection(direction)
        textSize(24)
        textAlign(.left, .top)
        let block = Array(repeating: text, count: 3).joined(separator: "\n")
        let box = textBounds(block, origin.x, origin.y)

        fill(paperTint)
        drawRect(corner: Vector2(box.x, box.y), width: box.width, height: box.height)
        fill(ink)
        drawText(block, origin.x, origin.y)

        // The arrow, over the block, pointing the way the columns fill.
        let y = box.y - 22
        let tip = rightward ? box.x + box.width : box.x
        let tail = rightward ? box.x : box.x + box.width
        let back = rightward ? tip - 13 : tip + 13
        stroke(accent)
        strokeWeight(1.5)
        drawLine(tail, y, tip, y)
        noStroke()
        fill(accent)
        drawTriangle(Vector2(tip, y), Vector2(back, y - 6), Vector2(back, y + 6))

        // Which column came first, since a still picture cannot say it alone.
        fill(accent)
        textFont(.system)
        textDirection(.automatic)
        textSize(13)
        textAlign(.center, .top)
        drawText("1", tail + (rightward ? 14 : -14), box.y + box.height + 8)

        label(caption, at: Vector2(box.x, box.y - 48))
    }

    private func label(_ text: String, at position: Vector2) {
        fill(faint)
        textFont(.system)
        textDirection(.automatic)
        textSize(13)
        textAlign(.left, .top)
        drawText(text, position.x, position.y)
    }
}
