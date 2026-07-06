// figure: gif duration=4 fps=10 width=360
//
// Guide figure: the 2D field from the terrain diagram, drifting on the
// loop: parameter. One lap tours a closed circle through the field, so the
// weather comes home and the GIF closes on itself with no reversal.
import Ollin

final class NoiseDrift: Sketch {
    override var canvasSize: CanvasSize { .size(540, 540) }

    override func setup() {
        noiseSeed(6)
        noStroke()
    }

    override func draw() {
        let cells = 45
        let cell = width / Double(cells)
        for row in 0..<cells {
            for col in 0..<cells {
                let x = Double(col) * cell
                let y = Double(row) * cell
                let n = noise(x * 0.012, y * 0.012, loop: loopProgress(over: 4), radius: 0.6)
                fill(Color(white: n))
                drawRect(x, y, cell, cell)
            }
        }
    }
}
