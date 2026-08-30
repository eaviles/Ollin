import Ollin

/// A Penrose rhombus tiling, the two-tile pattern that covers the plane with
/// five-fold symmetry and never repeats. The thick and thin rhombs are filled
/// by kind, and the matching-rule arcs are stroked on top: every arc end meets
/// a neighbor's across the shared edge, so the decoration reads as one weave
/// of closed curves. A slow pulse breathes light along the curves; the tiling
/// itself is a pure function of the canvas, computed once and held.
@main
final class PenroseRhombs: Sketch {
    private var tiles: [Penrose.Tile] = []
    private let period = 8.0
    override var loopDuration: Double? { period }

    override func draw() {
        if tiles.isEmpty {
            tiles = penroseTiling(.rhombs, tileEdge: 72)
        }

        background(Color(hex: 0x14101E))

        noStroke()
        for tile in tiles {
            fill(tile.kind == .thick ? Color(hex: 0x342A58) : Color(hex: 0x181129))
            drawShape(tile.shape)
        }

        // The arcs, breathing: brightness sweeps outward from the sun at the
        // center, one wavefront per loop.
        noFill()
        strokeCap(.round)
        let center = center
        let maxDistance = center.length
        for tile in tiles {
            let distance = tile.points[0].distance(to: center) / maxDistance
            let wave = pingPong(over: period, phase: distance)
            for (i, arc) in tile.arcs.enumerated() {
                let base = i == 0 ? Color(hex: 0xF2A65A) : Color(hex: 0x2EC4B6)
                stroke(Color.mix(base, .white, wave * 0.35).withAlpha(0.55 + wave * 0.45))
                strokeWeight((2.5 + wave * 2) * scale)
                drawPolyline(arc.points, closed: false)
            }
        }
    }
}
