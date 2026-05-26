//  Ported from the p5.js sketch week-1/random (MIT) in
//  https://github.com/eaviles/rtp-sfpc-f21-p5 — itself a p5 port of Zach
//  Lieberman's openFrameworks sample for the RTP class at SFPC, Fall 2021
//  (https://github.com/ofZach/RTP_SFPC_F21). Reworked for Ollin's API.

import Ollin

/// 800 dots across the canvas, each offset vertically by `signedNoise` (Perlin
/// noise in `-1...1`) — a smooth, correlated wave, where each dot stays close to
/// its neighbors. `mouseX` slides the sample position, so the wave drifts as you
/// move. The jagged counterpart is `RandomBand`; together they show random vs.
/// noise. (The source faked signed noise with `map(noise(...), 0, 1, -1, 1)`;
/// here `signedNoise` gives the `-1...1` range directly.)
@main
final class NoiseWave: Sketch {
    override func setup() {
        noStroke()
    }

    override func draw() {
        background(.black)
        for i in 0..<800 {
            let y = 400 + signedNoise(Double(i) * 0.01 + mouseX * 0.1) * 100
            circle(x: Double(i), y: y, radius: 2)
        }
    }
}
