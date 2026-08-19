// figure: frame=0
//
// Guide diagram (Chapter 7): two regular hyperbolic tilings in the Poincaré
// disk. Pentagons meeting four to a corner close into a curved checkerboard;
// heptagons meeting three to a corner fade by depth instead. Every tile is
// the same true size, only drawn smaller as it nears the horizon.
import Ollin

final class HyperbolicDisks: Sketch {
    override var canvasSize: CanvasSize { .size(880, 460) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x232020)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)
    let ivory = Color(hex: 0xF2E9DC)
    let indigo = Color(hex: 0x24476B)

    override func draw() {
        background(paper)

        let panels = [
            Rectangle(x: 80, y: 54, width: 330, height: 330),
            Rectangle(x: 470, y: 54, width: 330, height: 330),
        ]

        // {5,4}: meeting is even, so parity closes into a checkerboard.
        drawDisk(hyperbolicTiling(sides: 5, meeting: 4, in: panels[0], minEdge: 3),
                 in: panels[0]) { tile in
            tile.parity == 0 ? ivory : indigo
        }

        // {7,3}: meeting is odd, so fade by depth out from the middle.
        drawDisk(hyperbolicTiling(sides: 7, meeting: 3, in: panels[1], minEdge: 3),
                 in: panels[1]) { tile in
            Color.mix(ivory, indigo, t: min(Double(tile.depth) / 4, 1))
        }

        let titles = ["{5,4}: parity closes a checkerboard", "{7,3}: fading by depth"]
        for (i, panel) in panels.enumerated() {
            noStroke()
            fill(ink)
            textSize(16)
            textAlign(.left, .middle)
            drawText(titles[i], panel.x, panel.y - 18)
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("identical tiles forever, shrinking toward a horizon that never arrives",
                 width / 2, 414)
    }

    func drawDisk(_ tiles: [HyperbolicTiling.Tile], in panel: Rectangle,
                  color: (HyperbolicTiling.Tile) -> Color) {
        noStroke()
        for tile in tiles {
            fill(color(tile))
            drawShape(tile.shape)
        }
        noFill()
        stroke(paper.withAlpha(0.85))
        strokeWeight(1.2)
        for tile in tiles {
            drawPolyline(tile.points, closed: true)
        }
        stroke(soft)
        strokeWeight(2)
        drawCircle(center: panel.center, radius: min(panel.width, panel.height) / 2)
    }
}
