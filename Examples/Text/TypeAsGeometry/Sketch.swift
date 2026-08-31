//  The jitter row is ported from the p5.js sketch week-3/type-6 (MIT) in
//  https://github.com/eaviles/rtp-sfpc-f21-p5, itself a p5 port of Zach
//  Lieberman's openFrameworks sample for the RTP class at SFPC, Fall 2021
//  (https://github.com/ofZach/RTP_SFPC_F21). Reworked for Ollin's API.

import Foundation
import Ollin

/// Type as geometry. An `OutlineFont` loads a real `.ttf`/`.otf` once and draws
/// crisp at *any* `textSize`, and because each glyph is a `Shape`, the letters
/// can be taken apart and reworked. Two rows share the same core, `textToShapes`
/// pulling the glyph outlines out and `Shape.mapPoints` warping them:
///
/// - **Ripple**: a faint **stroked** ghost of the word (outline-only text, a
///   `stroke` with `noFill()`) showing the bare letterforms, under the word
///   again, filled, every outline point pushed along a flow field so the
///   letters breathe like liquid.
/// - **Jitter**: letters that won't hold still. Each glyph's outline is
///   resampled to evenly spaced points, then every point is nudged by a random
///   offset before the glyph is filled, so the type boils and wobbles like a
///   bad photocopy. The offsets re-roll every frame and their amount pulses;
///   `randomSeed(frameCount)` pins each frame's jitter to the frame number, so
///   the boil is frame-stable: any given frame always draws the same shimmer,
///   and a replay or an export repeats what the live run showed.
///
/// A crisp caption below comes from the very same font. Uses the bold system
/// font as the fallback so it runs anywhere; swap in any installed face with
/// `OutlineFont(name: "Avenir Next")` or load one from a file.
@main
final class TypeAsGeometry: Sketch {
    let display = OutlineFont(name: "AvenirNext-Heavy") ?? .systemBold
    let palette = CosinePalette.rainbow
    let rippleWord = "ollin"
    let jitterWord = "hello"
    var jitterGlyphs: [Shape] = []

    override func setup() {
        textFont(display)
        textAlign(.center, .middle)
        textSize(240 * scale)
        // One resampled shape per glyph for the jitter row, sampled once here
        // (the word and size don't change). Glyph fills need the non-zero
        // winding rule (even-odd cuts the bowls of a/e/o/g/s), and the even
        // resampling is what makes the outline wobble smoothly instead of
        // shattering: the raw outline puts whole straight edges between two
        // points. The spacing is wider than the jitter below, so neighbors
        // rarely cross and the outline rounds over instead of splintering.
        jitterGlyphs = textToShapes(jitterWord, width / 2, height * 0.62).map { shape in
            let dense = shape.contours.map { $0.resampled(spacing: 10 * scale) }
            return Shape(contours: dense, winding: .nonZero)
        }
    }

    override func draw() {
        background(Color(white: 0.06))

        textFont(display)
        textAlign(.center, .middle)
        textSize(240 * scale)
        let rippleCenter = Vector2(width / 2, height * 0.30)

        // Ghost: the bare letterforms, outline-only (no fill, thin stroke).
        noFill()
        stroke(Color(white: 1, alpha: 0.16))
        strokeWeight(1.5 * scale)
        drawText(rippleWord, at: rippleCenter)

        // Ripple: the same glyphs as geometry, every outline point displaced by
        // a slow noise flow field and filled with a drifting palette color.
        noStroke()
        let shapes = textToShapes(rippleWord, at: rippleCenter)
        for (index, shape) in shapes.enumerated() {
            let hue = Double(index) / Double(max(1, shapes.count - 1))
            fill(palette.color(at: 0.15 + hue * 0.7))
            // A bounded, smooth displacement field: signed noise per axis, so
            // every outline point moves a little (never a lot), which ripples
            // the letterforms without folding them into spikes. `mapPoints`
            // keeps the glyph's fill winding intact through the warp.
            let warped = shape.mapPoints { point in
                let n = point * 0.004
                let dx = signedNoise(n.x, n.y, time * 0.3)
                let dy = signedNoise(n.x + 40, n.y - 40, time * 0.3)
                return point + Vector2(dx, dy) * (12 * scale)
            }
            drawShape(warped)
        }

        // Jitter: the resampled glyphs, every point nudged by a fresh random
        // offset. The amount pulses (kept well under the point spacing, and
        // under the counters' wall thickness, so the bowls of e/o don't fill in
        // and turn the letters into diamonds); seeding from the frame number
        // re-rolls the boil each frame while keeping any one frame repeatable.
        fill(.white)
        let amount = unipolar(sin(time * 0.8)) * 6 * scale
        randomSeed(frameCount)
        for glyph in jitterGlyphs {
            drawShape(glyph.mapPoints { p in
                p + Vector2(random(-amount, amount), random(-amount, amount))
            })
        }

        // Caption: plain filled outline text, crisp at a small size from the
        // very same font.
        textAlign(.center, .top)
        textSize(40 * scale)
        fill(Color(white: 0.82))
        drawText("VECTOR TYPE · ANY SIZE · IT'S GEOMETRY", width / 2, height * 0.85)
    }
}
