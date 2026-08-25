import Ollin

/// The **retro / optical** filter family: the CRT-era looks — scanlines, the torn
/// `glitch`, the full `crt` (barrel + scanline + vignette + aberration), and `bloom`
/// glow. The glitch is animated by `seed`. Each tile is `scene.filtered(...)`
/// resolved on the GPU.
///
/// See the sibling families: `Effects/ColorFilters`, `Effects/BlurFilters`,
/// `Effects/StylizeFilters`, and `Effects/Distortion`.
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

        textFont(labelFont)
        drawSheet(tiles(time)) { filter, cell in
            drawImage((filter.map { scene.filtered($0) } ?? scene).image, in: cell)
        }
    }
}
