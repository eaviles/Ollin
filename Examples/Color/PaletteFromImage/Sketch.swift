import Ollin

/// Pulling a palette out of a picture. `extractPalette(from:)` clusters an
/// image's pixels in a perceptual space and hands back the colors it is mostly
/// made of, most-used first.
///
/// The image here is painted in `setup()` rather than loaded, so the sketch
/// carries no asset. The interesting part is that we know the answer in
/// advance: the painting uses five source colors, and the extraction has to
/// find them again from the pixels alone. The wide row is what it found and
/// the thin strip below is what the painting was made from, so the same five
/// colors appear twice. Their order differs because an extracted palette is
/// sorted by how much of the picture each color covers, not by where it sat
/// in the source.
///
/// The count cycles. Asking for fewer colors than the image holds makes the
/// clustering merge the nearest ones rather than drop them.
@main
final class PaletteFromImage: Sketch {
    let source = Palette(Color(hex: 0x1B2A41), Color(hex: 0x2C7DA0),
                         Color(hex: 0x8FBFA0), Color(hex: 0xE9C46A),
                         Color(hex: 0xD1495B))

    var painting = Image(width: 1, height: 1)
    var extracted: [Palette] = []   // one per count, so `draw()` never clusters

    override func setup() {
        noStroke()
        painting = paint()

        // Clustering is setup-time work. Extract once per count we might show.
        extracted = (1...8).map { extractPalette(from: painting, count: $0) }
    }

    override func draw() {
        background(Color(hex: 0x101014))

        // Cycle through the counts, holding each for a beat.
        let count = 2 + Int(time * 0.5) % 7
        let palette = extracted[count - 1]

        let side = width - 180.0
        drawImage(painting, in: Rectangle(x: 90, y: 80, width: side, height: side * 0.72))

        // What the extraction found, in order: the first swatch is the color
        // the picture is most made of.
        let barY = 80 + side * 0.72 + 44
        let step = side / Double(palette.count)
        for i in 0..<palette.count {
            fill(palette[i])
            drawRect(90 + Double(i) * step, barY, step, 130, cornerRadius: 4)
        }

        // What it was painted from, for comparison.
        let sourceStep = side / Double(source.count)
        for i in 0..<source.count {
            fill(source[i])
            drawRect(90 + Double(i) * sourceStep, barY + 146, sourceStep, 28)
        }

        drawCaption("\(count) colors extracted; the strip below is the \(source.count) it was painted with")
    }

    /// Bands of the source palette, warped by noise so the boundaries are not
    /// straight and the color mass is uneven, giving the clustering real work.
    private func paint() -> Image {
        let size = 220
        let image = Image(width: size, height: size)
        for y in 0..<size {
            for x in 0..<size {
                let u = Double(x) / Double(size - 1)
                let v = Double(y) / Double(size - 1)
                let warp = noise(u * 3, v * 3) * 0.45
                image[x, y] = source.color(at: fract(u * 0.6 + v * 0.3 + warp))
            }
        }
        return image
    }
}
