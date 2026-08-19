import Foundation

/// A discrete set of colors carried as a unit — a handful of swatches you
/// index into, step through, or ramp.
///
/// `palette[i]` wraps, so driving it with `frameCount` or any counter just
/// cycles; `color(at:)` quantizes `0...1` into equal bands (a noise value
/// picks a swatch); `ramp(in:)` turns the set into a smooth interpolating
/// `Ramp`.
///
/// Build one by hand, from a harmony (computed in OKLCH so the steps come
/// out perceptually even), or start from a built-in set:
///
/// ```swift
/// let p = Palette(.red, Color(hex: 0x1B9E77), .white)
/// let h = Palette.analogous(of: brand, count: 5)
/// fill(Palette.set2[frameCount / 60])
/// ```
public struct Palette: Equatable, Sendable {
    public var colors: [Color]

    public init(_ colors: [Color]) {
        self.colors = colors
    }

    public init(_ colors: Color...) {
        self.init(colors)
    }

    public var count: Int { colors.count }

    /// The color at `index`, wrapping in both directions — `palette[-1]` is
    /// the last color. An empty palette reads `.clear`.
    public subscript(index: Int) -> Color {
        guard !colors.isEmpty else { return .clear }
        let i = index % colors.count
        return colors[i < 0 ? i + colors.count : i]
    }

    /// The color whose band contains `t`: `0...1` splits into `count` equal
    /// steps (`t` clamps, an empty palette reads `.clear`).
    public func color(at t: Double) -> Color {
        guard !colors.isEmpty else { return .clear }
        let clamped = min(max(t, 0), 1)
        return colors[min(Int(clamped * Double(colors.count)), colors.count - 1)]
    }

    /// The palette as a smooth gradient: the colors spread evenly over
    /// `0...1` and interpolate in `space`.
    public func ramp(in space: ColorSpace = .oklab) -> Ramp {
        Ramp(colors, in: space)
    }
}

// MARK: - Harmonies

// Each builder rotates hue in OKLCH at the base color's lightness and
// chroma, so the companions genuinely read as the same weight. A rotated
// hue can support less chroma than the base; conversion maps it back in.
public extension Palette {
    /// The base and its opposite on the hue wheel.
    static func complementary(of base: Color) -> Palette {
        Palette(rotations(of: base, by: [0, 0.5]))
    }

    /// The base and the two hues flanking its complement, `spread` turns to
    /// either side.
    static func splitComplementary(of base: Color, spread: Double = 1.0 / 12) -> Palette {
        Palette(rotations(of: base, by: [0, 0.5 - spread, 0.5 + spread]))
    }

    /// The base and the two hues that split the wheel in thirds with it.
    static func triadic(of base: Color) -> Palette {
        Palette(rotations(of: base, by: [0, 1.0 / 3, 2.0 / 3]))
    }

    /// `count` neighboring hues centered on the base, `spread` turns apart.
    static func analogous(of base: Color, count: Int = 3, spread: Double = 1.0 / 12) -> Palette {
        guard count > 0 else { return Palette([]) }
        let offsets = (0..<count).map { (Double($0) - Double(count - 1) / 2) * spread }
        return Palette(rotations(of: base, by: offsets))
    }

    private static func rotations(of base: Color, by offsets: [Double]) -> [Color] {
        let lch = OKLCH(base)
        return offsets.map {
            $0 == 0 ? base : Color(OKLCH(l: lch.l, c: lch.c, h: lch.h + $0), alpha: base.alpha)
        }
    }
}

// MARK: - Built-in sets

// The eight ColorBrewer qualitative palettes (Cynthia Brewer, Mark Harrower,
// and The Pennsylvania State University; Apache-2.0), carried as data and
// credited in the README's Techniques list.
public extension Palette {
    /// Eight saturated mid-tones with a pastel pair up front.
    static let accent = Palette(Color(hex: 0x7FC97F), Color(hex: 0xBEAED4),
                                Color(hex: 0xFDC086), Color(hex: 0xFFFF99),
                                Color(hex: 0x386CB0), Color(hex: 0xF0027F),
                                Color(hex: 0xBF5B17), Color(hex: 0x666666))

    /// Eight dark, saturated tones.
    static let dark2 = Palette(Color(hex: 0x1B9E77), Color(hex: 0xD95F02),
                               Color(hex: 0x7570B3), Color(hex: 0xE7298A),
                               Color(hex: 0x66A61E), Color(hex: 0xE6AB02),
                               Color(hex: 0xA6761D), Color(hex: 0x666666))

    /// Twelve colors in light/dark pairs.
    static let paired = Palette(Color(hex: 0xA6CEE3), Color(hex: 0x1F78B4),
                                Color(hex: 0xB2DF8A), Color(hex: 0x33A02C),
                                Color(hex: 0xFB9A99), Color(hex: 0xE31A1C),
                                Color(hex: 0xFDBF6F), Color(hex: 0xFF7F00),
                                Color(hex: 0xCAB2D6), Color(hex: 0x6A3D9A),
                                Color(hex: 0xFFFF99), Color(hex: 0xB15928))

    /// Nine soft pastels.
    static let pastel1 = Palette(Color(hex: 0xFBB4AE), Color(hex: 0xB3CDE3),
                                 Color(hex: 0xCCEBC5), Color(hex: 0xDECBE4),
                                 Color(hex: 0xFED9A6), Color(hex: 0xFFFFCC),
                                 Color(hex: 0xE5D8BD), Color(hex: 0xFDDAEC),
                                 Color(hex: 0xF2F2F2))

    /// Eight muted pastels.
    static let pastel2 = Palette(Color(hex: 0xB3E2CD), Color(hex: 0xFDCDAC),
                                 Color(hex: 0xCBD5E8), Color(hex: 0xF4CAE4),
                                 Color(hex: 0xE6F5C9), Color(hex: 0xFFF2AE),
                                 Color(hex: 0xF1E2CC), Color(hex: 0xCCCCCC))

    /// Nine bold primaries — the classic categorical set.
    static let set1 = Palette(Color(hex: 0xE41A1C), Color(hex: 0x377EB8),
                              Color(hex: 0x4DAF4A), Color(hex: 0x984EA3),
                              Color(hex: 0xFF7F00), Color(hex: 0xFFFF33),
                              Color(hex: 0xA65628), Color(hex: 0xF781BF),
                              Color(hex: 0x999999))

    /// Eight medium tones, softer than `set1`.
    static let set2 = Palette(Color(hex: 0x66C2A5), Color(hex: 0xFC8D62),
                              Color(hex: 0x8DA0CB), Color(hex: 0xE78AC3),
                              Color(hex: 0xA6D854), Color(hex: 0xFFD92F),
                              Color(hex: 0xE5C494), Color(hex: 0xB3B3B3))

    /// Twelve light mid-tones.
    static let set3 = Palette(Color(hex: 0x8DD3C7), Color(hex: 0xFFFFB3),
                              Color(hex: 0xBEBADA), Color(hex: 0xFB8072),
                              Color(hex: 0x80B1D3), Color(hex: 0xFDB462),
                              Color(hex: 0xB3DE69), Color(hex: 0xFCCDE5),
                              Color(hex: 0xD9D9D9), Color(hex: 0xBC80BD),
                              Color(hex: 0xCCEBC5), Color(hex: 0xFFED6F))
}
