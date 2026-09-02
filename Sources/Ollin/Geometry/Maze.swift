import Foundation

/// Maze generation: carve a *perfect maze* (every cell reachable, no loops, so
/// any two cells are joined by exactly one path) over a `columns × rows` grid,
/// then read it as geometry. The walls come back as merged straight `Contour`
/// runs (long polylines, not per-cell fragments), so the maze strokes, hatches,
/// and exports to SVG for a pen plotter like any other line-work.
///
/// Three carving algorithms are built in, and the choice is a *texture* parameter as
/// much as an algorithmic one:
///
/// - `.backtracker` (randomized depth-first search) wanders as far as it can
///   before backing up, so it carves long, winding corridors with few dead ends:
///   the classic "river" maze.
/// - `.kruskal` (randomized Kruskal's) carves random walls anywhere in the grid
///   (union-find keeps it loop-free), so it scatters many short dead ends into
///   an even, all-over texture.
/// - `.wilson` (loop-erased random walks) samples *uniformly* over every
///   possible maze of the grid: no bias, no texture fingerprint.
///
/// The carve draws from `rng`, so the same seed always builds the same maze.
///
/// ```swift
/// var rng = SplitMix64(seed: 9)
/// let maze = Maze(columns: 24, rows: 24, algorithm: .backtracker, using: &rng)
/// for wall in maze.walls(in: bounds) { drawPolyline(wall.points) }
/// let route = maze.longestPath()
/// drawPolyline(maze.contour(of: route, in: bounds).points)
/// ```
public struct Maze: Equatable, Hashable, Sendable {
    /// The carving algorithm: each yields a perfect maze, with its own texture.
    public enum Algorithm: Sendable, CaseIterable {
        /// Randomized depth-first search: long winding corridors, few dead ends.
        case backtracker
        /// Randomized Kruskal's over union-find: many short dead ends, an even
        /// all-over texture.
        case kruskal
        /// Wilson's loop-erased random walks: a uniform sample over *all*
        /// possible mazes of the grid, so there is no bias at all.
        case wilson
    }

    /// A compass direction between adjacent cells (the canvas is y-down, so
    /// `.north` is the row above).
    public enum Direction: Int, Sendable, CaseIterable {
        case north = 0, east, south, west

        /// The opposite direction (`.north` ↔ `.south`, `.east` ↔ `.west`).
        public var opposite: Direction { Direction(rawValue: (rawValue + 2) % 4)! }

        var delta: (dc: Int, dr: Int) {
            switch self {
            case .north: return (0, -1)
            case .east: return (1, 0)
            case .south: return (0, 1)
            case .west: return (-1, 0)
            }
        }
    }

    public let columns: Int
    public let rows: Int

    /// Per-cell carved-passage bits, row-major; bit `1 << direction.rawValue`
    /// set means the wall on that side is open.
    private var links: [UInt8]

    /// Carve a `columns × rows` perfect maze with `algorithm`, drawing every
    /// random choice from `rng` (seed it for a reproducible maze).
    public init<R: RandomNumberGenerator>(columns: Int, rows: Int,
                                          algorithm: Algorithm = .backtracker,
                                          using rng: inout R) {
        self.columns = Swift.max(1, columns)
        self.rows = Swift.max(1, rows)
        self.links = [UInt8](repeating: 0, count: self.columns * self.rows)
        switch algorithm {
        case .backtracker: carveBacktracker(using: &rng)
        case .kruskal: carveKruskal(using: &rng)
        case .wilson: carveWilson(using: &rng)
        }
    }

    // MARK: - Reading the maze

    /// Whether the passage from the cell at `column`, `row` toward `direction`
    /// is open (carved). Out-of-bounds cells read closed.
    public func isOpen(_ direction: Direction, column: Int, row: Int) -> Bool {
        guard column >= 0, column < columns, row >= 0, row < rows else { return false }
        return links[row * columns + column] & (1 << UInt8(direction.rawValue)) != 0
    }

    /// The center of the cell at `column`, `row` when the maze is laid over
    /// `bounds` (cells split the rectangle evenly).
    public func center(ofColumn column: Int, row: Int, in bounds: Rectangle) -> Vector2 {
        let w = bounds.width / Double(columns), h = bounds.height / Double(rows)
        return Vector2(bounds.x + (Double(column) + 0.5) * w,
                       bounds.y + (Double(row) + 0.5) * h)
    }

