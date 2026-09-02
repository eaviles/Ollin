// figure: frame=0 themed
//
// Guide diagram: where a changed parameter ends up. The inspector holds the value
// while the sketch runs, and the one button under the rows writes it into the
// @Param line that declared it, so the file says what you tuned.
import Ollin
import OllinDiagram

final class ParametersToSource: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    override func draw() {
        background(theme.paper)
        textFont(.system)

        let panel = Rectangle(x: 40, y: 66, width: 380, height: 250)
        let second = Rectangle(x: 460, y: 66, width: 380, height: 250)
        diagramFrame(panel, title: "what the file says", theme: theme)
        diagramFrame(second, title: "turn it, then save", theme: theme)

        // The thumb stands where the value does, so the parameter reads as changed
        // down rather than merely moved: 120 and 86.5 of a 0...200 range.
        thumb(in: panel, at: 120 / 200, value: "120.0")
        thumb(in: second, at: 86.5 / 200, value: "86.5")
        saveButton(in: panel, pressed: false)
        saveButton(in: second, pressed: true)

        code(value: "120.0", moved: false, at: Vector2(panel.x, 372))
        code(value: "86.5", moved: true, at: Vector2(second.x, 372))

        diagramCaption("the value you turned becomes the number in your file",
                       at: 424, theme: theme)
    }

    /// One inspector row: the label over a track with its thumb, and the value
    /// box beside it. The second panel's thumb stands where the parameter was left.
    private func thumb(in panel: Rectangle, at fraction: Double, value: String) {
        let card = Rectangle(x: panel.x + 26, y: panel.y + 34, width: panel.width - 52, height: 78)
        withState {
            fill(theme.card)
            noStroke()
            drawRect(card, cornerRadius: 9)
        }
        drawText("RADIUS", card.x + 16, card.y + 22,
                 size: 13, color: theme.muted, align: .left, .middle)

        let track = Rectangle(x: card.x + 16, y: card.y + 52, width: card.width - 104, height: 6)
        withState {
            noStroke()
            fill(theme.ink(0.16))
            drawRect(track, cornerRadius: 3)
            fill(theme.accent)
            drawRect(Rectangle(x: track.x, y: track.y, width: track.width * fraction,
                               height: track.height), cornerRadius: 3)
            drawCircle(center: Vector2(track.x + track.width * fraction, track.y + 3), radius: 9)
        }
        drawText(value, card.x + card.width - 16, card.y + 55,
                 size: 17, color: theme.ink, align: .right, .middle)
    }

    /// The one action under the knobs, waiting in the first panel and run in
    /// the second, where it says what it wrote.
    private func saveButton(in panel: Rectangle, pressed: Bool) {
        let button = Rectangle(x: panel.x + 26, y: panel.y + 132, width: panel.width - 52, height: 38)
        withState {
            fill(theme.card)
            stroke(pressed ? theme.accent : theme.border)
            strokeWeight(1.5)
            drawRect(button, cornerRadius: 8)
        }
        drawText("Save parameters to Sketch.swift", button.x + button.width / 2, button.y + 20,
                 size: 17, color: pressed ? theme.accent : theme.ink(0.6),
                 align: .center, .middle)
        if pressed {
            drawText("Saved 1 value into Sketch.swift.", button.x, button.y + button.height + 22,
                     size: 14, color: theme.muted, align: .left, .middle)
        }
    }

    /// The declaration under each panel, with the number that changes set in
    /// the accent once it has been written.
    private func code(value: String, moved: Bool, at origin: Vector2) {
        textFont(.systemMono)
        textSize(19)
        textAlign(.left, .top)
        let parts: [(String, Bool)] = [
            ("@Param(0...200) var radius = ", false),
            (value, moved),
        ]
        var x = origin.x
        for (text, highlighted) in parts {
            fill(highlighted ? theme.accent : theme.ink)
            drawText(text, x, origin.y)
            x += textWidth(text)
        }
        textFont(.system)
    }
}
