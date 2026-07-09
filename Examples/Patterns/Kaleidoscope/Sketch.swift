import Ollin

/// A kaleidoscope mandala from one wedge of drawing. `symmetry(8, mirrored:
/// true)` replicates every draw call that follows into sixteen copies (eight
/// rotations, each with its mirror), so the sketch draws a single arm: a chain
/// of breathing dots, a swaying ribbon, and an orbiting ring, and the folds
/// complete the picture. The center medallion is drawn after `noSymmetry()`,
/// so it lands once.
///
/// All motion is phase-driven over one declared `loopDuration`, so
/// `--export-loop` writes a seamless lap.
@main
final class Kaleidoscope: Sketch {
    private let period = 8.0
    override var loopDuration: Double? { period }

    override func draw() {
        background(Color(hex: 0x0B0E14))
        let lap = loopProgress(over: period) * .tau

        translate(width / 2, height / 2)
        symmetry(8, mirrored: true)

        let teal = Color(hex: 0x2EC4B6)
        let ember = Color(hex: 0xF6511D)
        let cream = Color(hex: 0xFFF3D6)

        // A chain of dots along the arm, each breathing on its own phase; the
        // mirror doubles it into a petal outline.
        noStroke()
        for i in 0..<9 {
            let f = Double(i) / 8
            let radius = (90 + f * 380) * scale
            let swing = 0.34 - f * 0.16 + sin(lap + f * .tau) * 0.10
            fill(Color.mix(teal, ember, t: f, in: .oklch))
            drawCircle(cos(swing) * radius, sin(swing) * radius, (30 - f * 22) * scale)
        }

        // A ribbon swaying from near the center out to the rim (its phases are
        // offset so it's never straight).
        noFill()
        stroke(cream.withAlpha(0.85))
        strokeWeight(4 * scale)
        let reach = 470 * scale
        let bow = sin(lap + 2.1) * 130 * scale
        drawBezier(Vector2(70 * scale, 0),
                   Vector2(reach * 0.55, bow),
                   Vector2(reach, sin(lap * 2 + 1.3) * 40 * scale))

        // A small orbiting ring, melting hue against its neighbors.
        stroke(Color.mix(ember, teal, t: (sin(lap) + 1) / 2, in: .oklch))
        strokeWeight(3 * scale)
        let orbit = (250 + cos(lap) * 60) * scale
        drawCircle(cos(0.55) * orbit, sin(0.55) * orbit, 26 * scale)

        // The medallion draws once: symmetry off, back at the center.
        noSymmetry()
        fill(cream)
        noStroke()
        drawCircle(0, 0, 26 * scale)
        noFill()
        stroke(cream.withAlpha(0.6))
        strokeWeight(3 * scale)
        drawCircle(0, 0, 44 * scale)
    }
}
