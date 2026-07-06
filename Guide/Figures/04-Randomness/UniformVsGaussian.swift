// figure: frame=0
//
// Guide diagram: the two everyday shapes of chance. The same five hundred
// dots scattered twice: uniform spreads them evenly, Gaussian piles them
// around the mean. Histograms below count where the dots landed.
import Ollin

final class UniformVsGaussian: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.28)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(21)
        randomSeed(3)

        drawPanel(x: 70, title: "random(0, w)", note: "uniform: anywhere, equally",
                  gaussian: false)
        drawPanel(x: 470, title: "randomGaussian(mean:deviation:)",
                  note: "clustered around the mean", gaussian: true)
    }

    func drawPanel(x: Double, title: String, note: String, gaussian: Bool) {
        let w = 340.0
        let top = 96.0, boxHeight = 250.0
        let histTop = top + boxHeight + 26, histHeight = 110.0

        noStroke()
        fill(ink)
        textAlign(.center, .bottom)
        drawText(title, x + w / 2, top - 44)
        fill(Color(hex: 0x2B2B2B, alpha: 0.6))
        drawText(note, x + w / 2, top - 16)

        noFill()
        stroke(faint)
        strokeWeight(2)
        drawRect(x, top, w, boxHeight)

        // Scatter 500 dots and count them into bins as they land.
        let bins = 20
        var counts = [Int](repeating: 0, count: bins)
        noStroke()
        fill(Color(hex: 0xE4572E, alpha: 0.55))
        var placed = 0
        while placed < 500 {
            var sampleX = random(w)
            if gaussian {
                sampleX = randomGaussian(mean: w / 2, deviation: w / 6.5)
                if sampleX < 0 || sampleX >= w { continue }
            }
            drawCircle(x + sampleX, top + random(12, boxHeight - 12), 4)
            counts[Int(sampleX / w * Double(bins))] += 1
            placed += 1
        }

        // The histogram, on a shared scale so the two panels compare.
        let barWidth = w / Double(bins)
        stroke(faint)
        strokeWeight(2)
        drawLine(x, histTop + histHeight, x + w, histTop + histHeight)
        noStroke()
        fill(Color(hex: 0x2B2B2B, alpha: 0.55))
        for b in 0..<bins {
            let h = Double(counts[b]) / 62.0 * histHeight
            drawRect(x + Double(b) * barWidth + 2, histTop + histHeight - h,
                     barWidth - 4, h)
        }
    }
}
