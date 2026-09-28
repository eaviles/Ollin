// figure: frame=0 themed
//
// Guide diagram (Appendix B): the golden angle. Three panels place the same
// 500 seeds, seed i turned i times the angle and pushed out by the square
// root of i. The golden angle, about 137.5 degrees, fills the disk evenly.
// 137.0 degrees, half a degree less, sits close to 8/21 of a turn, so the
// seeds line up into curving spokes with gaps between them. Two fifths of a
// turn, 144 degrees, repeats every five seeds and makes five straight spokes.
import Ollin
import OllinDiagram

final class GoldenAngle: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    let count = 500
    let spacing = 5.8

    override func draw() {
        background(theme.paper)
        panel(center: Vector2(150, 225), angle: .goldenAngle, title: "137.5°, the golden angle", accent: true)
        panel(center: Vector2(440, 225), angle: .degrees(137.0), title: "137.0°", accent: false)
        panel(center: Vector2(730, 225), angle: .degrees(144.0), title: "144°, two fifths of a turn", accent: false)
        diagramCaption("only the golden angle never lines the seeds back up", at: 488, theme: theme)
    }

    func panel(center: Vector2, angle: Double, title: String, accent: Bool) {
        noStroke()
        fill(accent ? theme.accent : theme.ink(0.8))
        for p in phyllotaxis(count: count, spacing: spacing, angle: angle) {
            drawCircle(center: center + p, radius: 2.8)
        }

        fill(theme.ink)
        textSize(16)
        textAlign(.center, .top)
        drawText(title, center.x, center.y + spacing * Double(count).squareRoot() + 18)
    }
}
