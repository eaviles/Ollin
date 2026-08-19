import Foundation
import Ollin

/// A shape measured once, so it can be struck anywhere afterwards.
///
/// Working out what an outline rings at is real arithmetic, and where it is
/// struck only changes how loud each of those tones is. Doing the work once and
/// keeping the answer is what lets a sketch strike a shape wherever the mouse
/// lands without stopping to think about it.
///
/// ```swift
/// let bell = StruckShape(outline)              // once, in setup()
///
/// override func mousePressed() {
///     synth.voice = Voice(body: bell!.body(struckAt: Vector2(mouseX, mouseY)))
///     synth.play("C4")
/// }
/// ```
public struct StruckShape: Sendable {

    /// What the shape rings at, as multiples of its lowest tone.
    ///
    /// A symmetric shape has some of these twice over, because a pattern that
    /// fits at one rotation fits at another and both are really there. A drum
    /// does the same.
    public let ratios: [Double]

    /// How far each tone moves at each measured point, which is what decides
    /// how much a strike there puts into it.
    private let movement: [[Double]]
    private let points: [Vector2]
    private let middle: Vector2

    /// Measures a shape. Nil if it is too small or too thin to hold a standing
    /// wave at all.
    ///
    /// This is the expensive part, so do it once and keep the result. Measuring
    /// a circle at the default takes a few hundredths of a second in a release
    /// build and a second or two unoptimized, which is what a sketch run
    /// straight from source is.
    ///
    /// - Parameters:
    ///   - shape: the outline. Holes count: a shape with a hole in it rings
    ///     differently from one without.
    ///   - modes: how many tones to work out, up to ``ModalBody/maxModes``.
    ///   - resolution: how finely the shape is measured, across its longest
    ///     side. The default is where the accuracy stops improving much:
    ///     a circle measured at 40 lands its tones within half a percent of
    ///     what a real drumhead gives, and finer barely moves them.
    public init?(_ shape: Shape, modes: Int = 12, resolution: Int = 40) {
        let wanted = min(max(1, modes), ModalBody.maxModes)
        guard let solved = ShapeModes.solve(
            shape: shape, wanted: wanted, resolution: resolution
        ) else { return nil }
        ratios = solved.ratios
        movement = solved.movement
        points = solved.points
        middle = solved.defaultStrike
    }

    /// How much a strike at a point puts into each tone, loudest scaled to 1.
    ///
    /// A tone that holds still where you hit it gets nothing, which is the same
    /// reason a string plucked in the middle sounds hollow. Where two tones
    /// share a frequency, which of them takes the strike is arbitrary, so read
    /// their two numbers together rather than one at a time.
    public func gains(struckAt point: Vector2) -> [Double] {
        guard let cell = nearest(to: point) else {
            return [Double](repeating: 1, count: ratios.count)
        }
        let raw = movement.map { abs($0[cell]) }
        let loudest = raw.max() ?? 1
        return loudest > 1e-12 ? raw.map { $0 / loudest } : raw
    }

    /// The body this shape is, struck at a point.
    ///
    /// Nil for the point strikes a spot off to one side, which sets most things
    /// ringing; the exact middle of a symmetric shape is the one place where
    /// half its tones hold still.
    public func body(
        struckAt point: Vector2? = nil,
        decay: Double = 2.0,
        damping: Double = 1.0,
        hardness: Double = 0.7
    ) -> ModalBody {
        let gains = gains(struckAt: point ?? middle)
        return ModalBody(
            modes: zip(ratios, gains).map { ModalBody.Mode(ratio: $0, gain: $1) },
            decay: decay, damping: damping, hardness: hardness
        )
    }

    private func nearest(to point: Vector2) -> Int? {
        var best: Int?
        var bestDistance = Double.infinity
        for (index, position) in points.enumerated() {
            let distance = (position - point).lengthSquared
            if distance < bestDistance { bestDistance = distance; best = index }
        }
        return best
    }
}

