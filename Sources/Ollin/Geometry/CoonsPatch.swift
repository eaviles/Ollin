import Foundation

// A four-sided region whose sides are curves, and the edit that bends an
// outline into one. The patch reads every side by the fraction walked along
// it, so a side's midpoint is the patch's midpoint on that side, and blends
// the four sides the way Coons did: two ruled surfaces between opposite
// sides, added, less the plane through the four corners that both of them
// counted. With four straight sides that blend is the bilinear map from the
// corners, so one value covers both forms.

/// A four-sided region whose sides are curves, read like a rectangle: `u`
/// runs 0 to 1 from the left side to the right, `v` 0 to 1 from the top side
/// to the bottom, and `point(u:v:)` is the place at those fractions. Bend an
/// outline into it with `Contour.warped(from:into:)`, and lettering set in a
/// rectangle lands on a waving banner, a tile on a bulging cushion.
///
/// Give four curves (`init(top:right:bottom:left:)`) and every side of the
/// patch follows its curve exactly, the blend between them filling the
/// inside smoothly (a Coons patch); give four corners
/// (`init(topLeft:topRight:bottomRight:bottomLeft:)`) and the sides are
/// straight, the bilinear map. A patch made from a `Rectangle` is that
/// rectangle, so `point(u:v:)` agrees with `Rectangle.point(u:v:)`.
///
/// ```swift
/// let page = Rectangle(x: 140, y: 400, width: 800, height: 280)
/// let wave = { (y: Double) in Contour((0 ... 20).map { i in
///     Vector2(140 + Double(i) * 40, y + 50 * sin(Double(i) * 0.5 + time))
/// }, closed: false) }
/// let banner = CoonsPatch(top: wave(400), right: Contour([Vector2(940, 400), Vector2(940, 680)], closed: false),
///                         bottom: wave(680), left: Contour([Vector2(140, 400), Vector2(140, 680)], closed: false))
/// for glyph in textToShapes("ollin", 540, 600) {
///     drawShape(glyph.warped(from: page, into: banner))
/// }
/// ```
public struct CoonsPatch: Equatable, Sendable {
    /// The top side, from the top-left corner to the top-right.
    public let top: Contour
    /// The right side, from the top-right corner to the bottom-right.
    public let right: Contour
    /// The bottom side, from the bottom-left corner to the bottom-right.
    public let bottom: Contour
    /// The left side, from the top-left corner to the bottom-left.
    public let left: Contour

    /// The corner where the top and left sides meet, `point(u: 0, v: 0)`.
    public let topLeft: Vector2
    /// The corner where the top and right sides meet, `point(u: 1, v: 0)`.
    public let topRight: Vector2
    /// The corner where the bottom and right sides meet, `point(u: 1, v: 1)`.
    public let bottomRight: Vector2
    /// The corner where the bottom and left sides meet, `point(u: 0, v: 1)`.
    public let bottomLeft: Vector2

    private let topSide: Side
    private let rightSide: Side
    private let bottomSide: Side
    private let leftSide: Side

