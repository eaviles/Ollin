// figure: frame=0 unstable
// Unstable is measured, not assumed: two back-to-back lossless renders of this
// sketch differ at the pixel level on a quiet machine, so the nondeterminism
// is in the render itself, not the JPEG encoder. Worth a real diagnosis one day.
//
// Guide diagram: the five paths a sway can take between the two ends of its
// range, each plotted over one whole lap. Every one of them arrives back where
// the lap began, which is what lets a swaying sketch export a seamless loop.
import Ollin

final class SwayShapes: Sketch {
    override var canvasSize: CanvasSize { .size(880, 330) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.45)
    let pale = Color(hex: 0x2B2B2B, alpha: 0.12)

    static let named: [(SwayShape, String)] = [(.sine, ".sine"), (.triangle, ".triangle"),
                                               (.saw, ".saw"), (.square, ".square"),
                                               (.wander, ".wander")]
    static let lap = 6.0
    let top = 90.0, swing = 52.0

    override func setup() {
        textFont(OutlineFont.system)
    }

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        for (i, entry) in SwayShapes.named.enumerated() {
            let left = 46.0 + Double(i) * 168
            plot(entry.0, left: left, width: 140)
            noStroke()
            fill(ink)
            textSize(19)
            textAlign(.center, .top)
            drawText(entry.1, left + 70, top + swing * 2 + 24)
        }
        fill(faint)
        textSize(17)
        textAlign(.center, .top)
        drawText("one whole lap of sway(over:in:shape:), from the low end of the range to the high one and back",
                 440, 268)
    }

    /// What `shape` reads at `lap` of the way through, asked of `sway` itself:
    /// the phase argument moves the question rather than the clock.
    func value(of shape: SwayShape, at lap: Double) -> Double {
        sway(over: SwayShapes.lap, shape: shape, phase: lap - time / SwayShapes.lap)
    }

    func plot(_ shape: SwayShape, left: Double, width: Double) {
        stroke(pale)
        strokeWeight(1)
        drawLine(left, top, left + width, top)
        drawLine(left, top + swing * 2, left + width, top + swing * 2)

        noFill()
        stroke(ink.withAlpha(0.8))
        strokeWeight(2.5)
        var run: [Vector2] = []
        var previous = value(of: shape, at: 0)
        for i in 0...160 {
            let lap = Double(i) / 160
            let unit = value(of: shape, at: lap)
            if abs(unit - previous) > 0.5 && (shape == .square || shape == .saw) {
                drawPolyline(run)
                run = []
            }
            run.append(Vector2(left + lap * width, top + swing * 2 - unit * swing * 2))
            previous = unit
        }
        drawPolyline(run)
    }
}