public extension ModalBody {
    /// The body a drawn shape would be, if you could strike it.
    ///
    /// ```swift
    /// let outline = textToShapes("O").first!
    /// let body = ModalBody(shape: outline)
    /// synth.voice = Voice(body: body)
    /// ```
    ///
    /// A flat shape held at its edge rings at frequencies decided entirely by
    /// its outline, and working them out is a matter of asking which standing
    /// waves fit inside it. A circle gives the ratios of a drumhead, a square
    /// gives a square membrane's, and a shape nobody has a name for gives its
    /// own. Only the ratios come from the shape: which note it is playing is
    /// decided when you play it, so one outline is an instrument rather than a
    /// single sound.
    ///
    /// This measures the shape every time. To strike one shape in different
    /// places, measure it once with ``StruckShape`` and ask that for a body
    /// instead. A shape too small or too thin to hold a standing wave comes
    /// back as a plate, and says so once.
    init(
        shape: Shape,
        struckAt: Vector2? = nil,
        modes: Int = 12,
        resolution: Int = 40,
        decay: Double = 2.0,
        damping: Double = 1.0,
        hardness: Double = 0.7
    ) {
        if let measured = StruckShape(shape, modes: modes, resolution: resolution) {
            self = measured.body(struckAt: struckAt, decay: decay,
                                 damping: damping, hardness: hardness)
        } else {
            audioNoteOnce("that shape is too small or too thin to work out modes for; "
                          + "using a plate. Try a larger shape or a higher resolution.")
            let wanted = min(max(1, modes), ModalBody.maxModes)
            self.init(modes: Array(ModalBody.plate.modes.prefix(wanted)),
                      decay: decay, damping: damping, hardness: hardness)
        }
    }
}

/// Works out which standing waves fit inside a shape.
///
/// A flat plate held at its edge vibrates in the shapes that solve `-∆u = λu`
/// with nothing moving at the boundary, and it rings at frequencies
/// proportional to the square roots of those λ. So the sound of a shape is an
/// eigenvalue problem, and the whole of this file is finding the smallest
/// handful of them.
///
/// The shape is measured onto a grid, which turns the continuous problem into a
/// large sparse symmetric one. Only the lowest eigenvalues are wanted, and the
/// reliable way to get those is to work with the inverse, whose *largest*
/// eigenvalues they are. That needs a solve rather than a multiply, which is
/// what the banded factorization below is for: numbering the cells row by row
/// keeps every neighbor within one grid width, so the matrix is a band and
/// factorizing it is cheap.
enum ShapeModes {

    /// What a shape rings at, and how far each of those tones moves at every
    /// point it was measured on. Nil if the shape holds no standing wave.
    static func solve(
        shape: Shape, wanted: Int, resolution: Int
    ) -> (ratios: [Double], movement: [[Double]], points: [Vector2], defaultStrike: Vector2)? {
        guard let grid = Grid(shape: shape, resolution: resolution), grid.count >= 24 else {
            return nil
        }

        let subspace = min(grid.count, wanted + 6)
        guard let solved = lowestEigenpairs(of: grid, count: wanted, subspace: subspace) else {
            return nil
        }

        // Frequency goes as the square root of the eigenvalue, and only the
        // ratios survive: the grid spacing cancels, which is why the answer
        // does not depend on how big the shape was drawn.
        let base = solved.values.first ?? 0
        guard base > 1e-12 else { return nil }

        return (
            ratios: solved.values.map { ($0 / base).squareRoot() },
            movement: solved.vectors,
            points: grid.positions,
            defaultStrike: grid.defaultStrike
        )
    }

    // MARK: - The shape, measured

    /// The shape's interior as cells, numbered row by row.
    struct Grid {
        /// For each cell, its four neighbors, or -1 where the shape ends.
        var neighbors: [Int32]
        var positions: [Vector2]
        var count: Int
        /// The widest a neighbor's number can be from its own, which is what
        /// makes the matrix a band.
        var band: Int
        var defaultStrike: Vector2

