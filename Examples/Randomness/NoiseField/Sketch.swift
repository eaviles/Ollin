//  Ported from the p5.js sketch week-1/noise (MIT) in
//  https://github.com/eaviles/rtp-sfpc-f21-p5 — itself a p5 port of Zach
//  Lieberman's openFrameworks sample for the RTP class at SFPC, Fall 2021
//  (https://github.com/ofZach/RTP_SFPC_F21). Reworked for Ollin's API.

import Ollin

/// An 80×80 grid of cells shaded by 3D Perlin `noise`: the cell's (x, y) feeds
/// the first two noise dimensions and `mouseX` feeds the third, so moving the
/// mouse left↔right scrubs the cloudy field through its depth.
///
/// Each cell's noise value (`0...1`) becomes a grayscale fill via `Color(white:)`.
/// The grid covers the whole canvas, so no `background` is needed.
@main
final class NoiseField: Sketch {
    override func setup() {
        noStroke()
    }

    override func draw() {
        // The 80×80 grid fills the whole canvas, so each cell is 1/80 of it.
        let g = grid(columns: 80, rows: 80)
        for cell in g.cells {
            let shade = noise(Double(cell.column) * 0.01, Double(cell.row) * 0.01, mouseX * 0.1)
            fill(Color(white: shade))
            drawRect(cell.frame)
        }
    }
}
