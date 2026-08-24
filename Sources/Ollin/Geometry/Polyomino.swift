import Foundation

/// A polyomino: a set of squares joined edge to edge, held as whole-number cells.
///
/// The cells are normalized when the piece is made, so the lowest column and row
/// are both zero and the list is sorted. Two pieces that sit in the same place are
/// then equal, which is what lets the orientations of a piece be counted without
/// counting the same one twice.
///
/// ```swift
/// let ell = Polyomino(["X.", "X.", "XX"])
/// ell.orientations().count      // 8: four turns, and the mirror of each
/// ```
public struct Polyomino: Hashable, Sendable {
    /// One square of a polyomino, on a whole-number lattice.
    public struct Cell: Hashable, Sendable, Comparable {
        public var column: Int
        public var row: Int

        public init(_ column: Int, _ row: Int) {
            self.column = column
            self.row = row
        }

        /// Reading order: down the rows first, then across.
        public static func < (a: Cell, b: Cell) -> Bool {
            a.row != b.row ? a.row < b.row : a.column < b.column
        }
    }

    /// The squares, normalized to start at zero and sorted in reading order.
    public let cells: [Cell]

    /// Build a piece from its squares. Repeats are dropped.
    public init(cells: [Cell]) {
        guard !cells.isEmpty else {
            self.cells = []
            return
        }
        let minColumn = cells.map(\.column).min() ?? 0
        let minRow = cells.map(\.row).min() ?? 0
        self.cells = Array(Set(cells.map { Cell($0.column - minColumn, $0.row - minRow) })).sorted()
    }

    /// Build a piece by drawing it, one string per row.
    ///
    /// ```swift
    /// Polyomino([".X.",
    ///            "XXX"])   // the T
    /// ```
    ///
    /// Any character other than a space or a dot counts as filled.
    public init(_ rows: [String]) {
        var found: [Cell] = []
        for (row, line) in rows.enumerated() {
            for (column, character) in line.enumerated() where character != "." && character != " " {
                found.append(Cell(column, row))
            }
        }
        self.init(cells: found)
    }

    /// How many squares the piece is made of.
    public var count: Int { cells.count }
    /// How many columns the piece spans.
    public var columns: Int { (cells.map(\.column).max() ?? -1) + 1 }
    /// How many rows the piece spans.
    public var rows: Int { (cells.map(\.row).max() ?? -1) + 1 }
    /// Whether the piece has no squares at all.
    public var isEmpty: Bool { cells.isEmpty }

    /// The piece turned a quarter turn clockwise.
    public func rotated() -> Polyomino {
        Polyomino(cells: cells.map { Cell(-$0.row, $0.column) })
    }

    /// The piece flipped left to right.
    public func mirrored() -> Polyomino {
        Polyomino(cells: cells.map { Cell(-$0.column, $0.row) })
    }

    /// Every distinct way the piece can sit: four turns, and the mirror of each
    /// unless `reflections` is off. A piece with symmetry gives back fewer, which
    /// is why they are counted rather than assumed: the plus has one, the straight
    /// line has two, and the L has all eight.
    public func orientations(reflections: Bool = true) -> [Polyomino] {
        var seen: [Polyomino] = []
        var turning = self
        for _ in 0 ..< 4 {
            if !seen.contains(turning) { seen.append(turning) }
            if reflections {
                let flipped = turning.mirrored()
                if !seen.contains(flipped) { seen.append(flipped) }
            }
            turning = turning.rotated()
        }
        return seen
    }

    /// A solid block of cells, the region most tilings are asked for.
    public static func rectangle(columns: Int, rows: Int) -> Polyomino {
        guard columns > 0, rows > 0 else { return Polyomino(cells: []) }
        var cells: [Cell] = []
        cells.reserveCapacity(columns * rows)
        for row in 0 ..< rows {
            for column in 0 ..< columns { cells.append(Cell(column, row)) }
        }
        return Polyomino(cells: cells)
    }

