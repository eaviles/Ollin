import Foundation

/// A 2D point or vector with `Double` components, in sketch points
/// (top-left origin, y-down).
///
/// `Vector2` is Ollin's geometry currency: the type primitives like
/// `drawPolyline` take, and the value you pass around, transform, and compose.
///
/// Most of what you call on one is the shared [`Vector`](Vector) surface, which
/// `Vector3` has too. What this file adds is the part that needs a plane: a
/// direction is a single `angle` here, there is exactly one `perpendicular`, a
/// turn needs no axis, and `cross` comes back as a `Double` rather than a vector.
public struct Vector2: Vector, Hashable, Codable {
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

    /// Squared length: cheaper than `length` when you only need to compare.
    public var lengthSquared: Double { x * x + y * y }

    /// The angle from the positive x-axis, in radians (`atan2(y, x)`).
    ///
    /// A direction in the plane is one number, which is why this is 2D's own. In
    /// space it takes two, so `Vector3` has no `angle`.
    public var angle: Double { atan2(y, x) }

    /// This vector turned 90 degrees counter-clockwise (a left-hand normal).
    ///
    /// Unique to the plane: in space a vector has a whole disc of perpendiculars
    /// and you pick one with `cross`.
    public var perpendicular: Vector2 { Vector2(-y, x) }
}

public extension Vector2 {
    /// A vector of the given `length` pointing at `angle` radians from the x-axis.
    init(angle: Double, length: Double = 1) {
        self.init(cos(angle) * length, sin(angle) * length)
    }
}

public extension Vector2 {
    /// Component-wise sum.
    static func + (a: Vector2, b: Vector2) -> Vector2 { Vector2(a.x + b.x, a.y + b.y) }
    /// Component-wise difference.
    static func - (a: Vector2, b: Vector2) -> Vector2 { Vector2(a.x - b.x, a.y - b.y) }
    /// Negation (the opposite vector).
    static prefix func - (v: Vector2) -> Vector2 { Vector2(-v.x, -v.y) }
    /// Scale by a scalar.
    static func * (v: Vector2, s: Double) -> Vector2 { Vector2(v.x * s, v.y * s) }
    /// Divide each component by a scalar.
    static func / (v: Vector2, s: Double) -> Vector2 { Vector2(v.x / s, v.y / s) }
}

public extension Vector2 {
    /// Dot product.
    func dot(_ other: Vector2) -> Double { x * other.x + y * other.y }

    /// 2D cross product (the z of the 3D cross): the signed parallelogram area.
    /// Positive when `other` lies counter-clockwise from `self`.
    ///
    /// This is where the two vector types part. A cross in the plane has nowhere
    /// perpendicular to point, so what survives is the signed magnitude, one
    /// number answering "which side?". `Vector3.cross(_:)` returns the
    /// perpendicular vector instead.
    func cross(_ other: Vector2) -> Double { x * other.y - y * other.x }

    /// The signed angle from `self` to `other`, in radians (`-π…π`).
    ///
    /// Signed only because the plane has two turn directions. In space there is
    /// no sign without an axis to measure it against.
    func angle(to other: Vector2) -> Double { atan2(cross(other), dot(other)) }

    /// This vector rotated by `angle` radians about the origin.
    func rotated(by angle: Double) -> Vector2 {
        let c = cos(angle), s = sin(angle)
        return Vector2(x * c - y * s, x * s + y * c)
    }

    /// This vector rotated by `angle` radians about `pivot`.
    func rotated(by angle: Double, around pivot: Vector2) -> Vector2 {
        (self - pivot).rotated(by: angle) + pivot
    }

    /// A copy with `x` replaced.
    func with(x newX: Double) -> Vector2 { Vector2(newX, y) }
    /// A copy with `y` replaced.
    func with(y newY: Double) -> Vector2 { Vector2(x, newY) }
}
