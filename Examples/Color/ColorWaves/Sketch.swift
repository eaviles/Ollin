//  Ported from the p5.js sketch week-2/sin-3 (MIT) in
//  https://github.com/eaviles/rtp-sfpc-f21-p5 — itself a p5 port of Zach
//  Lieberman's openFrameworks sample for the RTP class at SFPC, Fall 2021
//  (https://github.com/ofZach/RTP_SFPC_F21). Reworked for Ollin's API.

import Foundation
import Ollin

/// One circle per row, with color, horizontal position, and size all driven by
/// `sin` — of the row index (a static vertical color gradient) and of
/// `time + index` (the flowing left↔right motion and pulsing size).
///
/// Each color channel is `unipolar(sin(...))`, riding a `sin` wave across the
/// full 0...1 range. `setup()` sets `noStroke()` once; the loop count and
/// offsets read live `width`/`height`, so it stays full-bleed on resize.
@main
final class ColorWaves: Sketch {
    override func setup() {
        noStroke()
    }

    override func draw() {
        background(.black)
        for row in 0..<Int(height) {
            let i = Double(row)
            fill(Color(red:   unipolar(sin(i * 0.010)),
                       green: unipolar(sin(i * 0.011)),
                       blue:  unipolar(sin(i * 0.012))))
            let x = width / 2 + width / 4 * sin(time + i * 0.02)
            let diameter = 62.5 * (1 + sin(time + i * 0.01)) * scale
            drawCircle(x, i, diameter / 2)
        }
    }
}
