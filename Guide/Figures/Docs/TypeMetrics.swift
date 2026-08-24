// figure: frame=0
//
// Docs diagram (Drawing/Text.md): the type metrics, measured from the
// baseline. A large sample line with the ascender line, baseline, and
// descender line ruled through it, textAscent and textDescent bracketed at
// the right, and a ghosted second line one textLeading below. The rules sit
// at the measured values, so the figure is honest by construction.
import Ollin

final class TypeMetrics: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.28)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)
        textSize(96)

        let baseline = 210.0
        let ascent = textAscent()
        let descent = textDescent()
        let leading = textLeading()
        let left = 84.0, right = 560.0

        // The ruled lines, at the measured heights.
        stroke(faint)
        strokeWeight(2)
        drawLine(left, baseline - ascent, right, baseline - ascent)
        drawLine(left, baseline + descent, right, baseline + descent)
        stroke(accent)
        drawLine(left, baseline, right, baseline)
        stroke(faint)
        drawLine(left, baseline + leading, right, baseline + leading)

        // The sample, tall tops and low descenders, on the accent baseline.
        noStroke()
        fill(ink)
        textAlign(.left, .baseline)
        drawText("Abkd gpy", left + 12, baseline)
        fill(Color(hex: 0x2B2B2B, alpha: 0.22))
        drawText("next line", left + 12, baseline + leading)

        // Line names.
        textSize(19)
        textAlign(.left, .middle)
        fill(ink)
        drawText("ascender line", right + 14, baseline - ascent)
        fill(accent)
        drawText("baseline: drawText's y", right + 14, baseline)
        fill(ink)
        drawText("descender line", right + 14, baseline + descent)

        // The three measures, bracketed clear of the line names.
        bracket(x: 820, from: baseline - ascent, to: baseline,
                name: "textAscent()", nameY: baseline - ascent / 2, side: -1)
        bracket(x: 820, from: baseline, to: baseline + descent,
                name: "textDescent()", nameY: baseline + descent + 24, side: -1)
        bracket(x: 44, from: baseline, to: baseline + leading,
                name: "textLeading()", nameY: baseline + leading / 2)

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("every measure starts at the baseline, for every font kind",
                 width / 2, 420)
    }

    func bracket(x: Double, from: Double, to: Double, name: String, nameY: Double,
                 side: Double = 1) {
        stroke(ink)
        strokeWeight(2)
        drawLine(x, from, x, to)
        drawLine(x - 7, from, x + 7, from)
        drawLine(x - 7, to, x + 7, to)
        noStroke()
        fill(ink)
        textSize(19)
        textAlign(side > 0 ? .left : .right, .middle)
        drawText(name, x + side * 14, nameY)
    }
}
