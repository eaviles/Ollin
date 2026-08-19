// figure: frame=0
//
// Guide diagram (Chapter 8): one passage in two identical boxes, with a rule
// down the edge each line is measured to. On the left every character stays
// inside it. On the right the stops that would not fit cross it, and the passage
// takes one line less.
import Ollin

final class HangingStops: Sketch {
    override var canvasSize: CanvasSize { .size(880, 460) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.4)
    let accent = Color(hex: 0xE4572E)
    let panel = Color(hex: 0xE9E4D8)

    /// The opening of the Pillow Book. Its stops are what the figure is about.
    let passage = """
    春はあけぼの。やうやう白くなりゆく山ぎは、すこしあかりて、\
    むらさきだちたる雲のほそくたなびきたる。夏は夜。月のころはさらなり、\
    闇もなほ、螢の多く飛びちがひたる。
    """

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textFont(.system)
        noStroke()

        box(at: Vector2(40, 90), hangs: false, title: "EVERY CHARACTER INSIDE")
        box(at: Vector2(464, 90), hangs: true, title: "STOPS ALLOWED TO HANG")

        fill(faint)
        textSize(14)
        textAlign(.left, .top)
        drawText("the stop takes its neighbour with it", 40, 400)
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
