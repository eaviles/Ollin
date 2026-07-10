import Foundation
@testable import Ollin
import Testing

/// Dithering is a quantizer with a memory, so the properties worth pinning are
/// the ones a quantizer can quietly break: that it only ever emits colors it was
/// given, that the tones it produces average back to the tones it was handed
/// (this is what the linear-light error accumulation buys, and diffusing in sRGB
/// would silently lose), that it answers the same way twice, and that its two
/// threshold maps are the published ones.
@Suite
struct DitherTests {

    private static let diffusionKernels: [Dither] = [
        .floydSteinberg, .jarvisJudiceNinke, .stucki, .atkinson,
        .burkes, .sierra, .twoRowSierra, .sierraLite,
    ]

    // MARK: - Output is drawn from the palette

    /// Every pixel of a dithered image is one of the palette's colors, whichever
    /// method ran. Nothing is blended, nothing is invented.
    @Test func everyPixelComesFromThePalette() {
        let palette = Palette(.black, .white, Color(red: 1, green: 0, blue: 0))
        let source = gradient(width: 32, height: 32)

        for method in Self.diffusionKernels + [.none, .ordered(size: 4), .blueNoise] {
            let out = source.dithered(method, to: palette)
            for y in 0..<out.height {
                for x in 0..<out.width {
                    let pixel = out[x, y]
                    #expect(palette.colors.contains { near($0, pixel) },
                            "\(method) emitted \(pixel) at \(x),\(y)")
                }
            }
        }
    }

    /// Quantizing to N levels emits only the N evenly spaced steps, per channel.
    @Test func levelsQuantizationEmitsOnlyItsSteps() {
        let out = gradient(width: 24, height: 24).dithered(.floydSteinberg, levels: 3)
        let steps = [0.0, 0.5, 1.0]
        for y in 0..<out.height {
            for x in 0..<out.width {
                let pixel = out[x, y]
                for channel in [pixel.red, pixel.green, pixel.blue] {
                    #expect(steps.contains { abs($0 - channel) < 0.01 })
                }
            }
        }
    }

    // MARK: - Tone is preserved (the linear-light property)

    /// The whole point of error diffusion: a flat mid-gray dithered to pure black
    /// and white averages back to that same gray *in linear light*. Diffusing the
    /// error in sRGB instead would land near 0.5 linear (far too bright), which
    /// is the bug this test exists to catch. Atkinson forwards only three
    /// quarters of its error, so it does not preserve tone and is pinned
    /// separately below.
    @Test func errorDiffusionPreservesLinearTone() {
        for gray in [0.25, 0.5, 0.75] {
            let source = flat(Color(red: gray, green: gray, blue: gray), size: 64)
            let expected = Color.srgbToLinear(gray)

            for method in Self.diffusionKernels where method != .atkinson {
                let out = source.dithered(method, to: Palette(.black, .white))
                let mean = meanLinearLuminance(of: out)
                #expect(abs(mean - expected) < 0.02,
                        "\(method) at gray \(gray): mean \(mean), expected \(expected)")
            }
        }
    }

    /// Atkinson's dropped quarter is the early-Macintosh look: shadows crush to
    /// clean black (a 25% gray comes out fully black) and the rest lands where
    /// the leak stops it. The exact means on a flat field are deterministic, so
    /// they are pinned as recorded values rather than a physics bound; a bound
    /// loose enough to admit the crush would also admit a real regression.
    @Test func atkinsonCrushIsStable() {
        let recorded: [(gray: Double, mean: Double)] = [
            (0.25, 0.0), (0.5, 0.1455), (0.75, 0.5305),
        ]
        for pin in recorded {
            let source = flat(Color(red: pin.gray, green: pin.gray, blue: pin.gray), size: 64)
            let out = source.dithered(.atkinson, to: Palette(.black, .white))
            let mean = meanLinearLuminance(of: out)
            #expect(abs(mean - pin.mean) < 0.005,
                    "atkinson at gray \(pin.gray): mean \(mean), pinned \(pin.mean)")
        }
    }

    /// The ordered and blue-noise maps are centered offsets, not raw thresholds,
    /// so they hold their tone too, across the whole ramp. A naive
    /// `value > matrix / n^2` threshold lifts a dark flat field toward a quarter
    /// gray, and a pair search whose noisiness penalty is too strong hands the
    /// light end of the ramp to solid white; this pins that neither happens.
    @Test func thresholdMapsPreserveLinearTone() {
        for gray in [0.25, 0.5, 0.75, 0.9] {
            let source = flat(Color(red: gray, green: gray, blue: gray), size: 64)
            let expected = Color.srgbToLinear(gray)

            // An n-cell matrix can only hit duty cycles in n-ths, so a flat
            // field's tone lands within half a step of the ideal: 1/32 for the
            // 4x4 matrix, finer than the 0.02 catch-all for the others.
            let cases: [(Dither, Double)] = [
                (.ordered(size: 4), 1.0 / 32 + 0.005),
                (.ordered(size: 8), 0.02),
                (.blueNoise, 0.02),
            ]
            for (method, tolerance) in cases {
                let mean = meanLinearLuminance(of: source.dithered(method, to: Palette(.black, .white)))
                #expect(abs(mean - expected) < tolerance,
                        "\(method) at gray \(gray): mean \(mean), expected \(expected)")
            }
        }
    }

    // MARK: - The threshold-map pair search

    /// The pair whose mix best matches the pixel often excludes the single
    /// nearest color. A neutral gray against black, white, and red sits
    /// perceptually nearest the red, but the mix that *is* gray is black and
    /// white: anchoring the pair on the nearest color rendered this field pink.
    @Test func pairSearchDoesNotTintAGrayField() {
        let red = Color(red: 1, green: 0, blue: 0)
        let palette = Palette(.black, .white, red)
        let gray = Color(red: 0.6, green: 0.6, blue: 0.6)
        let source = flat(gray, size: 64)

        for method in [Dither.ordered(size: 16), .blueNoise] {
            let out = source.dithered(method, to: palette)
            var redPixels = 0
            for y in 0..<64 {
                for x in 0..<64 where near(out[x, y], red) { redPixels += 1 }
            }
            #expect(redPixels == 0, "\(method) mixed red into a neutral gray field")
            let mean = meanLinearLuminance(of: out)
            let expected = Color.srgbToLinear(0.6)
            #expect(abs(mean - expected) < 0.02,
                    "\(method): mean \(mean), expected \(expected)")
        }
    }

    /// A tone between two palette colors must dither between them, not snap to
    /// one. Probing for the far color instead of searching pairs left every
    /// tone in this band solid (the projection clamped to zero), a flat plateau
    /// with a false contour at each edge.
    @Test func pairSearchBracketsInsteadOfBanding() {
        let gray = Color(hex: 0xBCBCBC)
        let palette = Palette(.black, gray, .white)
        // Between black and the gray, nearer the gray.
        let source = flat(Color(hex: 0xAAAAAA), size: 64)

        let out = source.dithered(.ordered(size: 16), to: palette)
        var used = Set<Int>()
        for y in 0..<64 {
            for x in 0..<64 {
                for (i, c) in palette.colors.enumerated() where near(out[x, y], c) {
                    used.insert(i)
                }
            }
        }
        #expect(used.count > 1, "a between-tones field came out a solid color")
        #expect(!used.contains(2), "white has no business in a black-to-gray mix")

        let mean = meanLinearLuminance(of: out)
        let expected = Color.srgbToLinear(Double(0xAA) / 255)
        #expect(abs(mean - expected) < 0.02, "mean \(mean), expected \(expected)")
    }

    /// The noisiness penalty: a mid gray flanked by two near-gray tints must
    /// mix the tints, not black and white, even though the black-and-white mix
    /// reproduces the tone exactly. Maximum-contrast speckle over a flat field
    /// is the classic eyesore the pair penalty exists to prevent.
    @Test func pairSearchPrefersTheQuietPair() {
        let tintA = Color(hex: 0x7E8582)
        let tintB = Color(hex: 0x8A7A76)
        let palette = Palette(.black, .white, tintA, tintB)
        let source = flat(Color(hex: 0x808080), size: 64)

        let out = source.dithered(.blueNoise, to: palette)
        var loud = 0
        for y in 0..<64 {
            for x in 0..<64 where near(out[x, y], .black) || near(out[x, y], .white) {
                loud += 1
            }
        }
        #expect(loud == 0, "a mid gray speckled with black or white (\(loud) pixels)")
    }

    /// A fully transparent pixel reads back as black, but that black is not
    /// real light: diffusing its error used to darken the visible pixels along
    /// a cutout's edge. White on a transparent background, quantized to an
    /// all-light palette, must stay pure white.
    @Test func transparentPixelsDoNotBleedIntoTheSubject() {
        let cream = Color(hex: 0xF7DFA5)
        let image = Image(width: 32, height: 32, color: .clear)
        for y in 0..<32 {
            for x in 16..<32 { image[x, y] = .white }
        }
        let out = image.dithered(.floydSteinberg, to: Palette(.white, cream))
        for y in 0..<32 {
            for x in 16..<32 {
                #expect(near(out[x, y], .white),
                        "the cutout's error bled into the subject at \(x),\(y)")
            }
        }
    }

    /// Each family must choose its color in the right space, and the two rules
    /// genuinely disagree: a mid gray against this palette is *linearly* nearest
    /// the navy but *perceptually* nearest the orange.
    ///
    /// Error diffusion has to take the linear pick, because linear light is the
    /// space it carries its error in. Choosing perceptually there traces a thin
    /// false contour of the wrong color along the tone where the rules part, and
    /// the arc is too thin to show up in tile-averaged error statistics, so it is
    /// pinned here instead: a lone pixel has no neighbours to diffuse onto, which
    /// makes the choice rule directly observable in the output.
    ///
    /// `.none` carries no error, so it is free to take the perceptual pick, and
    /// should.
    @Test func eachFamilyChoosesInItsOwnSpace() {
        let navy = Color(hex: 0x14203A)
        let orange = Color(hex: 0xBF3100)
        let cream = Color(hex: 0xF7DFA5)
        let palette = Palette(navy, orange, cream)
        let gray = Color(red: 0.5, green: 0.5, blue: 0.5)

        // The premise: the two rules pick differently for this pixel. If a future
        // palette or color made them agree, the test below would prove nothing.
        let linearPick = nearestInLinear(gray, of: palette)
        let perceptualPick = nearestInOKLab(gray, of: palette)
        #expect(linearPick == navy)
        #expect(perceptualPick == orange)

        let pixel = Image(width: 1, height: 1, color: gray)
        for method in Self.diffusionKernels {
            #expect(near(pixel.dithered(method, to: palette)[0, 0], linearPick),
                    "\(method) did not choose in linear light")
        }
        #expect(near(pixel.dithered(.none, to: palette)[0, 0], perceptualPick))
    }

    // MARK: - Determinism

    /// The same image, method, and palette give byte-identical pixels every time.
    /// Exports and snapshots depend on it.
    @Test func ditheringIsDeterministic() {
        let palette = Palette(extractedFrom: gradient(width: 16, height: 16), count: 4)
        let source = gradient(width: 16, height: 16)

        for method in [Dither.floydSteinberg, .atkinson, .ordered(size: 8), .blueNoise] {
            let first = source.dithered(method, to: palette)
            for _ in 0..<3 {
                let again = source.dithered(method, to: palette)
                #expect(pixelsMatch(first, again), "\(method) is not deterministic")
            }
        }
    }

    /// Serpentine scanning changes the result (it reverses every other row), and
    /// each direction choice is stable on its own.
    @Test func serpentineChangesTheScanAndStaysStable() {
        let source = gradient(width: 24, height: 24)
        let palette = Palette(.black, .white)

        let snake = source.dithered(.floydSteinberg, to: palette, serpentine: true)
        let raster = source.dithered(.floydSteinberg, to: palette, serpentine: false)
        #expect(!pixelsMatch(snake, raster))
        #expect(pixelsMatch(snake, source.dithered(.floydSteinberg, to: palette, serpentine: true)))

        // A threshold map has no scan order to reverse, so the flag is inert.
        #expect(pixelsMatch(source.dithered(.blueNoise, to: palette, serpentine: true),
                            source.dithered(.blueNoise, to: palette, serpentine: false)))
    }

    // MARK: - The threshold maps themselves

    /// The 2x2 and 4x4 Bayer matrices match the published ones, and the
    /// recurrence keeps every larger matrix a permutation of `0..<n*n`.
    @Test func bayerMatrixMatchesThePublishedForm() {
        #expect(BayerMatrix(size: 2).values == [0, 2,
                                                3, 1])
        #expect(BayerMatrix(size: 4).values == [0, 8, 2, 10,
                                                12, 4, 14, 6,
                                                3, 11, 1, 9,
                                                15, 7, 13, 5])
        for size in [2, 4, 8, 16] {
            let matrix = BayerMatrix(size: size)
            #expect(matrix.values.sorted() == Array(0..<(size * size)))
        }
    }

    /// `ordered(size:)` rounds down to a power of two and never escapes `2...16`.
    @Test func orderedSizeIsClampedToAPowerOfTwo() {
        #expect(BayerMatrix.shared(size: 1).size == 2)
        #expect(BayerMatrix.shared(size: 7).size == 4)
        #expect(BayerMatrix.shared(size: 16).size == 16)
        #expect(BayerMatrix.shared(size: 999).size == 16)
    }

    /// The blue-noise tile ranks every cell exactly once. If void-and-cluster
    /// ever assigned a rank twice, the tile would have a hole and a hot spot.
    @Test func blueNoiseTileIsAPermutation() {
        let ranks = BlueNoiseTile.ranks
        let n = BlueNoiseTile.size
        #expect(ranks.count == n * n)
        #expect(ranks.sorted() == Array(0..<(n * n)))
    }

    /// Blue noise's defining property: no clumps and no bare patches. Every
    /// 8x8 block of the tile holds close to its fair share of the low ranks,
    /// which white noise would not.
    @Test func blueNoiseIsEvenlySpread() {
        let n = BlueNoiseTile.size
        let ranks = BlueNoiseTile.ranks
        // Take the lowest eighth of the ranks: the cells that switch on first.
        let cutoff = (n * n) / 8
        var counts = [Int](repeating: 0, count: 64)   // 8x8 grid of 8x8 blocks
        for y in 0..<n {
            for x in 0..<n where ranks[y * n + x] < cutoff {
                counts[(y / 8) * 8 + (x / 8)] += 1
            }
        }
        let fairShare = cutoff / 64          // 8 dots per block
        for count in counts {
            #expect(abs(count - fairShare) <= 3,
                    "a block held \(count) dots, expected about \(fairShare)")
        }
    }

    // MARK: - Degenerate inputs

    /// An empty palette has nothing to snap to, so the image comes back as it was.
    @Test func emptyPaletteReturnsTheImageUnchanged() {
        let source = gradient(width: 8, height: 8)
        #expect(source.dithered(.floydSteinberg, to: Palette([])) === source)
    }

    /// A one-color palette paints everything that color, and does not spin
    /// forever accumulating an error it can never discharge.
    @Test func singleColorPaletteFlattensTheImage() {
        let out = gradient(width: 16, height: 16).dithered(.floydSteinberg,
                                                           to: Palette(.red))
        for y in 0..<out.height {
            for x in 0..<out.width { #expect(near(out[x, y], .red)) }
        }
    }

    /// A 1x1 image has nowhere to push its error and must not walk off the edge.
    @Test func singlePixelImage() {
        let image = Image(width: 1, height: 1, color: Color(red: 0.5, green: 0.5, blue: 0.5))
        let out = image.dithered(.stucki, to: Palette(.black, .white))
        #expect(out.width == 1 && out.height == 1)
    }

    /// Alpha rides through untouched; only the color channels are quantized.
    @Test func alphaIsPreserved() {
        let image = Image(width: 8, height: 8, color: Color(red: 0.5, green: 0.5, blue: 0.5,
                                                            alpha: 0.5))
        let out = image.dithered(.floydSteinberg, to: Palette(.black, .white))
        for y in 0..<8 {
            for x in 0..<8 { #expect(abs(out[x, y].alpha - 0.5) < 0.01) }
        }
    }

    /// `levels` below 2 is meaningless; it clamps rather than crashing.
    @Test func levelsBelowTwoClamps() {
        let out = gradient(width: 8, height: 8).dithered(.none, levels: 1)
        #expect(out.width == 8)
    }

    // MARK: - Helpers

    /// A left-to-right sRGB ramp, the input that makes banding and tone shifts
    /// visible.
    private func gradient(width: Int, height: Int) -> Image {
        let image = Image(width: width, height: height, color: .black)
        for y in 0..<height {
            for x in 0..<width {
                let t = Double(x) / Double(max(1, width - 1))
                image[x, y] = Color(red: t, green: t * 0.5, blue: 1 - t)
            }
        }
        return image
    }

    private func flat(_ color: Color, size: Int) -> Image {
        Image(width: size, height: size, color: color)
    }

    /// Mean of the image's linear-light luminance. The quantity error diffusion
    /// is supposed to conserve.
    private func meanLinearLuminance(of image: Image) -> Double {
        var total = 0.0
        for y in 0..<image.height {
            for x in 0..<image.width {
                let c = image[x, y]
                total += 0.2126 * Color.srgbToLinear(c.red)
                    + 0.7152 * Color.srgbToLinear(c.green)
                    + 0.0722 * Color.srgbToLinear(c.blue)
            }
        }
        return total / Double(image.width * image.height)
    }

    /// The two nearest-color rules, recomputed here rather than reached into, so
    /// the test would catch the implementation quietly swapping spaces.
    private func nearestInLinear(_ color: Color, of palette: Palette) -> Color {
        func linear(_ c: Color) -> SIMD3<Double> {
            SIMD3(Color.srgbToLinear(c.red), Color.srgbToLinear(c.green),
                  Color.srgbToLinear(c.blue))
        }
        let target = linear(color)
        return palette.colors.min {
            let a = linear($0) - target, b = linear($1) - target
            return (a * a).sum() < (b * b).sum()
        }!
    }

    private func nearestInOKLab(_ color: Color, of palette: Palette) -> Color {
        let target = OKLab(color)
        func d(_ c: Color) -> Double {
            let l = OKLab(c)
            let dl = l.l - target.l, da = l.a - target.a, db = l.b - target.b
            return dl * dl + da * da + db * db
        }
        return palette.colors.min { d($0) < d($1) }!
    }

    private func pixelsMatch(_ a: Image, _ b: Image) -> Bool {
        guard a.width == b.width, a.height == b.height else { return false }
        for y in 0..<a.height {
            for x in 0..<a.width where a[x, y] != b[x, y] { return false }
        }
        return true
    }

    /// Round-tripping through premultiplied bytes moves a channel by a step.
    private func near(_ a: Color, _ b: Color, tolerance: Double = 0.02) -> Bool {
        abs(a.red - b.red) < tolerance
            && abs(a.green - b.green) < tolerance
            && abs(a.blue - b.blue) < tolerance
    }
}
