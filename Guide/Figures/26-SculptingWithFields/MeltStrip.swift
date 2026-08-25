// figure: frame=0 themed
//
// Guide figure (Chapter 26): the melt knob. The same two circles at four
// smoothing radii: k = 0 is a hard union, and each larger k widens the blend
// until the pair reads as one body, colors fusing across the seam.
import Ollin

final class MeltStrip: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }

    override func draw() {
        background(paper)
        noStroke()

        let coral = Color(hex: 0xE4572E)
        let blue = Color(hex: 0x3A6EA5)
        let ks: [Double] = [0, 22, 55, 110]

        for (i, k) in ks.enumerated() {
            let cx = 120.0 + Double(i) * 215
            let cy = 255.0
            let pair = SDF.circle(radius: 62).colored(coral).at(x: -46, y: -26)
                .smoothUnion(SDF.circle(radius: 54).colored(blue).at(x: 40, y: 34), k: k)
            withState {
                translate(cx, cy)
                drawSDF(pair)
            }
            fill(ink)
            textSize(24)
            textAlign(.center, .middle)
            drawText(k == 0 ? "k = 0 (hard)" : "k = \(Int(k))", cx, cy + 160)
        }
    }
}
