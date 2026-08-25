// figure: frame=0 themed
//
// Guide diagram (Chapter 8): text as geometry, warped in steps. The same word
// comes back from textToShapes three times: untouched, nudged by a small
// smooth field, then pushed hard enough to read as liquid.
import Ollin
import OllinDiagram

final class TextWarp: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.45) }
    var accent: Color { theme.accent }

    override func setup() {
        noiseSeed(7)
    }

    override func draw() {
        background(paper)
        textSize(150)
        textAlign(.center, .middle)

        drawWarped(amount: 0, y: 95, label: "textToShapes: the glyphs back as shapes")
        drawWarped(amount: 7, y: 262, label: "every outline point nudged by signedNoise × 7")
        drawWarped(amount: 26, y: 429, label: "the same field × 26")
    }

    func drawWarped(amount: Double, y: Double, label: String) {
        noStroke()
        fill(amount == 0 ? ink : accent)
        for shape in textToShapes("warp", width / 2, y) {
            let warped = Shape(contours: shape.contours.map { c in
                Contour(c.points.map { p in
                    p + Vector2(signedNoise(p.x * 0.006, p.y * 0.006),
                                signedNoise(p.x * 0.006 + 40, p.y * 0.006)) * amount
                }, closed: c.isClosed)
            })
            drawShape(warped)
        }

        withState {
            noStroke()
            fill(faint)
            textAlign(.center, .middle)
            textSize(17)
            drawText(label, width / 2, y + 92)
        }
    }
}
