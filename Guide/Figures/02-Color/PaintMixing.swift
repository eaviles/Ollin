// figure: frame=0 themed
//
// Guide diagram: the same blue and yellow, mixed as numbers, as perception,
// and as paint. RGB lands in mud, OKLab is even but still neutral at the
// middle, and .paint meets in the green a real palette would give.
import Ollin
import OllinDiagram

final class PaintMixing: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let blue = Color(hex: 0x2050C8)
    let yellow = Color(hex: 0xFFC800)
    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var label: Color { theme.ink(0.55) }

    override func draw() {
        background(paper)
        noStroke()
        textSize(21)

        let spaces: [(ColorSpace, String)] = [
            (.rgb, "mixed in .rgb"),
            (.oklab, "mixed in .oklab"),
            (.paint, "mixed in .paint"),
        ]
        let steps = 11
        for (row, space) in spaces.enumerated() {
            let y = 105.0 + Double(row) * 130
            for i in 0..<steps {
                let t = Double(i) / Double(steps - 1)
                fill(Color.mix(blue, yellow, t: t, in: space.0))
                drawRect(70 + Double(i) * 68, y, 62, 74)
            }
            fill(label)
            textAlign(.left, .middle)
            drawText(space.1, 70, y - 24)
        }
    }
}
