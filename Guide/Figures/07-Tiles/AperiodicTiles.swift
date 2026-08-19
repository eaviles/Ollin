// figure: frame=0 probe
//
// Guide diagram (Chapter 7): the tilings that never repeat. Penrose kites
// and darts with their matching-rule arcs, Penrose rhombs, a girih star
// pattern grown over a honeycomb, and the spectre, one tile that can only
// tile aperiodically.
import Ollin

final class AperiodicTiles: Sketch {
    override var canvasSize: CanvasSize { .size(880, 348) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x232020)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)
    let accent = Color(hex: 0xE4572E)
    let cool = Color(hex: 0x17A398)

    override func draw() {
        background(paper)

        let panels = (0 ..< 4).map {
            Rectangle(x: 25 + Double($0) * 212, y: 62, width: 194, height: 194)
        }

        // Kites and darts, arcs on top: the decoration joins across tiles.
        withClip(panels[0]) {
            let tiles = Penrose.tiles(.kitesAndDarts, in: panels[0], tileEdge: 27)
            noStroke()
            for tile in tiles {
                fill(tile.kind == .kite ? Color(hex: 0xEFE9DE) : Color(hex: 0xDDD2BE))
                drawShape(tile.shape)
            }
            noFill()
            strokeWeight(1.6)
            for tile in tiles {
                for (i, arc) in tile.arcs.enumerated() {
                    stroke(i == 0 ? accent : cool)
                    drawPolyline(arc.points, closed: false)
                }
            }
        }

        // The rhomb pair: two shapes, five-fold order, no repetition.
        withClip(panels[1]) {
            let tiles = Penrose.tiles(.rhombs, in: panels[1], tileEdge: 26)
            noStroke()
            for tile in tiles {
                fill(tile.kind == .thick ? Color(hex: 0xE8DDC9) : paper)
                drawShape(tile.shape)
            }
            noFill()
            stroke(ink.withAlpha(0.55))
            strokeWeight(1)
            for tile in tiles {
                drawShape(tile.shape)
            }
        }

        // A girih star pattern over a honeycomb: rays from edge midpoints.
        withClip(panels[2]) {
            let expanded = Rectangle(center: panels[2].center, width: 260, height: 260)
            let cells = HexGrid(in: expanded, columns: 5, rows: 4).cells.map(\.corners)
            noFill()
            stroke(ink.withAlpha(0.14))
            strokeWeight(1)
            for cell in cells { drawPolygon(cell) }
            stroke(cool)
            strokeWeight(1.8)
            drawGirih(over: cells, angle: 60)
        }

        // The spectre, curved so it is one-handed forever.
        withClip(panels[3]) {
            strokeWeight(1)
            stroke(ink.withAlpha(0.6))
            for tile in Spectre.tiles(in: panels[3], tileEdge: 17, curve: 0.5) {
                fill(tile.isOdd ? accent : Color(hex: 0xEFE9DE))
                drawShape(tile.shape)
            }
        }

        let titles = ["kites & darts", "rhombs", "girih strapwork", "the spectre"]
        for (i, panel) in panels.enumerated() { frame(panel, title: titles[i]) }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("two shapes, or even one, that can never fall into a repeat",
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
