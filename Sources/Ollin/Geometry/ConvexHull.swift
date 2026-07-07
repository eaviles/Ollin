import Foundation

/// The convex hull of a point set: the smallest convex polygon that contains
/// every point, like a rubber band snapped around them. Returns the hull's
/// corner points in order around the boundary (collinear points along an
/// edge are dropped, so every returned point is a true corner). Fewer than
/// three distinct points return what there is.
///
/// The hull is ordinary geometry: wrap it in a `Contour` or `Shape` to fill
/// it, stroke it, offset it, or hand it to the booleans.
///
/// ```swift
/// let band = convexHull(of: scatter)
/// noFill()
/// stroke(.white)
/// drawPolygon(band)
/// ```
public func convexHull(of points: [Vector2]) -> [Vector2] {
    // Sort by x, then y, dropping exact duplicates (the monotone-chain scan
    // needs a strict order).
    let sorted = Array(Set(points.map { HullPoint($0) })).sorted().map(\.point)
    guard sorted.count > 2 else { return sorted }

    // The turn direction of a→b→c (positive one way, negative the other);
    // zero means collinear.
    func cross(_ a: Vector2, _ b: Vector2, _ c: Vector2) -> Double {
        (b - a).cross(c - a)
    }

    var lower: [Vector2] = []
    for p in sorted {
        while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 {
            lower.removeLast()
        }
        lower.append(p)
    }

    var upper: [Vector2] = []
    for p in sorted.reversed() {
        while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 {
            upper.removeLast()
        }
        upper.append(p)
    }

    // Each chain's last point is the other's first; drop both to avoid
    // repeating the endpoints.
    return lower.dropLast() + upper.dropLast()
}

/// A hashable, orderable wrapper so the hull can deduplicate and sort points.
private struct HullPoint: Hashable, Comparable {
    let x: Double, y: Double
    var point: Vector2 { Vector2(x, y) }
    init(_ p: Vector2) { self.x = p.x; self.y = p.y }
    static func < (a: HullPoint, b: HullPoint) -> Bool {
        a.x != b.x ? a.x < b.x : a.y < b.y
    }
}
