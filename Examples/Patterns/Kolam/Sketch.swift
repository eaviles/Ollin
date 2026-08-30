import Ollin

/// **Kolam and sona**: one line launched between a field of dots at 45 degrees,
/// bouncing off the edges until it comes back to where it began. The count is
/// exact: a field of `rows` by `columns` dots closes into gcd(rows, columns)
/// loops, so 7 by 5 is a single unbroken line and 6 by 4 is two.
///
/// A wall placed between two neighboring dots turns the line there too, and each
/// one either cuts a loop in two or joins two into one. The walls here are held
/// still while the field breathes, so you can watch the count change as the
/// drawing reorganizes.
///
/// Try it: set `columns` and `rows` to two numbers with a common factor and
/// count the loops, or empty `walls` and see the plain field underneath.
@main
final class Kolam_Example: Sketch {
    @Param(3 ... 12, icon: "arrow.left.and.right") var columns = 7.0
    @Param(3 ... 12, icon: "arrow.up.and.down") var rows = 5.0
    @Param(0 ... 4, icon: "scissors") var rounding = 3.0
    @Param(icon: "square.grid.3x3") var showDots = true

    /// Four walls, held still: they are what steers the line.
    let walls: [Kolam.Mirror] = [.rightOf(column: 2, row: 1), .below(column: 3, row: 2),
                                 .rightOf(column: 4, row: 3), .below(column: 1, row: 0)]

    let paper = Color(hex: 0x1A1410)
    let chalk = Color(hex: 0xF3E7D3)

    override func draw() {
        background(paper)

        let field = bounds.inset(by: .all(width * 0.12))
        let design = kolam(in: field, columns: Int(columns), rows: Int(rows),
                           mirrors: walls.filter { $0.column < Int(columns) && $0.row < Int(rows) })

        if showDots {
            noStroke()
            fill(chalk.withAlpha(0.45))
            for dot in design.dots { drawCircle(center: dot, radius: 3.5) }
        }

        noFill()
        strokeCap(.round)
        strokeJoin(.round)
        for (index, loop) in design.loops.enumerated() {
            // Each loop gets its own tone, so the count is readable at a glance.
            let tone = design.loops.count == 1 ? chalk
                : Color.mix(chalk, Color(hex: 0xE0724A),
                            Double(index) / Double(design.loops.count - 1))
            stroke(tone)
            strokeWeight(width * 0.008)
            drawPolyline(loop.smoothed(iterations: Int(rounding)).points, closed: true)
        }

        noStroke()
        fill(chalk.withAlpha(0.7))
        textFont(.system); textSize(width * 0.022); textAlign(.center, .bottom)
        let count = design.loops.count
        drawText("\(Int(columns)) by \(Int(rows)): \(count) \(count == 1 ? "line" : "lines")",
                 width / 2, height - width * 0.045)
    }
}
