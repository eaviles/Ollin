// figure: frame=0
//
// Guide diagram (Chapter 13): an outline rebuilt from spinning circles. The
// same letter reconstructed with three, twelve, and sixty-four terms, with
// the circles that produced each drawn faintly behind. More circles, more
// detail; the largest ones were always doing most of the work.
import Ollin

final class EpicycleTerms: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x232020)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)
    let accent = Color(hex: 0xE4572E)

    var chain: Epicycles?

    override func setup() {
        textFont(OutlineFont.systemBold)
        textAlign(.center, .middle)
        textSize(210)
        guard let glyph = textToShapes("g", at: Vector2(0, 0)).first,
              let outline = glyph.contours.first else { return }
        chain = Epicycles(outline, samples: 512)
    }

    override func draw() {
        background(paper)
        guard let chain else { return }

        let counts = [3, 12, 64]
        for (i, terms) in counts.enumerated() {
            let panel = Rectangle(x: 25 + Double(i) * 284, y: 66,
                                  width: 262, height: 262)
            let middle = Vector2(panel.x + panel.width / 2,
                                 panel.y + panel.height / 2)

            withState {
                translate(middle)
                // The construction at one moment, so the circles are visible.
                noFill()
                stroke(soft)
                strokeWeight(1)
                drawEpicycles(chain, at: 0.14, terms: terms)

                // The whole path those circles trace over one lap.
                stroke(accent)
                strokeWeight(2)
                drawPolygon(chain.path(samples: 600, terms: terms).points)
            }

            frame(panel, title: "\(terms) circles")
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("any closed outline is a sum of circles going round",
                 width / 2, 364)
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textSize(17)
        textAlign(.left, .middle)
        drawText(title, r.x, r.y - 20)
    }
}
