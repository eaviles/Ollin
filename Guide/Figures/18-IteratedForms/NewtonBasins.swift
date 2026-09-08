// figure: frame=0 themed
//
// Guide figure (Chapter 18): Newton's basins. The three cube roots of one with
// their beaded borders, five roots with the step scaled by 1.3 so the basins
// spiral, and the cubic z^3 - 2z + 2 framed on its cycle at 0 and 1, two pools
// the method never brings to a root.
import Ollin
import OllinDiagram

final class NewtonBasins: Sketch {
    override var canvasSize: CanvasSize { .size(880, 386) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }

    override func draw() {
        background(paper)

        let tile = 268, gap = 12.0
        let left = (width - Double(tile) * 3 - gap * 2) / 2
        let five = (0 ..< 5).map { i -> Vector2 in
            let a = Double(i) / 5 * .tau + 0.3
            return Vector2(cos(a), sin(a))
        }
        let cycle = [Vector2(-1.7693, 0), Vector2(0.88465, 0.58974), Vector2(0.88465, -0.58974)]

        let panels: [(String, Generator)] = [
            ("z³ - 1: three roots, three basins", .newton(phase: 0.1)),
            ("five roots, the step at 1.3",
             .newton(roots: five, relaxation: 1.3, iterations: 80)),
            ("z³ - 2z + 2: two dark pools",
             .newton(roots: cycle, trapped: Color(hex: 0x14202B), shading: 0.8,
                     center: Vector2(0.5, 0), zoom: 2.2)),
        ]

        textFont(.system)
        for (index, panel) in panels.enumerated() {
            let x = left + Double(index) * (Double(tile) + gap)
            let rect = Rectangle(x: x, y: 20, width: Double(tile), height: Double(tile))
            drawImage(generate(panel.1, width: tile, height: tile).image, in: rect)

            noStroke()
            fill(ink.withAlpha(0.62))
            textSize(16)
            textAlign(.center, .top)
            drawText(panel.0, rect.x + rect.width / 2, rect.y + rect.height + 8)
        }
    }
}
