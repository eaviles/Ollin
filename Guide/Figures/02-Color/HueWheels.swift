// figure: frame=0 themed
//
// Guide diagram: two ways to describe one color. RGB stores three amounts of
// light; HSB picks a hue on the wheel, then how vivid and how bright.
import Ollin

final class HueWheels: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var label: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.55) }

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
            fill(Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.08))
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
            drawArc(center: center, rx: 130, ry: 130, start: a0, stop: a1, mode: .pie)
        }
        fill(paper)
        drawCircle(center: center, radius: 58)
        fill(label)
        textAlign(.center, .middle)
        drawText("hue", center.x, center.y)

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
