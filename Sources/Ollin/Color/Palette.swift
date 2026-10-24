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
        // Qualified: `Collection` puts `min()`/`max()` on the palette itself,
        // which shadows the global two-argument forms inside this type.
        let clamped = Swift.min(Swift.max(t, 0), 1)
        return colors[Swift.min(Int(clamped * Double(colors.count)), colors.count - 1)]
    }

    /// The palette as a smooth gradient: the colors spread evenly over
    /// `0...1` and interpolate in `space`.
    public func ramp(in space: ColorSpace = .oklab) -> Ramp {
        Ramp(colors, in: space)
    }
}

/// A palette is a set of colors in order, so it reads as one: `for color in
/// palette`, `palette.enumerated()`, `map`, `first`, `isEmpty`, `reversed()`,
/// `Array(palette)`, and `palette.randomElement(using: &randomness)` all work
/// without reaching for `colors`.
///
/// The wrapping `palette[i]` above is the one thing that goes further than a
/// collection's own subscript, and it still answers the same color for every
/// index a collection asks about, so iterating stays inside the set. Reading
/// only: a wrapping index makes a setter ambiguous (`palette[-1] = x` could
/// mean the last color or a mistake), so a change goes through `colors`.
extension Palette: RandomAccessCollection {
    public var startIndex: Int { 0 }
    public var endIndex: Int { colors.count }
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

// MARK: - Schemes

public extension Palette {
    /// A way of building a palette around one hue (see `scheme(_:key:count:jitter:seed:)`).
    enum Scheme: Hashable, Sendable {
        /// Every color the key's hue: the first at its most vivid point
        /// (`Color.mostVivid(hue:)`), the rest dividing the lightness range
        /// from deep to light.
        case monochrome
        /// Hues spaced evenly around the wheel from the key: the half nearest
        /// the key vivid, each hue at the lightness where its color word is most
        /// typical, and the far half dark.
        case vividAndDark
        /// Hues spaced evenly around the wheel from the key, every one vivid
        /// at its typical lightness.
        case vivid
        /// Hues gathered close around the key, light and soft.
        case pastel
        /// Hues gathered close around the key, deep.
        case dark
    }

    /// A palette of `count` colors built around `key`'s hue (its OKLCH hue; a
    /// gray reads as hue 0, a red) by `scheme`, worked out in OKLCH so steps
    /// of lightness and hue read evenly.
    ///
    /// ```swift
    /// let tones = Palette.scheme(.monochrome, key: Color(hex: 0xC8553D))
    /// let wheel = Palette.scheme(.vividAndDark, key: .blue, count: 6, jitter: 0.5, seed: 3)
    /// ```
    ///
    /// The vivid colors take a lightness Ollin sets per hue, near where the
    /// hue's color word is most typical (yellow light; red, green, and cyan in
    /// the middle; blue and purple deep), at the largest chroma the screen
    /// shows there. `jitter` (`0` exact to `1`) nudges each color's lightness,
    /// chroma, and (except in a monochrome palette) hue by a small amount the
    /// `seed` picks, so two seeds give two related palettes.
    static func scheme(_ scheme: Scheme, key: Color, count: Int = 5, jitter: Double = 0,
                       seed: Int = 0) -> Palette {
        guard count > 0 else { return Palette([]) }
        let hue = OKLCH(key).h
        let n = Double(count)
        var colors: [OKLCH] = []
        switch scheme {
        case .monochrome:
            // Lightness spread over the range; the slot nearest the hue's most
            // vivid point becomes that point and moves to the front.
            let cusp = gamutCusp(hue: hue)
            var levels = (0..<count).map { i in count == 1 ? cusp.l : 0.22 + 0.74 * Double(i) / (n - 1) }
            let nearest = levels.indices.min { abs(levels[$0] - cusp.l) < abs(levels[$1] - cusp.l) } ?? 0
            levels.remove(at: nearest)
            colors.append(OKLCH(l: cusp.l, c: cusp.c, h: hue))
            for l in levels { colors.append(OKLCH(l: l, c: maxChroma(lightness: l, hue: hue) * 0.92, h: hue)) }
        case .vividAndDark, .vivid:
            for i in 0..<count {
                let h = hue + Double(i) / n
                let around = Swift.min(Double(i), n - Double(i)) / n
                if scheme == .vividAndDark, around > 0.25 + 1e-9 {
                    let l = Palette.darkLightness
                    colors.append(OKLCH(l: l, c: maxChroma(lightness: l, hue: h) * 0.85, h: h))
                } else {
                    let l = Palette.typicalLightness(hue: h)
                    colors.append(OKLCH(l: l, c: maxChroma(lightness: l, hue: h), h: h))
                }
            }
        case .pastel, .dark:
            for i in 0..<count {
                let offset = count == 1 ? 0 : (Double(i) / (n - 1) - 0.5) * 0.16
                let h = hue + offset
                let step = count == 1 ? 0.5 : Double(i) / (n - 1)
                if scheme == .pastel {
                    let l = 0.82 + 0.1 * (1 - abs(step - 0.5) * 2)
                    colors.append(OKLCH(l: l, c: Swift.min(0.075, maxChroma(lightness: l, hue: h)), h: h))
                } else {
                    let l = 0.2 + 0.16 * (1 - abs(step - 0.5) * 2)
                    colors.append(OKLCH(l: l, c: maxChroma(lightness: l, hue: h) * 0.8, h: h))
                }
            }
        }
        let amount = Swift.min(Swift.max(jitter, 0), 1)
        if amount > 0 {
            var rng = SplitMix64(seed: UInt64(bitPattern: Int64(seed)) &+ 0x5EED_CAFE)
            func unit() -> Double { Double(rng.next() >> 11) / Double(1 << 53) * 2 - 1 }
            colors = colors.map { c in
                let dh = unit(), dl = unit(), dc = unit()
                let h = scheme == .monochrome ? c.h : c.h + dh * 0.03 * amount
                let l = Swift.min(Swift.max(c.l + dl * 0.05 * amount, 0.05), 0.98)
                let chroma = Swift.min(c.c * (1 + dc * 0.15 * amount), maxChroma(lightness: l, hue: h))
                return OKLCH(l: l, c: Swift.max(chroma, 0), h: h)
            }
        }
        return Palette(colors.map { Color($0) })
    }

    /// The lightness the dark half of a vivid-and-dark wheel takes.
    internal static let darkLightness = 0.3

    /// The lightness a vivid hue takes: Ollin's own table of where each color
    /// word's hue looks most typical, read around the wheel and blended between
    /// neighbors so the lightness never jumps. Hues are OKLCH turns.
    internal static func typicalLightness(hue: Double) -> Double {
        let table: [(hue: Double, lightness: Double)] = [
            (25.0 / 360, 0.58),    // red
            (60.0 / 360, 0.72),    // orange
            (105.0 / 360, 0.9),    // yellow
            (145.0 / 360, 0.66),   // green
            (195.0 / 360, 0.72),   // cyan
            (255.0 / 360, 0.5),    // blue
            (300.0 / 360, 0.46),   // purple
            (345.0 / 360, 0.62),   // pink and magenta
        ]
        let h = hue - hue.rounded(.down)
        for i in table.indices {
            let a = table[i], b = table[(i + 1) % table.count]
            var span = b.hue - a.hue
            if span <= 0 { span += 1 }
            var t = h - a.hue
            if t < 0 { t += 1 }
            if t <= span { return a.lightness + (b.lightness - a.lightness) * (t / span) }
        }
        return 0.6
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
