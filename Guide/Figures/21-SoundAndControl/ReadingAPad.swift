// figure: frame=0
//
// Guide diagram (Chapter 21): what a controller reads, in one pose. A stick
// held up and to the right, a trigger half pulled, one face button down, with
// the value each read returns beside it. The values are the figure's own, so
// this draws the same whether or not a controller is plugged in.
import Ollin

final class ReadingAPad: Sketch {
    override var canvasSize: CanvasSize { .size(880, 560) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.4)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.62)
    let accent = Color(hex: 0xE4572E)
    let idle = Color(hex: 0x2B2B2B, alpha: 0.14)

    // The pose. Held up and to the right, so both axes are worth reading, and
    // the y is where the sign rule shows.
    let stick = Vector2(0.71, -0.71)
    let trigger = 0.5

    override func draw() {
        background(Color(hex: 0xF7F5F1))

        textFont(.systemMedium)
        fill(ink)
        textSize(21)
        textAlign(.left)
        drawText("one frame of a controller", 50, 52)

        fill(soft)
        textSize(14)
        drawText("read fresh in draw(), the way you read mouseX", 50, 76)

        pad(at: Vector2(60, 120))
        readouts(at: Vector2(470, 138))
    }

    // MARK: - The controller

    private func pad(at origin: Vector2) {
        withState {
            translate(origin)

            // Body.
            noFill()
            stroke(faint)
            strokeWeight(2)
            drawRect(corner: Vector2(0, 40), width: 360, height: 210, cornerRadius: 46)

            // Shoulders and triggers, drawn as fill levels so a half pull reads
            // as half full rather than as a switch.
            triggerBar(at: Vector2(46, 6), value: 0, label: "LT")
            triggerBar(at: Vector2(268, 6), value: trigger, label: "RT")

            dpad(at: Vector2(78, 108))
            faceButtons(at: Vector2(282, 108))

            stickWell(at: Vector2(130, 186), value: stick, live: true, label: "left")
            stickWell(at: Vector2(232, 186), value: .zero, live: false, label: "right")
        }
    }

    private func triggerBar(at origin: Vector2, value: Double, label: String) {
        let w = 46.0, h = 22.0
        noStroke()
        fill(idle)
        drawRect(corner: origin, width: w, height: h, cornerRadius: 8)
        if value > 0 {
            fill(accent)
            drawRect(corner: origin, width: w * value, height: h, cornerRadius: 8)
        }
        fill(soft)
        textSize(11)
        textAlign(.center)
        drawText(label, origin.x + w / 2, origin.y - 6)
        textAlign(.left)
    }

    private func dpad(at c: Vector2) {
        noStroke()
        fill(idle)
        drawRect(center: c, width: 62, height: 20, cornerRadius: 5)
        drawRect(center: c, width: 20, height: 62, cornerRadius: 5)
    }

    /// Named by position, so the bottom one is `.a` whatever the pad prints.
    private func faceButtons(at c: Vector2) {
        let r = 13.0, gap = 27.0
        let places: [(Vector2, String, Bool)] = [
            (c + Vector2(0, -gap), "y", false),
            (c + Vector2(-gap, 0), "x", false),
            (c + Vector2(gap, 0), "b", false),
            (c + Vector2(0, gap), "a", true),
        ]
        for (p, name, down) in places {
            noStroke()
            fill(down ? accent : idle)
            drawCircle(center: p, radius: r)
            fill(down ? Color.white : soft)
            textSize(12)
            textAlign(.center)
            drawText(name, p.x, p.y + 4)
            textAlign(.left)
        }
    }

    private func stickWell(at c: Vector2, value: Vector2, live: Bool, label: String) {
        let reach = 26.0
        noFill()
        stroke(faint)
        strokeWeight(2)
        drawCircle(center: c, radius: reach + 8)

        if live {
            stroke(accent.withAlpha(0.5))
            strokeWeight(2)
            drawLine(c, c + value * reach)
        }
        noStroke()
        fill(live ? accent : idle)
        drawCircle(center: c + value * reach, radius: 9)

        fill(soft)
        textSize(11)
        textAlign(.center)
        drawText(label, c.x, c.y + reach + 30)
        textAlign(.left)
    }

    // MARK: - What each read gives back

    private func readouts(at origin: Vector2) {
        withState {
            translate(origin)

            row(0, "controller.leftStick", String(format: "(%.2f, %.2f)", stick.x, stick.y),
                note: "up is negative y, the way the canvas counts,\nso adding it to a position moves up the screen")
            row(1, "controller.rightStick", "(0.00, 0.00)",
                note: "resting inside the deadzone, so it reads exactly zero")
            row(2, "controller.rightTrigger", String(format: "%.2f", trigger),
                note: "a level, not a switch: half pulled is half")
            row(3, "controller.isDown(.a)", "true",
                note: "the bottom face button, whatever the pad prints on it")
            row(4, "controller.wasPressed(.a)", "false",
                note: "true on the one frame it went down, and not while held")
        }
    }

    private func row(_ index: Int, _ call: String, _ value: String, note: String) {
        let y = Double(index) * 82

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
}
