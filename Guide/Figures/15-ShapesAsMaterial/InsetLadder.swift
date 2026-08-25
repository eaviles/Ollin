// figure: frame=0 themed
//
// Guide diagram (Chapter 15): the straight skeleton. On the left a pinched
// blob with the paths its corners travel as the boundary shrinks, interior
// ridges accented; on the right the same shape as a ladder of mitered
// insets, splitting in two where the waist pinches shut.
import Ollin
import OllinDiagram

final class InsetLadder: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }
    var outline: Color { theme.ink(0.35) }
    var accent: Color { theme.accent }

    override func draw() {
        background(paper)
        seed(4)

        let left = Rectangle(x: 45, y: 62, width: 370, height: 300)
        let right = Rectangle(x: 465, y: 62, width: 370, height: 300)

        frame(left, title: "the skeleton: the paths corners travel")
        frame(right, title: "the inset ladder: one build, every depth")

        for (i, panel) in [left, right].enumerated() {
            let center = Vector2(panel.x + panel.width / 2,
                                 panel.y + panel.height / 2)
            let shape = Shape(pinchedBlob(around: center))
            let skeleton = straightSkeleton(of: shape)

            noFill()
            stroke(outline)
            strokeWeight(1.6)
            drawShape(shape)

            if i == 0 {
                stroke(ink.withAlpha(0.28))
                strokeWeight(1)
                for arc in skeleton.arcs where arc.startDistance == 0 {
                    drawLine(arc.start, arc.end)
                }
                stroke(accent)
                strokeWeight(2.4)
                for arc in skeleton.arcs where arc.startDistance > 0 {
                    drawLine(arc.start, arc.end)
                }
            } else {
                stroke(accent.withAlpha(0.85))
                strokeWeight(1.4)
                for step in 1 ..< 9 {
                    drawShape(skeleton.inset(by: skeleton.maxInset * Double(step) / 9))
                }
            }
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("shrink the boundary evenly and the corners draw the map",
                 width / 2, 400)
    }

    /// A lobed outline with a waist, few enough points that each corner's
    /// arc reads on its own, pinched so the deep insets split in two.
    func pinchedBlob(around center: Vector2) -> [Vector2] {
        (0 ..< 28).map { i in
            let u = Double(i) / 28
            let angle = u * .tau
            let waist = 1 - 0.42 * pow(abs(sin(angle)), 3)
            let wobble = 1 + signedNoise(9, loop: u, radius: 1.3) * 0.16
            return center + Vector2(cos(angle) * 158 * wobble * waist,
                                    sin(angle) * 118 * wobble * waist)
        }
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textSize(17)
        textAlign(.left, .middle)
        drawText(title, r.x + 2, r.y - 20)
    }
}
