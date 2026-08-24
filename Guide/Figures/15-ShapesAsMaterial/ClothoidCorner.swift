// figure: frame=0 themed
//
// Guide diagram (Chapter 15): the same corner rounded two ways, each drawn
// over a graph of how hard it is bending as you travel along it. The plain arc
// steps; the eased corner ramps. Nothing here uses randomness.
import Ollin

final class ClothoidCorner: Sketch {
    override var canvasSize: CanvasSize { .size(880, 600) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x232020) }
    var soft: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.12) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }

    // One corner, drawn twice.
    let plan = [Vector2(40, 30), Vector2(250, 30), Vector2(250, 240)]
    let radius = 70.0

    override func draw() {
        background(paper)

        panel(x: 46, easement: 0.01,
              title: "one arc: the bend jumps twice",
              note: "the wheel is yanked, then held, then yanked back")
        panel(x: 486, easement: 82,
              title: "an easement each side: the bend ramps",
              note: "the wheel turns in, holds, and unwinds")

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("same corner, same radius: only the way the bend arrives is different",
                 width / 2, 552)
    }

    func panel(x: Double, easement: Double, title: String, note: String) {
        let route = clothoidCorners(plan, radius: radius, easement: easement)
        let total = route.length

        withState {
            translate(x, 60)

            noStroke()
            fill(ink)
            textSize(18)
            textAlign(.left, .middle)
            drawText(title, 0, -26)

            // The corner itself, over the polyline it was cut from.
            noFill()
            stroke(soft)
            strokeWeight(2)
            drawPolyline(plan)
            stroke(ink)
            strokeWeight(2.4)
            drawPolyline(route.contour(spacing: 0.5).points)

            // Where the turn leaves and rejoins the legs.
            noStroke()
            fill(accent)
            for piece in route where piece.curvatureRate != 0 || piece.curvature != 0 {
                drawCircle(center: piece.start, radius: 3.2)
                drawCircle(center: piece.end, radius: 3.2)
            }
        }

        // The bend, graphed against distance traveled.
        withState {
            translate(x, 350)
            let graph = Rectangle(x: 0, y: 0, width: 320, height: 130)

            noFill()
            stroke(soft)
            strokeWeight(2)
            drawLine(Vector2(0, graph.height), Vector2(graph.width, graph.height))
            drawLine(Vector2(0, 0), Vector2(0, graph.height))

            var line = [Vector2]()
            for i in 0...600 {
                let s = total * Double(i) / 600
                let bend = abs(route.curvature(at: s) ?? 0)
                line.append(Vector2(graph.width * Double(i) / 600,
                                    graph.height - bend * radius * graph.height))
            }
            stroke(accent)
            strokeWeight(2.2)
            drawPolyline(line)

            noStroke()
            fill(ink.withAlpha(0.7))
            textSize(15)
            textAlign(.left, .middle)
            drawText("1 / radius", 6, 6)
            textAlign(.left, .top)
            drawText("distance along the route", 0, graph.height + 10)
            textAlign(.left, .top)
            fill(ink)
            textSize(16)
            drawText(note, 0, graph.height + 36)
        }
    }
}
