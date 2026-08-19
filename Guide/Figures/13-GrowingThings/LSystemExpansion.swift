// figure: frame=0
//
// Guide diagram (Chapter 13): an L-system grows by rewriting. The same plant
// grammar drawn after one, two, three, and four rounds of rewriting, with the
// length of the instruction string under each: the drawing gets richer
// because the sentence gets longer.
import Ollin

final class LSystemExpansion: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.4)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)

    var drawings: [[Contour]] = []
    var lengths: [Int] = []

    override func setup() {
        seed(1)
        for iterations in 1 ... 4 {
            let r = panelRect(iterations - 1)
            drawings.append(lSystem(.plant, iterations: iterations,
                                    in: r.inset(by: .all(14)), padding: 0))
            lengths.append(LSystem.plant.expanded(iterations: iterations).count)
        }
    }

    func panelRect(_ i: Int) -> Rectangle {
        Rectangle(x: 42 + Double(i) * 204, y: 120, width: 190, height: 300)
    }

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(17)

        noStroke()
        fill(ink)
        textAlign(.center, .top)
        drawText("axiom X, two rules: X grows shoots, F stretches", width / 2, 42)
        textSize(15)
        fill(faint)
        drawText("X → F+[[X]-X]-F[-FX]+X          F → FF", width / 2, 72)

        for (i, drawing) in drawings.enumerated() {
            let r = panelRect(i)
            noFill()
            stroke(soft)
            strokeWeight(2)
            drawRect(r)
            stroke(ink)
            strokeWeight(1.4)
            strokeCap(.round)
            for contour in drawing { drawPolyline(contour.points) }

            noStroke()
            fill(ink)
            textSize(17)
            textAlign(.center, .top)
            drawText("\(i + 1) round\(i == 0 ? "" : "s")", r.x + r.width / 2, r.y + r.height + 16)
            fill(faint)
            textSize(15)
            drawText("\(lengths[i]) letters", r.x + r.width / 2, r.y + r.height + 40)
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("the drawing gets richer because the sentence gets longer", width / 2, 495)
    }
}
