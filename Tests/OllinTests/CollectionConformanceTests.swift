import Ollin
import Testing

/// The types that are a list of things now say so. Two questions per type:
/// that walking it agrees with the array property it used to need, element
/// for element, and that the conformance did not quietly change what an
/// existing call means.
///
/// Plain `import Ollin`, no `@testable`: only a plain import sees what a
/// sketch sees, which is the whole point of a conformance.
@Suite
struct CollectionConformanceTests {

    // MARK: A contour is its points

    @Test func contourWalksItsPoints() {
        let points = [Vector2(0, 0), Vector2(100, 0), Vector2(100, 80), Vector2(20, 60)]
        let contour = Contour(points)
        #expect(contour.count == 4)
        #expect(contour.isEmpty == false)
        #expect(Array(contour) == points)
        #expect(contour.first == points[0])
        #expect(contour.last == points[3])
        for (index, point) in contour.enumerated() {
            #expect(point == points[index])
            #expect(contour[index] == points[index])
        }
        #expect(Array(contour.reversed()) == points.reversed())
        #expect(contour.map(\.x) == points.map(\.x))
    }

    @Test func anEmptyContourIsAnEmptyCollection() {
        let contour = Contour([])
        #expect(contour.isEmpty)
        #expect(contour.count == 0)
        #expect(contour.first == nil)
        #expect(Array(contour).isEmpty)
    }

    /// The shared `Vector` surface reaches a contour now, so the mean of its
    /// points is one call. It is the *points'* mean, which is a different
    /// question from where a filled shape balances.
    @Test func contourReachesTheSharedVectorSurface() {
        let contour = Contour([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
        #expect(contour.centroid == Vector2(5, 5))
        #expect(Contour([]).centroid == nil)
    }

    /// The trap the conformance could have set: `contains` on a contour must
    /// stay the geometric question `Shape.contains(_:)` answers, not the
    /// membership question a collection would answer.
    @Test func containsOnAContourIsGeometric() {
        let square = Contour([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)])
        // The decisive pair: a point inside the square that is not one of its
        // four vertices. The geometric answer is true, the membership answer
        // false, so this says which one `contains` resolved to.
        #expect(square.contains(Vector2(50, 50)))
        #expect(square.points.contains(Vector2(50, 50)) == false)
        #expect(square.contains(Vector2(150, 50)) == false)
        // The membership question is still reachable, spelled as itself.
        #expect(square.points.contains(Vector2(0, 0)))
        // A point exactly on the boundary is not asserted either way: the ray
        // test documents it as landing on either side.
        // And it agrees with the shape built from the same points.
        let shape = Shape(square.points)
        for probe in [Vector2(50, 50), Vector2(150, 50), Vector2(99, 1), Vector2(-1, -1)] {
            #expect(square.contains(probe) == shape.contains(probe))
        }
    }

    @Test func aContourOfTwoPointsEnclosesNothing() {
        let line = Contour([Vector2(0, 0), Vector2(100, 100)], closed: false)
        #expect(line.contains(Vector2(50, 50)) == false)
        #expect(line.count == 2)
    }

    // MARK: A shape is its contours

    @Test func shapeWalksItsContours() {
        let outer = Contour([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)])
        let hole = Contour([Vector2(30, 30), Vector2(70, 30), Vector2(70, 70), Vector2(30, 70)])
        let shape = Shape(contours: [outer, hole])
        #expect(shape.count == 2)
        #expect(Array(shape) == [outer, hole])
        #expect(shape.first == outer)
        #expect(shape[1] == hole)
        // The elements are contours, so flattening walks every point.
        #expect(Array(shape.flatMap { $0 }) == outer.points + hole.points)
    }

