// figure: frame=0
//
// Guide diagram: 2D noise as a field over the canvas, one ask per cell,
// drawn twice from the same answers: as brightness on the left, as dot
// size on the right.
import Ollin

final class NoiseTerrain: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)

    override func setup() {
        noiseSeed(6)
        noStroke()
    }

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(21)

        let size = 340.0, top = 120.0
        let cells = 34
        let cell = size / Double(cells)

        for panel in 0..<2 {
            let left = panel == 0 ? 70.0 : 470.0
            for row in 0..<cells {
                for col in 0..<cells {
                    let x = left + Double(col) * cell
                    let y = top + Double(row) * cell
                    let n = noise(Double(col) * cell * 0.012, Double(row) * cell * 0.012)
                    if panel == 0 {
                        fill(Color(white: n))
                        drawRect(x, y, cell, cell)
                    } else {
                        fill(ink)
                        drawCircle(x + cell / 2, y + cell / 2, n * cell * 0.62)
                    }
                }
            }
        }

        fill(ink)
        textAlign(.center, .bottom)
        drawText("as brightness", 70 + size / 2, top - 14)
        drawText("as size", 470 + size / 2, top - 14)
        textAlign(.center, .top)
        drawText("noise(x * 0.012, y * 0.012) · the same answers, worn two ways", width / 2, top + size + 22)
    }
}
