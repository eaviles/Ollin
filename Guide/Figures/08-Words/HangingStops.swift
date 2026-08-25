// figure: frame=0 themed
//
// Guide diagram (Chapter 8): one passage in two identical boxes, with a rule
// down the edge each line is measured to. On the left every character stays
// inside it. On the right the stops that would not fit cross it, and the passage
// takes one line less.
import Ollin
import OllinDiagram

final class HangingStops: Sketch {
    override var canvasSize: CanvasSize { .size(880, 460) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.4) }
    var accent: Color { theme.accent }
    var panel: Color { theme.card }

    /// The opening of the Pillow Book. Its stops are what the figure is about.
    let passage = """
    春はあけぼの。やうやう白くなりゆく山ぎは、すこしあかりて、\
    むらさきだちたる雲のほそくたなびきたる。夏は夜。月のころはさらなり、\
    闇もなほ、螢の多く飛びちがひたる。
    """

    override func draw() {
        background(paper)
        textFont(.system)
        noStroke()

        box(at: Vector2(40, 90), hangs: false, title: "EVERY CHARACTER INSIDE")
        box(at: Vector2(464, 90), hangs: true, title: "STOPS ALLOWED TO HANG")

        fill(faint)
        textSize(14)
        textAlign(.left, .top)
        drawText("the stop takes its neighbor with it", 40, 400)
        fill(accent)
        drawText("the stop crosses the rule, and the pair stays", 464, 400)
    }

    /// One box of the passage, with a rule down the edge it is measured to.
    private func box(at origin: Vector2, hangs: Bool, title: String) {
        let box = Rectangle(x: origin.x, y: origin.y, width: 376, height: 290)
        fill(panel)
        drawRect(corner: Vector2(box.x, box.y), width: box.width, height: box.height)

        fill(faint)
        textSize(13)
        textAlign(.left, .bottom)
        drawText(title, box.x, box.y - 12)

        fill(ink)
        textSize(22)
        textAlign(.left, .top)
        if hangs { textHangingPunctuation() } else { noTextHangingPunctuation() }
        drawText(passage, in: box.inset(by: .all(18)))
        noTextHangingPunctuation()

        stroke(accent)
        strokeWeight(1)
        drawLine(box.x + box.width - 18, box.y + 8,
                 box.x + box.width - 18, box.y + box.height - 8)
        noStroke()
    }
}
