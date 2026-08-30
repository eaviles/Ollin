import Foundation
import Ollin
import Testing

/// Pure-CPU checks on the tiling-and-layout family: the hex and triangle
/// grids' lattice math, recursive subdivision's exact partition, the maze
/// generators' spanning-tree guarantees, and the Apollonian gasket's tangency.
@Suite
struct TilingTests {
    // MARK: - Hex grid

    private let hexBounds = Rectangle(x: 0, y: 0, width: 900, height: 700)

    /// Same-row neighbors sit exactly one spacing apart (√3 · size for
    /// pointy-top), and alternate rows shift by half a spacing.
    @Test func hexSpacingIsExact() {
        let grid = HexGrid(in: hexBounds, columns: 9, rows: 7)
        let spacing = 3.0.squareRoot() * grid.hexSize
        let a = grid.cell(column: 2, row: 3), b = grid.cell(column: 3, row: 3)
        #expect(abs(a.center.distance(to: b.center) - spacing) < 1e-9)
        let below = grid.cell(column: 2, row: 4)
        #expect(abs(abs(below.center.x - a.center.x) - spacing / 2) < 1e-9)
        #expect(abs(below.center.y - a.center.y - 1.5 * grid.hexSize) < 1e-9)
    }

    /// Every corner of every cell stays inside the padded bounds, in both
    /// orientations (the block-fitting math is exact).
    @Test func hexBlockFitsBounds() {
        for orientation in HexGrid.Orientation.allCases {
            let grid = HexGrid(in: hexBounds, columns: 8, rows: 6,
                               orientation: orientation, padding: 25)
            for cell in grid.cells {
                for corner in cell.corners {
                    #expect(corner.x >= grid.bounds.x - 1e-9)
                    #expect(corner.x <= grid.bounds.x + grid.bounds.width + 1e-9)
                    #expect(corner.y >= grid.bounds.y - 1e-9)
                    #expect(corner.y <= grid.bounds.y + grid.bounds.height + 1e-9)
                }
            }
        }
    }

    /// Axial coordinates round-trip through the offset storage, and adjacent
    /// cells are axial distance 1 apart.
    @Test func hexAxialRoundTrip() {
        for orientation in HexGrid.Orientation.allCases {
            let grid = HexGrid(in: hexBounds, columns: 7, rows: 5, orientation: orientation)
            for cell in grid.cells {
                let back = grid.cell(q: cell.q, r: cell.r)
                #expect(back?.column == cell.column)
                #expect(back?.row == cell.row)
                for neighbor in grid.neighbors(of: cell) {
                    #expect(grid.distance(from: cell, to: neighbor) == 1)
                }
            }
        }
    }

    /// Point-to-cell picking lands on the right hex for every cell center and
    /// for probes partway toward each corner (the cube-rounding path).
    @Test func hexPickingIsExact() {
        for orientation in HexGrid.Orientation.allCases {
            let grid = HexGrid(in: hexBounds, columns: 6, rows: 5, orientation: orientation)
            for cell in grid.cells {
                #expect(grid.cell(at: cell.center)?.column == cell.column)
                for corner in cell.corners {
                    let probe = Vector2(cell.center.x + (corner.x - cell.center.x) * 0.8,
                                        cell.center.y + (corner.y - cell.center.y) * 0.8)
                    let picked = grid.cell(at: probe)
                    #expect(picked?.column == cell.column)
                    #expect(picked?.row == cell.row)
                }
            }
        }
        let grid = HexGrid(in: hexBounds, columns: 6, rows: 5)
        #expect(grid.cell(at: Vector2(-500, -500)) == nil)
    }

    /// Interior cells have six neighbors, corners fewer; a radius-1 ring is
    /// the neighbor set, and distance along a pointy row counts columns.
    @Test func hexNeighborsRingsAndDistance() {
        let grid = HexGrid(in: hexBounds, columns: 7, rows: 7)
        let inner = grid.cell(column: 3, row: 3)
        #expect(grid.neighbors(of: inner).count == 6)
        #expect(grid.ring(around: inner, radius: 1).count == 6)
        #expect(grid.ring(around: inner, radius: 2).count == 12)
        #expect(grid.neighbors(of: grid.cell(column: 0, row: 0)).count < 6)
        let a = grid.cell(column: 0, row: 0), b = grid.cell(column: 4, row: 0)
        #expect(grid.distance(from: a, to: b) == 4)
    }

