// The expander's own point: the arithmetic the stroke and fill geometry is
// written in, kept apart from the framework's `Vector2` so the same files
// compile for the web page's player part, where no framework exists. The
// operations mirror `Vector2`'s one for one (the length is the plain square
// root of the sum of squares), so a value passing through either reads the
// same bits.

/// A point or offset with `Double` components, in sketch points.
package struct Point2D: Equatable {
    package var x: Double
    package var y: Double

    @inlinable
    package init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    @inlinable
    package var length: Double { (x * x + y * y).squareRoot() }

    /// The point as the single-precision pair a vertex carries.
    @inlinable
    package var simd2: SIMD2<Float> { SIMD2<Float>(Float(x), Float(y)) }

    @inlinable
    package static func + (a: Point2D, b: Point2D) -> Point2D { Point2D(a.x + b.x, a.y + b.y) }
    @inlinable
    package static func - (a: Point2D, b: Point2D) -> Point2D { Point2D(a.x - b.x, a.y - b.y) }
    @inlinable
    package static func * (v: Point2D, s: Double) -> Point2D { Point2D(v.x * s, v.y * s) }
    @inlinable
    package static func / (v: Point2D, s: Double) -> Point2D { Point2D(v.x / s, v.y / s) }
}
