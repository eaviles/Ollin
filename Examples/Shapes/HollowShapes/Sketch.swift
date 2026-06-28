import Ollin

/// `hollow(_:)` turns a region shape's solid interior into a constant-width band
/// hugging its outline — the `opOnion` trick `drawRing` uses, generalized to
/// every shape. Here a grid of shapes breathes its band width from 0 (solid) up
/// to a fat ring and back, so you can watch each one open from a filled shape
/// into a hollow band. Each cell also keeps a thin white `stroke`, which borders
/// *both* edges of the band — the framed-ring look you can't get from a stroke
/// alone (that would spend the only stroke on the band itself). Every cell is a
/// single instanced quad, so the whole grid is effectively free. `solid()` (not
/// shown) returns to filled shapes.
@main
final class HollowShapes: Sketch {
    let rows = 4
    let columns = 6

    override func setup() {
        stroke(Color(white: 0.95))
    }

    override func draw() {
        background(Color(white: 0.07))
        strokeWeight(2 * scale)
        // Shapes sit at evenly-spaced interior points, one inset gap off each edge.
        let colGap = width / Double(columns + 1)
        let rowGap = height / Double(rows + 1)
        let g = grid(columns: columns, rows: rows,
                     padding: .symmetric(horizontal: colGap, vertical: rowGap),
                     distribution: .spanning)
        let r = min(rowGap, colGap) * 0.42

        for p in g.points {
            let x = p.position.x, y = p.position.y

            // Band width breathes 0…r, phase-offset per cell so the grid
            // ripples between solid and fully hollow.
            let phase = time * 1.5 - Double(p.column) * 0.5 - Double(p.row) * 0.4
            let band = (0.5 - 0.5 * cos(phase)) * r
            hollow(band)

            fill(Colormap.turbo.color(at: Double(p.column) / Double(columns - 1)))

            switch (p.row + p.column) % 6 {
            case 0: drawCircle(x, y, r)
            case 1: drawRect(x - r, y - r, r * 2, r * 2, cornerRadius: r * 0.3)
            case 2: drawStar(x, y, r, r * 0.5, points: 5)
            case 3: drawTriangle(x, y, r)
            case 4: drawNgon(x, y, r, sides: 6)
            default: drawHeart(x, y, r * 1.7)
            }
        }
    }
}
