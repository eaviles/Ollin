// figure: frame=60
//
// Guide figure: the Chapter 2 finished sketch. A quilt of cells sampling one
// ramp diagonally, jittered by seeded randomness; a click swaps the seed for
// a fresh variation of the same field. The ramp is an analogous harmony of
// one base color, blended in OKLCH, so the Base parameter re-colors the field.
import Ollin

final class ColorField: Sketch {
    @Param("Base") var base = Color(hex: 0x5E60CE)
    @Param("Columns", 4...28) var columns = 14
    @Param("Jitter", 0...1) var jitter = 0.4

    var fieldSeed = 7

    var ramp: Ramp {
        Palette.analogous(of: base, count: 5, spread: 1.0 / 8).ramp(in: .oklch)
    }

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