        init?(shape: Shape, resolution: Int) {
            var low = Vector2(.infinity, .infinity)
            var high = Vector2(-.infinity, -.infinity)
            for contour in shape.contours {
                for point in contour.points {
                    low = Vector2(min(low.x, point.x), min(low.y, point.y))
                    high = Vector2(max(high.x, point.x), max(high.y, point.y))
                }
            }
            guard low.x.isFinite, high.x > low.x, high.y > low.y else { return nil }

            let across = max(8, min(160, resolution))
            let cell = max(high.x - low.x, high.y - low.y) / Double(across)
            let columns = max(3, Int(((high.x - low.x) / cell).rounded(.up)))
            let rows = max(3, Int(((high.y - low.y) / cell).rounded(.up)))
            guard columns * rows <= 40_000 else { return nil }

            // Cell centers, so the boundary falls between cells rather than on
            // them: a cell is inside or it is not, and the ones that are not
            // are where the shape is pinned.
            var indexOf = [Int32](repeating: -1, count: columns * rows)
            var positions = [Vector2]()
            var next: Int32 = 0
            for row in 0..<rows {
                for column in 0..<columns {
                    let point = Vector2(low.x + (Double(column) + 0.5) * cell,
                                        low.y + (Double(row) + 0.5) * cell)
                    guard shape.contains(point) else { continue }
                    indexOf[row * columns + column] = next
                    positions.append(point)
                    next += 1
                }
            }

            let count = Int(next)
            guard count >= 24 else { return nil }

            var neighbors = [Int32](repeating: -1, count: count * 4)
            var band = 1
            for row in 0..<rows {
                for column in 0..<columns {
                    let here = indexOf[row * columns + column]
                    guard here >= 0 else { continue }
                    let steps = [(-1, 0), (1, 0), (0, -1), (0, 1)]
                    for (slot, step) in steps.enumerated() {
                        let c = column + step.0
                        let r = row + step.1
                        guard c >= 0, c < columns, r >= 0, r < rows else { continue }
                        let other = indexOf[r * columns + c]
                        guard other >= 0 else { continue }
                        neighbors[Int(here) * 4 + slot] = other
                        band = max(band, abs(Int(other) - Int(here)))
                    }
                }
            }

            self.neighbors = neighbors
            self.positions = positions
            self.count = count
            self.band = band
            // Off to one side rather than in the middle, because the middle of
            // a symmetric shape is exactly where half its modes hold still.
            self.defaultStrike = Vector2(low.x + (high.x - low.x) * 0.29,
                                         low.y + (high.y - low.y) * 0.37)
        }

        /// Multiplies by the grid's own Laplacian: four times a cell, less each
        /// of its neighbors. Cells past the edge count as zero, which is the
        /// shape being held still there.
        func apply(_ vector: UnsafePointer<Double>, into result: UnsafeMutablePointer<Double>) {
            neighbors.withUnsafeBufferPointer { table in
                for index in 0..<count {
                    var value = 4 * vector[index]
                    for slot in 0..<4 {
                        let neighbor = table[index * 4 + slot]
                        if neighbor >= 0 { value -= vector[Int(neighbor)] }
                    }
                    result[index] = value
                }
            }
        }
    }

    // MARK: - The smallest eigenvalues

