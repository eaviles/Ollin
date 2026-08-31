//  Ported from the p5.js sketch week-4/pattern-1 (MIT) in
//  https://github.com/eaviles/rtp-sfpc-f21-p5, itself a p5 port of Zach
//  Lieberman's openFrameworks sample for the RTP class at SFPC, Fall 2021
//  (https://github.com/ofZach/RTP_SFPC_F21). Reworked for Ollin's API.

import Ollin

/// Both point layouts of `Grid`, side by side. The left panel shows the two
/// element kinds: one loop over `grid.cells` draws the faint cell outlines, a
/// second over `grid.points` draws a dot at each cell center. With the default
/// `.center` distribution the points sit inside their cells, so the two layers
/// line up; each dot pulses in a wave radiating from the panel's center, sized
/// by the cell so it fills any canvas.
///
/// The right panel is the same lattice call with `distribution: .spanning`:
/// the dots reach the bounds edge to edge (the corner dots sit on the
/// corners), and each is colored black or white by a small modulo rule on its
/// `dot.row` and `dot.column`. Every row's pattern is shifted by an `offset`
/// that rises and falls (0 to 4 to 0) down the grid, so the black/white
/// columns weave into diagonal bands. Nothing on that side depends on `time`,
/// so the weave holds still while the left panel pulses.
@main
final class GridField: Sketch {
    override func draw() {
        background(Color(hex: 0x10_10_14))

        // Two square panels sharing the middle of the canvas.
        let panel = shortSide / 2
        let top = (height - panel) / 2
        let left = Rectangle(x: width / 2 - panel, y: top, width: panel, height: panel)
        let right = Rectangle(x: width / 2, y: top, width: panel, height: panel)

        // Left, the default `.center` distribution: the cells as faint
        // outlines, the points as a pulsing dot at each cell center.
        let g = Grid(in: left, columns: 12, rows: 12, padding: .all(panel * 0.08))
        let mid = g.bounds.center
        noFill()
        stroke(Color(white: 1, alpha: 0.08))
        strokeWeight(1)
        for cell in g.cells {
            drawRect(cell.frame)
        }
        noStroke()
        for dot in g.points {
            let d = dist(dot.position.x, dot.position.y, mid.x, mid.y)
            let pulse = sin(time * 2 - d * 0.015)
            let radius = map(pulse, -1, 1, g.cellWidth * 0.06, g.cellWidth * 0.44)
            fill(Color(hue: map(d, 0, panel * 0.6, 0.56, 0.92), saturation: 0.7, brightness: 0.95))
            drawCircle(center: dot.position, radius: radius)
        }

        // Right, `distribution: .spanning` over a gray plate: the woven dots.
        fill(.gray)
        drawRect(right)
        let lattice = Grid(in: right, columns: 21, rows: 21,
                           padding: .all(panel * 0.08), distribution: .spanning)
        let radius = lattice.bounds.width / 20 / 2   // dots touch: half the gap between them
        for dot in lattice.points {
            var offset = dot.row % 8
            if offset > 4 { offset = 8 - offset }
            fill((dot.column + offset) % 4 < 2 ? .white : .black)
            drawCircle(center: dot.position, radius: radius)
        }
    }
}
