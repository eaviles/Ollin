// figure: frame=0 themed
//
// Guide diagram (Chapter 6): four more ways to divide a region, beside the
// square grid the chapter opens with. Hexagons, triangles, recursive
// splitting, and a carved maze, all read one cell at a time like `Grid`.
import Ollin
import OllinDiagram

final class OtherGrids: Sketch {
    override var canvasSize: CanvasSize { .size(880, 348) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }
    var accent: Color { theme.accent }

    override func draw() {
        background(paper)
        seed(6)

        let panels = (0 ..< 4).map {
            Rectangle(x: 25 + Double($0) * 212, y: 62, width: 194, height: 194)
        }

        // Hexagons, tinted by how many rings out from one chosen cell.
        let hexes = HexGrid(in: panels[0].inset(by: .all(6)), columns: 7, rows: 6,
                            gutter: 2)
        let focus = hexes.cell(column: 3, row: 2)
        noStroke()
        for cell in hexes.cells {
            let rings = Double(hexes.distance(from: focus, to: cell))
            fill(Color.mix(accent, ink, min(1, rings / 4)))
            drawPolygon(cell.corners)
        }

        // Triangles, alternating by which way they point.
        let tris = TriangleGrid(in: panels[1].inset(by: .all(6)), columns: 13,
                                rows: 7, gutter: 2)
        noStroke()
        for cell in tris.cells {
            fill(cell.pointsUp ? ink : accent)
            drawPolygon(cell.vertices)
        }

        // Recursive splitting: panels all the way down to a minimum size.
        stroke(paper)
        strokeWeight(3)
        for cell in subdivide(in: panels[2].inset(by: .all(6)), minSize: 34,
                              chance: 0.8) {
            fill(random(0, 1) < 0.25 ? accent : ink)
            drawRect(cell.frame)
        }

        // A perfect maze: every cell reachable, exactly one route between any two.
        let m = maze(columns: 9, rows: 9)
        stroke(ink)
        strokeWeight(2.4)
        strokeCap(.round)
        noFill()
        drawMaze(m, in: panels[3].inset(by: .all(10)))

        let titles = ["hexGrid", "triangleGrid", "subdivide", "maze"]
        for (i, panel) in panels.enumerated() { frame(panel, title: titles[i]) }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("four more ways to cut up a rectangle, each read cell by cell",
                 width / 2, 288)
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
