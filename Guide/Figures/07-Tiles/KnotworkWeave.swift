// figure: frame=0
//
// Guide figure (Chapter 7): Celtic knotwork. The same walk three ways: the bare
// line, the line given width and an over-under rule, and the knot the walls
// make of it.
import Ollin

final class KnotworkWeave: Sketch {
    override var canvasSize: CanvasSize { .size(880, 386) }

    let paper = Color(hex: 0x1D2B24)
    let ink = Color(hex: 0x0B1310)
    let gold = Color(hex: 0xE7C46B)

    override func draw() {
        background(Color(hex: 0xF7F5F1))

        let tile = 268.0, gap = 12.0
        let left = (width - tile * 3 - gap * 2) / 2
        let walls: [Kolam.Mirror] = [.rightOf(column: 2, row: 2), .below(column: 2, row: 2),
                                     .rightOf(column: 2, row: 3), .below(column: 3, row: 2)]
        let labels = ["the line", "given width", "and walls in the middle"]

        textFont(.system)
        for index in 0 ..< 3 {
            let x = left + Double(index) * (tile + gap)
            let frame = Rectangle(x: x, y: 20, width: tile, height: tile)
            noStroke()
            fill(paper)
            drawRect(frame)

            let field = frame.inset(by: 26)
            let mirrors = index == 2 ? walls : []
            let knot = knotwork(in: field, columns: 6, rows: 6, mirrors: mirrors)

            if index == 0 {
                noFill()
                stroke(gold)
                strokeWeight(3)
                strokeJoin(.round)
                for cord in knot.cords {
                    drawPolyline(cord.smoothed(iterations: 3).points, closed: true)
                }
            } else {
                for band in knot.bands(gap: 20) {
                    let line = band.smoothed(iterations: 3)
                    withState {
                        strokeCap(.round)
                        strokeJoin(.round)
                        stroke(ink)
                        strokeWeight(15)
                        drawPolyline(line.points, closed: line.isClosed)
                        stroke(gold)
                        strokeWeight(9)
                        drawPolyline(line.points, closed: line.isClosed)
                    }
                }
            }

            noStroke()
            fill(Color(hex: 0x2B2B2B, alpha: 0.62))
            textSize(16)
            textAlign(.center, .top)
            drawText(labels[index], frame.x + frame.width / 2, frame.y + frame.height + 8)
        }
    }
}
