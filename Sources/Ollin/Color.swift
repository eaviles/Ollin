import Foundation

/// An RGBA color with floating-point components in the range `0...1`.
///
/// `Color` is intentionally tiny and dependency-free (Foundation only). The
/// renderer converts it to the GPU-friendly representations it needs (a
/// `SIMD4<Float>` vertex color, or an `MTLClearColor` for `background`).
public struct Color: Equatable, Sendable {
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

// A few familiar named constants so `.white` / `.black` Just Work.
public extension Color {
    static let white = Color(white: 1)
    static let black = Color(white: 0)
    static let gray  = Color(white: 0.5)
    static let clear = Color(red: 0, green: 0, blue: 0, alpha: 0)
    static let red   = Color(red: 1, green: 0, blue: 0)
    static let green = Color(red: 0, green: 1, blue: 0)
    static let blue  = Color(red: 0, green: 0, blue: 1)
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