    /// The maze's walls laid over `bounds`, as open `Contour`s. Collinear wall
    /// segments merge into single long runs (each straight stretch of wall is
    /// one two-point contour), so the line-work stays clean for stroking,
    /// hatching, and plotter export. The outer border is included.
    public func walls(in bounds: Rectangle) -> [Contour] {
        let w = bounds.width / Double(columns), h = bounds.height / Double(rows)
        var out: [Contour] = []

        // Horizontal walls: line r sits above row r (r == rows is the bottom
        // border). A segment exists over cell c when the passage across the
        // line is closed.
        for r in 0...rows {
            var runStart: Int? = nil
            for c in 0...columns {   // one past the end flushes the last run
                let wallHere = c < columns && !(r > 0 && isOpen(.south, column: c, row: r - 1))
                if wallHere {
                    if runStart == nil { runStart = c }
                } else if let start = runStart {
                    let y = bounds.y + Double(r) * h
                    out.append(Contour([Vector2(bounds.x + Double(start) * w, y),
                                        Vector2(bounds.x + Double(c) * w, y)], closed: false))
                    runStart = nil
                }
            }
        }

        // Vertical walls: line c sits left of column c (c == columns is the
        // right border).
        for c in 0...columns {
            var runStart: Int? = nil
            for r in 0...rows {
                let wallHere = r < rows && !(c > 0 && isOpen(.east, column: c - 1, row: r))
                if wallHere {
                    if runStart == nil { runStart = r }
                } else if let start = runStart {
                    let x = bounds.x + Double(c) * w
                    out.append(Contour([Vector2(x, bounds.y + Double(start) * h),
                                        Vector2(x, bounds.y + Double(r) * h)], closed: false))
                    runStart = nil
                }
            }
        }

        return out
    }

    /// The unique path between two cells, as `(column, row)` steps including
    /// both endpoints (breadth-first search; a perfect maze has exactly one
    /// path). Out-of-bounds endpoints return an empty path.
    public func solution(fromColumn: Int, fromRow: Int,
                         toColumn: Int, toRow: Int) -> [(column: Int, row: Int)] {
        guard let cells = breadthFirstPath(from: fromRow * columns + fromColumn,
                                           to: toRow * columns + toColumn) else { return [] }
        return cells.map { (column: $0 % columns, row: $0 / columns) }
    }

    /// The longest corridor-to-corridor path in the maze (its diameter), as
    /// `(column, row)` steps: breadth-first search from any cell finds one far
    /// end, a second search from there finds the other. The natural
    /// entrance-and-exit pair for a maze meant to be solved.
    public func longestPath() -> [(column: Int, row: Int)] {
        let a = farthestCell(from: 0)
        let b = farthestCell(from: a)
        guard let cells = breadthFirstPath(from: a, to: b) else { return [] }
        return cells.map { (column: $0 % columns, row: $0 / columns) }
    }

    /// A `(column, row)` cell path (a `solution` or `longestPath` result) laid
    /// over `bounds` as an open polyline through the cell centers.
    public func contour(of path: [(column: Int, row: Int)], in bounds: Rectangle) -> Contour {
        Contour(path.map { center(ofColumn: $0.column, row: $0.row, in: bounds) }, closed: false)
    }

    // MARK: - Carving

    private mutating func carve(_ cell: Int, _ direction: Direction) {
        let (dc, dr) = direction.delta
        let neighbor = cell + dr * columns + dc
        links[cell] |= 1 << UInt8(direction.rawValue)
        links[neighbor] |= 1 << UInt8(direction.opposite.rawValue)
    }

    /// The in-bounds neighbor of `cell` toward `direction`, or nil.
    private func neighbor(of cell: Int, toward direction: Direction) -> Int? {
        let c = cell % columns + direction.delta.dc
        let r = cell / columns + direction.delta.dr
        guard c >= 0, c < columns, r >= 0, r < rows else { return nil }
        return r * columns + c
    }

    /// Randomized depth-first search: walk to a random unvisited neighbor,
    /// carving as you go; back up when boxed in. The explicit stack replaces
    /// recursion so a large maze can't overflow.
    private mutating func carveBacktracker<R: RandomNumberGenerator>(using rng: inout R) {
        var visited = [Bool](repeating: false, count: links.count)
        var stack = [Int.random(in: 0..<links.count, using: &rng)]
        visited[stack[0]] = true
        while let current = stack.last {
            var options: [Direction] = []
            for direction in Direction.allCases {
                if let n = neighbor(of: current, toward: direction), !visited[n] {
                    options.append(direction)
                }
            }
            if options.isEmpty {
                stack.removeLast()
            } else {
                let direction = options[Int.random(in: 0..<options.count, using: &rng)]
                carve(current, direction)
                let next = neighbor(of: current, toward: direction)!
                visited[next] = true
                stack.append(next)
            }
        }
    }

    /// Randomized Kruskal's: shuffle every interior wall, then knock each down
    /// only if its two cells aren't already connected (union-find over the
    /// cells keeps the carve loop-free).
    private mutating func carveKruskal<R: RandomNumberGenerator>(using rng: inout R) {
        var edges: [(cell: Int, direction: Direction)] = []
        edges.reserveCapacity(2 * links.count)
        for cell in 0..<links.count {
            if cell % columns < columns - 1 { edges.append((cell, .east)) }
            if cell / columns < rows - 1 { edges.append((cell, .south)) }
        }
        edges.shuffle(using: &rng)

        // Union-find with path halving and union by size.
        var parent = Array(0..<links.count)
        var size = [Int](repeating: 1, count: links.count)
        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x {
                parent[x] = parent[parent[x]]
                x = parent[x]
            }
            return x
        }

