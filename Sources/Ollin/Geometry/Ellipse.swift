import Foundation

/// An ellipse in sketch points: a `center`, a `radiusX` and a `radiusY` (the
/// half-widths along its own two axes), and a `rotation` in radians that
/// turns those axes clockwise as the canvas shows it. The typed value behind
/// `drawEllipse(_:)`; at a `rotation` of 0 it is the ellipse
/// `drawEllipse(x, y, radiusX, radiusY)` draws.
///
/// ```swift
/// let dish = Ellipse(center: center, radiusX: 260, radiusY: 110, rotation: .pi / 8)
/// drawEllipse(dish)
/// let rim = dish.perimeter                         // exact, not a formula's guess
/// if dish.contains(mouse) { /* inside */ }
/// ```
public struct Ellipse: Equatable, Hashable, Sendable, Codable, PlaneCurve {
    public let center: Vector2
    /// The half-width along the ellipse's own x axis.
    public let radiusX: Double
    /// The half-height along the ellipse's own y axis.
    public let radiusY: Double
    /// How far the axes are turned, in radians, clockwise as the canvas
    /// shows it.
    public let rotation: Double

    public init(center: Vector2, radiusX: Double, radiusY: Double, rotation: Double = 0) {
        self.center = center
        self.radiusX = radiusX
        self.radiusY = radiusY
        self.rotation = rotation
    }

    /// Build from bare `x, y, radiusX, radiusY`, the order `drawEllipse`
    /// takes.
    public init(x: Double, y: Double, radiusX: Double, radiusY: Double, rotation: Double = 0) {
        self.init(center: Vector2(x, y), radiusX: radiusX, radiusY: radiusY, rotation: rotation)
    }

    /// The area, `π * radiusX * radiusY`.
    public var area: Double { .pi * radiusX * radiusY }

    /// The distance round the outline, exact to double precision: the
    /// complete elliptic integral of the second kind, taken through the
    /// arithmetic-geometric mean, which doubles its correct digits every
    /// step. A circle's comes back as `2π r`.
    public var perimeter: Double {
        let a = Swift.max(abs(radiusX), abs(radiusY)), b = Swift.min(abs(radiusX), abs(radiusY))
        guard a > 0 else { return 0 }
        guard b > 0 else { return 4 * a }
        if a == b { return 2 * .pi * a }
        // E(k) = K(k) * (1 - sum of 2^(n-1) c_n^2), with K(k) = π / (2 a_N)
        // from the mean of a_0 = 1 and b_0 = b/a.
        var an = 1.0, bn = b / a
        var cn2 = 1 - bn * bn
        var sum = 0.5 * cn2
        var weight = 1.0
        for _ in 0 ..< 40 {
            let next = (an + bn) / 2
            let c = (an - bn) / 2
            bn = (an * bn).squareRoot()
            an = next
            cn2 = c * c
            sum += weight * cn2
            weight *= 2
            if cn2 * weight < 1e-18 { break }
        }
        let k = .pi / (2 * an)
        return 4 * a * k * (1 - sum)
    }

    /// How far from a circle it is: 0 for a circle, approaching 1 as it
    /// flattens.
    public var eccentricity: Double {
        let a = Swift.max(abs(radiusX), abs(radiusY)), b = Swift.min(abs(radiusX), abs(radiusY))
        guard a > 0 else { return 0 }
        return (1 - (b * b) / (a * a)).squareRoot()
    }

    /// The axis-aligned bounding box, exact under the rotation.
    public var bounds: Rectangle {
        let c = cos(rotation), s = sin(rotation)
        let hx = (radiusX * radiusX * c * c + radiusY * radiusY * s * s).squareRoot()
        let hy = (radiusX * radiusX * s * s + radiusY * radiusY * c * c).squareRoot()
        return Rectangle(center: center, width: 2 * hx, height: 2 * hy)
    }

    /// Whether `point` lies inside the ellipse (the outline counts as inside).
    public func contains(_ point: Vector2) -> Bool {
        toUnit(point).lengthSquared <= 1
    }

    /// The point at the parametric angle `angle` (radians): `center` plus
    /// `radiusX * cos(angle)` along the ellipse's own x axis and
    /// `radiusY * sin(angle)` along its y axis, turned by `rotation`. Not the
    /// polar angle of the point from the center, except on a circle.
    public func point(at angle: Double) -> Vector2 {
        fromUnit(Vector2(cos(angle), sin(angle)))
    }