    /// The piece as an outline, in canvas units: one closed contour per boundary
    /// loop, so a piece with a hole in it hands back the hole too.
    ///
    /// The outline is the edges that only one cell owns, chained end to end. It is
    /// what to stroke when a piece should read as one shape rather than as a run of
    /// squares.
    public func outlines(cellSize: Double, origin: Vector2 = .zero) -> [Contour] {
        guard !cells.isEmpty else { return [] }
        let filled = Set(cells)
        // An edge of a cell is on the boundary when the cell across it is missing.
        // Each is kept as a step from one lattice corner to the next, wound so the
        // filled side is on the same hand all the way round.
        var steps: [Cell: [Cell]] = [:]
        for cell in cells {
            let (c, r) = (cell.column, cell.row)
            if !filled.contains(Cell(c, r - 1)) { steps[Cell(c, r), default: []].append(Cell(c + 1, r)) }
            if !filled.contains(Cell(c + 1, r)) { steps[Cell(c + 1, r), default: []].append(Cell(c + 1, r + 1)) }
            if !filled.contains(Cell(c, r + 1)) { steps[Cell(c + 1, r + 1), default: []].append(Cell(c, r + 1)) }
            if !filled.contains(Cell(c - 1, r)) { steps[Cell(c, r + 1), default: []].append(Cell(c, r)) }
        }

        var loops: [Contour] = []
        // Sorted starts, so the same piece always hands back the same contours.
        var starts = steps.keys.sorted()
        while let start = starts.first(where: { !(steps[$0]?.isEmpty ?? true) }) {
            var corners: [Cell] = [start]
            var at = start
            while let next = steps[at]?.popLast() {
                if steps[at]?.isEmpty == true { steps[at] = nil }
                if next == start { break }
                corners.append(next)
                at = next
            }
            starts = steps.keys.sorted()
            guard corners.count >= 4 else { continue }
            // Drop the corners that only continue a straight run.
            var kept: [Cell] = []
            for i in corners.indices {
                let before = corners[(i + corners.count - 1) % corners.count]
                let after = corners[(i + 1) % corners.count]
                let turns = (corners[i].column - before.column) * (after.row - corners[i].row)
                    != (corners[i].row - before.row) * (after.column - corners[i].column)
                if turns { kept.append(corners[i]) }
            }
            loops.append(Contour(kept.map {
                Vector2(origin.x + Double($0.column) * cellSize, origin.y + Double($0.row) * cellSize)
            }, closed: true))
        }
        return loops
    }

    /// The twelve free pentominoes, in the usual letter order: F, I, L, N, P, T, U,
    /// V, W, X, Y, Z. Free means a piece and its mirror count as one.
    public static let pentominoes: [Polyomino] = [
        Polyomino([".XX", "XX.", ".X."]),   // F
        Polyomino(["X", "X", "X", "X", "X"]),   // I
        Polyomino(["X.", "X.", "X.", "XX"]),   // L
        Polyomino([".X", ".X", "XX", "X."]),   // N
        Polyomino(["XX", "XX", "X."]),   // P
        Polyomino(["XXX", ".X.", ".X."]),   // T
        Polyomino(["X.X", "XXX"]),   // U
        Polyomino(["X..", "X..", "XXX"]),   // V
        Polyomino(["X..", "XX.", ".XX"]),   // W
        Polyomino([".X.", "XXX", ".X."]),   // X
        Polyomino([".X", "XX", ".X", ".X"]),   // Y
        Polyomino(["XX.", ".X.", ".XX"]),   // Z
    ]

    /// The letters the pentominoes are known by, in the same order as
    /// `pentominoes`.
    public static let pentominoNames = ["F", "I", "L", "N", "P", "T", "U", "V", "W", "X", "Y", "Z"]

    /// The five free tetrominoes: I, O, T, S, L.
    public static let tetrominoes: [Polyomino] = [
        Polyomino(["X", "X", "X", "X"]),   // I
        Polyomino(["XX", "XX"]),   // O
        Polyomino(["XXX", ".X."]),   // T
        Polyomino([".XX", "XX."]),   // S
        Polyomino(["X.", "X.", "XX"]),   // L
    ]
}

