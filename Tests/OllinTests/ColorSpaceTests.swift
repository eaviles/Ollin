import Ollin
import Testing

/// Pure CPU checks on the OKLab-family conversions and `Color.mix`. No Metal,
/// so these run everywhere including CI.
@Suite
struct ColorSpaceTests {

    private func close(_ a: Double, _ b: Double, _ eps: Double = 1e-4) -> Bool {
        abs(a - b) <= eps
    }

    private func close(_ a: Color, _ b: Color, _ eps: Double = 1e-6) -> Bool {
        close(a.red, b.red, eps) && close(a.green, b.green, eps)
            && close(a.blue, b.blue, eps) && close(a.alpha, b.alpha, eps)
    }

    private func inGamut(_ c: Color) -> Bool {
        (0...1).contains(c.red) && (0...1).contains(c.green) && (0...1).contains(c.blue)
    }

    // MARK: OKLab

    @Test func okLabKnownValues() {
        let white = OKLab(.white)
        #expect(close(white.l, 1, 1e-5))
        #expect(close(white.a, 0, 1e-5))
        #expect(close(white.b, 0, 1e-5))
        let black = OKLab(.black)
        #expect(close(black.l, 0, 1e-9))
        // The sRGB primaries' published OKLab coordinates.
        let red = OKLab(.red)
        #expect(close(red.l, 0.62796))
        #expect(close(red.a, 0.22486))
        #expect(close(red.b, 0.12585))
        let green = OKLab(.green)
        #expect(close(green.l, 0.86644))
        #expect(close(green.a, -0.23389))
        #expect(close(green.b, 0.17950))
        let blue = OKLab(.blue)
        #expect(close(blue.l, 0.45201))
        #expect(close(blue.a, -0.03246))
        #expect(close(blue.b, -0.31153))
    }

    /// A 5×5×5 sweep of the unit RGB cube: the round-trip grid the OKLab and
    /// OKLCH conversions must both return unchanged.
    static let rgbCube: [Color] = {
        let s = Array(stride(from: 0.0, through: 1.0, by: 0.25))
        return s.flatMap { r in s.flatMap { g in s.map { b in Color(red: r, green: g, blue: b) } } }
    }()

    @Test(arguments: ColorSpaceTests.rgbCube)
    func okLabRoundTrip(_ c: Color) {
        #expect(close(Color(OKLab(c)), c))
    }

    // MARK: OKLCH

    @Test func okLCHKnownHues() {
        let red = OKLCH(.red)
        #expect(close(red.c, 0.25768, 1e-3))
        #expect(close(red.h, 29.234 / 360, 1e-3))
        #expect(close(OKLCH(.green).h, 142.495 / 360, 1e-3))
        #expect(close(OKLCH(.blue).h, 264.052 / 360, 1e-3))
    }

    @Test(arguments: ColorSpaceTests.rgbCube)
    func okLCHRoundTrip(_ c: Color) {
        #expect(close(Color(OKLCH(c)), c))
    }

    @Test func grayHasNoHue() {
        #expect(OKLCH(.gray).h == 0)
        #expect(OKLCH(.gray).c < 1e-6)
        #expect(OKHSL(.gray).h == 0)
        #expect(OKHSL(.gray).s == 0)
    }

    // MARK: Gamut mapping

    @Test func gamutMapReducesChromaOnly() {
        // Far more chroma than sRGB can show at this lightness and hue.
        let wild = OKLCH(l: 0.7, c: 0.5, h: 0.4)
        let c = Color(wild)
        #expect(inGamut(c))
        let back = OKLCH(c)
        #expect(close(back.l, 0.7, 2e-3))
        #expect(close(back.h, 0.4, 2e-3))
        #expect(back.c < 0.5)
        #expect(back.c > 0.05)
    }

    @Test func gamutMapLeavesInGamutAlone() {
        let mild = OKLCH(l: 0.6, c: 0.1, h: 0.1)
        let once = Color(mild)
        #expect(inGamut(once))
        #expect(close(Color(OKLCH(once)), once))
    }

    @Test func extremeLightnessMapsToBlackAndWhite() {
        #expect(close(Color(OKLab(l: 1.4, a: 0, b: 0)), .white))
        #expect(close(Color(OKLab(l: -0.2, a: 0, b: 0)), .black))
    }

    // MARK: OKHSL

    /// A sweep of OKHSL coordinates well inside the sRGB gamut, each surviving
    /// the round-trip back through `Color`.
    static let okHSLGrid: [OKHSL] = {
        let hs = Array(stride(from: 0.05, through: 0.95, by: 0.15))
        let ss = Array(stride(from: 0.1, through: 0.9, by: 0.2))
        let ls = Array(stride(from: 0.1, through: 0.9, by: 0.2))
        return hs.flatMap { h in ss.flatMap { s in ls.map { l in OKHSL(h: h, s: s, l: l) } } }
    }()

