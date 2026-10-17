import Ollin

/// Type and the words land on the canvas, the way a text field takes them.
///
/// The keyboard is read twice. `key` is the key itself: Option-E then E is two
/// presses of `e`. `typedText()` is what those presses typed once the system's
/// input methods composed them: one "é". The emoji viewer (Control-Command-Space)
/// types its pick the same way, and Chinese or Japanese typed through an input
/// method arrives once a candidate is chosen. Until then `composingText` holds
/// the reading, drawn here underlined at the end of the line, the way a text
/// field shows it.
///
/// `textTyped()` takes the text as it arrives, and `append(typing:)` keeps the
/// caption the way a text field would: Delete takes the last character away and
/// Return starts a new line. `caretPosition` tells the input method where the
/// line is, so its list of candidates opens under the caret rather than in a
/// corner. The panel at the bottom shows the last key beside the last text it
/// typed.
@main
final class TypedText: Sketch {
    /// What has been typed, newlines included.
    var caption = "Hola, \u{BF}qu\u{E9} tal?\n\u{65E5}\u{672C}\u{8A9E}\u{3082} \u{2728}"
    /// The last key pressed, and the last text the keyboard typed.
    var lastKey = "e"
    var lastTyped = "\u{E9}"

    let paper = Color(hex: 0xF6F2E9)
    let ink = Color(hex: 0x141210)
    let accent = Color(hex: 0xB4472A)
    let muted = Color(hex: 0x8A8378)

    override func setup() {
        textFont(.system)
        noStroke()
    }

    override func textTyped() {
        let typed = typedText()
        caption.append(typing: typed)
        lastTyped = typed
    }

    override func keyPressed() {
        if let key { lastKey = String(key) } else if let keyCode { lastKey = "\(keyCode)" }
    }

    override func draw() {
        background(paper)
        let size = 72.0
        let left = 80.0
        let leading = size * 1.3
        textSize(size)
        textAlign(.left, .baseline)

        let lines = caption.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var baseline = 200.0
        fill(ink)
        for line in lines.dropLast() {
            drawText(line, left, baseline)
            baseline += leading
        }
        let last = lines.last ?? ""
        drawText(last, left, baseline)

        // The reading an input method is still composing, underlined after
        // the confirmed text.
        var caretX = left + textWidth(last)
        if !composingText.isEmpty {
            fill(accent)
            drawText(composingText, caretX, baseline)
            let width = textWidth(composingText)
            drawRect(caretX, baseline + 10, width, 3)
            caretX += width
        }

        // A caret that blinks once a second, and the place the candidates open.
        if (time.truncatingRemainder(dividingBy: 1)) < 0.6 {
            fill(accent)
            drawRect(caretX + 4, baseline - size * 0.78, 4, size * 0.95)
        }
        caretPosition = Vector2(caretX, baseline + 18)

        drawPanel()
    }

    /// The two readings of the keyboard, side by side.
    private func drawPanel() {
        let top = 900.0
        fill(muted)
        textSize(18)
        drawText("LAST KEY", 80, top)
        drawText("LAST TYPED", 380, top)
        drawText("DELETE TAKES ONE AWAY  \u{B7}  RETURN STARTS A LINE", 80, 1010)
        fill(ink)
        textSize(54)
        drawText(lastKey, 80, top + 64)
        drawText(visible(lastTyped), 380, top + 64)
    }

    /// What a typed piece reads as on the panel: the characters that draw
    /// nothing are named.
    private func visible(_ typed: String) -> String {
        switch typed {
        case "\n": return "return"
        case "\t": return "tab"
        case "\u{8}": return "delete"
        default: return typed
        }
    }
}
