//  Recreation after Vera Molnár — in the spirit of her concentric-square works
//  ("(Dés)Ordres", "Structures de carrés"): order and disorder in squares.
//  A homage, not a reproduction.
//
//  Ported from the p5.js sketch week-1/vera-2 (MIT) in
//  https://github.com/eaviles/rtp-sfpc-f21-p5 — itself a p5 port of Zach
//  Lieberman's openFrameworks sample for the RTP class at SFPC, Fall 2021
//  (https://github.com/ofZach/RTP_SFPC_F21). Reworked for Ollin's API.

import Ollin

/// A 5×5 grid of cells, each a stack of 10 concentric squares — but each square
/// is drawn only ~95% of the time, so the orderly nesting frays into gaps.
/// **Move the mouse**: `mouseX` seeds the randomness, so sliding it left↔right
/// scrubs through different disorder patterns.
///
/// Demonstrates center-anchored `rect(center:width:height:)` and `randomSeed`
/// driven by input. After Vera Molnár.
@main
final class NestedSquares: Sketch {
    override func setup() {
        strokeWeight(2)
        noFill()
    }

    override func draw() {
        background(.white)
        randomSeed(Int(mouseX))   // the pattern is stable per mouseX, scrubs as you move
        for i in 0..<5 {
            for j in 0..<5 {
                let x = map(Double(i), 0, 4, 100, 700)
                let y = map(Double(j), 0, 4, 100, 700)
                for k in 0..<10 {
                    let size = map(Double(k), 0, 9, 5, 144)
                    if random() < 0.95 {
                        rect(center: Vector2(x, y), width: size, height: size)
                    }
                }
            }
        }
    }
}
