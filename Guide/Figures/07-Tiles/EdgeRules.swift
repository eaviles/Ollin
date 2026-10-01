// figure: frame=0 themed
//
// Guide diagram (Chapter 7): the edge rules behind the tilings that never
// repeat. Left, a small Wang tiling: squares with a color on each edge, laid
// so every pair of touching edges agrees. Right, a Penrose kite and dart that
// share one edge, with the arc from each side reaching that edge at the same
// point, so the curve carries on across it.
import Ollin
import OllinDiagram

final class EdgeRules: Sketch {
    override var canvasSize: CanvasSize { .size(880, 360) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }
    var faint: Color { theme.ink(0.45) }
    let accent = Color(hex: 0xE4572E)
    let cool = Color(hex: 0x17A398)

    // The tilings are depicted content, identical in both themes.
    let tileInk = Color(hex: 0x232020)
    let tilePaper = Color(hex: 0xF7F5F1)
    let sand = Color(hex: 0xE8DDC9)
    let kiteFill = Color(hex: 0xEFE9DE)
    let dartFill = Color(hex: 0xDDD2BE)

    // Ten by six cells of 36 points each, so the squares stay square.
    let left = Rectangle(x: 50, y: 62, width: 360, height: 216)
    let right = Rectangle(x: 470, y: 62, width: 360, height: 216)

    var quilt: WangTiling?
    var pair: [Penrose.Tile] = []

    override func setup() {
        // Re-pinned here so both themed passes lay the same quilt.
        seed(7)
        quilt = wangTiling(WangTiling.completeSet(colors: 2), columns: 10, rows: 6)
        pair = EdgeRules.neighboringPair()
    }

    override func draw() {
        background(paper)

        wangPanel()
        penrosePanel()

        frame(left, title: "Wang tiles: touching edges share a color")
        frame(right, title: "Penrose: the arcs meet across the shared edge")

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("two tiles may sit together only where their edges agree",
                 width / 2, 304)
    }

    // MARK: - Wang tiles

    func wangPanel() {
        guard let quilt else { return }
        noStroke()
        drawWangTiling(quilt, colors: [sand, cool], in: left)
        // The cell borders, so each square reads as one tile of four edges.
        noFill()
        stroke(tileInk.withAlpha(0.35))
        strokeWeight(1)
        for cell in Grid(in: left, columns: quilt.columns, rows: quilt.rows).cells {
            drawRect(cell.frame)
        }
    }

    // MARK: - Penrose

    /// A kite and a dart from one tiling that share an edge, in tile units.
    static func neighboringPair() -> [Penrose.Tile] {
        let field = Rectangle(x: 0, y: 0, width: 400, height: 400)
        let tiles = Penrose.tiles(.kitesAndDarts, in: field, tileEdge: 60)
        let center = field.center
        let kites = tiles.filter { $0.kind == .kite }.sorted {
            centroid(of: $0).distance(to: center) < centroid(of: $1).distance(to: center)
        }
        for kite in kites {
            if let dart = tiles.first(where: { $0.kind == .dart && sharedCorners(kite, $0) == 2 }) {
                return [kite, dart]
            }
        }
        return Array(tiles.prefix(2))
    }

    static func centroid(of tile: Penrose.Tile) -> Vector2 {
        tile.points.reduce(Vector2.zero, +) / Double(tile.points.count)
    }

    static func sharedCorners(_ a: Penrose.Tile, _ b: Penrose.Tile) -> Int {
        a.points.filter { p in b.points.contains { $0.distance(to: p) < 0.5 } }.count
    }

    func penrosePanel() {
        guard pair.count == 2 else { return }
        let kite = pair[0], dart = pair[1]

        // Fit the pair into the panel with one uniform scale.
        let pts = kite.points + dart.points
        let minX = pts.map(\.x).min() ?? 0, maxX = pts.map(\.x).max() ?? 1
        let minY = pts.map(\.y).min() ?? 0, maxY = pts.map(\.y).max() ?? 1
        let box = Rectangle(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        let s = min((right.width - 90) / box.width, (right.height - 50) / box.height)
        func m(_ p: Vector2) -> Vector2 { right.center + (p - box.center) * s }

        noStroke()
        for tile in pair {
            fill(tile.kind == .kite ? kiteFill : dartFill)
            drawPolygon(tile.points.map(m))
        }
        noFill()
        stroke(tileInk.withAlpha(0.55))
        strokeWeight(1)
        for tile in pair {
            drawPolygon(tile.points.map(m))
        }

        // The shared edge, drawn heavier. It sits on the tiles, which keep
        // their colors in both themes, so it is drawn in the tiles' ink.
        let shared = kite.points.filter { p in dart.points.contains { $0.distance(to: p) < 0.5 } }
        if shared.count == 2 {
            stroke(tileInk)
            strokeWeight(3)
            drawLine(m(shared[0]), m(shared[1]))
        }

        // The arc from each tile that ends on the shared edge: those two meet
        // at one point. The other two arcs end on the outer edges.
        var meeting: (Int, Int, Vector2)? = nil
        for (i, a) in kite.arcs.enumerated() {
            for (j, b) in dart.arcs.enumerated() {
                for pa in [a.points.first, a.points.last].compactMap({ $0 }) {
                    for pb in [b.points.first, b.points.last].compactMap({ $0 })
                    where pa.distance(to: pb) < 0.5 {
                        meeting = (i, j, pa)
                    }
                }
            }
        }
        strokeCap(.round)
        for (i, arc) in kite.arcs.enumerated() {
            let joins = meeting?.0 == i
            stroke(joins ? accent : cool)
            strokeWeight(joins ? 3.2 : 2)
            drawPolyline(arc.points.map(m), closed: false)
        }
        for (j, arc) in dart.arcs.enumerated() {
            let joins = meeting?.1 == j
            stroke(joins ? accent : cool)
            strokeWeight(joins ? 3.2 : 2)
            drawPolyline(arc.points.map(m), closed: false)
        }
        if let meeting {
            noStroke()
            fill(tilePaper)
            drawCircle(center: m(meeting.2), radius: 7)
            fill(accent)
            drawCircle(center: m(meeting.2), radius: 4.5)
        }

        // The names sit on the paper beside each tile, level with its middle.
        noStroke()
        fill(faint)
        textSize(15)
        textAlign(.center, .middle)
        drawText("kite", right.x + 62, m(EdgeRules.centroid(of: kite)).y)
        drawText("dart", right.x + right.width - 62, m(EdgeRules.centroid(of: dart)).y)
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
