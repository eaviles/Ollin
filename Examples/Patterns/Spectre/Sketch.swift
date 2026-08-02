import Ollin

/// The spectre, the einstein: one tile, no repeats, ever. The patch is grown
/// by the discovery paper's substitution system with curved edges (the
/// strictly chiral form, which cannot tile mirrored even if it wanted to).
/// Every tile is the same shape and the same handedness; the rare "odd"
/// tiles, each riding a mystic pair rotated thirty degrees from the rest,
/// glow as accents while a slow tide of light drifts across the field.
@main
final class SpectreField: Sketch {
    private var tiles: [Spectre.Tile] = []
    private let period = 10.0
    override var loopDuration: Double? { period }

    override func draw() {
        if tiles.isEmpty {
            tiles = spectreTiling(tileEdge: 26, curve: 0.55)
        }

        background(Color(hex: 0x0F1214))

        let diagonal = Vector2(width, height).length
        for tile in tiles {
            let along = (tile.points[0].x + tile.points[0].y) / diagonal
            let tide = pingPong(over: period, phase: along)
            if tile.isOdd {
                fill(Color.mix(Color(hex: 0xF6511D), Color(hex: 0xFCA311), t: tide))
            } else {
                fill(Color.mix(Color(hex: 0x1C2B2D), Color(hex: 0x2EC4B6), t: tide * 0.45))
            }
            stroke(Color(hex: 0x0F1214))
            strokeWeight(1.5 * scale)
            drawShape(tile.shape)
        }
    }
}
