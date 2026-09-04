import Foundation

/// A parquet deformation: a tiling of the plane whose tile changes shape as you
/// read across it. Every tile still meets its neighbors exactly, with no gaps,
/// no overlaps and nothing to line up by hand, and yet a square at one edge
/// has become an interlocking cross at the other, through a run of shapes that
/// are each only a little unlike the one beside them.
///
/// The whole design rests on one decision: the geometry lives on the *edges of
/// the lattice*, not on the tiles. A tile is not drawn and then fitted to its
/// neighbors; it is read off the four edges around it, and the tile on the far
/// side of any edge reads that same curve backwards. So the tiling holds
/// however far the shape drifts, and the drift is free to be anything.
///
/// An edge's shape is a `Profile`, a curve given in the edge's own frame: it
/// runs from one lattice corner to the other, and its sideways offsets are
/// fractions of the edge's length. Each edge blends `start` into `end` by an
/// `amount` read at its midpoint, so the sheet carries a whole family of shapes
/// between the two you named, and the blend is exact at both ends, so a
/// profile with square corners keeps them.
///
/// Two faces come out of one deformation:
///
/// - `tiles` is the interlocking pieces, each a closed `Contour` to fill, with
///   the `amount` it was built at for coloring the drift.
/// - `edges` is the line-work, every lattice edge exactly once, so stroking it
///   draws the design with no doubled lines and a pen plotter draws each edge
///   only once.
///
/// ```swift
/// let sheet = parquetDeformation(columns: 14, rows: 14,
///                                from: .straight, to: .tooth(depth: 0.3))
/// stroke(.black); strokeWeight(2)
/// for edge in sheet.edges { drawPolyline(edge.points, closed: false) }
/// ```
///
/// The lattice is a rectangle's worth of tiles, and the tiles on its rim carry
/// their deformed outer edges, so the sheet's own boundary is fringed rather
/// than straight. For a clean border, intersect the tiles with the bounds
/// through the shape booleans.
public struct ParquetDeformation: Sendable {
    /// One tile of the sheet: the piece bounded by the four lattice edges
    /// around cell (`column`, `row`).
    public struct Tile: Equatable, Sendable {
        /// The tile's column in the lattice, 0 at the left.
        public let column: Int
        /// The tile's row in the lattice, 0 at the top.
        public let row: Int
        /// The deformation amount at the tile's center, `0`…`1`: how far along
        /// the run from `start` to `end` this tile sits. Handy for coloring.
        public let amount: Double
        /// The center of the tile's lattice cell (not of its deformed outline).
        public let center: Vector2
        /// The tile's closed outline, walked clockwise from its top-left
        /// lattice corner.
        public let contour: Contour

        /// The tile as a fillable `Shape`.
        public var shape: Shape { Shape(contours: [contour]) }
    }

    /// The shape of one lattice edge, given in the edge's own frame: `x` runs
    /// from `0` at one lattice corner to `1` at the other, and `y` is the
    /// sideways offset as a fraction of the edge's length. Every profile starts
    /// at `(0, 0)` and ends at `(1, 0)`, which is what holds the lattice's
    /// corners in place.
    ///
    /// A profile is a polyline and may double back on itself: a tooth's
    /// vertical sides are as legal as a wave's slopes.
    public enum Profile: Equatable, Sendable {
        /// A plain segment: the undeformed lattice.
        case straight
        /// A square tooth of `depth` standing on the middle `width` of the
        /// edge: the classic interlocking key. A negative depth cuts a notch.
        case tooth(depth: Double, width: Double)
        /// `count` alternating peaks of `depth`, the first to the positive side.
        case zigzag(count: Int, depth: Double)
        /// `count` full sine waves of amplitude `depth`.
        case wave(count: Int, depth: Double)
        /// A circular arc bulging `depth` to one side at its middle.
        case bump(depth: Double)
        /// A profile written out by hand. The first and last points are pinned
        /// to `(0, 0)` and `(1, 0)` however they were given, so only the shape
        /// between them counts.
        case custom([Vector2])

