import Ollin

/// Ollin's built-in cosine-gradient `Palette` presets — Inigo Quilez's seven
/// example palettes — each swept across the canvas as a band and scrolled over
/// time. Build your own with `Palette(a:b:c:d:)`.
@main
final class Palettes: Sketch {
    let presets: [Palette] = [.rainbow, .dusk, .blush, .meadow, .sunset, .neon, .melon]

    override func setup() {
        noStroke()
    }

    override func draw() {
        background(.black)
        let bandHeight = height / Double(presets.count)
        let columns = 160
        let columnWidth = width / Double(columns)
        for (row, palette) in presets.enumerated() {
            for i in 0..<columns {
                let t = Double(i) / Double(columns) + time * 0.1
                fill(palette.color(at: t))
                drawRect(Double(i) * columnWidth, Double(row) * bandHeight,
                     columnWidth + 1, bandHeight)
            }
        }
    }
}
