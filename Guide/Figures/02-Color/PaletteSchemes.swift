// figure: frame=0 probe themed
//
// Guide diagram (Chapter 2): the five palette schemes built around one key
// hue, six colors each, under the hue's most vivid color. Monochrome keeps
// the one hue from deep to light with the vivid point first; vivid and dark
// splits a wheel into a vivid near half and a dark far half; the vivid wheel
// takes every hue at its typical lightness; pastel and dark gather close
// around the key.
import Ollin
import OllinDiagram

final class PaletteSchemes: Sketch {
    override var canvasSize: CanvasSize { .size(880, 560) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var label: Color { theme.ink(0.72) }

    override func draw() {
        background(paper)
        noStroke()
        textSize(20)
        textAlign(.left, .middle)

        let key = Color.mostVivid(hue: 0.07)
        let left = 70.0, gap = 8.0
        let swatch = (740.0 - 5 * gap) / 6

        caption("Color.mostVivid(hue: 0.07)", 40)
        fill(key)
        drawRect(left, 62, swatch, 40, cornerRadius: 4)

        let schemes: [(String, Palette.Scheme)] = [
            (".monochrome", .monochrome), (".vividAndDark", .vividAndDark), (".vivid", .vivid),
            (".pastel", .pastel), (".dark", .dark),
        ]
        for (row, (name, scheme)) in schemes.enumerated() {
            let y = 140 + Double(row) * 84
            caption("Palette.scheme(\(name), key: key, count: 6)", y)
            let palette = Palette.scheme(scheme, key: key, count: 6)
            for i in 0 ..< palette.count {
                fill(palette[i])
                drawRect(left + Double(i) * (swatch + gap), y + 22, swatch, 40, cornerRadius: 4)
            }
        }

        func caption(_ text: String, _ y: Double) {
            fill(label)
            drawText(text, left, y)
        }
    }
}
