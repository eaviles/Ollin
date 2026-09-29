// figure: frame=0 themed
//
// Guide diagram (Chapter 44): what `device.show(self)` sets going. The sketch
// runs in the live window on the Mac; each frame it draws is compressed on the
// Mac's media engine and sent down the cable on a connection of its own, and
// the phone decodes it and shows it full screen. The finger on the glass goes
// back up the cable on the sensor connection, and the first finger becomes the
// sketch's pointer before its next draw. Both screens are one render of the
// probe through OllinApp.image(of:), since the phone shows the Mac's picture.
//
// ShowOnPhone is declared first on purpose: the loader compiles the first
// `class …: Sketch` it finds, so the probe comes after it.
import Ollin
import OllinDiagram

final class ShowOnPhone: Sketch {
    override var canvasSize: CanvasSize { .size(880, 500) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    /// The picture both screens show, made once and kept for the themed pass.
    private var picture: Image?

    /// Where the finger rests, as a fraction of the screen.
    private let finger = Vector2(0.64, 0.36)

    override func setup() { noLoop() }

    override func draw() {
        background(theme.paper)
        textFont(.system)
        if picture == nil {
            let probe = PourProbe()
            probe.finger = finger
            if let exported = try? OllinApp.image(of: probe, frame: 0) {
                picture = Image(cgImage: exported)
            }
        }
        let screen = picture ?? Image(width: 1, height: 1)

        // The live window on the Mac.
        let window = Rectangle(x: 36, y: 64, width: 124, height: 270)
        noStroke()
        drawText("on the Mac", 206, 34, size: 16, color: theme.ink, align: .center, .middle)
        fill(theme.card)
        stroke(theme.border)
        strokeWeight(1.5)
        drawRect(window, cornerRadius: 8)
        noStroke()
        for i in 0..<3 {
            fill(theme.ink(0.25))
            drawCircle(window.x + 12 + Double(i) * 10, window.y + 11, 3)
        }
        let canvas = Rectangle(x: window.x + 8, y: window.y + 22, width: window.width - 16, height: window.height - 30)
        drawImage(screen, in: canvas)
        drawText("the live window", window.center.x, window.y + window.height + 14, size: 12, color: theme.muted,
                 align: .center, .top)

        // The Mac's two jobs: a frame out, a finger in.
        let out = Rectangle(x: 184, y: 76, width: 212, height: 56)
        box(out, title: "each frame, compressed", lines: ["as HEVC on the media engine,", "straight from the texture"])
        let pointer = Rectangle(x: 184, y: 236, width: 212, height: 88)
        box(pointer, title: "the first finger is the pointer",
            lines: ["mouseX, mouseY, mouseIsPressed", "and pressure, set before", "the next draw()"])
        arrow(from: Vector2(window.x + window.width + 4, out.center.y), to: Vector2(out.x - 4, out.center.y))
        arrow(from: Vector2(pointer.x - 4, pointer.center.y), to: Vector2(window.x + window.width + 4, pointer.center.y))

        // The cable, with its two connections.
        let cable = Rectangle(x: 420, y: 58, width: 180, height: 286)
        fill(theme.card)
        stroke(theme.border)
        strokeWeight(1)
        drawRect(cable, cornerRadius: 10)
        noStroke()
        drawText("the cable", cable.center.x, cable.y + cable.height + 14, size: 12, color: theme.muted,
                 align: .center, .top)
        let down = out.center.y, up = pointer.center.y
        arrow(from: Vector2(out.x + out.width + 4, down), to: Vector2(694, down))
        drawText("pictures, port 1339", cable.center.x, down - 18, size: 12.5, color: theme.ink, align: .center, .middle)
        drawText("most carry only what changed;", cable.center.x, down + 20, size: 11, color: theme.muted,
                 align: .center, .middle)
        drawText("a whole one every second", cable.center.x, down + 35, size: 11, color: theme.muted,
                 align: .center, .middle)
        drawText("a frame the cable can't take yet", cable.center.x, down + 62, size: 11, color: theme.muted,
                 align: .center, .middle)
        drawText("is skipped before it is compressed", cable.center.x, down + 77, size: 11, color: theme.muted,
                 align: .center, .middle)
        arrow(from: Vector2(694, up), to: Vector2(pointer.x + pointer.width + 4, up))
        drawText("fingers and tilt, port 1338", cable.center.x, up - 18, size: 12.5, color: theme.ink,
                 align: .center, .middle)
        drawText("the sensor connection", cable.center.x, up + 20, size: 11, color: theme.muted, align: .center, .middle)

        // The phone, showing the Mac's picture, with the finger on it.
        let phone = Rectangle(x: 704, y: 64, width: 126, height: 270)
        noStroke()
        drawText("the phone", phone.center.x, 34, size: 16, color: theme.ink, align: .center, .middle)
        fill(Color(hex: 0x111318))
        stroke(theme.border)
        strokeWeight(2)
        drawRect(phone, cornerRadius: 16)
        let glass = Rectangle(x: phone.x + 6, y: phone.y + 6, width: phone.width - 12, height: phone.height - 12)
        drawImage(screen, in: glass)
        noStroke()
        fill(Color(hex: 0x111318))
        drawRect(phone.center.x - 20, phone.y + 9, 40, 8, cornerRadius: 4)
        let tip = Vector2(glass.x + glass.width * finger.x, glass.y + glass.height * finger.y)
        fill(Color(white: 1, alpha: 0.28))
        stroke(Color(white: 1, alpha: 0.75))
        strokeWeight(1.5)
        drawCircle(center: tip, radius: 11)
        noStroke()
        drawText("decoded on its media engine,", phone.center.x, phone.y + phone.height + 14, size: 12,
                 color: theme.muted, align: .center, .top)
        drawText("shown full screen in Sketch mode", phone.center.x, phone.y + phone.height + 30, size: 12,
                 color: theme.muted, align: .center, .top)

        diagramCaption("the Mac draws and the phone shows; the finger comes back as the pointer", at: 408,
                       theme: theme)
        drawText("a save under the live window reaches the phone once the Mac has compiled it; nothing is built for the phone",
                 width / 2, 446, size: 13, color: theme.muted, align: .center, .top)
    }

    private func box(_ r: Rectangle, title: String, lines: [String]) {
        fill(theme.dark ? Color(hex: 0x1C232C) : .white)
        stroke(theme.border)
        strokeWeight(1.5)
        drawRect(r, cornerRadius: 8)
        noStroke()
        drawText(title, r.x + 12, r.y + 16, size: 13, color: theme.ink, align: .left, .middle)
        for (i, line) in lines.enumerated() {
            drawText(line, r.x + 12, r.y + 35 + Double(i) * 15, size: 11, color: theme.muted, align: .left, .middle)
        }
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

/// The probe: a painting sketch at the phone's shape, the fuller one the
/// chapter points to in Examples/3D/Phone/PhoneCanvas rather than its short
/// `Pour`, which draws only the circle under the finger. A finger is held down,
/// with the paint it has already let fall below it.
final class PourProbe: Sketch {
    override var canvasSize: CanvasSize { .size(216, 468) }

    /// Where the finger rests, as a fraction of the canvas.
    var finger = Vector2(0.64, 0.36)

    override func draw() {
        background(Color(white: 0.05))
        noStroke()
        let tip = Vector2(width * finger.x, height * finger.y)
        // What the finger laid down on its way here, oldest first.
        for i in 0..<24 {
            let t = Double(i) / 23
            let x = width * (0.22 + t * 0.42) + sin(t * 7) * width * 0.08
            let y = height * (0.78 - t * 0.42)
            fill(Color(hue: 0.08 + t * 0.06, saturation: 0.75, brightness: 1, alpha: 0.18 + t * 0.35))
            drawCircle(x, y, width * (0.03 + t * 0.03))
        }
        fill(Color(hue: 0.13, saturation: 0.6, brightness: 1, alpha: 0.95))
        drawCircle(center: tip, radius: width * 0.09)
    }
}
