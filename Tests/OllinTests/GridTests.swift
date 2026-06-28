import Testing
@testable import Ollin

struct GridTests {

    @Test func cellSizeDividesTheBounds() {
        let g = Grid(in: Rectangle(x: 0, y: 0, width: 100, height: 60), columns: 4, rows: 3)
        #expect(g.cellWidth == 25)
        #expect(g.cellHeight == 20)
        #expect(g.cellSize == Vector2(25, 20))
    }

    @Test func cellsAndCenteredPointsAreCorrect() {
        let g = Grid(in: Rectangle(x: 0, y: 0, width: 100, height: 100), columns: 10, rows: 10)
        let c = g.cell(column: 0, row: 0)
        #expect(c.frame == Rectangle(x: 0, y: 0, width: 10, height: 10))
        #expect(c.center == Vector2(5, 5))
        #expect(g.point(column: 0, row: 0).position == Vector2(5, 5))     // cell center
        #expect(g.point(column: 2, row: 3).position == Vector2(25, 35))
    }

    @Test func elementsCarryTheirIndices() {
        let g = Grid(in: Rectangle(x: 0, y: 0, width: 30, height: 20), columns: 3, rows: 2)
        let c = g.cell(column: 2, row: 1)
        #expect(c.column == 2 && c.row == 1)
        let p = g.point(column: 1, row: 0)
        #expect(p.column == 1 && p.row == 0)
    }

    @Test func paddingInsetsTheBoundsBeforeDividing() {
        let g = Grid(in: Rectangle(x: 0, y: 0, width: 120, height: 120),
                     columns: 2, rows: 2, padding: .all(20))
        #expect(g.bounds == Rectangle(x: 20, y: 20, width: 80, height: 80))
        #expect(g.cellWidth == 40)
    }

    @Test func gutterShrinksCellsAndSpacesThem() {
        // 3 cells across 100 with a 10pt gutter: 100 - 2*10 = 80, /3 cells.
        let g = Grid(in: Rectangle(x: 0, y: 0, width: 100, height: 100),
                     columns: 3, rows: 1, gutter: 10)
        #expect(g.cellWidth == 80.0 / 3.0)
        #expect(g.cell(column: 0, row: 0).frame.x == 0)
        #expect(g.cell(column: 1, row: 0).frame.x == 80.0 / 3.0 + 10)   // one cell + one gutter
    }

    @Test func insetsBuildersHitTheRightEdges() {
        #expect(Insets.all(10) == Insets(top: 10, right: 10, bottom: 10, left: 10))
        #expect(Insets.symmetric(horizontal: 4, vertical: 8) == Insets(top: 8, right: 4, bottom: 8, left: 4))
        #expect(Insets.horizontal(6) == Insets(top: 0, right: 6, bottom: 0, left: 6))
        #expect(Insets.vertical(6) == Insets(top: 6, right: 0, bottom: 6, left: 0))
    }

    @Test func bareNumberPaddingIsAllEdges() {
        let g = Grid(in: Rectangle(x: 0, y: 0, width: 100, height: 100),
                     columns: 1, rows: 1, padding: 25)
        #expect(g.bounds == Rectangle(x: 25, y: 25, width: 50, height: 50))
    }

    @Test func insetNeverInverts() {
        let r = Rectangle(x: 0, y: 0, width: 10, height: 10).inset(by: .all(20))
        #expect(r.width == 0)
        #expect(r.height == 0)
    }

    @Test func pointsAndCellsAreRowMajor() {
        let g = Grid(in: Rectangle(x: 0, y: 0, width: 30, height: 20), columns: 3, rows: 2)
        #expect(g.points.count == 6)
        #expect(g.cells.count == 6)
        // Index 0,1,2 are row 0 (left→right); 3,4,5 are row 1.
        #expect(g.cells[0].column == 0 && g.cells[0].row == 0)
        #expect(g.cells[2].column == 2 && g.cells[2].row == 0)
        #expect(g.cells[3].column == 0 && g.cells[3].row == 1)
        #expect(g.points[3].position == g.point(column: 0, row: 1).position)
    }

    @Test func centeredPointIsAlwaysTheTrueCellCenter() {
        let g = Grid(in: Rectangle(x: 0, y: 0, width: 100, height: 100), columns: 10, rows: 10)
        #expect(g.distribution == .center)
        #expect(g.points[0].position == g.cell(column: 0, row: 0).center)
    }

    @Test func spanningPointsReachTheEdges() {
        let g = Grid(in: Rectangle(x: 0, y: 0, width: 100, height: 100),
                     columns: 5, rows: 5, distribution: .spanning)
        // Outer points sit on the bounds; spacing is width/(count-1) = 25.
        #expect(g.point(column: 0, row: 0).position == Vector2(0, 0))
        #expect(g.point(column: 4, row: 4).position == Vector2(100, 100))
        #expect(g.point(column: 1, row: 0).position == Vector2(25, 0))
        #expect(g.points.count == 25)
        #expect(g.points.first?.position == Vector2(0, 0))
        #expect(g.points.last?.position == Vector2(100, 100))
        // Cells still tile and keep their true centers, spanning or not.
        #expect(g.cell(column: 0, row: 0).center == Vector2(10, 10))
    }

    @Test func spanningSinglePointCentersInsteadOfDividingByZero() {
        let g = Grid(in: Rectangle(x: 0, y: 0, width: 80, height: 80),
                     columns: 1, rows: 1, distribution: .spanning)
        #expect(g.point(column: 0, row: 0).position == Vector2(40, 40))
    }

    @Test func gridsNestThroughACellFrame() {
        let outer = Grid(in: Rectangle(x: 0, y: 0, width: 100, height: 100), columns: 2, rows: 2)
        let inner = Grid(in: outer.cell(column: 1, row: 0).frame, columns: 5, rows: 5)
        #expect(inner.bounds == Rectangle(x: 50, y: 0, width: 50, height: 50))
        #expect(inner.cellWidth == 10)
    }

    @Test func zeroDimensionsAreEmptyNotADivideByZero() {
        let g = Grid(in: Rectangle(x: 0, y: 0, width: 100, height: 100), columns: 0, rows: 4)
        #expect(g.cellWidth == 0)
        #expect(g.points.isEmpty)
        #expect(g.cells.isEmpty)
    }
}
