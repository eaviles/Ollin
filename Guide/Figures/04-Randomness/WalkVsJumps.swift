// figure: frame=0 probe
//
// Guide diagram: chance with and without memory. Top: a fresh roll decides
// each value outright, so the trace is hash. Bottom: each roll only nudges
// the previous value, and a wandering path appears.
import Ollin

final class WalkVsJumps: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.28)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(21)
        randomSeed(6)

        strip(top: 92, label: "y = random(0, h) · a fresh roll each step, no memory") {
            _, h in random(0, h)
        }
        strip(top: 330, label: "y += random(-9, 9) · each roll nudges the last") {
            y, h in
            var next = y + random(-9, 9)
            if next < 0 { next = 0 }
            if next > h { next = h }
            return next
        }
    }

    func strip(top: Double, label: String, next: (Double, Double) -> Double) {
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
        var y = h / 2
        var previousX = left, previousY = top + y
        stroke(accent)
        strokeWeight(2)
        for i in 1..<samples {
            y = next(y, h)
            let x = left + Double(i) / Double(samples - 1) * w
            drawLine(previousX, previousY, x, top + y)
            previousX = x
            previousY = top + y
        }
    }
}