    @Test(arguments: ColorSpaceTests.okHSLGrid)
    func okHSLRoundTrip(_ hsl: OKHSL) {
        let c = Color(hsl)
        #expect(inGamut(c))
        let back = OKHSL(c)
        #expect(close(back.h, hsl.h))
        #expect(close(back.s, hsl.s))
        #expect(close(back.l, hsl.l))
    }

    @Test func okHSLExtremes() {
        #expect(Color(OKHSL(h: 0.3, s: 0.8, l: 1)) == .white)
        #expect(Color(OKHSL(h: 0.3, s: 0.8, l: 0)) == .black)
        // A fully saturated primary sits on the gamut boundary.
        let red = OKHSL(.red)
        #expect(close(red.s, 1, 1e-3))
        #expect(close(red.l, 0.568, 1e-3))
    }

    @Test(arguments: Array(stride(from: 0.1, through: 0.9, by: 0.1)))
    func okHSLHoldsLightnessAcrossHues(_ h: Double) {
        // The OKHSL pitch: same s and l at any hue reads as the same lightness.
        let reference = OKLab(Color(OKHSL(h: 0, s: 0.9, l: 0.6))).l
        let l = OKLab(Color(OKHSL(h: h, s: 0.9, l: 0.6))).l
        #expect(close(l, reference, 1e-6))
    }

    // MARK: Mixing

    @Test(arguments: [ColorSpace.rgb, .hsb, .oklab, .oklch, .okhsl])
    func mixEndpointsAndClampT(_ space: ColorSpace) {
        let a = Color(hex: 0x3366FF, alpha: 0.5)
        let b = Color(hex: 0xFFAA00)
        #expect(close(Color.mix(a, b, 0, in: space), a), "t = 0 in \(space)")
        #expect(close(Color.mix(a, b, 1, in: space), b), "t = 1 in \(space)")
        #expect(close(Color.mix(a, b, -3, in: space), a), "t clamps low in \(space)")
        #expect(close(Color.mix(a, b, 7, in: space), b), "t clamps high in \(space)")
    }

    @Test func mixDefaultIsPerceptualMidGray() {
        let mid = Color.mix(.black, .white, 0.5)
        // The published matrices leave grays a ~4e-8 channel residual.
        #expect(close(mid.red, mid.green, 1e-6))
        #expect(close(mid.green, mid.blue, 1e-6))
        #expect(close(OKLab(mid).l, 0.5, 1e-6))
    }

    @Test func mixRGBIsComponentLerp() {
        #expect(close(Color.mix(.red, .blue, 0.5, in: .rgb),
                      Color(red: 0.5, green: 0, blue: 0.5), 1e-12))
    }

    @Test func mixHueTakesShortestArc() {
        // Red (h 0) to magenta-violet (h 5/6): the short way passes pink
        // (h 11/12), never green.
        let magenta = Color(hue: 5.0 / 6, saturation: 1, brightness: 1)
        let mid = Color.mix(.red, magenta, 0.5, in: .hsb)
        #expect(mid.green < 1e-9)
        #expect(close(mid.red, 1, 1e-9))
        #expect(close(mid.blue, 0.5, 1e-9))
    }

    @Test func mixAchromaticEndpointAdoptsHue() {
        // Fading red to white shouldn't swing through unrelated hues.
        let mid = Color.mix(.white, .red, 0.5, in: .oklch)
        #expect(close(OKLCH(mid).h, OKLCH(.red).h, 1e-2))
        let mid2 = Color.mix(.red, .black, 0.5, in: .okhsl)
        #expect(close(OKHSL(mid2).h, OKHSL(.red).h, 1e-2))
    }

    @Test func mixInterpolatesAlpha() {
        let a = Color(red: 1, green: 0, blue: 0, alpha: 0)
        let b = Color(red: 1, green: 0, blue: 0, alpha: 1)
        #expect(close(Color.mix(a, b, 0.25).alpha, 0.25, 1e-12))
    }

    @Test(arguments: Array(stride(from: 0.0, to: 1.0, by: 0.125)),
                     Array(stride(from: 0.25, through: 1.0, by: 0.25)))
    func hsbComponentsRoundTrip(_ h: Double, _ s: Double) {
        let c = Color(hue: h, saturation: s, brightness: 0.8)
        let back = Color.mix(c, c, 0.5, in: .hsb)
        #expect(close(back, c, 1e-9))
    }
}
