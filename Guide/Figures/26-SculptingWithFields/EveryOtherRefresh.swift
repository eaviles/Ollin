// figure: frame=0 themed
//
// Guide diagram (Chapter 26): frame interpolation, refresh by refresh. Twelve
// refreshes of a 60 Hz display run left to right. The top row is what draw()
// made: a frame on every other refresh. The bottom row is what the display
// showed: each drawn frame one refresh after it was drawn, and between two
// drawn frames the made one, built from both. The first drawn frame repeats,
// since there is nothing yet to build from. A still cannot show a made frame,
// since an export never interpolates; the timing is what a picture can carry.
import Ollin
import OllinDiagram

final class EveryOtherRefresh: Sketch {
    override var canvasSize: CanvasSize { .size(880, 440) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    let refreshes = 12
    let box = 36.0

    override func draw() {
        background(theme.paper)
        textFont(.system)

        let left = 236.0, right = width - 44
        let step = (right - left) / Double(refreshes - 1)
        let drawnY = 92.0, shownY = 222.0, axisY = 318.0
        let names = ["A", "B", "C", "D", "E", "F"]

        func x(_ refresh: Int) -> Double { left + Double(refresh) * step }

        // The connectors first, so the boxes sit on them. A drawn frame is
        // shown on the refresh after its own, and the made frame shown on a
        // drawing refresh is built from that frame and the one drawn before it.
        // The very first frame is shown at once, then repeated.
        strokeWeight(1)
        stroke(theme.ink(0.3))
        drawLine(x(0), drawnY + box / 2, x(0), shownY - box / 2)
        drawLine(x(0), drawnY + box / 2, x(1), shownY - box / 2)
        for k in stride(from: 2, to: refreshes, by: 2) {
            stroke(theme.ink(0.3))
            drawLine(x(k), drawnY + box / 2, x(k + 1), shownY - box / 2)
            stroke(theme.accent(0.55))
            drawLine(x(k - 2), drawnY + box / 2, x(k), shownY - box / 2)
            drawLine(x(k), drawnY + box / 2, x(k), shownY - box / 2)
        }

        // The top row: what draw() made, one frame on every other refresh.
        for k in stride(from: 0, to: refreshes, by: 2) {
            drawnBox(names[k / 2], at: Vector2(x(k), drawnY), faint: false)
        }

        // The bottom row: what the display showed.
        for k in 0..<refreshes {
            let at = Vector2(x(k), shownY)
            if k == 0 {
                drawnBox(names[0], at: at, faint: false)
            } else if k == 1 {
                drawnBox(names[0], at: at, faint: true)
            } else if k % 2 == 0 {
                madeBox("\(names[k / 2 - 1])\(names[k / 2])", at: at)
            } else {
                drawnBox(names[(k - 1) / 2], at: at, faint: false)
            }
        }

        // The axis of refreshes.
        stroke(theme.ink(0.5))
        strokeWeight(1)
        drawLine(left - box / 2, axisY, right + box / 2, axisY)
        for k in 0..<refreshes {
            drawLine(x(k), axisY - 5, x(k), axisY + 5)
        }
        drawText("twelve refreshes of a 60 Hz display, a fifth of a second",
                 left - box / 2, axisY + 12, size: 14, color: theme.muted, align: .left, .top)

        drawText("draw() made", left - box / 2 - 20, drawnY,
                 size: 16, color: theme.ink, align: .right, .middle)
        drawText("the display showed", left - box / 2 - 20, shownY,
                 size: 16, color: theme.ink, align: .right, .middle)
        drawText("repeated", x(1), shownY + box / 2 + 6, size: 12, color: theme.muted,
                 align: .center, .top)
        drawText("made from A and B", x(2) - box / 2, shownY + box / 2 + 22, size: 12,
                 color: theme.accent, align: .left, .top)
        drawText("one refresh later", x(3) + 6, (drawnY + shownY) / 2 + 12, size: 12,
                 color: theme.muted, align: .left, .middle)

        diagramCaption("six frames drawn, twelve shown, and each drawn one arrives a refresh late",
                       at: 382, theme: theme)
    }

    /// A drawn frame: a solid box with its letter. Faint when it is a repeat.
    private func drawnBox(_ name: String, at center: Vector2, faint: Bool) {
        noStroke()
        fill(faint ? theme.ink(0.3) : theme.ink)
        drawRect(center.x - box / 2, center.y - box / 2, box, box)
        drawText(name, center.x, center.y + 1, size: 16, color: theme.paper,
                 align: .center, .middle)
    }

    /// A made frame: an accent outline with the two letters it was built from.
    private func madeBox(_ name: String, at center: Vector2) {
        fill(theme.accent(0.12))
        stroke(theme.accent)
        strokeWeight(2)
        drawRect(center.x - box / 2, center.y - box / 2, box, box)
        noStroke()
        drawText(name, center.x, center.y + 1, size: 14, color: theme.accent,
                 align: .center, .middle)
    }
}
