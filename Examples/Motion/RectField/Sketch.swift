import Ollin

/// The rectangle cousin of `Myriad` — thousands of rounded rects at once, the
/// headline for the SDF box path. A grid where each tile's size, corner radius,
/// rotation, and color ripple from a `noise` field drifting with `time`: the
/// corner radius sweeps its whole range, so tiles morph from sharp squares to
/// fully rounded pills. Every rect is one instanced quad whose fill and rounded
/// edge are computed analytically in the shader (and rotated by its own
/// transform), so per-rect CPU work is one struct write.
@main
final class RectField: Sketch {
    let palette = CosinePalette.neon
    let cols = 56
    let rows = 56

    override func setup() {
        noStroke()
    }

    override func draw() {
        background(.black)
        let g = grid(columns: cols, rows: rows)
        let t = time * 0.2
        for dot in g.points {
            let n = noise(Double(dot.column) * 0.08, Double(dot.row) * 0.08, t)
            let size = map(n, 0, 1, g.cellWidth * 0.25, g.cellWidth * 0.95)

            // A second, decorrelated field drives the corner radius across
            // its full range: 0 (sharp square) up to size/2 (a pill/circle).
            let rn = noise(Double(dot.column) * 0.08, Double(dot.row) * 0.08, t + 40)
            let radius = map(rn, 0, 1, 0, size / 2)

            let angle = map(noise(Double(dot.column) * 0.05, Double(dot.row) * 0.05, t + 80),
                            0, 1, -0.5, 0.5)

            fill(palette.color(at: n + time * 0.05))
            withState {
                translate(dot.position)
                rotate(angle)
                drawRect(center: .zero, width: size, height: size, cornerRadius: radius)
            }
        }
    }
}
