import Ollin

/// Four ways to scatter points, side by side, while the count breathes.
///
/// Plain `random` clumps and leaves holes at every count. The Halton and Sobol
/// sequences cover evenly at every count, and they're *streams*: as the count
/// grows, the points already placed never move, new ones just land in the
/// gaps (watch the panels; only the random one reads noisy). The Poisson-disk
/// set is the odd one out on purpose: its coverage is the most even of all at
/// full count, but it's a *layout*, not a stream, so cutting it short leaves
/// a patch grown around its seed instead of a fair covering of the whole
/// frame.
///
/// That prefix property is what the sequences are for: draft with 100 points,
/// render with 10,000, and the draft is a subset of the final.
@main
final class LowDiscrepancy: Sketch {
    private let labelFont = OutlineFont.system
    private let maxCount = 900

    private var panels: [(String, [Vector2])] = []

    override var loopDuration: Double? { 16 }

    override func setup() {
        seed(7)
        // One unit square of each; panels scale the points to their frame.
        let unit = Rectangle(x: 0, y: 0, width: 1, height: 1)
        let scattered = (0 ..< maxCount).map { _ in randomVector(in: unit) }
        panels = [
            ("random", scattered),
            ("poisson disk", poissonDisk(in: unit, radius: 0.022, maxCount: maxCount)),
            ("halton (2, 3)", haltonPoints(count: maxCount, in: unit)),
            ("sobol", sobolPoints(count: maxCount, in: unit)),
        ]
    }

    override func draw() {
        background(Color(hex: 0x11141C))

        // The prefix on show: out and back over the loop, so every panel grows
        // to its full count and thins back down.
        let t = Easing.easeInOutQuad(pingPong(over: 16))
        let count = 60 + Int(t * Double(maxCount - 60))

        let plate = 44.0
        let grid = Grid(in: Rectangle(x: 0, y: 0, width: width, height: height - 30),
                        columns: 2, rows: 2, padding: 66, gutter: 54)
        for cell in grid.cells {
            let (label, points) = panels[cell.row * 2 + cell.column]
            let frame = Rectangle(x: cell.frame.x, y: cell.frame.y,
                                  width: cell.frame.width, height: cell.frame.height - plate)

            fill(Color(hex: 0x171B26))
            noStroke()
            drawRect(corner: frame.corner, width: frame.width, height: frame.height, cornerRadius: 10)

            fill(Color(hex: 0xE8ECF4))
            for p in points.prefix(count) {
                drawCircle(frame.x + p.x * frame.width, frame.y + p.y * frame.height, 2.6 * scale)
            }

            fill(Color(white: 0.75))
            textFont(labelFont)
            textSize(16)
            textAlign(.left, .middle)
            drawText(label, frame.x, frame.y + frame.height + plate / 2)
        }

        drawCaption("\(count) points each; the sequences stay evenly spread at every count")
    }
}
