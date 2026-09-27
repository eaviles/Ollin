// figure: frame=0 themed
//
// Guide diagram (Chapter 8): one Latin passage in two identical boxes, with a
// rule down the right edge each line is measured to. On the left the box wraps
// the passage and every line stops where its last word ends. On the right the
// same box is justified, so the spaces open until every full line reaches the
// rule, and the last line of the paragraph keeps its natural length.
import Ollin
import OllinDiagram

final class BothEdgesFlush: Sketch {
    override var canvasSize: CanvasSize { .size(880, 460) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.4) }
    var accent: Color { theme.accent }
    var panel: Color { theme.card }

    /// The passage the chapter's specimen sets, so the step shows the text
    /// the finished sketch goes on to use.
    let passage = """
        A letter is a shape before it is a sound. Ask for it as geometry and \
        the whole chapter opens up: outlines you can warp, contours you can \
        stroke, and points you can respace until marks sit evenly along the \
        edge of an O. Everything here is one word, three kinds of letter, and one passage.
        """

    override func draw() {
        background(paper)
        textFont(.system)
        noStroke()

        box(at: Vector2(x: 40, y: 90), justified: false, title: "RAGGED RIGHT")
        box(at: Vector2(x: 464, y: 90), justified: true, title: "JUSTIFIED")

        fill(faint)
        textSize(14)
        textAlign(.left, .top)
        drawText("each line stops where its last word ends", 40, 400)
        fill(accent)
        drawText("the spaces open until every full line reaches the rule", 464, 400)
    }

    /// One box of the passage, with a rule down the edge it is measured to.
    private func box(at origin: Vector2, justified: Bool, title: String) {
        let box = Rectangle(x: origin.x, y: origin.y, width: 376, height: 290)
        fill(panel)
        drawRect(corner: Vector2(x: box.x, y: box.y), width: box.width, height: box.height)

        fill(faint)
        textSize(13)
        textAlign(.left, .bottom)
        drawText(title, box.x, box.y - 12)

        fill(ink)
        textSize(21)
        textAlign(.left, .top)
        if justified { textJustify() } else { noTextJustify() }
        drawText(passage, in: box.inset(by: .all(18)))
        noTextJustify()

        stroke(accent)
        strokeWeight(1)
        drawLine(box.x + box.width - 18, box.y + 8,
                 box.x + box.width - 18, box.y + box.height - 8)
        noStroke()
    }
}
