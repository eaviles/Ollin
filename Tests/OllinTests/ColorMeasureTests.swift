@testable import Ollin
import Testing
import Foundation

/// Measuring color: CIELAB, the two distances, the palette entry nearest a color,
/// an image's histogram, and shades whose hue drifts with lightness.
///
/// The oracles are external wherever one exists. CIEDE2000 is read against the 34
/// pairs Sharma, Wu and Dalal published with their implementation notes (2005),
/// which were chosen to catch the places implementations slip (the mean hue across
/// the wrap, a color with no chroma, the blue rotation term). CIELAB is read against
/// sRGB red's published D50 value and white's exact one. The nearest entry is read
/// against a brute-force search, and the histogram against counts made by hand.
@Suite
struct ColorMeasureTests {

    // MARK: CIEDE2000

    /// Sharma, Wu and Dalal, "The CIEDE2000 Color-Difference Formula: Implementation
    /// Notes, Supplementary Test Data, and Mathematical Observations", Color Research
    /// and Application 30 (2005), Table 1: L1 a1 b1, L2 a2 b2, and the difference.
    static let sharmaPairs: [(Double, Double, Double, Double, Double, Double, Double)] = [
        (50.0000, 2.6772, -79.7751, 50.0000, 0.0000, -82.7485, 2.0425),
        (50.0000, 3.1571, -77.2803, 50.0000, 0.0000, -82.7485, 2.8615),
        (50.0000, 2.8361, -74.0200, 50.0000, 0.0000, -82.7485, 3.4412),
        (50.0000, -1.3802, -84.2814, 50.0000, 0.0000, -82.7485, 1.0000),
        (50.0000, -1.1848, -84.8006, 50.0000, 0.0000, -82.7485, 1.0000),
        (50.0000, -0.9009, -85.5211, 50.0000, 0.0000, -82.7485, 1.0000),
        (50.0000, 0.0000, 0.0000, 50.0000, -1.0000, 2.0000, 2.3669),
        (50.0000, -1.0000, 2.0000, 50.0000, 0.0000, 0.0000, 2.3669),
        (50.0000, 2.4900, -0.0010, 50.0000, -2.4900, 0.0009, 7.1792),
        (50.0000, 2.4900, -0.0010, 50.0000, -2.4900, 0.0010, 7.1792),
        (50.0000, 2.4900, -0.0010, 50.0000, -2.4900, 0.0011, 7.2195),
        (50.0000, 2.4900, -0.0010, 50.0000, -2.4900, 0.0012, 7.2195),
        (50.0000, -0.0010, 2.4900, 50.0000, 0.0009, -2.4900, 4.8045),
        (50.0000, -0.0010, 2.4900, 50.0000, 0.0010, -2.4900, 4.8045),
        (50.0000, -0.0010, 2.4900, 50.0000, 0.0011, -2.4900, 4.7461),
        (50.0000, 2.5000, 0.0000, 50.0000, 0.0000, -2.5000, 4.3065),
        (50.0000, 2.5000, 0.0000, 73.0000, 25.0000, -18.0000, 27.1492),
        (50.0000, 2.5000, 0.0000, 61.0000, -5.0000, 29.0000, 22.8977),
        (50.0000, 2.5000, 0.0000, 56.0000, -27.0000, -3.0000, 31.9030),
        (50.0000, 2.5000, 0.0000, 58.0000, 24.0000, 15.0000, 19.4535),
        (50.0000, 2.5000, 0.0000, 50.0000, 3.1736, 0.5854, 1.0000),
        (50.0000, 2.5000, 0.0000, 50.0000, 3.2972, 0.0000, 1.0000),
        (50.0000, 2.5000, 0.0000, 50.0000, 1.8634, 0.5757, 1.0000),
        (50.0000, 2.5000, 0.0000, 50.0000, 3.2592, 0.3350, 1.0000),
        (60.2574, -34.0099, 36.2677, 60.4626, -34.1751, 39.4387, 1.2644),
        (63.0109, -31.0961, -5.8663, 62.8187, -29.7946, -4.0864, 1.2630),
        (61.2901, 3.7196, -5.3901, 61.4292, 2.2480, -4.9620, 1.8731),
        (35.0831, -44.1164, 3.7933, 35.0232, -40.0716, 1.5901, 1.8645),
        (22.7233, 20.0904, -46.6940, 23.0331, 14.9730, -42.5619, 2.0373),
        (36.4612, 47.8580, 18.3852, 36.2715, 50.5065, 21.2231, 1.4146),
        (90.8027, -2.0831, 1.4410, 91.1528, -1.6435, 0.0447, 1.4441),
        (90.9257, -0.5406, -0.9208, 88.6381, -0.8985, -0.7239, 1.5381),
        (6.7747, -0.2908, -2.4247, 5.8714, -0.0985, -2.2286, 0.6377),
        (2.0776, 0.0795, -1.1350, 0.9033, -0.0636, -0.5514, 0.9082),
    ]

