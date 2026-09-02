// figure: frame=0 themed
//
// Guide diagram (Chapter 28): the physical-computing loop. A microcontroller
// prints one number per line over USB, a SerialPort reads it three ways, and
// a line written back drives the hardware. Boxes and arrows drawn with Ollin,
// like every diagram in the guide.
import Ollin
import OllinDiagram

final class SerialLoop: Sketch {
    override var canvasSize: CanvasSize { .size(880, 520) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.45) }
    var soft: Color { theme.ink(0.6) }
    var accent: Color { theme.accent }
    var card: Color { darkTheme ? Color(hex: 0x2A2724) : .white }

    override func draw() {
        background(paper)

        // The two ends of the wire.
        box(x: 60, y: 140, w: 260, h: 100, title: "a microcontroller",
            sub: "prints one number per line")
        box(x: 560, y: 140, w: 260, h: 100, title: "SerialPort",
            sub: "matching: \"usbmodem\"", accented: true)

        // Out: the sensor stream. Back: a command line.
        arrow(from: Vector2(322, 168), to: Vector2(558, 168))
        arrow(from: Vector2(558, 212), to: Vector2(322, 212))
        noStroke()
        fill(soft)
        textSize(15)
        textAlign(.center, .bottom)
        drawText("\"512\" and a newline, over USB", 440, 128)
        textAlign(.center, .top)
        drawText("writeLine(\"led:on\")", 440, 252)

        // What each end holds.
        fill(soft)
        textSize(15)
        textAlign(.center, .top)
        drawText("sensors in, servos and LEDs out", 190, 268)

        textAlign(.left, .top)
        fill(ink)
        drawText("float(default: 0)", 560, 290)
        drawText("lines()", 560, 318)
        drawText("bind(to: $radius)", 560, 346)
        fill(soft)
        drawText("the latest reading", 716, 290)
        drawText("each line, once", 716, 318)
        drawText("drives a parameter", 716, 346)

        noStroke()
        fill(soft)
        textSize(19)
        textAlign(.center, .top)
        drawText("unplugged, the port waits; plugged back in, it reopens by itself", width / 2, 452)
    }

    func box(x: Double, y: Double, w: Double, h: Double,
             title: String, sub: String, accented: Bool = false) {
        fill(card)
        stroke(accented ? accent : faint)
        strokeWeight(accented ? 2.5 : 1.5)
        drawRect(x, y, w, h, cornerRadius: 10)
        noStroke()
        fill(ink)
        textSize(20)
        textAlign(.center, .bottom)
        drawText(title, x + w / 2, y + h / 2 + 2)
        fill(soft)
        textSize(16)
        textAlign(.center, .top)
        drawText(sub, x + w / 2, y + h / 2 + 8)
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
