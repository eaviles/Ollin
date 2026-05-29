//  Ported from the p5.js sketch week-4/pattern-4 (MIT) in
//  https://github.com/eaviles/rtp-sfpc-f21-p5 — itself a p5 port of Zach
//  Lieberman's openFrameworks sample for the RTP class at SFPC, Fall 2021
//  (https://github.com/ofZach/RTP_SFPC_F21). Reworked for Ollin's API.

import Foundation
import CoreGraphics
import Ollin

/// Proportional "energy" distribution: 100 columns whose *widths* are shares of
/// a moving total, so they always sum to the block width. Each column's energy is
/// a positive `sin(index + time)` value; dividing by the running total turns it
/// into a fraction of the width. Every column is a vertical stack of 100 short
/// rects in a black/white checkerboard.
///
/// Demonstrates `translate` (a per-frame origin shift, used here to center the
/// block in the canvas) alongside `drawRect`.
@main
final class EnergyGrid: Sketch {
    override func setup() {
        noStroke()
    }

    override func draw() {
        background(Color(white: 60.0 / 255.0))

        // Each column's energy is a positive sine wave over its index, drifting
        // with time; the sum is the total to normalize against.
        let energy = (0..<100).map { map(sin(Double($0) * 0.1 + time), -1, 1, 0.01, 1.0) }
        let total = energy.reduce(0, +)

        // A centered square block filling 80% of the canvas — a 10% margin all
        // around, against the gray field.
        let block = min(width, height) * 0.8
        translate((width - block) / 2, (height - block) / 2)
        var x = 0.0
        for i in 0..<100 {
            let columnWidth = block * (energy[i] / total)
            for j in 0..<100 {
                let y = map(Double(j), 0, 100, 0, block)
                fill((i + j) % 2 == 0 ? .black : .white)
                drawRect(x, y, columnWidth, block / 100)
            }
            x += columnWidth
        }
    }
}
