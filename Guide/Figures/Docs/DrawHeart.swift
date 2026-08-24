// figure: frame=0
//
// Docs catalog figure (Drawing/Drawing.md, drawHeart): the heart as drawn,
// then turned with the transform stack: a half turn points it up, a quarter
// turn tips it like a playing-card suit.
import Ollin

final class DrawHeart: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let wash = Color(hex: 0x2B2B2B, alpha: 0.10)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        panel(cx: 176, angle: 0, name: "lobes up, point down")
        panel(cx: 452, angle: .pi, name: "rotate(.pi)")
        panel(cx: 722, angle: .pi / 4, name: "rotate(.pi / 4)")
    }

    func panel(cx: Double, angle: Double, name: String) {
        let cy = 148.0
        fill(wash)
        stroke(ink)
        strokeWeight(3)
        withState {
            translate(cx, cy)
            rotate(angle)
            drawHeart(0, 0, 170)
        }

        noStroke()
        fill(accent)
        drawCircle(cx, cy, 3.5)

        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText(name, cx, 262)
    }
}
