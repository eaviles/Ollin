import Ollin
import Testing

/// Laws for the primes and for the square spiral they are written on. The spiral
/// is a bijection that steps one cell at a time, the odd squares sit on one
/// diagonal, and a quadratic traces a straight line, which is the whole reason
/// the picture has lines in it.
@Suite
struct UlamSpiralTests {
    // MARK: - The primes

    /// The sieve against the numbers everyone knows.
    @Test func theSieveFindsTheKnownPrimes() {
        #expect(primes(upTo: 30) == [2, 3, 5, 7, 11, 13, 17, 19, 23, 29])
        #expect(primes(upTo: 1).isEmpty)
        #expect(primes(upTo: 2) == [2])
        // 25 primes below 100, 168 below 1000: the counts every table starts with.
        #expect(primes(upTo: 100).count == 25)
        #expect(primes(upTo: 1000).count == 168)
    }

    /// The one-number test and the whole-run sieve have to agree, or one of them
    /// is wrong.
    @Test func theTwoWaysOfAskingAgree() {
        let sieved = Set(primes(upTo: 5000))
        for n in -3 ... 5000 {
            #expect(isPrime(n) == sieved.contains(n), "disagreed about \(n)")
        }
    }

    // MARK: - The walk

    /// Every cell holds its own number, and every number lands on its own cell.
    @Test func theWalkVisitsEveryCellExactlyOnce() {
        let spiral = UlamSpiral(grid: Grid(in: Rectangle(x: 0, y: 0, width: 90, height: 90),
                                           columns: 9, rows: 9))
        #expect(Set(spiral.numbers) == Set(1 ... 81))
        #expect(spiral.order.count == 81)
        #expect(Set(spiral.order) == Set(0 ..< 81))

        for number in 1 ... 81 {
            let point = spiral.point(of: number)
            #expect(point != nil)
        }
        #expect(spiral.point(of: 82) == nil)
        #expect(spiral.point(of: 0) == nil)
    }

    /// One step at a time: consecutive numbers are always in touching cells, which
    /// is what makes it a walk rather than a scatter.
    @Test func consecutiveNumbersAreNeighbors() {
        let spiral = UlamSpiral(grid: Grid(in: Rectangle(x: 0, y: 0, width: 110, height: 110),
                                           columns: 11, rows: 11))
        for step in 1 ..< spiral.order.count {
            let before = spiral.order[step - 1], now = spiral.order[step]
            let dc = abs(before % 11 - now % 11), dr = abs(before / 11 - now / 11)
            #expect(dc + dr == 1, "step \(step) jumped \(dc), \(dr)")
        }
    }

    /// The odd squares walk out along one diagonal and the even squares along the
    /// opposite one. That falls out of the spiral's own shape: a square number
    /// lands where a ring closes, and the rings close in alternating corners. The
    /// even ones sit one step off their diagonal, because their ring turns the
    /// corner just before it closes.
    @Test func theSquaresWalkOutAlongTwoDiagonals() {
        let spiral = UlamSpiral(grid: Grid(in: Rectangle(x: 0, y: 0, width: 130, height: 130),
                                           columns: 13, rows: 13))
        let middle = 6

        for odd in stride(from: 1, through: 13, by: 2) {
            let cell = try? cellOf(odd * odd, in: spiral, size: 13)
            #expect(cell != nil)
            guard let cell else { continue }
            // Down and to the right of the middle, in equal measure.
            #expect(cell.column - middle == (odd - 1) / 2)
            #expect(cell.row - middle == (odd - 1) / 2)
        }
        for even in stride(from: 2, through: 12, by: 2) {
            guard let cell = try? cellOf(even * even, in: spiral, size: 13) else {
                Issue.record("no cell for \(even * even)")
                continue
            }
            // Up and to the left, one step short across.
            #expect(middle - cell.column == (even - 2) / 2)
            #expect(middle - cell.row == even / 2)
        }
    }

    /// The reason the picture has lines in it: a diagonal of the spiral is the run
    /// of values of a quadratic, so the values of one quadratic fall on a straight
    /// line. Ulam's own example is `4n² + 2n + 1`, and its cells must be evenly
    /// spaced along one direction.
    @Test func aQuadraticTracesAStraightLine() {
        let size = 41
        let spiral = UlamSpiral(grid: Grid(in: Rectangle(x: 0, y: 0, width: 410, height: 410),
                                           columns: size, rows: size))
        var cells: [(column: Int, row: Int)] = []
        for n in 0 ... 6 {
            let value = 4 * n * n + 2 * n + 1
            guard value <= size * size,
                  let cell = try? cellOf(value, in: spiral, size: size) else { continue }
            cells.append(cell)
        }
        #expect(cells.count >= 5, "expected several values inside the square")

        let first = cells[0], second = cells[1]
        let stepColumn = second.column - first.column, stepRow = second.row - first.row
        #expect(abs(stepColumn) == abs(stepRow), "a diagonal steps the same both ways")
        for (index, cell) in cells.enumerated() {
            #expect(cell.column - first.column == stepColumn * index,
                    "value \(index) left the line")
            #expect(cell.row - first.row == stepRow * index)
        }
    }

    // MARK: - Reading it

    /// The prime marks and a hand-written test pick out the same cells.
    @Test func thePrimeMarksAreThePrimes() {
        let spiral = UlamSpiral(grid: Grid(in: Rectangle(x: 0, y: 0, width: 150, height: 150),
                                           columns: 15, rows: 15))
        #expect(spiral.primePoints == spiral.points(where: { isPrime($0) }))
        #expect(spiral.primePoints.count == primes(upTo: 225).count)
    }

    /// Counting from somewhere else moves every number, and the marks with them.
    @Test func startingElsewhereShiftsTheWholeSquare() {
        let grid = Grid(in: Rectangle(x: 0, y: 0, width: 90, height: 90), columns: 9, rows: 9)
        let plain = UlamSpiral(grid: grid)
        let shifted = UlamSpiral(grid: grid, start: 41)
        #expect(shifted.numbers == plain.numbers.map { $0 + 40 })
        #expect(shifted.point(of: 41) == plain.point(of: 1))
    }

    /// The walk drawn as a path has a point per cell and never doubles back onto
    /// the point it just left.
    @Test func thePathIsTheWalk() {
        let spiral = UlamSpiral(grid: Grid(in: Rectangle(x: 0, y: 0, width: 70, height: 70),
                                           columns: 7, rows: 7))
        let path = spiral.path
        #expect(!path.isClosed)
        #expect(path.points.count == 49)
        for i in 1 ..< path.points.count {
            #expect((path.points[i] - path.points[i - 1]).length > 0)
        }
    }

    /// The cell a number landed on, worked out from the row-major numbers.
    private func cellOf(_ number: Int, in spiral: UlamSpiral,
                        size: Int) throws -> (column: Int, row: Int) {
        guard let index = spiral.numbers.firstIndex(of: number) else {
            throw CellMissing()
        }
        return (index % size, index / size)
    }

    private struct CellMissing: Error {}
}