    /// The ellipse as a closed outline of `segments` straight pieces, starting
    /// at the end of its own x axis and running clockwise as the canvas shows
    /// it, so it can join the outlines a `Shape`, a boolean, or
    /// `regions(enclosedBy:)` takes. Left to its default, the count follows
    /// the larger radius the way `Circle.contour(segments:)` does, so no piece
    /// strays more than a tenth of a unit from the curve. A count given is
    /// held to at least 3.
    public func contour(segments: Int? = nil) -> Contour {
        let count = segments.map { Swift.max($0, 3) }
            ?? Circle.segmentCount(forRadius: Swift.max(abs(radiusX), abs(radiusY)))
        return Contour((0 ..< count).map { point(at: Double($0) / Double(count) * 2 * .pi) },
                       closed: true)
    }

    /// `contour(segments:)` at its default count.
    public var contour: Contour { contour(segments: nil) }

    /// The point on the outline nearest to `point`, found by Newton's method
    /// on the parametric angle from the nearest of a ring of samples.
    public func nearestPoint(to point: Vector2) -> Vector2 {
        guard radiusX != 0, radiusY != 0 else {
            return LineSegment(self.point(at: 0), self.point(at: .pi)).nearestPoint(to: point)
        }
        // Work in the ellipse's own frame, where the curve is (a cos t, b sin t).
        let c = cos(rotation), s = sin(rotation)
        let d = point - center
        let q = Vector2(d.x * c + d.y * s, -d.x * s + d.y * c)
        let a = radiusX, b = radiusY
        var best = 0.0, bestD = Double.infinity
        for i in 0 ..< 64 {
            let t = Double(i) / 64 * 2 * .pi
            let dd = Vector2(a * cos(t) - q.x, b * sin(t) - q.y).lengthSquared
            if dd < bestD { bestD = dd; best = t }
        }
        var t = best
        for _ in 0 ..< 40 {
            let ct = cos(t), st = sin(t)
            let p = Vector2(a * ct, b * st)
            let dp = Vector2(-a * st, b * ct)
            let ddp = Vector2(-a * ct, -b * st)
            let f = (p - q).dot(dp)
            let df = dp.dot(dp) + (p - q).dot(ddp)
            guard abs(df) > 1e-300 else { break }
            let step = f / df
            t -= step
            if abs(step) < 1e-15 { break }
        }
        return self.point(at: t)
    }

    /// How far `point` is from the outline.
    public func distance(to point: Vector2) -> Double {
        nearestPoint(to: point).distance(to: point)
    }

    // MARK: The unit-circle frame

    /// Whether the two radii are the same, so the ellipse is a circle and the
    /// crossing engine can use the circle's closed forms.
    var isCircular: Bool {
        abs(radiusX - radiusY) <= 1e-12 * Swift.max(abs(radiusX), abs(radiusY))
    }

    /// `point` carried into the frame where the ellipse is the unit circle:
    /// moved to the center, turned back by `rotation`, and scaled by the two
    /// radii.
    func toUnit(_ point: Vector2) -> Vector2 {
        let c = cos(rotation), s = sin(rotation)
        let d = point - center
        let local = Vector2(d.x * c + d.y * s, -d.x * s + d.y * c)
        return Vector2(radiusX != 0 ? local.x / radiusX : 0, radiusY != 0 ? local.y / radiusY : 0)
    }

    /// The inverse of `toUnit`.
    func fromUnit(_ u: Vector2) -> Vector2 {
        let c = cos(rotation), s = sin(rotation)
        let local = Vector2(u.x * radiusX, u.y * radiusY)
        return center + Vector2(local.x * c - local.y * s, local.x * s + local.y * c)
    }

    /// The gradient of `toUnit(p).lengthSquared - 1` with respect to `p`.
    func unitGradient(at point: Vector2) -> Vector2 {
        let u = toUnit(point)
        let c = cos(rotation), s = sin(rotation)
        let local = Vector2(radiusX != 0 ? 2 * u.x / radiusX : 0, radiusY != 0 ? 2 * u.y / radiusY : 0)
        return Vector2(local.x * c - local.y * s, local.x * s + local.y * c)
    }
}