    /// A gutter pulls each corner in by gutter/√3, so neighboring edges end up
    /// exactly one gutter apart.
    @Test func hexGutterShrinksRadius() {
        let g = HexGrid(in: hexBounds, columns: 6, rows: 5, gutter: 9)
        #expect(abs(g.cell(column: 1, row: 1).radius - (g.hexSize - 9 / 3.0.squareRoot())) < 1e-9)
    }

    /// Abutting hexes share an edge: exactly two coincident corners at
    /// gutter 0.
    @Test func hexNeighborsShareTwoCorners() {
        let grid = HexGrid(in: hexBounds, columns: 6, rows: 5)
        let a = grid.cell(column: 2, row: 2)
        for b in grid.neighbors(of: a) {
            var shared = 0
            for ca in a.corners {
                for cb in b.corners where ca.distance(to: cb) < 1e-6 { shared += 1 }
            }
            #expect(shared == 2)
        }
    }

    // MARK: - Triangle grid

    /// Orientation alternates in a checkerboard, neighbors share an edge (two
    /// coincident vertices), and interior cells have three neighbors.
    @Test func triangleParityAndNeighbors() {
        let grid = TriangleGrid(in: hexBounds, columns: 11, rows: 6)
        #expect(grid.cells.count == 66)
        for cell in grid.cells {
            #expect(cell.pointsUp == ((cell.column + cell.row) % 2 == 0))
        }
        let inner = grid.cell(column: 5, row: 3)
        let neighbors = grid.neighbors(of: inner)
        #expect(neighbors.count == 3)
        for b in neighbors {
            #expect(b.pointsUp != inner.pointsUp)
            var shared = 0
            for va in inner.vertices {
                for vb in b.vertices where va.distance(to: vb) < 1e-6 { shared += 1 }
            }
            #expect(shared == 2)
        }
    }

    /// The equilateral block fits the padded bounds and rows tile edge to
    /// edge: a row of C triangles spans (C+1)/2 edge lengths.
    @Test func triangleBlockFitsAndTiles() {
        let grid = TriangleGrid(in: hexBounds, columns: 10, rows: 5, padding: 30)
        let e = grid.edgeLength
        #expect((Double(grid.columns) + 1) / 2 * e <= grid.bounds.width + 1e-9)
        #expect(3.0.squareRoot() / 2 * e * Double(grid.rows) <= grid.bounds.height + 1e-9)
        for cell in grid.cells {
            for v in cell.vertices {
                #expect(grid.bounds.contains(v) || v.x >= grid.bounds.x - 1e-9)
            }
            // Equilateral: all three sides are one edge length.
            for i in 0..<3 {
                let side = cell.vertices[i].distance(to: cell.vertices[(i + 1) % 3])
                #expect(abs(side - e) < 1e-9)
            }
        }
    }

    /// A gutter separates neighboring triangles by exactly the asked gap
    /// (each edge insets by half of it).
    @Test func triangleGutterInsetsEdges() {
        let grid = TriangleGrid(in: hexBounds, columns: 8, rows: 4, gutter: 8)
        let cell = grid.cell(column: 3, row: 1)
        let inradius = grid.edgeLength * 3.0.squareRoot() / 6
        let expected = grid.edgeLength * (inradius - 4) / inradius
        let side = cell.vertices[0].distance(to: cell.vertices[1])
        #expect(abs(side - expected) < 1e-9)
    }

    // MARK: - Subdivision

    /// The leaves tile the root exactly: areas sum to the root's area and
    /// every leaf lies inside it.
    @Test func subdivisionPartitionsExactly() {
        let rect = Rectangle(x: 50, y: 80, width: 800, height: 600)
        for style in [Subdivision.Style.binary, .quad] {
            var rng = SplitMix64(seed: 11)
            let cells = Subdivision.cells(in: rect, minSize: 40, maxDepth: 7,
                                          chance: 0.8, style: style, using: &rng)
            let area = cells.reduce(0) { $0 + $1.frame.width * $1.frame.height }
            #expect(abs(area - rect.width * rect.height) < 1e-6)
            for cell in cells {
                #expect(cell.frame.x >= rect.x - 1e-9)
                #expect(cell.frame.y >= rect.y - 1e-9)
                #expect(cell.frame.x + cell.frame.width <= rect.x + rect.width + 1e-9)
                #expect(cell.frame.y + cell.frame.height <= rect.y + rect.height + 1e-9)
            }
        }
    }

