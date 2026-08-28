// figure: frame=0 themed
//
// Guide diagram (Chapter 28): bytes mean nothing until a characteristic says
// what they are. One heart rate reading is read right and read wrong, and two
// more values show a scale and a sign. Boxes and arrows drawn with Ollin,
// like every diagram in the guide.
import Ollin
import OllinDiagram

final class BytesIntoValues: Sketch {
    override var canvasSize: CanvasSize { .size(880, 560) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.6) }
    var faint: Color { theme.ink(0.35) }
    var accent: Color { theme.accent }
    var card: Color { theme.card }

    override func draw() {
        background(paper)

        noStroke()
        fill(soft)
        textSize(17)
        textAlign(.left, .top)
        drawText("what arrives from a heart rate strap", 60, 36)

        // The packet, as it comes off the radio.
        let bytes = ["10", "72", "02", "03"]
        for (index, byte) in bytes.enumerated() {
            let x = 60 + Double(index) * 92
            let lit = index <= 1
            cell(x: x, y: 70, text: byte, lit: lit)
        }
        fill(faint)
        textSize(15)
        textAlign(.left, .center)
        drawText("the beat intervals: another field, not the rate", 60 + 4 * 92 + 8, 106)

        // What the first byte decides.
        arrow(from: Vector2(96, 146), to: Vector2(96, 196))
        fill(ink)
        textSize(17)
        textAlign(.left, .top)
        drawText("flags", 118, 190)
        fill(soft)
        textSize(15)
        drawText("its lowest bit is 0, so the rate that follows is one byte wide", 118, 214)

        // Read right.
        row(y: 268, label: "read as the standard says",
            reading: ".heartRateMeasurement", result: "72 beats a minute", good: true)

        // Read wrong: the mistake the format exists to stop.
        row(y: 348, label: "read as two bytes anyway",
            reading: ".read(as: .uint16)", result: "626 beats a minute", good: false)

        // Two more, where the format also carries a scale and a sign.
        line(y: 424)
        small(y: 452, bytes: "64", name: ".batteryLevel",
              note: "one byte, no scale", result: "100%")
        small(y: 492, bytes: "2E FB", name: ".temperature",
              note: "two bytes, signed, hundredths", result: "-12.34 °C")
    }

    // MARK: - Parts

    func cell(x: Double, y: Double, text: String, lit: Bool) {
        fill(card)
        stroke(lit ? accent : theme.border)
        strokeWeight(lit ? 2.5 : 1.5)
        drawRect(x, y, 76, 72, cornerRadius: 8)
        noStroke()
        fill(lit ? ink : faint)
        textSize(26)
        textAlign(.center, .center)
        drawText(text, x + 38, y + 36)
    }

    func row(y: Double, label: String, reading: String, result: String, good: Bool) {
        noStroke()
        fill(soft)
        textSize(15)
        textAlign(.left, .top)
        drawText(label, 60, y)
        fill(ink)
        textSize(19)
        drawText(reading, 60, y + 24)

        arrow(from: Vector2(400, y + 32), to: Vector2(470, y + 32))

        fill(good ? accent : faint)
        textSize(24)
        drawText(result, 490, y + 18)
        if !good {
            // A strike through the wrong answer, so the eye reads it as the
            // thing not to do rather than as a second correct reading.
            stroke(faint)
            strokeWeight(2)
            drawLine(486, y + 32, 486 + Double(result.count) * 12.5, y + 32)
        }
    }

    func line(y: Double) {
        stroke(theme.border)
        strokeWeight(1)
        drawLine(60, y, width - 60, y)
    }

    func small(y: Double, bytes: String, name: String, note: String, result: String) {
        noStroke()
        fill(ink)
        textSize(19)
        textAlign(.left, .center)
        drawText(bytes, 60, y)
        fill(soft)
        textSize(17)
        drawText(name, 168, y)
        fill(faint)
        textSize(15)
        drawText(note, 380, y)
        fill(accent)
        textSize(19)
        drawText(result, 640, y)
    }

    func arrow(from a: Vector2, to b: Vector2) {
        let dir = (b - a).normalized
        stroke(accent)
        strokeWeight(3)
        drawLine(a, b - dir * 12)
        noStroke()
        fill(accent)
        drawPolygon([b, b - dir * 15 + dir.perpendicular * 6,
                        b - dir * 15 - dir.perpendicular * 6])
    }
}
