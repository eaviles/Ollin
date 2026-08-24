// figure: frame=0
//
// Docs catalog figure (Drawing/Drawing.md, drawMoon): three crescents from
// one marked center: the classic slim crescent, a larger offset opening it
// toward a half-moon, and cornerRadius rounding the two cusps.
import Ollin

final class DrawMoon: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let wash = Color(hex: 0x2B2B2B, alpha: 0.10)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        panel(cx: 176, inner: 74, offset: 52, corner: 0, label: "a crescent")
        panel(cx: 452, inner: 60, offset: 74, corner: 0, label: "a larger offset opens it")
        panel(cx: 728, inner: 74, offset: 52, corner: 10, label: "cornerRadius 10")
    }

    func panel(cx: Double, inner: Double, offset: Double, corner: Double,
               label: String) {
        let cy = 148.0
        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawMoon(cx, cy, 84, inner, offset, cornerRadius: corner)

        noStroke()
        fill(accent)
        drawCircle(cx, cy, 3.5)

        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText(label, cx, 252)
    }
}
