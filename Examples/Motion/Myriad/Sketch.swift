import Ollin

/// Thousands of shapes at once: the headline for the SDF drawing path. A
/// 90×90 grid (8,100 circles) where each circle's radius and color ripple
/// from a `noise` field drifting with `time`. Every shape is a single
/// instanced quad whose fill and edge are computed analytically in the
/// shader, so per-shape CPU work is one struct write and the whole field
/// stays smooth.
///
/// The "Rounded rects" knob swaps the circles for a field of rounded rects on
/// the SDF box path. Two more `noise` fields, decorrelated from the first by
/// an offset in the field's third coordinate, drive what a circle does not
/// have: the corner radius sweeps its whole range, so tiles morph from sharp
/// squares to fully rounded pills, and each tile turns by its own angle (a
/// per-instance `rotate`, carried by each quad's own transform).
@main
final class Myriad: Sketch {
    let palette = CosinePalette.neon

    @Param("Rounded rects") var rects = false

    override func setup() {
        noStroke()
    }

    override func draw() {
        background(.black)
        if rects {
            drawRectField()
        } else {
            drawCircleField()
        }
    }

    /// 8,100 circles, radius and color riding one noise field.
    private func drawCircleField() {
        let g = grid(columns: 90, rows: 90)
        for dot in g.points {
            let n = noise(Double(dot.column) * 0.06, Double(dot.row) * 0.06, time * 0.25)
            fill(palette.color(at: n + time * 0.05))
            drawCircle(center: dot.position,
                       radius: map(n, 0, 1, g.cellWidth * 0.05, g.cellWidth * 0.7))
        }
    }

    /// Thousands of rounded rects: size and color from the same kind of
    /// field, corner radius and rotation each from a decorrelated one.
    private func drawRectField() {
        let g = grid(columns: 56, rows: 56)
        let t = time * 0.2
        for dot in g.points {
            let n = noise(Double(dot.column) * 0.08, Double(dot.row) * 0.08, t)
            let size = map(n, 0, 1, g.cellWidth * 0.25, g.cellWidth * 0.95)

            // A second, decorrelated field drives the corner radius across
            // its full range: 0 (sharp square) up to size/2 (a pill/circle).
            let rn = noise(Double(dot.column) * 0.08, Double(dot.row) * 0.08, t + 40)
            let radius = map(rn, 0, 1, 0, size / 2)

            // A third field turns each tile by its own angle.
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
