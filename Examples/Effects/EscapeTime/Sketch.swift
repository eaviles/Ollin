import Ollin

/// One iteration, six readings. Every tile runs the same escape-time loop, z to
/// z² + c; what differs is only the question asked of each orbit. The
/// **mandelbrot** and **julia** tiles ask *when* it escaped, coloring by the
/// smooth iteration count through a palette (`phase` cycles the bands, and the
/// julia's `c` rides a small orbit so the filigree morphs). The four **orbit
/// trap** tiles ask instead *how close* it ever came to a shape held in the
/// plane: a cross grows the classic stalks, a point makes soft knots, a circle
/// and a square light up wherever an orbit skims their outline, and two of the
/// traps turn with `angle` so the stalks sweep through the filigree.
///
/// Try it: zoom the Mandelbrot in (`center:` near the seahorse valley at
/// (-0.75, 0.1) with `zoom: 60` and more `iterations`), swap a trap tile's `c`
/// for your own Julia point (near the set's edge is richest), or tighten `glow`
/// to thin the filaments.
@main
final class EscapeTime_Example: Sketch {
    private let labelFont = OutlineFont.system

    override func draw() {
        background(Color(white: 0.06))

        // Match `drawSheet`'s own 3 x 2 layout for six items, generating each
        // set at its cell's size so nothing stretches.
        let space = width * 0.01
        let w = Int((width - space * 4) / 3), h = Int((height - space * 3) / 2)

        let tiles: [(String, Generator)] = [
            ("mandelbrot", .mandelbrot(phase: time * 0.03)),
            ("julia", .julia(c: Vector2(-0.79 + 0.012 * cos(time * 0.3),
                                        0.15 + 0.012 * sin(time * 0.2)),
                             phase: time * 0.02)),
            ("cross", .orbitTrap(.cross(.zero), c: Vector2(-0.79, 0.15), zoom: 1.2,
                                 angle: time * 0.12)),
            ("point", .orbitTrap(.point(.zero), glow: 0.15)),
            ("circle", .orbitTrap(.circle(center: .zero, radius: 0.5),
                                  c: Vector2(0.285, 0.01), zoom: 1.2, glow: 0.02)),
            ("square", .orbitTrap(.square(center: .zero, radius: 0.35),
                                  c: Vector2(-0.4, 0.6), zoom: 1.2, glow: 0.05,
                                  angle: 0.5 + time * 0.08)),
        ]

        textFont(labelFont)
        drawSheet(tiles, columns: 3) { generator, cell in
            drawImage(generate(generator, width: w, height: h).image, in: cell)
        }
    }
}
