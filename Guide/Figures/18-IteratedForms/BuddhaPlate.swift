// figure: frame=0 themed
//
// Guide figure (Chapter 18): the Buddhabrot two ways. The same seeded plate
// developed in grayscale from one iteration cap, and in false color from
// three caps, so color reads as orbit depth.
import Ollin

final class BuddhaPlate: Sketch {
    override var canvasSize: CanvasSize { .size(880, 466) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    private var gray: Image?
    private var color: Image?

    override func setup() {
        let grayRenderer = Buddhabrot.Renderer(Buddhabrot(iterations: [1000]),
                                               width: 400, height: 400, seed: 7)
        grayRenderer.accumulate(samples: 600_000)
        gray = grayRenderer.image()

        let colorRenderer = Buddhabrot.Renderer(Buddhabrot(),
                                                width: 400, height: 400, seed: 7)
        colorRenderer.accumulate(samples: 600_000)
        color = colorRenderer.image()
    }

    override func draw() {
        background(paper)

        let tile = 400.0, gap = 26.0
        let left = (width - tile * 2 - gap) / 2
        let panels: [(String, Image?)] = [
            ("one cap, counts as gray", gray),
            ("three caps exposed as red, green, blue", color),
        ]

        textFont(.system)
        for (index, panel) in panels.enumerated() {
            let x = left + Double(index) * (tile + gap)
            let rect = Rectangle(x: x, y: 20, width: tile, height: tile)
            if let image = panel.1 { drawImage(image, in: rect) }
            noStroke()
            fill(ink.withAlpha(0.62))
            textSize(16)
            textAlign(.center, .top)
            drawText(panel.0, rect.x + rect.width / 2, rect.y + rect.height + 8)
        }
    }
}
