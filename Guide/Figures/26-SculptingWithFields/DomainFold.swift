// figure: frame=0 themed
//
// Guide contact sheet (Chapter 26): domain operators fold space, so one
// shape becomes many for free: a mirror, a tiling, and a radial fan of the
// same off-center cluster.
import Ollin
import OllinDiagram

final class DomainFold: Sketch {
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
        // One asymmetric cluster, used by all three panels.
        let cell = SDF.circle(radius: 30).colored(coral)
            .smoothUnion(SDF.rect(width: 52, height: 30, cornerRadius: 9)
                .colored(blue).at(34, 24), k: 16)

        // A petal for the mandala: symmetric across its wedge, so the fold is seamless.
        let petal = SDF.ellipse(radiusX: 42, radiusY: 20).colored(coral)
            .smoothUnion(SDF.circle(radius: 13).colored(blue).at(52, 0), k: 14)

        let tiles: [(String, SDF)] = [
            ("mirrored(x:)", cell.at(52, 0).mirrored(x: true)),
            ("repeated(spacing:count:)", cell.scaled(0.72).repeated(spacing: Vector2(88, 88), count: 1)),
            ("repeatedRadially(9)", petal.at(82, 0).repeatedRadially(count: 9)),
        ]

        for (i, tile) in tiles.enumerated() {
            let cx = 150.0 + Double(i) * 290
            withState {
                translate(cx, 250)
                drawSDF(tile.1)
            }
            fill(ink)
            textSize(22)
            textAlign(.center, .middle)
            drawText(tile.0, cx, 460)
        }
    }
}
