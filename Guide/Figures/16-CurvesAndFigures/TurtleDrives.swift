// figure: frame=0 themed
//
// Guide diagram (Chapter 16): a pen you drive. Left, a square and a pentagon
// walked by a turtle, each with its program under it. Middle, a tree grown by
// walking a limb, remembering the spot, and growing a smaller tree to each
// side. Right, a polyspiral: ever longer steps with the same turn after each.
// Nothing here uses randomness.
import Ollin
import OllinDiagram

final class TurtleDrives: Sketch {
    override var canvasSize: CanvasSize { .size(880, 420) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    let accent = Color(hex: 0xE07A5F)
    let leaf = Color(hex: 0x5B8C5A)

    override func draw() {
        background(paper)

        let panels = [Rectangle(x: 48, y: 60, width: 248, height: 248),
                      Rectangle(x: 316, y: 60, width: 248, height: 248),
                      Rectangle(x: 584, y: 60, width: 248, height: 248)]

        noFill()
        strokeJoin(.round)
        strokeCap(.round)

        // Left: a square and a pentagon, each one short program.
        do {
            let p = panels[0]
            var square = Turtle(at: p.point(u: 0.12, v: 0.42))
            for _ in 0 ..< 4 {
                square.forward(p.width * 0.3)
                square.right(90)
            }
            var pentagon = Turtle(at: p.point(u: 0.56, v: 0.42))
            for _ in 0 ..< 5 {
                pentagon.forward(p.width * 0.26)
                pentagon.right(72)
            }
            strokeWeight(2.5)
            stroke(ink)
            for run in square.contours + pentagon.contours { drawPolyline(run.points) }
            // Where each turtle started, and which way it faced.
            noStroke()
            fill(accent)
            drawCircle(center: p.point(u: 0.12, v: 0.42), radius: 4.5)
            drawCircle(center: p.point(u: 0.56, v: 0.42), radius: 4.5)
            drawText("forward, right 90, four times", p.point(u: 0.5, v: 0.72).x, p.point(u: 0.5, v: 0.72).y,
                     size: 14, color: theme.muted, align: .center, .middle)
            drawText("forward, right 72, five times", p.point(u: 0.5, v: 0.82).x, p.point(u: 0.5, v: 0.82).y,
                     size: 14, color: theme.muted, align: .center, .middle)
            noFill()
        }

        // Middle: a tree, by push and pop.
        do {
            let p = panels[1]
            var tree = Turtle(at: p.point(u: 0.5, v: 0.96))
            grow(&tree, length: p.height * 0.24, depth: 7)
            // A limb's length says how far down the tree it is, since every
            // branch is seven tenths of the one it grows from.
            let runs = tree.contours
            let longest = runs.map(\.length).max() ?? 1
            for run in runs {
                let share = run.length / longest
                strokeWeight(0.8 + 4 * share * share)
                stroke(share > 0.3 ? ink : leaf)
                drawPolyline(run.points)
            }
        }

        // Right: a polyspiral.
        do {
            let p = panels[2]
            var spiral = Turtle(at: p.center, heading: -90)
            for i in 1 ... 60 {
                spiral.forward(Double(i) * 2.2)
                spiral.right(89)
            }
            strokeWeight(1.8)
            stroke(accent)
            drawPolyline(fitted(spiral.contours[0].points, in: p.inset(by: 16)))
        }

        diagramFrame(panels[0], title: "a shape as its moves", theme: theme)
        diagramFrame(panels[1], title: "push, pop: a branch", theme: theme)
        diagramFrame(panels[2], title: "steps 1, 2, 3 … turn 89°", theme: theme)
        diagramCaption("a figure written as the moves that make it, from the pen's own point of view", at: 340, theme: theme)
        drawText("forward, back, left, right, penUp, penDown, pushState, popState; every run an ordinary contour",
                 width / 2, 374, size: 17, color: theme.muted, align: .center, .top)
    }

    func grow(_ turtle: inout Turtle, length: Double, depth: Int) {
        guard depth > 0 else { return }
        turtle.forward(length)
        turtle.pushState()
        turtle.left(26)
        grow(&turtle, length: length * 0.7, depth: depth - 1)
        turtle.popState()
        turtle.pushState()
        turtle.right(26)
        grow(&turtle, length: length * 0.7, depth: depth - 1)
        turtle.popState()
    }
}
