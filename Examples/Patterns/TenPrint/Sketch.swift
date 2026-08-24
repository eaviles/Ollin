import Ollin

/// A maze of diagonals: one cell, one coin, one of two lines.
///
/// The rule is the whole program. In every cell of a grid, draw one diagonal or
/// the other by a coin flip. Because the diagonals meet at the cells' corners,
/// what comes out is not a field of loose marks but a tangle of long connected
/// paths, and no two runs of the coin give the same one.
///
/// `runs` is the joining: the same diagonals, walked end to end wherever they
/// meet, so a pen travels a long way before it lifts. Here each run takes its own
/// color, which is the clearest way to see what the joining found. Hold the mouse
/// to see the plain per-cell reading instead, one color for every diagonal, which
/// is what the original printed.
///
/// The colors travel along the ramp over the loop, so the tangle shimmers without
/// the design ever changing. `--export-svg` writes the runs as real polylines.
@main
final class TenPrint_Example: Sketch {
    override var loopDuration: Double? { 12 }

    private var maze: TenPrint?

    override func setup() {
        seed(11)
        maze = tenPrint(in: bounds.inset(by: 60), columns: 34, rows: 34)
    }

    override func draw() {
        background(Color(hex: 0x0B0E14))
        guard let maze else { return }

        strokeWeight(7)
        strokeCap(.round)
        noFill()

        if mouseIsPressed {
            stroke(Color(hex: 0xE8ECF4))
            for line in maze.lines { drawPolyline(line.points) }
            drawCaption("one diagonal per cell, by a coin flip")
            return
        }

        let slide = loopProgress(over: 12)
        let runs = maze.runs
        for (index, run) in runs.enumerated() {
            // The golden ratio steps the hue, so two runs that lie beside each
            // other never get the same color and each one reads as one path.
            let t = (Double(index) * 0.6180339887 + slide).truncatingRemainder(dividingBy: 1)
            stroke(CosinePalette.rainbow.color(at: t))
            drawPolyline(run.points)
        }
        drawCaption("\(runs.count) runs joined from \(maze.lines.count) diagonals; hold the mouse for the plain reading")
    }
}
