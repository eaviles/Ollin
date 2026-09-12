// figure: frame=0 themed
//
// Guide diagram: two ways to describe one color. RGB stores three amounts of
// light; HSB picks a hue on the wheel, then how vivid and how bright.
import Ollin
import OllinDiagram

final class HueWheels: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var label: Color { theme.ink(0.72) }

    override func draw() {
        background(paper)
        noStroke()
        textSize(21)

        // Left: RGB as three amounts of light, and the color they add up to.
        let amounts: [(Color, Double, String)] = [
            (.red, 0.95, "red   0.95"),
            (.green, 0.45, "green 0.45"),
            (.blue, 0.25, "blue  0.25"),
        ]
        for (i, bar) in amounts.enumerated() {
            let y = 120.0 + Double(i) * 64
            fill(theme.ink(0.08))
            drawRect(70, y, 240, 36)
            fill(bar.0)
            drawRect(70, y, 240 * bar.1, 36)
            fill(label)
            textAlign(.left, .middle)
            drawText(bar.2, 322, y + 18)
        }
        fill(Color(red: 0.95, green: 0.45, blue: 0.25))
        drawRect(70, 330, 240, 70)
        fill(label)
        textAlign(.left, .middle)
        drawText("all three together", 322, 365)
        textAlign(.center, .top)
        fill(ink)
        textSize(23)
        drawText("RGB: three amounts of light", 190, 470)

        // Right: the HSB hue wheel, plus saturation and brightness sweeps.
        let center = Vector2(650, 210)
        let wedges = 36
        textSize(21)
        for i in 0..<wedges {
            let a0 = Double(i) / Double(wedges) * .tau
            let a1 = Double(i + 1) / Double(wedges) * .tau + 0.004
            fill(Color(hue: Double(i) / Double(wedges), saturation: 0.85, brightness: 0.95))
            drawArc(center: center, radiusX: 130, radiusY: 130, start: a0, stop: a1, mode: .pie)
        }
        fill(paper)
        drawCircle(center: center, radius: 58)
        fill(label)
        textAlign(.center, .middle)
        drawText("hue", center.x, center.y)

        // Where the wheel starts, and which way it turns. Hue 0 sits at the
        // right because angle zero points right, and the numbers climb
        // clockwise because y grows downward on this canvas.
        withState {
            stroke(ink)
            strokeWeight(2)
            drawLine(center + Vector2(134, 0), center + Vector2(144, 0))
            noStroke()
            fill(ink)
            drawCircle(center: center + Vector2(94, 0), radius: 5)
            textSize(15)
            textAlign(.right, .middle)
            drawText("hue 0 = red", width - 8, center.y)

            // The sweep from 0 to 1, drawn as the quarter it opens with.
            noFill()
            stroke(theme.accent)
            strokeWeight(2.5)
            drawArc(center.x, center.y, 158, 158, start: -.tau * 0.20, stop: -.tau * 0.055)
            fill(theme.accent)
            let head = center + Vector2(angle: -.tau * 0.045, length: 158)
            drawArrow(from: center + Vector2(angle: -.tau * 0.075, length: 158),
                      to: head, headLength: 16, headWidth: 13)
            textSize(18)
            textAlign(.center, .bottom)
            drawText("0 to 1 runs clockwise", center.x + 4, center.y - 176)
        }

        for i in 0..<9 {
            let t = Double(i) / 8
            fill(Color(hue: 0.07, saturation: t, brightness: 0.95))
            drawRect(510 + Double(i) * 31, 380, 29, 34)
            fill(Color(hue: 0.07, saturation: 0.85, brightness: t))
            drawRect(510 + Double(i) * 31, 424, 29, 34)
        }
        fill(label)
        textAlign(.right, .middle)
        drawText("saturation", 498, 397)
        drawText("brightness", 498, 441)
        fill(ink)
        textSize(23)
        textAlign(.center, .top)
        drawText("HSB: a wheel, then two dials", 650, 470)
    }
}
