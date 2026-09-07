// figure: frame=0 themed
//
// Guide diagram: a look asked for in words. The field above the Save button
// takes a phrase, the parameters it concerns move inside their ranges, and the
// line under the field names each move with Undo beside it.
import Ollin
import OllinDiagram

final class LookToParameters: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    override func draw() {
        background(theme.paper)
        textFont(.system)

        let before = Rectangle(x: 40, y: 66, width: 380, height: 330)
        let after = Rectangle(x: 460, y: 66, width: 380, height: 330)
        diagramFrame(before, title: "type a look", theme: theme)
        diagramFrame(after, title: "press return", theme: theme)

        field(in: before, sent: false)
        field(in: after, sent: true)

        // Radius 120 of 0...200, then 180; the tint purple, then orange.
        slider(in: before, at: 120 / 200, value: "120.0", moved: false)
        slider(in: after, at: 180 / 200, value: "180.0", moved: true)
        swatch(in: before, color: Color(red: 0.5, green: 0, blue: 1), value: "#8000FF", moved: false)
        swatch(in: after, color: Color(red: 1, green: 0.27, blue: 0), value: "#FF4500", moved: true)

        report(in: after)

        diagramCaption("the parameters the words concern move, and the line says which",
                       at: 436, theme: theme)
    }

    /// The field above the rows, with the phrase typed and the arrow beside it.
    private func field(in panel: Rectangle, sent: Bool) {
        let box = Rectangle(x: panel.x + 26, y: panel.y + 34, width: panel.width - 92, height: 40)
        withState {
            fill(theme.card)
            stroke(sent ? theme.accent : theme.border)
            strokeWeight(1.5)
            drawRect(box, cornerRadius: 8)
        }
        drawText("bigger and warmer", box.x + 14, box.y + 21,
                 size: 17, color: theme.ink, align: .left, .middle)
        let arrow = Vector2(box.x + box.width + 22, box.y + 20)
        withState {
            noStroke()
            fill(sent ? theme.accent : theme.ink(0.35))
            drawCircle(center: arrow, radius: 13)
            fill(theme.paper)
            drawTriangle(arrow.x - 5, arrow.y + 3, arrow.x + 5, arrow.y + 3, arrow.x, arrow.y - 6)
        }
    }

    /// One slider row: the label, the track with its thumb, and the value box.
    private func slider(in panel: Rectangle, at fraction: Double, value: String, moved: Bool) {
        let card = Rectangle(x: panel.x + 26, y: panel.y + 96, width: panel.width - 52, height: 78)
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
                 size: 17, color: moved ? theme.accent : theme.ink, align: .right, .middle)
    }

    /// One color row: the label, the swatch, and the hex beside it.
    private func swatch(in panel: Rectangle, color: Color, value: String, moved: Bool) {
        let card = Rectangle(x: panel.x + 26, y: panel.y + 186, width: panel.width - 52, height: 56)
        withState {
            fill(theme.card)
            noStroke()
            drawRect(card, cornerRadius: 9)
        }
        drawText("TINT", card.x + 16, card.y + 28,
                 size: 13, color: theme.muted, align: .left, .middle)
        withState {
            fill(color)
            stroke(theme.ink(0.2))
            strokeWeight(1)
            drawRect(Rectangle(x: card.x + card.width - 132, y: card.y + 14, width: 28, height: 28), cornerRadius: 6)
        }
        drawText(value, card.x + card.width - 16, card.y + 29,
                 size: 17, color: moved ? theme.accent : theme.ink, align: .right, .middle)
    }

    /// The line under the rows once the ask is answered, with Undo beside it.
    private func report(in panel: Rectangle) {
        let y = panel.y + 268
        drawText("Moved Radius from 120 to 180", panel.x + 26, y,
                 size: 14, color: theme.muted, align: .left, .middle)
        drawText("and Tint from #8000FF to #FF4500.", panel.x + 26, y + 22,
                 size: 14, color: theme.muted, align: .left, .middle)
        drawText("Undo", panel.x + panel.width - 26, y + 22,
                 size: 14, color: theme.accent, align: .right, .middle)
    }
}
