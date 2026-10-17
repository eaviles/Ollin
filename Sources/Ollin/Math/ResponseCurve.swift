import Foundation

/// A curve shaped by points: a number from 0 to 1 goes in and a number from 0
/// to 1 comes out, the way an `Easing` reads, except that the shape is
/// whatever the points say. It is the fit for a falloff (how strongly a brush
/// paints at each distance from its center), a response (how a pressure, a
/// loudness, or a speed turns into a size), or a tone curve.
///
/// ```swift
/// @Param var falloff = ResponseCurve([(0, 1), (0.3, 0.85), (0.7, 0.2), (1, 0)])
///
/// override func draw() {
///     for ring in 0..<20 {
///         let t = Double(ring) / 19
///         fill(Color(white: falloff(t)))
///         drawCircle(width / 2, height / 2, 400 * (1 - t))
///     }
/// }
/// ```
///
/// As a parameter it is a small graph in the inspector whose points drag, and
/// the points it ends on are written back into the sketch like any other
/// parameter's value.
///
/// The curve passes through every point and runs smooth between them, and it
/// never overshoots: between two points it stays between their heights, so a
/// falloff never dips below zero and a response never runs past one. That is
/// monotone cubic interpolation, the method Fritsch and Carlson published in
/// 1980. Left of the first point the curve holds the first point's height, and
/// right of the last it holds the last one's.
public struct ResponseCurve: Hashable, Sendable {
    /// The points the curve passes through, in order of `x`, each inside the
    /// unit square.
    public private(set) var points: [Vector2]
    /// The curve's slope at each point, worked out once from the points.
    private var slopes: [Double]

    /// A curve through `points`. Each point is held inside the unit square,
    /// the points are put in order of `x`, and a point at the same `x` as the
    /// one before it is dropped, since a curve has one height at each `x`. No
    /// points at all gives the straight line from (0, 0) to (1, 1).
    public init(points: [Vector2]) {
        var kept: [Vector2] = []
        let inside = points
            .filter { $0.x.isFinite && $0.y.isFinite }
            .map { Vector2(Swift.min(Swift.max($0.x, 0), 1), Swift.min(Swift.max($0.y, 0), 1)) }
            .enumerated()
            .sorted { $0.element.x == $1.element.x ? $0.offset < $1.offset : $0.element.x < $1.element.x }
            .map(\.element)
        for point in inside where kept.last?.x != point.x {
            kept.append(point)
        }
        if kept.isEmpty { kept = [Vector2(0, 0), Vector2(1, 1)] }
        self.points = kept
        self.slopes = ResponseCurve.slopes(through: kept)
    }

    /// A curve through points written as `(x, y)` pairs, the shortest way to
    /// spell one: `ResponseCurve([(0, 1), (0.5, 0.8), (1, 0)])`.
    public init(_ points: [(Double, Double)]) {
        self.init(points: points.map { Vector2($0.0, $0.1) })
    }

    /// The straight line from (0, 0) to (1, 1): what goes in comes out.
    public static let linear = ResponseCurve([(0, 0), (1, 1)])

    /// The curve's height at `x`, from 0 to 1. `x` is held to `0...1` first.
    public func callAsFunction(_ x: Double) -> Double {
        guard let first = points.first, let last = points.last else { return x }
        let x = Swift.min(Swift.max(x.isFinite ? x : 0, 0), 1)
        if points.count == 1 || x <= first.x { return first.y }
        if x >= last.x { return last.y }
        // The interval holding x: the last point at or left of it.
        var low = 0
        var high = points.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if points[middle].x <= x { low = middle } else { high = middle }
        }
        let a = points[low]
        let b = points[low + 1]
        let h = b.x - a.x
        let t = (x - a.x) / h
        let t2 = t * t
        let t3 = t2 * t
        let value = (2 * t3 - 3 * t2 + 1) * a.y
            + (t3 - 2 * t2 + t) * h * slopes[low]
            + (-2 * t3 + 3 * t2) * b.y
            + (t3 - t2) * h * slopes[low + 1]
        // The method keeps the value between the two heights; rounding can
        // step a hair past an end, and the curve promises 0...1.
        return Swift.min(Swift.max(value, 0), 1)
    }

    /// The curve as an `Easing`, for a call that takes one: a parameter's
    /// glide, a tween's feel. Built from a closure, so it compares equal only
    /// to itself.
    public var easing: Easing {
        let curve = self
        return Easing { curve($0) }
    }

    /// Fritsch-Carlson slopes: each inner point starts from the mean of the
    /// secants on its two sides (zero where they disagree in sign, a peak or a
    /// valley, which is what keeps the curve from overshooting there), a flat
    /// interval flattens both its ends, and a pair of slopes too steep for
    /// their interval is scaled back onto the circle of radius 3 that keeps
    /// the piece monotone.
    private static func slopes(through points: [Vector2]) -> [Double] {
        let n = points.count
        guard n > 1 else { return Array(repeating: 0, count: n) }
        var secants: [Double] = []
        for k in 0..<(n - 1) {
            secants.append((points[k + 1].y - points[k].y) / (points[k + 1].x - points[k].x))
        }
        var m = Array(repeating: 0.0, count: n)
        m[0] = secants[0]
        m[n - 1] = secants[n - 2]
        for k in 1..<(n - 1) {
            m[k] = secants[k - 1] * secants[k] <= 0 ? 0 : (secants[k - 1] + secants[k]) / 2
        }
        for k in 0..<(n - 1) {
            let d = secants[k]
            if d == 0 {
                m[k] = 0
                m[k + 1] = 0
                continue
            }
            let alpha = m[k] / d
            let beta = m[k + 1] / d
            let length = alpha * alpha + beta * beta
            if length > 9 {
                let tau = 3 / length.squareRoot()
                m[k] = tau * alpha * d
                m[k + 1] = tau * beta * d
            }
        }
        return m
    }

    public static func == (lhs: ResponseCurve, rhs: ResponseCurve) -> Bool {
        lhs.points == rhs.points
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(points)
    }
}
