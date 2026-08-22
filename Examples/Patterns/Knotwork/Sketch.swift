import Ollin

/// **Celtic knotwork**: the kolam line given width and a rule about who passes
/// over whom. Wherever two passes meet, one goes over, and the choice
/// alternates along every cord, so the weave holds together instead of reading
/// as a tangle.
///
/// The bands come back already broken where they dive under, so stroking them
/// in order draws the weave. No masking, and no draw order to get right.
///
/// Try it: change the field size, or move a wall, and watch a knot become a
/// different knot.
@main
final class Knotwork_Example: Sketch {
    @Param(3 ... 10, icon: "arrow.left.and.right") var columns = 6.0
    @Param(3 ... 10, icon: "arrow.up.and.down") var rows = 6.0
    @Param(6 ... 40, icon: "scribble") var band = 22.0
    @Param(icon: "square.split.2x2") var showWalls = true

    let walls: [Kolam.Mirror] = [.rightOf(column: 2, row: 2), .below(column: 2, row: 2),
                                 .rightOf(column: 2, row: 3), .below(column: 3, row: 2)]

    let paper = Color(hex: 0x1D2B24)
    let ink = Color(hex: 0x0B1310)
    let gold = Color(hex: 0xE7C46B)

    override func draw() {
        background(paper)

        let field = bounds.inset(by: .all(width * 0.1))
        let inUse = showWalls
            ? walls.filter { $0.column < Int(columns) && $0.row < Int(rows) } : []
        let knot = knotwork(in: field, columns: Int(columns), rows: Int(rows), mirrors: inUse)

        for piece in knot.bands(gap: band * 1.35) {
            let line = piece.smoothed(iterations: 3)
            withState {
                strokeCap(.round)
                strokeJoin(.round)
                stroke(ink)
                strokeWeight(band)
                drawPolyline(line.points, closed: line.isClosed)
                stroke(gold)
                strokeWeight(band - 7)
                drawPolyline(line.points, closed: line.isClosed)
            }
        }

        noStroke()
        fill(gold.withAlpha(0.55))
        textFont(.system); textSize(width * 0.02); textAlign(.center, .bottom)
        drawText("\(knot.cords.count) cord\(knot.cords.count == 1 ? "" : "s"), \(knot.crossings.count) crossings",
                 width / 2, height - width * 0.035)
    }
}
