// figure: frame=0 probe themed
//
// Guide diagram: smoothing a jittery signal. The gray path is a clean sweep
// with seeded jitter added; the accent path is the same samples run through
// the adaptive filter behind @Smoothed.
import Ollin
import OllinDiagram

final class SmoothedSignal: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.35) }
    var accent: Color { theme.accent }

    override func draw() {
        randomSeed(11)
        background(paper)
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
            smooth.append(Vector2(p.x, filter.filter(p.y, deltaTime: 1.0 / 60.0)))
        }

        noFill()
        stroke(faint)
        strokeWeight(2)
        drawPolyline(raw)
        stroke(accent)
        strokeWeight(3.5)
        drawPolyline(smooth)

        noStroke()
        fill(theme.ink(0.6))
        textAlign(.left, .middle)
        drawText("the raw signal", left + 10, 480)
        fill(accent)
        drawText("after @Smoothed", left + 220, 480)
    }
}
