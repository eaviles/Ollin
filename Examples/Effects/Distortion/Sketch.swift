import Ollin

/// The distortion filters — uv warps that re-sample the image at a remapped
/// coordinate — shown as a live 3×3 contact sheet. One scene is drawn into an
/// off-screen layer, then each tile applies a different geometric `Filter`, animated
/// so the warp reads in motion: the swirl winds, the wave and ripple travel, the
/// kaleidoscope and polar tunnel turn, the bulge breathes.
///
/// Try it: change a tile's parameters, or chain a color filter after the warp
/// (`scene.filtered(.swirl(...)).filtered(.colorama())`).
@main
final class Distortion_Example: Sketch {
    private let labelFont = OutlineFont.system

    private func tiles(_ t: Double) -> [(String, Filter)] {
        [
            ("kaleidoscope", .kaleidoscope(segments: 6, angle: t * 0.3)),
            ("swirl", .swirl(angle: 3 * sin(t * 0.6), radius: 0.6)),
            ("bulge", .bulge(amount: 0.6 * sin(t), radius: 0.5)),
            ("wave", .wave(amplitude: 0.03, frequency: 7, phase: t * 2)),
            ("ripple", .ripple(amplitude: 0.025, frequency: 14, phase: t * 3,
                               center: Vector2(0.5 + 0.22 * cos(t * 0.4),
                                               0.5 + 0.22 * sin(t * 0.4)))),
            ("mirror", .mirror(vertical: false)),
            ("polar", .polar(amount: 1)),
            ("tile", .tile(count: 3, mirror: true)),
            ("perturb", .perturb(amount: 0.04, scale: 5, phase: t)),
        ]
    }

    override func draw() {
        background(Color(white: 0.06))

        // A bold, legible scene — a few flat shapes and a grid — so each warp's
        // geometry is easy to read.
        let scene = makeRenderTarget()
        withTarget(scene) {
            background(Color(hex: 0x0E1B2A))
            noStroke()
            fill(Color(hex: 0xFF5252)); drawCircle(width * 0.34, height * 0.40, 150)
            fill(Color(hex: 0x40C4FF)); drawRect(width * 0.50, height * 0.50, width * 0.34, height * 0.34)
            fill(Color(hex: 0xFFD740)); drawTriangle(width * 0.30, height * 0.78,
                                                     width * 0.16, height * 0.55,
                                                     width * 0.46, height * 0.55)
            stroke(Color(white: 1, alpha: 0.35)); strokeWeight(3); noFill()
            for i in 1 ..< 8 {
                let g = width * Double(i) / 8
                drawLine(g, 0, g, height); drawLine(0, g, width, g)
            }
        }

        let cols = 3, rows = 3
        let gutter = width * 0.012
        let cellW = (width - gutter * Double(cols + 1)) / Double(cols)
        let cellH = (height - gutter * Double(rows + 1)) / Double(rows)
        for (i, tile) in tiles(time).enumerated() {
            let r = i / cols, c = i % cols
            let x = gutter + Double(c) * (cellW + gutter)
            let y = gutter + Double(r) * (cellH + gutter)
            drawImage(scene.filtered(tile.1).image,
                      in: Rectangle(x: x, y: y, width: cellW, height: cellH))
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
