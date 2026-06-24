import Ollin

/// The **stylize & optical** filter family: edge and relief passes (edges, sharpen,
/// emboss, normalMap), painterly abstractions (toon, oilPaint, crosshatch, median,
/// contour), and the print / screen looks (halftone, cmykHalftone, dither, pixelate,
/// lineScreen), plus the lens optics (vignette, chromatic). One scene, shown through
/// each, all resolved on the GPU.
///
/// See the sibling families: `Effects/ColorFilters`, `Effects/BlurFilters`,
/// `Effects/RetroFilters`, and `Effects/Distortion`.
@main
final class StylizeFilters_Example: Sketch {
    private let labelFont = OutlineFont.system

    private var tiles: [(String, Filter?)] {
        [
            ("edges", .edges(intensity: 2.5)),
            ("sharpen", .sharpen(amount: 2.5)),
            ("emboss", .emboss(amount: 2)),
            ("normalMap", .normalMap(strength: 2)),
            ("toon", .toon(levels: 5)),
            ("oilPaint", .oilPaint(radius: 5)),
            ("crosshatch", .crosshatch(scale: 95)),
            ("median", .median()),
            ("contour", .contour(levels: 12)),
            ("vignette", .vignette(amount: 0.85)),
            ("chromatic", .chromaticAberration(amount: 0.012)),
            ("halftone", .halftone(scale: 44)),
            ("cmykHalftone", .cmykHalftone(scale: 56)),
            ("dither", .dither(levels: 4, pixelSize: 6)),
            ("pixelate", .pixelate(size: 24)),
            ("lineScreen", .lineScreen(scale: 56, angle: .pi / 6)),
        ]
    }

    override func draw() {
        background(Color(white: 0.06))

        // A scene with color, smooth tone, and crisp edges, so the edge/relief and
        // painterly passes all have structure to work on.
        let scene = renderTarget()
        withTarget(scene) {
            background(Color(hex: 0x101826))
            noStroke()
            fill(.linear(from: Vector2(0, 0), to: Vector2(width, height),
                         Ramp([Color(hex: 0x1A2A6C), Color(hex: 0xB21F66), Color(hex: 0xFDBB2D)])))
            drawRect(0, 0, width, height)
            for i in 0 ..< 6 {
                let t = time * 0.25 + Double(i) * .tau / 6
                fill(Color(hue: Double(i) / 6, saturation: 0.8, brightness: 0.95))
                drawCircle(width * 0.5 + cos(t) * width * 0.28,
                           height * 0.5 + sin(t * 1.3) * height * 0.28, 165)
            }
            stroke(.white); strokeWeight(7); noFill()
            drawCircle(width * 0.5, height * 0.5, 150 + sin(time) * 30)
        }

        drawFilterSheet(self, scene, tiles, font: labelFont)
    }
}

/// Tile a family's filters into a near-square grid, labelled. (Each family example
/// carries its own copy so the file stays standalone.)
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
