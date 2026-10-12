import Foundation

/// A piece of a circle, in sketch points: a `center`, a `radius`, and the two
/// angles it runs between, `start` to `stop`, in radians measured from the
/// positive x-axis and increasing clockwise as the canvas shows it, the same
/// angles `drawArc` takes. The typed value behind `drawArc(_:mode:)`.
///
/// ```swift
/// let smile = Arc(center: center, radius: 120, start: .pi * 0.15, stop: .pi * 0.85)
/// drawArc(smile)
/// let ends = smile.startPoint.distance(to: smile.endPoint)
/// ```
///
/// A `stop` smaller than `start` runs the other way round, so the same two
/// angles can name either of the two arcs between them.
public struct Arc: Equatable, Hashable, Sendable, Codable, PlaneCurve {
    public let center: Vector2
    public let radius: Double
    /// Where the arc begins, in radians.
    public let start: Double
    /// Where the arc ends, in radians.
    public let stop: Double

    public init(center: Vector2, radius: Double, start: Double, stop: Double) {
        self.center = center
        self.radius = radius
        self.start = start
        self.stop = stop
    }

    /// Build from bare `x, y, radius`, the order `drawArc` takes.
    public init(x: Double, y: Double, radius: Double, start: Double, stop: Double) {
        self.init(center: Vector2(x, y), radius: radius, start: start, stop: stop)
    }

    /// The signed angle swept, `stop - start`: negative when the arc runs
    /// counterclockwise as the canvas shows it.
    public var sweep: Double { stop - start }

    /// The length along the curve, `|sweep| * radius`.
    public var length: Double { abs(sweep) * radius }

    /// The whole circle the arc is a piece of.
    public var circle: Circle { Circle(center: center, radius: radius) }

    /// Where the arc begins.
    public var startPoint: Vector2 { point(atAngle: start) }

    /// Where the arc ends.
    public var endPoint: Vector2 { point(atAngle: stop) }

    /// The point halfway along the arc (`point(at: 0.5)`).
    public var midpoint: Vector2 { point(at: 0.5) }

    /// The straight line between the two ends.
    public var chord: LineSegment { LineSegment(startPoint, endPoint) }

    /// The point a fraction `t` of the way along the sweep, clamped to the
    /// arc the way `Contour.point(at:)` is on an open contour.
    public func point(at t: Double) -> Vector2 {
        let t = t.isFinite ? Swift.min(Swift.max(t, 0), 1) : 0
        return point(atAngle: start + sweep * t)
    }

    /// Whether `angle` (radians) lies on the arc. Angles a whole turn apart
    /// are the same angle, and either end counts.
    public func contains(angle: Double) -> Bool {
        CurveCrossings.Round(center: center, radius: radius, start: start, sweep: sweep)
            .contains(angle: angle)
    }

    /// The axis-aligned bounding box of the curve itself: its two ends, plus
    /// whichever of the four axis points the sweep passes through.
    public var bounds: Rectangle {
        var points = [startPoint, endPoint]
        for quarter in 0 ..< 4 {
            let angle = Double(quarter) * .pi / 2
            if contains(angle: angle) { points.append(point(atAngle: angle)) }
        }
        var minX = points[0].x, maxX = points[0].x, minY = points[0].y, maxY = points[0].y
        for p in points.dropFirst() {
            minX = Swift.min(minX, p.x); maxX = Swift.max(maxX, p.x)
            minY = Swift.min(minY, p.y); maxY = Swift.max(maxY, p.y)
        }
        return Rectangle(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The arc as an open polyline, flattened like `Circle.contour(segments:)`
    /// so no piece strays more than a tenth of a unit from the curve, with at
    /// least two pieces.
    public var contour: Contour { contour(mode: .open) }

    /// The arc as an outline closed the way `drawArc`'s `mode` closes it:
    /// `.open` is the curve alone, `.chord` joins the two ends, and `.pie`
    /// closes through the center. `segments` fixes the number of pieces (held
    /// to at least 2); left to its default, the count follows the radius and
    /// the sweep.
    public func contour(mode: ArcMode, segments: Int? = nil) -> Contour {
        let count: Int
        if let segments {
            count = Swift.max(segments, 2)
        } else {
            let full = Double(Circle.segmentCount(forRadius: radius))
            count = Swift.max(2, Int((full * abs(sweep) / (2 * .pi)).rounded(.up)))
        }
        let points = (0 ... count).map { point(atAngle: start + sweep * Double($0) / Double(count)) }
        switch mode {
        case .open: return Contour(points, closed: false)
        case .chord: return Contour(points, closed: true)
        case .pie: return Contour([center] + points, closed: true)
        }
    }

    /// The point on the arc nearest to `point`: its projection onto the
    /// circle when that lands on the sweep, else the nearer of the two ends.
    public func nearestPoint(to point: Vector2) -> Vector2 {
        let d = point - center
        if d.lengthSquared > 0, contains(angle: d.angle) {
            return center + d.normalized * radius
        }
        let a = startPoint, b = endPoint
        return a.distanceSquared(to: point) <= b.distanceSquared(to: point) ? a : b
    }

    /// How far `point` is from the arc.
    public func distance(to point: Vector2) -> Double {
        nearestPoint(to: point).distance(to: point)
    }

    private func point(atAngle angle: Double) -> Vector2 {
        center + Vector2(angle: angle, length: radius)
    }
}
