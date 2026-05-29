//  Ported from the p5.js sketch week-1/random (MIT) in
//  https://github.com/eaviles/rtp-sfpc-f21-p5 — itself a p5 port of Zach
//  Lieberman's openFrameworks sample for the RTP class at SFPC, Fall 2021
//  (https://github.com/ofZach/RTP_SFPC_F21). Reworked for Ollin's API.

import Ollin

/// A dot per column across the canvas, each offset vertically by `signedNoise`
/// (Perlin noise in `-1...1`) — a smooth, correlated wave, where each dot stays
/// close to its neighbors. `mouseX` slides the sample position, so the wave
/// drifts as you move. The jagged counterpart is `RandomBand`; together they show
/// random vs. noise. (The source faked signed noise with `map(noise(...), 0, 1,
/// -1, 1)`; here `signedNoise` gives the `-1...1` range directly.)
@main
final class NoiseWave: Sketch {
    override func setup() {
        noStroke()
    }

    override func draw() {
        background(.black)
        // Sample the noise over a normalized span (≈8 humps across the canvas) and
        // offset by ⅛ of the height, so the wave keeps its shape at any size.
        for i in 0..<Int(width) {
            let t = Double(i) / width                         // 0…1 across the canvas
            let n = signedNoise(t * 8 + mouseX / width * 8)   // mouse scrolls the wave
            drawCircle(Double(i), height / 2 + n * height / 8, 2 * scale)
        }
    }
}
