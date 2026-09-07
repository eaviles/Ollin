// figure: frame=0 themed
//
// Guide diagram: three Gabor noise fields at one wavelength, drawn by the
// generator. Left: every direction at once. Middle: one direction, the spread
// at zero. Right: a narrow band, the waves running long and interfering.
import Ollin
import OllinDiagram

final class NoiseWithADirection: Sketch {
    override var canvasSize: CanvasSize { .size(880, 330) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }

    override func setup() {
        noStroke()
    }

    override func draw() {
        background(paper)
        textSize(19)

        let size = 190
        let lefts = [85.0, 345.0, 605.0]
        let top = 58.0
        let fields: [(String, Generator)] = [
            ("gaborNoise(x, y)",
             .gaborNoise(wavelength: 14, seed: 6, foreground: ink, background: paper)),
            ("spread: 0",
             .gaborNoise(wavelength: 14, angle: .pi / 4, spread: 0, seed: 6,
                         foreground: ink, background: paper)),
            ("bandwidth: 0.2",
             .gaborNoise(wavelength: 14, bandwidth: 0.2, angle: 0, spread: 0.3, seed: 6,
                         foreground: ink, background: paper)),
        ]
        for (i, (label, field)) in fields.enumerated() {
            drawImage(generate(field, width: size, height: size).image, lefts[i], top)
            fill(ink)
            textAlign(.center, .top)
            drawText(label, lefts[i] + Double(size) / 2, top + Double(size) + 12)
        }
    }
}
