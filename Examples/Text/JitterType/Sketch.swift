//  Ported from the p5.js sketch week-3/type-6 (MIT) in
//  https://github.com/eaviles/rtp-sfpc-f21-p5 — itself a p5 port of Zach
//  Lieberman's openFrameworks sample for the RTP class at SFPC, Fall 2021
//  (https://github.com/ofZach/RTP_SFPC_F21). Reworked for Ollin's API.

import Foundation
import Ollin

/// Letters that won't hold still. Each glyph is pulled out as a `Shape` with
/// `textToShapes` and its outline resampled to evenly spaced points; then every
/// point is nudged by a random offset before the glyph is filled — so the type
/// boils and wobbles like a bad photocopy. (`mapPoints` keeps each glyph's fill
/// winding through the warp; the even resampling is what makes it wobble smoothly
/// instead of shattering — Core Text's raw outline puts whole straight edges
/// between two points.) The jitter is re-rolled every frame and its amount pulses,
/// building from crisp letters up to a roiling shimmer and back. Uses the bold
/// system font.
@main
final class JitterType: Sketch {
    let font = OutlineFont.systemBold
    var glyphs: [Shape] = []

    override func setup() {
        textFont(font)
        textAlign(.center, .middle)
        textSize(280 * scale)
        // One resampled shape per glyph, centered on the canvas. Glyph fills need
        // the non-zero winding rule (even-odd cuts the bowls of a/e/o/g/s). The
        // spacing is wider than the jitter below, so neighbors rarely cross — the
        // outline wobbles and rounds over instead of shattering into shards.
        glyphs = textToShapes("hello", width / 2, height / 2).map { shape in
            let dense = shape.contours.map { $0.resampled(spacing: 12 * scale) }
            return Shape(contours: dense, winding: .nonZero)
        }
    }

    override func draw() {
        background(Color(white: 0.24))
        noStroke()
        fill(.white)

        // The jitter amount pulses (kept well under the point spacing — and under
        // the counters' wall thickness — so the bowls of e/o don't fill in and turn
        // the letters into diamonds); reseed each frame for a continuous boil.
        let amount = unipolar(sin(time * 0.8)) * 7 * scale
        randomSeed(frameCount)
        for glyph in glyphs {
            drawShape(glyph.mapPoints { p in
                p + Vector2(random(-amount, amount), random(-amount, amount))
            })
        }
    }
}
