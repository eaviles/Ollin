// figure: frame=0 themed
//
// Guide diagram (Chapter 7): two perfect mazes carved over the same grid by
// two algorithms. Every cell is reachable and there is exactly one route
// between any two, so each maze has one longest route, traced in the accent
// color from its entrance dot to its exit dot. The depth-first carve winds in
// long corridors; the union-find carve leaves many short dead ends.
import Ollin
import OllinDiagram

final class PerfectMaze: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }
    var accent: Color { theme.accent }

    override func draw() {
        background(paper)
        seed(8)

        let panels = [Rectangle(x: 60, y: 62, width: 340, height: 340),
                      Rectangle(x: 480, y: 62, width: 340, height: 340)]
        let algorithms: [Maze.Algorithm] = [.backtracker, .kruskal]
        let titles = [".backtracker", ".kruskal"]

        for (i, panel) in panels.enumerated() {
            let area = panel.inset(by: .all(14))
            let m = maze(columns: 18, rows: 18, algorithm: algorithms[i])

            // The walls: one stroke, joined into long runs.
            stroke(ink)
            strokeWeight(2.4)
            strokeCap(.round)
            noFill()
            drawMaze(m, in: area)

            // The longest route, the maze's natural entrance and exit.
            let route = m.longestPath()
            stroke(accent)
            strokeWeight(4)
            drawPolyline(m.contour(of: route, in: area).points)
            noStroke()
            fill(accent)
            for end in [route.first!, route.last!] {
                drawCircle(center: m.center(ofColumn: end.column, row: end.row, in: area),
                           radius: 6)
            }

            frame(panel, title: titles[i])
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("one route between any two cells, and the longest one traced",
                 width / 2, 430)
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textSize(16)
        textAlign(.left, .middle)
        drawText(title, r.x, r.y - 18)
    }
}
