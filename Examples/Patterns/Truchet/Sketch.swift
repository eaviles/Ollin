import Ollin

/// Truchet tiling: one tile design on every cell of a grid, each spun to a
/// random orientation. The `.arcs` tile joins the cell's edge midpoints with two
/// quarter-circles, so the arcs meet across cell borders and a wall of random
/// spins reads as smooth, meandering loops.
///
/// The tiling is a pure function of the seed, so it's computed once and held;
/// what moves is a flow field that shifts each arc's color, so waves of hue
/// travel along the connected curves. Each arc is an ordinary `Contour`, so the
/// same line-work would stroke, hatch, or export to SVG for a pen plotter.
@main
final class TruchetTiles: Sketch {
    private var arcs: [Contour] = []

    override func draw() {
        if arcs.isEmpty {
            seed(3)
            arcs = truchet(columns: 12, rows: 12, tile: .arcs)
        }

        background(Color(hex: 0x0E1116))
        noFill()
        strokeCap(.round)
        strokeWeight(11 * scale)

        let a = Color(hex: 0x2EC4B6)   // teal
        let b = Color(hex: 0xF6511D)   // ember

        for arc in arcs {
            // A flow through the field shifts each arc's color; since the arcs
            // connect across cells, the hue sweeps along the loops as waves.
            let mid = arc.points[arc.points.count / 2]
            let flow = signedNoise(mid.x * 0.003, mid.y * 0.003, time * 0.9)
            stroke(Color.mix(a, b, (flow + 1) * 0.5))
            drawPolyline(arc.points, closed: false)
        }
    }
}
