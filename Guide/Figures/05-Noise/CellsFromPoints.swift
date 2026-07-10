// figure: frame=0
//
// Guide diagram: cellular (Worley) noise read two ways from the same hidden
// points. Left: the distance to the nearest point, dark at each point and
// brightening toward the walls. Right: the border reading, dark exactly on
// the walls between cells.
import Ollin

final class CellsFromPoints: Sketch {
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
        let cells = 170
        let cell = size / Double(cells)

        for panel in 0..<2 {
            let left = panel == 0 ? 70.0 : 470.0
            for row in 0..<cells {
                for col in 0..<cells {
                    let px = Double(col) * cell
                    let py = Double(row) * cell
                    let x = left + px
                    let y = top + py
                    if panel == 0 {
                        let n = worley(px * 0.012, py * 0.012)
                        fill(Color(white: min(n, 1)))
                    } else {
                        let b = worley(px * 0.012, py * 0.012, feature: .border)
                        fill(Color(white: min(b * 2.5, 1)))
                    }
                    drawRect(x, y, cell, cell)
                }
            }
        }

        fill(ink)
        textAlign(.center, .bottom)
        drawText("worley(x, y)", 70 + size / 2, top - 14)
        drawText("feature: .border", 470 + size / 2, top - 14)
        textAlign(.center, .top)
        drawText("one hidden point per cell · every dark core on the left sits on one", width / 2, top + size + 22)
    }
}
