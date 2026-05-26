//  Ported from the p5.js sketch week-4/pattern-4 (MIT) in
//  https://github.com/eaviles/rtp-sfpc-f21-p5 — itself a p5 port of Zach
//  Lieberman's openFrameworks sample for the RTP class at SFPC, Fall 2021
//  (https://github.com/ofZach/RTP_SFPC_F21). Reworked for Ollin's API.

import Foundation
import CoreGraphics
import Ollin

/// Proportional "energy" distribution: 100 columns whose *widths* are shares of
/// a moving total, so they always sum to 500 points. Each column's energy is a
/// positive `sin(index + time)` value; dividing by the running total turns it
/// into a fraction of the width. Every column is a vertical stack of 100 short
/// rects in a black/white checkerboard.
///
/// Demonstrates `translate` (a per-frame origin shift, used here to center the
/// 500×500 block in the 700×700 canvas) alongside `rect`.
@main
final class EnergyGrid: Sketch {
    override var preferredSize: CGSize { CGSize(width: 700, height: 700) }

    override func setup() {
        noStroke()
    }

    override func draw() {
        background(Color(white: 60.0 / 255.0))

        // Each column's energy is a positive sine wave over its index, drifting
        // with time; the sum is the total to normalize against.
        let energy = (0..<100).map { map(sin(Double($0) * 0.1 + time), -1, 1, 0.01, 1.0) }
        let total = energy.reduce(0, +)

        translate(x: 100, y: 100)   // center the 500×500 block in the 700 canvas
        var x = 0.0
        for i in 0..<100 {
            let columnWidth = 500 * (energy[i] / total)
            for j in 0..<100 {
                let y = map(Double(j), 0, 100, 0, 500)
                fill((i + j) % 2 == 0 ? .black : .white)
                rect(x: x, y: y, width: columnWidth, height: 5)
            }
            x += columnWidth
        }
    }
}
