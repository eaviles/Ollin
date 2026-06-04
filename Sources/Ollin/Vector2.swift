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

    /// Squared length — cheaper than `length` when you only need to compare.
    public var lengthSquared: Double { x * x + y * y }

    /// This vector scaled to length 1, or `.zero` if it has no length.
    public var normalized: Vector2 {
        let len = length
        return len > 0 ? self / len : .zero
    }

    /// The angle from the positive x-axis, in radians (`atan2(y, x)`).
    public var angle: Double { atan2(y, x) }

    /// This vector turned 90° counter-clockwise (a left-hand normal).
    public var perpendicular: Vector2 { Vector2(-y, x) }
}

public extension Vector2 {
    /// A vector of the given `length` pointing at `angle` radians from the x-axis.
    init(angle: Double, length: Double = 1) {
        self.init(cos(angle) * length, sin(angle) * length)
    }
}

public extension Vector2 {
    static func + (a: Vector2, b: Vector2) -> Vector2 { Vector2(a.x + b.x, a.y + b.y) }
    static func - (a: Vector2, b: Vector2) -> Vector2 { Vector2(a.x - b.x, a.y - b.y) }
    static prefix func - (v: Vector2) -> Vector2 { Vector2(-v.x, -v.y) }
    static func * (v: Vector2, s: Double) -> Vector2 { Vector2(v.x * s, v.y * s) }
    static func * (s: Double, v: Vector2) -> Vector2 { Vector2(v.x * s, v.y * s) }
    static func / (v: Vector2, s: Double) -> Vector2 { Vector2(v.x / s, v.y / s) }

    static func += (a: inout Vector2, b: Vector2) { a = a + b }
    static func -= (a: inout Vector2, b: Vector2) { a = a - b }
    static func *= (v: inout Vector2, s: Double) { v = v * s }
    static func /= (v: inout Vector2, s: Double) { v = v / s }
}

public extension Vector2 {
    /// Dot product.
    func dot(_ other: Vector2) -> Double { x * other.x + y * other.y }

    /// 2D cross product (the z of the 3D cross): the signed parallelogram area.
    /// Positive when `other` lies counter-clockwise from `self`.
    func cross(_ other: Vector2) -> Double { x * other.y - y * other.x }

    /// Euclidean distance to `other`.
    func distance(to other: Vector2) -> Double { (self - other).length }

    /// Squared distance to `other` — cheaper for comparisons.
    func distanceSquared(to other: Vector2) -> Double { (self - other).lengthSquared }

    /// The signed angle from `self` to `other`, in radians (`-π…π`).
    func angle(to other: Vector2) -> Double { atan2(cross(other), dot(other)) }

    /// Linear interpolation toward `other` by `t` (`0` = self, `1` = other).
    func lerp(to other: Vector2, _ t: Double) -> Vector2 {
        Vector2(x + (other.x - x) * t, y + (other.y - y) * t)
    }

    /// This vector rotated by `angle` radians about the origin.
    func rotated(by angle: Double) -> Vector2 {
        let c = cos(angle), s = sin(angle)
        return Vector2(x * c - y * s, x * s + y * c)
    }

    /// This vector rotated by `angle` radians about `pivot`.
    func rotated(by angle: Double, around pivot: Vector2) -> Vector2 {
        (self - pivot).rotated(by: angle) + pivot
    }

    /// This vector clamped to at most `maxLength`, preserving direction.
    func limited(to maxLength: Double) -> Vector2 {
        let lsq = lengthSquared
        guard lsq > maxLength * maxLength, lsq > 0 else { return self }
        return self * (maxLength / lsq.squareRoot())
    }

    /// The component of this vector in the direction of `other` (vector projection).
    func projected(onto other: Vector2) -> Vector2 {
        let lsq = other.lengthSquared
        return lsq > 0 ? other * (dot(other) / lsq) : .zero
    }

    /// A copy with `x` replaced.
    func with(x newX: Double) -> Vector2 { Vector2(newX, y) }
    /// A copy with `y` replaced.
    func with(y newY: Double) -> Vector2 { Vector2(x, newY) }
}