/// One piece put down: which of the given pieces it is, which way round, and
/// where it landed.
///
/// A `Polyomino` is a shape rather than a position (it normalizes itself back to
/// the origin whenever it is made), so where a piece sits is carried here instead.
public struct PolyominoPlacement: Hashable, Sendable {
    /// The index of the piece in the list handed to the solver.
    public let piece: Int
    /// The orientation used, in the piece's own coordinates.
    public let shape: Polyomino
    /// Where the shape's own origin lands, in the region's cell coordinates.
    public let at: Polyomino.Cell

    public init(piece: Int, shape: Polyomino, at: Polyomino.Cell) {
        self.piece = piece
        self.shape = shape
        self.at = at
    }

    /// The cells the piece covers, in the region's coordinates.
    public var cells: [Polyomino.Cell] {
        shape.cells.map { Polyomino.Cell($0.column + at.column, $0.row + at.row) }
    }

    /// The placed piece as an outline, in canvas units, ready to stroke or fill.
    public func outlines(cellSize: Double, origin: Vector2 = .zero) -> [Contour] {
        shape.outlines(cellSize: cellSize,
                       origin: Vector2(origin.x + Double(at.column) * cellSize,
                                       origin.y + Double(at.row) * cellSize))
    }
}

/// Fit `pieces` into `region` so that every cell is covered exactly once, or hand
/// back nil when no such fit exists.
///
/// ```swift
/// let board = Polyomino.rectangle(columns: 10, rows: 6)
/// let fit = tilePolyominoes(Polyomino.pentominoes, covering: board)
/// ```
///
/// By default each piece is used at most once, which is the puzzle the twelve
/// pentominoes are famous for. Pass `reuse: true` and each piece may be used as
/// often as it fits, which is the case for tiling a floor with a few shapes.
///
/// The search fills the first uncovered cell each time, so it fails fast: a cell
/// no piece can cover ends the branch immediately rather than after the rest of
/// the board is laid. Answering "no fit exists" still means the whole space was
/// searched, so keep the region to a puzzle's size rather than a wall's.
public func tilePolyominoes(_ pieces: [Polyomino], covering region: Polyomino,
                            reuse: Bool = false,
                            reflections: Bool = true) -> [PolyominoPlacement]? {
    var rng = SplitMix64(seed: 0)
    return tilePolyominoes(pieces, covering: region, reuse: reuse,
                           reflections: reflections, shuffled: false, using: &rng)
}

/// The same fit, with the order the pieces are tried shuffled by `rng`, so two
/// seeds give two different tilings of the same region.
public func tilePolyominoes<R: RandomNumberGenerator>(
    _ pieces: [Polyomino], covering region: Polyomino, reuse: Bool = false,
    reflections: Bool = true, using rng: inout R
) -> [PolyominoPlacement]? {
    tilePolyominoes(pieces, covering: region, reuse: reuse,
                    reflections: reflections, shuffled: true, using: &rng)
}

/// One way a piece can sit inside the region: which piece, where it landed, and
/// the region cell indices it covers.
private struct PolyominoOption {
    let piece: Int
    let shape: Polyomino
    let at: Polyomino.Cell
    let covered: [Int]
}

