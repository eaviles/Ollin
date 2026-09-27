// figure: frame=0
//
// Guide payoff (Chapter 4): an ordered grid of nested quadrilaterals whose
// corners slip further off their posts with every row. The nudges are rolled
// once in setup() from the sketch's variation, so every seed is a repeatable
// picture and the arrow keys step through them; the page's render pins
// variation 7. After Vera Molnár's studies of order and disorder.
import Ollin

final class DisorderGrid: Sketch {
    @Param("Disorder", 0...1) var disorder = 0.6

    let columns = 9, rows = 9, layers = 4
    let ink = Color(hex: 0x232020)
    let accents: [Color] = [
        Color(hex: 0xC1272D), Color(hex: 0x2E5FA3), Color(hex: 0xD9A21B),
    ]
    var nudges: [Double] = []   // eight per quadrilateral, rolled once
    var inks: [Color] = []      // one per quadrilateral

    override func setup() {
        seed(7)   // the variation on this page; delete the line to roll a fresh one
        roll()
    }

    func roll() {
        nudges = []
        inks = []
        for _ in 0..<(rows * columns * layers) {
            for _ in 0..<8 {
                nudges.append(random(-1, 1))
            }
            if random() < 0.08 {
                inks.append(randomChoice(accents))
            } else {
                inks.append(ink)
            }
        }
    }

    override func draw() {
        background(Color(hex: 0xF2EDE4))
        noFill()
        strokeWeight(2.5)

        let margin = 90.0
        let cell = (width - margin * 2) / Double(columns)
        var quad = 0
        for r in 0..<rows {
            let unrest = Double(r) / Double(rows - 1) * disorder
            let d = unrest * cell * 0.35
            for c in 0..<columns {
                let left = margin + Double(c) * cell
                let top = margin + Double(r) * cell
                for k in 0..<layers {
                    let inset = cell * 0.1 * Double(k + 1)
                    let n = quad * 8
                    let x1 = left + inset + nudges[n] * d
                    let y1 = top + inset + nudges[n + 1] * d
                    let x2 = left + cell - inset + nudges[n + 2] * d
                    let y2 = top + inset + nudges[n + 3] * d
                    let x3 = left + cell - inset + nudges[n + 4] * d
                    let y3 = top + cell - inset + nudges[n + 5] * d
                    let x4 = left + inset + nudges[n + 6] * d
                    let y4 = top + cell - inset + nudges[n + 7] * d
                    stroke(inks[quad])
                    drawLine(x1, y1, x2, y2)
                    drawLine(x2, y2, x3, y3)
                    drawLine(x3, y3, x4, y4)
                    drawLine(x4, y4, x1, y1)
                    quad += 1
                }
            }
        }
        drawText("Variation \(variation)", margin, height - margin / 2,
                 size: 20, color: ink)
    }

    override func keyPressed() {
        if keyCode == .rightArrow {
            seed(variation + 1)
            roll()
        }
        if keyCode == .leftArrow {
            seed(variation - 1)
            roll()
        }
    }
}
