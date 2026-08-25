// figure: frame=0 themed
//
// Guide diagram: the two everyday shapes of chance. The same five hundred
// dots scattered twice: uniform spreads them evenly, Gaussian piles them
// around the mean. Histograms below count where the dots landed.
import Ollin
import OllinDiagram

final class UniformVsGaussian: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.28) }
    var accent: Color { theme.accent }

    override func draw() {
        background(paper)
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
        fill(theme.ink(0.6))
        drawText(note, x + w / 2, top - 16)

        noFill()
        stroke(faint)
        strokeWeight(2)
        drawRect(x, top, w, boxHeight)

        // Scatter 500 dots and count them into bins as they land.
        let bins = 20
        var counts = [Int](repeating: 0, count: bins)
        noStroke()
        fill(theme.accent(0.55))
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
        fill(theme.ink(0.55))
        for b in 0..<bins {
            let h = Double(counts[b]) / 62.0 * histHeight
            drawRect(x + Double(b) * barWidth + 2, histTop + histHeight - h,
                     barWidth - 4, h)
        }
    }
}
