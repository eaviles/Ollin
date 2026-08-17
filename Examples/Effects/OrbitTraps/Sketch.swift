import Ollin

/// **Orbit traps**: the escape-time iteration colored not by when each orbit
/// escapes but by how close it ever came to a shape held in the plane. A cross
/// grows the classic stalks, a point makes soft knots, a circle and a square
/// light up wherever an orbit skims their outline. Two of the traps turn with
/// `angle`, so the stalks sweep through the filigree.
///
/// Try it: swap any tile's `c` for your own Julia point (near the Mandelbrot
/// set's edge is richest), or tighten `glow` to thin the filaments.
@main
final class OrbitTraps_Example: Sketch {
    private let labelFont = OutlineFont.system

    override func draw() {
        background(Color(white: 0.06))

        let gutter = width * 0.012
        let w = Int((width - gutter * 3) / 2), h = Int((height - gutter * 3) / 2)
        let tiles: [(Generator, String)] = [
            (.orbitTrap(.cross(.zero), c: Vector2(-0.79, 0.15), zoom: 1.2,
                        angle: time * 0.12), "cross"),
            (.orbitTrap(.point(.zero), glow: 0.15), "point"),
            (.orbitTrap(.circle(center: .zero, radius: 0.5), c: Vector2(0.285, 0.01),
                        zoom: 1.2, glow: 0.02), "circle"),
            (.orbitTrap(.square(center: .zero, radius: 0.35), c: Vector2(-0.4, 0.6),
                        zoom: 1.2, glow: 0.05, angle: 0.5 + time * 0.08), "square"),
        ]

        for (i, tile) in tiles.enumerated() {
            let x = gutter + Double(i % 2) * (Double(w) + gutter)
            let y = gutter + Double(i / 2) * (Double(h) + gutter)
            drawImage(generate(tile.0, width: w, height: h).image,
                      in: Rectangle(x: x, y: y, width: Double(w), height: Double(h)))
            withState {
                noStroke()
                fill(Color(white: 0, alpha: 0.55))
                drawRect(x, y + Double(h) - 28, Double(w), 28)
                fill(.white)
                textFont(labelFont); textSize(15); textAlign(.left, .middle)
                drawText(tile.1, x + 10, y + Double(h) - 14)
            }
        }
    }
}
