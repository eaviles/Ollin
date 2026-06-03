import Foundation
import Ollin

// Font: "Marble Madness" from playdate-arcade-fonts by idleberg
//   https://github.com/idleberg/playdate-arcade-fonts — fonts CC0 (public domain),
//   original homages to classic arcade typography. Copied beside this sketch (the
//   way you'd bundle your own font) and loaded at runtime by the Playdate `.fnt`
//   loader. Ollin bundles no arcade fonts itself — only the loader.

/// Loading a **Playdate `.fnt`** font and drawing with it. The `.fnt` sits in this
/// example's own folder; `setup()` loads it from the bundle, and from there it's
/// just another `textFont`. An arcade attract-screen as the specimen: a title, a
/// score that ticks, a blinking prompt, and the character set scrolling under it.
@main
final class PlaydateFont: Sketch {
    var arcade = BitmapFont.builtin   // replaced in setup() with the loaded .fnt
    let charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz 0123456789   "

    override func setup() {
        // The single self-contained file (its glyph strike is embedded), loaded the
        // way a user would load a font dropped beside their sketch.
        if let url = Bundle.module.url(forResource: "MarbleMadness", withExtension: "fnt"),
           let font = BitmapFont(fntContentsOf: url) {
            arcade = font
        }
    }

    override func draw() {
        background(Color(white: 0.05))
        textFont(arcade)

        // Title.
        let titleSize = 110 * scale
        textAlign(.center, .middle)
        textSize(titleSize)
        fill(Color(red: 0.95, green: 0.85, blue: 0.2))
        drawText("MARBLE", width / 2, height * 0.30)
        fill(Color(red: 0.95, green: 0.45, blue: 0.15))
        drawText("MADNESS", width / 2, height * 0.30 + titleSize)

        // Score: counts up like an arcade attract loop (the digits, animating).
        let score = Int(time * 1730) % 1_000_000
        let padded = String(format: "%06d", score)
        fill(.white)
        textAlign(.center, .top)
        textSize(64 * scale)
        drawText("1UP   \(padded)", width / 2, height * 0.55)

        // Blinking prompt.
        if sin(time * 5) > 0 {
            fill(Color(white: 0.75))
            textSize(40 * scale)
            drawText("PRESS START", width / 2, height * 0.68)
        }

        // Character-set marquee, scrolling right-to-left and wrapped with textWidth.
        textAlign(.left, .baseline)
        textSize(34 * scale)
        fill(Color(red: 0.4, green: 0.8, blue: 0.95))
        let stripWidth = textWidth(charset)
        let scrolled = (time * 120 * scale).truncatingRemainder(dividingBy: stripWidth)
        let start = width - scrolled
        let y = height * 0.9
        drawText(charset, start, y)
        drawText(charset, start - stripWidth, y)   // trailing copy hides the seam
    }
}
