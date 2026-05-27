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
/// let c = Palette.rainbow.color(at: t)        // built-in sweep
/// let warm = Palette(a: (0.5, 0.5, 0.5), b: (0.5, 0.5, 0.5),
///                    c: (1.0, 1.0, 1.0), d: (0.0, 0.10, 0.20))
/// ```
public struct Palette: Sendable {
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

public extension Palette {
    /// A full, even hue sweep over `0...1` — Inigo Quilez's canonical palette.
    static let rainbow = Palette(a: (0.5, 0.5, 0.5),
                                 b: (0.5, 0.5, 0.5),
                                 c: (1.0, 1.0, 1.0),
                                 d: (0.0, 0.33, 0.67))
}
