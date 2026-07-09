import Foundation
import Ollin
import Testing

/// Extraction is a clustering, so the properties worth pinning are the ones a
/// clustering can quietly break: that it returns the same answer twice, that
/// the first color is the one the image is mostly made of, and that the
/// degenerate inputs stay calm.
@Suite
struct PaletteExtractTests {

    /// An image painted from a fixed set of colors yields exactly those
    /// colors when asked for that many, and nothing invented.
    @Test func flatImageReturnsItsOwnColors() {
        let reds = Color(red: 1, green: 0, blue: 0)
        let green = Color(red: 0, green: 1, blue: 0)
        let blue = Color(red: 0, green: 0, blue: 1)
        let image = paint([reds, green, blue], width: 12, height: 12)

        let palette = Palette(extractedFrom: image, count: 3)
        #expect(palette.count == 3)
        for color in [reds, green, blue] {
            #expect(palette.colors.contains { near($0, color) })
        }
    }

    /// Asking for more colors than the image holds returns what it holds.
    @Test func fewerDistinctColorsThanRequested() {
        let image = paint([Color(red: 1, green: 0, blue: 0),
                           Color(red: 0, green: 0, blue: 1)], width: 8, height: 8)
        let palette = Palette(extractedFrom: image, count: 6)
        #expect(palette.count == 2)
    }

    /// The dominant color leads. Three quarters red, one quarter blue.
    @Test func mostUsedColorComesFirst() {
        let image = Image(width: 8, height: 8, color: Color(red: 1, green: 0, blue: 0))
        for y in 0..<2 {
            for x in 0..<8 { image[x, y] = Color(red: 0, green: 0, blue: 1) }
        }
        let palette = Palette(extractedFrom: image, count: 2)
        #expect(palette.count == 2)
        #expect(near(palette[0], Color(red: 1, green: 0, blue: 0)))
        #expect(near(palette[1], Color(red: 0, green: 0, blue: 1)))
    }

    /// The same image and seed always give the same palette: an extracted
    /// palette can be snapshotted and carried in an export's recipe.
    @Test func extractionIsDeterministic() {
        let image = noisyImage()
        let first = Palette(extractedFrom: image, count: 5)
        for _ in 0..<4 {
            #expect(Palette(extractedFrom: image, count: 5).colors == first.colors)
        }
    }

    /// A different seed is allowed to land elsewhere, but must still be stable.
    @Test func seedIsStablePerValue() {
        let image = noisyImage()
        let a = Palette(extractedFrom: image, count: 5, seed: 7)
        let b = Palette(extractedFrom: image, count: 5, seed: 7)
        #expect(a.colors == b.colors)
    }

    /// Transparent pixels carry no color, so they carry no weight.
    @Test func transparentPixelsAreIgnored() {
        let image = Image(width: 8, height: 8, color: .clear)
        for x in 0..<8 { image[x, 0] = Color(red: 1, green: 0, blue: 0) }
        let palette = Palette(extractedFrom: image, count: 3)
        #expect(palette.count == 1)
        #expect(near(palette[0], Color(red: 1, green: 0, blue: 0)))
    }

    /// Nothing to cluster: an empty palette, not a crash and not a black.
    @Test func degenerateInputsYieldEmptyPalettes() {
        let blank = Image(width: 4, height: 4, color: .clear)
        #expect(Palette(extractedFrom: blank, count: 3).count == 0)

        let solid = Image(width: 4, height: 4, color: Color(red: 1, green: 0, blue: 0))
        #expect(Palette(extractedFrom: solid, count: 0).count == 0)
        #expect(Palette(extractedFrom: solid, count: 1).count == 1)
    }

    /// A large image costs no more accuracy than a small one: the grid sample
    /// still sees the same broad color mass.
    @Test func largeImagesSampleDownWithoutLosingTheColors() {
        let image = Image(width: 400, height: 400, color: Color(red: 1, green: 0, blue: 0))
        for y in 0..<200 {
            for x in 0..<400 { image[x, y] = Color(red: 0, green: 0, blue: 1) }
        }
        let palette = Palette(extractedFrom: image, count: 2)
        #expect(palette.count == 2)
        #expect(palette.colors.contains { near($0, Color(red: 1, green: 0, blue: 0)) })
        #expect(palette.colors.contains { near($0, Color(red: 0, green: 0, blue: 1)) })
    }

    // MARK: - Helpers

    /// Bands of `colors` down the image, so each occupies a known share.
    private func paint(_ colors: [Color], width: Int, height: Int) -> Image {
        let image = Image(width: width, height: height, color: colors[0])
        let band = height / colors.count
        for (i, color) in colors.enumerated() {
            for y in (i * band)..<min((i + 1) * band, height) {
                for x in 0..<width { image[x, y] = color }
            }
        }
        return image
    }

    /// A deterministic spread of colors, enough to make clustering do work.
    private func noisyImage() -> Image {
        var rng = SplitMix64(seed: 99)
        let image = Image(width: 32, height: 32, color: .clear)
        for y in 0..<32 {
            for x in 0..<32 {
                image[x, y] = Color(red: Double(rng.next() % 256) / 255,
                                    green: Double(rng.next() % 256) / 255,
                                    blue: Double(rng.next() % 256) / 255)
            }
        }
        return image
    }

    /// Round-tripping through premultiplied bytes and OKLab moves a channel by
    /// a step or two, so compare with a tolerance rather than for equality.
    private func near(_ a: Color, _ b: Color, tolerance: Double = 0.02) -> Bool {
        abs(a.red - b.red) < tolerance
            && abs(a.green - b.green) < tolerance
            && abs(a.blue - b.blue) < tolerance
    }
}
