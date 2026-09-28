import Foundation

/// Scattering points inside a `Shape` and along its outline: the region a
/// fill covers, holes left out, rather than the box around it.
///
/// A shape with a hole, a concave outline, or several islands still scatters
/// evenly, because the points are drawn from the same triangles the fill is
/// made of: a triangle is picked in proportion to its area, then a point
/// inside it. Nothing is thrown at the bounding box and thinned, so a thin
/// or sparse shape costs no more than a compact one.
///
/// ```swift
/// let glyph = textToShapes("O", size: 400)[0]
/// let dots = randomPoints(in: glyph, count: 800)      // inside the letter, none in its counter
/// let rim = randomPoints(along: glyph, count: 200)    // on its outline, even by length
/// let spread = poissonDisk(in: glyph, radius: 12)     // blue noise, kept inside
/// ```
///
/// Every form draws from `rng`, so the same seed always lays the points down
/// the same way. The `Sketch` forms below run on the sketch's own seeded
/// `random`.

// MARK: - Inside

/// `count` points scattered evenly over the filled region of `shape`, under
/// the shape's own `winding` rule, so a hole receives none and a concave bay
/// receives its share.
///
/// - Parameters:
///   - shape: The region to fill. Open contours sit out, the way a fill
///     ignores them; a shape with no area returns no points.
///   - count: How many points to return.
///   - rng: The random source; seed it for a layout that repeats.
/// - Returns: The points, in the order they were drawn.
public func randomPoints<R: RandomNumberGenerator>(
    in shape: Shape,
    count: Int,
    using rng: inout R
) -> [Vector2] {
    guard count > 0 else { return [] }
    let table = ShapeAreaTable(shape)
    guard table.total > 0 else { return [] }
    var out: [Vector2] = []
    out.reserveCapacity(count)
    for _ in 0 ..< count {
        out.append(table.draw(using: &rng))
    }
    return out
}

// MARK: - Along the outline

/// `count` points scattered along the outline of `shape`, evenly by walked
/// length: a long edge receives more than a short one, and a point never
/// favors a corner over the middle of a side however the points are spaced.
///
/// Every contour with at least two points takes part, open ones included,
/// since each is stroked as an outline; a closed contour's walk includes the
/// segment back to its start.
///
/// - Parameters:
///   - shape: The outline to scatter along. A shape whose contours have no
///     length returns no points.
///   - count: How many points to return.
///   - rng: The random source; seed it for a layout that repeats.
/// - Returns: The points, in the order they were drawn.
public func randomPoints<R: RandomNumberGenerator>(
    along shape: Shape,
    count: Int,
    using rng: inout R
) -> [Vector2] {
    guard count > 0 else { return [] }
    let table = OutlineLengthTable(shape)
    guard table.total > 0 else { return [] }
    var out: [Vector2] = []
    out.reserveCapacity(count)
    for _ in 0 ..< count {
        out.append(table.point(at: Double.random(in: 0 ..< table.total, using: &rng)))
    }
    return out
}

// MARK: - Blue noise inside

