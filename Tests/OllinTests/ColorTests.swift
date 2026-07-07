import Ollin
import Testing

/// Pure CPU checks on `Color`'s hex and HSB initializers. No Metal, so these
/// run everywhere including CI.
@Suite
struct ColorTests {

    /// A loose float comparison for conversion-derived channels.
    private func close(_ a: Color, _ b: Color, _ eps: Double = 1e-12) -> Bool {
        abs(a.red - b.red) <= eps && abs(a.green - b.green) <= eps
            && abs(a.blue - b.blue) <= eps && abs(a.alpha - b.alpha) <= eps
    }

    // MARK: Hex, integer form

    @Test func hexIntChannels() {
        let c = Color(hex: 0xFF8040)
        #expect(c.red == 1)
        #expect(c.green == 128.0 / 255)
        #expect(c.blue == 64.0 / 255)
        #expect(c.alpha == 1)
    }

    @Test func hexIntAlphaParameter() {
        #expect(Color(hex: 0x0000FF, alpha: 0.5)
            == Color(red: 0, green: 0, blue: 1, alpha: 0.5))
    }

    @Test func hexIntExtremes() {
        #expect(Color(hex: 0x000000) == .black)
        #expect(Color(hex: 0xFFFFFF) == .white)
    }

    // MARK: Hex, string form

    @Test func hexStringSixDigits() {
        #expect(Color(hex: "#FF0066") == Color(hex: 0xFF0066))
        // The leading # is optional and case doesn't matter.
        #expect(Color(hex: "ff0066") == Color(hex: 0xFF0066))
    }

    @Test func hexStringShorthand() {
        #expect(Color(hex: "#f60") == Color(hex: 0xFF6600))
        #expect(Color(hex: "#f608")
            == Color(red: 1, green: 102.0 / 255, blue: 0, alpha: 136.0 / 255))
    }

    @Test func hexStringEightDigits() {
        #expect(Color(hex: "#FF006680")
            == Color(red: 1, green: 0, blue: 102.0 / 255, alpha: 128.0 / 255))
    }

    @Test func hexStringRejectsMalformed() {
        #expect(Color(hex: "") == nil)
        #expect(Color(hex: "#") == nil)
        #expect(Color(hex: "#ff006") == nil)      // five digits fits no form
        #expect(Color(hex: "#ff00g6") == nil)     // non-hex character
        #expect(Color(hex: "0xFF0066") == nil)    // 0x is the integer form's spelling
        #expect(Color(hex: "##ff0066") == nil)
    }

    // MARK: Hue, saturation, brightness

    @Test func hsbPrimaries() {
        #expect(close(Color(hue: 0, saturation: 1, brightness: 1), .red))
        #expect(close(Color(hue: 1.0 / 3, saturation: 1, brightness: 1), .green, 1e-9))
        #expect(close(Color(hue: 2.0 / 3, saturation: 1, brightness: 1), .blue, 1e-9))
    }

    @Test func hsbSecondaries() {
        #expect(close(Color(hue: 1.0 / 6, saturation: 1, brightness: 1),
                      Color(red: 1, green: 1, blue: 0), 1e-9))
        #expect(close(Color(hue: 0.5, saturation: 1, brightness: 1),
                      Color(red: 0, green: 1, blue: 1), 1e-9))
    }

    @Test func hsbZeroSaturationIsGray() {
        #expect(close(Color(hue: 0.37, saturation: 0, brightness: 0.6),
                      Color(white: 0.6)))
    }

    @Test func hsbHueWraps() {
        #expect(close(Color(hue: 1.25, saturation: 0.8, brightness: 0.9),
                      Color(hue: 0.25, saturation: 0.8, brightness: 0.9), 1e-9))
        #expect(close(Color(hue: -0.75, saturation: 0.8, brightness: 0.9),
                      Color(hue: 0.25, saturation: 0.8, brightness: 0.9), 1e-9))
        #expect(close(Color(hue: 1, saturation: 1, brightness: 1), .red))
    }

    @Test func hsbClampsSaturationAndBrightness() {
        #expect(close(Color(hue: 0, saturation: 1.5, brightness: 1), .red))
        #expect(close(Color(hue: 0, saturation: 1, brightness: -0.2), .black))
    }

    @Test func hsbAlphaPassesThrough() {
        #expect(Color(hue: 0, saturation: 1, brightness: 1, alpha: 0.25).alpha == 0.25)
    }

    // MARK: Color temperature (blackbody)

    @Test func kelvinWarmIsOrange() {
        // Low temperatures (candle/tungsten) are warm: red full, blue suppressed.
        let warm = Color(kelvin: 2000)
        #expect(warm.red > warm.green && warm.green > warm.blue)
        #expect(warm.red == 1.0)        // red saturates at 255 below ~6600K
    }

    @Test func kelvinCoolIsBlue() {
        // High temperatures (deep shade) are cool: blue full, red pulled back.
        let cool = Color(kelvin: 12000)
        #expect(cool.blue > cool.red)
        #expect(cool.blue == 1.0)       // blue saturates at 255 above 6600K
    }

    @Test func kelvinClampsRange() {
        // Below 1000K and above 40000K clamp to the endpoints (no NaN from the logs).
        #expect(close(Color(kelvin: 100), Color(kelvin: 1000)))
        #expect(close(Color(kelvin: 99999), Color(kelvin: 40000)))
    }

    @Test(arguments: Array(stride(from: 1000.0, through: 40000, by: 500)))
    func kelvinComponentsStayInRange(_ k: Double) {
        let c = Color(kelvin: k)
        #expect(c.red >= 0 && c.red <= 1)
        #expect(c.green >= 0 && c.green <= 1)
        #expect(c.blue >= 0 && c.blue <= 1)
    }

    @Test func kelvinAlphaPassesThrough() {
        #expect(Color(kelvin: 5600, alpha: 0.4).alpha == 0.4)
    }

    // MARK: Named colors

    /// Each extended named constant beside its CSS Color Module Level 4 hex value.
    static let namedCSSValues: [(name: String, color: Color, hex: UInt32)] = [
        ("orange", .orange, 0xFFA500),
        ("cyan", .cyan, 0x00FFFF),
        ("magenta", .magenta, 0xFF00FF),
        ("teal", .teal, 0x008080),
        ("indigo", .indigo, 0x4B0082),
        ("slateGray", .slateGray, 0x708090),
    ]

    /// The extended named set carries its CSS Color Module Level 4 values.
    @Test(arguments: ColorTests.namedCSSValues)
    func namedColorsMatchCSSValues(_ named: (name: String, color: Color, hex: UInt32)) {
        #expect(named.color == Color(hex: named.hex), "\(named.name)")
    }

    /// Every named constant is opaque.
    @Test(arguments: [Color.yellow, .orange, .purple, .crimson, .gold,
                      .forestGreen, .navy, .violet, .khaki, .silver])
    func namedColorsAreOpaque(_ color: Color) {
        #expect(color.alpha == 1)
    }

    /// The pure additive primaries are kept (deliberately not CSS's darker
    /// `green`), so `green` reads as full-intensity green.
    @Test func primariesStayPure() {
        #expect(Color.green == Color(red: 0, green: 1, blue: 0))
        #expect(Color.green != Color(hex: 0x008000))
    }

    /// `withAlpha` swaps only the alpha, leaving the color itself untouched.
    @Test func withAlphaKeepsTheColor() {
        let faded = Color(hex: 0xE4572E).withAlpha(0.3)
        #expect(faded.alpha == 0.3)
        #expect(faded.withAlpha(1) == Color(hex: 0xE4572E))
    }

    /// Luminance is 0...1, anchored at black and white, and weighs the
    /// channels the way the eye does: green over red over blue.
    @Test func luminanceWeighsChannelsPerceptually() {
        #expect(Color.black.luminance == 0)
        #expect(abs(Color.white.luminance - 1) < 1e-9)
        #expect(Color.green.luminance > Color.red.luminance)
        #expect(Color.red.luminance > Color.blue.luminance)
        #expect(abs(Color.green.luminance - 0.7152) < 1e-9)
    }
}