        /// A square tooth of `depth` standing on the middle half of the edge.
        public static func tooth(depth: Double) -> Profile {
            .tooth(depth: depth, width: 0.5)
        }

        /// Two alternating peaks of `depth`.
        public static func zigzag(depth: Double) -> Profile {
            .zigzag(count: 2, depth: depth)
        }

        /// One full sine wave of amplitude `depth`.
        public static func wave(depth: Double) -> Profile {
            .wave(count: 1, depth: depth)
        }

        /// How finely the curved profiles are flattened into polylines.
        private static let curveSegments = 24

        /// The profile as a polyline in the edge's frame.
        public var points: [Vector2] {
            switch self {
            case .straight:
                return [Vector2(0, 0), Vector2(1, 0)]

            case let .tooth(depth, width):
                let w = min(max(width, 0), 1)
                let a = 0.5 - w / 2, b = 0.5 + w / 2
                return [Vector2(0, 0), Vector2(a, 0), Vector2(a, depth),
                        Vector2(b, depth), Vector2(b, 0), Vector2(1, 0)]

            case let .zigzag(count, depth):
                guard count > 0 else { return Profile.straight.points }
                var out = [Vector2(0, 0)]
                for i in 0..<count {
                    let u = (Double(i) + 0.5) / Double(count)
                    out.append(Vector2(u, i.isMultiple(of: 2) ? depth : -depth))
                }
                out.append(Vector2(1, 0))
                return out

            case let .wave(count, depth):
                guard count > 0 else { return Profile.straight.points }
                let steps = Profile.curveSegments * count
                var out = (0...steps).map { i -> Vector2 in
                    let u = Double(i) / Double(steps)
                    return Vector2(u, depth * sin(2 * Double.pi * Double(count) * u))
                }
                out[0] = Vector2(0, 0)
                out[steps] = Vector2(1, 0)
                return out

            case let .bump(depth):
                guard abs(depth) > 1e-12 else { return Profile.straight.points }
                // The circle through (0, 0) and (1, 0) whose sagitta at the
                // midpoint is `depth`; the arc is swept from one end to the
                // other and its ends pinned, so rounding never opens the edge.
                let radius = (0.25 + depth * depth) / (2 * abs(depth))
                let centerY = depth - (depth < 0 ? -radius : radius)
                let half = asin(min(1, 0.5 / radius))
                let steps = Profile.curveSegments
                var out = (0...steps).map { i -> Vector2 in
                    let t = -half + 2 * half * Double(i) / Double(steps)
                    let side = radius * cos(t)
                    return Vector2(0.5 + radius * sin(t),
                                   centerY + (depth < 0 ? -side : side))
                }
                out[0] = Vector2(0, 0)
                out[steps] = Vector2(1, 0)
                return out

            case let .custom(given):
                guard given.count >= 2 else { return Profile.straight.points }
                var out = given
                out[0] = Vector2(0, 0)
                out[out.count - 1] = Vector2(1, 0)
                return out
            }
        }
    }

    /// Which way the deformation runs across the sheet.
    public enum Sweep: Sendable, Equatable, CaseIterable {
        /// `start` at the left edge, `end` at the right.
        case horizontal
        /// `start` at the top, `end` at the bottom.
        case vertical
        /// `start` at the top-left corner, `end` at the bottom-right.
        case diagonal
        /// `start` at the center, `end` at the corners.
        case radial
    }

    /// The lattice the tiles sit on. Its `gutter` does not apply: parquet tiles
    /// meet along shared edges, so there is nothing to open a gap between.
    public let grid: Grid
    /// The profile every edge blends from, at amount `0`.
    public let start: Profile
    /// The profile every edge blends to, at amount `1`.
    public let end: Profile

