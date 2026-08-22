@testable import Ollin
import Testing

/// Pure-CPU checks on the kolam walk. The load-bearing one is the count: over a
/// plain field the line closes into exactly `gcd(rows, columns)` loops, which is
/// a theorem about the walk and not a matter of taste, so a picture could not
/// check it. Beside it sit the two conservation laws (four segments per cell,
/// every loop closed) and what a wall does to the count.
@Suite
struct KolamTests {

    private func design(columns: Int, rows: Int,
                        mirrors: [Kolam.Mirror] = []) -> Kolam {
        Kolam(grid: Grid(in: Rectangle(x: 0, y: 0, width: 100, height: 100),
                         columns: columns, rows: rows),
              mirrors: mirrors)
    }

    private func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        var x = a, y = b
        while y != 0 { (x, y) = (y, x % y) }
        return x
    }

    @Test func theLoopCountIsTheGreatestCommonDivisor() {
        for rows in 1 ... 8 {
            for columns in 1 ... 8 {
                let made = design(columns: columns, rows: rows).loopCount
                let want = greatestCommonDivisor(rows, columns)
                #expect(made == want,
                        "a \(columns) by \(rows) field must close into \(want) loops, made \(made)")
            }
        }
    }

    @Test func aFieldWithCoprimeSidesIsOneUnbrokenLine() {
        #expect(design(columns: 7, rows: 5).loopCount == 1)
        #expect(design(columns: 9, rows: 4).loopCount == 1)
        #expect(design(columns: 6, rows: 4).loopCount == 2, "and 6 by 4 is not")
    }

    @Test func everyCellHoldsFourSegments() {
        for (columns, rows) in [(1, 1), (3, 5), (6, 4), (8, 8)] {
            let loops = design(columns: columns, rows: rows).loops
            let segments = loops.reduce(0) { $0 + $1.points.count }
            #expect(segments == 4 * columns * rows,
                    "\(columns) by \(rows) held \(segments) segments")
            #expect(loops.allSatisfy { $0.isClosed }, "every loop closes")
            #expect(loops.allSatisfy { $0.points.count >= 4 }, "and none is degenerate")
        }
    }

    @Test func oneWallEitherCutsALoopInTwoOrJoinsTwoIntoOne() {
        // Every wall inside the field must move the count by exactly one. A wall
        // asked for on the outside edge is dropped instead, since the edge
        // already turns the line, and those are the cases that move nothing.
        let columns = 7, rows = 5
        let base = design(columns: columns, rows: rows).loopCount
        var moved = 0, dropped = 0
        for row in 0 ..< rows {
            for column in 0 ..< columns {
                for wall in [Kolam.Mirror.rightOf(column: column, row: row),
                             Kolam.Mirror.below(column: column, row: row)] {
                    let count = design(columns: columns, rows: rows, mirrors: [wall]).loopCount
                    let onTheEdge = (wall.isUpright && column == columns - 1)
                        || (!wall.isUpright && row == rows - 1)
                    if onTheEdge {
                        #expect(count == base, "a wall on the edge says nothing new")
                        dropped += 1
                    } else {
                        #expect(abs(count - base) == 1,
                                "a wall at \(column), \(row) moved the count by \(count - base)")
                        moved += 1
                    }
                }
            }
        }
        #expect(dropped == rows + columns, "the edge walls are the two outer runs")
        #expect(moved == 2 * columns * rows - rows - columns)
    }

    @Test func theLoopsStayInsideTheirBounds() {
        let bounds = Rectangle(x: 20, y: 40, width: 300, height: 200)
        let made = Kolam(grid: Grid(in: bounds, columns: 5, rows: 3))
        for loop in made.loops {
            for point in loop.points {
                #expect(point.x >= bounds.x - 1e-9 && point.x <= bounds.bottomRight.x + 1e-9)
                #expect(point.y >= bounds.y - 1e-9 && point.y <= bounds.bottomRight.y + 1e-9)
            }
        }
        #expect(made.dots.count == 15, "one dot per cell")
    }

    @Test func anEmptyFieldDrawsNothing() {
        #expect(design(columns: 0, rows: 4).loops.isEmpty)
        #expect(design(columns: 4, rows: 0).loops.isEmpty)
    }
}