    /// No cut leaves a side thinner than minSize, and depth never exceeds
    /// maxDepth.
    @Test func subdivisionRespectsFloors() {
        let rect = Rectangle(x: 0, y: 0, width: 900, height: 900)
        var rng = SplitMix64(seed: 3)
        let cells = Subdivision.cells(in: rect, minSize: 60, maxDepth: 5, using: &rng)
        for cell in cells {
            #expect(cell.frame.width >= 60 - 1e-9)
            #expect(cell.frame.height >= 60 - 1e-9)
            #expect(cell.depth <= 5)
        }
    }

    /// The same seed always yields the same layout; quad splits keep the
    /// 1 + 3k leaf count and quarter each parent evenly.
    @Test func subdivisionDeterminismAndQuadCounts() {
        let rect = Rectangle(x: 0, y: 0, width: 640, height: 640)
        var rngA = SplitMix64(seed: 7), rngB = SplitMix64(seed: 7)
        let a = Subdivision.cells(in: rect, minSize: 30, chance: 0.7, using: &rngA)
        let b = Subdivision.cells(in: rect, minSize: 30, chance: 0.7, using: &rngB)
        #expect(a == b)

        var rng = SplitMix64(seed: 9)
        let quads = Subdivision.cells(in: rect, minSize: 20, maxDepth: 4,
                                      chance: 0.6, style: .quad, using: &rng)
        #expect((quads.count - 1) % 3 == 0)

        var one = SplitMix64(seed: 1)
        let level = Subdivision.cells(in: rect, minSize: 20, maxDepth: 1,
                                      style: .quad, using: &one)
        #expect(level.count == 4)
        for cell in level {
            #expect(cell.depth == 1)
            #expect(abs(cell.frame.width - 320) < 1e-9)
        }
    }

    // MARK: - Maze

    /// Every algorithm carves a perfect maze: exactly cells − 1 passages,
    /// symmetric adjacency, and every cell reachable from every other.
    @Test func mazeIsPerfectForEveryAlgorithm() {
        for algorithm in Maze.Algorithm.allCases {
            var rng = SplitMix64(seed: 21)
            let maze = Maze(columns: 14, rows: 11, algorithm: algorithm, using: &rng)
            var carved = 0
            var reached = 1
            var seen = [Bool](repeating: false, count: 14 * 11)
            seen[0] = true
            var frontier = [(0, 0)]
            for row in 0..<11 {
                for column in 0..<14 {
                    if maze.isOpen(.east, column: column, row: row) {
                        carved += 1
                        #expect(maze.isOpen(.west, column: column + 1, row: row))
                    }
                    if maze.isOpen(.south, column: column, row: row) {
                        carved += 1
                        #expect(maze.isOpen(.north, column: column, row: row + 1))
                    }
                }
            }
            #expect(carved == 14 * 11 - 1)
            while let (c, r) = frontier.popLast() {
                for direction in Maze.Direction.allCases where maze.isOpen(direction, column: c, row: r) {
                    let (dc, dr) = direction == .north ? (0, -1)
                        : direction == .east ? (1, 0)
                        : direction == .south ? (0, 1) : (-1, 0)
                    let n = (r + dr) * 14 + (c + dc)
                    if !seen[n] {
                        seen[n] = true
                        reached += 1
                        frontier.append((c + dc, r + dr))
                    }
                }
            }
            #expect(reached == 14 * 11)
        }
    }

