import Ollin

/// A 16×16 grid showing both halves of `Grid`: one loop over `grid.cells` draws
/// the faint cell outlines, a second over `grid.points` draws a dot at each cell
/// center. With the default `.center` distribution the points sit inside their
/// cells, so the two layers line up. Each dot pulses in a wave radiating from the
/// center, sized by the cell so it fills any canvas.
@main
final class GridField: Sketch {
    override func draw() {
        background(Color(hex: 0x10_10_14))
        let g = grid(columns: 16, rows: 16, padding: .all(min(width, height) * 0.08))
        let mid = g.bounds.center

        // The cells: faint outlines, one per cell rectangle.
        noFill()
        stroke(Color(white: 1, alpha: 0.08))
        strokeWeight(1)
        for cell in g.cells {
            drawRect(cell.frame)
        }

        // The points: a pulsing dot at each cell center.
        noStroke()
        for dot in g.points {
            let d = dist(dot.position.x, dot.position.y, mid.x, mid.y)
            let pulse = sin(time * 2 - d * 0.015)
            let radius = map(pulse, -1, 1, g.cellWidth * 0.06, g.cellWidth * 0.44)
            fill(Color(hue: map(d, 0, width * 0.6, 0.56, 0.92), saturation: 0.7, brightness: 0.95))
            drawCircle(center: dot.position, radius: radius)
        }
    }
}
