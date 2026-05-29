import Ollin

/// The three ways a circular `drawArc` closes — open, chord, pie — side by side,
/// each with a fill and a stroke so the difference reads: `.open` strokes only
/// the curve (the chord stays open), `.chord` adds the straight chord, `.pie`
/// strokes the two radii through the center. The shared sweep animates, growing
/// and shrinking, so you can watch each mode enclose the same arc differently.
/// Circular arcs take the SDF path — analytic fill, stroke, and anti-aliasing.
@main
final class ArcModes: Sketch {
    override func setup() {
        strokeWeight(8)
        stroke(.black)
    }

    override func draw() {
        background(.white)
        let r = width / 8
        let y = height / 2
        let begin = -0.5
        let sweep = map(sin(time * 0.5), -1, 1, 0.6, Double.tau * 0.72)

        arc(width * 1 / 6, y, r, begin, sweep, .open,  Color(red: 0.20, green: 0.55, blue: 0.95))
        arc(width * 3 / 6, y, r, begin, sweep, .chord, Color(red: 0.30, green: 0.78, blue: 0.55))
        arc(width * 5 / 6, y, r, begin, sweep, .pie,   Color(red: 0.98, green: 0.65, blue: 0.20))
    }

    private func arc(_ x: Double, _ y: Double, _ r: Double,
                     _ begin: Double, _ sweep: Double, _ mode: ArcMode, _ c: Color) {
        fill(c)
        drawArc(x, y, r, r, start: begin, stop: begin + sweep, mode: mode)
    }
}
