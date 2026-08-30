// figure: frame=0 themed
//
// Guide figure (Chapter 16): one page under a light that falls across it, cut two ways.
// The same picture, one number for the whole page against each pixel's own neighborhood.
import Ollin
import OllinDiagram

final class LocalAverages: Sketch {
    override var canvasSize: CanvasSize { .size(880, 386) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var labelInk: Color { theme.ink(0.62) }

    override func draw() {
        background(paper)

        let tile = 268.0, gap = 12.0
        let left = (width - tile * 3 - gap * 2) / 2
        let labels = ["the page, lit from one side", "one number for all of it",
                      "each pixel against its own patch"]

        textFont(.system)
        for index in 0 ..< 3 {
            let x = left + Double(index) * (tile + gap)
            let frame = Rectangle(x: x, y: 20, width: tile, height: tile)

            let page = makeRenderTarget(width: Int(tile), height: Int(tile))
            withTarget(page) { paint(tile) }

            switch index {
            case 0:
                drawImage(page.image, in: frame)
            case 1:
                drawImage(page.filtered(.threshold(0.3)).image, in: frame)
            default:
                drawImage(page.filtered(.adaptiveThreshold(window: 90)).image, in: frame)
            }

            fill(labelInk)
            textSize(16)
            textAlign(.center, .top)
            drawText(labels[index], frame.x + frame.width / 2, frame.y + frame.height + 8)
        }
    }

    /// A page of marks, then a light multiplied over them so one corner sits in shadow.
    private func paint(_ side: Double) {
        background(Color(hex: 0xF3EDE2))
        noStroke()
        fill(Color(hex: 0x1B2028))
        for row in 0 ..< 6 {
            let y = side * (0.12 + Double(row) * 0.085)
            drawRect(corner: Vector2(side * 0.1, y),
                     width: side * (row == 5 ? 0.44 : 0.76), height: 9)
        }
        for i in 0 ..< 4 {
            drawCircle(side * (0.18 + Double(i) * 0.2), side * 0.82, Double(9 + i * 4))
        }
        stroke(Color(hex: 0x1B2028))
        strokeWeight(5)
        drawLine(side * 0.1, side * 0.68, side * 0.9, side * 0.68)
        noStroke()

        blendMode(.multiply)
        fill(Gradient.linear(from: Vector2(side * 0.1, 0), to: Vector2(side * 1.22, side * 1.22),
                             Ramp([Color(white: 1), Color(white: 0.2)])))
        drawRect(0, 0, side, side)
        blendMode(.normal)
    }
}
