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

        drawFilterSheet(self, scene, tiles, font: labelFont)
    }
}

/// Tile a family's filters into a near-square grid, labeled. Shared shape for the
/// color / blur / stylize / retro family sheets (each example carries its own copy,
/// so the file stays standalone — examples are meant to be read and copied).
@MainActor
func drawFilterSheet(_ s: Sketch, _ scene: RenderTarget,
                     _ tiles: [(String, Filter?)], font: OutlineFont) {
    let cols = Int(Double(tiles.count).squareRoot().rounded(.up))
    let rows = (tiles.count + cols - 1) / cols
    let gutter = s.width * 0.01
    let cellW = (s.width - gutter * Double(cols + 1)) / Double(cols)
    let cellH = (s.height - gutter * Double(rows + 1)) / Double(rows)
    let labelSize = cols >= 4 ? 13.0 : 17.0
    let plate = cols >= 4 ? 22.0 : 30.0
    for (i, tile) in tiles.enumerated() {
        let r = i / cols, c = i % cols
        let x = gutter + Double(c) * (cellW + gutter)
        let y = gutter + Double(r) * (cellH + gutter)
        let layer = tile.1.map { scene.filtered($0) } ?? scene
        s.drawImage(layer.image, in: Rectangle(x: x, y: y, width: cellW, height: cellH))
        s.withState {
            s.blendMode(.normal)
            s.fill(Color(white: 0, alpha: 0.55)); s.noStroke()
            s.drawRect(x, y + cellH - plate, cellW, plate)
            s.fill(.white)
            s.textFont(font); s.textSize(labelSize); s.textAlign(.left, .middle)
            s.drawText(tile.0, x + 8, y + cellH - plate / 2)
        }
    }
}
