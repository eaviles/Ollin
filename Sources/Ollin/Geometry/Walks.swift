import Foundation

/// The random-walk family: paths built one random step at a time. The plain
/// walk wanders locally, the Lévy flight mixes tight scribbles with sudden
/// long jumps, and the self-avoiding walk threads a lattice without ever
/// crossing itself. All three draw from `rng`, so the same seed always traces
/// the same path, and all three return plain points ready for `drawPolyline`,
/// `Contour`, hatching, or the SVG path.

// MARK: - Plain random walk

/// A simple isotropic random walk: from `start`, take `steps` steps of length
/// `stepLength`, each in a uniformly random direction. The diffusive scribble
/// that stays local (after N steps it has typically drifted only √N step
/// lengths from home), which is exactly its charm: dense, tangled, organic.
///
/// ```swift
/// var rng = SplitMix64(seed: 3)
/// drawPolyline(randomWalk(from: center, steps: 4000, stepLength: 6, using: &rng))
/// ```
///
/// - Parameters:
///   - start: The starting point (also the first point returned).
///   - steps: How many steps to take.
///   - stepLength: The length of every step.
///   - rng: The random source; seed it for a reproducible path.
/// - Returns: `steps + 1` points, beginning at `start`.
public func randomWalk<R: RandomNumberGenerator>(
    from start: Vector2,
    steps: Int,
    stepLength: Double,
    using rng: inout R
) -> [Vector2] {
    guard steps > 0 else { return [start] }
    var points: [Vector2] = [start]
    points.reserveCapacity(steps + 1)
    var current = start
    for _ in 0 ..< steps {
        let angle = Double.random(in: 0 ..< 2 * .pi, using: &rng)
        current = Vector2(current.x + cos(angle) * stepLength,
                          current.y + sin(angle) * stepLength)
        points.append(current)
    }
    return points
}

// MARK: - Lévy flight

/// A Lévy flight: a random walk whose step lengths follow a heavy-tailed power
/// law, so it scribbles tightly in one spot, then leaps far away and scribbles
/// again. The clustered-then-jumping pattern of foraging animals and searching
/// eyes, and a classic generative mark: local texture connected by long strokes.
///
/// Step lengths are drawn from the truncated power law p(l) ∝ l^(-exponent) on
/// [`minStep`, `maxStep`] by inverse-CDF sampling; directions are uniform.
/// `exponent` sets the temperament: near 1 the long jumps dominate, near 3 it
/// approaches an ordinary walk (2, the default, is the classic balance).
///
/// ```swift
/// var rng = SplitMix64(seed: 11)
/// let path = levyFlight(from: center, steps: 600,
///                       minStep: 4, maxStep: 400, using: &rng)
/// drawPolyline(path)
/// ```
///
/// - Parameters:
///   - start: The starting point (also the first point returned).
///   - steps: How many steps to take.
///   - minStep: The shortest possible step (must be > 0; the power law
///     diverges at zero, so a floor is part of the definition).
///   - maxStep: The longest possible step.
///   - exponent: The power-law exponent μ, canonically in 1...3.
///   - rng: The random source; seed it for a reproducible path.
/// - Returns: `steps + 1` points, beginning at `start`.
public func levyFlight<R: RandomNumberGenerator>(
    from start: Vector2,
    steps: Int,
    minStep: Double,
    maxStep: Double,
    exponent: Double = 2,
    using rng: inout R
) -> [Vector2] {
    guard steps > 0, minStep > 0, maxStep >= minStep else { return [start] }
    var points: [Vector2] = [start]
    points.reserveCapacity(steps + 1)
    var current = start
    for _ in 0 ..< steps {
        let u = Double.random(in: 0 ..< 1, using: &rng)
        let length: Double
        if abs(exponent - 1) < 1e-9 {
            // μ = 1 is the log-uniform limit of the inverse CDF below.
            length = minStep * pow(maxStep / minStep, u)
        } else {
            // Inverse CDF of p(l) ∝ l^(-μ) truncated to [minStep, maxStep].
            let oneMinusMu = 1 - exponent
            let a = pow(minStep, oneMinusMu)
            let b = pow(maxStep, oneMinusMu)
            length = pow(a + u * (b - a), 1 / oneMinusMu)
        }
        let angle = Double.random(in: 0 ..< 2 * .pi, using: &rng)
        current = Vector2(current.x + cos(angle) * length,
                          current.y + sin(angle) * length)
        points.append(current)
    }
    return points
}

// MARK: - Self-avoiding walk

