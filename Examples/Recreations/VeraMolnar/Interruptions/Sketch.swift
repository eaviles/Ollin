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
/// avoiding any need for `noLoop()`/`redraw()`. Demonstrates `withState { }` with
/// `translate`/`rotate`, plus `drawLine`, `random`, and Perlin `noise`.
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

        // Canvas-relative: a 1/16 inset, with each segment ~0.3 of the inset long.
        let s = min(width, height)
        let margin = s * 0.0625
        let half = margin * 0.3
        for i in 0..<40 {
            for j in 0..<40 {
                let x = map(Double(i), 0, 39, margin, width - margin)
                let y = map(Double(j), 0, 39, margin, height - margin)
                withState {
                    translate(x, y)
                    rotate(random(0, .tau))
                    // 0.7 (the source uses 0.6) keeps the intended density
                    // against Ollin's contrast-calibrated noise: gate is raw < 0.2.
                    if noise(Double(i) * 0.1, Double(j) * 0.1) < 0.7 {
                        drawLine(-half, 0, half, 0)
                    }
                }
            }
        }
    }
}