    /// The horizontal lattice edges, each left to right, row-major over
    /// `rows + 1` lines of `columns` edges.
    private let acrossEdges: [[Vector2]]
    /// The vertical lattice edges, each top to bottom, row-major over `rows`
    /// lines of `columns + 1` edges.
    private let downEdges: [[Vector2]]
    /// The amount read at each tile's center, row-major.
    private let tileAmounts: [Double]

    // MARK: - Building

    /// A deformation whose amount at any point is worked out by `amount`, which
    /// is handed a point in canvas coordinates and answers `0`…`1` (anything
    /// outside is clamped). This is the general form: drive the drift from
    /// noise, from an image's tone, from a distance, from whatever you like.
    ///
    /// ```swift
    /// let sheet = ParquetDeformation(grid: Grid(in: bounds, columns: 20, rows: 20),
    ///                                from: .straight,
    ///                                to: .zigzag(count: 3, depth: 0.2)) { p in
    ///     noise(p.x * 0.003, p.y * 0.003)
    /// }
    /// ```
    public init(grid: Grid, from start: Profile, to end: Profile,
                amount: (Vector2) -> Double) {
        self.grid = grid
        self.start = start
        self.end = end

        let columns = grid.columns, rows = grid.rows
        guard columns > 0, rows > 0 else {
            self.acrossEdges = []
            self.downEdges = []
            self.tileAmounts = []
            return
        }

        let bounds = grid.bounds
        func corner(_ column: Int, _ row: Int) -> Vector2 {
            ParquetDeformation.latticeCorner(column: column, row: row,
                                             columns: columns, rows: rows, bounds: bounds)
        }
        let startPoints = start.points, endPoints = end.points
        func edge(_ a: Vector2, _ b: Vector2) -> [Vector2] {
            let t = min(max(amount((a + b) / 2), 0), 1)
            return ParquetDeformation.placed(
                ParquetDeformation.blended(startPoints, endPoints, t), from: a, to: b)
        }

        var across: [[Vector2]] = []
        across.reserveCapacity((rows + 1) * columns)
        for row in 0...rows {
            for column in 0..<columns {
                across.append(edge(corner(column, row), corner(column + 1, row)))
            }
        }
        var down: [[Vector2]] = []
        down.reserveCapacity(rows * (columns + 1))
        for row in 0..<rows {
            for column in 0...columns {
                down.append(edge(corner(column, row), corner(column, row + 1)))
            }
        }
        var amounts: [Double] = []
        amounts.reserveCapacity(rows * columns)
        for row in 0..<rows {
            for column in 0..<columns {
                let center = (corner(column, row) + corner(column + 1, row + 1)) / 2
                amounts.append(min(max(amount(center), 0), 1))
            }
        }
        self.acrossEdges = across
        self.downEdges = down
        self.tileAmounts = amounts
    }

    /// A deformation that runs `start` into `end` across the sheet in one of
    /// the four named directions.
    public init(grid: Grid, from start: Profile, to end: Profile,
                sweep: Sweep = .horizontal) {
        let bounds = grid.bounds
        let diagonalHalf = (2.0 as Double).squareRoot()
        self.init(grid: grid, from: start, to: end) { point in
            let u = bounds.width > 0 ? (point.x - bounds.x) / bounds.width : 0
            let v = bounds.height > 0 ? (point.y - bounds.y) / bounds.height : 0
            switch sweep {
            case .horizontal: return u
            case .vertical: return v
            case .diagonal: return (u + v) / 2
            case .radial:
                let dx = (u - 0.5) * 2, dy = (v - 0.5) * 2
                return (dx * dx + dy * dy).squareRoot() / diagonalHalf
            }
        }
    }

    // MARK: - The two faces

