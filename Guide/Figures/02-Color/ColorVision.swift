// figure: frame=1 themed
//
// Guide figure: a photograph and the same six colors twice, seen four ways. The
// picture is the bundled weave, where red sits beside green oftener than in any
// other bundled photograph, so the two commonest kinds flatten it to one band.
// The middle block is a familiar chart set, whose orange and green arrive on one
// olive for those same two kinds. The bottom block is the published safe set,
// which holds apart. A bar under a swatch marks a pair the check found.
import Ollin
import OllinDiagram
import OllinSamplePhotos

final class ColorVision2: Sketch {
    override var canvasSize: CanvasSize { .size(1200, 925) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    let chart = Palette([
        Color(hex: 0x1F77B4), Color(hex: 0xFF7F0E), Color(hex: 0x2CA02C),
        Color(hex: 0xD62728), Color(hex: 0x9467BD), Color(hex: 0x8C564B),
    ])

    private var photograph = Image(width: 1, height: 1)

    override func setup() {
        photograph = SamplePhoto.textiles.load().resized(width: 450, height: 450)
    }

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

        // One layer carries the picture and every column filters that same
        // layer, so a cell differs from its neighbor by nothing but the kind of
        // vision put over it.
        let plate = makeRenderTarget(width: 450, height: 450)
        withTarget(plate) { drawImage(photograph, 0, 0, 450, 450) }

        for (column, view) in views.enumerated() {
            let x = 60.0 + Double(column) * 285
            fill(theme.ink)
            textSize(21)
            drawText(view.0, at: Vector2(x, 52))

            drawImage(plate.filtered(.colorVision(view.1)).image, x, 92, 225, 225)
            strip(chart, vision: view.1, x: x, y: 387, height: 210)
            strip(.colorblindSafe, vision: view.1, x: x, y: 667, height: 210)
        }

        fill(theme.muted)
        textSize(18)
        drawText("a photograph: red beside green", at: Vector2(60, 82))
        drawText("a familiar chart set", at: Vector2(60, 377))
        drawText("Palette.colorblindSafe", at: Vector2(60, 657))
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
