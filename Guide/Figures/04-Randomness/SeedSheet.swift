// figure: frame=0
//
// Guide diagram: the same constellation sketch drawn nine times, each tile
// seeded with a different number. A seed replays its exact sequence of rolls,
// so every tile is stable, repeatable, and its own little world.
import Ollin

final class SeedSheet: Sketch {
    override var canvasSize: CanvasSize { .size(900, 930) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.28)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(21)

        let margin = 44.0, gap = 40.0
        let tile = (width - margin * 2 - gap * 2) / 3
        for row in 0..<3 {
            for col in 0..<3 {
                let seedNumber = row * 3 + col + 1
                let x = margin + Double(col) * (tile + gap)
                let y = margin + Double(row) * (tile + gap)
                drawTile(x: x, y: y, size: tile, seedNumber: seedNumber)
            }
        }
    }

    func drawTile(x: Double, y: Double, size: Double, seedNumber: Int) {
        randomSeed(seedNumber)

        noFill()
        stroke(faint)
        strokeWeight(2)
        drawRect(x, y, size, size)

        // Ten random points, connected in the order they were rolled.
        let inset = 30.0
        var xs: [Double] = []
        var ys: [Double] = []
        for _ in 0..<10 {
            xs.append(random(x + inset, x + size - inset))
            ys.append(random(y + inset, y + size - inset))
        }
        stroke(Color(hex: 0x2B2B2B, alpha: 0.45))
        strokeWeight(1.5)
        for i in 1..<10 {
            drawLine(xs[i - 1], ys[i - 1], xs[i], ys[i])
        }
        noStroke()
        fill(accent)
        for i in 0..<10 {
            drawCircle(xs[i], ys[i], random(4, 10))
        }

        fill(ink)
        textAlign(.center, .top)
        drawText("seed \(seedNumber)", x + size / 2, y + size + 8)
    }
}
