// figure: frame=0 probe
//
// Guide diagram: smoothing a jittery signal. The gray path is a clean sweep
// with seeded jitter added; the accent path is the same samples run through
// the adaptive filter behind @Smoothed.
import Ollin

final class SmoothedSignal: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.35)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        randomSeed(11)
        background(Color(hex: 0xF7F5F1))
        textSize(21)

        let left = 80.0, right = 800.0
        let midY = 270.0

        // A clean sweep, plus jitter: the kind of signal a sensor hands you.
        var raw: [Vector2] = []
        let samples = 240
        for i in 0...samples {
            let t = Double(i) / Double(samples)
            let x = left + t * (right - left)
            let clean = midY - sin(t * .tau * 1.25) * 110 * sin(t * .tau * 0.5)
            raw.append(Vector2(x, clean + random(-26, 26)))
        }

        // The same samples through the filter behind @Smoothed.
        var filter = OneEuroFilter<Double>(minCutoff: 1, beta: 0.01)
        var smooth: [Vector2] = []
        for p in raw {
            smooth.append(Vector2(p.x, filter.filter(p.y, dt: 1.0 / 60.0)))
        }

        noFill()
        stroke(faint)
        strokeWeight(2)
        drawPolyline(raw)
        stroke(accent)
        strokeWeight(3.5)
        drawPolyline(smooth)

        noStroke()
        fill(Color(hex: 0x2B2B2B, alpha: 0.6))
        textAlign(.left, .middle)
        drawText("the raw signal", left + 10, 480)
        fill(accent)
        drawText("after @Smoothed", left + 220, 480)
    }
}
