import Foundation
import Ollin
import Testing

/// Parquet-deformation invariants: the shared-edge rule that makes it a tiling
/// at all, the blend reproducing both named profiles exactly, the lattice
/// corners staying put, the four sweeps running the right way, and the
/// undeformed cases collapsing to what they should.
@Suite struct ParquetDeformationTests {
    private let frame = Rectangle(x: 0, y: 0, width: 480, height: 360)

    private func sheet(columns: Int = 6, rows: Int = 5,
                       from start: ParquetDeformation.Profile = .straight,
                       to end: ParquetDeformation.Profile = .tooth(depth: 0.3),
                       sweep: ParquetDeformation.Sweep = .horizontal) -> ParquetDeformation {
        ParquetDeformation(grid: Grid(in: frame, columns: columns, rows: rows),
                           from: start, to: end, sweep: sweep)
    }

    /// The invariant the whole technique rests on: neighboring tiles do not
    /// merely meet, they are built from the *same* curve. Every point of a
    /// shared lattice edge appears in both tiles' outlines, exactly, with no
    /// tolerance, because both sides read one stored result.
    @Test func neighborsShareTheSameCurve() {
        let columns = 6, rows = 5
        let design = sheet(columns: columns, rows: rows,
                           from: .wave(count: 1, depth: 0.2),
                           to: .tooth(depth: 0.3, width: 0.4), sweep: .diagonal)
        let tiles = design.tiles
        let edges = design.edges
        let verticalBase = (rows + 1) * columns

        func tile(_ column: Int, _ row: Int) -> ParquetDeformation.Tile {
            tiles[row * columns + column]
        }

        var checked = 0
        // Every interior horizontal edge is shared by the tile above and below.
        for row in 1..<rows {
            for column in 0..<columns {
                let shared = edges[row * columns + column].points
                let above = Set(tile(column, row - 1).contour.points)
                let below = Set(tile(column, row).contour.points)
                #expect(shared.allSatisfy { above.contains($0) },
                        "the tile above must carry the shared edge point for point")
                #expect(shared.allSatisfy { below.contains($0) },
                        "the tile below must carry the shared edge point for point")
                checked += 1
            }
        }
        // Every interior vertical edge is shared by the tile left and right.
        for row in 0..<rows {
            for column in 1..<columns {
                let shared = edges[verticalBase + row * (columns + 1) + column].points
                let left = Set(tile(column - 1, row).contour.points)
                let right = Set(tile(column, row).contour.points)
                #expect(shared.allSatisfy { left.contains($0) })
                #expect(shared.allSatisfy { right.contains($0) })
                checked += 1
            }
        }
        #expect(checked == (rows - 1) * columns + rows * (columns - 1))
    }

    /// Every lattice edge is emitted exactly once, so stroking `edges` draws no
    /// line twice, which is what a pen plotter needs.
    @Test func everyLatticeEdgeAppearsOnce() {
        let columns = 6, rows = 5
        let design = sheet(columns: columns, rows: rows)
        #expect(design.edges.count == (rows + 1) * columns + rows * (columns + 1))
        #expect(design.tiles.count == columns * rows)
        #expect(design.edges.allSatisfy { !$0.isClosed })
    }

    /// The lattice's own corners never move, however deep the profiles run:
    /// each tile's outline starts at its top-left lattice corner.
    @Test func latticeCornersStayPut() {
        let columns = 6, rows = 5
        let design = sheet(columns: columns, rows: rows,
                           from: .bump(depth: 0.3), to: .zigzag(count: 3, depth: 0.25),
                           sweep: .radial)
        let cellWidth = frame.width / Double(columns)
        let cellHeight = frame.height / Double(rows)
        for tile in design.tiles {
            let corner = Vector2(frame.x + Double(tile.column) * cellWidth,
                                 frame.y + Double(tile.row) * cellHeight)
            #expect(tile.contour.points[0].distance(to: corner) < 1e-9)
            #expect(tile.contour.isClosed)
        }
    }

    /// A profile is reproduced exactly at its own end of the run: the blend
    /// samples at the union of both profiles' vertices, so a square tooth keeps
    /// its corners rather than arriving rounded off.
    @Test func theNamedProfilesSurviveTheBlend() {
        let tooth = ParquetDeformation.Profile.tooth(depth: 0.3)
        let design = ParquetDeformation(grid: Grid(in: frame, columns: 4, rows: 1),
                                        from: .straight, to: tooth) { point in
            point.x < frame.width / 2 ? 0 : 1
        }
        // The lattice's top line: the left half undeformed, the right half the
        // tooth in full, with all six of its vertices.
        let straightEdges = design.edges.prefix(2)
        #expect(straightEdges.allSatisfy { $0.points.count == 2 })

        let cellWidth = frame.width / 4
        let deformed = design.edges[2].points
        #expect(deformed.count == tooth.points.count)
        for (profilePoint, drawn) in zip(tooth.points, deformed) {
            // x runs along the edge, y is a fraction of its length, pushed to
            // the segment's left-hand perpendicular, downward for an edge that
            // runs to the right.
            let expected = Vector2(frame.x + 2 * cellWidth + profilePoint.x * cellWidth,
                                   frame.y + profilePoint.y * cellWidth)
            #expect(drawn.distance(to: expected) < 1e-9)
        }
    }

    /// With one profile at both ends nothing drifts, so every tile is the same
    /// piece translated: the parquet before it is deformed.
    @Test func oneProfileAtBothEndsTilesCongruently() {
        let columns = 5, rows = 4
        let design = ParquetDeformation(grid: Grid(in: frame, columns: columns, rows: rows),
                                        from: .tooth(depth: 0.25), to: .tooth(depth: 0.25))
        let tiles = design.tiles
        let first = tiles[0]
        let reference = first.contour.points.map { $0 - first.contour.points[0] }
        for tile in tiles.dropFirst() {
            let moved = tile.contour.points.map { $0 - tile.contour.points[0] }
            #expect(moved.count == reference.count)
            for (a, b) in zip(moved, reference) {
                #expect(a.distance(to: b) < 1e-9, "every tile must be the same piece moved")
            }
        }
    }

    /// Straight to straight is the plain grid: four corners a tile, sitting on
    /// the cells themselves.
    @Test func straightToStraightIsThePlainGrid() {
        let columns = 3, rows = 2
        let design = ParquetDeformation(grid: Grid(in: frame, columns: columns, rows: rows),
                                        from: .straight, to: .straight)
        let cellWidth = frame.width / Double(columns)
        let cellHeight = frame.height / Double(rows)
        for tile in design.tiles {
            #expect(tile.contour.points.count == 4)
            let expected = Rectangle(x: frame.x + Double(tile.column) * cellWidth,
                                     y: frame.y + Double(tile.row) * cellHeight,
                                     width: cellWidth, height: cellHeight)
            #expect(tile.contour.points[0].distance(to: expected.topLeft) < 1e-9)
            #expect(tile.contour.points[1].distance(to: expected.topRight) < 1e-9)
            #expect(tile.contour.points[2].distance(to: expected.bottomRight) < 1e-9)
            #expect(tile.contour.points[3].distance(to: expected.bottomLeft) < 1e-9)
        }
        #expect(design.edges.allSatisfy { $0.points.count == 2 })
    }

    /// Each sweep runs the amount the way it says, ending at 0 and 1.
    @Test func theSweepsRunTheirOwnWay() {
        let columns = 8, rows = 8
        func amounts(_ sweep: ParquetDeformation.Sweep) -> [Double] {
            sheet(columns: columns, rows: rows, sweep: sweep).tiles.map(\.amount)
        }

        let horizontal = amounts(.horizontal)
        for row in 0..<rows {
            let line = (0..<columns).map { horizontal[row * columns + $0] }
            #expect(line == line.sorted(), "a horizontal sweep must rise to the right")
            #expect(Set(line).count == columns, "and never repeat within a line")
        }

        let vertical = amounts(.vertical)
        for column in 0..<columns {
            let line = (0..<rows).map { vertical[$0 * columns + column] }
            #expect(line == line.sorted(), "a vertical sweep must rise downward")
        }

        let diagonal = amounts(.diagonal)
        #expect(diagonal[0] < diagonal[diagonal.count - 1])
        #expect(abs(diagonal[0] - (0.5 / Double(columns) + 0.5 / Double(rows)) / 2) < 1e-9)

        let radial = amounts(.radial)
        // The center of an even lattice is a tile corner, so the four tiles
        // around it are the nearest, and a corner tile is the farthest.
        #expect(radial[0] > radial[(rows / 2) * columns + columns / 2])
        #expect(radial.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    /// The closure form is the general one: the drift can come from anywhere,
    /// and answers outside `0`…`1` are clamped rather than extrapolated.
    @Test func aCustomAmountDrivesTheDrift() {
        let columns = 4, rows = 1
        let design = ParquetDeformation(grid: Grid(in: frame, columns: columns, rows: rows),
                                        from: .straight, to: .tooth(depth: 0.3)) { point in
            point.x < frame.width / 2 ? -5 : 12
        }
        let amounts = design.tiles.map(\.amount)
        #expect(amounts == [0, 0, 1, 1])
    }

    /// Profiles that describe nothing fall back to a straight edge rather than
    /// trapping, and a lattice with no cells is empty.
    @Test func degenerateInputsStayHarmless() {
        #expect(ParquetDeformation.Profile.zigzag(count: 0, depth: 0.2).points
            == ParquetDeformation.Profile.straight.points)
        #expect(ParquetDeformation.Profile.wave(count: 0, depth: 0.2).points
            == ParquetDeformation.Profile.straight.points)
        #expect(ParquetDeformation.Profile.bump(depth: 0).points
            == ParquetDeformation.Profile.straight.points)
        let tooShort: ParquetDeformation.Profile = .custom([])
        #expect(tooShort.points == ParquetDeformation.Profile.straight.points)
        // A hand-written profile has its ends pinned to the lattice corners.
        let handWritten: ParquetDeformation.Profile =
            .custom([Vector2(0.4, 0.9), Vector2(0.5, 0.2), Vector2(0.7, -0.4)])
        let pinned = handWritten.points
        #expect(pinned[0] == Vector2(0, 0))
        #expect(pinned[2] == Vector2(1, 0))
        #expect(pinned[1] == Vector2(0.5, 0.2))

        let empty = ParquetDeformation(grid: Grid(in: frame, columns: 0, rows: 4),
                                       from: .straight, to: .tooth(depth: 0.3))
        #expect(empty.tiles.isEmpty)
        #expect(empty.edges.isEmpty)
    }
}
