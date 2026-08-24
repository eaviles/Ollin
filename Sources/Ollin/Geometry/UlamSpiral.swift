import Foundation

/// The Ulam spiral: write the whole numbers in a square spiral from the middle
/// outward, then mark the ones that pass some test. Mark the primes and the
/// marks do not scatter. They gather along diagonal lines, which is what Stanisław
/// Ulam noticed on a notepad during a dull talk in 1963.
///
/// The lines are not a coincidence and not a proof of anything either. A diagonal
/// of the spiral is the run of values of a quadratic, so a diagonal that stays
/// crowded is a quadratic that keeps returning primes, and mathematics has known
/// such polynomials since Euler. What the picture does is make them visible.
///
/// ```swift
/// let spiral = ulamSpiral(size: 101)
/// noStroke(); fill(.white)
/// for point in spiral.primePoints { drawCircle(center: point, radius: 3) }
/// ```
///
/// The spiral is laid over a `Grid`, so every cell carries its own frame and
/// center, and `numbers` zips with `grid.cells` row by row. The whole square is
/// worked out when the value is made, so keep `size` to the hundreds for a
/// picture drawn every frame.
public struct UlamSpiral: Equatable, Sendable {
    /// The grid the spiral is written on. Square: as many columns as rows.
    public let grid: Grid
    /// The number in the middle cell, where the walk starts.
    public let start: Int
    /// The number written in each cell, row-major, so it zips with `grid.cells`.
    public let numbers: [Int]
    /// The cell index each number lands on, in counting order, so `order[0]` is
    /// the middle cell and `order[1]` the one the walk steps to first. A step the
    /// walk took outside the grid reads `-1`, which only an even-sided grid has.
    public let order: [Int]

    /// Write the numbers from `start` into `grid`, spiralling out from the middle.
    /// An even-sided grid has no middle cell, so the walk starts just past it.
    ///
    /// The walk goes right, then up, then left, then down, turning as soon as the
    /// side it is on runs out. On screen that reads counterclockwise, which is the
    /// way the picture is usually shown.
    public init(grid: Grid, start: Int = 1) {
        let columns = grid.columns, rows = grid.rows
        self.grid = grid
        self.start = start
        guard columns > 0, rows > 0 else {
            numbers = []
            order = []
            return
        }

        var written = [Int](repeating: 0, count: columns * rows)
        var walk: [Int] = []
        walk.reserveCapacity(columns * rows)
        var placed = 0

        // Step right, up, left, down, and the side lengths grow 1, 1, 2, 2, 3, 3 …
        var column = columns / 2, row = rows / 2
        var number = start
        var side = 1
        var direction = 0
        let steps: [(Int, Int)] = [(1, 0), (0, -1), (-1, 0), (0, 1)]

        // A step outside the grid still counts, so the numbering never skips; the
        // walk records it as -1. Only an even-sided grid, whose middle is off
        // center, ever leaves and comes back.
        func place() {
            guard column >= 0, column < columns, row >= 0, row < rows else {
                walk.append(-1)
                return
            }
            let index = row * columns + column
            written[index] = number
            walk.append(index)
            placed += 1
        }

        place()
        number += 1
        // Two sides of every length, and the walk stops once the square is full.
        while placed < columns * rows {
            for _ in 0 ..< 2 {
                let step = steps[direction % 4]
                for _ in 0 ..< side {
                    column += step.0
                    row += step.1
                    place()
                    number += 1
                    if placed == columns * rows { break }
                }
                direction += 1
                if placed == columns * rows { break }
            }
            side += 1
            // Far past the point where a spiral has covered any grid it started in.
            if side > 2 * (columns + rows) + 4 { break }
        }

        numbers = written
        order = walk
    }

    // MARK: - Reading it

    /// The middle of the cell `number` was written in, or `nil` if the spiral
    /// never reached it.
    public func point(of number: Int) -> Vector2? {
        let step = number - start
        guard step >= 0, step < order.count else { return nil }
        let index = order[step]
        guard index >= 0 else { return nil }
        return grid.cell(column: index % grid.columns, row: index / grid.columns).center
    }

    /// The number written at a cell, or `nil` outside the grid.
    public func number(column: Int, row: Int) -> Int? {
        guard column >= 0, column < grid.columns, row >= 0, row < grid.rows else { return nil }
        return numbers[row * grid.columns + column]
    }

    /// The middle of every cell whose number passes `test`, row-major.
    public func points(where test: (Int) -> Bool) -> [Vector2] {
        zip(grid.cells, numbers).compactMap { test($0.1) ? $0.0.center : nil }
    }

    /// The middle of every cell holding a prime, row-major. Worked out by one
    /// sieve over the whole square rather than a test per cell.
    public var primePoints: [Vector2] {
        guard let largest = numbers.max(), largest >= 2 else { return [] }
        var standing = [Bool](repeating: false, count: largest + 1)
        for prime in primes(upTo: largest) { standing[prime] = true }
        return zip(grid.cells, numbers).compactMap { cell, number in
            number >= 0 && number <= largest && standing[number] ? cell.center : nil
        }
    }

    /// The walk itself, from the middle outward, as one open contour. Stroke it to
    /// see the spiral the numbers are written along, or send it to a plotter.
    public var path: Contour {
        Contour(order.filter { $0 >= 0 }
            .map { grid.cell(column: $0 % grid.columns, row: $0 / grid.columns).center },
                closed: false)
    }
}

public extension Sketch {
    /// An Ulam spiral of `size × size` cells over `bounds` (the whole canvas by
    /// default), counting from `start` in the middle.
    ///
    /// ```swift
    /// let spiral = ulamSpiral(size: 101)
    /// noStroke(); fill(.white)
    /// for point in spiral.primePoints { drawCircle(center: point, radius: 3) }
    /// ```
    func ulamSpiral(in bounds: Rectangle? = nil, size: Int, start: Int = 1,
                    padding: Insets = .zero) -> UlamSpiral {
        let grid = Grid(in: bounds ?? self.bounds, columns: size, rows: size,
                        padding: padding)
        return UlamSpiral(grid: grid, start: start)
    }

    /// Draw an Ulam spiral's primes as filled dots in the current `fill`, one per
    /// cell, sized to the cell. For any other reading, hold the `ulamSpiral(…)`
    /// value and draw from `points(where:)` yourself.
    func drawUlamSpiral(in bounds: Rectangle? = nil, size: Int, start: Int = 1,
                        padding: Insets = .zero) {
        let spiral = ulamSpiral(in: bounds, size: size, start: start, padding: padding)
        let radius = Swift.min(spiral.grid.cellWidth, spiral.grid.cellHeight) * 0.4
        for point in spiral.primePoints { drawCircle(center: point, radius: radius) }
    }
}
