import Foundation
import Ollin

/// Text set the other way: down the page, in columns that fill right to left.
///
/// Japanese and Chinese are written this way as readily as across, and the
/// difference is not a rotation. The font keeps a second shape for every
/// character that has to turn, so the brackets lie down, the long vowel mark
/// stands up, and the comma moves to the top right of its square. Ollin asks for
/// those shapes and stacks the squares; it never rotates anything.
///
/// The two `textAlign` axes swap jobs when the writing turns. The vertical one
/// now says where each column starts, and the horizontal one places the block of
/// columns, which is why a box is filled from its right edge.
@main
final class Columns: Sketch {
    override var canvasSize: CanvasSize { .size(1080, 1080) }

    @Param("Down the page", icon: "text.append")
    var vertical = true

    @Param("Justify to the box", icon: "text.justify")
    var justified = true

    @Param("Size", 22...44, icon: "textformat.size")
    var glyphSize = 30.0

    let ink = Color(hex: 0x1A1613)
    let paper = Color(hex: 0xF4EFE4)
    let seal = Color(hex: 0xA8321E)

    /// The opening of the Pillow Book, written about the year 1002. The brackets
    /// and the comma are here on purpose: they are the characters that turn.
    let passage = """
    春はあけぼの。やうやう白くなりゆく山ぎは、すこしあかりて、\
    むらさきだちたる雲のほそくたなびきたる。「をかし」といふ（ほかに\
    言ひやうもない）気持ちが、ただそこにある。
    夏は夜。月のころはさらなり、闇もなほ、螢の多く飛びちがひたる。\
    また、ただ一つ二つなど、ほのかにうち光りて行くもをかし。\
    雨など降るもをかし。
    """

    override func setup() {
        textFont(.system)
        noStroke()
    }

    override func draw() {
        background(paper)

        // The box is a limit rather than something the text has to fill, so each
        // way of writing gets one shaped for it: a tall narrow one for columns, a
        // wide one for lines.
        let box = vertical ? Rectangle(x: 520, y: 140, width: 440, height: 780)
                           : Rectangle(x: 120, y: 140, width: 840, height: 500)
        fill(Color(hex: 0xE7DFCE))
        drawRect(corner: Vector2(box.x, box.y), width: box.width, height: box.height)

        textDirection(vertical ? .topToBottom : .automatic)
        if justified { textJustify() } else { noTextJustify() }
        textSize(glyphSize)
        fill(ink)

        // Vertical text opens at the right of its box, horizontal at the left.
        // Either way the other axis starts the block at the top.
        textAlign(vertical ? .right : .left, .top)
        drawText(passage, in: box.inset(by: .all(28)))

        drawTitle()
    }

    /// A heading in its own column, to show that a plain position works the same
    /// way: the block starts where you put it and fills away from there.
    private func drawTitle() {
        textSize(38)
        fill(seal)
        textDirection(vertical ? .topToBottom : .automatic)
        textAlign(vertical ? .right : .left, .top)
        drawText("枕草子", vertical ? 1000 : 120, vertical ? 150 : 70)

        fill(ink.withAlpha(0.45))
        textSize(15)
        textDirection(.automatic)
        textAlign(.left, .top)
        drawText(vertical ? "TATEGAKI, COLUMNS FILL RIGHT TO LEFT"
                          : "YOKOGAKI, LINES FILL TOP TO BOTTOM",
                 120, vertical ? 96 : 116)   // clear of the heading, which sits here too
    }
}