    private static func lowestEigenpairs(
        of grid: Grid, count wanted: Int, subspace: Int
    ) -> (values: [Double], vectors: [[Double]])? {
        let n = grid.count
        guard let factor = BandFactorization(grid: grid) else { return nil }

        // One flat block rather than an array of columns, and every loop below
        // runs over raw pointers. This is arithmetic a sketch waits on while it
        // starts up, and it is run unoptimized as often as not, where bounds
        // checks and array-of-array indirection cost more than the arithmetic.
        var basis = [Double](repeating: 0, count: subspace * n)
        var rotated = [Double](repeating: 0, count: subspace * n)
        var projected = [Double](repeating: 0, count: subspace * subspace)
        var scratch = [Double](repeating: 0, count: n)
        var values = [Double](repeating: 0, count: subspace)
        var previous = [Double](repeating: 0, count: subspace)

        // A deterministic start, so the same shape always gives the same
        // answer, and never the sketch's own randomness.
        var random = CompositionRandom(seed: 0x1D0C)
        for index in basis.indices { basis[index] = random.nextUnit() * 2 - 1 }

        basis.withUnsafeMutableBufferPointer { basisBuffer in
            let x = basisBuffer.baseAddress!
            orthonormalize(x, columns: subspace, rows: n)

            for round in 0..<30 {
                // One step towards the smallest eigenvalues is one solve
                // against the matrix, because the smallest of a matrix are the
                // largest of its inverse and power iteration finds the largest.
                for column in 0..<subspace { factor.solve(x + column * n) }
                orthonormalize(x, columns: subspace, rows: n)

                // Rayleigh-Ritz: the best answer available inside the subspace,
                // got by projecting the problem down to something small enough
                // to solve outright.
                scratch.withUnsafeMutableBufferPointer { work in
                    for column in 0..<subspace {
                        grid.apply(x + column * n, into: work.baseAddress!)
                        for row in 0..<subspace {
                            var sum = 0.0
                            let source = x + row * n
                            for index in 0..<n { sum += source[index] * work[index] }
                            projected[row * subspace + column] = sum
                        }
                    }
                }
                let small = jacobiEigen(&projected, subspace)
                values = small.values

                // Turn the subspace to face the answers it just gave, so the
                // next round starts from a better place and the columns come
                // out in order.
                rotated.withUnsafeMutableBufferPointer { out in
                    let target = out.baseAddress!
                    target.update(repeating: 0, count: subspace * n)
                    for column in 0..<subspace {
                        let destination = target + column * n
                        for source in 0..<subspace {
                            let weight = small.vectors[source * subspace + column]
                            guard weight != 0 else { continue }
                            let from = x + source * n
                            for index in 0..<n { destination[index] += weight * from[index] }
                        }
                    }
                    x.update(from: target, count: subspace * n)
                }

                if round > 2 {
                    var worst = 0.0
                    for index in 0..<min(wanted, subspace) where values[index] > 0 {
                        worst = max(worst, abs(values[index] - previous[index]) / values[index])
                    }
                    // Loose on purpose: measuring the shape onto a grid is
                    // itself worth about a percent, so chasing the last digits
                    // of the solve buys nothing and costs rounds.
                    if worst < 1e-6 { break }
                }
                previous = values
            }
        }

        let take = min(wanted, subspace)
        guard values.first ?? 0 > 1e-12 else { return nil }
        let columns = (0..<take).map { column in
            Array(basis[(column * n)..<((column + 1) * n)])
        }
        return (values: Array(values.prefix(take)), vectors: columns)
    }

    /// Makes the columns unit length and at right angles to each other, twice,
    /// because one pass loses the right angles to rounding when the columns
    /// start out nearly parallel, which is exactly what power iteration does
    /// to them.
    private static func orthonormalize(
        _ basis: UnsafeMutablePointer<Double>, columns: Int, rows: Int
    ) {
        for _ in 0..<2 {
            for column in 0..<columns {
                let here = basis + column * rows
                for earlier in 0..<column {
                    let before = basis + earlier * rows
                    var dot = 0.0
                    for index in 0..<rows { dot += here[index] * before[index] }
                    for index in 0..<rows { here[index] -= dot * before[index] }
                }
                var norm = 0.0
                for index in 0..<rows { norm += here[index] * here[index] }
                norm = norm.squareRoot()
                if norm > 1e-12 {
                    let scale = 1 / norm
                    for index in 0..<rows { here[index] *= scale }
                }
            }
        }
    }

    // MARK: - The banded factorization

    /// The grid's Laplacian, taken apart once so it can be solved against many
    /// times. Only the band is stored, since a cell's neighbors are all within
    /// one grid width of its own number.
    private struct BandFactorization {
        let n: Int
        let band: Int
        /// `values[j * (band + 1) + (i - j)]` is row i, column j of the factor.
        var values: [Double]

