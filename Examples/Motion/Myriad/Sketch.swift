import Ollin

/// Thousands of circles at once — the headline for the SDF drawing path. A
/// 90×90 grid (8,100 circles) where each circle's radius and color ripple from a
/// `noise` field drifting with `time`. Every circle is a single instanced quad
/// whose fill and edge are computed analytically in the shader, so per-circle CPU
/// work is one struct write and the whole field stays smooth.
@main
final class Myriad: Sketch {
    let palette = CosinePalette.neon
    let cols = 90
    let rows = 90

    override func setup() {
        noStroke()
    }

    override func draw() {
        background(.black)
        let cell = width / Double(cols)
        for j in 0..<rows {
            for i in 0..<cols {
                let x = (Double(i) + 0.5) * cell
                let y = (Double(j) + 0.5) * cell
                let n = noise(Double(i) * 0.06, Double(j) * 0.06, time * 0.25)
                fill(palette.color(at: n + time * 0.05))
                drawCircle(x, y, map(n, 0, 1, cell * 0.05, cell * 0.7))
            }
        }
    }
}
