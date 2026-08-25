import Ollin

/// The **blur** filter family: the Gaussian, the edge-preserving bilateral, and the
/// two directional blurs (motion + radial), shown over one detailed scene so the
/// smoothing — and what each preserves — reads clearly. Each tile is
/// `scene.filtered(...)` resolved on the GPU.
///
/// See the sibling families: `Effects/ColorFilters`, `Effects/StylizeFilters`,
/// `Effects/RetroFilters`, and `Effects/Distortion`.
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

        textFont(labelFont)
        drawSheet(tiles) { filter, cell in
            drawImage((filter.map { scene.filtered($0) } ?? scene).image, in: cell)
        }
    }
}
