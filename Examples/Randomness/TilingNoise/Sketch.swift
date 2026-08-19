import Ollin

/// Noise that tiles: `tilingNoise` and `tilingFbm` close on themselves in both
/// directions, so a picture drawn from them repeats with no seam.
///
/// Both panels here are one 256-pixel tile laid down nine times. The left tile
/// comes from ordinary `fbm(u * 6, v * 6)`, whose left edge and right edge are
/// unrelated, so every join draws a line. The right tile comes from
/// `tilingFbm(u, v, detail: 6)` and the nine copies read as one field.
///
/// `detail` is the frequency you would otherwise multiply into the coordinates,
/// so moving a map across is a direct swap and the grain survives it. Any
/// picture that will be repeated wants this, and a projected one always
/// repeats: `triplanarTextured(_:)` carries its picture across the whole
/// surface. A mismatched normal map is the loud case, because the two sides of
/// the join then light differently.
@main
final class TilingNoise: Sketch {

    let side = 150.0
    var plain = Image(width: 1, height: 1, premultipliedRGBA: [0, 0, 0, 255])!
    var tiled = Image(width: 1, height: 1, premultipliedRGBA: [0, 0, 0, 255])!

    /// A grayscale picture from a function of the tile's own coordinates.
    func picture(size: Int, _ shade: (Double, Double) -> Double) -> Image {
        var bytes = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0 ..< size {
            for x in 0 ..< size {
                let u = (Double(x) + 0.5) / Double(size), v = (Double(y) + 0.5) / Double(size)
                let g = UInt8((min(max(shade(u, v), 0), 1) * 255).rounded())
                let i = (y * size + x) * 4
                bytes[i] = g; bytes[i + 1] = g; bytes[i + 2] = g
            }
        }
        return Image(width: size, height: size, premultipliedRGBA: bytes)!
    }

    override func setup() {
        noiseSeed(3)
        noLoop()
        plain = picture(size: 256) { u, v in self.fbm(u * 6, v * 6, octaves: 5) }
        tiled = picture(size: 256) { u, v in self.tilingFbm(u, v, detail: 6, octaves: 5) }
    }

    override func draw() {
        background(Color(hex: 0x121316))
        textSize(26)
        fill(.white)
        textAlign(.center)

        panel(plain, at: 50, label: "fbm(u * 6, v * 6)")
        panel(tiled, at: 580, label: "tilingFbm(u, v, detail: 6)")
    }

    /// One tile laid down nine times, with its name under it.
    func panel(_ tile: Image, at x: Double, label: String) {
        for row in 0 ..< 3 {
            for column in 0 ..< 3 {
                drawImage(tile, x + Double(column) * side, 300 + Double(row) * side, side, side)
            }
        }
        drawText(label, x + side * 1.5, 800)
    }
}
