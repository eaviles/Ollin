// figure: frame=0
//
// Guide payoff (Chapter 4): an ordered grid of nested quadrilaterals whose
// corners slip further off their posts with every row, seeded so each value
// of the Seed knob is a repeatable variation. After Vera Molnár's studies
// of order and disorder.
import Ollin

final class DisorderGrid: Sketch {
    @Param("Disorder", 0...1) var disorder = 0.6
    @Param("Seed", 1...9999) var gridSeed = 7

    let ink = Color(hex: 0x232020)
    let accents: [Color] = [
        Color(hex: 0xC1272D), Color(hex: 0x2E5FA3), Color(hex: 0xD9A21B),
    ]

    override func draw() {
        randomSeed(gridSeed)
        background(Color(hex: 0xF2EDE4))
        noFill()
        strokeWeight(2.5)

        let columns = 9, rows = 9, layers = 4
        let margin = 90.0
        let cell = (width - margin * 2) / Double(columns)
        for r in 0..<rows {
            let unrest = Double(r) / Double(rows - 1) * disorder
            let d = unrest * cell * 0.35
            for c in 0..<columns {
                let left = margin + Double(c) * cell
                let top = margin + Double(r) * cell
                for k in 0..<layers {
                    let inset = cell * 0.1 * Double(k + 1)
                    let x1 = left + inset + random(-1, 1) * d
                    let y1 = top + inset + random(-1, 1) * d
                    let x2 = left + cell - inset + random(-1, 1) * d
                    let y2 = top + inset + random(-1, 1) * d
                    let x3 = left + cell - inset + random(-1, 1) * d
                    let y3 = top + cell - inset + random(-1, 1) * d
                    let x4 = left + inset + random(-1, 1) * d
                    let y4 = top + cell - inset + random(-1, 1) * d
                    stroke(ink)
                    if random() < 0.08 {
                        stroke(randomChoice(accents))
                    }
                    drawLine(x1, y1, x2, y2)
                    drawLine(x2, y2, x3, y3)
                    drawLine(x3, y3, x4, y4)
                    drawLine(x4, y4, x1, y1)
                }
            }
        }
    }

    override func mousePressed() {
        gridSeed += 1
    }
}
