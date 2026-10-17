// figure: frame=0 themed
//
// Guide diagram (Chapter 38): the keyboard read two ways. Each row is a press,
// or a run of presses, in order: the keys pressed, what `composingText` holds
// after them, and what `typedText()` returns. Option-E holds an accent and E finishes it as
// one "é"; five letters typed through a Japanese input method show as a
// reading, Space turns the reading into kanji, and Return confirms it. The
// rows are the figure's own, so it draws the same on any machine.
import Foundation
import Ollin
import OllinDiagram

final class TwoReadings: Sketch {
    override var canvasSize: CanvasSize { .size(880, 560) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.4) }
    var soft: Color { theme.ink(0.62) }
    var accent: Color { theme.accent }

    /// One press: the keys drawn as caps, what is being composed after it, and
    /// what it typed.
    struct Press {
        let keys: [String]
        let composing: String
        let typed: String
    }

    let presses = [
        Press(keys: ["\u{2325}", "E"], composing: "\u{B4}", typed: ""),
        Press(keys: ["E"], composing: "", typed: "\u{E9}"),
        Press(keys: ["N", "I", "H", "O", "N"], composing: "\u{306B}\u{307B}\u{3093}", typed: ""),
        Press(keys: ["space"], composing: "\u{65E5}\u{672C}", typed: ""),
        Press(keys: ["return"], composing: "", typed: "\u{65E5}\u{672C}"),
    ]

    let keysX = 50.0
    let composingX = 420.0
    let typedX = 650.0
    let top = 168.0
    let rowHeight = 72.0

    override func draw() {
        background(paper)

        textFont(.systemMedium)
        fill(ink)
        textSize(21)
        textAlign(.left)
        drawText("the same presses, read as text", 50, 52)

        fill(soft)
        textSize(14)
        drawText("key reports each key; typedText() reports what the keys typed", 50, 76)

        header()
        for (index, press) in presses.enumerated() {
            row(press, at: top + Double(index) * rowHeight, isLast: index == presses.count - 1)
        }
    }

    private func header() {
        noStroke()
        fill(soft)
        textSize(13)
        textAlign(.left)
        drawText("pressed", keysX, top - 32)
        drawText("composingText", composingX, top - 32)
        drawText("typedText()", typedX, top - 32)
        stroke(faint)
        strokeWeight(1)
        drawLine(Vector2(keysX, top - 20), Vector2(830, top - 20))
    }

    private func row(_ press: Press, at y: Double, isLast: Bool) {
        // The keys, as caps.
        var x = keysX
        for key in press.keys {
            let width = key.count > 1 ? 74.0 : 40.0
            noFill()
            stroke(soft)
            strokeWeight(1.5)
            drawRect(x, y - 4, width, 40, cornerRadius: 7)
            noStroke()
            fill(ink)
            textSize(key.count > 1 ? 14 : 17)
            textAlign(.center)
            drawText(key, x + width / 2, y + 22)
            x += width + 8
        }

        // What is being composed, underlined the way a text field shows it.
        textAlign(.left)
        if press.composing.isEmpty {
            fill(faint)
            textSize(15)
            drawText("empty", composingX, y + 22)
        } else {
            fill(accent)
            textSize(26)
            drawText(press.composing, composingX, y + 24)
            let width = textWidth(press.composing)
            drawRect(composingX, y + 31, width, 2.5)
        }

        // What the press typed.
        if press.typed.isEmpty {
            fill(faint)
            textSize(15)
            drawText("nothing", typedX, y + 22)
        } else {
            fill(ink)
            textSize(26)
            drawText("\u{201C}" + press.typed + "\u{201D}", typedX, y + 24)
        }

        if !isLast {
            stroke(faint.withAlpha(0.5))
            strokeWeight(1)
            drawLine(Vector2(keysX, y + rowHeight - 14), Vector2(830, y + rowHeight - 14))
        }
    }
}
