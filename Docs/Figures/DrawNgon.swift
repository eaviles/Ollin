// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Drawing.md, drawNgon): regular polygons at
// four side counts, one vertex up, with the circumradius indicated once on
// the first: it runs from the dotted center to a vertex.
import Ollin
import OllinDiagram

final class DrawNgon: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var wash: Color { theme.ink(0.10) }
    var accent: Color { theme.accent }

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