    /// The interlocking pieces, row-major so they zip with `grid.cells`. Each
    /// tile's outline is walked clockwise from its top-left lattice corner, and
    /// every edge it shares with a neighbor is the same curve on both sides.
    public var tiles: [Tile] {
        let columns = grid.columns, rows = grid.rows
        guard columns > 0, rows > 0 else { return [] }
        let bounds = grid.bounds
        var out: [Tile] = []
        out.reserveCapacity(columns * rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let top = acrossEdges[row * columns + column]
                let right = downEdges[row * (columns + 1) + column + 1]
                let bottom = acrossEdges[(row + 1) * columns + column].reversed()
                let left = downEdges[row * (columns + 1) + column].reversed()
                // Each side drops its last point, which is the next side's first.
                var ring: [Vector2] = []
                ring.reserveCapacity(top.count + right.count + bottom.count + left.count)
                ring.append(contentsOf: top.dropLast())
                ring.append(contentsOf: right.dropLast())
                ring.append(contentsOf: bottom.dropLast())
                ring.append(contentsOf: left.dropLast())

                let topLeft = Self.latticeCorner(column: column, row: row,
                                                 columns: columns, rows: rows, bounds: bounds)
                let bottomRight = Self.latticeCorner(column: column + 1, row: row + 1,
                                                     columns: columns, rows: rows, bounds: bounds)
                out.append(Tile(column: column, row: row,
                                amount: tileAmounts[row * columns + column],
                                center: (topLeft + bottomRight) / 2,
                                contour: Contour(ring, closed: true)))
            }
        }
        return out
    }

    /// The line-work: every lattice edge exactly once, as an open `Contour`.
    /// The horizontal edges come first (top line to bottom, left to right
    /// within a line), then the vertical ones (top row to bottom, left to right
    /// within a row).
    public var edges: [Contour] {
        (acrossEdges + downEdges).map { Contour($0, closed: false) }
    }

    // MARK: - The lattice

    /// The position of lattice corner (`column`, `row`), where column `columns`
    /// and row `rows` are the far edges of `bounds`.
    private static func latticeCorner(column: Int, row: Int, columns: Int, rows: Int,
                                      bounds: Rectangle) -> Vector2 {
        Vector2(bounds.x + bounds.width * Double(column) / Double(columns),
                bounds.y + bounds.height * Double(row) / Double(rows))
    }

    // MARK: - Profile blending

    /// A profile placed on the segment `a`→`b`: `x` runs along it, `y` to its
    /// left-hand perpendicular. Every edge is generated once, in one canonical
    /// direction, and both tiles beside it read that one result, so the two can
    /// never disagree.
    private static func placed(_ profile: [Vector2], from a: Vector2, to b: Vector2) -> [Vector2] {
        let along = b - a
        let sideways = along.perpendicular
        return profile.map { a + along * $0.x + sideways * $0.y }
    }

    /// The blend of two profiles at `amount`.
    ///
    /// Both are reparameterized by normalized arc length, and the result's
    /// vertices sit at the *union* of the two vertex parameters. Between two
    /// consecutive parameters both inputs are straight, so their blend is
    /// straight too: the polyline is the exact interpolation rather than a
    /// sampling of it, and at `0` or `1` it reproduces that profile's corners
    /// with nothing rounded off.
    private static func blended(_ from: [Vector2], _ to: [Vector2], _ amount: Double) -> [Vector2] {
        if amount <= 0 { return from }
        if amount >= 1 { return to }
        let fromStops = arcLengthStops(from), toStops = arcLengthStops(to)
        var stops = fromStops
        stops.append(contentsOf: toStops)
        stops.sort()

        var blend: [Vector2] = []
        blend.reserveCapacity(stops.count)
        var previous = -1.0
        for stop in stops where stop - previous > 1e-12 {
            previous = stop
            let a = point(on: from, stops: fromStops, at: stop)
            let b = point(on: to, stops: toStops, at: stop)
            blend.append(a.lerp(to: b, amount))
        }
        guard blend.count >= 2 else { return Profile.straight.points }
        blend[0] = Vector2(0, 0)
        blend[blend.count - 1] = Vector2(1, 0)
        return withoutCollinear(blend)
    }

    /// The normalized cumulative arc length of every vertex of a polyline,
    /// `0`…`1`.
    private static func arcLengthStops(_ points: [Vector2]) -> [Double] {
        var lengths = [0.0]
        lengths.reserveCapacity(points.count)
        var total = 0.0
        for i in 1..<points.count {
            total += points[i].distance(to: points[i - 1])
            lengths.append(total)
        }
        guard total > 0 else { return [Double](repeating: 0, count: points.count) }
        return lengths.map { $0 / total }
    }

    /// The point at normalized arc length `t` along a polyline whose vertices
    /// sit at `stops`.
    private static func point(on points: [Vector2], stops: [Double], at t: Double) -> Vector2 {
        if t <= 0 { return points[0] }
        if t >= 1 { return points[points.count - 1] }
        var low = 0, high = stops.count - 1
        while low + 1 < high {
            let mid = (low + high) / 2
            if stops[mid] <= t { low = mid } else { high = mid }
        }
        let span = stops[low + 1] - stops[low]
        let f = span > 0 ? (t - stops[low]) / span : 0
        return points[low].lerp(to: points[low + 1], f)
    }

    /// A polyline with its straight-through vertices dropped, so a blend that
    /// happens to come out straight is two points rather than a dozen. The two
    /// ends are always kept.
    private static func withoutCollinear(_ points: [Vector2]) -> [Vector2] {
        guard points.count > 2 else { return points }
        var out = [points[0]]
        for i in 1..<(points.count - 1) {
            let a = out[out.count - 1], b = points[i], c = points[i + 1]
            if abs((b - a).cross(c - a)) > 1e-12 { out.append(b) }
        }
        out.append(points[points.count - 1])
        return out
    }
}

