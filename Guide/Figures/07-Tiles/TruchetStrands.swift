// figure: frame=0 themed
//
// Guide diagram (Chapter 7): the strands as values. On the left, the arcs that
// `truchet` hands back over an eight by eight grid, each contour stroked in a
// color of its own, so the quarter circles read as the separate values they
// are. On the right, the same arrangement (the seed is pinned again before the
// second call) stroked twice: a wide rim pass in ink under a narrower color
// pass, all rims before any color, so the arcs merge into one pipe wherever
// they meet at a doorway. The color follows each strand's midpoint across the
// panel, which is the finished sketch's move without its noise.
import Ollin
import OllinDiagram

final class TruchetStrands: Sketch {
    override var canvasSize: CanvasSize { .size(880, 460) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }

    let ramp = Ramp([
        Color(hex: 0xF2542D), Color(hex: 0xF5DFBB),
        Color(hex: 0x0E9594), Color(hex: 0x127475),
    ])

    override func draw() {
        background(paper)

        let left = Rectangle(x: 92, y: 60, width: 320, height: 320)
        let right = Rectangle(x: 468, y: 60, width: 320, height: 320)
        let columns = 8

        // The same seed before each call gives the same coin flips, so the
        // right panel is the left one's arrangement drawn a second way.
        seed(3)
        let strands = truchet(in: left, columns: columns, rows: columns, tile: .arcs)
        seed(3)
        let piping = truchet(in: right, columns: columns, rows: columns, tile: .arcs)

        noFill()
        strokeCap(.round)

        strokeWeight(6)
        for (index, strand) in strands.enumerated() {
            stroke(CosinePalette.rainbow.color(at: (Double(index) * 0.6180339887)
                .truncatingRemainder(dividingBy: 1)))
            drawPolyline(strand.points)
        }

        let cell = right.width / Double(columns)
        stroke(ink)
        strokeWeight(cell * 0.40)
        for strand in piping {
            drawPolyline(strand.points)
        }
        strokeWeight(cell * 0.26)
        for strand in piping {
            let along = (strand.midpoint.x - right.x) / right.width
            stroke(ramp.color(at: along))
            drawPolyline(strand.points)
        }

        frame(left, title: "\(strands.count) strands, each in its own color")
        frame(right, title: "the same strands, stroked twice")

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("hold the strands, and you decide how each one is drawn",
                 width / 2, 404)
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