/// A blue-noise (Poisson-disk) scatter of the filled region of `shape`: even
/// but organic, no two points closer than `radius`, none in a hole.
///
/// This is the same dart-throwing the rectangle form of `poissonDisk` runs,
/// with the shape's fill as the place a dart may land.
/// Each seed is drawn from the fill's own triangles rather than from the box
/// around the shape, and when the darts around every placed point have all
/// missed, a fresh seed is drawn the same way and the throwing goes on; so a
/// thin shape, where most darts thrown around a point fall outside, still
/// fills, and a shape of several islands fills every island, not only the one
/// the first seed landed in. Throwing stops when `candidates` fresh seeds in a
/// row find no room.
///
/// - Parameters:
///   - shape: The region to fill, under its own `winding` rule. Open contours
///     sit out; a shape with no area returns no points.
///   - radius: The minimum distance between any two points.
///   - candidates: Darts thrown around each placed point before it is
///     retired, and fresh seeds tried before the scatter is called full.
///   - maxCount: An optional cap on how many points to emit.
///   - rng: The random source; seed it for a layout that repeats.
/// - Returns: The sampled points, in the order they were placed.
public func poissonDisk<R: RandomNumberGenerator>(
    in shape: Shape,
    radius: Double,
    candidates: Int = 30,
    maxCount: Int? = nil,
    using rng: inout R
) -> [Vector2] {
    guard radius > 0, let bounds = shape.bounds else { return [] }
    if let maxCount, maxCount <= 0 { return [] }
    let table = ShapeAreaTable(shape)
    guard table.total > 0 else { return [] }

    // A cell of side r/√2 holds at most one sample, so a candidate only has to
    // check the samples in the 5×5 block of cells around it: nothing farther can
    // be within `radius`.
    let cell = radius / 2.0.squareRoot()
    let cols = Swift.max(Int((bounds.width / cell).rounded(.up)), 1)
    let rows = Swift.max(Int((bounds.height / cell).rounded(.up)), 1)
    var grid = [Int](repeating: -1, count: cols * rows)   // sample index per cell, −1 = empty

    var samples: [Vector2] = []
    var active: [Int] = []
    let r2 = radius * radius
    let tries = Swift.max(candidates, 1)

    func cellOf(_ p: Vector2) -> (col: Int, row: Int) {
        let col = Swift.min(Swift.max(Int((p.x - bounds.x) / cell), 0), cols - 1)
        let row = Swift.min(Swift.max(Int((p.y - bounds.y) / cell), 0), rows - 1)
        return (col, row)
    }

    /// Whether `p` is at least `radius` from every existing sample.
    func fits(_ p: Vector2) -> Bool {
        let (col, row) = cellOf(p)
        for r in Swift.max(row - 2, 0)...Swift.min(row + 2, rows - 1) {
            for c in Swift.max(col - 2, 0)...Swift.min(col + 2, cols - 1) {
                let idx = grid[r * cols + c]
                if idx >= 0, samples[idx].distanceSquared(to: p) < r2 { return false }
            }
        }
        return true
    }

    func insert(_ p: Vector2) {
        let (col, row) = cellOf(p)
        grid[row * cols + col] = samples.count
        active.append(samples.count)
        samples.append(p)
    }

    /// A fresh seed from the fill's own triangles, or `nil` when `tries` in a
    /// row found no room: the scatter is full.
    func seed() -> Vector2? {
        for _ in 0 ..< tries {
            let p = table.draw(using: &rng)
            if fits(p) { return p }
        }
        return nil
    }

    while let start = seed() {
        insert(start)
        if let maxCount, samples.count >= maxCount { return samples }

        while !active.isEmpty {
            let ai = Int.random(in: 0 ..< active.count, using: &rng)
            let origin = samples[active[ai]]
            var placed = false

            for _ in 0 ..< tries {
                // A point drawn uniformly *by area* from the annulus [radius, 2·radius]:
                // the √ keeps the darts from bunching near the inner ring.
                let angle = Double.random(in: 0 ..< (2 * .pi), using: &rng)
                let dist = radius * (1 + 3 * Double.random(in: 0 ..< 1, using: &rng)).squareRoot()
                let candidate = Vector2(origin.x + cos(angle) * dist,
                                        origin.y + sin(angle) * dist)
                if bounds.contains(candidate), shape.contains(candidate), fits(candidate) {
                    insert(candidate)
                    placed = true
                    if let maxCount, samples.count >= maxCount { return samples }
                    break
                }
            }

            // No dart landed: this point can't seed any more neighbors, so retire it.
            if !placed {
                active.swapAt(ai, active.count - 1)
                active.removeLast()
            }
        }
    }

    return samples
}

// MARK: - Picking a triangle by area

/// The fill's triangles with a running total of their areas, which turns one
/// number in `0 ..< total` into a triangle chosen in proportion to its area,
/// and a point inside it from two more.
struct ShapeAreaTable {

    /// The corners of each triangle that has area, three per triangle.
    private var corners: [Vector2] = []
    /// `cumulative[t]` is the area of triangles `0 ... t`.
    private var cumulative: [Double] = []

    var total: Double { cumulative.last ?? 0 }

