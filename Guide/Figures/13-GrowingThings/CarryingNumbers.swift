// figure: frame=0
//
// Guide diagram (Chapter 13): what a symbol carrying a number buys. The same
// idea three times: a plain grammar whose every segment is one step, a
// parametric one whose segments carry their own length, and a parametric one
// carrying a width as well, drawn as marks so the trunk is thick.
import Ollin

final class CarryingNumbers: Sketch {
    override var canvasSize: CanvasSize { .size(880, 560) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.4)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)

    var plain: [Contour] = []
    var carried: [Contour] = []
    var tapered: [StrokeMark] = []

    override func setup() {
        seed(1)
        plain = lSystem(.tree, iterations: 3, in: panelRect(0).inset(by: .all(14)), padding: 0)
        carried = lSystem(.selfSimilarBranch, iterations: 9,
                          in: panelRect(1).inset(by: .all(14)), padding: 0)
        tapered = lSystemMarks(.taperedTree(), iterations: 9,
                               in: panelRect(2).inset(by: .all(14)), padding: 0)
    }

    func panelRect(_ i: Int) -> Rectangle {
        Rectangle(x: 42 + Double(i) * 273, y: 122, width: 250, height: 300)
    }

    override func draw() {
        background(Color(hex: 0xF7F5F1))

        noStroke()
        fill(ink)
        textSize(17)
        textAlign(.center, .top)
        drawText("a plain grammar picks the next symbol, a parametric one picks its numbers too",
                 width / 2, 42)
        textSize(15)
        fill(faint)
        drawText("F is one step        F(s) is a step s long        !(w)F(s) is s long and w wide",
                 width / 2, 72)

        for i in 0 ..< 3 {
            noFill()
            stroke(soft)
            strokeWeight(2)
            drawRect(panelRect(i))
        }

        strokeCap(.round)
        strokeJoin(.round)
        noFill()

        stroke(ink)
        strokeWeight(1.4)
        for contour in plain { drawPolyline(contour.points, closed: false) }
        for contour in carried { drawPolyline(contour.points, closed: false) }

        // The third panel draws through marks, so the width the grammar set at
        // every branch arrives with the line rather than being thrown away.
        strokeWeight(9)
        for mark in tapered { drawMark(mark) }

        let captions = [("every segment one step", "F [ + F ] [ - F ]"),
                        ("each carries its length", "A(s) → F(s) [ +A(s/R) ] [ -A(s/R) ]"),
                        ("and its width", "A(s,w) → !(w) F(s) [ … ]")]
        for (i, caption) in captions.enumerated() {
            let r = panelRect(i)
            noStroke()
            fill(ink)
            textSize(17)
            textAlign(.center, .top)
            drawText(caption.0, r.x + r.width / 2, r.y + r.height + 16)
            fill(faint)
            textSize(14)
            drawText(caption.1, r.x + r.width / 2, r.y + r.height + 40)
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("the same rewriting, with arithmetic in the rules", width / 2, 505)
    }
}
