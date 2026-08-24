// figure: frame=0
//
// Docs catalog figure (Drawing/Drawing.md, drawRoundedX): the round-capped
// saltire at two arm thicknesses, and turned with the transform stack.
import Ollin

final class DrawRoundedX: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let wash = Color(hex: 0x2B2B2B, alpha: 0.10)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        let cy = 140.0

        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawRoundedX(176, cy, 180, 48)
        drawRoundedX(452, cy, 180, 18)
        withState {
            translate(722, cy)
            rotate(0.4)
            drawRoundedX(0, 0, 180, 48)
        }

        noStroke()
        fill(accent)
        drawCircle(176, cy, 3.5)
        drawCircle(452, cy, 3.5)
        drawCircle(722, cy, 3.5)

        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText("thickness 48", 176, 262)
        drawText("thickness 18", 452, 262)
        drawText("turned with rotate", 722, 262)
    }
}
