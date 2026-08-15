import Ollin

/// A wall that fills in slowly, and remembers how far it got.
///
/// Every few seconds one more tile lands in a free cell, picked at random. That
/// makes the picture something the clock alone cannot rebuild: the same run at
/// the same second would have chosen differently. So the tiles are marked
/// `@Saved`, the installation writes them down every ten seconds, and a relaunch
/// carries on from the wall it left.
///
/// Try it. Run it, let a dozen tiles land, quit with Command-Q, and run it
/// again: the wall is where you left it. Run it with `--fresh` to start over,
/// and the saved wall is left alone for next time.
///
/// The file is JSON you can open, in `~/Library/Application Support/Ollin/`.
/// Ten seconds is a demonstration cadence; a minute suits a piece that is
/// actually going up somewhere. See `Docs/Output/Installation.md`.
@main
final class Resuming: Sketch {

    override var installation: Installation {
        Installation(checkpoint: .every(seconds: 10))
    }

    /// One tile: which cell it took, and how it was dressed. A sketch's own
    /// `Codable` type is saved like any other value.
    struct Tile: Codable {
        var cell: Int
        var shade: Double
        var turn: Double
    }

    @Saved var tiles: [Tile] = []
    @Saved var nextLanding = 0.0

    private let columns = 12
    private let rows = 12
    private let every = 2.0        // seconds between tiles

    private let ink = Ramp([Color(red: 0.20, green: 0.24, blue: 0.34),
                            Color(red: 0.42, green: 0.62, blue: 0.78),
                            Color(red: 0.94, green: 0.80, blue: 0.52),
                            Color(red: 0.86, green: 0.44, blue: 0.36)])

    override func draw() {
        background(Color(white: 0.06))
        land()

        let cellSize = min(width / Double(columns), height / Double(rows))
        let originX = (width - cellSize * Double(columns)) / 2
        let originY = (height - cellSize * Double(rows)) / 2
        noStroke()

        for (index, tile) in tiles.enumerated() {
            let column = tile.cell % columns, row = tile.cell / columns
            let middle = Vector2(originX + (Double(column) + 0.5) * cellSize,
                                 originY + (Double(row) + 0.5) * cellSize)
            // The newest tile settles in over its first second, so a relaunch
            // shows the saved wall standing still and the new work moving.
            let age = min(1, (time - nextLanding + every) * 1.5)
            let settle = index == tiles.count - 1 ? easeOut(max(0, age)) : 1
            let side = cellSize * 0.78 * (0.6 + 0.4 * settle)

            withState {
                translate(middle)
                rotate(tile.turn * (1 - settle))
                fill(ink.color(at: tile.shade).withAlpha(0.35 + 0.65 * settle))
                drawRect(center: Vector2(0, 0), width: side, height: side, cornerRadius: side * 0.22)
            }
        }
    }

    /// One more tile, when it is due and there is anywhere left to put it.
    private func land() {
        guard time >= nextLanding, tiles.count < columns * rows else { return }
        nextLanding = time + every
        let taken = Set(tiles.map(\.cell))
        let free = (0 ..< columns * rows).filter { !taken.contains($0) }
        guard let cell = free.randomElement() else { return }
        tiles.append(Tile(cell: cell, shade: random(), turn: random(-0.6, 0.6)))
    }

    private func easeOut(_ t: Double) -> Double { 1 - pow(1 - t, 3) }
}
