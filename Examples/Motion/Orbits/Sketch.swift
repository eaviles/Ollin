//  Ported from the p5.js sketch week-2/sin-4 (MIT) in
//  https://github.com/eaviles/rtp-sfpc-f21-p5 — itself a p5 port of Zach
//  Lieberman's openFrameworks sample for the RTP class at SFPC, Fall 2021
//  (https://github.com/ofZach/RTP_SFPC_F21). Reworked for Ollin's API.

import Foundation
import Ollin

/// Ten circles orbiting the center, each on a wider ring and at a faster
/// angular speed, traced with `cos`/`sin`. `map` turns the ring index into a
/// speed multiplier — 1 at the innermost ring rising toward ~8 at the
/// outermost — so the rings drift in and out of alignment over time.
///
/// The center reads live as `width / 2, height / 2`.
@main
final class Orbits: Sketch {
    override func setup() {
        noStroke()
        fill(.white)
    }

    override func draw() {
        background(.black)
        for i in 0..<10 {
            let fi = Double(i)
            let orbitRadius = 100 + fi * 20
            let angle = time * map(fi, 0, 10, 1, 10)
            let x = width / 2 + orbitRadius * cos(angle)
            let y = height / 2 + orbitRadius * sin(angle)
            drawCircle(x, y, 20)
        }
    }
}
