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
