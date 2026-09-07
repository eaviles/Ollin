import Foundation

/// A dash pattern laid along a stroked path: the lengths of the dashes and of
/// the gaps between them, and a phase that slides the pattern along. Set it with
/// `strokeDash(_:)`, the way `strokeCap(_:)` sets the ends; the choice holds
/// until changed, and `noStrokeDash()` returns to a whole stroke.
///
/// `lengths` alternates dash, gap, dash, gap, in the same units as the path, so
/// `scale` scales the dashes along with the weight. An odd count repeats itself,
/// the way SVG reads one: `[8, 4, 2]` is `[8, 4, 2, 8, 4, 2]`. `phase` is how far
/// the pattern has slid along the path. A positive phase carries the dashes
/// forward, so `phase: time * 60` marches them along at 60 points a second.
///
/// ```swift
/// strokeWeight(4)
/// strokeDash([12, 8])
/// drawPolyline(points)
/// ```
///
/// Every dash is a stroke of its own, so `strokeCap` finishes its ends. A
/// `.dots(spacing:)` pattern lays down zero-length dashes, which are dots under
/// `strokeCap(.round)` and nothing under `.butt`. A corner inside a dash keeps
/// its `strokeJoin`. A width profile, a brush, and an along-path gradient still
/// read their place on the whole path, so a taper tapers across the gaps.
///
/// It applies wherever a path is expanded into a stroke: `drawLine`,
/// `drawBezier`, `drawPolyline`, `drawCurve`, `drawArc`, the outlines of
/// `drawShape` and `drawPolygon`, and stroked text. While a dash is on,
/// `drawCircle`, `drawEllipse`, `drawRect`, `drawTriangle`, `drawNgon`, and
/// `drawStar` hand their outline to that same path, so they dash too. The rest
/// of the analytic catalog keeps a continuous outline and notes it once.
/// `Contour.dashed(_:)` is the same cut as a geometry operation.
public struct StrokeDash: Hashable, Sendable {
    /// Dash, gap, dash, gap, in points along the path. An odd count repeats.
    public var lengths: [Double]

    /// How far the pattern has slid along the path, in points. A positive phase
    /// carries the dashes forward along the path's direction.
    public var phase: Double

    public init(_ lengths: [Double], phase: Double = 0) {
        self.lengths = lengths
        self.phase = phase
    }

    /// Dashes `length` long with `gap` between them; `gap` defaults to `length`.
    public static func dashes(_ length: Double, gap: Double? = nil, phase: Double = 0) -> StrokeDash {
        StrokeDash([length, gap ?? length], phase: phase)
    }

    /// Zero-length dashes every `spacing` points: dots under `strokeCap(.round)`.
    public static func dots(spacing: Double, phase: Double = 0) -> StrokeDash {
        StrokeDash([0, spacing], phase: phase)
    }

    /// The length of one repeat of the pattern.
    public var period: Double { resolvedLengths.reduce(0, +) }

    /// Whether the pattern leaves the path whole: nothing was given, or no gap
    /// has any length.
    public var isSolid: Bool {
        let lengths = resolvedLengths
        guard !lengths.isEmpty else { return true }
        var gaps = 0.0
        for i in stride(from: 1, to: lengths.count, by: 2) { gaps += lengths[i] }
        let period = lengths.reduce(0, +)
        return gaps <= 0 || period <= 0 || !period.isFinite
    }

    /// The pattern as it is walked: an odd count repeated, and anything negative
    /// or not a number read as zero.
    var resolvedLengths: [Double] {
        let clamped = lengths.map { $0.isFinite ? max(0, $0) : 0 }
        return clamped.count % 2 == 1 ? clamped + clamped : clamped
    }
}

extension StrokeDash {
    /// One dash of a cut path: its points, and where each sits on the whole
    /// path as a fraction of the path's length (what a width profile or an
    /// along-path gradient reads, so a dash keeps its place in the whole).
    struct Piece {
        var points: [Vector2]
        var fractions: [Double]
    }

    /// How many dashes the pattern lays along a path of `length`, at most.
    func dashCount(along length: Double) -> Int {
        let period = self.period
        guard period > 0, length > 0, length.isFinite else { return 0 }
        return Int((length / period).rounded(.up)) * (resolvedLengths.count / 2) + 1
    }

