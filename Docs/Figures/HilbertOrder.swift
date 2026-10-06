// figure: frame=0 themed
//
// Docs diagram (Generators/HilbertOrder.md): the Hilbert curve and a scatter
// in its order. Left, the curve at level 3 through the 64 cells of its grid,
// which is the sort of the cells' own centers. Right, a seeded scatter of
// points joined as one line in the order the curve visits them, with the
// first and last points marked.
import Ollin
import OllinDiagram

final class HilbertOrder: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var accent: Color { theme.accent }

    override func draw() {
        background(paper)
        let left = Rectangle(x: 110, y: 56, width: 300, height: 300)
        let right = Rectangle(x: 470, y: 56, width: 300, height: 300)

        // The curve: the cell centers of an 8 by 8 grid, sorted along it.
        let level = 3
        let n = 1 << level
        var centers: [Vector2] = []
        for row in 0 ..< n {
            for column in 0 ..< n {
                centers.append(left.point(u: (Double(column) + 0.5) / Double(n),
                                          v: (Double(row) + 0.5) / Double(n)))
            }
        }
        let curve = hilbertSorted(centers, level: level)
        noFill()
        stroke(theme.border)
        strokeWeight(1)
        for k in 1 ..< n {
            let f = Double(k) / Double(n)
            drawLine(left.point(u: f, v: 0), left.point(u: f, v: 1))
            drawLine(left.point(u: 0, v: f), left.point(u: 1, v: f))
        }
        stroke(ink)
        strokeWeight(2.5)
        strokeJoin(.round)
        drawPolyline(curve)
        noStroke()
        fill(accent)
        drawCircle(center: curve[0], radius: 5)
        drawCircle(center: curve[curve.count - 1], radius: 5)

        // A scatter joined in curve order.
        seed(7)
        let points = (0 ..< 320).map { _ in randomVector(in: right.inset(by: 12)) }
        let line = hilbertSorted(points)
        noFill()
        stroke(ink)
        strokeWeight(1.4)
        drawPolyline(line)
        noStroke()
        fill(theme.muted)
        drawCircles(points, radius: 2)
        fill(accent)
        drawCircle(center: line[0], radius: 5)
        drawCircle(center: line[line.count - 1], radius: 5)

        diagramFrame(left, title: "level 3: 64 cells, one path", theme: theme)
        diagramFrame(right, title: "320 points sorted along it", theme: theme)

        drawText("a cell's neighbor on the curve is its neighbor on the page, so the sorted line stays local",
                 width / 2, 400, size: 17, color: ink, align: .center, .top)
    }
}
