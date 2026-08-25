import Foundation
import Ollin

/// A wall of body text drawn through the SDF glyph atlas (`textMode(.atlas)`):
/// thousands of glyphs redrawn every frame, where each glyph costs a few vertex
/// writes — one quad sampling the atlas — instead of a flatten + triangulation.
/// A brightness wave rolls down the rows and the block drifts upward, so every
/// glyph moves each frame: the volume case the atlas path exists for. The same
/// sketch with `textMode(.outline)` re-tessellates every glyph per frame and
/// bogs down; toggle the FPS overlay to compare.
///
/// Self-contained — the system monospaced face, and the text is generated from a
/// small word pool, so there's no bundled asset.
@main
final class TextVolume: Sketch {
    let font = OutlineFont.systemMono
    let palette = CosinePalette.sunset

    /// A pool of short words the wall is woven from (no source text, no asset).
    let words = """
    light field signal noise pixel vector glyph atlas raster shader metal canvas
    motion phase drift bloom grain orbit pulse weave thread lattice ember tide
    quiet ink stone river ash north salt amber lull ridge cove fern moss dawn
    """.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)

    var lines: [String] = []
    var glyphCount = 0
    let bodySize = 22.0

    override func setup() {
        seed(7)
        textFont(font)
        textSize(bodySize * scale)

        // Wrap a stream of words to the canvas width, filling a couple of screens'
        // worth of rows so there's always a full wall on screen as it scrolls.
        let margin = 40.0 * scale
        let maxWidth = width - margin * 2
        let rows = Int(height / (bodySize * 1.35 * scale)) * 2
        var line = ""
        while lines.count < rows {
            let word = words[Int(random(Double(words.count)))]
            let candidate = line.isEmpty ? word : line + " " + word
            if textWidth(candidate) > maxWidth, !line.isEmpty {
                lines.append(line)
                line = word
            } else {
                line = candidate
            }
        }
        glyphCount = lines.reduce(0) { $0 + $1.count }
    }

    override func draw() {
        background(Color(white: 0.05))
        textFont(font)
        textMode(.atlas)              // the SDF-atlas scale path
        textSize(bodySize * scale)
        textAlign(.left, .top)

        let margin = 40.0 * scale
        let lineHeight = bodySize * 1.35 * scale
        // Drift the whole block upward, wrapping by one line height so it loops.
        let scroll = (time * lineHeight * 1.2).truncatingRemainder(dividingBy: lineHeight)

        for (i, line) in lines.enumerated() {
            let y = margin - lineHeight + Double(i) * lineHeight - scroll
            if y < -lineHeight || y > height { continue }
            // A brightness + color wave rolling down the rows.
            let wave = unipolar(sin(time * 2.2 - Double(i) * 0.22))
            fill(brighten(palette.color(at: 0.25 + 0.5 * wave), 0.15 + 0.5 * wave))
            drawText(line, margin, y)
        }
    }

    /// Blend `c` toward white by `t` (no `Color.mix` in the core yet).
    private func brighten(_ c: Color, _ t: Double) -> Color {
        Color(red: lerp(c.red, 1, t), green: lerp(c.green, 1, t), blue: lerp(c.blue, 1, t))
    }
}
