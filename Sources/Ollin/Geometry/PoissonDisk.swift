import Foundation

/// Blue-noise (Poisson-disk) sampling: an even-but-organic scatter of points in
/// which no two are closer than `radius`. Unlike plain random scatter, there are
/// no clumps and no gaps (the hallmark of *blue noise*), which is exactly what
/// natural-looking stippling, object scatter, and seed sets want. It's the point
/// distribution the packing and `Voronoi` paths like to consume: a Poisson-disk
/// set relaxes into calm, uniform cells with almost no Lloyd iteration.
///
/// This is Bridson's dart-throwing sampler: a background grid sized so each cell
/// holds at most one sample makes the "is anything within `radius`?" test a look
/// at a handful of neighbors, so the whole thing runs in linear time. It draws
/// from `rng`, so the same seed always yields the same layout.
///
/// ```swift
/// var rng = SplitMix64(seed: 7)
/// let points = poissonDisk(in: bounds, radius: 24, using: &rng)
/// let cells = Voronoi(sites: points, bounds: bounds).cells   // even, gap-free
/// ```
///
/// The number of points is set by `radius` and the area, not requested directly
/// (a smaller `radius` packs more in); pass `maxCount` to stop early once enough
/// have landed. `candidates` is how many darts are thrown around each active
/// point before it's retired; Bridson's default of 30 trades a little speed for
/// a tight, even fill.
///
/// - Parameters:
///   - bounds: The rectangle to fill.
///   - radius: The minimum distance between any two points.
///   - candidates: Darts thrown per active point before retiring it (Bridson's `k`).
///   - maxCount: An optional cap on how many points to emit.
///   - rng: The random source to draw from; seed it for a reproducible layout.
/// - Returns: The sampled points, in the order they were placed.
public func poissonDisk<R: RandomNumberGenerator>(
    in bounds: Rectangle,
    radius: Double,
    candidates: Int = 30,
    maxCount: Int? = nil,
    using rng: inout R
) -> [Vector2] {
    guard radius > 0, bounds.width > 0, bounds.height > 0 else { return [] }
    if let maxCount, maxCount <= 0 { return [] }

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

    // Seed with a single random point somewhere in the rectangle.
    insert(Vector2(bounds.x + Double.random(in: 0 ..< 1, using: &rng) * bounds.width,
                   bounds.y + Double.random(in: 0 ..< 1, using: &rng) * bounds.height))

    while !active.isEmpty {
        let ai = Int.random(in: 0 ..< active.count, using: &rng)
        let origin = samples[active[ai]]
        var placed = false

        for _ in 0 ..< Swift.max(candidates, 1) {
            // A point drawn uniformly *by area* from the annulus [radius, 2·radius]:
            // the √ keeps the darts from bunching near the inner ring.
            let angle = Double.random(in: 0 ..< (2 * .pi), using: &rng)
            let dist = radius * (1 + 3 * Double.random(in: 0 ..< 1, using: &rng)).squareRoot()
            let candidate = Vector2(origin.x + cos(angle) * dist,
                                    origin.y + sin(angle) * dist)
            if bounds.contains(candidate), fits(candidate) {
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

    return samples
}

// MARK: - Sketch sugar

public extension Sketch {
    /// A blue-noise (Poisson-disk) scatter of `bounds` (the whole canvas by
    /// default): points spread evenly but organically, with no two closer than
    /// `radius`. Driven by the seeded `random`, so `seed(_:)` makes the layout
    /// reproducible: the same seed always lays the points down the same way.
    ///
    /// The count follows from `radius` and the area, not a request (halving the
    /// radius roughly quadruples the points); pass `maxCount` to stop once enough
    /// have landed.
    ///
    /// ```swift
    /// seed(7)
    /// let dots = poissonDisk(radius: 24)
    /// noStroke(); fill(.black)
    /// drawPoints(dots, size: 4)
    /// // …or feed them straight to the tessellators for even cells:
    /// drawVoronoi(dots)
    /// ```
    func poissonDisk(in bounds: Rectangle? = nil,
                     radius: Double,
                     candidates: Int = 30,
                     maxCount: Int? = nil) -> [Vector2] {
        Ollin.poissonDisk(in: bounds ?? canvasRectangle,
                          radius: radius,
                          candidates: candidates,
                          maxCount: maxCount,
                          using: &rng)
    }
}