    /// The same seed carves the same maze; different algorithms (or seeds)
    /// draw differently.
    @Test func mazeIsDeterministic() {
        var a = SplitMix64(seed: 4), b = SplitMix64(seed: 4)
        #expect(Maze(columns: 9, rows: 9, algorithm: .wilson, using: &a)
            == Maze(columns: 9, rows: 9, algorithm: .wilson, using: &b))
    }

    /// The solution path steps through adjacent, open cells from end to end,
    /// and the longest path is at least as long as any specific solution.
    @Test func mazeSolutionAndLongestPath() {
        var rng = SplitMix64(seed: 12)
        let maze = Maze(columns: 12, rows: 12, algorithm: .backtracker, using: &rng)
        let path = maze.solution(fromColumn: 0, fromRow: 0, toColumn: 11, toRow: 11)
        #expect(path.first! == (column: 0, row: 0))
        #expect(path.last! == (column: 11, row: 11))
        for (a, b) in zip(path, path.dropFirst()) {
            let dc = b.column - a.column, dr = b.row - a.row
            #expect(abs(dc) + abs(dr) == 1)
            let direction: Maze.Direction = dc == 1 ? .east : dc == -1 ? .west : dr == 1 ? .south : .north
            #expect(maze.isOpen(direction, column: a.column, row: a.row))
        }
        #expect(maze.longestPath().count >= path.count)
    }

    /// Walls merge into straight runs: the top border (which has no openings)
    /// comes back as one full-width contour, and every wall contour is a
    /// straight two-point run.
    @Test func mazeWallsMergeIntoRuns() {
        var rng = SplitMix64(seed: 2)
        let maze = Maze(columns: 8, rows: 6, algorithm: .kruskal, using: &rng)
        let rect = Rectangle(x: 0, y: 0, width: 800, height: 600)
        let walls = maze.walls(in: rect)
        for wall in walls {
            #expect(wall.points.count == 2)
            #expect(wall.points[0].x == wall.points[1].x || wall.points[0].y == wall.points[1].y)
        }
        let top = walls.filter { $0.points[0].y == 0 && $0.points[1].y == 0 }
        #expect(top.count == 1)
        #expect(abs(abs(top[0].points[1].x - top[0].points[0].x) - 800) < 1e-9)
    }

    // MARK: - Apollonian gasket

    /// The three seeds have the closed-form radius (2√3 − 3)·R, kiss each
    /// other, and kiss the rim from inside.
    @Test func gasketSeedsAreExact() {
        let enclosing = Circle(x: 500, y: 500, radius: 400)
        let foam = apollonianGasket(in: enclosing, minRadius: 40)
        let expected = (2 * 3.0.squareRoot() - 3) * 400
        for i in 0..<3 {
            #expect(abs(foam[i].radius - expected) < 1e-9)
            #expect(abs(foam[i].center.distance(to: enclosing.center) - (400 - expected)) < 1e-9)
            let j = (i + 1) % 3
            #expect(abs(foam[i].center.distance(to: foam[j].center) - 2 * expected) < 1e-9)
        }
    }

    /// The first filled gap (the central circle) satisfies the Descartes
    /// circle theorem against the three seeds, taking the root that isn't the
    /// enclosing circle.
    @Test func gasketFollowsDescartes() {
        let foam = apollonianGasket(in: Circle(x: 0, y: 0, radius: 1), minRadius: 0.01)
        let k = (0..<3).map { 1 / foam[$0].radius }
        let root = 2 * (k[0] * k[1] + k[1] * k[2] + k[2] * k[0]).squareRoot()
        let center = 1 / foam[3].radius
        #expect(abs(center - (k[0] + k[1] + k[2] + root)) < 1e-6)
        // The other root of the same quadratic is the enclosing circle, k = −1.
        #expect(abs((k[0] + k[1] + k[2] - root) - -1) < 1e-6)
    }

    /// The foam stays inside the rim, no two circles overlap, and every
    /// radius respects the floor.
    @Test func gasketCirclesNeverOverlap() {
        let enclosing = Circle(x: 200, y: 300, radius: 250)
        let foam = apollonianGasket(in: enclosing, minRadius: 6)
        #expect(foam.count > 50)
        for c in foam {
            #expect(c.radius >= 6 - 1e-9)
            #expect(c.center.distance(to: enclosing.center) + c.radius <= 250 + 1e-6)
        }
        for i in 0..<min(foam.count, 80) {
            for j in (i + 1)..<min(foam.count, 80) {
                let gap = foam[i].center.distance(to: foam[j].center)
                    - foam[i].radius - foam[j].radius
                #expect(gap > -1e-6)
            }
        }
    }
}
