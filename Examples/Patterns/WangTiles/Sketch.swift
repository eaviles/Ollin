import Ollin

/// Wang tiles: squares with colored edges that may only sit together where
/// the touching edges agree. A seeded scanline fill turns those local rules
/// into one connected, maze-like pattern; here each tile draws its edge
/// colors as four triangles meeting at the cell center, the classic
/// rendering, and the whole quilt re-lays itself every few seconds by walking
/// the seed.
@main
final class WangQuilt: Sketch {
    private var tiling: WangTiling?
    private var laidSeed = -1

    override func draw() {
        // A fresh layout every four seconds, each derived from the sketch's
        // variation so the run stays reproducible without reseeding it.
        let step = Int(time / 4)
        if tiling == nil || step != laidSeed {
            laidSeed = step
            var rng = SplitMix64(seed: UInt64(bitPattern: Int64(variation &+ step)))
            tiling = WangTiling.fill(tiles: WangTiling.completeSet(colors: 2),
                                     columns: 15, rows: 15, using: &rng)
        }
        guard let tiling else { return }

        background(Color(hex: 0x0E1116))
        noStroke()
        drawWangTiling(tiling, colors: [Color(hex: 0x14213D), Color(hex: 0xFCA311)])
    }
}
