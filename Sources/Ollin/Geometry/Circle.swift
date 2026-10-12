import Foundation

/// A circle in sketch points (top-left origin, y-down): a `center` and a
/// `radius`.
///
/// Like `Vector2` and `Rectangle`, `Circle` is a value you pass around and
/// compose, not just a draw call: it's the typed currency `drawCircle(_:)` and
/// the batch `drawCircles(_:)` take, with the bare scalar
/// `drawCircle(x, y, radius)` as sugar over it.
public struct Circle: Equatable, Hashable, Sendable, Codable, PlaneCurve {
    public let center: Vector2
    public let radius: Double

    public init(center: Vector2, radius: Double) {
        self.center = center
        self.radius = radius
    }

    /// Build from bare `x, y, radius`.
    public init(x: Double, y: Double, radius: Double) {
        self.init(center: Vector2(x, y), radius: radius)
    }

    public var x: Double { center.x }
    public var y: Double { center.y }

    /// The diameter (`radius * 2`).
    public var diameter: Double { radius * 2 }

    /// The area, `π r²`.
    public var area: Double { .pi * radius * radius }

    /// The distance round the outline, `2π r`.
    public var perimeter: Double { 2 * .pi * radius }

    /// The axis-aligned bounding box.
    public var bounds: Rectangle {
        Rectangle(center: center, width: diameter, height: diameter)
    }

    /// Whether `point` lies inside the circle (the boundary counts as inside).
    public func contains(_ point: Vector2) -> Bool {
        let dx = point.x - center.x, dy = point.y - center.y
        return dx * dx + dy * dy <= radius * radius
    }

    /// The point on the circle at `angle` radians from the positive x-axis,
    /// clockwise as the canvas shows it.
    public func point(at angle: Double) -> Vector2 {
        center + Vector2(angle: angle, length: radius)
    }

    /// The point on the circle nearest to `point` (the rightmost point for
    /// the center itself).
    public func nearestPoint(to point: Vector2) -> Vector2 {
        let d = point - center
        guard d.lengthSquared > 0 else { return self.point(at: 0) }
        return center + d.normalized * radius
    }

    /// How far `point` is from the outline, inside or out.
    public func distance(to point: Vector2) -> Double {
        abs(point.distance(to: center) - radius)
    }

    /// `contour(segments:)` at its default count.
    public var contour: Contour { contour(segments: nil) }

    /// The circle as a closed outline of `segments` straight pieces, starting
    /// at the right and running clockwise as the canvas shows it, so a circle
    /// can join the outlines a `Shape`, a boolean, or `regions(enclosedBy:)`
    /// takes. Left to its default, the count follows the radius so that no
    /// piece strays more than a tenth of a unit from the true circle, the
    /// same limit `Contour.rounded(_:)` flattens an arc to, from 8 pieces for
    /// a tiny ring up to 256, past which a very wide circle (a radius over
    /// about 1,300) strays a little more. A count given is held to at least 3.
    public func contour(segments: Int? = nil) -> Contour {
        let count = segments.map { Swift.max($0, 3) } ?? Circle.segmentCount(forRadius: radius)
        return Contour((0 ..< count).map { i in
            center + Vector2(angle: Double(i) / Double(count) * 2 * .pi, length: radius)
        }, closed: true)
    }

    /// How many straight pieces a whole circle of `radius` takes so that no
    /// piece strays more than a tenth of a unit from it: 8 for a tiny ring,
    /// up to 256. Shared by the arc and the ellipse.
    static func segmentCount(forRadius radius: Double) -> Int {
        guard radius > 0.05 else { return 8 }
        let step = 2 * acos(1 - 0.1 / radius)
        return Swift.min(256, Swift.max(8, Int((2 * Double.pi / step).rounded(.up))))
    }
}