    init(_ shape: Shape) {
        let vertices = shape.triangulatedFill()
        var running = 0.0
        var i = 0
        corners.reserveCapacity(vertices.count)
        cumulative.reserveCapacity(vertices.count / 3)
        while i + 2 < vertices.count {
            let a = vertices[i], b = vertices[i + 1], c = vertices[i + 2]
            i += 3
            let area = abs((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)) / 2
            guard area > 0 else { continue }
            running += area
            cumulative.append(running)
            corners.append(a); corners.append(b); corners.append(c)
        }
    }

    /// One point drawn evenly over the whole fill.
    func draw<R: RandomNumberGenerator>(using rng: inout R) -> Vector2 {
        let t = triangle(at: Double.random(in: 0 ..< total, using: &rng))
        let u = Double.random(in: 0 ..< 1, using: &rng)
        let v = Double.random(in: 0 ..< 1, using: &rng)
        let bary = ollinTriangleBarycentric(u, v)
        let a = corners[3 * t], b = corners[3 * t + 1], c = corners[3 * t + 2]
        return a * bary.x + b * bary.y + c * bary.z
    }

    /// The triangle holding `u`, which the caller draws in `0 ..< total`.
    private func triangle(at u: Double) -> Int {
        var lo = 0, hi = cumulative.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if cumulative[mid] <= u { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }
}

// MARK: - Walking the outline by length

/// Every segment of every contour with a running total of their lengths, which
/// turns one number in `0 ..< total` into a point that far along the whole
/// outline.
struct OutlineLengthTable {

    /// The two ends of each segment that has length.
    private var segments: [(Vector2, Vector2)] = []
    /// `cumulative[s]` is the length of segments `0 ... s`.
    private var cumulative: [Double] = []

    var total: Double { cumulative.last ?? 0 }

    init(_ shape: Shape) {
        var running = 0.0
        for contour in shape.contours where contour.points.count >= 2 {
            let points = contour.points
            let count = contour.isClosed ? points.count : points.count - 1
            for i in 0 ..< count {
                let a = points[i], b = points[(i + 1) % points.count]
                let length = a.distance(to: b)
                guard length > 0 else { continue }
                running += length
                cumulative.append(running)
                segments.append((a, b))
            }
        }
    }

    /// The point `walked` along the outline, in `0 ..< total`.
    func point(at walked: Double) -> Vector2 {
        var lo = 0, hi = cumulative.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if cumulative[mid] <= walked { lo = mid + 1 } else { hi = mid }
        }
        let (a, b) = segments[lo]
        let start = lo == 0 ? 0 : cumulative[lo - 1]
        let length = cumulative[lo] - start
        return a + (b - a) * ((walked - start) / length)
    }
}

// MARK: - Sketch sugar

public extension Sketch {
    /// `count` points scattered evenly inside `shape`, holes left out. Driven
    /// by the seeded `random`, so `seed(_:)` makes the layout reproducible.
    ///
    /// ```swift
    /// seed(4)
    /// let dots = randomPoints(in: blob, count: 600)
    /// noStroke(); fill(.black)
    /// drawPoints(dots, size: 3)
    /// ```
    func randomPoints(in shape: Shape, count: Int) -> [Vector2] {
        Ollin.randomPoints(in: shape, count: count, using: &rng)
    }

    /// `count` points scattered along the outline of `shape`, evenly by
    /// length. Driven by the seeded `random`.
    func randomPoints(along shape: Shape, count: Int) -> [Vector2] {
        Ollin.randomPoints(along: shape, count: count, using: &rng)
    }

    /// A blue-noise (Poisson-disk) scatter of the inside of `shape`: no two
    /// points closer than `radius`, none in a hole, every island filled.
    /// Driven by the seeded `random`. The count follows from `radius` and the
    /// shape's area; pass `maxCount` to stop once enough have landed.
    ///
    /// ```swift
    /// seed(7)
    /// let dots = poissonDisk(in: letter, radius: 14)
    /// ```
    func poissonDisk(in shape: Shape,
                     radius: Double,
                     candidates: Int = 30,
                     maxCount: Int? = nil) -> [Vector2] {
        Ollin.poissonDisk(in: shape,
                          radius: radius,
                          candidates: candidates,
                          maxCount: maxCount,
                          using: &rng)
    }
}
