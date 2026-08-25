import Ollin

/// A drifting field of light rebuilt as a grid of glyphs.
///
/// `drawGlyphMosaic` samples an image cell by cell and places, in each cell,
/// the character whose measured ink matches the brightness underneath: bright
/// cores earn solid blocks, mid tones the checkered and crossed marks, faint
/// edges a lone dot, and true shadow stays empty. The ramp is not hand-ordered;
/// every glyph in the set is measured in the active font, so any string works
/// as a palette of marks. The bundled bitmap font covers the whole default
/// `GlyphSet.technical` set, and its chunky pixel forms are the classic look.
///
/// The source is painted small every frame (three orbiting blobs under a
/// slow-turning band of light), so the sketch carries no asset and the mosaic
/// re-reads it live: characters promote and demote as the light passes
/// through their cells.
@main
final class GlyphMosaic: Sketch {
    override var loopDuration: Double? { 10 }

    private let source = Image(width: 176, height: 176, color: .black)

    override func draw() {
        paint(phase: loopProgress(over: 10) * .tau)

        background(.black)
        textFont(BitmapFont.builtin)
        noStroke()
        fill(.white)
        // The default set ends in full-cell blocks and shades, which tile
        // into solid regions at the bright end. This set tops out at discrete
        // filled marks instead, so even the brightest cells stay separate
        // glyphs with black gutters, and any string works the same way.
        let marks = "·⠂∙•⠒1x∷+=⠶✕▪∴≡⁘┼⠿※╬◌═◇○▖▘▝▗⊘⊞◐⊗✚✜▚▞⣤▤◈⊠□▣⣶◆●◉▧▨▦░▒⊡◘▩◙⣿■"
        drawGlyphMosaic(source, columns: 64, characters: marks,
                        in: canvasRectangle.inset(by: 64))

        drawCaption("every mark chosen by its measured ink; empty cells are true shadow")
    }

    /// Three blobs on circular orbits, lit by a rotating soft band. Every
    /// motion completes a whole number of turns per loop, so the mosaic's
    /// perfect-loop export closes exactly.
    private func paint(phase: Double) {
        let n = source.width
        for y in 0 ..< n {
            for x in 0 ..< n {
                let u = (Double(x) + 0.5) / Double(n) * 2 - 1
                let v = (Double(y) + 0.5) / Double(n) * 2 - 1

                // Orbiting gaussian blobs, one per harmonic; kept compact so
                // the dense end of the ramp stays an accent, not a slab.
                var field = 0.0
                field += glow(u, v, 0.52 * cos(phase), 0.52 * sin(phase), 8.5)
                field += 0.85 * glow(u, v, 0.34 * cos(-2 * phase + 1.3),
                                     0.34 * sin(-2 * phase + 1.3), 13)
                field += 0.70 * glow(u, v, 0.66 * cos(3 * phase + 4.0),
                                     0.66 * sin(3 * phase + 4.0), 18)

                // A broad band of light sweeping through, one turn per loop.
                let band = unipolar(sin(2.6 * (u * cos(phase) + v * sin(phase)) - phase))
                // Soft-knee compression holds the cores just under white, and
                // a static grain nudges neighboring cells onto different
                // rungs of the ramp, so dense regions stay a mix of marks
                // instead of one repeated glyph.
                let grain = signedFbm(u * 7 + 20, v * 7 + 20, octaves: 3) * 0.07
                let tone = clamp((1 - exp(-1.25 * field * (0.35 + 0.65 * band))) * 0.8 + grain,
                                 0, 0.86)
                source[x, y] = Color(white: tone)
            }
        }
    }

    private func glow(_ u: Double, _ v: Double, _ cx: Double, _ cy: Double,
                      _ sharpness: Double) -> Double {
        let dx = u - cx, dy = v - cy
        return exp(-(dx * dx + dy * dy) * sharpness)
    }
}
