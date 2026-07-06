// figure: frame=0
//
// Guide diagram: chance as a decision-maker. Two probability gates at
// different thresholds, a uniform pick from a four-color palette, and a
// weighted pick that leans hard on one color.
import Ollin

final class Choices: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.28)
    let accent = Color(hex: 0xE4572E)
    let palette: [Color] = [
        Color(hex: 0x5E60CE), Color(hex: 0x64DFDF),
        Color(hex: 0xFFB703), Color(hex: 0xE56B6F),
    ]

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(21)
        randomSeed(4)

        let slots = 34
        let left = 70.0, right = width - 70
        let pitch = (right - left) / Double(slots - 1)

        gateRow(y: 100, label: "if random() < 0.25 { draw }",
                probability: 0.25, slots: slots, left: left, pitch: pitch)
        gateRow(y: 210, label: "if random() < 0.75 { draw }",
                probability: 0.75, slots: slots, left: left, pitch: pitch)

        // A uniform pick: every color equally likely.
        rowLabel("palette[Int(random(4))] · every color equally likely", y: 320)
        for i in 0..<slots {
            fill(palette[Int(random(4))])
            noStroke()
            drawRect(left + Double(i) * pitch - 8, 344, 16, 26)
        }

        // A weighted pick: stack the thresholds.
        rowLabel("roll < 0.6 → indigo · roll < 0.9 → coral · else → gold", y: 430)
        for i in 0..<slots {
            let roll = random()
            var pick = palette[0]
            if roll >= 0.6 { pick = palette[3] }
            if roll >= 0.9 { pick = palette[2] }
            fill(pick)
            noStroke()
            drawRect(left + Double(i) * pitch - 8, 454, 16, 26)
        }
    }

    func rowLabel(_ text: String, y: Double) {
        noStroke()
        fill(ink)
        textAlign(.left, .bottom)
        drawText(text, 70, y - 4)
    }

    func gateRow(y: Double, label: String, probability: Double,
                 slots: Int, left: Double, pitch: Double) {
        rowLabel(label, y: y)
        for i in 0..<slots {
            let x = left + Double(i) * pitch
            if random() < probability {
                noStroke()
                fill(accent)
                drawCircle(x, y + 36, 9)
            } else {
                noFill()
                stroke(faint)
                strokeWeight(1.5)
                drawCircle(x, y + 36, 4)
            }
        }
    }
}
