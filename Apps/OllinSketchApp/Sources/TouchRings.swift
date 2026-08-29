import Ollin

/// A sketch for the glass: rings that breathe on their own, and a mark that
/// follows the finger.
///
/// It is written exactly as a desk sketch is. A finger is the pointer, so
/// `mouseX`, `mouseY`, and `mouseIsPressed` read the touch with no change, and a
/// stylus or a screen that measures force fills `pressure` as well.
///
/// `.resizable` makes the canvas the size of the screen it lands on, so the
/// piece fills a phone held either way and a tablet too. A fixed canvas would
/// be letterboxed inside it instead.
final class TouchRings: Sketch {
    override var canvasSize: CanvasSize { .square(1080) }
    override var windowMode: WindowMode { .resizable }

    /// Where the mark is now. It runs after the finger rather than jumping to
    /// it, so a lifted finger leaves the mark to coast to a stop.
    private var mark = Vector2(0, 0)

    override func setup() {
        mark = Vector2(width / 2, height / 2)
    }

    override func draw() {
        background(Color(red: 0.05, green: 0.05, blue: 0.07))

        let center = Vector2(width / 2, height / 2)
        let short = min(width, height)

        noFill()
        strokeWeight(2)
        for ring in 0..<9 {
            let step = Double(ring) / 9
            let radius = short * (0.06 + step * 0.42) + sin(time * 1.2 - step * 3) * short * 0.02
            stroke(Color(hue: 0.55 + step * 0.25, saturation: 0.5, brightness: 1,
                         alpha: 0.25 + (1 - step) * 0.4))
            drawCircle(center: center, radius: radius)
        }

        mark += (Vector2(mouseX, mouseY) - mark) * 0.18

        // A press swells the mark, and so does the force behind it where the
        // screen can measure one.
        let base = short * 0.03
        let swell = mouseIsPressed ? base * (pressureIsAvailable ? 1 + pressure * 2 : 2) : base
        noStroke()
        fill(Color(red: 1, green: 0.85, blue: 0.4, alpha: 0.9))
        drawCircle(center: mark, radius: swell)
    }
}