    /// A patch bounded by four curves, each followed exactly. `top` runs from
    /// the top-left corner to the top-right, and it sets the patch's
    /// direction: any other side given the other way round is turned to
    /// meet it (the left side starts at the end nearer the top's start, the
    /// right side at the end nearer the top's end, and the bottom at the end
    /// nearer the left side's end). Each side is read by the fraction walked
    /// along it, so `point(u: 0.5, v: 0)` is the top curve's midpoint by
    /// length, however its points are spaced.
    ///
    /// The sides are meant to meet at the four corners. Where two ends miss
    /// each other, the corner is the point halfway between them, and the
    /// difference is spread across the patch so that each side still keeps
    /// its own shape. A side of one point pinches the patch to that point (a
    /// triangle), and an empty side runs straight between the corners of its
    /// two neighbors.
    public init(top: Contour, right: Contour, bottom: Contour, left: Contour) {
        let top = Self.open(top)
        let topStart = top.points.first, topEnd = top.points.last
        let left = Self.open(left, startingNear: topStart)
        let right = Self.open(right, startingNear: topEnd)
        let bottom = Self.open(bottom, startingNear: left.points.last ?? topStart)

        // Each corner is halfway between the two ends that meet there; a
        // missing end leaves the other one to decide.
        func meet(_ a: Vector2?, _ b: Vector2?) -> Vector2 {
            switch (a, b) {
            case let (a?, b?): return (a + b) * 0.5
            case let (a?, nil): return a
            case let (nil, b?): return b
            default: return .zero
            }
        }
        let topLeft = meet(top.points.first, left.points.first)
        let topRight = meet(top.points.last, right.points.first)
        let bottomLeft = meet(bottom.points.first, left.points.last)
        let bottomRight = meet(bottom.points.last, right.points.last)

        // An empty side becomes the straight run between its two corners, so
        // every side has a shape to read.
        func filled(_ side: Contour, _ a: Vector2, _ b: Vector2) -> Contour {
            side.points.isEmpty ? Contour([a, b], closed: false) : side
        }
        self.top = filled(top, topLeft, topRight)
        self.right = filled(right, topRight, bottomRight)
        self.bottom = filled(bottom, bottomLeft, bottomRight)
        self.left = filled(left, topLeft, bottomLeft)
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
        topSide = Side(self.top)
        rightSide = Side(self.right)
        bottomSide = Side(self.bottom)
        leftSide = Side(self.left)
    }

    /// A patch with straight sides between four corners: the bilinear map,
    /// where `point(u:v:)` is the place `u` of the way across and `v` of the
    /// way down, read between the corners. A tile tilted into perspective, a
    /// card skewed, a square pinched toward one corner.
    public init(topLeft: Vector2, topRight: Vector2, bottomRight: Vector2, bottomLeft: Vector2) {
        self.init(top: Contour([topLeft, topRight], closed: false),
                  right: Contour([topRight, bottomRight], closed: false),
                  bottom: Contour([bottomLeft, bottomRight], closed: false),
                  left: Contour([topLeft, bottomLeft], closed: false))
    }

    /// The patch that is `rectangle` itself, the starting point to bend from:
    /// `point(u:v:)` agrees with `rectangle.point(u:v:)`, and an outline
    /// warped from the rectangle into it comes back where it was.
    public init(_ rectangle: Rectangle) {
        self.init(topLeft: rectangle.topLeft, topRight: rectangle.topRight,
                  bottomRight: rectangle.bottomRight, bottomLeft: rectangle.bottomLeft)
    }

    /// The place at fractions `u` across (0 on the left side, 1 on the
    /// right) and `v` down (0 on the top side, 1 on the bottom). Along an
    /// edge of the square of fractions it is the side itself: `point(u: t,
    /// v: 0)` is the point `t` of the way along the top curve by length.
    /// Fractions outside 0 to 1 carry on past the sides in the direction
    /// each was heading at its end, so a point outside the rectangle it was
    /// warped from lands outside the patch rather than piling up on an edge.
    public func point(u: Double, v: Double) -> Vector2 {
        // Two ruled surfaces, one between the top and bottom curves and one
        // between the left and right, added, less the bilinear surface of
        // the corners that both of them included.
        let acrossV = topSide.point(at: u) * (1 - v) + bottomSide.point(at: u) * v
        let acrossU = leftSide.point(at: v) * (1 - u) + rightSide.point(at: v) * u
        let corners = topLeft * ((1 - u) * (1 - v)) + topRight * (u * (1 - v))
            + bottomLeft * ((1 - u) * v) + bottomRight * (u * v)
        return acrossV + acrossU - corners
    }

    /// The patch's outline, closed and clockwise on the canvas: along the
    /// top, down the right, back along the bottom, and up the left, each
    /// side through its own points as the patch reads them (so where the
    /// sides meet at their corners, exactly the four curves).
    public var contour: Contour {
        var out: [Vector2] = []
        for t in topSide.fractions { out.append(point(u: t, v: 0)) }
        for t in rightSide.fractions.dropFirst() { out.append(point(u: 1, v: t)) }
        for t in bottomSide.fractions.reversed().dropFirst() { out.append(point(u: t, v: 1)) }
        for t in leftSide.fractions.reversed().dropFirst().dropLast() { out.append(point(u: 0, v: t)) }
        return Contour(out, closed: true)
    }

