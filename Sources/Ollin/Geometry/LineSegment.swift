import Foundation

/// A straight piece of line between two points, in sketch points: the typed
/// value behind `drawLine(_:_:)`, as `Circle` is behind `drawCircle(_:)`.
///
/// ```swift
/// let edge = LineSegment(Vector2(100, 900), Vector2(980, 160))
/// drawLine(edge)
/// for hit in edge.crossings(with: Circle(center: center, radius: 200)) {
///     drawCircle(center: hit, radius: 6)
/// }
/// ```
///
/// A segment has two ends and a length. The line through a point in a
/// direction, with no ends, is `Ray2`.
public struct LineSegment: Equatable, Hashable, Sendable, Codable, PlaneCurve {
    public let start: Vector2
    public let end: Vector2

    public init(_ start: Vector2, _ end: Vector2) {
        self.start = start
        self.end = end
    }

    /// Build from bare `x1, y1, x2, y2`, the order `drawLine` takes.
    public init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        self.init(Vector2(x1, y1), Vector2(x2, y2))
    }

    /// The distance from `start` to `end`.
    public var length: Double { (end - start).length }

    /// The step from `start` to `end`.
    public var vector: Vector2 { end - start }

    /// The unit vector from `start` toward `end` (`.zero` when the two ends
    /// coincide).
    public var direction: Vector2 {
        let v = vector
        let d = v.length
        return d > 0 ? v / d : .zero
    }

    /// The angle of `direction` in radians, as `Vector2.angle` reads it.
    public var angle: Double { vector.angle }

    /// The point halfway between the ends.
    public var midpoint: Vector2 { (start + end) / 2 }

    /// The axis-aligned bounding box.
    public var bounds: Rectangle {
        let minX = Swift.min(start.x, end.x), minY = Swift.min(start.y, end.y)
        return Rectangle(x: minX, y: minY,
                         width: Swift.max(start.x, end.x) - minX,
                         height: Swift.max(start.y, end.y) - minY)
    }

    /// The segment as an open two-point contour.
    public var contour: Contour { Contour([start, end], closed: false) }

    /// The point a fraction `t` of the way from `start` to `end`, clamped to
    /// the segment the way `Contour.point(at:)` is on an open contour.
    public func point(at t: Double) -> Vector2 {
        let t = t.isFinite ? Swift.min(Swift.max(t, 0), 1) : 0
        return start + vector * t
    }

    /// How far along the segment `point` sits, as a fraction `0...1`: the
    /// inverse of `point(at:)` for a point on the segment, and the nearest
    /// place for one beside it.
    public func fraction(of point: Vector2) -> Double {
        let v = vector
        let d2 = v.lengthSquared
        guard d2 > 0 else { return 0 }
        return Swift.min(Swift.max((point - start).dot(v) / d2, 0), 1)
    }

    /// The point on the segment nearest to `point`.
    public func nearestPoint(to point: Vector2) -> Vector2 {
        self.point(at: fraction(of: point))
    }

    /// How far `point` is from the segment.
    public func distance(to point: Vector2) -> Double {
        nearestPoint(to: point).distance(to: point)
    }

    /// The same segment run the other way.
    public func reversed() -> LineSegment { LineSegment(end, start) }
}
