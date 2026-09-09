import Ollin
import OllinSamplePhotos

/// A photograph and two palettes seen four ways: as most people see them, and
/// as the three kinds of color vision see them.
///
/// The picture is one of the bundled sample photographs, woven blankets hung
/// side by side. It is here because red sits beside green in it more often than
/// in any other picture Ollin ships, and that is the pair the two commonest
/// kinds cannot hold apart: the reds and greens of the weave arrive as one
/// muddy band in the second and third columns while the blues survive.
///
/// Under it, the same four columns over two palettes. The first is a familiar
/// six-color chart set. The second is `Palette.colorblindSafe`, the published
/// set chosen to hold apart under all three. Watch the chart's orange and green
/// arrive on top of each other in the second column. `confusions(under:)` finds
/// that pair for you, and the swatch is marked where it happens.
///
/// A palette is checked color by color with `Color.simulated(_:)`; a picture is
/// checked by putting the whole layer through `Filter.colorVision`, which is
/// what each cell of the top row does. The `preview` parameter runs that filter
/// over the finished canvas instead, which is how you check a piece rather than
/// a palette. It draws every column in its true colors first, so the one filter
/// over the top is the only thing simulating anything: a sheet of color, seen
/// the way the whole piece would be seen.
@main
final class ColorVisionSketch: Sketch {
    override var canvasSize: CanvasSize { .size(1080, 1330) }

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

    /// The width of a column, and so of a swatch and of a picture cell.
    private let cell = 190.0

    private var photograph = Image(width: 1, height: 1)

    override func setup() {
        noLoop()
        textFont(.systemMedium)
        // Twice the size it is drawn at, so the weave still reads once the
        // filter has run over it.
        photograph = SamplePhoto.textiles.load().resized(width: 380, height: 380)
    }

    override func draw() {
        background(Color(white: 0.97))
        noStroke()

        // One layer holds the picture, and each column filters that same layer,
        // so every cell differs only by the kind of vision applied to it.
        let plate = makeRenderTarget(width: 380, height: 380)
        withTarget(plate) { drawImage(photograph, 0, 0, 380, 380) }

        label("a photograph: red beside green", at: Vector2(60, 118))
        label("a familiar chart set", at: Vector2(60, 400))
        label("the published safe set", at: Vector2(60, 822))

        // Checking a piece and comparing the kinds are two different pictures.
        // Under `preview` every column keeps its true colors, so the filter laid
        // over the finished canvas is the only thing that has simulated
        // anything, and the column names would be false.
        if preview { label("the whole canvas under \(previewKind.rawValue), drawn in true colors first", at: Vector2(60, 68)) }

        for (column, view) in views.enumerated() {
            let x = 60.0 + Double(column) * 250
            let vision = preview ? ColorVision.normal : view.vision
            if !preview { label(view.name, at: Vector2(x, 68)) }
            drawImage(plate.filtered(.colorVision(vision)).image, x, 140, cell, cell)
            row(chart, vision: vision, x: x, y: 422, height: 340)
            row(.colorblindSafe, vision: vision, x: x, y: 844, height: 420)
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
            drawRect(x, top, cell, size)

            if confused.contains(i) {
                fill(Color(white: 0.15))
                drawRect(x, top + size + 1, cell, 4)
            }
        }
    }

    private func label(_ text: String, at position: Vector2) {
        fill(Color(white: 0.25))
        textSize(20)
        drawText(text, at: position)
    }
}
