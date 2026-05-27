import Foundation

/// A 2D point or vector with `Double` components, in sketch points
/// (top-left origin, y-down).
///
/// `Vector2` is Ollin's geometry currency — the type primitives like
/// `polyline` take, and the value you pass around, transform, and compose.
public struct Vector2: Equatable, Hashable, Sendable {
    public let x: Double
    public let y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// The origin, `(0, 0)`.
    public static let zero = Vector2(0, 0)
    /// `(1, 1)`.
    public static let one = Vector2(1, 1)
    /// The x-axis unit vector, `(1, 0)`.
    public static let unitX = Vector2(1, 0)
    /// The y-axis unit vector, `(0, 1)`.
    public static let unitY = Vector2(0, 1)

    /// Euclidean length (distance from the origin).
    public var length: Double { (x * x + y * y).squareRoot() }

    /// This vector scaled to length 1, or `.zero` if it has no length.
    public var normalized: Vector2 {
        let len = length
        return len > 0 ? self / len : .zero
    }
}

public extension Vector2 {
    static func + (a: Vector2, b: Vector2) -> Vector2 { Vector2(a.x + b.x, a.y + b.y) }
    static func - (a: Vector2, b: Vector2) -> Vector2 { Vector2(a.x - b.x, a.y - b.y) }
    static prefix func - (v: Vector2) -> Vector2 { Vector2(-v.x, -v.y) }
    static func * (v: Vector2, s: Double) -> Vector2 { Vector2(v.x * s, v.y * s) }
    static func * (s: Double, v: Vector2) -> Vector2 { Vector2(v.x * s, v.y * s) }
    static func / (v: Vector2, s: Double) -> Vector2 { Vector2(v.x / s, v.y / s) }
}
