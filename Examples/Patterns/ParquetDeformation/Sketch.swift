import Ollin

/// A parquet deformation: one tiling whose tile changes shape as you read
/// across it, every piece still meeting its neighbors exactly. The trick is
/// that the geometry lives on the lattice's edges rather than on the tiles, so
/// the two tiles beside any edge are built from the same curve and the tiling
/// cannot come apart however far the shape drifts.
///
/// The run here is a front that travels. Behind it the tile is a soft
/// four-lobed pinwheel, ahead of it an interlocking square key, and the band
/// between holds every shape in between. The front slides back and forth, so
/// the sheet keeps turning one tile into the other and back, which is the
/// whole point of the form, laid out in space in the drawn original and in
/// time here.
///
/// The closure form of the builder is what moves it: it is handed a point and
/// answers how far along the run that point sits, so the front is one
/// `smoothstep` rather than anything the tiling has to know about.
///
/// Both faces draw: the tiles filled by the amount they were built at, and the
/// line-work over them, which visits each lattice edge exactly once.
@main
final class ParquetRun: Sketch {
    override func draw() {
        background(Color(hex: 0x14110F))           // near-black ground

        let field = bounds.inset(by: .all(70 * scale))
        let front = 0.5 + sin(time * 0.25) * 0.55  // where the run sits, now
        let band = 0.55                            // how wide the run is
        let sheet = ParquetDeformation(
            grid: Grid(in: field, columns: 15, rows: 15),
            from: .wave(count: 1, depth: 0.22),
            to: .tooth(depth: 0.3, width: 0.42)
        ) { point in
            let u = (point.x - field.x) / field.width
            return smoothstep(front - band / 2, front + band / 2, u)
        }

        let cool = Color(hex: 0x2E5E6B)            // the wave end
        let warm = Color(hex: 0xE0A33C)            // the tooth end
        noStroke()
        for tile in sheet.tiles {
            fill(Color.mix(cool, warm, tile.amount))
            drawShape(tile.shape)
        }

        stroke(Color(hex: 0xF4EFE6))               // one pass over every edge
        strokeWeight(1.6 * scale)
        strokeJoin(.round)
        for edge in sheet.edges {
            drawPolyline(edge.points, closed: false)
        }
    }
}