    /// Every published pair to the four decimals it is printed with, and the same
    /// answer with the two colors swapped.
    @Test func ciede2000MatchesThePublishedPairs() {
        #expect(Self.sharmaPairs.count == 34)
        for (i, row) in Self.sharmaPairs.enumerated() {
            let one = CIELab(l: row.0, a: row.1, b: row.2)
            let two = CIELab(l: row.3, a: row.4, b: row.5)
            let forward = one.ciede2000(to: two)
            let backward = two.ciede2000(to: one)
            #expect(abs(forward - row.6) < 1e-4, "pair \(i + 1): \(forward) against \(row.6)")
            #expect(abs(forward - backward) < 1e-12, "pair \(i + 1) is not symmetric")
        }
    }

    // MARK: CIELAB

    /// White is exactly (100, 0, 0), since the Bradford adaptation carries D65 to
    /// D50; sRGB red is (54.2905, 80.8049, 69.8910), the published D50 value.
    @Test func cielabReadsTheKnownValues() {
        let white = CIELab(.white)
        #expect(abs(white.l - 100) < 1e-9 && abs(white.a) < 1e-9 && abs(white.b) < 1e-9)
        let black = CIELab(.black)
        #expect(abs(black.l) < 1e-12 && abs(black.a) < 1e-12 && abs(black.b) < 1e-12)
        let red = CIELab(Color(red: 1, green: 0, blue: 0))
        #expect(abs(red.l - 54.2905) < 1e-4)
        #expect(abs(red.a - 80.8049) < 1e-4)
        #expect(abs(red.b - 69.8910) < 1e-4)
        // A gray is a gray: no a, no b, at every level.
        for v in stride(from: 0.05, through: 0.95, by: 0.1) {
            let gray = CIELab(Color(white: v))
            #expect(abs(gray.a) < 1e-9 && abs(gray.b) < 1e-9)
        }
    }

    /// A color into CIELAB and back is the same color, for every color in sRGB.
    @Test func cielabRoundTrips() {
        var random = SplitMix64(seed: 112)
        for _ in 0 ..< 500 {
            let color = Color(red: Double.random(in: 0 ... 1, using: &random), green: Double.random(in: 0 ... 1, using: &random), blue: Double.random(in: 0 ... 1, using: &random))
            let back = Color(CIELab(color))
            #expect(abs(back.red - color.red) < 1e-9)
            #expect(abs(back.green - color.green) < 1e-9)
            #expect(abs(back.blue - color.blue) < 1e-9)
        }
    }

