// figure: frame=0
//
// Guide diagram: random forgets, noise remembers. Top: a fresh roll decides
// each height outright, hash. Bottom: the same march across the canvas asks
// noise instead, and nearby questions get nearby answers: a glide.
import Ollin

final class RandomVsNoise: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.28)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(21)
        seed(6)

        strip(top: 92, label: "y = random(0, h) · every answer stands alone") { _, h in
            random(0, h)
        }
        strip(top: 330, label: "y = noise(x * 0.02) * h · nearby questions, nearby answers") { x, h in
            noise(x * 0.02) * h
        }
    }

    func strip(top: Double, label: String, sample: (Double, Double) -> Double) {
        let left = 70.0, w = width - 140, h = 130.0

        noStroke()
        fill(ink)
        textAlign(.left, .bottom)
        drawText(label, left, top - 12)

        noFill()
        stroke(faint)
        strokeWeight(2)
        drawRect(left, top, w, h)

        let samples = 140
        var previousX = left, previousY = top + sample(0, h)
        stroke(accent)
        strokeWeight(2)
        for i in 1..<samples {
            let x = left + Double(i) / Double(samples - 1) * w
            let y = top + sample(x - left, h)
            drawLine(previousX, previousY, x, y)
            previousX = x
            previousY = y
        }
    }
}
