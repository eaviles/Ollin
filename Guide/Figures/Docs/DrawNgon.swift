// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Drawing.md, drawNgon): regular polygons at
// four side counts, one vertex up, with the circumradius indicated once on
// the first: it runs from the dotted center to a vertex.
import Ollin

final class DrawNgon: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var wash: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.10) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        let cy = 148.0
        let radius = 82.0

        panel(cx: 130, cy: cy, radius: radius, sides: 5)
        panel(cx: 352, cy: cy, radius: radius, sides: 6)
        panel(cx: 574, cy: cy, radius: radius, sides: 8)
        panel(cx: 796, cy: cy, radius: radius, sides: 12)

        // The circumradius, once: center to the top vertex.
        stroke(accent)
        strokeWeight(2)
        drawLine(130, cy, 130, cy - radius)
        noStroke()
        fill(accent)
        textSize(16)
        textAlign(.left, .middle)
        drawText("radius", 138, cy - radius / 2)
    }

    func panel(cx: Double, cy: Double, radius: Double, sides: Int) {
        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawNgon(cx, cy, radius, sides: sides)

        noStroke()
        fill(accent)
        drawCircle(cx, cy, 3.5)

        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText("sides: \(sides)", cx, cy + radius + 26)
    }
}
