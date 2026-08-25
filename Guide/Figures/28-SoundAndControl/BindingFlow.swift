// figure: frame=0 themed
//
// Guide diagram (Chapter 28): three hands on one knob. A MIDI controller, an
// OSC message from a phone, and the inspector slider all drive the same
// @Param; the sketch just reads the property. Boxes and arrows drawn with
// Ollin, like every diagram in the guide.
import Ollin
import OllinDiagram

final class BindingFlow: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

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

        // The three sources.
        box(x: 50, y: 70, w: 250, h: 96, title: "a MIDI knob",
            sub: "controlChange 7, 0 to 127")
        box(x: 50, y: 212, w: 250, h: 96, title: "an OSC message",
            sub: "/radius 0.62, from a phone")
        box(x: 50, y: 354, w: 250, h: 96, title: "the inspector slider",
            sub: "dragged in the live host")

        // The parameter they all land on.
        box(x: 390, y: 212, w: 250, h: 96, title: "@Param(20...400)",
            sub: "var radius = 120.0", accented: true)
        noStroke()
        fill(soft)
        textSize(15)
        textAlign(.center, .top)
        drawText("mapped into the range, smoothed if asked", 515, 316)

        // The sketch reads one number.
        let dial = Vector2(772, 260)
        noFill()
        stroke(ink)
        strokeWeight(3)
        drawCircle(center: dial, radius: 52)
        strokeWeight(1.5)
        stroke(faint)
        drawCircle(center: dial, radius: 34)
        drawCircle(center: dial, radius: 18)
        noStroke()
        fill(ink)
        textSize(17)
        textAlign(.center, .top)
        drawText("the sketch reads", dial.x, 330)
        drawText("radius", dial.x, 352)

        // Arrows: sources to the param, param to the drawing.
        arrow(from: Vector2(300, 118), to: Vector2(388, 240))
        arrow(from: Vector2(300, 260), to: Vector2(388, 260))
        arrow(from: Vector2(300, 402), to: Vector2(388, 280))
        arrow(from: Vector2(640, 260), to: Vector2(716, 260))

        noStroke()
        fill(soft)
        textSize(19)
        textAlign(.center, .top)
        drawText("three hands on one knob: whichever moved most recently wins", width / 2, 495)
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
