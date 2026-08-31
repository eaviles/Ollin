import Ollin

/// A Penrose tiling, the two-tile pattern that covers the plane with five-fold
/// symmetry and never repeats. Both built-in variants are here: the P3 thick
/// and thin rhombs, and the P2 kites and darts; click or press a key to swap.
/// The tiles are filled by kind, and the matching-rule arcs are stroked on
/// top: every arc end meets a neighbor's across the shared edge, so the
/// decoration reads as one weave of closed curves in either variant. A slow
/// pulse breathes light along the curves; each tiling is a pure function of
/// the canvas, computed once and held.
@main
final class PenroseRhombs: Sketch {
    private var variant: Penrose.Variant = .rhombs
    private var tiles: [Penrose.Tile] = []
    private let period = 8.0
    override var loopDuration: Double? { period }

    override func draw() {
        if tiles.isEmpty {
            tiles = penroseTiling(variant, tileEdge: 72)
        }

        background(Color(hex: 0x14101E))

        noStroke()
        for tile in tiles {
            fill(tileColor(tile.kind))
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

        drawCaption(variant == .rhombs
            ? "P3 thick and thin rhombs; click or press a key for the P2 kites and darts"
            : "P2 kites and darts; click or press a key for the P3 rhombs")
    }

    override func mousePressed() { swapVariant() }
    override func keyPressed() { swapVariant() }

    private func swapVariant() {
        variant = variant == .rhombs ? .kitesAndDarts : .rhombs
        tiles = []
    }

    private func tileColor(_ kind: Penrose.TileKind) -> Color {
        switch kind {
        case .thick: return Color(hex: 0x342A58)
        case .thin: return Color(hex: 0x181129)
        case .kite: return Color(hex: 0x24504B)
        case .dart: return Color(hex: 0x241531)
        }
    }
}
