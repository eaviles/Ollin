// figure: frame=0 themed
//
// Guide contact sheet (Chapter 26): the combining verbs. The same circle and
// rounded rectangle under each operator; the smooth forms melt colors across
// the seam, morph blends the boundary itself.
import Ollin
import OllinDiagram

final class Verbs: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }

    override func draw() {
        background(paper)
        noStroke()

        let coral = Color(hex: 0xE4572E)
        let blue = Color(hex: 0x3A6EA5)
        let a = SDF.circle(radius: 58).colored(coral).at(x: -34, y: -8)
        let b = SDF.rect(width: 108, height: 68, cornerRadius: 16).colored(blue).at(x: 40, y: 14)

        let tiles: [(String, SDF)] = [
            ("union", a.union(b)),
            ("smoothUnion, k: 34", a.smoothUnion(b, k: 34)),
            ("morph, amount: 0.5", a.morph(b, amount: 0.5)),
            ("subtract", a.subtract(b)),
            ("smoothSubtract, k: 34", a.smoothSubtract(b, k: 34)),
            ("intersect", a.intersect(b)),
        ]

        for (i, tile) in tiles.enumerated() {
            let cx = 160.0 + Double(i % 3) * 280
            let cy = 140.0 + Double(i / 3) * 250
            withState {
                translate(cx, cy)
                drawSDF(tile.1)
            }
            fill(ink)
            textSize(24)
            textAlign(.center, .middle)
            drawText(tile.0, cx, cy + 118)
        }
    }
}
