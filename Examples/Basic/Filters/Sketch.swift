import Ollin

/// The filter catalog as a contact sheet: one animated scene, drawn once into an
/// off-screen layer, then shown through fifteen GPU `Filter`s side by side. Each
/// tile is `scene.filtered(...)` composited with `drawImage`; the whole sheet is
/// recorded in a frame and resolved on the GPU, no layer ever read back to the CPU.
///
/// Try it: swap a tile's filter or its parameters, or change the scene. Filters
/// chain (`scene.filtered(.threshold()).filtered(.bloom())`), and `postProcess(_:)`
/// runs one over the whole finished frame.
@main
final class Filters_Example: Sketch {
    private let labelFont = OutlineFont.system

    // Name + filter for each tile (nil = the untouched scene).
    private var tiles: [(String, Filter?)] {
        [
            ("original", nil),
            ("colorGrade", .colorGrade(contrast: 1.3, saturation: 1.8, hue: 0.05)),
            ("invert", .invert()),
            ("posterize", .posterize(levels: 4)),
            ("threshold", .threshold(0.5, softness: 0.04)),
            ("sepia", .sepia()),
            ("duotone", .duotone(dark: Color(hex: 0x14233B), light: Color(hex: 0xFFD27D))),
            ("gradientMap", .gradientMap(.turbo)),
            ("edges", .edges(intensity: 2.5)),
            ("sharpen", .sharpen(amount: 2.5)),
            ("vignette", .vignette(amount: 0.85)),
            ("chromatic", .chromaticAberration(amount: 0.012)),
            ("halftone", .halftone(scale: 48)),
            ("dither", .dither(levels: 4, pixelSize: 6)),
            ("pixelate", .pixelate(size: 26)),
            ("lineScreen", .lineScreen(scale: 60, angle: .pi / 6)),
        ]
    }

    override func draw() {
        background(Color(white: 0.06))

        // The shared scene: vivid drifting blobs, a bright ring, and diagonal
        // strokes, giving color, a wide brightness range, and edges, so every
        // filter has something to bite on.
        let scene = renderTarget()
        withTarget(scene) {
            background(Color(hex: 0x101826))
            noStroke()
            // A smooth diagonal gradient backdrop: continuous tone the tonal filters
            // (dither, posterize, threshold, halftone) need something gradual to show.
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
            stroke(Color(white: 1, alpha: 0.5)); strokeWeight(3)
            for i in 0 ..< 9 {
                let x = width * Double(i) / 8
                drawLine(x, 0, x + width * 0.25, height)
            }
        }

        // Tile the sheet 4 across, square cells, a small gutter.
        let cols = 4, rows = 4
        let gutter = width * 0.012
        let cellW = (width - gutter * Double(cols + 1)) / Double(cols)
        let cellH = (height - gutter * Double(rows + 1)) / Double(rows)
        for (i, tile) in tiles.enumerated() {
            let r = i / cols, c = i % cols
            let x = gutter + Double(c) * (cellW + gutter)
            let y = gutter + Double(r) * (cellH + gutter)
            let rect = Rectangle(x: x, y: y, width: cellW, height: cellH)
            let layer = tile.1.map { scene.filtered($0) } ?? scene
            drawImage(layer.image, in: rect)

            // Label: a dark plate so it reads over any tile, then the name.
            withState {
                blendMode(.normal)
                fill(Color(white: 0, alpha: 0.55)); noStroke()
                drawRect(x, y + cellH - 30, cellW, 30)
                fill(.white)
                textFont(labelFont); textSize(17); textAlign(.left, .middle)
                drawText(tile.0, x + 9, y + cellH - 15)
            }
        }
    }
}
