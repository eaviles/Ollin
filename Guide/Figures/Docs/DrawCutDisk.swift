// figure: frame=0
//
// Docs catalog figure (Drawing/Drawing.md, drawCutDisk): the same disk under
// three cut offsets: zero is the half disk, positive raises the flat edge and
// keeps a smaller cap, negative keeps more than half.
import Ollin

final class DrawCutDisk: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let wash = Color(hex: 0x2B2B2B, alpha: 0.10)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        panel(cx: 176, cut: 0, name: "cut: 0, a half disk")
        panel(cx: 452, cut: 42, name: "cut: 42, a smaller cap")
        panel(cx: 722, cut: -42, name: "cut: -42, more than half")
    }

    func panel(cx: Double, cut: Double, name: String) {
        let cy = 148.0
        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawCutDisk(cx, cy, 84, cut)

        noStroke()
        fill(accent)
        drawCircle(cx, cy, 3.5)

        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText(name, cx, 262)
    }
}
