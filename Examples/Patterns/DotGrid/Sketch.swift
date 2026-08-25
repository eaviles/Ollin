//  Ported from the p5.js sketch week-4/pattern-1 (MIT) in
//  https://github.com/eaviles/rtp-sfpc-f21-p5 — itself a p5 port of Zach
//  Lieberman's openFrameworks sample for the RTP class at SFPC, Fall 2021
//  (https://github.com/ofZach/RTP_SFPC_F21). Reworked for Ollin's API.

import Ollin

/// A 21×21 grid of dots, each colored black or white by a small modulo rule.
/// Every row's pattern is shifted by an `offset` that rises and falls (0→4→0)
/// down the grid, so the black/white columns weave into diagonal bands.
///
/// Nothing here depends on `time`, so the image is static — the draw loop just
/// redraws the same pattern each frame.
@main
final class DotGrid: Sketch {
    override func setup() {
        noStroke()
    }

    override func draw() {
        background(.gray)
        // Canvas-relative layout: an eighth-of-canvas margin, the dots spanning
        // it edge to edge, so it fills any canvas size.
        let margin = shortSide * 0.125
        let g = grid(columns: 21, rows: 21, padding: .all(margin), distribution: .spanning)
        let radius = g.bounds.width / 20 / 2   // dots touch: half the gap between them
        for dot in g.points {
            var offset = dot.row % 8
            if offset > 4 { offset = 8 - offset }
            fill((dot.column + offset) % 4 < 2 ? .white : .black)
            drawCircle(center: dot.position, radius: radius)
        }
    }
}
