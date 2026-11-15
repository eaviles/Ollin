// figure: frame=0 themed
//
// Guide diagram (Chapter 4): what a grid chain keeps as it reads more of the
// cells around a place. One small picture of a town on the left, and the
// field a `MarkovGrid` writes from it at orders 1 to 4. Along its row alone
// the town is loose stripes; with the cell above the buildings run together;
// with all four the blocks keep their sides and the streets stay open.
import Ollin
import OllinDiagram

final class GridReach: Sketch {
    override var canvasSize: CanvasSize { .size(880, 300) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }
    var accent: Color { theme.accent }

    /// A town seen from above: `#` a building, `p` a park, `w` a pond, and
    /// `.` the street between them.
    static let town = [
        "........................",
        ".####.######.ppppp.####.",
        ".####.######.ppppp.####.",
        ".####.######.ppppp.####.",
        ".####........ppppp.####.",
        "......#####.........####",
        ".###..#####.######......",
        ".###..#####.######.####.",
        ".###........######.####.",
        ".###.wwwww.........####.",
        ".....wwwww.#######.####.",
        ".###.wwwww.#######......",
        ".###.......#######.###..",
        ".###.#####.........###..",
        ".....#####.pppppp..###..",
        ".###.#####.pppppp.......",
        ".###.......pppppp.#####.",
        ".###.####..........#####",
        ".....####.#######..#####",
        ".###.####.#######.......",
        ".###......#######.####..",
        ".###.####.........####..",
        ".....####.######..####..",
        "........................",
    ].map(Array.init)

    override func draw() {
        background(paper)

        let side = 150.0
        let top = 62.0
        let data = Rectangle(x: 24, y: top, width: side, height: side)
        paint(Self.town, in: data)
        frame(data, title: "the picture")

        for order in 1 ... 4 {
            let panel = Rectangle(x: 210 + Double(order - 1) * (side + 16), y: top, width: side, height: side)
            var chain = MarkovGrid<Character>(vocabulary: Array(".#pw"), order: order, seed: 3)
            // The picture is written above, every row of one length.
            try! chain.learn(Self.town)
            paint(chain.nextRows(30, columns: 30), in: panel)
            frame(panel, title: "order \(order)")
        }

        noStroke()
        fill(ink)
        textSize(19)
        textAlign(.center, .top)
        drawText("the more of the cells around a place it reads, the more of the town it keeps",
                 width / 2, 240)
    }

    /// The cells of a grid, fitted to a square: buildings in ink, parks in
    /// the accent, ponds in a lighter ink, streets left as paper. Each run of
    /// one letter along a row is a single polygon, and polygons that share an
    /// edge meet without a seam.
    func paint(_ rows: [[Character]], in r: Rectangle) {
        let cell = r.width / Double(rows[0].count)
        noStroke()
        for (y, row) in rows.enumerated() {
            var start = 0
            while start < row.count {
                var end = start + 1
                while end < row.count, row[end] == row[start] { end += 1 }
                if row[start] != "." {
                    let left = r.x + Double(start) * cell, right = r.x + Double(end) * cell
                    let above = r.y + Double(y) * cell
                    fill(row[start] == "#" ? theme.ink(0.82) : row[start] == "p" ? accent : theme.ink(0.34))
                    drawPolygon([Vector2(left, above), Vector2(right, above),
                                 Vector2(right, above + cell), Vector2(left, above + cell)])
                }
                start = end
            }
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
        drawText(title, r.x, r.y - 18)
    }
}
