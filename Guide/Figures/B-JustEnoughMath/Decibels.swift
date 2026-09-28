// figure: frame=0 themed
//
// Guide diagram (Appendix B): decibels. Nine rows from 0 dB, full scale, down
// to -48 dB in steps of 6. Each row's bar is the level as a fraction of full
// scale, 10 to the power of dB over 20, printed at its end: every step of
// 6 decibels roughly halves the bar. The row at -12 dB is marked, the level
// a mix usually sits under.
import Ollin
import OllinDiagram

final class Decibels: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    override func draw() {
        background(theme.paper)

        let left = 190.0
        let full = 560.0
        let top = 70.0
        let rowHeight = 42.0

        noStroke()
        fill(theme.muted)
        textSize(14)
        textAlign(.right, .bottom)
        drawText("decibels", left - 24, top - 12)
        textAlign(.left, .bottom)
        drawText("level, as a fraction of full scale", left, top - 12)

        for row in 0...8 {
            let db = -6.0 * Double(row)
            let level = pow(10, db / 20)
            let y = top + Double(row) * rowHeight
            let marked = row == 2

            fill(marked ? theme.accent : theme.ink(0.8))
            drawRect(left, y + 6, full * level, rowHeight - 14)

            fill(marked ? theme.accent : theme.ink)
            textSize(16)
            textAlign(.right, .middle)
            drawText(row == 0 ? "0 dB" : "−\(Int(-db)) dB", left - 24, y + rowHeight / 2)
            textAlign(.left, .middle)
            fill(theme.muted)
            textSize(14)
            drawText("\((level * 1000).rounded() / 1000)", left + full * level + 10, y + rowHeight / 2)
            if marked {
                fill(theme.accent)
                drawText("a mix usually sits below this", left + full * level + 80, y + rowHeight / 2)
            }
        }

        diagramCaption("each step of 6 decibels down halves the level, near enough", at: 488, theme: theme)
    }
}
