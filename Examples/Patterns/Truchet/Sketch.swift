import Ollin

/// Truchet tiling: one tile design on every cell of a grid, each spun to a
/// random orientation. Both built-in tiles share the canvas: on the left, the
/// `.arcs` tile joins the cell's edge midpoints with two quarter-circles, so
/// the arcs meet across cell borders and a wall of random spins reads as
/// smooth, meandering loops; on the right, the `.diagonals` tile draws one
/// corner-to-corner stroke per cell, and the same random spins read as a maze
/// of corridors.
///
/// The tilings are pure functions of the seed, so they're computed once and
/// held; what moves is a flow field that shifts each contour's color, so waves
/// of hue travel along the connected curves and corridors alike. Each piece is
/// an ordinary `Contour`, so the same line-work would stroke, hatch, or export
/// to SVG for a pen plotter.
@main
final class TruchetTiles: Sketch {
    private var pieces: [Contour] = []

    override func draw() {
        if pieces.isEmpty {
            seed(3)
            let left = Rectangle(x: 0, y: 0, width: width / 2, height: height)
            let right = Rectangle(x: width / 2, y: 0, width: width / 2, height: height)
            pieces = truchet(in: left, columns: 6, rows: 12, tile: .arcs)
                + truchet(in: right, columns: 6, rows: 12, tile: .diagonals)
        }

        background(Color(hex: 0x0E1116))
        noFill()
        strokeCap(.round)
        strokeWeight(11 * scale)

        let a = Color(hex: 0x2EC4B6)   // teal
        let b = Color(hex: 0xF6511D)   // ember

        for piece in pieces {
            // A flow through the field shifts each piece's color; since the
            // marks connect across cells, the hue sweeps along the loops and
            // corridors as waves.
            let mid = piece.points[piece.points.count / 2]
            let flow = signedNoise(mid.x * 0.003, mid.y * 0.003, time * 0.9)
            stroke(Color.mix(a, b, (flow + 1) * 0.5))
            drawPolyline(piece.points, closed: false)
        }
    }
}
