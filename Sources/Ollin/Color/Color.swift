import Foundation

/// An RGBA color with floating-point components in the range `0...1`.
///
/// `Color` is intentionally tiny and dependency-free (Foundation only). The
/// renderer converts it to the GPU-friendly representations it needs (a
/// `SIMD4<Float>` vertex color, or an `MTLClearColor` for `background`).
public struct Color: Equatable, Hashable, Sendable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    /// Create a color from RGBA components in `0...1`.
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Create an opaque (or translucent) grayscale color. `white` is in `0...1`.
    public init(white: Double, alpha: Double = 1.0) {
        self.init(red: white, green: white, blue: white, alpha: alpha)
    }
}

public extension Color {
    /// The same color with a different `alpha` (`0...1`), the original left
    /// untouched. The everyday fade: `fill(ink.withAlpha(0.3))` draws with a
    /// translucent version of a color you already hold.
    func withAlpha(_ alpha: Double) -> Color {
        Color(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// The color's perceived brightness in `0...1`: the Rec. 709 weighted sum
    /// of the linearized components, so green counts most and blue least, the
    /// way the eye weighs them. White is 1, black is 0, and a pure blue reads
    /// far darker than a pure green of the same numeric size.
    ///
    /// The handle for image-driven work: sample a pixel, then size, choose, or
    /// gate marks by `pixel.luminance`.
    var luminance: Double {
        0.2126 * Color.srgbToLinear(red)
            + 0.7152 * Color.srgbToLinear(green)
            + 0.0722 * Color.srgbToLinear(blue)
    }
}

// A few familiar named constants so `.white` / `.black` Just Work.
//
// `red`/`green`/`blue` here are the **additive primaries**: `green` is pure
// `(0, 1, 0)`, the natural default for building colors on screen (it's what the
// CSS named-color set calls `lime`). The fuller set below fills in around them.
public extension Color {
    static let white = Color(white: 1)
    static let black = Color(white: 0)
    static let gray  = Color(white: 0.5)
    static let clear = Color(red: 0, green: 0, blue: 0, alpha: 0)
    static let red   = Color(red: 1, green: 0, blue: 0)
    static let green = Color(red: 0, green: 1, blue: 0)
    static let blue  = Color(red: 0, green: 0, blue: 1)
}

// MARK: - Named colors

// A fuller set of named colors so common ones read by name. The names and their
// exact sRGB values follow the **CSS Color Module Level 4** `<named-color>` set,
// the modern web-standard list. Pure data over `Color(hex:)`, no new machinery.
//
// (Ollin's `green`/`blue`/`red` above stay the pure additive primaries; for the
// CSS sense of a darker "green" reach for `darkGreen` or `forestGreen`.)
public extension Color {
    // Secondary & everyday
    static let yellow  = Color(hex: 0xFFFF00)
    static let cyan    = Color(hex: 0x00FFFF)
    static let magenta = Color(hex: 0xFF00FF)
    static let orange  = Color(hex: 0xFFA500)
    static let purple  = Color(hex: 0x800080)
    static let pink    = Color(hex: 0xFFC0CB)
    static let brown   = Color(hex: 0xA52A2A)

    // Warm
    static let crimson = Color(hex: 0xDC143C)
    static let tomato  = Color(hex: 0xFF6347)
    static let coral   = Color(hex: 0xFF7F50)
    static let salmon  = Color(hex: 0xFA8072)
    static let gold    = Color(hex: 0xFFD700)

    // Greens
    static let darkGreen   = Color(hex: 0x006400)
    static let forestGreen = Color(hex: 0x228B22)
    static let seaGreen    = Color(hex: 0x2E8B57)
    static let olive       = Color(hex: 0x808000)
    static let teal        = Color(hex: 0x008080)
    static let turquoise   = Color(hex: 0x40E0D0)

    // Blues
    static let navy      = Color(hex: 0x000080)
    static let royalBlue = Color(hex: 0x4169E1)
    static let steelBlue = Color(hex: 0x4682B4)
    static let skyBlue   = Color(hex: 0x87CEEB)
    static let indigo    = Color(hex: 0x4B0082)

    // Purples & pinks
    static let violet   = Color(hex: 0xEE82EE)
    static let orchid   = Color(hex: 0xDA70D6)
    static let plum     = Color(hex: 0xDDA0DD)
    static let lavender = Color(hex: 0xE6E6FA)
    static let maroon   = Color(hex: 0x800000)

    // Earth & neutral
    static let tan       = Color(hex: 0xD2B48C)
    static let khaki     = Color(hex: 0xF0E68C)
    static let beige     = Color(hex: 0xF5F5DC)
    static let ivory     = Color(hex: 0xFFFFF0)
    static let silver    = Color(hex: 0xC0C0C0)
    static let lightGray = Color(hex: 0xD3D3D3)
    static let darkGray  = Color(hex: 0xA9A9A9)
    static let slateGray = Color(hex: 0x708090)
}

// MARK: - Hex

public extension Color {
    /// Create a color from a 24-bit `0xRRGGBB` value: `Color(hex: 0xFF0066)`.
    ///
    /// The integer form for hex literals — compile-checked, nothing to parse,
    /// never optional. An integer carries no digit count (`0xFFF` and
    /// `0x000FFF` are the same value), so this form is always six digits of
    /// RGB and alpha rides as its own parameter; shorthand and RGBA digit
    /// forms belong to `init?(hex String:)`.
    init(hex: UInt32, alpha: Double = 1.0) {
        precondition(hex <= 0xFFFFFF,
                     "Color(hex:) takes a 24-bit 0xRRGGBB value; for alpha use the alpha: parameter")
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  alpha: alpha)
    }

    /// Create a color from a hex string: `"#RGB"`, `"#RGBA"`, `"#RRGGBB"`, or
    /// `"#RRGGBBAA"`. The leading `#` is optional and case doesn't matter.
    /// Returns `nil` for anything else, so a string from a file or the network
    /// fails cleanly instead of trapping.
    init?(hex: String) {
        var digits = Substring(hex)
        if digits.hasPrefix("#") { digits = digits.dropFirst() }
        let nibbles = digits.compactMap(\.hexDigitValue)
        guard nibbles.count == digits.count else { return nil }
        switch nibbles.count {
        case 3, 4:
            // Shorthand: each digit doubles, so F becomes FF (15 × 17 = 255).
            let c = nibbles.map { Double($0 * 17) / 255 }
            self.init(red: c[0], green: c[1], blue: c[2],
                      alpha: nibbles.count == 4 ? c[3] : 1)
        case 6, 8:
            let c = stride(from: 0, to: nibbles.count, by: 2)
                .map { Double(nibbles[$0] << 4 | nibbles[$0 + 1]) / 255 }
            self.init(red: c[0], green: c[1], blue: c[2],
                      alpha: nibbles.count == 8 ? c[3] : 1)
        default:
            return nil
        }
    }
}

// MARK: - Color temperature (blackbody)

public extension Color {
    /// Create a color from a blackbody **color temperature** in kelvin — the way a
    /// photographer or gaffer names light. Candlelight sits near `1900`, tungsten
    /// around `3200`, daylight `5600`, an overcast sky `7000`, deep shade `9000`+.
    /// Lower is warmer (orange), higher is cooler (blue), neutral white around `6600`.
    ///
    /// The result is an ordinary sRGB `Color`, so it drops straight into `fill`,
    /// `background`, or a `Light`'s color — which is what lets a lighting rig read as
    /// the temperatures it actually is (`Color(kelvin: 5600)` for a daylight key)
    /// rather than opaque RGB. `kelvin` clamps to `1000...40000`.
    init(kelvin: Double, alpha: Double = 1.0) {
        // Tanner Helland's piecewise approximation of the Planckian locus, scaled to
        // 0…1 sRGB (see the README's Techniques list). `t` is the temperature in
        // hundreds of kelvin; the clamp keeps the logs and powers in range.
        let t = min(max(kelvin, 1000), 40000) / 100
        func unit(_ v: Double) -> Double { min(max(v, 0), 255) / 255 }
        let r: Double
        let g: Double
        if t <= 66 {
            r = 255
            g = 99.4708025861 * log(t) - 161.1195681661
        } else {
            r = 329.698727446 * pow(t - 60, -0.1332047592)
            g = 288.1221695283 * pow(t - 60, -0.0755148492)
        }
        let b: Double
        if t >= 66 {
            b = 255
        } else if t <= 19 {
            b = 0
        } else {
            b = 138.5177312231 * log(t - 10) - 305.0447927307
        }
        self.init(red: unit(r), green: unit(g), blue: unit(b), alpha: alpha)
    }
}

// MARK: - Hue, saturation, brightness

public extension Color {
    /// Create a color from hue, saturation, and brightness, each in `0...1`.
    ///
    /// Hue wraps (1.2 reads as 0.2, −0.25 as 0.75), so it can run on `time`
    /// or any unbounded value without bookkeeping; saturation and brightness
    /// clamp to `0...1`.
    init(hue: Double, saturation: Double, brightness: Double, alpha: Double = 1.0) {
        let h = (hue - hue.rounded(.down)) * 6
        let s = min(max(saturation, 0), 1)
        let v = min(max(brightness, 0), 1)
        let sector = Int(h)
        let f = h - Double(sector)
        let p = v * (1 - s)
        let q = v * (1 - s * f)
        let t = v * (1 - s * (1 - f))
        switch sector {
        case 0: self.init(red: v, green: t, blue: p, alpha: alpha)
        case 1: self.init(red: q, green: v, blue: p, alpha: alpha)
        case 2: self.init(red: p, green: v, blue: t, alpha: alpha)
        case 3: self.init(red: p, green: q, blue: v, alpha: alpha)
        case 4: self.init(red: t, green: p, blue: v, alpha: alpha)
        default: self.init(red: v, green: p, blue: q, alpha: alpha)
        }
    }
}
