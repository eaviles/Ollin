// figure: frame=0 probe themed
//
// Guide diagram (Chapter 8): the three kinds of font, one word each. An
// outline font fills vector contours (and can stroke them), a bitmap font
// stamps a grid of pixels, and a stroke font draws a single pen line.
import Ollin
import OllinDiagram

final class TypeSpecimen: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.45) }
    var accent: Color { theme.accent }

    override func draw() {
        background(paper)

        // Row 1: the outline font (the default), filled and stroked.
        row(name: "outline", note: "vector contours: crisp at any size, takes fill and stroke", y: 106)
        noStroke()
        fill(ink)
        textSize(88)
        textAlign(.left, .middle)
        drawText("ollin", 80, 106)
        noFill()
        stroke(accent)
        strokeWeight(2)
        drawText("ollin", 320, 106)

        // Row 2: the bitmap font, every lit pixel a square.
        row(name: "bitmap", note: "a grid of pixels, scaled up square by square", y: 274)
        noStroke()
        fill(ink)
        textFont(BitmapFont.builtIn)
        textSize(58)
        drawText("ollin", 80, 268)

        // Row 3: the stroke font, a single pen line with no interior.
        row(name: "stroke", note: "one pen line per glyph: no fill, plotter-friendly", y: 442)
        noFill()
        stroke(ink)
        strokeWeight(3)
        strokeCap(.round)
        strokeJoin(.round)
        textFont(StrokeFont.builtIn)
        textSize(88)
        drawText("ollin", 80, 442)
    }

    func row(name: String, note: String, y: Double) {
        withState {
            textFont(OutlineFont.systemMedium)
            noStroke()
            textAlign(.left, .middle)
            fill(accent)
            textSize(21)
            drawText(name, 80, y - 72)
            fill(faint)
            textSize(17)
            drawText(note, 80, y + 62)
        }
    }
}
