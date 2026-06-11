import Foundation
import Ollin

/// "Hello, text." A specimen for the bitmap-font `drawText`: a title that breathes
/// and shifts color, a centered multilingual caption, and the character set —
/// Latin, Spanish accents, and Japanese kana — marqueeing along the bottom. Every
/// glyph is stamped as pixel squares on the SDF path, so text rides the transform
/// stack and stays crisp at any size. The bundled font is Cozette (MIT).
@main
final class HelloText: Sketch {
    let palette = CosinePalette.sunset
    let specimen = "ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz 0123456789  áéíóú ñ ü ¿¡  ハローワールド こんにちは  .,!?:;-+=/()[]<>#@%&   "

    override func draw() {
        background(Color(white: 0.07))

        // Title: centered, breathing, color drifting through the palette's bright
        // warm band (kept out of its dark midtones so it stays legible on black).
        let pulse = 1 + 0.06 * sin(time * 2)
        fill(palette.color(at: 0.12 + 0.12 * sin(time * 0.6)))
        textAlign(.center, .middle)
        textSize(150 * pulse * scale)
        drawText("ollin", width / 2, height * 0.38)

        // Caption: a centered, multilingual block under the title.
        fill(Color(white: 0.7))
        textAlign(.center, .top)
        textSize(34 * scale)
        drawText("BITMAP TEXT\n¡hola!  こんにちは", width / 2, height * 0.56)

        // Specimen marquee: the character set — including the Japanese "Hello
        // World" (ハローワールド) — scrolling right-to-left, wrapped with textWidth.
        textAlign(.left, .baseline)
        textSize(30 * scale)
        fill(palette.color(at: 0.75))
        let stripWidth = textWidth(specimen)
        let scrolled = (time * 110 * scale).truncatingRemainder(dividingBy: stripWidth)
        let start = width - scrolled
        let y = height * 0.9
        drawText(specimen, start, y)
        drawText(specimen, start - stripWidth, y)   // trailing copy hides the seam
    }
}
