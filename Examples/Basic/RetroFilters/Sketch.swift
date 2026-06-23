import Ollin

/// The **retro / optical** filter family: the CRT-era looks — scanlines, the torn
/// `glitch`, the full `crt` (barrel + scanline + vignette + aberration), and `bloom`
/// glow. The glitch is animated by `seed`. Each tile is `scene.filtered(...)`
/// resolved on the GPU.
///
/// See the sibling families: `Basic/ColorFilters`, `Basic/BlurFilters`,
/// `Basic/StylizeFilters`, and `Basic/Distortion`.
@main
final class RetroFilters_Example: Sketch {
    private let labelFont = OutlineFont.system

    private func tiles(_ t: Double) -> [(String, Filter?)] {
        [
            ("scanlines", .scanlines(count: 120, intensity: 0.45)),
            ("glitch", .glitch(amount: 0.32, seed: t * 8)),
            ("crt", .crt(curvature: 0.18, scanline: 0.35)),
            ("bloom", .bloom(threshold: 0.5, intensity: 1.6, radius: 22)),
        ]
    }

    override func draw() {
        background(.black)

        // A bright, high-contrast scene — a glowing ring, vivid bars, bold text —
        // the kind of thing a CRT and a bloom flatter.
        let scene = renderTarget()
        withTarget(scene) {
            background(Color(hex: 0x05080F))
            noStroke()
            for i in 0 ..< 6 {
                fill(Color(hue: Double(i) / 6, saturation: 0.9, brightness: 1.0))
                drawRect(width * Double(i) / 6, height * 0.66, width / 6, height * 0.34)
            }
            stroke(Color(hex: 0x66FFE0)); strokeWeight(10); noFill()
            drawCircle(width * 0.5, height * 0.38, 170 + sin(time) * 24)
            fill(.white); noStroke()
            textFont(labelFont); textSize(120); textAlign(.center, .middle)
            drawText("OLLIN", width * 0.5, height * 0.38)
        }

        drawFilterSheet(self, scene, tiles(time), font: labelFont)
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
