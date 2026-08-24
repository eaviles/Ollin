// figure: frame=0
//
// Docs catalog figure (Drawing/Drawing.md, drawCoolS): the notebook doodle
// as its filled silhouette, and with a stroke tracing its outline.
import Ollin

final class DrawCoolS: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let wash = Color(hex: 0x2B2B2B, alpha: 0.10)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        let cy = 132.0

        fill(ink)
        noStroke()
        drawCoolS(300, cy, 196)

        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawCoolS(580, cy, 196)

        noStroke()
        fill(accent)
        drawCircle(300, cy, 3.5)
        drawCircle(580, cy, 3.5)

        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText("filled", 300, 262)
        drawText("with a stroke", 580, 262)
    }
}