    /// A swatch past the sRGB gamut lands inside it, keeping its lightness and
    /// its hue the way an OKLab color mapped back does.
    @Test func aLabColorOutsideSRGBIsMappedIn() {
        let vivid = CIELab(l: 60, a: -90, b: 70)                   // a green no screen makes
        let mapped = Color(vivid)
        for c in [mapped.red, mapped.green, mapped.blue] { #expect((0 ... 1).contains(c)) }
        let unmapped = vivid.linearRGB
        let wanted = OKLab(linearRed: unmapped.x, green: unmapped.y, blue: unmapped.z)
        let wantedHue = atan2(wanted.b, wanted.a) / .tau
        let got = OKLCH(mapped)
        #expect(abs(got.l - wanted.l) < 0.01)
        #expect(abs((got.h - wantedHue).truncatingRemainder(dividingBy: 1)) < 0.01
            || abs((got.h - wantedHue).truncatingRemainder(dividingBy: 1)) > 0.99)
        #expect(got.c < (wanted.a * wanted.a + wanted.b * wanted.b).squareRoot())
    }

    // MARK: Distance

    /// OKLab distance is the confusion check's own number, black to white is 1, and
    /// both measures are zero on a color and symmetric between two.
    @Test func distanceIsTheConfusionChecksScale() {
        let palette = Palette.set1
        for confusion in palette.confusions(under: ColorVision(.deuteranomaly), tolerance: 0.2) {
            let a = palette[confusion.first].simulated(ColorVision(.deuteranomaly))
            let b = palette[confusion.second].simulated(ColorVision(.deuteranomaly))
            #expect(abs(a.distance(to: b) - confusion.distance) < 1e-12)
        }
        #expect(abs(Color.black.distance(to: .white) - 1) < 1e-6)
        for measure in ColorDistance.allCases {
            for (a, b) in zip(palette.colors, palette.colors.reversed()) {
                #expect(a.distance(to: a, measure: measure) == 0)
                #expect(abs(a.distance(to: b, measure: measure)
                    - b.distance(to: a, measure: measure)) < 1e-12)
            }
        }
        // The CIEDE2000 route is CIELAB's own formula, color for color.
        let teal = Color(hex: 0x2A7F8F), sand = Color(hex: 0xD8C49A)
        #expect(teal.distance(to: sand, measure: .ciede2000)
            == CIELab(teal).ciede2000(to: CIELab(sand)))
    }

    // MARK: Nearest

    /// The nearest entry is the brute-force minimum under each measure, ties going
    /// to the earlier entry, and nothing for an empty palette.
    @Test(arguments: ColorDistance.allCases)
    func theNearestEntryIsTheSmallestDistance(measure: ColorDistance) {
        var random = SplitMix64(seed: 7)
        for round in 0 ..< 60 {
            let palette = Palette((0 ..< 3 + round % 9).map { _ in
                Color(red: Double.random(in: 0 ... 1, using: &random), green: Double.random(in: 0 ... 1, using: &random), blue: Double.random(in: 0 ... 1, using: &random))
            })
            let probe = Color(red: Double.random(in: 0 ... 1, using: &random), green: Double.random(in: 0 ... 1, using: &random), blue: Double.random(in: 0 ... 1, using: &random))
            let distances = palette.colors.map { probe.distance(to: $0, measure: measure) }
            let expected = distances.indices.min { (distances[$0], $0) < (distances[$1], $1) }
            #expect(palette.nearestIndex(to: probe, measure: measure) == expected)
            #expect(palette.nearest(to: probe, measure: measure) == expected.map { palette[$0] })
        }
        let twins = Palette(.red, .blue, .blue, .red)
        #expect(twins.nearestIndex(to: Color(red: 0.1, green: 0, blue: 0.9), measure: measure) == 1)
        #expect(twins.nearestIndex(to: Color(red: 0.9, green: 0, blue: 0.1), measure: measure) == 0)
        #expect(Palette([]).nearestIndex(to: .red, measure: measure) == nil)
        #expect(Palette([]).nearest(to: .red, measure: measure) == nil)
    }

    // MARK: Histogram

    /// A picture whose 256 pixels hold every byte once, opaque: one pixel a bin at
    /// 256 bins on each color channel, the total the pixel count, and coarser bins
    /// holding their share exactly.
    @Test func everyByteLandsInItsOwnBin() throws {
        var bytes: [UInt8] = []
        for v in 0 ..< 256 { bytes += [UInt8(v), UInt8(255 - v), UInt8(v / 2), 255] }
        let image = try #require(Image(width: 16, height: 16, premultipliedRGBA: bytes))
        let red = image.histogram(of: .red)
        #expect(red.total == 256)
        #expect(red.counts == [Int](repeating: 1, count: 256))
        #expect(image.histogram(of: .green).counts == [Int](repeating: 1, count: 256))
        #expect(image.histogram(of: .blue).counts
            == (0 ..< 256).map { $0 < 128 ? 2 : 0 })
        #expect(image.histogram(of: .alpha, bins: 4).counts == [0, 0, 0, 256])
        #expect(image.histogram(of: .red, bins: 16).counts == [Int](repeating: 16, count: 16))
        for channel in Histogram.Channel.allCases {
            for bins in [1, 3, 7, 64, 1000] {
                #expect(image.histogram(of: channel, bins: bins).total == 256)
            }
        }
    }

    /// The region is the one `averageColor(in:)` reads, edges rounded outward, and
    /// the total is its pixel count; a region off the picture counts nothing.
    @Test func aRegionCountsItsOwnPixels() {
        let image = Image(width: 40, height: 30, color: Color(red: 0.2, green: 0.6, blue: 0.9))
        #expect(image.histogram().total == 1200)
        #expect(image.histogram(in: Rectangle(x: 10, y: 5, width: 8, height: 4)).total == 32)
        #expect(image.histogram(in: Rectangle(x: 9.5, y: 4.5, width: 8, height: 4)).total == 45)
        #expect(image.histogram(in: Rectangle(x: 35, y: 25, width: 20, height: 20)).total == 25)
        #expect(image.histogram(in: Rectangle(x: 100, y: 100, width: 5, height: 5)).total == 0)
        // One color, one bin, at the color's own lightness.
        let lightness = OKLab(Color(red: 0.2, green: 0.6, blue: 0.9)).l
        let h = image.histogram(of: .lightness, bins: 100)
        #expect(h.counts[Int(lightness * 100)] == 1200)
    }

    /// Straight color is read under alpha, a clear pixel counts at 0, and a
    /// translucent gray's lightness is the gray's own.
    @Test func alphaIsDividedOut() throws {
        // Opaque white, half-covered white (premultiplied 128), and clear.
        let bytes: [UInt8] = [255, 255, 255, 255, 128, 128, 128, 128, 0, 0, 0, 0]
        let image = try #require(Image(width: 3, height: 1, premultipliedRGBA: bytes))
        let red = image.histogram(of: .red, bins: 4)
        #expect(red.counts == [1, 0, 0, 2])
        let light = image.histogram(of: .lightness, bins: 4)
        #expect(light.counts == [1, 0, 0, 2])
        #expect(image.histogram(of: .alpha, bins: 2).counts == [1, 2])
    }

    /// The percentile reads the cumulative count: the median of a ramp is its
    /// middle, the ends are the ends, and a single level answers inside its bin.
    @Test func percentilesReadTheCumulativeCount() throws {
        var bytes: [UInt8] = []
        for v in 0 ..< 256 { bytes += [UInt8(v), UInt8(v), UInt8(v), 255] }
        let ramp = try #require(Image(width: 256, height: 1, premultipliedRGBA: bytes))
        let h = ramp.histogram(of: .red)
        #expect(abs(h.percentile(0.5) - 0.5) < 1e-12)
        #expect(h.percentile(0) == 0)
        #expect(h.percentile(1) == 1)
        #expect(abs(h.percentile(0.25) - 0.25) < 1e-12)
        let flat = Image(width: 10, height: 10, color: Color(white: 0.5))
        let one = flat.histogram(of: .red)
        let bin = one.counts.firstIndex { $0 > 0 }!
        for f in [0.0, 0.3, 0.5, 1.0] {
            let p = one.percentile(f)
            #expect(p >= Double(bin) / 256 && p <= Double(bin + 1) / 256)
        }
        #expect(Image(width: 4, height: 4).histogram(in: Rectangle(x: 9, y: 9, width: 1, height: 1))
            .percentile(0.5) == 0)
    }

    // MARK: Shades

    private static let bases: [Color] = [
        Color(hex: 0xC0392B), Color(hex: 0xE67E22), Color(hex: 0x27AE60), Color(hex: 0x2A7F8F),
        Color(hex: 0x2E5AAC), Color(hex: 0x8E44AD), Color(hex: 0xD35D9B), Color(hex: 0xC8875E),
    ]

    /// The base is one of the swatches, exactly, and lightness climbs swatch by
    /// swatch from the darkest to the lightest.
    @Test(arguments: [3, 5, 8])
    func shadesHoldTheBaseAndClimb(count: Int) {
        for base in Self.bases {
            let shades = Palette.shades(of: base, count: count)
            #expect(shades.count == count)
            #expect(shades.colors.contains(base))
            let lightness = shades.colors.map { OKLab($0).l }
            for (a, b) in zip(lightness, lightness.dropFirst()) { #expect(b > a) }
            #expect(abs(lightness.first! - 0.2) < 0.01 || lightness.first! == OKLab(base).l)
        }
        #expect(Palette.shades(of: .red, count: 1).colors == [.red])
        #expect(Palette.shades(of: .red, count: 0).colors.isEmpty)
    }

    /// The lights turn toward yellow and the shadows away from it, by the drift at
    /// the ends; with no drift the hue never moves.
    @Test func theHueDriftsWarmInTheLightAndCoolInTheShadow() {
        let yellow = OKLCH(Color(red: 1, green: 1, blue: 0)).h
        func arc(_ from: Double, _ to: Double) -> Double {
            var d = (to - from).truncatingRemainder(dividingBy: 1)
            if d > 0.5 { d -= 1 } else if d <= -0.5 { d += 1 }
            return d
        }
        for base in Self.bases {
            let h0 = OKLCH(base).h
            let ramp = Ramp.shades(of: base, lightness: 0.25...0.9, hueDrift: 0.05)
            let light = OKLCH(ramp.color(at: 1)).h
            let dark = OKLCH(ramp.color(at: 0)).h
            // Lights: closer to yellow, never past it. Shadows: further from it.
            #expect(abs(arc(light, yellow)) < abs(arc(h0, yellow)) + 1e-3)
            #expect(abs(arc(dark, yellow)) > abs(arc(h0, yellow)) - 1e-3)
            #expect(abs(abs(arc(h0, dark)) - 0.05) < 0.01)
            // The ends keep at most half the base's chroma.
            for end in [ramp.color(at: 0), ramp.color(at: 1)] {
                #expect(OKLCH(end).c <= OKLCH(base).c * 0.5 + 1e-3)
            }
            let still = Ramp.shades(of: base, lightness: 0.25...0.9, hueDrift: 0)
            for t in [0.0, 0.3, 0.7, 1.0] {
                #expect(abs(arc(OKLCH(still.color(at: t)).h, h0)) < 0.01)
            }
            // A negative drift is the same turns, mirrored.
            let cool = Ramp.shades(of: base, lightness: 0.25...0.9, hueDrift: -0.05)
            #expect(abs(arc(OKLCH(cool.color(at: 1)).h, dark)) < 0.01)
        }
        // A base near yellow stops at yellow in the light rather than passing it.
        let gold = Color(OKLCH(l: 0.75, c: 0.15, h: yellow - 0.01))
        let lights = OKLCH(Ramp.shades(of: gold, hueDrift: 0.1).color(at: 1)).h
        #expect(abs(arc(lights, yellow)) < 0.005)
    }
}
