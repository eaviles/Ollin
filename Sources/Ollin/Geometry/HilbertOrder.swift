import Foundation

// Points in the order of a space-filling curve. The Hilbert curve visits every
// cell of a square grid once, and two cells near each other along the curve
// are near each other on the page, so sorting points by where the curve
// visits their cell orders a scatter into one line that stays local: a
// stipple drawn as one stroke, a cloud walked in an order that keeps
// neighbors together, a large set ordered by a single sort.

/// The place of `point` along a Hilbert curve laid over `bounds`: the index
/// of the cell the point falls in, on the curve's visit through a grid of
/// `2^level` by `2^level` cells, from 0 at the first cell to `4^level - 1` at
/// the last. The curve starts at the top left of `bounds` and ends at the top
/// right. A point outside the bounds is read at the nearest cell, and a
/// bounds with no width or no height maps that axis to the first cell.
///
/// At the default `level` of 16 the grid is 65,536 cells across, finer than
/// any canvas, so two points share an index only when they sit within a cell
/// of each other. A lower level makes a coarser order: points in one cell
/// read as the same place, which `hilbertOrder(of:level:)` keeps in their
/// given order. `level` is held to `1 ... 30`.
public func hilbertIndex(of point: Vector2, in bounds: Rectangle, level: Int = 16) -> Int {
    let level = Swift.min(Swift.max(level, 1), 30)
    let n = 1 << level
    func cell(_ value: Double, _ origin: Double, _ extent: Double) -> Int {
        guard extent > 0, value.isFinite else { return 0 }
        let scaled = Swift.min(Swift.max((value - origin) / extent * Double(n), 0), Double(n - 1))
        return Int(scaled)
    }
    return hilbertDistance(x: cell(point.x, bounds.x, bounds.width),
                           y: cell(point.y, bounds.y, bounds.height), n: n)
}

/// The indices of `points` in the order a Hilbert curve over their bounds
/// visits them, so `order.map { points[$0] }` is the points sorted along the
/// curve. Two points in one cell of the curve's grid keep their given order,
/// and the same points always sort the same way. The sort is the whole cost:
/// a hundred thousand points order in a few milliseconds.
///
/// ```swift
/// let order = hilbertOrder(of: dots)
/// drawPolyline(order.map { dots[$0] })          // one line through the dots
/// for (place, i) in order.enumerated() {         // colored along the curve
///     fill(ramp.color(at: Double(place) / Double(dots.count)))
///     drawCircle(center: dots[i], radius: 3)
/// }
/// ```
///
/// The order keeps neighbors together, which is what a plotter or a reveal
/// wants, but it is not a shortest tour: `singleLine(through:)` is the tour,
/// at a far greater cost. The curve's grid is laid over the points' own
/// bounds, so the order follows the scatter's shape rather than the canvas.
public func hilbertOrder(of points: [Vector2], level: Int = 16) -> [Int] {
    guard !points.isEmpty else { return [] }
    var low = Vector2(.infinity, .infinity), high = Vector2(-.infinity, -.infinity)
    for p in points where p.x.isFinite && p.y.isFinite {
        low = Vector2(Swift.min(low.x, p.x), Swift.min(low.y, p.y))
        high = Vector2(Swift.max(high.x, p.x), Swift.max(high.y, p.y))
    }
    guard low.x <= high.x else { return Array(points.indices) }
    let bounds = Rectangle(corner: low, width: high.x - low.x, height: high.y - low.y)
    let keyed = points.indices.map { (key: hilbertIndex(of: points[$0], in: bounds, level: level), index: $0) }
    return keyed.sorted { $0.key != $1.key ? $0.key < $1.key : $0.index < $1.index }.map(\.index)
}

/// `points` sorted along a Hilbert curve over their bounds, the same order
/// `hilbertOrder(of:level:)` gives, as the points themselves. The result is
/// a permutation of the input: every point once, in curve order.
public func hilbertSorted(_ points: [Vector2], level: Int = 16) -> [Vector2] {
    hilbertOrder(of: points, level: level).map { points[$0] }
}

/// The distance along the Hilbert curve of cell `(x, y)` on an `n` by `n`
/// grid, `n` a power of two: at each level the quadrant the cell is in
/// decides which quarter of the curve it lies on, and the cell is turned into
/// that quadrant's own frame for the next level down.
func hilbertDistance(x: Int, y: Int, n: Int) -> Int {
    var x = x, y = y, d = 0
    var s = n >> 1
    while s > 0 {
        let rx = x & s != 0 ? 1 : 0
        let ry = y & s != 0 ? 1 : 0
        d += s * s * ((3 * rx) ^ ry)
        if ry == 0 {
            if rx == 1 {
                x = n - 1 - x
                y = n - 1 - y
            }
            swap(&x, &y)
        }
        s >>= 1
    }
    return d
}
