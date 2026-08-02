import Ollin

/// Islamic star patterns by the polygons-in-contact method: every tile edge
/// midpoint sprouts a pair of rays at the contact angle, and where rays meet,
/// the strapwork is born. The background sweeps the contact angle over a
/// honeycomb, morphing the same tiling from spiky stars to a woven lattice;
/// the medallion is the girih-tile flower (a decagon ringed by ten pentagons)
/// at the classic 54 degrees.
@main
final class GirihStars: Sketch {
    private let period = 12.0
    override var loopDuration: Double? { period }

    private var hexes: [[Vector2]] = []
    private var flower: [[Vector2]] = []

    override func setup() {
        // A honeycomb over an expanded rectangle, so cells cover the whole
        // canvas instead of letterboxing inside it.
        let expanded = Rectangle(center: Vector2(width / 2, height / 2),
                                 width: width * 1.3, height: height * 1.3)
        hexes = HexGrid(in: expanded, columns: 13, rows: 12).cells.map(\.corners)

        // The flower: a decagon with a pentagon laid on each edge. Girih
        // tiles share one edge length, so walking each decagon edge backward
        // lands a pentagon snug against it, on the outside.
        let edge = width * 0.052
        let decagon = Girih.Tile.decagon.points(edge: edge, at: Vector2(width / 2, height / 2))
        flower = [decagon]
        for i in decagon.indices {
            let p = decagon[i], q = decagon[(i + 1) % decagon.count]
            flower.append(Girih.Tile.pentagon.points(onEdge: q, p))
        }
    }

    override func draw() {
        background(Color(hex: 0x101418))

        // The honeycomb strapwork, contact angle swinging over the loop.
        let angle = 35 + pingPong(over: period) * 35   // 35...70 degrees
        noFill()
        stroke(Color(hex: 0x2EC4B6).withAlpha(0.8))
        strokeWeight(2.5 * scale)
        strokeCap(.round)
        drawGirih(over: hexes, angle: angle)

        // The girih-tile medallion at the classic angle.
        fill(Color(hex: 0x101418).withAlpha(0.85))
        noStroke()
        for tile in flower { drawPolygon(tile) }
        noFill()
        stroke(Color(hex: 0xFCA311))
        strokeWeight(3.5 * scale)
        drawGirih(over: flower, angle: 54)
    }
}