    public static func == (a: CoonsPatch, b: CoonsPatch) -> Bool {
        a.top == b.top && a.right == b.right && a.bottom == b.bottom && a.left == b.left
    }

    /// `side` as an open run of points, turned round when its end is nearer
    /// `anchor` than its start is.
    private static func open(_ side: Contour, startingNear anchor: Vector2? = nil) -> Contour {
        var points = side.points
        if side.isClosed, let first = points.first { points.append(first) }
        if let anchor, let first = points.first, let last = points.last,
           last.distanceSquared(to: anchor) < first.distanceSquared(to: anchor) {
            points.reverse()
        }
        return Contour(points, closed: false)
    }

    /// One side read by the fraction walked along it, carried on straight
    /// past either end.
    private struct Side: Sendable {
        let walk: Contour.Walk?
        let point: Vector2
        /// The fraction of the walk at each of the side's own points, the
        /// places the outline reads it at.
        let fractions: [Double]

        init(_ contour: Contour) {
            walk = Contour.Walk(contour)
            point = contour.points.first ?? .zero
            if let walk {
                fractions = walk.cumulative.map { $0 / walk.total }
            } else {
                fractions = [0, 1]
            }
        }

        func point(at t: Double) -> Vector2 {
            guard let walk else { return point }
            guard t.isFinite else { return walk.points[0] }
            if t < 0 {
                let start = walk.points[0], next = walk.points[1]
                return start + (start - next).normalized * (-t * walk.total)
            }
            if t > 1 {
                let n = walk.points.count
                let end = walk.points[n - 1], before = walk.points[n - 2]
                return end + (end - before).normalized * ((t - 1) * walk.total)
            }
            return walk.point(atDistance: t * walk.total)
        }
    }
}

public extension Contour {
    /// A copy bent from `rectangle` into `patch`: every point is read as
    /// fractions across and down the rectangle (`Rectangle.uv(of:)`) and put
    /// at the same fractions in the patch (`CoonsPatch.point(u:v:)`), so
    /// lettering set in a box lands on a waving banner with its first letter
    /// at the left side and its last at the right. A patch made from the
    /// rectangle gives the outline back unchanged.
    ///
    /// Straight runs of the outline are given extra points first, so a
    /// straight edge bends with the patch instead of staying straight
    /// between its two ends; `spacing` is the longest straight stretch left,
    /// measured before the bend (0 keeps the points as they are). Every
    /// original point stays, so corners survive. A point outside the
    /// rectangle lands outside the patch, carried past its sides.
    ///
    /// ```swift
    /// let box = Rectangle(x: 100, y: 100, width: 400, height: 200)
    /// let tilted = CoonsPatch(topLeft: Vector2(140, 80), topRight: Vector2(520, 140),
    ///                         bottomRight: Vector2(480, 360), bottomLeft: Vector2(100, 300))
    /// drawShape(Shape(contours: [outline.warped(from: box, into: tilted)]))
    /// ```
    func warped(from rectangle: Rectangle, into patch: CoonsPatch, spacing: Double = 4) -> Contour {
        let dense = refined(maxSegment: spacing)
        return Contour(dense.points.map { p in
            let uv = rectangle.uv(of: p)
            return patch.point(u: uv.x, v: uv.y)
        }, closed: isClosed)
    }
}

public extension Shape {
    /// Every contour bent from `rectangle` into `patch` (see
    /// `Contour.warped(from:into:spacing:)`), keeping the `winding` rule, so
    /// a glyph's counter bends with its outline. Bend every glyph of a word
    /// from the one rectangle that holds the whole word, and the word bends
    /// as one piece.
    func warped(from rectangle: Rectangle, into patch: CoonsPatch, spacing: Double = 4) -> Shape {
        Shape(contours: contours.map { $0.warped(from: rectangle, into: patch, spacing: spacing) },
              winding: winding)
    }
}
