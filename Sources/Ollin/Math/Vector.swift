import Foundation

/// The surface `Vector2` and `Vector3` share: the constants, the arithmetic, the
/// measurements, and the ways of making a new vector that mean the same thing
/// however many dimensions you are in.
///
/// It is written once here, so the two types cannot drift apart, and so you can
/// write a helper that takes either:
///
/// ```swift
/// func midpoint<V: Vector>(_ a: V, _ b: V) -> V { a.lerp(to: b, 0.5) }
///
/// midpoint(Vector2(0, 0), Vector2(10, 4))          // Vector2(5, 2)
/// midpoint(Vector3(0, 0, 0), Vector3(10, 4, 2))    // Vector3(5, 2, 1)
/// ```
///
/// What each type declares on its own is what does *not* generalize. The one to
/// know is `cross`: in 2D it is a `Double`, the signed area of the parallelogram
/// two vectors span, which answers "is that to my left or my right?"; in 3D it
/// is a `Vector3` perpendicular to both, which is how you get a surface normal
/// or a frame. Same name, same geometry underneath, different kind of answer.
/// `Vector2` also keeps the members that need a plane to mean anything (`angle`,
/// `perpendicular`, the signed `angle(to:)`, `rotated(by:)`, and the polar
/// initializer), and `Vector3` adds `unitZ` and `xy`.
public protocol Vector: Equatable, Sendable {
    /// The origin: every component `0`.
    static var zero: Self { get }
    /// Every component `1`.
    static var one: Self { get }
    /// The x-axis unit vector.
    static var unitX: Self { get }
    /// The y-axis unit vector.
    static var unitY: Self { get }

    /// Squared length: cheaper than `length` when you only need to compare.
    var lengthSquared: Double { get }

    /// Dot product: the sum of the component products, which is also
    /// `|a| * |b| * cos θ`. One number saying how much the two point the same
    /// way, positive under 90 degrees and negative past it.
    func dot(_ other: Self) -> Double

    /// A copy with `x` replaced.
    func with(x newX: Double) -> Self
    /// A copy with `y` replaced.
    func with(y newY: Double) -> Self

    /// Component-wise sum.
    static func + (a: Self, b: Self) -> Self
    /// Component-wise difference.
    static func - (a: Self, b: Self) -> Self
    /// Negation (the opposite vector).
    static prefix func - (v: Self) -> Self
    /// Scale by a scalar.
    static func * (v: Self, s: Double) -> Self
    /// Divide each component by a scalar.
    static func / (v: Self, s: Double) -> Self
}

// Everything below is `@inlinable` on purpose. A sketch calls these from its own
// module, where a generic body that cannot be specialized costs about two thirds
// again on a steering loop (measured); inlining puts it back to the speed of a
// hand-written concrete method.
public extension Vector {
    /// Euclidean length (distance from the origin).
    @inlinable
    var length: Double { lengthSquared.squareRoot() }

    /// This vector scaled to length 1, or `.zero` if it has no length.
    @inlinable
    var normalized: Self {
        let len = length
        return len > 0 ? self / len : .zero
    }

    /// Scale by a scalar.
    @inlinable
    static func * (s: Double, v: Self) -> Self { v * s }

    /// Add `b` in place (the `pos += vel` idiom).
    @inlinable
    static func += (a: inout Self, b: Self) { a = a + b }
    /// Subtract `b` in place.
    @inlinable
    static func -= (a: inout Self, b: Self) { a = a - b }
    /// Scale in place.
    @inlinable
    static func *= (v: inout Self, s: Double) { v = v * s }
    /// Divide in place.
    @inlinable
    static func /= (v: inout Self, s: Double) { v = v / s }

    /// Euclidean distance to `other`.
    @inlinable
    func distance(to other: Self) -> Double { (self - other).length }

    /// Squared distance to `other`: cheaper for comparisons.
    @inlinable
    func distanceSquared(to other: Self) -> Double { (self - other).lengthSquared }

    /// Linear interpolation toward `other` by `t` (`0` = self, `1` = other).
    @inlinable
    func lerp(to other: Self, _ t: Double) -> Self { self + (other - self) * t }

    /// This vector clamped to at most `maxLength`, preserving direction.
    @inlinable
    func limited(to maxLength: Double) -> Self {
        let lsq = lengthSquared
        guard lsq > maxLength * maxLength, lsq > 0 else { return self }
        return self * (maxLength / lsq.squareRoot())
    }

    /// The component of this vector in the direction of `other` (vector projection).
    @inlinable
    func projected(onto other: Self) -> Self {
        let lsq = other.lengthSquared
        return lsq > 0 ? other * (dot(other) / lsq) : .zero
    }
}

public extension Collection where Element: Vector {
    /// The centroid (arithmetic mean) of the points, or `nil` when empty.
    ///
    /// This is the mean of the points *themselves*: where vertices crowd, the
    /// centroid is pulled toward them, so for a polygon outline it is not the
    /// same as the area's center of mass.
    @inlinable
    var centroid: Element? {
        guard !isEmpty else { return nil }
        return reduce(Element.zero, +) / Double(count)
    }
}
