import Ollin

/// Wave Function Collapse: fill a grid from a handful of tiles so every neighbor
/// connects legally. Each cell starts holding all tiles at once; the solver keeps
/// collapsing the most-constrained cell to one tile and propagating that choice
/// to its neighbors, until the whole grid is a single continuous pipe network.
///
/// The tiles here are a blank plus straight, elbow, tee, and cross connectors
/// (built from one drawn shape each via `rotations()`); their edge sockets say
/// which sides carry a pipe, so the solver only ever places tiles whose pipes
/// line up. The solve is a pure function of the seed, so it re-rolls to a fresh
/// but always-legal layout every few seconds.
@main
final class WaveFunctionCollapseSketch: Sketch {
    private let tiles: [WFCTile] = {
        let blank = WFCTile([0, 0, 0, 0], weight: 1.1)
        let line  = WFCTile([1, 0, 1, 0], weight: 1.6).rotations(2)   // vertical + horizontal
        let elbow = WFCTile([1, 1, 0, 0], weight: 1.3).rotations(4)   // four corners
        let tee   = WFCTile([1, 1, 1, 0], weight: 0.5).rotations(4)
        let cross = WFCTile([1, 1, 1, 1], weight: 0.3)
        return [blank] + line + elbow + tee + [cross]
    }()

    private var grid: [[Int]] = []
    private var roll = -1

    override func draw() {
        // Re-roll to a new (still legal) layout every few seconds.
        let currentRoll = frameCount / 170
        if currentRoll != roll {
            roll = currentRoll
            seed(currentRoll + 1)
            grid = wfc(tiles: tiles, columns: 18, rows: 18) ?? grid
        }
        guard !grid.isEmpty else { return }

        background(Color(hex: 0x0E1116))
        strokeCap(.round)
        strokeJoin(.round)
        strokeWeight(6 * scale)
        noFill()

        drawWFC(grid, padding: .all(40 * scale)) { index, cell in
            let sockets = tiles[index].sockets
            guard sockets.contains(where: { $0 != 0 }) else { return }
            // Tint each tile by position so the network reads with some depth.
            let hue = (cell.center.x + cell.center.y) / (width + height)
            stroke(Color(hue: 0.5 + hue * 0.25, saturation: 0.55, brightness: 0.95))

            let c = cell.center
            let mids = [Vector2(cell.center.x, cell.y),               // top
                        Vector2(cell.x + cell.width, cell.center.y),  // right
                        Vector2(cell.center.x, cell.y + cell.height), // bottom
                        Vector2(cell.x, cell.center.y)]               // left
            for edge in 0 ..< 4 where sockets[edge] != 0 {
                drawLine(c, mids[edge])
            }
        }
    }
}
