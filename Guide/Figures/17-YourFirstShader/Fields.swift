// figure: frame=0 themed
//
// Guide figure (Chapter 17): all six pattern fields, the built-in generators
// that are pure closed-form per-pixel math with no state, no source picture, and
// no texture reads. Each is drawn at one fixed phase, since a still has to stand
// in for something that normally moves.
import Ollin
import OllinDiagram

final class Fields: Sketch {
    override var canvasSize: CanvasSize { .size(880, 648) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }

    override func draw() {
        background(paper)

        let tile = 268, gap = 12.0
        let left = (width - Double(tile) * 3 - gap * 2) / 2

        let fields: [(String, Generator)] = [
            (".quasicrystal", .quasicrystal(phase: 2.0)),
            (".moire", .moire(phase: 1.4)),
            (".gyroid", .gyroid(phase: 1.2)),
            (".phyllotaxis", .phyllotaxis(phase: 0.8)),
            (".hexPulse", .hexPulse(phase: 2.6)),
            (".chladni", .chladni(m: 5, n: 3, phase: 1.0)),
        ]

        textFont(.system)
        for (index, field) in fields.enumerated() {
            let x = left + Double(index % 3) * (Double(tile) + gap)
            let y = 22 + Double(index / 3) * (Double(tile) + 44)
            drawImage(generate(field.1, width: tile, height: tile).image,
                      in: Rectangle(x: x, y: y, width: Double(tile), height: Double(tile)))
            noStroke()
            fill(ink.withAlpha(0.62))
            textSize(17)
            textAlign(.center, .top)
            drawText(field.0, x + Double(tile) / 2, y + Double(tile) + 8)
        }
    }
}
