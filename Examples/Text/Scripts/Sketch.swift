import Foundation
import Ollin

/// Text in the scripts that are not Latin.
///
/// One glyph per letter is the English case and almost nowhere else. Arabic runs
/// right to left and joins its letters into shapes no single character has;
/// Devanagari draws part of a syllable *before* the letter it follows; Thai and
/// Japanese write without spaces, so a box has to know where a line may break;
/// and an emoji is not an outline at all but a picture the font carries.
///
/// Everything here is one `drawText` call per line. What the sketch chooses is
/// the base direction of the mixed line, which is the one thing the text cannot
/// say for itself.
@main
final class Scripts: Sketch {
    override var canvasSize: CanvasSize { .size(1080, 1080) }
    override var loopDuration: Double? { 6 }

    @Param("Base direction", icon: "text.alignleft")
    var direction: TextDirection = .automatic

    @Param("Wave", 0...1, icon: "waveform")
    var wave = 0.55

    let ink = Color(hex: 0x141210)
    let paper = Color(hex: 0xF6F2E9)
    let accent = Color(hex: 0xB4472A)

    /// A line, and the language it is in.
    let lines: [(String, String)] = [
        ("hi 👋 Ollin",        "Latin, with a picture"),
        ("مرحبا بالعالم",      "Arabic, right to left"),
        ("ที่นี่มีคนอยู่",         "Thai, marks stacked"),
        ("क्षि नमस्ते",          "Devanagari, reordered"),
        ("日本語のテキスト",     "Japanese"),
    ]

    override func setup() {
        textFont(.system)
        noStroke()
    }

    override func draw() {
        background(paper)
        textDirection(direction)

        fill(ink)
        textAlign(.left, .baseline)
        var y = 110.0
        for (line, label) in lines {
            textSize(48)
            drawText(line, 80, y)
            textSize(18)
            fill(accent)
            drawText(label.uppercased(), 80, y + 30)
            fill(ink)
            y += 98
        }

        drawMixedLine(at: 620)
        drawWavingWord(at: 740)
        drawWrappedParagraph(in: Rectangle(x: 80, y: 810, width: 440, height: 180))
        drawFacesUsed(at: Vector2(590, 812))
    }

    /// The line whose reading depends on the base direction. It opens with a
    /// bracket, which has no direction of its own, so the bracket lands at
    /// whichever end the direction says.
    private func drawMixedLine(at y: Double) {
        textSize(44)
        fill(ink)
        drawText("(1) مرحبا Ollin", 80, y)
        textSize(18)
        fill(accent)
        drawText("THE BRACKET FOLLOWS THE BASE DIRECTION", 80, y + 28)
    }

    /// A per-letter effect over a script that reorders and joins. Each piece the
    /// closure hands back is one thing a reader would point at, so an Arabic
    /// letter carrying a vowel mark moves as one and a syllable is never cut in
    /// half.
    private func drawWavingWord(at y: Double) {
        textSize(58)
        textAlign(.left, .baseline)
        let phase = loopProgress(over: loopDuration ?? 6) * .tau
        drawText("مرحبا بالعالم", 80, y) { g in
            fill(g.index.isMultiple(of: 2) ? ink : accent)
            withState {
                translate(0, sin(phase - Double(g.index) * 0.55) * 22 * wave)
                g.draw()
            }
        }
    }

    /// A paragraph with no spaces in it. Where a line may break comes from the
    /// script's own rules, so Japanese breaks between characters and the block
    /// fits the box.
    private func drawWrappedParagraph(in box: Rectangle) {
        fill(ink)
        textSize(27)
        textAlign(.left, .top)
        drawText(String(repeating: "日本語のテキストです。", count: 4), in: box)
        textSize(18)
        fill(accent)
        drawText("WRAPPED WITH NO SPACES TO BREAK AT", box.x, box.y + 132)
    }

    /// Which faces the machine actually lent one mixed line. Nothing was installed
    /// for this: asking a Latin font for Japanese quietly borrows a face that has
    /// the letters, and this is how to see it happen.
    private func drawFacesUsed(at position: Vector2) {
        let sample = "Ollin 日本語 👋"
        fill(accent)
        textSize(18)
        textAlign(.left, .top)
        drawText("FACES BORROWED FOR \(sample)", position.x, position.y)
        fill(ink)
        textSize(23)
        var y = position.y + 30
        for name in OutlineFont.system.fontsUsed(for: sample) {
            drawText(name, position.x, y)
            y += 30
        }
    }
}