        for (cell, direction) in edges {
            let a = find(cell), b = find(neighbor(of: cell, toward: direction)!)
            guard a != b else { continue }
            if size[a] >= size[b] {
                parent[b] = a
                size[a] += size[b]
            } else {
                parent[a] = b
                size[b] += size[a]
            }
            carve(cell, direction)
        }
    }

    /// Wilson's algorithm: from each not-yet-carved cell, random-walk until the
    /// walk touches the maze, remembering only the *last* exit direction from
    /// every cell it crosses. Re-walking the remembered directions replays the
    /// walk with its loops erased (a loop overwrites its own trail), and that
    /// loop-erased path is what gets carved. Slower to start than the others,
    /// but the result is a uniform sample over every possible maze.
    private mutating func carveWilson<R: RandomNumberGenerator>(using rng: inout R) {
        var inMaze = [Bool](repeating: false, count: links.count)
        inMaze[Int.random(in: 0..<links.count, using: &rng)] = true

        var exitDirection = [Direction?](repeating: nil, count: links.count)
        for start in 0..<links.count where !inMaze[start] {
            // The random walk: record the latest exit direction per cell.
            var current = start
            while !inMaze[current] {
                var options: [Direction] = []
                for direction in Direction.allCases where neighbor(of: current, toward: direction) != nil {
                    options.append(direction)
                }
                let direction = options[Int.random(in: 0..<options.count, using: &rng)]
                exitDirection[current] = direction
                current = neighbor(of: current, toward: direction)!
            }
            // Replay from the start along the remembered directions: only the
            // loop-erased core of the walk is reachable, so only it carves.
            current = start
            while !inMaze[current] {
                let direction = exitDirection[current]!
                carve(current, direction)
                inMaze[current] = true
                current = neighbor(of: current, toward: direction)!
            }
        }
    }

    // MARK: - Paths

    /// Breadth-first parents from `from`; returns the cell path to `to`
    /// (inclusive), or nil when either end is out of bounds.
    private func breadthFirstPath(from: Int, to: Int) -> [Int]? {
        guard from >= 0, from < links.count, to >= 0, to < links.count else { return nil }
        var parent = [Int](repeating: -1, count: links.count)
        parent[from] = from
        var frontier = [from]
        while !frontier.isEmpty, parent[to] == -1 {
            var next: [Int] = []
            for cell in frontier {
                for direction in Direction.allCases {
                    guard isOpen(direction, column: cell % columns, row: cell / columns),
                          let n = neighbor(of: cell, toward: direction), parent[n] == -1 else { continue }
                    parent[n] = cell
                    next.append(n)
                }
            }
            frontier = next
        }
        guard parent[to] != -1 else { return nil }
        var path = [to]
        while path.last! != from { path.append(parent[path.last!]) }
        return path.reversed()
    }

    /// The cell farthest (by corridor distance) from `from`: one breadth-first
    /// flood, take the last layer's first discovery.
    private func farthestCell(from: Int) -> Int {
        var seen = [Bool](repeating: false, count: links.count)
        seen[from] = true
        var frontier = [from]
        var last = from
        while !frontier.isEmpty {
            last = frontier[0]
            var next: [Int] = []
            for cell in frontier {
                for direction in Direction.allCases {
                    guard isOpen(direction, column: cell % columns, row: cell / columns),
                          let n = neighbor(of: cell, toward: direction), !seen[n] else { continue }
                    seen[n] = true
                    next.append(n)
                }
            }
            frontier = next
        }
        return last
    }
}

// MARK: - Sketch sugar

public extension Sketch {
    /// Carve a `columns × rows` perfect maze, drawn from the seeded `random` so
    /// `seed(_:)` makes it reproducible. Read its geometry with
    /// `walls(in:)` (the stroke-ready line-work), `solution(...)` /
    /// `longestPath()` (cell paths), and `contour(of:in:)` (a path as a
    /// polyline). `algorithm` picks the texture: winding corridors
    /// (`.backtracker`), even short dead ends (`.kruskal`), or the unbiased
    /// uniform sample (`.wilson`).
    ///
    /// ```swift
    /// seed(9)
    /// let m = maze(columns: 24, rows: 24)
    /// stroke(.white); strokeWeight(4); strokeCap(.round)
    /// drawMaze(m)
    /// ```
    func maze(columns: Int, rows: Int, algorithm: Maze.Algorithm = .backtracker) -> Maze {
        Maze(columns: columns, rows: rows, algorithm: algorithm, using: &rng)
    }

    /// Stroke `maze`'s walls over `bounds` (the whole canvas by default) with the
    /// current `stroke`. For per-wall color or the solution overlay, read
    /// `maze.walls(in:)` / `maze.contour(of:in:)` and stroke them yourself.
    func drawMaze(_ maze: Maze, in bounds: Rectangle? = nil) {
        for wall in maze.walls(in: bounds ?? self.bounds) {
            drawPolyline(wall.points, closed: false)
        }
    }
}
