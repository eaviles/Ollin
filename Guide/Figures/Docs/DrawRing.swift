// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Drawing.md, drawRing): one outer radius three
// times, with the inner radius setting the band: a thin band, a thick band
// around a small hole, and a fine ring. The ring is a filled region, so the
// figure paints it with fill alone.
import Ollin

final class DrawRing: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        panel(cx: 176, inner: 62, label: "innerRadius 62")
        panel(cx: 452, inner: 20, label: "innerRadius 20")
        panel(cx: 728, inner: 86, label: "innerRadius 86")
    }

    func panel(cx: Double, inner: Double, label: String) {
        let cy = 148.0
        noStroke()
        fill(ink)
        drawRing(cx, cy, inner, 94)

        fill(accent)
        drawCircle(cx, cy, 3.5)

        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText(label, cx, 252)
    }
}
