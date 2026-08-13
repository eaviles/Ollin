import Ollin

/// Two palettes seen four ways: as most people see them, and as the three kinds
/// of color vision see them. The top row is a familiar six-color chart set. The
/// bottom row is `Palette.colorblindSafe`, the published set chosen to hold
/// apart under all three.
///
/// Watch the top row's orange and green arrive on top of each other in the
/// second column. `confusions(under:)` finds that pair for you, and the swatch
/// is marked where it happens.
///
/// The `preview` knob puts `Filter.colorVision` over the whole canvas instead,
/// which is how you check a finished piece rather than a palette.
@main
final class ColorVisionSketch: Sketch {

    /// Put the whole sketch through one kind, the way you would check a piece.
    @Param(icon: "eye") var preview = false
    @Param(icon: "eyedropper") var previewKind = ColorVision.Kind.deuteranomaly

    let chart = Palette([
        Color(hex: 0x1F77B4), Color(hex: 0xFF7F0E), Color(hex: 0x2CA02C),
        Color(hex: 0xD62728), Color(hex: 0x9467BD), Color(hex: 0x8C564B),
    ])

    let views: [(name: String, vision: ColorVision)] = [
        ("average", .normal),
        ("protanopia", .protanopia),
        ("deuteranopia", .deuteranopia),
        ("tritanopia", .tritanopia),
    ]

    override func setup() {
        noLoop()
        textFont(.systemMedium)
    }

    override func draw() {
        background(Color(white: 0.97))
        noStroke()

        label("a familiar chart set", at: Vector2(60, 118))
        label("the published safe set", at: Vector2(60, 578))

        for (column, view) in views.enumerated() {
            let x = 60.0 + Double(column) * 250
            label(view.name, at: Vector2(x, 68))
            row(chart, vision: view.vision, x: x, y: 140, height: 340)
            row(.colorblindSafe, vision: view.vision, x: x, y: 600, height: 420)
        }

        if preview {
            postProcess(.colorVision(ColorVision(previewKind)))
        }
    }

    /// One palette as one kind of vision sees it, a swatch per color, with a bar
    /// under any swatch that has landed on another one.
    private func row(_ palette: Palette, vision: ColorVision, x: Double, y: Double,
                     height: Double) {
        let confused = Set(palette.confusions(under: vision).flatMap { [$0.first, $0.second] })
        let size = height / Double(palette.count) - 8

        for (i, color) in palette.colors.enumerated() {
            let top = y + Double(i) * (size + 8)
            fill(color.simulated(vision))
            drawRect(x, top, 190, size)

            if confused.contains(i) {
                fill(Color(white: 0.15))
                drawRect(x, top + size + 1, 190, 4)
            }
        }
    }

    private func label(_ text: String, at position: Vector2) {
        fill(Color(white: 0.25))
        textSize(20)
        drawText(text, at: position)
    }
}
