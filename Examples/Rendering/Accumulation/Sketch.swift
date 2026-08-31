import Ollin

/// Accumulation: the canvas isn't cleared each frame, so faint marks pile up on
/// a persistent surface and the image is *built up over time* rather than
/// redrawn. `noClear()` turns it on; `blendMode(.add)` makes the marks sum as
/// light. Each frame draws only a handful of nearly invisible dots, and the
/// picture is the pile: minutes of them, none ever erased.
///
/// Three slow pens swing on breathing circles, each leaving a short faint trace
/// per frame, so their figures emerge from nothing and keep deepening where the
/// paths recross. Drag to scribble a soft spray of your own; press any key to
/// wipe the surface and start the exposure again (while accumulating,
/// `background(_:)` is the reset).
///
/// The same piling-up earns real depth of field in `Rendering/DepthOfField`,
/// where every accumulated sample is jittered by its distance from a focal
/// plane and the blur emerges from the statistics of where the light fell.
@main
final class Accumulation_Example: Sketch {
    /// A pen on a breathing circle: a fast revolution whose radius swells and
    /// shrinks on a much slower one, so the trace never quite repeats.
    private struct Pen {
        var tone: Double        // 0…1 color key
        var reach: Double       // orbit radius, as a fraction of the short side
        var breathe: Double     // how fast the radius swells (revolutions/sec)
        var turn: Double        // how fast the pen goes round (revolutions/sec)
        var p1, p2: Double      // phases for each
    }
    private var pens: [Pen] = []
    private var wipeRequested = false
    private let base = Color(red: 0.02, green: 0.015, blue: 0.03)

    override func setup() {
        seed(11)
        background(base)     // the one base wipe
        noClear()            // then accumulate forever
        for i in 0 ..< 3 {
            pens.append(Pen(tone: Double(i) / 3 + random(0.1),
                            reach: random(0.18, 0.30),
                            breathe: random(0.05, 0.16),
                            turn: random(0.6, 1.4),
                            p1: random(.tau), p2: random(.tau)))
        }
    }

    override func keyPressed() {
        wipeRequested = true
    }

    override func draw() {
        if wipeRequested {   // reset the exposure on the frame after the key
            background(base)
            wipeRequested = false
        }
        blendMode(.add)      // every mark adds a little light to the pile
        noStroke()

        let cx = width / 2, cy = height / 2
        for pen in pens {
            // One dot is nearly invisible; the figure is the accumulation.
            let ink = Colormap.magma.color(at: 0.25 + pen.tone * 0.6)
            fill(Color(red: ink.red, green: ink.green, blue: ink.blue, alpha: 0.05))
            for k in 0 ..< 40 {
                // Sample a short arc of the pen's path, anchored to the clock,
                // so the trace stays continuous at any frame rate.
                let t = time + Double(k) * 0.0009
                let r = shortSide * pen.reach * (1 + 0.35 * sin(t * pen.breathe * .tau + pen.p1))
                let a = t * pen.turn * .tau + pen.p2
                drawCircle(cx + cos(a) * r, cy + sin(a) * r, 1.4 * scale)
            }
        }

        // The instrument: drag to scribble a soft spray of the same faint ink.
        if mouseIsPressed {
            fill(Color(white: 1, alpha: 0.05))
            for _ in 0 ..< 60 {
                let j = ring(innerRadius: 0, outerRadius: 18 * scale)
                drawCircle(mouseX + j.x, mouseY + j.y, 1.2 * scale)
            }
        }
    }
}
