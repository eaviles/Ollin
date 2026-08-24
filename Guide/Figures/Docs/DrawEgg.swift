// figure: frame=0
//
// Docs catalog figure (Drawing/Drawing.md, drawEgg): the egg at three radius
// pairs, from the classic taper to the equal-radii circle, each centered on
// its marked anchor.
import Ollin

final class DrawEgg: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let wash = Color(hex: 0x2B2B2B, alpha: 0.10)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        panel(cx: 176, bottom: 72, top: 38, name: "bottom 72, top 38")
        panel(cx: 452, bottom: 72, top: 16, name: "a narrower tip")
        panel(cx: 722, bottom: 55, top: 55, name: "equal radii: a circle")
    }

    func panel(cx: Double, bottom: Double, top: Double, name: String) {
        let cy = 148.0
        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawEgg(cx, cy, bottom, top)

        noStroke()
        fill(accent)
        drawCircle(cx, cy, 3.5)

        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText(name, cx, 262)
    }
}
