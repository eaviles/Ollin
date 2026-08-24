// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Drawing.md, drawRect): the two anchors side
// by side, the top-left corner form and the center form, each with its
// anchor dotted, and a third rectangle with rounded corners.
import Ollin

final class DrawRect: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var wash: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.10) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawRect(62, 92, 210, 122)
        drawRect(center: Vector2(452, 153), width: 210, height: 122)
        drawRect(636, 92, 200, 122, cornerRadius: 26)

        // The anchors: (x, y) is the top-left in the corner form, the
        // middle in the center form.
        noStroke()
        fill(accent)
        drawCircle(62, 92, 3.5)
        drawCircle(center: Vector2(452, 153), radius: 3.5)
        textSize(16)
        textAlign(.left, .middle)
        drawText("(x, y)", 74, 84)
        drawText("(x, y)", 464, 145)

        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText("corner anchor", 167, 272)
        drawText("center anchor", 452, 272)
        drawText("cornerRadius: 26", 736, 272)
    }
}
