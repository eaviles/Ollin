//  Ported from the p5.js sketch week-4/pattern-3 (MIT) in
//  https://github.com/eaviles/rtp-sfpc-f21-p5 — itself a p5 port of Zach
//  Lieberman's openFrameworks sample for the RTP class at SFPC, Fall 2021
//  (https://github.com/ofZach/RTP_SFPC_F21). Reworked for Ollin's API.

import Ollin

/// A 30×30 grid of dots that flee the cursor: each dot is pushed away from
/// `mouseX`/`mouseY` and swells as the pointer nears it.
///
/// `dist` gives each dot's distance to the cursor; `map(..., clamp: true)`
/// turns that into a 0...1 closeness `pct` (1 right under the cursor, 0 once
/// it's 200 points away). `pct` then drives both the push (along the unit
/// vector away from the cursor) and the radius.
@main
final class RepelGrid: Sketch {
    override func setup() {
        noStroke()
    }

    override func draw() {
        background(.black)
        // Canvas-relative so the grid fills any canvas size and the cursor lines
        // up with it: a 1/16 inset, a quarter-canvas cursor reach, and a push and
        // dot radius scaled to that inset.
        let s = shortSide
        let margin = s * 0.0625
        let reach = s * 0.25
        let push = s * 0.0625
        let g = grid(columns: 30, rows: 30, padding: .all(margin), distribution: .spanning)
        for dot in g.points {
            let x = dot.position.x, y = dot.position.y

            let distance = dist(x, y, mouseX, mouseY)
            let pct = map(distance, 0, reach, 1, 0, clamp: true)

            var dx = x - mouseX
            var dy = y - mouseY
            if distance > 0 {            // normalize to a unit push direction
                dx /= distance
                dy /= distance
            }

            drawCircle(x + dx * pct * push,
                       y + dy * pct * push,
                       margin * (0.1 + 0.16 * pct))
        }
    }
}