/// A self-avoiding walk: a path over a square lattice that never revisits a
/// cell. Grown depth-first with backtracking, so instead of dying the moment
/// it boxes itself in (as the naive walk almost always does), it retreats and
/// tries another way, threading a long single line through the grid: the
/// dense, maze-like meander of one unbroken stroke.
///
/// The lattice is `cellSize`-square cells centered in `bounds`, and the path
/// visits cell centers, each step moving to an orthogonal neighbor. Cells once
/// visited stay blocked forever (backtracking retreats *through* them but
/// never re-enters), which is what makes the search finite and the final path
/// self-avoiding. The longest path found is returned; pass `maxLength` to stop
/// as soon as the path reaches that many points.
///
/// ```swift
/// var rng = SplitMix64(seed: 5)
/// let path = selfAvoidingWalk(in: bounds, cellSize: 24, using: &rng)
/// drawPolyline(path)
/// ```
///
/// Deterministic given the seed: the neighbor order is shuffled with `rng` at
/// each cell, and everything else iterates in fixed order.
///
/// - Parameters:
///   - bounds: The rectangle the lattice is fitted into.
///   - cellSize: The lattice spacing (one step length).
///   - start: Where to begin; snapped to the nearest cell. Defaults to the
///     center of `bounds`.
///   - maxLength: An optional cap on the number of points returned.
///   - rng: The random source; seed it for a reproducible path.
/// - Returns: The path's points (cell centers), beginning at the start cell.
public func selfAvoidingWalk<R: RandomNumberGenerator>(
    in bounds: Rectangle,
    cellSize: Double,
    from start: Vector2? = nil,
    maxLength: Int? = nil,
    using rng: inout R
) -> [Vector2] {
    guard cellSize > 0, bounds.width > 0, bounds.height > 0 else { return [] }
    let cols = Swift.max(Int(bounds.width / cellSize), 1)
    let rows = Swift.max(Int(bounds.height / cellSize), 1)
    if let maxLength, maxLength <= 0 { return [] }

    // The lattice is centered in the bounds, like the tiling grids.
    let originX = bounds.x + (bounds.width - Double(cols) * cellSize) / 2
    let originY = bounds.y + (bounds.height - Double(rows) * cellSize) / 2
    func center(of cell: Int) -> Vector2 {
        Vector2(originX + (Double(cell % cols) + 0.5) * cellSize,
                originY + (Double(cell / cols) + 0.5) * cellSize)
    }

    let startPoint = start ?? Vector2(bounds.x + bounds.width / 2, bounds.y + bounds.height / 2)
    let startCol = Swift.min(Swift.max(Int((startPoint.x - originX) / cellSize), 0), cols - 1)
    let startRow = Swift.min(Swift.max(Int((startPoint.y - originY) / cellSize), 0), rows - 1)
    let startCell = startRow * cols + startCol

    var visited = [Bool](repeating: false, count: cols * rows)
    // Parent links let the best path be reconstructed after backtracking:
    // visited cells are never re-entered, so a cell's parent never changes.
    var parent = [Int](repeating: -1, count: cols * rows)

    // One DFS frame per path cell: the cell plus its shuffled, not-yet-tried
    // neighbor directions (indices into `offsets`).
    let offsets = [(0, -1), (1, 0), (0, 1), (-1, 0)]
    var stack: [(cell: Int, directions: [Int], next: Int)] = []

    func shuffledDirections() -> [Int] {
        var order = [0, 1, 2, 3]
        // Fisher-Yates over the fixed base order, driven by `rng` alone.
        for i in (1 ..< order.count).reversed() {
            let j = Int.random(in: 0 ... i, using: &rng)
            order.swapAt(i, j)
        }
        return order
    }

    visited[startCell] = true
    stack.append((startCell, shuffledDirections(), 0))
    var bestEnd = startCell
    var bestLength = 1

    while let top = stack.last {
        if let maxLength, stack.count >= maxLength { bestEnd = top.cell; bestLength = stack.count; break }
        if top.next >= top.directions.count {
            stack.removeLast()
            continue
        }
        stack[stack.count - 1].next += 1
        let (dx, dy) = offsets[top.directions[top.next]]
        let col = top.cell % cols + dx
        let row = top.cell / cols + dy
        guard col >= 0, col < cols, row >= 0, row < rows else { continue }
        let neighbor = row * cols + col
        guard !visited[neighbor] else { continue }
        visited[neighbor] = true
        parent[neighbor] = top.cell
        stack.append((neighbor, shuffledDirections(), 0))
        if stack.count > bestLength {
            bestLength = stack.count
            bestEnd = neighbor
        }
    }

    // Walk the parent chain back from the best endpoint.
    var path: [Vector2] = []
    path.reserveCapacity(bestLength)
    var cell = bestEnd
    while cell >= 0 {
        path.append(center(of: cell))
        cell = parent[cell]
    }
    return path.reversed()
}

// MARK: - Sketch sugar

public extension Sketch {
    /// A simple random walk from `start` (the canvas center by default):
    /// `steps` steps of `stepLength`, each in a uniformly random direction.
    /// Driven by the seeded `random`, so `seed(_:)` reproduces the path.
    func randomWalk(from start: Vector2? = nil,
                    steps: Int,
                    stepLength: Double) -> [Vector2] {
        Ollin.randomWalk(from: start ?? Vector2(width / 2, height / 2),
                         steps: steps,
                         stepLength: stepLength,
                         using: &rng)
    }

    /// A Lévy flight from `start` (the canvas center by default): tight local
    /// scribbles connected by sudden long jumps, the step lengths drawn from a
    /// truncated power law on [`minStep`, `maxStep`]. Driven by the seeded
    /// `random`, so `seed(_:)` reproduces the path.
    func levyFlight(from start: Vector2? = nil,
                    steps: Int,
                    minStep: Double,
                    maxStep: Double,
                    exponent: Double = 2) -> [Vector2] {
        Ollin.levyFlight(from: start ?? Vector2(width / 2, height / 2),
                         steps: steps,
                         minStep: minStep,
                         maxStep: maxStep,
                         exponent: exponent,
                         using: &rng)
    }

    /// A self-avoiding walk over a `cellSize` lattice in `bounds` (the whole
    /// canvas by default): one unbroken path that never crosses itself, grown
    /// with backtracking so it winds long instead of dying early. Driven by
    /// the seeded `random`, so `seed(_:)` reproduces the path.
    func selfAvoidingWalk(in bounds: Rectangle? = nil,
                          cellSize: Double,
                          from start: Vector2? = nil,
                          maxLength: Int? = nil) -> [Vector2] {
        Ollin.selfAvoidingWalk(in: bounds ?? canvasRectangle,
                               cellSize: cellSize,
                               from: start,
                               maxLength: maxLength,
                               using: &rng)
    }
}
