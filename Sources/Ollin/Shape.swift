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

/// A fillable region made of one or more `Contour`s. Unlike a convex
/// `drawPolygon`, a `Shape` can be **concave** and can have **holes**: extra
/// contours nested inside the outer one cut holes out of the fill (even-odd
/// winding, so a contour's direction doesn't matter). The fill is triangulated;
/// each contour is also stroked as its own outline.
///
/// `Shape` is a value you build, hold, and transform, like `Vector2` and
/// `Rectangle` — not just an immediate draw call.
public struct Shape: Equatable, Sendable {
    public var contours: [Contour]

    public init(contours: [Contour]) {
        self.contours = contours
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
}
