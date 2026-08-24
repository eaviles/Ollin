// figure: frame=0
//
// Docs catalog figure (Drawing/Drawing.md, drawHorseshoe): the band at three
// gaps, from nearly a closed ring to a wide opening; the gap is the full
// angular span of the missing piece.
import Ollin

final class DrawHorseshoe: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let wash = Color(hex: 0x2B2B2B, alpha: 0.10)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        panel(cx: 176, gap: 0.6, name: "gap: 0.6, nearly a ring")
        panel(cx: 452, gap: 1.4, name: "gap: 1.4, the classic")
        panel(cx: 722, gap: 2.6, name: "gap: 2.6, wide open")
    }

    func panel(cx: Double, gap: Double, name: String) {
        let cy = 148.0
        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawHorseshoe(cx, cy, 62, 30, gap: gap)

        noStroke()
        fill(accent)
        drawCircle(cx, cy, 3.5)

        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText(name, cx, 262)
    }
}
