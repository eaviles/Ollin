// figure: frame=0 themed
//
// Guide diagram (Chapter 15): an outline rebuilt from spinning circles. The
// same letter reconstructed with three, twelve, and sixty-four terms, with
// the circles that produced each drawn faintly behind. More circles, more
// detail; the largest ones were always doing most of the work.
import Ollin
import OllinDiagram

final class EpicycleTerms: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }
    var accent: Color { theme.accent }

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