        init?(grid: Grid) {
            n = grid.count
            band = min(grid.band, grid.count - 1)
            guard band >= 1 else { return nil }
            values = [Double](repeating: 0, count: n * (band + 1))

            // The matrix itself, written into the band.
            for index in 0..<n {
                values[index * (band + 1)] = 4
                for slot in 0..<4 {
                    let neighbor = Int(grid.neighbors[index * 4 + slot])
                    guard neighbor > index, neighbor - index <= band else { continue }
                    values[index * (band + 1) + (neighbor - index)] = -1
                }
            }

            // Taken apart into a lower factor, in place, one column at a time.
            for column in 0..<n {
                var diagonal = values[column * (band + 1)]
                for earlier in max(0, column - band)..<column {
                    let value = values[earlier * (band + 1) + (column - earlier)]
                    diagonal -= value * value
                }
                guard diagonal > 1e-14 else { return nil }
                let root = diagonal.squareRoot()
                values[column * (band + 1)] = root

                let last = min(column + band, n - 1)
                guard last > column else { continue }
                for row in (column + 1)...last {
                    var sum = values[column * (band + 1) + (row - column)]
                    for earlier in max(0, row - band)..<column {
                        sum -= values[earlier * (band + 1) + (row - earlier)]
                            * values[earlier * (band + 1) + (column - earlier)]
                    }
                    values[column * (band + 1) + (row - column)] = sum / root
                }
            }
        }

        /// Solves the matrix against a vector in place, forwards then backwards.
        func solve(_ x: UnsafeMutablePointer<Double>) {
            let stride = band + 1
            values.withUnsafeBufferPointer { factor in
                let l = factor.baseAddress!
                for row in 0..<n {
                    var sum = x[row]
                    for column in max(0, row - band)..<row {
                        sum -= l[column * stride + (row - column)] * x[column]
                    }
                    x[row] = sum / l[row * stride]
                }
                for row in Swift.stride(from: n - 1, through: 0, by: -1) {
                    var sum = x[row]
                    let last = min(row + band, n - 1)
                    if last > row {
                        for column in (row + 1)...last {
                            sum -= l[row * stride + (column - row)] * x[column]
                        }
                    }
                    x[row] = sum / l[row * stride]
                }
            }
        }
    }

    // MARK: - The small dense problem

    /// Every eigenvalue and eigenvector of a small symmetric matrix, by turning
    /// the largest off-diagonal entry to zero over and over until none is left.
    ///
    /// Slow for anything big and completely dependable for something this size,
    /// which is the trade worth making here: the matrix is the size of the
    /// subspace, a couple of dozen at most.
    ///
    /// Returns the values ascending, with the vectors as columns in the same
    /// order.
    private static func jacobiEigen(
        _ matrix: inout [Double], _ size: Int
    ) -> (values: [Double], vectors: [Double]) {
        var vectors = [Double](repeating: 0, count: size * size)
        for index in 0..<size { vectors[index * size + index] = 1 }

        for _ in 0..<(60 * size) {
            var largest = 0.0
            var p = 0
            var q = 1
            for row in 0..<size {
                for column in (row + 1)..<size where abs(matrix[row * size + column]) > largest {
                    largest = abs(matrix[row * size + column])
                    p = row
                    q = column
                }
            }
            guard largest > 1e-14 else { break }

            let app = matrix[p * size + p]
            let aqq = matrix[q * size + q]
            let apq = matrix[p * size + q]
            let theta = 0.5 * atan2(2 * apq, app - aqq)
            let c = cos(theta)
            let s = sin(theta)

            for k in 0..<size {
                let akp = matrix[k * size + p]
                let akq = matrix[k * size + q]
                matrix[k * size + p] = c * akp + s * akq
                matrix[k * size + q] = -s * akp + c * akq
            }
            for k in 0..<size {
                let apk = matrix[p * size + k]
                let aqk = matrix[q * size + k]
                matrix[p * size + k] = c * apk + s * aqk
                matrix[q * size + k] = -s * apk + c * aqk
            }
            for k in 0..<size {
                let vkp = vectors[k * size + p]
                let vkq = vectors[k * size + q]
                vectors[k * size + p] = c * vkp + s * vkq
                vectors[k * size + q] = -s * vkp + c * vkq
            }
        }

        let order = (0..<size).sorted { matrix[$0 * size + $0] < matrix[$1 * size + $1] }
        var values = [Double](repeating: 0, count: size)
        var sorted = [Double](repeating: 0, count: size * size)
        for (place, source) in order.enumerated() {
            values[place] = matrix[source * size + source]
            for row in 0..<size { sorted[row * size + place] = vectors[row * size + source] }
        }
        return (values: values, vectors: sorted)
    }
}
