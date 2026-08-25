// figure: frame=0 themed
//
// Guide diagram (Chapter 15): the spirolateral, and what decides whether it
// closes. One run on the left, the four runs it takes to come home in the
// middle, and an order whose runs never come home on the right.
import Ollin
import OllinDiagram

final class Spirolaterals: Sketch {
    override var canvasSize: CanvasSize { .size(880, 460) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    let accent = Color(hex: 0xE07A5F)
    var soft: Color { theme.ink(0.12) }

    override func draw() {
        background(paper)

        let panels = [Rectangle(x: 64, y: 66, width: 232, height: 232),
                      Rectangle(x: 324, y: 66, width: 232, height: 232),
                      Rectangle(x: 584, y: 66, width: 232, height: 232)]

        // One run of order 7, and the whole figure those runs make. Both are
        // fitted to the finished figure, so the run sits where it sits in it.
        let whole = spirolateral(order: 7, step: 10)
        let placed = fitted(whole.points, in: panels[1].inset(by: 18))
        let scaleToPanel = { (points: [Vector2], panel: Rectangle) -> [Vector2] in
            points.map { $0 - panels[1].center + panel.center }
        }

        noFill()
        strokeJoin(.round)
        strokeWeight(3)
        stroke(accent)
        drawPolyline(scaleToPanel(Array(placed.prefix(8)), panels[0]), closed: false)

        stroke(ink)
        strokeWeight(2)
        drawPolyline(placed, closed: true)
        stroke(accent)
        strokeWeight(3)
        drawPolyline(Array(placed.prefix(8)), closed: false)

        // An order that is a multiple of four turns the walker a whole number of
        // turns per run, so every repeat leaves in the same direction.
        let drifting = spirolateral(order: 8, step: 10, repeats: 3)
        stroke(ink)
        strokeWeight(2)
        drawPolyline(fitted(drifting.points, in: panels[2].inset(by: 18)), closed: false)

        frame(panels[0], title: "one run: 1, 2, 3 … 7")
        frame(panels[1], title: "four runs, and it closes")
        frame(panels[2], title: "order 8 never closes")

        fill(ink)
        noStroke()
        textSize(21)
        textAlign(.center, .top)
        drawText("the figure closes when a whole number of runs makes a whole turn",
                 width / 2, 352)
        textSize(17)
        fill(darkTheme ? Color(hex: 0xE8E5E1, alpha: 0.62) : Color(hex: 0x6E6A63))
        drawText("at a quarter turn, that leaves out the multiples of four and nothing else",
                 width / 2, 386)
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
        drawText(title, r.x, r.y - 20)
    }
}
