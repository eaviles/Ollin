import Foundation

/// Site percolation: fill a `columns × rows` grid with open cells at a given
/// `probability`, then read the **clusters** (groups of open cells joined
/// edge-to-edge) as geometry. Percolation is the classic model of a phase
/// transition: below the critical probability (about 0.5927 on this square
/// lattice) the clusters stay small islands, and just past it one giant
/// cluster suddenly spans the whole grid. Sweeping `probability` through that
/// threshold is the show.
///
/// Clusters come back largest first, each a list of `(column, row)` cells.
/// `spanningClusterIndex` names the cluster that touches both the top and
/// bottom rows, if one exists. `cellRects(of:in:)` places a cluster's cells
/// into a canvas rectangle for filling, and `outlines(of:in:)` traces its
/// boundary as closed `Contour` loops (outer edges and holes), so a cluster
/// strokes, hatches, and exports to SVG for a pen plotter like any other
/// line-work.
///
/// The roll draws from `rng`, so the same seed always fills the same grid. The
/// open-cell init takes any boolean grid instead (an image threshold, a noise
/// field), so the cluster reading works on patterns you made some other way.
///
/// ```swift
/// var rng = SplitMix64(seed: 9)
/// let p = Percolation(columns: 48, rows: 48, probability: 0.6, using: &rng)
/// for rect in p.cellRects(of: 0, in: bounds) { drawRect(rect) }   // largest cluster
/// for loop in p.outlines(of: 0, in: bounds) { drawPolygon(loop.points) }
/// ```
public struct Percolation: Equatable, Hashable, Sendable {
    /// The critical probability of the square-lattice site model: the point
    /// the spanning cluster appears at (Newman and Ziff's measured value).
    public static let criticalProbability = 0.592746

    public let columns: Int
    public let rows: Int
    /// Row-major open flags, `columns * rows` of them.
    public let openCells: [Bool]

    /// Each open cell's cluster index (largest cluster first), -1 for closed
    /// cells. Row-major, `columns * rows` entries.
    public private(set) var labels: [Int]

    /// The clusters as flat row-major cell indices, largest first (ties broken
    /// by which cluster appears first in reading order).
    private var clusterIndices: [[Int]]

    /// Fill the grid at `probability`, rolling row by row from `rng`.
    public init<R: RandomNumberGenerator>(columns: Int, rows: Int,
                                          probability: Double,
                                          using rng: inout R) {
        let cols = max(1, columns), rws = max(1, rows)
        let p = min(max(probability, 0), 1)
        var open = [Bool](repeating: false, count: cols * rws)
        for i in 0 ..< open.count {
            open[i] = Double.random(in: 0 ..< 1, using: &rng) < p
        }
        self.init(columns: cols, rows: rws, openCells: open)
    }

    /// Read clusters off a grid you filled yourself: `openCells` is row-major,
    /// `columns * rows` flags (extra entries are ignored, missing ones read
    /// closed). This is the seam for thresholded images and noise fields.
    public init(columns: Int, rows: Int, openCells: [Bool]) {
        let cols = max(1, columns), rws = max(1, rows)
        self.columns = cols
        self.rows = rws
        var open = openCells
        if open.count < cols * rws {
            open.append(contentsOf: [Bool](repeating: false,
                                           count: cols * rws - open.count))
        } else if open.count > cols * rws {
            open.removeLast(open.count - cols * rws)
        }
        self.openCells = open

        // Union-find over the open cells: each cell unions with its open west
        // and north neighbors, one reading-order pass.
        var parent = [Int](repeating: -1, count: cols * rws)
        func find(_ i: Int) -> Int {
            var root = i
            while parent[root] != root { root = parent[root] }
            var walk = i
            while parent[walk] != root {
                let next = parent[walk]
                parent[walk] = root
                walk = next
            }
            return root
        }
        for i in 0 ..< open.count where open[i] {
            parent[i] = i
            let c = i % cols
            if c > 0, open[i - 1] { parent[find(i)] = find(i - 1) }
            if i >= cols, open[i - cols] {
                let a = find(i), b = find(i - cols)
                if a != b { parent[a] = b }
            }
        }

        // Collect clusters in reading order, then order them largest first.
        var clusterOf: [Int: Int] = [:]
        var found: [[Int]] = []
        for i in 0 ..< open.count where open[i] {
            let root = find(i)
            if let k = clusterOf[root] {
                found[k].append(i)
            } else {
                clusterOf[root] = found.count
                found.append([i])
            }
        }
        let order = found.indices.sorted {
            found[$0].count != found[$1].count
                ? found[$0].count > found[$1].count
                : found[$0][0] < found[$1][0]
        }
        clusterIndices = order.map { found[$0] }

        var labels = [Int](repeating: -1, count: cols * rws)
        for (k, cells) in clusterIndices.enumerated() {
            for i in cells { labels[i] = k }
        }
        self.labels = labels
    }

