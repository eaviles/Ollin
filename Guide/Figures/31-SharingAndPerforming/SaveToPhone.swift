// figure: frame=0 themed
//
// Guide diagram (Chapter 31): what a save does when the sketch is on the
// phone. The file on the Mac, with one line changed; the three steps a save
// runs, with the times each takes; and the phone before and after, its screen
// rendered from one probe through OllinApp.image(of:) at the same frame twice,
// the hue changed the way the edit changed it. The rings stand at the same
// radii in both, which is the claim: the state the app writes down every
// second is read back at launch, so a reinstall carries on where the last
// version was. Under the phones, what that state holds; under everything, the
// parameters reaching a browser on the Mac.
//
// SaveToPhone is declared first on purpose: the loader compiles the first
// `class …: Sketch` it finds, so the probe comes after it.
import Ollin
import OllinDiagram

final class SaveToPhone: Sketch {
    override var canvasSize: CanvasSize { .size(880, 540) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    /// The two screens, made once and kept for the themed second pass.
    private var screens: [Image] = []

    override func setup() { noLoop() }

    override func draw() {
        background(theme.paper)
        textFont(.system)
        if screens.isEmpty {
            screens = [0.55, 0.05].map { hue in
                let probe = PhoneProbe()
                probe.hue = hue
                guard let exported = OllinApp.image(of: probe, frame: 40) else { return Image(width: 1, height: 1) }
                return Image(cgImage: exported)
            }
        }

        // The file on the Mac, with the line that changed.
        let file = Rectangle(x: 40, y: 70, width: 250, height: 168)
        noStroke()
        drawText("on the Mac", file.center.x, file.y - 22, size: 16, color: theme.ink, align: .center, .middle)
        fill(theme.card)
        stroke(theme.border)
        strokeWeight(1)
        drawRect(file, cornerRadius: 8)
        noStroke()
        drawText("TouchRings.swift", file.x + 14, file.y + 18, size: 12, color: theme.muted, align: .left, .middle)
        let code = ["for ring in 0..<9 {", "    stroke(Color(", "        hue: 0.05 + step * 0.25,", "        saturation: 0.5,", "        brightness: 1))", "    drawCircle(center:", "               radius: radius)"]
        for (i, line) in code.enumerated() {
            let y = file.y + 40 + Double(i) * 17
            let changed = i == 2
            if changed {
                fill(theme.accent(0.14))
                drawRect(file.x + 8, y - 8, file.width - 16, 17, cornerRadius: 3)
            }
            drawText(line, file.x + 14, y, size: 11.5, color: changed ? theme.ink : theme.ink(0.65),
                     align: .left, .middle)
        }
        chip("saved", at: file.x + file.width - 62, y: file.y + 18)
        drawText("ollin phone TouchRings.swift", file.center.x, file.y + file.height + 18, size: 12.5,
                 color: theme.ink, align: .center, .middle)
        drawText("the framework built once, about 80 s; then a save is:",
                 file.center.x, file.y + file.height + 40, size: 11, color: theme.muted, align: .center, .middle)

        // The three steps of a save.
        let steps: [(String, String)] = [
            ("the one file recompiled", "5 to 7 s, the app relinked and signed"),
            ("installed again", "about 2.5 s, over the cable or Wi-Fi"),
            ("launched, the state read back", "under ten seconds from the save"),
        ]
        let stepX = 330.0, stepW = 230.0
        for (i, step) in steps.enumerated() {
            let y = 92.0 + Double(i) * 62
            let box = Rectangle(x: stepX, y: y, width: stepW, height: 44)
            fill(theme.dark ? Color(hex: 0x1C232C) : .white)
            stroke(theme.border)
            strokeWeight(1.5)
            drawRect(box, cornerRadius: 8)
            noStroke()
            drawText(step.0, box.x + 12, box.y + 15, size: 13, color: theme.ink, align: .left, .middle)
            drawText(step.1, box.x + 12, box.y + 32, size: 11, color: theme.muted, align: .left, .middle)
            if i < steps.count - 1 {
                arrow(from: Vector2(box.center.x, box.y + box.height + 2), to: Vector2(box.center.x, y + 60))
            }
        }
        arrow(from: Vector2(file.x + file.width + 8, 114), to: Vector2(stepX - 6, 114))
        arrow(from: Vector2(stepX + stepW + 8, 260), to: Vector2(600, 260))

        // The phone, before and after.
        let phoneW = 100.0, phoneH = 210.0, phoneY = 70.0
        let before = Rectangle(x: 612, y: phoneY, width: phoneW, height: phoneH)
        let after = Rectangle(x: 742, y: phoneY, width: phoneW, height: phoneH)
        noStroke()
        drawText("the phone", (before.center.x + after.center.x) / 2, phoneY - 22, size: 16, color: theme.ink,
                 align: .center, .middle)
        phone(before, screen: screens[0])
        phone(after, screen: screens[1])
        drawText("before", before.center.x, phoneY + phoneH + 12, size: 12, color: theme.muted, align: .center, .top)
        drawText("after the save", after.center.x, phoneY + phoneH + 12, size: 12, color: theme.muted, align: .center, .top)
        stroke(theme.accent)
        strokeWeight(1.5)
        drawLine(before.x + phoneW + 6, phoneY + phoneH / 2, after.x - 6, phoneY + phoneH / 2)
        noStroke()
        drawText("the same phase, the new colors", (before.center.x + after.center.x) / 2, phoneY + phoneH + 30,
                 size: 11, color: theme.accent, align: .center, .top)

        // What the app writes down every second.
        let state = Rectangle(x: 600, y: 334, width: 250, height: 96)
        fill(theme.card)
        stroke(theme.border)
        strokeWeight(1)
        drawRect(state, cornerRadius: 8)
        noStroke()
        drawText("written every second, read back at launch", state.x + 12, state.y + 16, size: 11,
                 color: theme.muted, align: .left, .middle)
        let held = ["the clock and the seed", "every @Param value", "every @Saved property"]
        for (i, line) in held.enumerated() {
            drawText(line, state.x + 12, state.y + 40 + Double(i) * 18, size: 12.5, color: theme.ink,
                     align: .left, .middle)
        }
        drawText("so the phase holds, and a tuned value stays tuned",
                 state.center.x, state.y + state.height + 12, size: 11, color: theme.muted, align: .center, .top)

        // The parameters, in a browser on the Mac.
        let strip = Rectangle(x: 330, y: 330, width: 230, height: 84)
        fill(theme.dark ? Color(hex: 0x1C232C) : .white)
        stroke(theme.border)
        strokeWeight(1.5)
        drawRect(strip, cornerRadius: 8)
        noStroke()
        drawText("the parameters, both ways", strip.x + 12, strip.y + 16, size: 13, color: theme.ink, align: .left, .middle)
        drawText("http://localhost:9330", strip.x + 12, strip.y + 38, size: 12, color: theme.accent, align: .left, .middle)
        drawText("a slider on the Mac moves the phone;", strip.x + 12, strip.y + 58, size: 11, color: theme.muted, align: .left, .middle)
        drawText("a value tuned there rides every save", strip.x + 12, strip.y + 72, size: 11, color: theme.muted, align: .left, .middle)

        diagramCaption("a save is a build and a reinstall, and the written state makes it a swap",
                       at: 466, theme: theme)
        drawText("the phone has to be unlocked to launch the new version, and on the cable or awake on the same network",
                 width / 2, 496, size: 13, color: theme.muted, align: .center, .top)
    }

    private func phone(_ r: Rectangle, screen: Image) {
        fill(Color(hex: 0x111318))
        stroke(theme.border)
        strokeWeight(2)
        drawRect(r, cornerRadius: 14)
        let inset = Rectangle(x: r.x + 5, y: r.y + 5, width: r.width - 10, height: r.height - 10)
        drawImage(screen, in: inset)
        noStroke()
        fill(Color(hex: 0x111318))
        drawRect(r.x + r.width / 2 - 20, r.y + 7, 40, 8, cornerRadius: 4)
    }

    private func chip(_ text: String, at x: Double, y: Double) {
        textSize(11)
        let w = textWidth(text) + 14
        fill(theme.accent(0.12))
        stroke(theme.accent)
        strokeWeight(1.2)
        drawRect(x - 7, y - 9, w, 18, cornerRadius: 5)
        noStroke()
        drawText(text, x, y + 1, size: 11, color: theme.ink, align: .left, .middle)
    }

    private func arrow(from a: Vector2, to b: Vector2) {
        let dir = (b - a).normalized
        stroke(theme.accent)
        strokeWeight(2)
        drawLine(a, b - dir * 9)
        noStroke()
        fill(theme.accent)
        drawPolygon([b, b - dir * 11 + dir.perpendicular * 4.5, b - dir * 11 - dir.perpendicular * 4.5])
    }
}

/// The probe: the rings of the reference phone sketch, at the phone's shape,
/// with the hue as the value the edit changes.
final class PhoneProbe: Sketch {
    override var canvasSize: CanvasSize { .size(180, 400) }

    @Param("Hue", 0 ... 1) var hue = 0.55

    override func draw() {
        background(Color(red: 0.05, green: 0.05, blue: 0.07))
        let short = min(width, height)
        noFill()
        strokeWeight(2)
        for ring in 0..<9 {
            let step = Double(ring) / 9
            let radius = short * (0.06 + step * 0.42) + sin(time * 1.2 - step * 3) * short * 0.02
            stroke(Color(hue: hue + step * 0.25, saturation: 0.5, brightness: 1,
                         alpha: 0.25 + (1 - step) * 0.4))
            drawCircle(center: center, radius: radius)
        }
        noStroke()
        fill(Color(red: 1, green: 0.85, blue: 0.4, alpha: 0.9))
        drawCircle(center: center + Vector2(short * 0.18, short * 0.3), radius: short * 0.04)
    }
}
