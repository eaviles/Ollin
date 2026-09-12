// figure: frame=60
//
// Guide figure: the Chapter 2 payoff. A quilt of cells sampling one ramp
// diagonally, jittered by seeded randomness; a click swaps the seed for a
// fresh variation of the same poster.
import Ollin

final class ColorField: Sketch {
    @Param("Columns", 4...28) var columns = 14
    @Param("Jitter", 0...1) var jitter = 0.4

    var fieldSeed = 7

    let ramp = Ramp([
        Color(hex: 0x14213D), Color(hex: 0x5E60CE),
        Color(hex: 0xE56B6F), Color(hex: 0xFFB703), Color(hex: 0xFFF3E0),
    ])

    override func draw() {
        randomSeed(fieldSeed)
        background(Color(hex: 0x0E1116))
        noStroke()
        let margin = 70.0, gutter = 7.0
        let cell = (width - margin * 2 - gutter * Double(columns - 1)) / Double(columns)
        for c in 0..<columns {
            for r in 0..<columns {
                let x = margin + Double(c) * (cell + gutter)
                let y = margin + Double(r) * (cell + gutter)
                let diagonal = Double(c + r) / Double(columns * 2 - 2)
                let t = diagonal
                    + random(-0.5, 0.5) * jitter * 0.5
                    + sin(time * .tau / 5 + diagonal * 4) * 0.16
                fill(ramp.color(at: t))
                drawRect(x, y, cell, cell)
            }
        }
    }

    override func mousePressed() {
        fieldSeed += 1
    }
}
