import Foundation

/// A 3D point or vector with `Double` components.
///
/// Ollin draws in 2D, but some values live in space: a body joint in meters, a
/// point of a depth cloud. `Vector3` carries those.
///
/// Most of what you call on one is the shared [`Vector`](Vector) surface, which
/// `Vector2` has too. What this file adds is the part that needs a third
/// dimension: `unitZ`, a `cross` that comes back as a vector, and `xy` to drop
/// the depth and land back on the canvas plane. Axis meaning (which way is up,
/// where the origin sits) belongs to whatever produced the value, so check the
/// producer's documentation.
public struct Vector3: Vector, Hashable, Codable {
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

    /// Squared length: cheaper than `length` when you only need to compare.
    public var lengthSquared: Double { x * x + y * y + z * z }

    /// The `(x, y)` components as a `Vector2`: the drop-the-depth projection
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
    /// Divide each component by a scalar.
    static func / (v: Vector3, s: Double) -> Vector3 { Vector3(v.x / s, v.y / s, v.z / s) }
}

public extension Vector3 {
    /// Dot product.
    func dot(_ other: Vector3) -> Double { x * other.x + y * other.y + z * other.z }

    /// Cross product: the vector perpendicular to both, with length the area of
    /// their parallelogram.
    ///
    /// This is where the two vector types part. In space there is somewhere
    /// perpendicular to point, so the answer is a direction: a surface normal, a
    /// frame's third axis, a torque. `Vector2.cross(_:)` keeps only the signed
    /// magnitude, one number answering "which side?".
    func cross(_ other: Vector3) -> Vector3 {
        Vector3(y * other.z - z * other.y,
                z * other.x - x * other.z,
                x * other.y - y * other.x)
    }

    /// A copy with `x` replaced.
    func with(x newX: Double) -> Vector3 { Vector3(newX, y, z) }
    /// A copy with `y` replaced.
    func with(y newY: Double) -> Vector3 { Vector3(x, newY, z) }
    /// A copy with `z` replaced.
    func with(z newZ: Double) -> Vector3 { Vector3(x, y, newZ) }
}