    /// How many clusters the grid holds.
    public var clusterCount: Int { clusterIndices.count }

    /// Whether the cell at `column`, `row` is open (out of range reads closed).
    public func isOpen(atColumn column: Int, row: Int) -> Bool {
        guard column >= 0, column < columns, row >= 0, row < rows else { return false }
        return openCells[row * columns + column]
    }

    /// The cluster a cell belongs to, or nil for closed and out-of-range cells.
    public func clusterIndex(atColumn column: Int, row: Int) -> Int? {
        guard column >= 0, column < columns, row >= 0, row < rows else { return nil }
        let label = labels[row * columns + column]
        return label >= 0 ? label : nil
    }

    /// One cluster's cells as `(column, row)` pairs, in reading order.
    public func cluster(_ index: Int) -> [(column: Int, row: Int)] {
        guard index >= 0, index < clusterIndices.count else { return [] }
        return clusterIndices[index].map { (column: $0 % columns, row: $0 / columns) }
    }

    /// Every cluster's size, largest first.
    public var clusterSizes: [Int] { clusterIndices.map(\.count) }

    /// The index of the cluster that touches both the top and bottom rows, if
    /// any (the largest one when several span).
    public var spanningClusterIndex: Int? {
        for (k, cells) in clusterIndices.enumerated() {
            var touchesTop = false, touchesBottom = false
            for i in cells {
                let row = i / columns
                if row == 0 { touchesTop = true }
                if row == rows - 1 { touchesBottom = true }
                if touchesTop && touchesBottom { return k }
            }
        }
        return nil
    }

    /// Whether any cluster spans top to bottom.
    public var spans: Bool { spanningClusterIndex != nil }

    /// One cluster's cells placed into `rect`, one small rectangle per cell,
    /// ready to fill.
    public func cellRects(of index: Int, in rect: Rectangle) -> [Rectangle] {
        guard index >= 0, index < clusterIndices.count else { return [] }
        let w = rect.width / Double(columns), h = rect.height / Double(rows)
        return clusterIndices[index].map { i in
            Rectangle(x: rect.x + Double(i % columns) * w,
                      y: rect.y + Double(i / columns) * h,
                      width: w, height: h)
        }
    }

