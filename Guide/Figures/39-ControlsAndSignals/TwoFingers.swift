// figure: frame=0 themed
//
// Guide diagram (Chapter 39): what a pinch and a turn read as. Two fingers on
// the trackpad at one reading (hollow) and the next (filled): the distance
// between them grew to 1.4 times, and the line between them turned 25 degrees
// clockwise. Beside it the two values that frame reads, and a square sized and
// turned by them. The values are the figure's own, so it draws the same on any
// machine.
import Foundation
import Ollin
import OllinDiagram

final class TwoFingers: Sketch {
    override var canvasSize: CanvasSize { .size(880, 520) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.4) }
    var soft: Color { theme.ink(0.62) }
    var accent: Color { theme.accent }

    // The gesture: the fingers spread from 140 apart to 1.4 times that, and
    // the line between them turns 25 degrees.
    let half = 70.0
    let spread = 1.4
    let before = -0.30
    let turn = 25.0 * .pi / 180

    override func draw() {
        background(paper)

        textFont(.systemMedium)
        fill(ink)
        textSize(21)
        textAlign(.left)
        drawText("two fingers, one frame apart", 50, 52)

        fill(soft)
        textSize(14)
        drawText("each frame reads how much they spread and how far they turned", 50, 76)

        trackpad(center: Vector2(240, 262))
        readouts(at: Vector2(480, 130))
        square(center: Vector2(640, 410))
    }

    // MARK: - The fingers

    private func trackpad(center c: Vector2) {
        noFill()
        stroke(faint)
        strokeWeight(2)
        drawRect(center: c, width: 380, height: 300, cornerRadius: 28)

        let after = before + turn
        let a0 = Vector2(angle: before, length: half), a1 = Vector2(angle: after, length: half * spread)

        // The turn, swept between the two lines past the right-hand fingers.
        stroke(accent.withAlpha(0.7))
        strokeWeight(2)
        drawArc(center: c, radiusX: 146, radiusY: 146, start: before, stop: after)
        noStroke()
        fill(accent)
        textSize(13)
        textAlign(.left)
        let label = c + Vector2(angle: before + turn / 2, length: 156)
        drawText("25°", label.x, label.y + 5)

        // The reading before: hollow fingers on a dashed line.
        stroke(soft)
        strokeWeight(1.5)
        strokeDash([5, 5])
        drawLine(c - a0, c + a0)
        drawLine(c + a0, c + Vector2(angle: before, length: 146))
        strokeDash([])
        noFill()
        strokeWeight(2)
        drawCircle(center: c - a0, radius: 15)
        drawCircle(center: c + a0, radius: 15)

        // The reading after: filled fingers on a solid line.
        stroke(accent)
        strokeWeight(2)
        drawLine(c - a1, c + a1)
        stroke(accent.withAlpha(0.5))
        strokeDash([5, 5])
        drawLine(c + a1, c + Vector2(angle: after, length: 146))
        strokeDash([])
        noStroke()
        fill(accent.withAlpha(0.85))
        drawCircle(center: c - a1, radius: 15)
        drawCircle(center: c + a1, radius: 15)

        // The distances, each on the right half of its own line: the first
        // above it, the second below.
        textSize(13)
        textAlign(.center)
        fill(soft)
        let d0 = c + Vector2(angle: before, length: half / 2) + Vector2(angle: before - .pi / 2, length: 16)
        drawText("d", d0.x, d0.y + 4)
        fill(accent)
        let d1 = c + Vector2(angle: after, length: half * spread / 2) + Vector2(angle: after + .pi / 2, length: 20)
        drawText("1.4 d", d1.x, d1.y + 4)

        // Which reading is which.
        let key = c + Vector2(-160, 118)
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawCircle(center: key, radius: 7)
        noStroke()
        fill(accent.withAlpha(0.85))
        drawCircle(center: key + Vector2(150, 0), radius: 7)
        fill(soft)
        textSize(12)
        textAlign(.left)
        drawText("one reading", key.x + 14, key.y + 4)
        drawText("the next", key.x + 164, key.y + 4)
    }

    // MARK: - What the frame reads

    private func readouts(at origin: Vector2) {
        withState {
            translate(origin)
            row(0, "pinchScale", String(format: "%.2f", spread),
                note: "how much the distance between the\nfingers grew: 1.4 d over d")
            row(1, "turnAngle", String(format: "%.2f", turn),
                note: "how far the line between them turned,\nin radians, clockwise on the screen")
        }
    }

    private func row(_ index: Int, _ call: String, _ value: String, note: String) {
        let y = Double(index) * 82

        noStroke()
        fill(ink)
        textSize(14)
        textAlign(.left)
        drawText(call, 0, y)

        fill(accent)
        textSize(15)
        textAlign(.right)
        drawText(value, 350, y)
        textAlign(.left)

        fill(soft)
        textSize(12)
        var line = y + 20
        for part in note.split(separator: "\n") {
            drawText(String(part), 0, line)
            line += 16
        }

        stroke(faint)
        strokeWeight(1)
        drawLine(Vector2(0, y + 54), Vector2(350, y + 54))
    }

    // MARK: - What a sketch does with them

    private func square(center c: Vector2) {
        noStroke()
        fill(ink)
        textSize(13)
        textAlign(.left)
        drawText("size *= pinchScale", 480, 318)
        drawText("spin += turnAngle", 480, 338)

        let size = 64.0
        withState {
            translate(c)
            noFill()
            stroke(soft)
            strokeWeight(1.5)
            strokeDash([5, 5])
            drawRect(center: .zero, width: size, height: size)
            strokeDash([])
            rotate(turn)
            stroke(accent)
            strokeWeight(2.5)
            drawRect(center: .zero, width: size * spread, height: size * spread)
        }
    }
}
