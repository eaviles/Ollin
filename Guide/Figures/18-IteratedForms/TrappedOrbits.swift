// figure: frame=0 themed
//
// Guide figure (Chapter 18): orbit traps. The same Julia set three times: colored
// by escape time, by the orbit's closest pass to a cross held in the plane, and
// by the same cross turned. Only the question asked of the orbit changes.
import Ollin

final class TrappedOrbits: Sketch {
    override var canvasSize: CanvasSize { .size(880, 386) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }

    /// The c all three panels share.
    let pick = Vector2(-0.79, 0.15)

    override func draw() {
        background(paper)

        let tile = 268, gap = 12.0
        let left = (width - Double(tile) * 3 - gap * 2) / 2

        let panels: [(String, Generator)] = [
            ("colored by when the orbit escapes",
             .julia(c: pick, zoom: 1.2, phase: 0.4)),
            ("by its closest pass to a cross",
             .orbitTrap(.cross(.zero), c: pick, zoom: 1.2)),
            ("the same cross, turned",
             .orbitTrap(.cross(.zero), c: pick, zoom: 1.2, angle: 0.6)),
        ]

        textFont(.system)
        for (index, panel) in panels.enumerated() {
            let x = left + Double(index) * (Double(tile) + gap)
            let rect = Rectangle(x: x, y: 20, width: Double(tile), height: Double(tile))
            drawImage(generate(panel.1, width: tile, height: tile).image, in: rect)

            noStroke()
            fill(ink.withAlpha(0.62))
            textSize(16)
            textAlign(.center, .top)
            drawText(panel.0, rect.x + rect.width / 2, rect.y + rect.height + 8)
        }
    }
}
