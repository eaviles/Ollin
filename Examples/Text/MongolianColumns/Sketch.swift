import Foundation
import Ollin

/// The other vertical writing: columns that run top to bottom and fill left to
/// right, which is how traditional Mongolian is set.
///
/// The column order is the small half of the difference. The large half is that
/// these letters join. A word is one connected stroke, and every letter takes the
/// width its own shape needs, so nothing here can be set on an em square the way
/// Japanese and Chinese are. Ollin shapes the line the way it shapes a horizontal
/// one, keeping the joins and the real widths, and then turns the whole line a
/// quarter turn clockwise to stand it up.
///
/// The two `textAlign` axes swap jobs exactly as they do for the other vertical
/// mode. The vertical one says where each column starts, the horizontal one
/// places the block, so `textAlign(.left, .top)` fills a box from its opening
/// corner, which for this writing is the top left.
///
/// The text is one phrase: `ᠮᠣᠩᠭᠣᠯ ᠪᠢᠴᠢᠭ`, "Mongol bichig", the script's own
/// name for itself. It is repeated rather than continued, because this is a
/// specimen of the layout and not a piece of writing.
@main
final class MongolianColumns: Sketch {
    override var canvasSize: CanvasSize { .size(1080, 1080) }

    @Param("Size", 26...64, icon: "textformat.size")
    var glyphSize = 52.0

    @Param("Columns", 2...7, icon: "rectangle.split.3x1")
    var columnCount = 5

    let ink = Color(hex: 0x1B1A17)
    let paper = Color(hex: 0xF2EDE1)
    let mark = Color(hex: 0x2C5D63)

    /// The script's own name. Six letters, then a space, then five.
    let phrase = "ᠮᠣᠩᠭᠣᠯ ᠪᠢᠴᠢᠭ"

    /// A face that has the script. The system font does not, and a column takes
    /// its width from the face it was given, so asking for the right one is what
    /// keeps the columns from sitting on top of each other.
    var mongolian: OutlineFont?

    override func setup() {
        mongolian = OutlineFont(name: "Noto Sans Mongolian")
        noStroke()
    }

    override func draw() {
        background(paper)
        guard let mongolian else {
            fill(ink)
            textAlign(.center, .middle)
            drawText("This sketch needs the Noto Sans Mongolian face.", 540, 540)
            return
        }

        textFont(mongolian)
        textDirection(.topToBottomLeftToRight)
        textSize(glyphSize)
        textAlign(.left, .top)
        fill(ink)

        // One call lays the whole block out. Each `\n` starts the next column, and
        // that next column stands to the *right* of the one before it.
        let block = Array(repeating: phrase, count: columnCount).joined(separator: "\n")
        // Asked at the origin with this alignment, the reported box is the block's
        // own size, which is enough to centre it before anything is drawn.
        let extent = textBounds(block, 0, 0)
        let corner = Vector2((1080 - extent.width) / 2, (1080 - extent.height) / 2)
        drawText(block, corner.x, corner.y)

        drawGuides(around: textBounds(block, corner.x, corner.y))
    }

    /// Marks that say which column came first, since a still picture of the layout
    /// cannot say it on its own.
    private func drawGuides(around box: Rectangle) {
        stroke(mark.withAlpha(0.35))
        strokeWeight(1.5)
        noFill()
        drawRect(corner: Vector2(box.x, box.y), width: box.width, height: box.height)

        // An arrow above the block, running the way the columns fill.
        let y = box.y - 34
        stroke(mark)
        drawLine(box.x, y, box.x + box.width, y)
        drawLine(box.x + box.width, y, box.x + box.width - 16, y - 7)
        drawLine(box.x + box.width, y, box.x + box.width - 16, y + 7)

        noStroke()
        fill(mark)
        textFont(.system)
        textDirection(.automatic)
        textSize(16)
        textAlign(.center, .bottom)
        drawText("COLUMNS FILL LEFT TO RIGHT", box.center.x, y - 16)
        textAlign(.left, .top)
        drawText("FIRST", box.x, box.y + box.height + 18)
        textAlign(.right, .top)
        drawText("LAST", box.x + box.width, box.y + box.height + 18)
    }
}
