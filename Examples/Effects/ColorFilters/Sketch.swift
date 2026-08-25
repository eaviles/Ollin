import Ollin

/// The **color & tone** filter family as a contact sheet: one animated scene drawn
/// once into an off-screen layer, then shown through each grade and tone `Filter`
/// side by side. Every tile is `scene.filtered(...)` composited with `drawImage`,
/// all resolved on the GPU.
///
/// See the sibling families: `Effects/BlurFilters`, `Effects/StylizeFilters`,
/// `Effects/RetroFilters`, and `Effects/Distortion`.
@main
final class ColorFilters_Example: Sketch {
    private let labelFont = OutlineFont.system

    private var tiles: [(String, Filter?)] {
        [
            ("original", nil),
            ("colorGrade", .colorGrade(contrast: 1.3, saturation: 1.8, hue: 0.05)),
            ("levels", .levels(blackPoint: 0.08, whitePoint: 0.92, gamma: 1.4)),
            ("exposure", .exposure(stops: 0.9)),
            ("temperature +", .temperature(amount: 0.7)),
            ("temperature −", .temperature(amount: -0.7)),
            ("vibrance", .vibrance(amount: 0.9)),
            ("solarize", .solarize(0.5)),
            ("invert", .invert()),
            ("posterize", .posterize(levels: 4)),
            ("threshold", .threshold(0.5, softness: 0.04)),
            ("sepia", .sepia()),
            ("duotone", .duotone(dark: Color(hex: 0x14233B), light: Color(hex: 0xFFD27D))),
            ("gradientMap", .gradientMap(.turbo)),
            ("colorama", .colorama(cycles: 3)),
            ("lumaKey", .lumaKey(low: 0.35)),
        ]
    }

    override func draw() {
        background(Color(white: 0.06))

        // A vivid scene with a wide brightness range, so every grade has color and
        // tone to bite on.
        let scene = renderTarget()
        withTarget(scene) {
            background(Color(hex: 0x101826))
            noStroke()
            fill(.linear(from: Vector2(0, 0), to: Vector2(width, height),
                         Ramp([Color(hex: 0x1A2A6C), Color(hex: 0xB21F66), Color(hex: 0xFDBB2D)])))
            drawRect(0, 0, width, height)
            for i in 0 ..< 7 {
                let t = time * 0.25 + Double(i) * .tau / 7
                let x = width * 0.5 + cos(t) * width * 0.30
                let y = height * 0.5 + sin(t * 1.3) * height * 0.30
                fill(Color(hue: Double(i) / 7, saturation: 0.75, brightness: 0.9))
                drawCircle(x, y, 190)
            }
            stroke(.white); strokeWeight(6); noFill()
            drawCircle(width * 0.5, height * 0.5, 150 + sin(time) * 30)
        }

        textFont(labelFont)
        drawSheet(tiles) { filter, cell in
            drawImage((filter.map { scene.filtered($0) } ?? scene).image, in: cell)
        }
    }
}