    /// `Shape.contains(_ point:)` predates the conformance and must still win
    /// over the collection's `contains(_ element:)`.
    @Test func containsOnAShapeStaysGeometric() {
        let outer = Contour([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)])
        let shape = Shape(contours: [outer])
        #expect(shape.contains(Vector2(50, 50)))
        #expect(shape.contains(outer))                       // the element question
        #expect(shape.contains(Contour([Vector2(9, 9)])) == false)
    }

    // MARK: The three grids are their cells

    /// `cells` now reads through the conformance, so comparing the two would
    /// be tautological. The order is pinned against the row-major walk written
    /// out here instead, which is the walk `cells` used to do for itself.
    @Test func gridOrderIsTheRowMajorWalkItAlwaysWas() {
        let grid = Grid(in: Rectangle(x: 12, y: 8, width: 640, height: 480),
                        columns: 6, rows: 4, gutter: 5)
        var expected = [Grid.Cell]()
        for row in 0..<4 {
            for column in 0..<6 { expected.append(grid.cell(column: column, row: row)) }
        }
        #expect(Array(grid) == expected)
        #expect(grid.cells == expected)

        let hexes = HexGrid(in: Rectangle(x: 0, y: 0, width: 500, height: 500),
                            columns: 5, rows: 3, gutter: 2)
        var hexExpected = [HexGrid.Cell]()
        for row in 0..<3 {
            for column in 0..<5 { hexExpected.append(hexes.cell(column: column, row: row)) }
        }
        #expect(Array(hexes) == hexExpected)
        #expect(hexes.cells == hexExpected)

        let tris = TriangleGrid(in: Rectangle(x: 0, y: 0, width: 500, height: 300),
                                columns: 7, rows: 3, gutter: 1)
        var triExpected = [TriangleGrid.Cell]()
        for row in 0..<3 {
            for column in 0..<7 { triExpected.append(tris.cell(column: column, row: row)) }
        }
        #expect(Array(tris) == triExpected)
        #expect(tris.cells == triExpected)
    }

    @Test func gridWalksItsCellsInTheSameOrder() {
        let grid = Grid(in: Rectangle(x: 0, y: 0, width: 800, height: 600),
                        columns: 7, rows: 5, gutter: 4)
        let cells = grid.cells
        #expect(grid.count == 35)
        #expect(cells.count == 35)
        #expect(Array(grid) == cells)
        for (index, cell) in grid.enumerated() {
            #expect(cell == cells[index])
            // Row-major: the index spells the address back.
            #expect(cell.column == index % 7)
            #expect(cell.row == index / 7)
        }
        #expect(grid.first == grid.cell(column: 0, row: 0))
        #expect(grid.last == grid.cell(column: 6, row: 4))
    }

    @Test func hexGridWalksItsCellsInTheSameOrder() {
        let grid = HexGrid(in: Rectangle(x: 10, y: 20, width: 700, height: 500),
                           columns: 9, rows: 6, orientation: .flat, gutter: 3)
        let cells = grid.cells
        #expect(grid.count == 54)
        #expect(Array(grid) == cells)
        for (index, cell) in grid.enumerated() {
            #expect(cell == cells[index])
            #expect(cell.column == index % 9)
            #expect(cell.row == index / 9)
        }
    }

    @Test func triangleGridWalksItsCellsInTheSameOrder() {
        let grid = TriangleGrid(in: Rectangle(x: 0, y: 0, width: 900, height: 400),
                                columns: 11, rows: 4, gutter: 2)
        let cells = grid.cells
        #expect(grid.count == 44)
        #expect(Array(grid) == cells)
        for (index, cell) in grid.enumerated() {
            #expect(cell == cells[index])
            #expect(cell.column == index % 11)
            #expect(cell.row == index / 11)
        }
    }

    // MARK: A piece is its squares

    @Test func polyominoWalksItsSquaresInReadingOrder() {
        let ell = Polyomino(["X.", "X.", "XX"])
        #expect(ell.count == 4)
        #expect(ell.isEmpty == false)
        #expect(Array(ell) == ell.cells)
        #expect(ell.first == Polyomino.Cell(0, 0))
        #expect(ell.last == Polyomino.Cell(1, 2))
        // Reading order: down the rows first, then across.
        #expect(ell.sorted() == Array(ell))
        #expect(ell.contains(Polyomino.Cell(1, 2)))
        #expect(ell.contains(Polyomino.Cell(1, 0)) == false)
        #expect(ell.map(\.row) == [0, 1, 2, 2])
        #expect(Polyomino(cells: []).isEmpty)
    }

    /// The same shape drawn two ways walks the same squares, because the
    /// squares are normalized before they are stored.
    @Test func twoSpellingsOfOnePieceWalkAlike() {
        let drawn = Polyomino(["XX", ".X"])
        let listed = Polyomino(cells: [.init(5, 9), .init(6, 9), .init(6, 10)])
        #expect(Array(drawn) == Array(listed))
        #expect(drawn == listed)
    }

    /// A grid asked for nothing is an empty collection rather than a crash.
    @Test func anEmptyGridIsAnEmptyCollection() {
        let grid = Grid(in: Rectangle(x: 0, y: 0, width: 100, height: 100), columns: 0, rows: 0)
        #expect(grid.isEmpty)
        #expect(grid.count == 0)
        #expect(Array(grid).isEmpty)
        #expect(grid.cells.isEmpty)
    }

    /// What the conformance is for: the whole standard library arrives.
    @Test func theStandardLibraryReachesAGrid() {
        let grid = Grid(in: Rectangle(x: 0, y: 0, width: 400, height: 400), columns: 4, rows: 4)
        let corners = grid.filter { $0.column == 0 || $0.column == 3 }
        #expect(corners.count == 8)
        #expect(grid.map(\.center).count == 16)
        #expect(grid.contains(grid.cell(column: 2, row: 2)))
        let checker = grid.enumerated().filter { $0.offset % 2 == 0 }
        #expect(checker.count == 8)
    }
}
