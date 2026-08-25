// figure: frame=1 themed
//
// Guide figure: the same six colors twice, seen four ways. The top block is a
// familiar chart set, whose orange and green arrive on one olive for the two
// commonest kinds. The bottom block is the published safe set, which holds
// apart. A bar under a swatch marks a pair the check found.
import Ollin
import OllinDiagram

final class ColorVision2: Sketch {
    override var canvasSize: CanvasSize { .size(1200, 620) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    let chart = Palette([
        Color(hex: 0x1F77B4), Color(hex: 0xFF7F0E), Color(hex: 0x2CA02C),
        Color(hex: 0xD62728), Color(hex: 0x9467BD), Color(hex: 0x8C564B),
    ])

    let views: [(String, Ollin.ColorVision)] = [
        ("as most people see it", .normal),
        ("protanopia", .protanopia),
        ("deuteranopia", .deuteranopia),
        ("tritanopia", .tritanopia),
    ]

    override func draw() {
        background(theme.paper)
        noStroke()
        textFont(.systemMedium)

        for (column, view) in views.enumerated() {
            let x = 60.0 + Double(column) * 285
            fill(theme.ink)
            textSize(21)
            drawText(view.0, at: Vector2(x, 52))

            strip(chart, vision: view.1, x: x, y: 92, height: 210)
            strip(.colorblindSafe, vision: view.1, x: x, y: 372, height: 210)
        }

        fill(theme.muted)
        textSize(18)
        drawText("a familiar chart set", at: Vector2(60, 82))
        drawText("Palette.colorblindSafe", at: Vector2(60, 362))
    }

    private func strip(_ palette: Palette, vision: Ollin.ColorVision, x: Double, y: Double,
                       height: Double) {
        let confused = Set(palette.confusions(under: vision).flatMap { [$0.first, $0.second] })
        let size = height / Double(palette.count) - 6

        for (i, color) in palette.colors.enumerated() {
            let top = y + Double(i) * (size + 6)
            fill(color.simulated(vision))
            drawRect(x, top, 225, size)

            if confused.contains(i) {
                fill(theme.ink)
                drawRect(x, top + size + 1, 225, 3)
            }
        }
    }
}