    /// Cut `points` into the pieces the pattern leaves along them, in path
    /// order, or `nil` when the pattern leaves the path whole. The pattern
    /// starts at the first point and runs the closing segment of a closed path
    /// too, and a dash that crosses that seam comes back as one piece, so the
    /// join at the first point stays a join.
    func cut(_ points: [Vector2], closed: Bool) -> [Piece]? {
        guard !isSolid else { return nil }
        // Drop repeated points and a closed loop's closing duplicate, the way
        // the stroke expander does, so the walk and the expansion agree.
        var pts: [Vector2] = []
        for p in points where (pts.last.map { ($0 - p).length > 1e-9 } ?? true) { pts.append(p) }
        if closed, pts.count > 1, (pts[0] - pts[pts.count - 1]).length <= 1e-9 { pts.removeLast() }
        let n = pts.count
        guard n >= 2 else { return nil }
        let segments = closed ? n : n - 1
        var cum = [Double](repeating: 0, count: segments + 1)
        for i in 0..<segments { cum[i + 1] = cum[i] + (pts[(i + 1) % n] - pts[i]).length }
        let total = cum[segments]
        guard total > 0, total.isFinite else { return nil }

        let lengths = resolvedLengths
        let period = lengths.reduce(0, +)
        var bounds = [0.0]
        for l in lengths { bounds.append(bounds[bounds.count - 1] + l) }

        /// The point `s` along the path, and the direction of the segment it is on.
        func place(_ s: Double) -> (point: Vector2, direction: Vector2) {
            var i = 0
            while i < segments - 1 && cum[i + 1] <= s { i += 1 }
            let a = pts[i], b = pts[(i + 1) % n]
            let len = cum[i + 1] - cum[i]
            let d = len > 0 ? (b - a) / len : Vector2(1, 0)
            return (a + d * (s - cum[i]), d)
        }

        var pieces: [Piece] = []
        func emit(from sa: Double, to sb: Double) {
            var piece = Piece(points: [], fractions: [])
            let start = place(sa)
            piece.points.append(start.point)
            piece.fractions.append(sa / total)
            var i = 0
            while i < segments && cum[i + 1] <= sa { i += 1 }
            i += 1
            while i < segments + (closed ? 0 : 1) && cum[i] < sb - 1e-9 {
                piece.points.append(pts[i % n])
                piece.fractions.append(cum[i] / total)
                i += 1
            }
            if sb - sa > 1e-9 {
                piece.points.append(place(sb).point)
            } else {
                // A zero-length dash still needs a direction for its caps: nudge
                // the end along the path by less than any stroke could show.
                piece.points.append(start.point + start.direction * 1e-3)
            }
            piece.fractions.append(sb / total)
            pieces.append(piece)
        }

        // Where the pattern stands at the start of the path: the phase slid back.
        var u = (-phase).truncatingRemainder(dividingBy: period)
        if u < 0 { u += period }
        // The interval that holds `u`. A zero-length dash sitting exactly there
        // counts as holding it, so a dot lands on the first point.
        var k = 0
        while k < lengths.count - 1 && (u > bounds[k + 1] || (u == bounds[k + 1] && lengths[k] > 0)) { k += 1 }
        var s = 0.0
        var dashStart = k % 2 == 0 ? 0.0 : nil as Double?
        while true {
            let next = s + (bounds[k + 1] - u)
            if next >= total - 1e-9 {
                if let a = dashStart {
                    emit(from: a, to: total)
                } else if !closed, abs(next - total) <= 1e-9, lengths[(k + 1) % lengths.count] == 0 {
                    emit(from: total, to: total)   // a dot exactly on the last point
                }
                break
            }
            if let a = dashStart { emit(from: a, to: next) }
            s = next
            k = (k + 1) % lengths.count
            u = bounds[k]
            dashStart = k % 2 == 0 ? s : nil
        }

        if closed, pieces.count >= 2,
           let first = pieces.first, let last = pieces.last,
           first.fractions[0] <= 1e-12, last.fractions[last.fractions.count - 1] >= 1 - 1e-12 {
            // The dash across the seam: the last piece continues into the first.
            var merged = last
            merged.points.append(contentsOf: first.points.dropFirst())
            merged.fractions.append(contentsOf: first.fractions.dropFirst())
            pieces.removeLast()
            pieces.removeFirst()
            pieces.append(merged)
        } else if closed, pieces.count == 1,
                  pieces[0].fractions[0] <= 1e-12,
                  pieces[0].fractions[pieces[0].fractions.count - 1] >= 1 - 1e-12 {
            return nil   // one dash that covers the whole loop: the path is whole
        }
        return pieces
    }
}

public extension Contour {
    /// The contour cut into the pieces a dash pattern leaves along it, each an
    /// open contour, in path order. The pattern starts at the first point and
    /// runs the closing segment of a closed contour too; a dash that crosses
    /// that seam comes back as one piece. A pattern that leaves the contour
    /// whole returns it as it is.
    func dashed(_ dash: StrokeDash) -> [Contour] {
        guard let pieces = dash.cut(points, closed: isClosed) else { return [self] }
        return pieces.map { Contour($0.points, closed: false) }
    }
}

public extension Shape {
    /// Every contour cut by the pattern (see `Contour.dashed(_:)`), as one shape
    /// of open contours, keeping the `winding` rule.
    func dashed(_ dash: StrokeDash) -> Shape {
        Shape(contours: contours.flatMap { $0.dashed(dash) }, winding: winding)
    }
}
