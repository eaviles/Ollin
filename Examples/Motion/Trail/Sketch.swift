//  Ported from the p5.js sketch week-2/sin-5 (MIT) in
//  https://github.com/eaviles/rtp-sfpc-f21-p5 — itself a p5 port of Zach
//  Lieberman's openFrameworks sample for the RTP class at SFPC, Fall 2021
//  (https://github.com/ofZach/RTP_SFPC_F21). Reworked for Ollin's API.

import Foundation
import Ollin

/// A point traces a Lissajous figure (`cos`/`sin` on slightly different
/// frequencies), and the last 600 positions are kept in a `trail` and drawn as
/// a single connected `polyline`. A filled dot marks the live head.
///
/// The trail is just a `[Vector2]` the sketch owns: append the new point each
/// frame, drop the oldest once it passes 600.
@main
final class Trail: Sketch {
    var trail: [Vector2] = []

    override func draw() {
        background(.black)

        // The figure's reach and the head dot scale with the canvas
        // (`scale` = min(width, height) / 1000), so it fills any square the same.
        let reach = 375 * scale
        let head = Vector2(width / 2 + reach * cos(time * 3),
                           height / 2 + reach * sin(time * 3.7))
        trail.append(head)
        if trail.count > 600 { trail.removeFirst() }

        noFill()
        stroke(.white)
        drawPolyline(trail)

        noStroke()
        fill(.white)
        drawCircle(head.x, head.y, 12 * scale)
    }
}
