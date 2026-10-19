import Foundation

/// Half of the canvas: every point on one side of a straight line, the line
/// included. `point` is anywhere on the line and `inward` points into the side
/// that is kept, at any length. The cut a facet painter makes through a face,
/// and the thing `Shape.clipped(to:)` keeps.
///
/// ```swift
/// let lit = HalfPlane(point: facet.centroid, inward: facet.tilt)
/// drawShape(facet.shape.clipped(to: lit))        // the downhill half of the face
/// ```
public struct HalfPlane: Equatable, Hashable, Sendable {
    /// A point on the boundary line.
    public var point: Vector2
    /// Which way the kept side lies. It does not have to be a unit vector.
    public var inward: Vector2

    public init(point: Vector2, inward: Vector2) {
        self.point = point
        self.inward = inward
    }

    /// The side to the left of `line` as the canvas shows it: standing at its
    /// origin and looking along its direction, left is left on screen.
    public init(leftOf line: Ray2) {
        self.init(point: line.origin, inward: Vector2(line.direction.y, -line.direction.x))
    }

    /// The side to the right of `line` as the canvas shows it.
    public init(rightOf line: Ray2) {
        self.init(point: line.origin, inward: Vector2(-line.direction.y, line.direction.x))
    }

    /// The boundary as a line, running along the kept side's edge.
    public var boundary: Ray2 { Ray2(origin: point, direction: Vector2(-inward.y, inward.x)) }

    /// How far `p` is inside: positive on the kept side, zero on the line, and
    /// negative outside, in canvas units.
    public func signedDistance(to p: Vector2) -> Double {
        let length = inward.length
        guard length > 0 else { return 0 }
        return (p - point).dot(inward) / length
    }

    /// Whether `p` is on the kept side, the boundary included.
    public func contains(_ p: Vector2) -> Bool {
        (p - point).dot(inward) >= 0
    }

    /// Where the segment from `a` to `b` crosses the boundary (`a` when the
    /// segment runs along it).
    func crossing(_ a: Vector2, _ b: Vector2) -> Vector2 {
        let da = (a - point).dot(inward), db = (b - point).dot(inward)
        let span = db - da
        guard abs(span) > 1e-12 else { return a }
        return a.lerp(to: b, -da / span)
    }
}

public extension Contour {
    /// The part of the contour on the kept side of `half`, by one pass over its
    /// points against the one line (the Sutherland-Hodgman clip). A closed
    /// contour comes back as one closed contour, or none when nothing is
    /// inside; an open one comes back as the pieces of it that are, each its
    /// own open contour. A closed outline that is not convex keeps its fill
    /// right but may touch itself along the cut, as any clip of that shape does.
    func clipped(to half: HalfPlane) -> [Contour] {
        guard points.count >= 2 else {
            return points.count == 1 && half.contains(points[0]) ? [self] : []
        }
        if isClosed {
            var out: [Vector2] = []
            out.reserveCapacity(points.count + 2)
            for i in points.indices {
                let current = points[i]
                let previous = points[i == 0 ? points.count - 1 : i - 1]
                let currentIn = half.contains(current), previousIn = half.contains(previous)
                if currentIn {
                    if !previousIn { out.append(half.crossing(previous, current)) }
                    out.append(current)
                } else if previousIn {
                    out.append(half.crossing(previous, current))
                }
            }
            return out.count >= 3 ? [Contour(out, closed: true)] : []
        }
        var pieces: [Contour] = []
        var run: [Vector2] = []
        for i in points.indices {
            let current = points[i]
            let currentIn = half.contains(current)
            if i > 0 {
                let previous = points[i - 1]
                let previousIn = half.contains(previous)
                if currentIn != previousIn {
                    let cross = half.crossing(previous, current)
                    if currentIn { run.append(cross) } else { run.append(cross); pieces.append(Contour(run, closed: false)); run = [] }
                }
            }
            if currentIn { run.append(current) }
        }
        if run.count >= 2 { pieces.append(Contour(run, closed: false)) }
        return pieces
    }
}

public extension Shape {
    /// The part of the shape on the kept side of `half`: every contour clipped
    /// by one pass against the line (see `Contour.clipped(to:)`), contours that
    /// vanish dropped, and the `winding` kept. A convex shape stays convex. The
    /// shape booleans are not involved, so this costs one walk of the outline.
    func clipped(to half: HalfPlane) -> Shape {
        Shape(contours: contours.flatMap { $0.clipped(to: half) }, winding: winding)
    }

    /// The shape cut along `line` into its two sides, left and right as the
    /// canvas shows them when you look along the line's direction. The two
    /// areas add up to the shape's own.
    func split(along line: Ray2) -> (left: Shape, right: Shape) {
        (clipped(to: HalfPlane(leftOf: line)), clipped(to: HalfPlane(rightOf: line)))
    }

    /// The band of the shape within `distance` of `line` on either side: two
    /// half-plane clips, one from each edge of the band.
    func clipped(within distance: Double, of line: Ray2) -> Shape {
        let normal = Vector2(line.direction.y, -line.direction.x).normalized
        let reach = Swift.max(distance, 0)
        return clipped(to: HalfPlane(point: line.origin + normal * reach, inward: -normal))
            .clipped(to: HalfPlane(point: line.origin - normal * reach, inward: normal))
    }
}
