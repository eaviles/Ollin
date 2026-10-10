// figure: frame=0 themed
//
// Guide diagram: shades of five base colors, six swatches each, built twice.
// On the left the hue stays put and only lightness moves; on the right the
// hue drifts, warmer toward yellow in the light and cooler in the shadow. The
// base color sits in each row at the place its own lightness gives it, ringed.
import Ollin
import OllinDiagram

final class ShadesThatDrift: Sketch {
    override var canvasSize: CanvasSize { .size(880, 520) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    let bases = [Color(hex: 0xC0392B), Color(hex: 0x27AE60), Color(hex: 0x2E5AAC),
                 Color(hex: 0x8E44AD), Color(hex: 0xC8875E)]

    override func draw() {
        background(theme.paper)
        textSize(19)
        textAlign(.left, .middle)
        noStroke()
        fill(theme.ink(0.72))
        drawText("hueDrift: 0", 60, 48)
        drawText("hueDrift: 1.0 / 12", 470, 48)

        let swatch = 58.0, gap = 4.0, rowGap = 84.0
        for (row, base) in bases.enumerated() {
            let y = 82 + Double(row) * rowGap
            for (column, drift) in [0.0, 1.0 / 12].enumerated() {
                let shades = Palette.shades(of: base, count: 6, hueDrift: drift)
                let x0 = 60 + Double(column) * 410
                for (i, color) in shades.enumerated() {
                    let x = x0 + Double(i) * (swatch + gap)
                    noStroke()
                    fill(color)
                    drawRect(x, y, swatch, swatch)
                    if color == base {
                        noFill()
                        stroke(theme.ink(0.85))
                        strokeWeight(2.5)
                        drawRect(x - 5, y - 5, swatch + 10, swatch + 10)
                    }
                }
            }
        }
    }
}
