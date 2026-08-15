// figure: frame=1
//
// Guide diagram (Chapter 22): the two ways a long run breaks the clock, and what
// is done about each. Above, a night with no frames: the wall clock hands the
// piece the whole gap, the summed clock hands it one capped step. Below, the
// 32-bit clock a shader reads, stuck after a week and exact again once it
// restarts on a whole lap.
import Ollin

final class LongRunClock: Sketch {
    override var canvasSize: CanvasSize { .size(880, 540) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.55)
    let accent = Color(hex: 0xE4572E)
    let good = Color(hex: 0x2E7D5B)
    let rule = Color(hex: 0x2B2B2B, alpha: 0.18)
    let shade = Color(hex: 0x2B2B2B, alpha: 0.07)

    let left = 60.0
    let right = 820.0

    override func draw() {
        background(paper)
        noStroke()

        heading("a night with no frames", at: Vector2(left, 40))
        timeline()

        heading("the clock a shader reads, three frames apart", at: Vector2(left, 330))
        readout(title: "after a week, counting seconds",
                readings: "604800.00   604800.00   604800.00",
                note: "stuck: a frame no longer changes it",
                tint: accent, at: Vector2(left, 366))
        readout(title: "restarted on a whole lap",
                readings: "37.50   37.52   37.53",
                note: "exact again, and the restart is hidden",
                tint: good, at: Vector2(448, 366))
    }

    /// Frames, a gap with none, and then the first frame back.
    func timeline() {
        let axis = 150.0
        let gapStart = 330.0, gapEnd = 560.0

        fill(shade)
        drawRect(gapStart, axis - 40, gapEnd - gapStart, 80)

        stroke(rule)
        strokeWeight(1)
        drawLine(Vector2(left, axis), Vector2(right, axis))

        stroke(ink)
        strokeWeight(2)
        var x = left
        while x < gapStart - 6 {
            drawLine(Vector2(x, axis - 9), Vector2(x, axis + 9))
            x += 15
        }
        x = gapEnd
        while x <= right {
            drawLine(Vector2(x, axis - 9), Vector2(x, axis + 9))
            x += 15
        }
        // The frame the gap ends on, which is the one that has to be read.
        stroke(accent)
        strokeWeight(3)
        drawLine(Vector2(gapEnd, axis - 13), Vector2(gapEnd, axis + 13))

        noStroke()
        fill(soft)
        textSize(15)
        textAlign(.center, .center)
        drawText("no frames for 8 hours: the display slept", (gapStart + gapEnd) / 2, axis - 58)
        textAlign(.left, .center)
        drawText("frames", left, axis + 32)
        fill(accent)
        drawText("the first frame back", gapEnd + 8, axis + 32)

        fill(ink)
        textSize(16)
        textAlign(.left, .top)
        drawText("that one frame is worth:", left, axis + 66)

        answer(mark: "by the wall clock", value: "deltaTime = 8 hours",
               note: "every integrator jumps with it",
               tint: accent, y: axis + 104)
        answer(mark: "by the sum of its steps", value: "deltaTime = 0.25 s",
               note: "the piece carries on where it stopped",
               tint: good, y: axis + 138)
    }

    func heading(_ text: String, at p: Vector2) {
        noStroke()
        fill(ink)
        textSize(20)
        textAlign(.left, .top)
        drawText(text, p.x, p.y)
    }

    /// One reading of that frame: a coloured dot, how it was measured, the
    /// number it gives, and what that costs.
    func answer(mark: String, value: String, note: String, tint: Color, y: Double) {
        noStroke()
        fill(tint)
        drawCircle(left + 5, y, 5)
        fill(ink)
        textSize(15)
        textAlign(.left, .center)
        drawText(mark, left + 20, y)
        drawText(value, left + 240, y)
        fill(soft)
        drawText(note, left + 424, y)
    }

    /// A small card of three consecutive frames' clock values.
    func readout(title: String, readings: String, note: String, tint: Color, at p: Vector2) {
        let card = Rectangle(x: p.x, y: p.y, width: 372, height: 128)
        fill(Color(white: 1))
        drawRect(card, cornerRadius: 10)
        fill(tint)
        drawRect(card.x, card.y, 4, card.height, cornerRadius: 2)

        textAlign(.left, .top)
        fill(soft)
        textSize(14)
        drawText(title, card.x + 22, card.y + 16)

        fill(ink)
        textSize(17)
        drawText(readings, card.x + 22, card.y + 46)

        fill(tint)
        textSize(13)
        drawText(note, card.x + 22, card.y + 90)
    }
}
