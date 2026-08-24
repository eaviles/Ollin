// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Drawing.md, drawBlobbyCross): the concave
// four-armed cross across the blobbiness range, bulbous to spiky, with the
// tip-to-center radius marked on the first.
import Ollin

final class DrawBlobbyCross: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var wash: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.10) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        let cy = 140.0
        let radius = 96.0

        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawBlobbyCross(176, cy, radius, blobbiness: 0.8)
        drawBlobbyCross(452, cy, radius, blobbiness: 0.5)
        drawBlobbyCross(722, cy, radius, blobbiness: 0.2)

        // The tips reach radius along each axis.
        stroke(accent)
        strokeWeight(2)
        drawLine(176, cy, 176, cy - radius)

        noStroke()
        fill(accent)
        drawCircle(176, cy, 3.5)
        drawCircle(452, cy, 3.5)
        drawCircle(722, cy, 3.5)
        textSize(16)
        textAlign(.left, .middle)
        drawText("radius", 184, cy - radius / 2)

        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText("blobbiness 0.8", 176, 262)
        drawText("0.5, the default", 452, 262)
        drawText("0.2", 722, 262)
    }
}
