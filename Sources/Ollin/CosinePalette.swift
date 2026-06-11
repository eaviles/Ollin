import Foundation

/// A cyclic color gradient from a cosine formula: each channel is
/// `a + b · cos(2π · (c · t + d))`. Four `(r, g, b)` coefficient triples shape
/// it — `a` sets the center, `b` the amplitude, `c` the frequency, and `d` the
/// per-channel phase. It's a tiny, dependency-free way to turn a single number
/// into pleasing, continuously-cycling color.
///
/// The technique is Inigo Quilez's; see https://iquilezles.org/articles/palettes/.
///
/// ```swift
/// let c = CosinePalette.rainbow.color(at: t)        // built-in sweep
/// let warm = CosinePalette(a: (0.5, 0.5, 0.5), b: (0.5, 0.5, 0.5),
///                    c: (1.0, 1.0, 1.0), d: (0.0, 0.10, 0.20))
/// ```
public struct CosinePalette: Sendable {
    /// An `(r, g, b)` coefficient triple.
    public typealias RGB = (r: Double, g: Double, b: Double)

    public var a: RGB
    public var b: RGB
    public var c: RGB
    public var d: RGB

    public init(a: RGB, b: RGB, c: RGB, d: RGB) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
    }

    /// The color at parameter `t`. The gradient cycles, so for the default
    /// coefficients `t = 0` and `t = 1` meet; any value of `t` is valid.
    /// Channels are clamped to `0...1`.
    public func color(at t: Double) -> Color {
        func channel(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
            let value = a + b * cos(2 * .pi * (c * t + d))
            return Swift.max(0, Swift.min(1, value))
        }
        return Color(red: channel(a.r, b.r, c.r, d.r),
                     green: channel(a.g, b.g, c.g, d.g),
                     blue: channel(a.b, b.b, c.b, d.b))
    }
}

// Inigo Quilez's seven example palettes, named for how each one reads.
public extension CosinePalette {
    /// A full, even hue sweep over `0...1`.
    static let rainbow = CosinePalette(a: (0.5, 0.5, 0.5), b: (0.5, 0.5, 0.5),
                                 c: (1.0, 1.0, 1.0), d: (0.0, 0.33, 0.67))

    /// Warm cream and amber, through a dark middle, to cool blue.
    static let dusk = CosinePalette(a: (0.5, 0.5, 0.5), b: (0.5, 0.5, 0.5),
                              c: (1.0, 1.0, 1.0), d: (0.0, 0.10, 0.20))

    /// Soft rose and pink framed by teal.
    static let blush = CosinePalette(a: (0.5, 0.5, 0.5), b: (0.5, 0.5, 0.5),
                               c: (1.0, 1.0, 1.0), d: (0.3, 0.20, 0.20))

    /// Sunny gold-yellow easing into greens.
    static let meadow = CosinePalette(a: (0.5, 0.5, 0.5), b: (0.5, 0.5, 0.5),
                                c: (1.0, 1.0, 0.5), d: (0.8, 0.90, 0.30))

    /// Peach and salmon through mauve to gold.
    static let sunset = CosinePalette(a: (0.5, 0.5, 0.5), b: (0.5, 0.5, 0.5),
                                c: (1.0, 0.7, 0.4), d: (0.0, 0.15, 0.20))

    /// Vivid, high-saturation magenta, teal, and yellow.
    static let neon = CosinePalette(a: (0.5, 0.5, 0.5), b: (0.5, 0.5, 0.5),
                              c: (2.0, 1.0, 0.0), d: (0.5, 0.20, 0.25))

    /// Coral-red to mint-green, soft like watermelon.
    static let melon = CosinePalette(a: (0.8, 0.5, 0.4), b: (0.2, 0.4, 0.2),
                               c: (2.0, 1.0, 1.0), d: (0.0, 0.25, 0.25))
}
