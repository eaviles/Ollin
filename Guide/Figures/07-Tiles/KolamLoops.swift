// figure: frame=0 themed
//
// Guide figure (Chapter 7): kolam and sona. The same walk over three fields.
// Seven by five closes into one unbroken line; six by four closes into two, one
// per shade; and two walls dropped into the seven by five field cut its single
// line into three.
import Ollin
import OllinDiagram

final class KolamLoops: Sketch {
    override var canvasSize: CanvasSize { .size(880, 386) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var canvasPaper: Color { theme.paper }
    let paper = Color(hex: 0x1A1410)
    let chalk = Color(hex: 0xF3E7D3)
    let warm = Color(hex: 0xE0724A)

    override func draw() {
        background(canvasPaper)

        let tile = 268.0, gap = 12.0
        let left = (width - tile * 3 - gap * 2) / 2
        let walls: [Kolam.Mirror] = [.rightOf(column: 2, row: 1), .below(column: 4, row: 2)]

        let panels: [(String, Int, Int, [Kolam.Mirror])] = [
            ("7 by 5 dots: one line", 7, 5, []),
            ("6 by 4 dots: two loops", 6, 4, []),
            ("7 by 5, with two walls", 7, 5, walls),
        ]

        textFont(.system)
        for (index, panel) in panels.enumerated() {
            let x = left + Double(index) * (tile + gap)
            let frame = Rectangle(x: x, y: 20, width: tile, height: tile)

            noStroke()
            fill(paper)
            drawRect(frame)

            let design = kolam(in: frame.inset(by: 30), columns: panel.1, rows: panel.2,
                               mirrors: panel.3)

            fill(chalk.withAlpha(0.4))
            for dot in design.dots { drawCircle(center: dot, radius: 3) }

            noFill()
            strokeJoin(.round)
            strokeCap(.round)
            strokeWeight(4)
            for (loop, contour) in design.loops.enumerated() {
                let spread = Double(design.loops.count - 1)
                stroke(spread == 0 ? chalk : Color.mix(chalk, warm, t: Double(loop) / spread))
                drawPolyline(contour.smoothed(iterations: 3).points, closed: true)
            }

            noStroke()
            fill(theme.ink(0.62))
            textSize(16)
            textAlign(.center, .top)
            drawText(panel.0, frame.x + frame.width / 2, frame.y + frame.height + 8)
        }
    }
}
