import Foundation
import Ollin

/// A full stop allowed to sit past the end of its line.
///
/// A stop may not open a line. So a stop that will not fit takes the character it
/// follows to the next line with it, and leaves a hole at the edge where both used
/// to be. Letting it hang past the edge instead keeps the line full and the margin
/// even. Japanese typesetting calls it ぶら下げ, and Latin typesetters do the same
/// thing to keep a right margin looking straight.
///
/// The same passage is set twice here, in two identical boxes, with a rule down
/// each right edge. On the right the stops cross that rule.
@main
final class HangingStops: Sketch {
    override var canvasSize: CanvasSize { .size(1080, 720) }

    @Param("Let stops hang", icon: "text.alignright")
    var hanging = true

    @Param("Size", 18...34, icon: "textformat.size")
    var glyphSize = 24.0

    let ink = Color(hex: 0x1B1A17)
    let paper = Color(hex: 0xF2EDE1)
    let panel = Color(hex: 0xE7DFCE)
    let rule = Color(hex: 0xC1452E)

    /// The opening of the Pillow Book, written about the year 1002. Its stops and
    /// commas are what this example is about.
    let passage = """
    春はあけぼの。やうやう白くなりゆく山ぎは、すこしあかりて、\
    むらさきだちたる雲のほそくたなびきたる。夏は夜。月のころはさらなり、\
    闇もなほ、螢の多く飛びちがひたる。また、ただ一つ二つなど、\
    ほのかにうち光りて行くもをかし。雨など降るもをかし。
    """

    override func setup() {
        textFont(.system)
        noStroke()
    }

    override func draw() {
        background(paper)
        box(at: Vector2(60, 160), hangs: false, title: "EVERY CHARACTER INSIDE")
        box(at: Vector2(596, 160), hangs: hanging,
            title: hanging ? "STOPS ALLOWED TO HANG" : "EVERY CHARACTER INSIDE")
        caption()
    }

    /// One box of the passage, with a rule down the edge the text is measured to.
    private func box(at origin: Vector2, hangs: Bool, title: String) {
        let box = Rectangle(x: origin.x, y: origin.y, width: 424, height: 460)

        fill(panel)
        drawRect(corner: Vector2(box.x, box.y), width: box.width, height: box.height)

        fill(ink.withAlpha(0.45))
        textSize(14)
        textAlign(.left, .bottom)
        drawText(title, box.x, box.y - 14)

        fill(ink)
        textSize(glyphSize)
        textAlign(.left, .top)
        if hangs { textHangingPunctuation() } else { noTextHangingPunctuation() }
        drawText(passage, in: box.inset(by: .all(22)))
        noTextHangingPunctuation()

        // The edge every line is measured to. A hung stop crosses it.
        stroke(rule)
        strokeWeight(1)
        drawLine(box.x + box.width - 22, box.y + 10,
                 box.x + box.width - 22, box.y + box.height - 10)
        noStroke()
    }

    private func caption() {
        fill(ink.withAlpha(0.5))
        textSize(15)
        textAlign(.center, .top)
        drawText("a stop that will not fit takes its neighbour to the next line, unless it may hang",
                 540, 664)
    }
}
