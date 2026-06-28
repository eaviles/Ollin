import Ollin

/// Ollin's built-in cosine-gradient `CosinePalette` presets — Inigo Quilez's seven
/// example palettes — each swept across the canvas as a band and scrolled over
/// time. Build your own with `CosinePalette(a:b:c:d:)`.
@main
final class Palettes: Sketch {
    let presets: [CosinePalette] = [.rainbow, .dusk, .blush, .meadow, .sunset, .neon, .melon]

    override func setup() {
        noStroke()
    }

    override func draw() {
        background(.black)
        let g = grid(columns: 160, rows: presets.count)
        for cell in g.cells {
            let t = Double(cell.column) / Double(g.columns) + time * 0.1
            fill(presets[cell.row].color(at: t))
            drawRect(cell.frame)
        }
    }
}
