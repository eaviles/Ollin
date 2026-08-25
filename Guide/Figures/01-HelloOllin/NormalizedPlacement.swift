// figure: frame=0 probe themed
//
// Guide diagram (Chapter 1): why fractions beat pixels for layout. The same
// three marks placed by fixed pixel coordinates and then by 0…1 fractions,
// each drawn into a square, a wide, and a tall canvas. Only the fractions
// survive the change of shape.
import Ollin
import OllinDiagram

final class NormalizedPlacement: Sketch {
    override var canvasSize: CanvasSize { .size(880, 600) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.45) }

    // The panels depict a sketch's own artwork, identical in both themes.
    let night = Color(hex: 0x1B2A4A)
    let accent = Color(hex: 0xE4572E)
    let sand = Color(hex: 0xF2CC8F)

    override func draw() {
        background(paper)

        let shapes = [(w: 170.0, h: 170.0), (w: 220.0, h: 124.0), (w: 116.0, h: 190.0)]
        let columns = [155.0, 440.0, 715.0]

        for (row, byFraction) in [false, true].enumerated() {
            let midY = 152.0 + Double(row) * 258
            for (i, shape) in shapes.enumerated() {
                let r = Rectangle(x: columns[i] - shape.w / 2, y: midY - shape.h / 2,
                                  width: shape.w, height: shape.h)
                withClip(r) {
                    noStroke()
                    fill(night)
                    drawRect(r)
                    marks(in: r, byFraction: byFraction)
                }
                noFill()
                stroke(soft)
                strokeWeight(1.5)
                drawRect(r)
            }
            noStroke()
            fill(ink)
            textSize(17)
            textAlign(.left, .middle)
            drawText(byFraction ? "placed by fractions: uv(0.5, 0.42)"
                                : "placed by pixels: drawCircle(85, 71, 34)",
                     40, midY - 124)
        }

        noStroke()
        fill(soft)
        textSize(15)
        textAlign(.center, .top)
        drawText("one layout, three canvas shapes", width / 2, 548)
    }

    func marks(in r: Rectangle, byFraction: Bool) {
        if byFraction {
            fill(accent)
            drawCircle(center: r.point(u: 0.5, v: 0.42), radius: r.width * 0.2)
            fill(sand)
            drawCircle(center: r.point(u: 0.72, v: 0.72), radius: r.width * 0.1)
            fill(.white)
            drawCircle(center: r.point(u: 0.22, v: 0.78), radius: r.width * 0.06)
        } else {
            // Fixed offsets from the top-left corner, as a beginner would write
            // them against one canvas size.
            fill(accent)
            drawCircle(r.x + 85, r.y + 71, 34)
            fill(sand)
            drawCircle(r.x + 122, r.y + 122, 17)
            fill(.white)
            drawCircle(r.x + 37, r.y + 133, 10)
        }
    }
}
