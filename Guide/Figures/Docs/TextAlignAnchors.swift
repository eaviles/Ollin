// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Text.md, textAlign): every horizontal and
// vertical anchor combination on the same two-line block, the anchor point
// dotted in each, plus the default .baseline on its own strip below.
import Ollin
import OllinDiagram

final class TextAlignAnchors: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.55) }
    var faint: Color { theme.ink(0.22) }
    var accent: Color { theme.accent }

    let columns: [(Double, TextAlignH, String)] = [
        (215, .left, ".left"), (460, .center, ".center"), (705, .right, ".right"),
    ]
    let rows: [(Double, TextAlignV, String)] = [
        (120, .top, ".top"), (235, .middle, ".middle"), (350, .bottom, ".bottom"),
    ]

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        // Headers and row labels.
        noStroke()
        fill(soft)
        textSize(18)
        textAlign(.center, .middle)
        for (cx, _, name) in columns { drawText(name, cx, 42) }
        textAlign(.right, .middle)
        for (cy, _, name) in rows { drawText(name, 100, cy) }

        // The nine combinations, each anchored to its dotted point.
        for (cy, v, _) in rows {
            for (cx, h, _) in columns {
                stroke(faint)
                strokeWeight(1)
                drawLine(cx - 78, cy, cx + 78, cy)
                drawLine(cx, cy - 44, cx, cy + 44)
                noStroke()
                fill(ink)
                textSize(25)
                textAlign(h, v)
                drawText("two\nlines", cx, cy)
                fill(accent)
                drawCircle(cx, cy, 4)
            }
        }

        // The default vertical anchor, .baseline: the first line's baseline
        // sits on the y, so the block hangs from that rule.
        noStroke()
        fill(soft)
        textSize(18)
        textAlign(.right, .middle)
        drawText(".baseline", 100, 480)
        let bx = 215.0, by = 480.0
        stroke(faint)
        strokeWeight(1)
        drawLine(bx - 78, by, bx + 160, by)
        noStroke()
        fill(ink)
        textSize(25)
        textAlign(.left, .baseline)
        drawText("two\nlines", bx, by)
        fill(accent)
        drawCircle(bx, by, 4)
        fill(soft)
        textSize(16)
        textAlign(.left, .middle)
        drawText("the default: the first line's baseline sits on the y", 430, 480)
    }
}
