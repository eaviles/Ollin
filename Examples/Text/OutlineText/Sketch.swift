import Foundation
import Ollin

/// Outline (vector) text. An `OutlineFont` loads a real `.ttf`/`.otf` once and
/// draws crisp at *any* `textSize`, and because each glyph is a `Shape`, the type
/// is geometry you can take apart and move.
///
/// Three things are on screen, all from one font:
/// - a faint **stroked** ghost of the word (outline-only text — `noFill()` + a
///   `stroke`), showing the bare letterforms;
/// - the word again, filled and **rippling** — its glyph outlines are pulled out
///   with `textToShapes`, then every point is pushed along a flow field so the
///   letters breathe like liquid (text as first-class geometry);
/// - a crisp caption in plain filled outline text.
///
/// Uses the bold system font so it runs anywhere; swap in any installed face with
/// `OutlineFont(name: "Avenir Next")` or load one from a file.
@main
final class OutlineText: Sketch {
    let display = OutlineFont(name: "AvenirNext-Heavy") ?? .systemBold
    let palette = Palette.rainbow
    let word = "ollin"

    override func setup() {
        textFont(display)
        textAlign(.center, .middle)
    }

    override func draw() {
        background(Color(white: 0.06))

        textFont(display)
        textAlign(.center, .middle)
        textSize(320 * scale)
        let center = Vector2(width / 2, height * 0.44)

        // Ghost: the bare letterforms, outline-only (no fill, thin stroke).
        noFill()
        stroke(Color(white: 1, alpha: 0.16))
        strokeWeight(1.5 * scale)
        drawText(word, at: center)

        // Ripple: the same glyphs as geometry, every outline point displaced by a
        // slow curl-noise flow field and filled with a drifting palette color.
        noStroke()
        let shapes = textToShapes(word, at: center)
        for (index, shape) in shapes.enumerated() {
            let hue = Double(index) / Double(max(1, shapes.count - 1))
            fill(palette.color(at: 0.15 + hue * 0.7))
            // A bounded, smooth displacement field — signed noise per axis, so
            // every outline point moves a little (never a lot), which ripples the
            // letterforms without folding them into spikes. `mapPoints` keeps the
            // glyph's fill winding intact through the warp.
            let warped = shape.mapPoints { point in
                let n = point * 0.004
                let dx = signedNoise(n.x, n.y, time * 0.3)
                let dy = signedNoise(n.x + 40, n.y - 40, time * 0.3)
                return point + Vector2(dx, dy) * (14 * scale)
            }
            drawShape(warped)
        }

        // Caption: plain filled outline text, crisp at a small size from the very
        // same font.
        textAlign(.center, .top)
        textSize(40 * scale)
        noStroke()
        fill(Color(white: 0.82))
        drawText("VECTOR TYPE · ANY SIZE · IT'S GEOMETRY", width / 2, height * 0.78)
    }
}
