// figure: gif duration=2.5 fps=12 width=360
//
// Guide figure (Chapter 14): points the field carries. Every frame, each
// dot takes a small step along the curl field at its own position, and a
// faint wash over the last frame turns the steps into trails. A dot that
// leaves the canvas is put back somewhere new. The seed is set once in
// setup, so the field is the same every frame and the run reproduces.
import Ollin

final class Drift: Sketch {
    var dots: [Vector2] = []

    override func setup() {
        seed(7)
        dots = poissonDisk(radius: 36)
        background(Color(hex: 0x101318))
        noClear()
    }

    override func draw() {
        let field = curlField(scale: 0.0022)
        dots = field.advected(dots, stepLength: 3)
        for i in dots.indices where !bounds.contains(dots[i]) {
            dots[i] = Vector2(random(width), random(height))
        }

        // Fade the last frame a little instead of erasing it: trails.
        noStroke()
        fill(Color(hex: 0x101318).withAlpha(0.06))
        drawRect(bounds)

        fill(Color(hex: 0x9AD9CE))
        drawCircles(dots, radius: 2.4)
    }
}