private func tilePolyominoes<R: RandomNumberGenerator>(
    _ pieces: [Polyomino], covering region: Polyomino, reuse: Bool,
    reflections: Bool, shuffled: Bool, using rng: inout R
) -> [PolyominoPlacement]? {
    let cells = region.cells
    guard !cells.isEmpty else { return [] }
    guard !pieces.isEmpty, pieces.allSatisfy({ !$0.isEmpty }) else { return nil }

    var index: [Polyomino.Cell: Int] = [:]
    for (i, cell) in cells.enumerated() { index[cell] = i }

    // Every way any piece can sit inside the region, gathered by the first cell it
    // covers, which is the cell the search will be trying to fill.
    var options: [PolyominoOption] = []
    var optionsByCell = [[Int]](repeating: [], count: cells.count)

    // The offsets are swept over the region's whole box, not over the region's
    // cells: a piece whose own bounding box starts on an empty corner (the F, for
    // one) sits at offsets that are not cells of the region at all. Both are
    // normalized to start at zero, so a negative offset could never place a piece
    // inside and is not tried.
    for (pieceIndex, piece) in pieces.enumerated() {
        for orientation in piece.orientations(reflections: reflections) {
            for row in 0 ..< region.rows {
                for column in 0 ..< region.columns {
                    var covered: [Int] = []
                    covered.reserveCapacity(orientation.cells.count)
                    for cell in orientation.cells {
                        guard let i = index[Polyomino.Cell(cell.column + column, cell.row + row)] else {
                            covered = []
                            break
                        }
                        covered.append(i)
                    }
                    guard covered.count == orientation.cells.count else { continue }
                    options.append(PolyominoOption(piece: pieceIndex, shape: orientation,
                                                   at: Polyomino.Cell(column, row),
                                                   covered: covered.sorted()))
                }
            }
        }
    }
    for (i, option) in options.enumerated() {
        for cell in option.covered { optionsByCell[cell].append(i) }
    }
    if shuffled {
        for i in optionsByCell.indices { optionsByCell[i].shuffle(using: &rng) }
    }

    var taken = [Bool](repeating: false, count: cells.count)
    var spent = [Int](repeating: 0, count: pieces.count)
    var laid: [PolyominoPlacement] = []

    // How many ways each cell can still be covered, kept up to date as pieces go
    // down rather than recounted, and how many of a placement's cells are already
    // spoken for. An option is still available when that second number is zero.
    var ways = [Int](repeating: 0, count: cells.count)
    for option in options {
        for cell in option.covered { ways[cell] += 1 }
    }
    var blocked = [Int](repeating: 0, count: options.count)

    func close(_ cell: Int) {
        for option in optionsByCell[cell] {
            if blocked[option] == 0 {
                for other in options[option].covered where other != cell { ways[other] -= 1 }
            }
            blocked[option] += 1
        }
    }

    func open(_ cell: Int) {
        for option in optionsByCell[cell].reversed() {
            blocked[option] -= 1
            if blocked[option] == 0 {
                for other in options[option].covered where other != cell { ways[other] += 1 }
            }
        }
    }

    func search() -> Bool {
        // Fill the cell with the fewest ways left, which is what keeps a long thin
        // board from being searched from one end to the other: the corner that is
        // running out of options is the one that decides the branch.
        var target = -1
        var fewest = Int.max
        for cell in cells.indices where !taken[cell] {
            if ways[cell] < fewest {
                fewest = ways[cell]
                target = cell
                if fewest == 0 { break }
            }
        }
        guard target >= 0 else { return true }
        guard fewest > 0 else { return false }

        for option in optionsByCell[target] where blocked[option] == 0 {
            if !reuse, spent[options[option].piece] > 0 { continue }
            for cell in options[option].covered { taken[cell] = true; close(cell) }
            spent[options[option].piece] += 1
            laid.append(PolyominoPlacement(piece: options[option].piece,
                                           shape: options[option].shape,
                                           at: options[option].at))
            if search() { return true }
            laid.removeLast()
            spent[options[option].piece] -= 1
            for cell in options[option].covered.reversed() { open(cell); taken[cell] = false }
        }
        return false
    }

    return search() ? laid : nil
}

public extension Sketch {
    /// Fit `pieces` into `region`, taking the order to try them from the sketch's
    /// own seeded generator, so a seed reproduces the tiling and a new seed finds
    /// another one.
    func tilePolyominoes(_ pieces: [Polyomino], covering region: Polyomino,
                         reuse: Bool = false, reflections: Bool = true) -> [PolyominoPlacement]? {
        Ollin.tilePolyominoes(pieces, covering: region, reuse: reuse,
                              reflections: reflections, using: &rng)
    }
}
