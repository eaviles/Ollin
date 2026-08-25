// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Drawing.md, hollow / solid): the same star
// solid and under hollow(16). The fill paints the band, and the active
// stroke borders both of its edges, which a stroke alone could never do.
import Ollin
import OllinDiagram

final class HollowBand: Sketch {
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

        let cy = 146.0
        let outer = 100.0, inner = 50.0

        // Left: the ordinary solid star.
        solid()
        star(cx: 250, cy: cy, outer: outer, inner: inner, name: "solid()")

        // Right: the same star as a 16-point band hugging its outline. The
        // fill paints the band and the stroke runs along both of its edges.
        hollow(16)
        star(cx: 630, cy: cy, outer: outer, inner: inner, name: "hollow(16)")
        solid()

        // Point out the two stroked edges of the band, on the right arm.
        let center = Vector2(630, cy)
        let armDir = Vector2(angle: -0.1 * Double.pi)   // the right arm's vertex
        let outerEdge = center + armDir * (outer + 8)
        let innerEdge = center + armDir * (outer - 8)
        let anchor = Vector2(775, 74)
        stroke(accent)
        strokeWeight(2)
        drawLine(anchor, outerEdge)
        drawLine(anchor, innerEdge)
        noStroke()
        fill(accent)
        textSize(16)
        textAlign(.center, .bottom)
        drawText("both edges stroked", 758, 66)
    }

    func star(cx: Double, cy: Double, outer: Double, inner: Double, name: String) {
        fill(wash)
        stroke(ink)
        strokeWeight(2.5)
        drawStar(cx, cy, outer, inner, points: 5)

        solid()   // the anchor dot is a plain dot even while the star is a band
        noStroke()
        fill(accent)
        drawCircle(cx, cy, 3.5)

        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText(name, cx, cy + outer + 26)
    }
}
