//  Recreation after Vera Molnár — in the spirit of her "Interruptions" (1969)
//  and her order-vs-disorder line works. A homage, not a reproduction.
//
//  Ported from the p5.js sketch week-1/vera-1 (MIT) in
//  https://github.com/eaviles/rtp-sfpc-f21-p5 — itself a p5 port of Zach
//  Lieberman's openFrameworks sample for the RTP class at SFPC, Fall 2021
//  (https://github.com/ofZach/RTP_SFPC_F21). Reworked for Ollin's API.

import Foundation
import Ollin

/// A 40×40 field of short line segments at random rotations, with some omitted
/// where a Perlin-noise field dips below a threshold — Vera Molnár's interplay
/// of order (the grid) and disorder (the rotations and gaps). **Click to
/// recreate**: each click re-rolls the seed for a new variation.
///
/// The original is a static, seeded still image. Here `draw()` re-applies the
/// seed every frame so it looks static, and `mousePressed()` bumps the seed —
/// avoiding any need for `noLoop()`/`redraw()`. Demonstrates `isolated { }` with
/// `translate`/`rotate`, plus `line`, `random`, and Perlin `noise`.
@main
final class Interruptions: Sketch {
    var seed = 0

    override func setup() {
        stroke(.black)
    }

    /// Each click is a fresh roll of the disorder.
    override func mousePressed() {
        seed += 1
    }

    override func draw() {
        background(.white)
        randomSeed(seed)   // re-seed each frame so the image is stable until a click
        noiseSeed(seed)

        for i in 0..<40 {
            for j in 0..<40 {
                let x = map(Double(i), 0, 39, 50, 750)
                let y = map(Double(j), 0, 39, 50, 750)
                isolated {
                    translate(x: x, y: y)
                    rotate(random(0, .tau))
                    // p5's threshold is 0.6; 0.7 reproduces that density against
                    // Ollin's contrast-calibrated noise (same gate: raw < 0.2).
                    if noise(Double(i) * 0.1, Double(j) * 0.1) < 0.7 {
                        line(x1: -15, y1: 0, x2: 15, y2: 0)
                    }
                }
            }
        }
    }
}
