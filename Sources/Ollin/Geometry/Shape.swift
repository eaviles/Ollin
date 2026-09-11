import Foundation

/// One connected path: an ordered run of points that's either open (a stroked
/// path) or closed (an outline you can fill). The building block of a `Shape`.
///
/// A `Contour` is polygonal — straight segments between its points. To author a
/// *curved* outline, trace it with `Path` (or `Contour(curveThrough:)`), which
/// samples the curve into points for you.
public struct Contour: Equatable, Sendable {
    public var points: [Vector2]

    /// Whether the last point joins back to the first. Closed contours can be
    /// filled and are stroked as a loop; open ones are stroke-only.
    public var isClosed: Bool

    public init(_ points: [Vector2], closed: Bool = true) {
        self.points = points
        self.isClosed = closed
    }
}

public extension Contour {
    /// The distance walked along the contour's segments, end to end (plus the
    /// closing segment back to the start when the contour is closed).
    var length: Double {
        guard points.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<points.count {
            total += (points[i] - points[i - 1]).length
        }
        if isClosed {
            total += (points[0] - points[points.count - 1]).length
        }
        return total
    }

    /// The point a fraction `t` (`0...1`, clamped) of the way along the
    /// contour *by walked length*, so it lands mid-stroke even when the points
    /// are spaced unevenly. A closed contour's walk includes the closing
    /// segment, so `t` near 1 sits just before the start again.
    func point(at t: Double) -> Vector2 {
        guard let first = points.first else { return .zero }
        let total = length
        guard total > 0 else { return first }
        var remaining = min(max(t, 0), 1) * total
        var walk = Array(points.dropFirst())
        if isClosed { walk.append(first) }
        var previous = first
        for point in walk {
            let segment = (point - previous).length
            if remaining <= segment {
                guard segment > 0 else { continue }
                return previous + (point - previous) * (remaining / segment)
            }
            remaining -= segment
            previous = point
        }
        return walk[walk.count - 1]
    }

    /// The point halfway along the contour (`point(at: 0.5)`): a handy anchor
    /// for styling per contour, like coloring each strand of a tiling by a
    /// field sampled at its middle.
    var midpoint: Vector2 { point(at: 0.5) }

    /// A copy whose points march an even `spacing` apart along the walked
    /// path (arc length), keeping `isClosed`. Points that arrive unevenly
    /// spaced, like a glyph outline from `textToShapes` (dense on curves,
    /// sparse on straights), come back at a steady interval, ready for dot,
    /// dash, and jitter effects. A degenerate contour (fewer than two points,
    /// or a non-positive `spacing`) returns unchanged.
    func resampled(spacing: Double) -> Contour {
        guard points.count >= 2, spacing > 0 else { return self }
        var poly = points
        if isClosed { poly.append(points[0]) }
        var result = [poly[0]]
        var sinceLast = 0.0              // arc length accrued since the last emit
        for i in 1..<poly.count {
            let a = poly[i - 1], b = poly[i]
            let segment = (b - a).length
            guard segment > 1e-9 else { continue }
            var t = 0.0                  // position along this segment, 0…segment
            while sinceLast + (segment - t) >= spacing {
                t += spacing - sinceLast
                result.append(a + (b - a) * (t / segment))
                sinceLast = 0
            }
            sinceLast += segment - t     // carry the unconsumed tail forward
        }
        return Contour(result, closed: isClosed)
    }
}

/// The rule that decides which regions of a self-overlapping or multi-contour
/// outline are inside the fill.
///
/// - `evenOdd` (the default): a point is filled when a ray from it crosses the
///   outline an odd number of times. Nested contours alternate fill/hole and a
///   contour's *direction doesn't matter* — the simple, predictable rule for
///   hand-built shapes with holes.
/// - `nonZero`: a point is filled when the signed crossings (by winding
///   *direction*) don't cancel to zero. This is the rule font outlines are
///   authored for, so it's what glyph fills use: it keeps counters as holes
///   (opposite winding) yet still fills places where an outline overlaps itself
///   (e.g. the terminal of an `e`, `a`, `g`, `s`), which even-odd would drop.
public enum FillWinding: Sendable {
    case evenOdd
    case nonZero
}

