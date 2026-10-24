// figure: frame=0 themed
// Guide figure (Chapter 21): the edge glow. A word and a star, each in the
// middle of its layer, given a band of light along their edges with spots of
// color circling them: two colors and three spots a color, then three colors and
// one spot each over a wider band. The spots go round the layer's middle, so
// each shape sits on it.
import Ollin
import OllinDiagram

final class EdgeGlow: Sketch {
    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    override var canvasSize: CanvasSize { .size(880, 430) }

    override func draw() {
        background(theme.paper)
        let tile = 400.0, gap = 20.0
        let left = (width - tile * 2 - gap) / 2
        let labels = ["two colors, three spots each", "three colors, one spot each, a wider band"]
        for index in 0 ..< 2 {
            let x = left + Double(index) * (tile + gap)
            let frame = Rectangle(x: x, y: 10, width: tile, height: 380)
            let marks = makeRenderTarget(width: Int(tile), height: 380)
            withTarget(marks) {
                background(Color(white: 0, alpha: 0))
                noStroke()
                if index == 0 {
                    fill(Color(hex: 0x262C3D))
                    textFont(OutlineFont(name: "AvenirNext-Heavy") ?? .systemBold)
                    textSize(130)
                    textAlign(.center, .center)
                    drawText("edge", tile * 0.5, 190)
                } else {
                    fill(Color(hex: 0x1D2230))
                    drawStar(tile * 0.5, 190, 130, 58, points: 5)
                }
            }
            let glow: Filter = index == 0
                ? .edgeGlow(width: 12, colors: [Color(hex: 0x7B2FF7), Color(hex: 0x00E0FF)], spots: 3, phase: 0.4)
                : .edgeGlow(width: 22, colors: [Color(hex: 0xFF5A8A), Color(hex: 0xFFC94A), Color(hex: 0x4AE0A0)],
                            spots: 1, spotSize: 0.1, bloom: 0.8, phase: 1.1)
            noStroke()
            fill(Color(hex: 0x0B0C10))
            drawRect(frame)
            drawImage(marks.filtered(glow).image, in: frame)
            fill(theme.ink(0.62))
            textFont(.system)
            textSize(16)
            textAlign(.center, .top)
            drawText(labels[index], frame.x + frame.width / 2, frame.y + frame.height + 8)
        }
    }
}
