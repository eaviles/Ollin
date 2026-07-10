import Ollin

/// A shimmer over a `TriangleGrid`: alternating up- and down-pointing
/// equilateral triangles, each tinted by a slow noise field sampled at its
/// center. The two orientations read the field through two different palettes,
/// so the checkerboard parity shows as an interleaved weave even though every
/// cell follows the same motion.
@main
final class TriangleWeave: Sketch {
    override func draw() {
        background(Color(hex: 0x0E1116))
        let grid = triangleGrid(columns: 23, rows: 11, padding: .all(50 * scale), gutter: 5 * scale)

        noStroke()
        for cell in grid.cells {
            let n = noise(cell.center.x * 0.0022, cell.center.y * 0.0022, time * 0.35)
            let up = Color.mix(Color(hex: 0x113A4E), Color(hex: 0x3FB8AF), t: n)
            let down = Color.mix(Color(hex: 0x3A1330), Color(hex: 0xEE7752), t: n)
            fill(cell.pointsUp ? up : down)
            drawPolygon(cell.vertices)
        }
    }
}
