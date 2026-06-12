import Foundation

/// A 3D point or vector with `Double` components.
///
/// Ollin draws in 2D, but some values live in space — a body joint in meters,
/// a point of a depth cloud. `Vector3` carries those: `Vector2`'s arithmetic
/// with a `z`, plus `xy` to project back onto the canvas plane. Axis meaning
/// (which way is up, where the origin sits) belongs to whatever produced the
/// value, so check the producer's documentation.
public struct Vector3: Equatable, Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    /// The origin, `(0, 0, 0)`.
    public static let zero = Vector3(0, 0, 0)
    /// `(1, 1, 1)`.
    public static let one = Vector3(1, 1, 1)
    /// The x-axis unit vector, `(1, 0, 0)`.
    public static let unitX = Vector3(1, 0, 0)
    /// The y-axis unit vector, `(0, 1, 0)`.
    public static let unitY = Vector3(0, 1, 0)
    /// The z-axis unit vector, `(0, 0, 1)`.
    public static let unitZ = Vector3(0, 0, 1)

    /// Euclidean length (distance from the origin).
    public var length: Double { (x * x + y * y + z * z).squareRoot() }

    /// Squared length — cheaper than `length` when you only need to compare.
    public var lengthSquared: Double { x * x + y * y + z * z }

    /// This vector scaled to length 1, or `.zero` if it has no length.
    public var normalized: Vector3 {
        let len = length
        return len > 0 ? self / len : .zero
    }

    /// The `(x, y)` components as a `Vector2` — the drop-the-depth projection
    /// onto the canvas plane.
    public var xy: Vector2 { Vector2(x, y) }
}

public extension Vector3 {
    /// Component-wise sum.
    static func + (a: Vector3, b: Vector3) -> Vector3 { Vector3(a.x + b.x, a.y + b.y, a.z + b.z) }
    /// Component-wise difference.
    static func - (a: Vector3, b: Vector3) -> Vector3 { Vector3(a.x - b.x, a.y - b.y, a.z - b.z) }
    /// Negation (the opposite vector).
    static prefix func - (v: Vector3) -> Vector3 { Vector3(-v.x, -v.y, -v.z) }
    /// Scale by a scalar.
    static func * (v: Vector3, s: Double) -> Vector3 { Vector3(v.x * s, v.y * s, v.z * s) }
    /// Scale by a scalar.
    static func * (s: Double, v: Vector3) -> Vector3 { Vector3(v.x * s, v.y * s, v.z * s) }
    /// Divide each component by a scalar.
    static func / (v: Vector3, s: Double) -> Vector3 { Vector3(v.x / s, v.y / s, v.z / s) }

    /// Add `b` in place (the `pos += vel` idiom).
    static func += (a: inout Vector3, b: Vector3) { a = a + b }
    /// Subtract `b` in place.
    static func -= (a: inout Vector3, b: Vector3) { a = a - b }
    /// Scale in place.
    static func *= (v: inout Vector3, s: Double) { v = v * s }
    /// Divide in place.
    static func /= (v: inout Vector3, s: Double) { v = v / s }
}

public extension Vector3 {
    /// Dot product.
    func dot(_ other: Vector3) -> Double { x * other.x + y * other.y + z * other.z }

    /// Cross product: the vector perpendicular to both, with length the area of
    /// their parallelogram.
    func cross(_ other: Vector3) -> Vector3 {
        Vector3(y * other.z - z * other.y,
                z * other.x - x * other.z,
                x * other.y - y * other.x)
    }

    /// Euclidean distance to `other`.
    func distance(to other: Vector3) -> Double { (self - other).length }

    /// Squared distance to `other` — cheaper for comparisons.
    func distanceSquared(to other: Vector3) -> Double { (self - other).lengthSquared }

    /// Linear interpolation toward `other` by `t` (`0` = self, `1` = other).
    func lerp(to other: Vector3, _ t: Double) -> Vector3 {
        Vector3(x + (other.x - x) * t, y + (other.y - y) * t, z + (other.z - z) * t)
    }

    /// This vector clamped to at most `maxLength`, preserving direction.
    func limited(to maxLength: Double) -> Vector3 {
        let lsq = lengthSquared
        guard lsq > maxLength * maxLength, lsq > 0 else { return self }
        return self * (maxLength / lsq.squareRoot())
    }

    /// The component of this vector in the direction of `other` (vector projection).
    func projected(onto other: Vector3) -> Vector3 {
        let lsq = other.lengthSquared
        return lsq > 0 ? other * (dot(other) / lsq) : .zero
    }

    /// A copy with `x` replaced.
    func with(x newX: Double) -> Vector3 { Vector3(newX, y, z) }
    /// A copy with `y` replaced.
    func with(y newY: Double) -> Vector3 { Vector3(x, newY, z) }
    /// A copy with `z` replaced.
    func with(z newZ: Double) -> Vector3 { Vector3(x, y, newZ) }
}
