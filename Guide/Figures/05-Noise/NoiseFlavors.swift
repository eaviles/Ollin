// figure: frame=0
//
// Guide diagram: six landscapes from one seed, same zoom, different rules.
// Top row: layered noise, simplex, and warped fbm. Bottom row: cellular
// distances, ridged creases, and turbulence billows.
import Ollin

final class NoiseFlavors: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)

    override func setup() {
        noiseSeed(6)
        noStroke()
    }

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(19)

        let size = 190.0
        let lefts = [85.0, 345.0, 605.0]
        let tops = [58.0, 318.0]
        let cells = 95
        let cell = size / Double(cells)

        let labels = [["noise(x, y)", "simplexNoise(x, y)", "warpedFbm(x, y)"],
                      ["worley(x, y)", "ridgedFbm(x, y)", "turbulence(x, y)"]]

        for r in 0..<2 {
            for c in 0..<3 {
                for row in 0..<cells {
                    for col in 0..<cells {
                        let px = Double(col) * cell
                        let py = Double(row) * cell
                        let n = flavor(r, c, px * 0.014, py * 0.014)
                        fill(Color(white: min(max(n, 0), 1)))
                        drawRect(lefts[c] + px, tops[r] + py, cell, cell)
                    }
                }
                fill(ink)
                textAlign(.center, .top)
                drawText(labels[r][c], lefts[c] + size / 2, tops[r] + size + 12)
            }
        }
    }

    private func flavor(_ r: Int, _ c: Int, _ x: Double, _ y: Double) -> Double {
        switch (r, c) {
        case (0, 0): return noise(x, y)
        case (0, 1): return simplexNoise(x, y)
        case (0, 2): return warpedFbm(x, y)
        case (1, 0): return worley(x * 1.6, y * 1.6)
        case (1, 1): return ridgedFbm(x, y)
        default: return turbulence(x, y)
        }
    }
}
