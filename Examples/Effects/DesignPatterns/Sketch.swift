import Ollin

/// The design-pattern generators: nine animated procedural sources beyond the
/// basic checkers/grid/bars/noise set, each a single `generate` call: glowing
/// filaments, a smoke ring, revolving color panes, a spiral, wavy stripes,
/// orbiting dots, grainy poster gradients, a pulsing border, and god rays.
/// (The tenth, the mesh gradient, has its own example.)
///
/// Every generator takes a `phase` you feed `time` for motion, and each flows
/// into the rest of the effects chain; filter them, blend them, or feed them
/// to a combine like any other layer.
@main
final class DesignPatterns_Example: Sketch {
    private let labelFont = OutlineFont.system

    override func draw() {
        background(Color(white: 0.06))
        let t = time

        let tiles: [(String, RenderTarget)] = [
            ("filaments", generate(.filaments(phase: t))),
            ("smokeRing", generate(.smokeRing(colors: [.white, Color(hex: 0x6FD9FF)],
                                              phase: t))),
            ("colorPanels", generate(.colorPanels(phase: t * 30))),
            ("spiral", generate(.spiral(phase: t * 0.4))),
            ("waves", generate(.waves(shape: 1.2, phase: t * 0.5))),
            ("dotOrbit", generate(.dotOrbit(phase: t))),
            ("grainGradient", generate(.grainGradient(shape: .blob, phase: t))),
            ("pulsingBorder", generate(.pulsingBorder(phase: t))),
            ("godRays", generate(.godRays(phase: t))),
        ]

        let gutter = width * 0.015
        let g = grid(columns: 3, rows: 3, padding: .all(gutter), gutter: gutter)
        for (cell, tile) in zip(g.cells, tiles) {
            let rect = cell.frame
            drawImage(tile.1.image, in: rect)
            withState {
                fill(Color(white: 0, alpha: 0.55)); noStroke()
                drawRect(rect.x, rect.y + rect.height - 32, rect.width, 32)
                fill(.white)
                textFont(labelFont); textSize(18); textAlign(.left, .middle)
                drawText(tile.0, rect.x + 10, rect.y + rect.height - 16)
            }
        }
    }
}
