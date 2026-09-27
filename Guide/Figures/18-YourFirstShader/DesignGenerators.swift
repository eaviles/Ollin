// figure: frame=0
//
// Guide figure (Chapter 18): the design generators as they come. One labeled
// tile each, every one generate(_:) with nothing set but a fixed phase, so
// the sheet shows the family's defaults. Each layer is generated at its
// tile's own size, which keeps the centered compositions centered.
import Ollin

final class DesignGenerators: Sketch {
    override var canvasSize: CanvasSize { .size(1500, 640) }

    override func draw() {
        background(Color(hex: 0x0C0E13))

        let tiles: [(String, Generator)] = [
            ("meshGradient", .meshGradient(phase: 2)),
            ("filaments", .filaments(phase: 2)),
            ("smokeRing", .smokeRing(phase: 2)),
            ("colorPanels", .colorPanels(phase: 2)),
            ("spiral", .spiral(phase: 2)),
            ("waves", .waves(phase: 2)),
            ("dotOrbit", .dotOrbit(phase: 2)),
            ("grainGradient", .grainGradient(phase: 2)),
            ("pulsingBorder", .pulsingBorder(phase: 2)),
            ("godRays", .godRays(phase: 2)),
        ]

        drawSheet(tiles, columns: 5) { generator, cell in
            let layer = generate(generator, width: Int(cell.width), height: Int(cell.height))
            drawImage(layer.image, in: cell)
        }
    }
}