/// A fillable region made of one or more `Contour`s. Unlike a convex
/// `drawPolygon`, a `Shape` can be **concave** and can have **holes**: extra
/// contours nested inside the outer one cut holes out of the fill. The `winding`
/// rule decides how (even-odd by default). The fill is triangulated; each
/// contour is also stroked as its own outline.
///
/// `Shape` is a value you build, hold, and transform, like `Vector2` and
/// `Rectangle` — not just an immediate draw call.
public struct Shape: Equatable, Sendable {
    public var contours: [Contour]
    /// How the fill resolves overlaps and nested contours (see `FillWinding`).
    /// Defaults to `.evenOdd`; glyph shapes from the text API use `.nonZero`.
    public var winding: FillWinding

    public init(contours: [Contour], winding: FillWinding = .evenOdd) {
        self.contours = contours
        self.winding = winding
    }

    /// A shape from a single contour of points (closed by default).
    public init(_ points: [Vector2], closed: Bool = true) {
        self.init(contours: [Contour(points, closed: closed)])
    }

    /// A shape from an outer boundary with holes cut out of it. All contours are
    /// closed; the holes are removed from the fill by even-odd winding.
    public init(outer: [Vector2], holes: [[Vector2]]) {
        self.init(contours: [Contour(outer)] + holes.map { Contour($0) })
    }

    /// A copy with every contour point passed through `transform`, keeping the
    /// `winding` rule and open/closed flags. The safe way to move or warp a
    /// shape (a glyph from `textToShapes`, say) without dropping its winding.
    public func mapPoints(_ transform: (Vector2) -> Vector2) -> Shape {
        Shape(contours: contours.map { Contour($0.points.map(transform), closed: $0.isClosed) },
              winding: winding)
    }

    /// A copy with every contour respaced to an even point `spacing` (see
    /// `Contour.resampled(spacing:)`), keeping the `winding` rule.
    public func resampled(spacing: Double) -> Shape {
        Shape(contours: contours.map { $0.resampled(spacing: spacing) },
              winding: winding)
    }
}

public extension Shape {
    /// Whether `point` lies inside the filled region, honoring the shape's
    /// `winding` rule (even-odd crossings, or the non-zero winding number).
    /// Every contour is treated as closed, the same way a fill treats an
    /// outline. A point exactly on an edge may land on either side (it's a
    /// floating-point ray test), so don't lean on the boundary itself.
    func contains(_ point: Vector2) -> Bool {
        var crossings = 0
        var windingNumber = 0
        for contour in contours {
            let pts = contour.points
            guard pts.count >= 3 else { continue }
            for i in pts.indices {
                let a = pts[i]
                let b = pts[(i + 1) % pts.count]
                // Count crossings of the ray running +x from `point`, using
                // the half-open vertex rule so a ray through a corner never
                // double-counts.
                guard (a.y > point.y) != (b.y > point.y) else { continue }
                let t = (point.y - a.y) / (b.y - a.y)
                if a.x + (b.x - a.x) * t > point.x {
                    crossings += 1
                    windingNumber += b.y > a.y ? 1 : -1
                }
            }
        }
        return winding == .evenOdd ? crossings % 2 == 1 : windingNumber != 0
    }
}

