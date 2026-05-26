//  Ported from the p5.js sketch week-1/random (MIT) in
//  https://github.com/eaviles/rtp-sfpc-f21-p5 — itself a p5 port of Zach
//  Lieberman's openFrameworks sample for the RTP class at SFPC, Fall 2021
//  (https://github.com/ofZach/RTP_SFPC_F21). Reworked for Ollin's API.

import Ollin

/// 800 dots across the canvas, each jittered vertically by `random(-100, 100)` —
/// a rough, uncorrelated band, every dot independent of its neighbors.
/// `randomSeed(mouseX)` holds the scatter steady for a given cursor position, so
/// sliding the mouse re-rolls it. The smooth counterpart is `NoiseWave` — the
/// two together are the classic random-vs-noise comparison.
@main
final class RandomBand: Sketch {
    override func setup() {
        noStroke()
    }

    override func draw() {
        background(.black)
        randomSeed(Int(mouseX))
        for i in 0..<800 {
            circle(x: Double(i), y: 400 + random(-100, 100), radius: 2)
        }
    }
}
