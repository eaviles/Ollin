import Ollin

/// The **blur** filter family: the Gaussian, the edge-preserving bilateral, and the
/// two directional blurs (motion + radial), shown over one detailed scene so the
/// smoothing — and what each preserves — reads clearly. Each tile is
/// `scene.filtered(...)` resolved on the GPU.
///
/// See the sibling families: `Basic/ColorFilters`, `Basic/StylizeFilters`,
/// `Basic/RetroFilters`, and `Basic/Distortion`.
@main
final class BlurFilters_Example: Sketch {
    private let labelFont = OutlineFont.system

    private var tiles: [(String, Filter?)] {
        [
            ("gaussianBlur", .gaussianBlur(radius: 9)),
            ("bilateral", .bilateral(radius: 6, sigma: 0.18)),
            ("motionBlur", .motionBlur(angle: 0.4, distance: 0.06)),
            ("radialBlur", .radialBlur(amount: 0.14)),
        ]
    }

    override func draw() {
        background(Color(white: 0.06))

        // A scene with both flat color regions and fine high-frequency detail (thin
        // rings, small dots), so a plain blur and an edge-preserving one read apart.
        let scene = renderTarget()
        withTarget(scene) {
            background(Color(hex: 0x12202E))
            noStroke()
            fill(Color(hex: 0xFF6B6B)); drawCircle(width * 0.36, height * 0.40, 170)
            fill(Color(hex: 0x4ECDC4)); drawRect(width * 0.52, height * 0.50, width * 0.34, height * 0.32)
            stroke(Color(white: 1, alpha: 0.7)); noFill()
            for i in 1 ... 10 { strokeWeight(2); drawCircle(width * 0.5, height * 0.5, Double(i) * 42) }
            noStroke(); fill(.white)
            for i in 0 ..< 80 {
                let a = Double(i) * .tau / 80
                drawCircle(width * 0.5 + cos(a) * width * 0.44,
                           height * 0.5 + sin(a) * height * 0.44, 5)
            }
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
