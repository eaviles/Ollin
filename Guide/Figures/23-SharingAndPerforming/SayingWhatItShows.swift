// figure: frame=0
//
// Guide figure (Chapter 23): one picture and what it says about itself. The
// scene on the left is drawn from a handful of numbers; the lines on the right
// are written from the same numbers by describe(), which is what a screen
// reader is handed. Nothing here is written twice.
import Ollin

final class SayingWhatItShows: Sketch {
    override var canvasSize: CanvasSize { .size(960, 460) }

    let ink = Color(hex: 0x2B2B2B)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.6)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(Color(hex: 0xF7F5F1))

        // The picture, drawn from these five numbers.
        let panel = Rectangle(x: 40, y: 64, width: 340, height: 320)
        let horizon = panel.corner.y + panel.height * 0.66
        let sun = Vector2(panel.corner.x + panel.width * 0.30, panel.corner.y + panel.height * 0.26)
        let sunRadius = 34.0
        let boat = Vector2(panel.corner.x + panel.width * 0.70, horizon + 46)

        withClip(panel) {
            noStroke()
            fill(Color(hex: 0x9EC6E8))
            drawRect(panel)
            for ring in stride(from: 4.0, through: 1.0, by: -1.0) {
                fill(Color(hex: 0xFFE9A8, alpha: 0.10))
                drawCircle(center: sun, radius: sunRadius * ring)
            }
            fill(Color(hex: 0xFFE08A))
            drawCircle(center: sun, radius: sunRadius)
            fill(Color(hex: 0x3E7CA6))
            drawRect(panel.corner.x, horizon, panel.width, panel.height)
            fill(Color(hex: 0x16202E))
            drawTriangle(Vector2(boat.x, boat.y - 30), Vector2(boat.x + 22, boat.y),
                         Vector2(boat.x, boat.y))
            drawRect(center: Vector2(boat.x, boat.y + 7), width: 54, height: 9)
        }

        // The words, written from the same five numbers.
        describe("A bay at noon. The sun stands high on the left, and a small "
                 + "boat crosses the water.")
        describe("the sun", as: "a pale yellow disc high on the left",
                 in: Rectangle(center: sun, width: sunRadius * 2, height: sunRadius * 2))
        describe("the water", as: "a flat blue band across the lower third",
                 in: Rectangle(x: panel.corner.x, y: horizon, width: panel.width, height: 110))
        describe("the boat", as: "a small dark hull with one sail, two thirds across",
                 in: Rectangle(center: boat, width: 60, height: 44))

        drawLabels(panel: panel)
    }

    private func drawLabels(panel: Rectangle) {
        noStroke()
        textFont(.systemMedium)

        let column = 448.0, columnWidth = 470.0

        fill(soft)
        textSize(15)
        textAlign(.left, .bottom)
        drawText("what it draws", panel.corner.x, panel.corner.y - 12)
        drawText("what it says", column, panel.corner.y - 12)

        // The first line is the whole piece; the rest are its named parts.
        let lines = accessibleDescription.lines
        var y = panel.corner.y + 10
        for (i, line) in lines.enumerated() {
            fill(i == 0 ? ink : soft)
            textSize(i == 0 ? 17 : 15)
            textAlign(.left, .top)
            drawText(line, in: Rectangle(x: column, y: y, width: columnWidth, height: 80))
            y += i == 0 ? 84 : 32
        }

        fill(accent)
        drawRect(column - 16, panel.corner.y + 8, 3, 56)

        fill(soft)
        textSize(14)
        textAlign(.center, .top)
        drawText("the same numbers place the sun and write the sentence about it",
                 width / 2, panel.corner.y + panel.height + 26)
    }
}
