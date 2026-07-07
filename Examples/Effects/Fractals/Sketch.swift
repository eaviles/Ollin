import Ollin

/// **Escape-time fractals** as generators: the Mandelbrot set on the left, a
/// Julia set on the right. Both color by the smooth iteration count through a
/// palette; `phase` cycles the bands, and the Julia's `c` rides a small orbit
/// so the whole filigree morphs.
///
/// Try it: zoom the Mandelbrot in (`center:` near the seahorse valley at
/// (-0.75, 0.1) with `zoom: 60` and more `iterations`), or steer the Julia's
/// `c` with the mouse.
@main
final class Fractals_Example: Sketch {
    private let labelFont = OutlineFont.system

    override func draw() {
        background(Color(white: 0.06))

        let gutter = width * 0.012
        let w = Int((width - gutter * 3) / 2), h = Int(height - gutter * 2)

        let mandelbrot = generate(.mandelbrot(phase: time * 0.03), width: w, height: h)
        let julia = generate(.julia(c: Vector2(-0.79 + 0.012 * cos(time * 0.3),
                                               0.15 + 0.012 * sin(time * 0.2)),
                                    phase: time * 0.02),
                             width: w, height: h)

        for (i, tile) in [("mandelbrot", mandelbrot), ("julia", julia)].enumerated() {
            let x = gutter + Double(i) * (Double(w) + gutter)
            drawImage(tile.1.image, in: Rectangle(x: x, y: gutter,
                                                  width: Double(w), height: Double(h)))
            withState {
                noStroke()
                fill(Color(white: 0, alpha: 0.55))
                drawRect(x, gutter + Double(h) - 28, Double(w), 28)
                fill(.white)
                textFont(labelFont); textSize(15); textAlign(.left, .middle)
                drawText(tile.0, x + 10, gutter + Double(h) - 14)
            }
        }
    }
}
