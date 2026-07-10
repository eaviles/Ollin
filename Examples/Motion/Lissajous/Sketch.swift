import Ollin

/// The Lissajous table: a grid where the curve in each cell swings side to
/// side `a` times per lap (its column) while it bobs `b` times (its row). The
/// diagonal holds circles and ellipses; everything off it weaves. One shared
/// phase drifts a full turn per loop, so every figure rolls through its whole
/// family (the diagonal breathes from circle to line and back) and the lap is
/// seamless. A tracer rides each curve at the true parametric speed: fast
/// through the middle, hanging at the turns, which is the sine wave made
/// visible.
@main
final class LissajousTable: Sketch {
    let cells = 4
    let period = 8.0
    override var loopDuration: Double? { period }

    override func draw() {
        background(Color(hex: 0x101318))
        noFill()

        let drift = loopProgress(over: period) * .tau
        let u = loopProgress(over: period) * .tau
        let grid = Grid(in: bounds, columns: cells, rows: cells,
                        padding: .all(70 * scale), gutter: 30 * scale)

        for cell in grid.cells {
            let a = cell.column + 1
            let b = cell.row + 1
            let w = min(cell.frame.width, cell.frame.height) * 0.8
            let hue = Double(a + b - 2) / Double(2 * cells - 1)
            let curve = lissajous(a: a, b: b, phase: drift, width: w)

            withState {
                translate(cell.center.x, cell.center.y)
                stroke(Color(hue: map(hue, 0, 1, 0.5, 0.95),
                             saturation: 0.5, brightness: 0.95, alpha: 0.85))
                strokeWeight(1.6 * scale)
                drawPolyline(curve.points, closed: true)

                // The tracer evaluates the same sines the curve is built
                // from, so it rides at parametric speed.
                let p = Vector2(w / 2 * sin(Double(a) * u + drift),
                                w / 2 * sin(Double(b) * u))
                noStroke()
                fill(.white)
                drawCircle(p.x, p.y, 5 * scale)
                noFill()
            }
        }
    }
}
