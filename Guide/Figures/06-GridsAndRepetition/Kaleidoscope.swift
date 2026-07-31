// figure: frame=0
//
// Guide diagram (Chapter 6): the built-in fold. One lopsided wedge drawn
// once, then the same drawing code under an eight-fold symmetry, then under
// a mirrored one. Nothing about the wedge changes between panels.
import Ollin

final class Kaleidoscope: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x232020)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(paper)

        let panels = (0 ..< 3).map {
            Rectangle(x: 25 + Double($0) * 284, y: 66, width: 262, height: 262)
        }
        let titles = ["the wedge alone", "symmetry(8)", "symmetry(8, mirrored: true)"]

        for (i, panel) in panels.enumerated() {
            withState {
                translate(panel.x + panel.width / 2, panel.y + panel.height / 2)
                if i == 1 { symmetry(8) }
                if i == 2 { symmetry(8, mirrored: true) }
                wedge()
            }
            frame(panel, title: titles[i])
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("draw one crooked thing; the folds make it a mandala",
                 width / 2, 364)
    }

    /// A deliberately lopsided wedge, so the folding has something to do.
    func wedge() {
        stroke(ink)
        strokeWeight(3)
        strokeCap(.round)
        noFill()
        drawLine(18, 0, 108, 0)
        drawLine(74, 0, 96, -30)
        drawLine(74, 0, 88, 22)

        noStroke()
        fill(accent)
        drawCircle(108, 0, 8)
        fill(ink)
        drawCircle(96, -30, 4.5)
        drawCircle(46, 0, 3)
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textSize(16)
        textAlign(.left, .middle)
        drawText(title, r.x, r.y - 20)
    }
}