// MARK: - Sketch sugar

public extension Sketch {
    /// A parquet deformation over a `columns × rows` lattice of `bounds` (the
    /// whole canvas by default): a tiling whose tile runs from the `from`
    /// profile to the `to` profile across the sheet, every tile still meeting
    /// its neighbors exactly.
    ///
    /// Read `.tiles` for the interlocking pieces and `.edges` for the
    /// line-work; for the plain case, `drawParquetDeformation` strokes the
    /// edges for you.
    ///
    /// ```swift
    /// let sheet = parquetDeformation(columns: 14, rows: 14,
    ///                                from: .straight, to: .tooth(depth: 0.3))
    /// for tile in sheet.tiles {
    ///     fill(Color(hue: tile.amount, saturation: 0.5, brightness: 0.9))
    ///     drawShape(tile.shape)
    /// }
    /// ```
    func parquetDeformation(in bounds: Rectangle? = nil, columns: Int, rows: Int,
                            from start: ParquetDeformation.Profile,
                            to end: ParquetDeformation.Profile,
                            sweep: ParquetDeformation.Sweep = .horizontal) -> ParquetDeformation {
        ParquetDeformation(grid: Grid(in: bounds ?? self.bounds, columns: columns, rows: rows),
                           from: start, to: end, sweep: sweep)
    }

    /// Draw the line-work of a parquet deformation with the current `stroke`.
    /// For filled tiles or per-tile color, hold the `parquetDeformation(…)`
    /// value and draw its faces yourself.
    func drawParquetDeformation(in bounds: Rectangle? = nil, columns: Int, rows: Int,
                                from start: ParquetDeformation.Profile,
                                to end: ParquetDeformation.Profile,
                                sweep: ParquetDeformation.Sweep = .horizontal) {
        for edge in parquetDeformation(in: bounds, columns: columns, rows: rows,
                                       from: start, to: end, sweep: sweep).edges {
            drawPolyline(edge.points, closed: false)
        }
    }
}
