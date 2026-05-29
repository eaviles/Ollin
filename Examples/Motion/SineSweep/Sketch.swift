//  Ported from the p5.js sketch week-2/sin-1 (MIT) in
//  https://github.com/eaviles/rtp-sfpc-f21-p5 — itself a p5 port of Zach
//  Lieberman's openFrameworks sample for the RTP class at SFPC, Fall 2021
//  (https://github.com/ofZach/RTP_SFPC_F21). Reworked for Ollin's API.

import Foundation
import Ollin

/// A circle swept left↔right across the canvas. `map` remaps `sin(time)`
/// (which swings -1...1) onto 0...width, so the circle slides from edge to
/// edge — half-off each side at the extremes.
///
/// `width`/`height` are read live, so the sweep stays full-width on resize.
@main
final class SineSweep: Sketch {
    override func draw() {
        background(.black)
        let x = map(sin(time), -1, 1, 0, width)
        circle(x, height / 2, 30)
    }
}
