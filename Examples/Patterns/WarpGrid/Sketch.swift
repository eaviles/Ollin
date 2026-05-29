//  Ported from the p5.js sketch week-4/pattern-2 (MIT) in
//  https://github.com/eaviles/rtp-sfpc-f21-p5 — itself a p5 port of Zach
//  Lieberman's openFrameworks sample for the RTP class at SFPC, Fall 2021
//  (https://github.com/ofZach/RTP_SFPC_F21). Reworked for Ollin's API.

import Foundation
import Ollin

/// A 30×30 checkerboard of rectangles whose columns warp toward one edge. Each
/// column's left/right edge is a 0...1 fraction raised to a `mouseX`-driven
/// power (`pow`), so moving the cursor squeezes the columns to one side and
/// stretches the rest — the checkerboard breathes horizontally under the mouse.
///
/// Demonstrates `drawRect`: every cell is one `drawRect(x, y, width, height)`, filled
/// black or white by an `(i + j)` parity rule. The columns sit at zero width
/// until the mouse first moves (`mouseX` starts at 0, making the exponent 0).
@main
final class WarpGrid: Sketch {
    override func setup() {
        noStroke()
    }

    override func draw() {
        background(.black)
        let cellHeight = width / 30
        for i in 0..<30 {
            // Column edges, warped by a mouseX-driven power curve. `i`-only, so
            // hoisted out of the inner loop.
            let leftPct  = pow(map(Double(i),     0, 30, 0, 1), mouseX * 0.01)
            let rightPct = pow(map(Double(i + 1), 0, 30, 0, 1), mouseX * 0.01)
            let left  = map(leftPct,  0, 1, 0, width)
            let right = map(rightPct, 0, 1, 0, width)
            for j in 0..<30 {
                let y = map(Double(j), 0, 30, 0, width)
                fill((i + j) % 2 == 0 ? .white : .black)
                drawRect(left, y, right - left, cellHeight)
            }
        }
    }
}
