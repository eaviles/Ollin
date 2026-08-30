import Foundation
import Ollin

/// Per-glyph `drawText`. The closure form hands you every letter — its character,
/// index, position, and bounds — so you can give each one its own transform and
/// color before stamping it with `g.draw()`. Here each glyph rides a traveling
/// sine wave, tilts into the motion, and takes its own hue: a per-letter effect
/// that otherwise means measuring and placing each glyph by hand. Uses the bold
/// system font.
@main
final class GlyphWave: Sketch {
    let font = OutlineFont(name: "AvenirNext-Bold") ?? .systemBold
    let palette = CosinePalette.rainbow
    let word = "ollin"

    override func setup() {
        textFont(font)
        textAlign(.center, .middle)
    }

    override func draw() {
        background(Color(white: 0.06))
        textFont(font)
        textAlign(.center, .middle)
        textSize(240 * scale)
        noStroke()

        drawText(word, at: Vector2(width / 2, height * 0.46)) { g in
            let phase = time * 3 - Double(g.index) * 0.7
            fill(palette.color(at: g.progress * 0.85 + time * 0.05))
            withState {
                translate(0, sin(phase) * 60 * scale)   // bob along the wave
                translate(g.center)                       // tilt about the glyph's
                rotate(cos(phase) * 0.28)                 // own center, into the motion
                translate(g.center * -1)
                g.draw()
            }
        }

        textAlign(.center, .top)
        textSize(34 * scale)
        fill(Color(white: 0.8))
        drawText("PER-GLYPH DRAWTEXT", width / 2, height * 0.74)
    }
}
