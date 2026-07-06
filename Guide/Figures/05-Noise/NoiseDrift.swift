// figure: gif duration=4 fps=10 width=360
//
// Guide figure: the 2D field from the terrain diagram, with the third noise
// dimension fed by a slow out-and-back clock (pingPong), so the weather
// drifts and the loop closes on itself.
import Ollin

final class NoiseDrift: Sketch {
    override var canvasSize: CanvasSize { .size(540, 540) }

    override func setup() {
        noiseSeed(6)
        noStroke()
    }

    override func draw() {
        let z = pingPong(over: 4) * 0.9
        let cells = 45
        let cell = width / Double(cells)
        for row in 0..<cells {
            for col in 0..<cells {
                let n = noise(Double(col) * cell * 0.012, Double(row) * cell * 0.012, z)
                fill(Color(white: n))
                drawRect(Double(col) * cell, Double(row) * cell, cell, cell)
            }
        }
    }
}