public extension Shape {
    /// The axis-aligned box around every point, `nil` when the shape has no
    /// points at all. Open contours count: this is the box the outline
    /// occupies, not the box its fill occupies.
    var bounds: Rectangle? {
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        for contour in contours {
            for point in contour.points {
                minX = Swift.min(minX, point.x); maxX = Swift.max(maxX, point.x)
                minY = Swift.min(minY, point.y); maxY = Swift.max(maxY, point.y)
            }
        }
        guard minX <= maxX else { return nil }
        return Rectangle(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// How much area the fill covers.
    ///
    /// The shape's own `winding` rule decides what counts, so a ring comes
    /// back as the difference between its two circles whichever way its hole
    /// was wound, and a self-overlapping outline is counted once. Open
    /// contours are ignored, the way a fill ignores them.
    var area: Double {
        abs(resolvedFill().contours.reduce(0) { $0 + Shape.signedArea($1.points) })
    }

    /// The balance point of the filled region: where the shape would sit on a
    /// pin. Holes pull it the way a bite out of a biscuit does.
    ///
    /// A shape with no area at all (a single open path, one straight line of
    /// points) has no such point, so the average of its points comes back
    /// instead.
    var centroid: Vector2 {
        var weighted = Vector2.zero
        var total = 0.0
        for contour in resolvedFill().contours where contour.points.count >= 3 {
            let signed = Shape.signedArea(contour.points)
            weighted += Shape.centroid(of: contour.points) * signed
            total += signed
        }
        guard abs(total) > 1e-12 else {
            let points = contours.flatMap(\.points)
            guard !points.isEmpty else { return .zero }
            return points.reduce(.zero, +) / Double(points.count)
        }
        return weighted / total
    }

    /// The filled region resolved under the shape's own winding rule, so the
    /// contours that come back are outer boundaries and holes wound against
    /// each other. One contour already means what it says, so it passes
    /// through untouched rather than paying for the resolve.
    private func resolvedFill() -> Shape {
        let closed = contours.filter { $0.isClosed && $0.points.count >= 3 }
        guard closed.count > 1 else { return Shape(contours: closed, winding: winding) }
        return union(Shape(contours: []))
    }

    /// The shape's separate islands, one `Shape` each, holes kept with the
    /// island they belong to.
    ///
    /// A boolean or a fracture can leave several regions in one value (a bar
    /// cut in two, a cell that straddles the waist of an hourglass). This is
    /// how to treat each of them as its own thing: give one to a rigid body,
    /// measure one's area, drop the crumbs. A shape that is already one island
    /// comes back alone.
    func separated() -> [Shape] {
        let closed = contours.filter { $0.isClosed && $0.points.count >= 3 }
        guard closed.count > 1 else { return contours.isEmpty ? [] : [self] }

        // Nesting decides what is an island and what is a hole in it, rather
        // than which way a contour is wound: the two fill rules disagree about
        // winding, and a shape built by hand may not follow either. The test
        // point sits on the contour's own edge, not inside it, so a ring's
        // outer boundary is not read as living inside its own hole.
        let probes = closed.map { Shape.edgeProbe(of: $0.points) }
        var depth = [Int](repeating: 0, count: closed.count)
        var parent = [Int?](repeating: nil, count: closed.count)
        for i in closed.indices {
            let probe = probes[i]
            var smallest = Double.infinity
            for j in closed.indices where j != i {
                guard Shape.contains(closed[j].points, probe) else { continue }
                depth[i] += 1
                let size = abs(Shape.signedArea(closed[j].points))
                if size < smallest { smallest = size; parent[i] = j }
            }
        }

        var islands: [Int: [Contour]] = [:]
        var order: [Int] = []
        for i in closed.indices where depth[i] % 2 == 0 {
            islands[i] = [closed[i]]
            order.append(i)
        }
        for i in closed.indices where depth[i] % 2 == 1 {
            guard let owner = parent[i], islands[owner] != nil else { continue }
            islands[owner]?.append(closed[i])
        }
        return order.compactMap { islands[$0] }.map { Shape(contours: $0, winding: winding) }
    }

    /// Twice the signed area of a closed polygon, halved: positive one way
    /// around, negative the other.
    internal static func signedArea(_ points: [Vector2]) -> Double {
        guard points.count >= 3 else { return 0 }
        var sum = 0.0
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    /// The area centroid of one closed polygon.
    internal static func centroid(of points: [Vector2]) -> Vector2 {
        var sum = Vector2.zero
        var total = 0.0
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            let cross = a.x * b.y - b.x * a.y
            sum += (a + b) * cross
            total += cross
        }
        guard abs(total) > 1e-12 else {
            return points.reduce(.zero, +) / Double(points.count)
        }
        return sum / (3 * total)
    }

    /// Whether a closed polygon contains a point (even-odd crossings).
    internal static func contains(_ points: [Vector2], _ point: Vector2) -> Bool {
        var crossings = 0
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            guard (a.y > point.y) != (b.y > point.y) else { continue }
            let t = (point.y - a.y) / (b.y - a.y)
            if a.x + (b.x - a.x) * t > point.x { crossings += 1 }
        }
        return crossings % 2 == 1
    }

    /// A point on a closed polygon's own boundary: the middle of its first
    /// real edge. Two contours of one shape never cross, so this is enough to
    /// tell which one lies inside which, and unlike an interior point it is
    /// not swallowed by the contour's own hole.
    internal static func edgeProbe(of points: [Vector2]) -> Vector2 {
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            if a.distanceSquared(to: b) > 0 { return (a + b) / 2 }
        }
        return points.first ?? .zero
    }
}
