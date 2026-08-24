// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Drawing.md, drawParallelogram): the skew
// shears the top edge along +x: leaning right at a positive skew, a
// rectangle at zero, leaning left at a negative one.
import Ollin

final class DrawParallelogram: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var wash: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.10) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        panel(cx: 176, skew: 56, label: "skew 56")
        panel(cx: 452, skew: 0, label: "skew 0, a rectangle")
        panel(cx: 728, skew: -56, label: "skew -56")
    }

    func panel(cx: Double, skew: Double, label: String) {
        let cy = 148.0
        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawParallelogram(cx, cy, 170, 120, skew)

        noStroke()
        fill(accent)
        drawCircle(cx, cy, 3.5)

        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText(label, cx, 252)
    }
}
