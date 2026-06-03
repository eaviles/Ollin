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
}
