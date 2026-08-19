// Guide figure (Chapter 18): the logistic map's bifurcation diagram as a
// density image, with the first two forks and the period-3 window labeled.
// Everything is a pure function of the map, so the figure is deterministic.
import Ollin

final class Bifurcation: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    override func draw() {
        background(.white)

        let map = IteratedMap.logistic()
        let frame = Rectangle(x: 40, y: 24, width: 800, height: 452)
        if let plate = map.bifurcationImage(width: 800, height: 452,
                                            samplesPerColumn: 12_000) {
            drawImage(plate, in: frame)
        }

        // The story's landmarks: the first fork, the second, and the wide
        // periodic window inside the chaos.
        let accent = Color(hex: 0xB0492C)
        textFont(OutlineFont.system)
        textSize(17)
        textAlign(.center, .top)
        for (r, label) in [(3.0, "first fork"), (3.4495, "second"), (3.8284, "period 3")] {
            let x = frame.x + (r - 2.4) / 1.6 * frame.width
            stroke(accent.withAlpha(0.85))
            strokeWeight(1.5)
            drawLine(x, frame.y + frame.height + 2, x, frame.y + frame.height + 12)
            noStroke()
            fill(accent)
            drawText(label, x, frame.y + frame.height + 18)
            fill(Color(white: 0.35))
            drawText(String(format: "%.2f", r), x, frame.y + frame.height + 40)
        }
    }
}
