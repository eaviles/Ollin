// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Drawing.md, drawLine): straight segments at a
// run of stroke weights and angles, down to a hairline, with the thickest
// line's endpoints dotted where its flat butt ends stop.
import Ollin

final class DrawLine: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        // Three weights, stacked; the top line's endpoints are marked to
        // show the default butt cap stopping exactly at the points.
        stroke(ink)
        strokeWeight(14)
        drawLine(110, 88, 400, 88)
        strokeWeight(5)
        drawLine(110, 152, 400, 168)
        strokeWeight(1.5)
        drawLine(110, 216, 400, 240)

        noStroke()
        fill(accent)
        drawPoint(110, 88, 6)
        drawPoint(400, 88, 6)
        textSize(16)
        textAlign(.left, .middle)
        drawText("butt ends stop at the points", 420, 88)

        fill(ink)
        textAlign(.right, .middle)
        drawText("14", 96, 88)
        drawText("5", 96, 160)
        drawText("1.5", 96, 228)

        // One long sub-pixel hairline: still smooth, fading by ink.
        stroke(ink)
        strokeWeight(0.5)
        drawLine(500, 250, 830, 130)
        noStroke()
        fill(ink)
        textSize(16)
        textAlign(.left, .middle)
        drawText("0.5", 660, 168)

        textSize(18)
        textAlign(.center, .top)
        drawText("any weight, any angle, down to a hairline", 440, 280)
    }
}