    /// One cluster's boundary traced over `rect` as closed loops: the outer
    /// outline plus one loop per enclosed hole, corners exact and collinear
    /// runs merged. Interior sits on the walker's right, and where two lobes
    /// pinch at a corner the trace takes the tighter turn, so loops never
    /// cross themselves.
    public func outlines(of index: Int, in rect: Rectangle) -> [Contour] {
        guard index >= 0, index < clusterIndices.count else { return [] }
        let cells = clusterIndices[index]
        let vstride = columns + 1

        // Directed boundary edges over the (columns+1) x (rows+1) corner grid
        // (row-major vertex indices). Each open side whose neighbor is outside
        // the cluster emits one edge, wound so the cluster stays on the right
        // of the walk.
        var edges: [(from: Int, to: Int)] = []
        var member = [Bool](repeating: false, count: columns * rows)
        for i in cells { member[i] = true }
        func inCluster(_ column: Int, _ row: Int) -> Bool {
            guard column >= 0, column < columns, row >= 0, row < rows else { return false }
            return member[row * columns + column]
        }
        for i in cells {
            let c = i % columns, r = i / columns
            let tl = r * vstride + c, tr = tl + 1
            let bl = tl + vstride, br = bl + 1
            if !inCluster(c, r - 1) { edges.append((tl, tr)) }   // top, walking east
            if !inCluster(c + 1, r) { edges.append((tr, br)) }   // right, walking south
            if !inCluster(c, r + 1) { edges.append((br, bl)) }   // bottom, walking west
            if !inCluster(c - 1, r) { edges.append((bl, tl)) }   // left, walking north
        }
        var edgesAt: [Int: [Int]] = [:]   // start vertex -> edge slots (lookup only)
        for (i, e) in edges.enumerated() { edgesAt[e.from, default: []].append(i) }

        // Chain the edges into loops. At a pinch vertex (two outgoing edges)
        // take the sharpest right turn relative to the incoming direction, so
        // each lobe closes as its own tight loop and no loop crosses itself.
        var used = [Bool](repeating: false, count: edges.count)
        var loops: [[Int]] = []
        for start in edges.indices where !used[start] {
            used[start] = true
            var loop: [Int] = [edges[start].from]
            var from = edges[start].from
            var to = edges[start].to
            while to != loop[0] {
                loop.append(to)
                var picked: Int? = nil
                var bestTurn = Int.min
                for slot in edgesAt[to] ?? [] where !used[slot] {
                    let turn = turnPriority(from: from, via: to,
                                            to: edges[slot].to, vstride: vstride)
                    if turn > bestTurn { bestTurn = turn; picked = slot }
                }
                guard let slot = picked else { break }
                used[slot] = true
                from = to
                to = edges[slot].to
            }
            loops.append(loop)
        }

        // Merge collinear runs and map grid vertices into the rectangle.
        let w = rect.width / Double(columns), h = rect.height / Double(rows)
        return loops.map { loop in
            var pruned: [Int] = []
            for (j, v) in loop.enumerated() {
                let prev = loop[(j + loop.count - 1) % loop.count]
                let next = loop[(j + 1) % loop.count]
                let dc1 = v % vstride - prev % vstride, dr1 = v / vstride - prev / vstride
                let dc2 = next % vstride - v % vstride, dr2 = next / vstride - v / vstride
                if dc1 != dc2 || dr1 != dr2 { pruned.append(v) }
            }
            return Contour(pruned.map { v in
                Vector2(rect.x + Double(v % vstride) * w,
                        rect.y + Double(v / vstride) * h)
            }, closed: true)
        }
    }

    /// The right-turn preference at a vertex: higher is tighter. Directions
    /// are on the corner grid, y down, so a positive cross product is a right
    /// turn on screen.
    private func turnPriority(from: Int, via: Int, to: Int, vstride: Int) -> Int {
        let d1c = via % vstride - from % vstride, d1r = via / vstride - from / vstride
        let d2c = to % vstride - via % vstride, d2r = to / vstride - via / vstride
        let cross = d1c * d2r - d1r * d2c
        if cross > 0 { return 2 }        // right turn on screen (y down)
        if cross == 0 { return 1 }       // straight on
        return 0                          // left turn
    }
}

public extension Sketch {
    /// Fill a `columns × rows` site-percolation grid at `probability`, rolled
    /// from the seeded `random` so `seed(_:)` makes it reproducible. Read the
    /// clusters largest-first with `cluster(_:)` / `cellRects(of:in:)` /
    /// `outlines(of:in:)`, and watch for `spans`: the giant cluster appears as
    /// `probability` crosses `Percolation.criticalProbability`.
    ///
    /// ```swift
    /// seed(9)
    /// let p = percolation(columns: 48, rows: 48, probability: 0.6)
    /// for rect in p.cellRects(of: 0, in: bounds) { drawRect(rect) }
    /// ```
    func percolation(columns: Int, rows: Int, probability: Double) -> Percolation {
        Percolation(columns: columns, rows: rows, probability: probability, using: &rng)
    }
}
