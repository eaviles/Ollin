import Ollin

/// A rose garden: the classic chart of `r = cos(k * theta)` curves, one per
/// cell of a `Grid`. Columns raise `n`, rows raise `d`, so `k = n / d` walks
/// through whole and fractional frequencies: odd `n` gives `n` petals, even
/// `n` doubles to `2n`, and the fractional rows weave the petals into open
/// stars. Each rose spins by exactly one petal per lap (its own symmetry
/// step), so the whole chart loops seamlessly. Pure line work on paper: the
/// same contours plot straight to SVG.
@main
final class Roses: Sketch {
    let columns = 5
    let rows = 4
    let period = 10.0
    override var loopDuration: Double? { period }

    override func draw() {
        background(Color(hex: 0xF5F0E6))
        noFill()
        strokeWeight(1.8 * scale)

        let ink = Color(hex: 0x2B2118)
        let accent = Color(hex: 0xA33B20)
        let grid = Grid(in: bounds, columns: columns, rows: rows,
                        padding: .all(70 * scale))

        for cell in grid.cells {
            let n = cell.column + 1
            let d = cell.row + 1
            let radius = min(cell.frame.width, cell.frame.height) * 0.42
            // Reduced fractions repeat an earlier cell's curve; ink those in
            // the accent so the chart shows which are new.
            let isReduced = greatestCommonDivisor(n, d) > 1
            stroke(isReduced ? accent.withAlpha(0.45) : ink)

            withState {
                translate(cell.center.x, cell.center.y)
                rotate(loopProgress(over: period) * .tau / Double(petals(n: n, d: d)))
                drawPolyline(rose(n: n, d: d, radius: radius).points, closed: true)
            }
        }
    }

    /// The petal count after reducing `n / d`: `n` when both are odd,
    /// `2n` otherwise. The rotation steps by one petal so each lap maps the
    /// rose onto itself.
    private func petals(n: Int, d: Int) -> Int {
        let g = greatestCommonDivisor(n, d)
        let rn = n / g
        let rd = d / g
        return (rn * rd) % 2 == 1 ? rn : 2 * rn
    }

    private func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        var a = a
        var b = b
        while b != 0 { (a, b) = (b, a % b) }
        return max(1, a)
    }
}
