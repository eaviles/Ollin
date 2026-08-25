// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Drawing.md, drawArrow): one arrow with its two
// anchor points dotted, a heavier arrow whose head has grown with the stroke
// weight, and a ring of thin arrows fanning out from a shared center.
import Ollin
import OllinDiagram

final class DrawArrow: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var accent: Color { theme.accent }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        // One arrow, its two anchors dotted: the tip lands exactly on `to`.
        let from = Vector2(120, 210)
        let to = Vector2(330, 96)
        stroke(ink)
        strokeWeight(3)
        drawArrow(from: from, to: to)
        noStroke()
        fill(accent)
        drawPoint(from.x, from.y, 6)
        drawPoint(to.x, to.y, 6)
        fill(ink)
        drawText("from", at: from + Vector2(0, 22), size: 16, align: .center, .middle)
        drawText("to", at: to + Vector2(0, -20), size: 16, align: .center, .middle)

        // A heavier stroke: the head grows with the weight by itself.
        stroke(ink)
        strokeWeight(9)
        drawArrow(from: Vector2(410, 210), to: Vector2(610, 110))
        drawText("the head follows the weight", at: Vector2(510, 246),
                 size: 16, color: ink, align: .center, .top)

        // A fan of thin arrows from one center: one stroke() colors each
        // whole mark, shaft and head.
        let hub = Vector2(740, 152)
        stroke(accent)
        strokeWeight(2)
        for a in angles(9) {
            drawArrow(from: polar(a, 26, around: hub), to: polar(a, 92, around: hub))
        }

        drawText("a stroked shaft, a solid head, one color", at: Vector2(440, 280),
                 size: 18, color: ink, align: .center, .top)
    }
}
