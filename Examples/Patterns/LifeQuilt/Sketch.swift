//  Ported from @eaviles's sketch 2024.026. Reworked for Ollin's API.

import Ollin

/// A quilt of triangular wedges driven by Conway's Game of Life.
///
/// Four independent life grids share the canvas. Each live cell is filled with a
/// right-isosceles wedge whose apex sits at the cell center, rotated a quarter
/// turn per layer — so the four layers tile every cell into quadrants. A wedge
/// is colored by its angle from the canvas center through a cosine palette, and
/// fades in and out with the cell's life. The grids step every 20 frames (a cell
/// is born on 3 live neighbors, survives on 2 or 3); a cell that lives past 60
/// generations dies and scatters fresh seeds, so the quilt keeps churning. Every
/// wedge is one analytic SDF triangle, so the thousands on screen stay crisp and
/// cheap.
@main
final class LifeQuilt: Sketch {
    static let gridSize = 48
    static let layerCount = 4

    struct Cell { var alive = false; var alpha = 0.0; var gen = 0 }
    /// `cells[layer][i][j]` — four overlaid life grids.
    var cells: [[[Cell]]] = []

    override func setup() {
        seed(2_024_026)
        let n = Self.gridSize
        let column = Array(repeating: Cell(), count: n)
        let plane = Array(repeating: column, count: n)
        cells = Array(repeating: plane, count: Self.layerCount)
        for layer in 0..<Self.layerCount {
            for _ in 0..<(n * 2) {
                let (i, j) = seedCell()
                cells[layer][i][j].alive = true
                cells[layer][i][j].alpha = 1
            }
        }
    }

    /// A grid index clustered near the center (a small disk around it).
    private func seedCell() -> (Int, Int) {
        let p = ring(innerRadius: 0, outerRadius: 0.25)
        let i = Int(map(p.x, -1, 1, 0, Double(Self.gridSize - 1)).rounded())
        let j = Int(map(p.y, -1, 1, 0, Double(Self.gridSize - 1)).rounded())
        return (clampIndex(i), clampIndex(j))
    }
    private func clampIndex(_ v: Int) -> Int {
        Swift.max(0, Swift.min(Self.gridSize - 1, v))
    }

    override func draw() {
        background(.black)
        noStroke()
        let n = Self.gridSize
        let side = width / Double(n)
        let half = side / 2
        let center = Vector2(width / 2, height / 2)
        let t = time * 0.02   // slow color drift

        for layer in 0..<Self.layerCount {
            let off = map(Double(layer), 0, 3, 0.8, 1.2)
            for i in 0..<n {
                let cx = (Double(i) + 0.5) * side
                for j in 0..<n {
                    let step = cells[layer][i][j].alive ? 0.01 : -0.01
                    let alpha = Swift.max(0, Swift.min(1, cells[layer][i][j].alpha + step))
                    cells[layer][i][j].alpha = alpha
                    guard alpha > 0 else { continue }

                    let cy = (Double(j) + 0.5) * side
                    let diff = Vector2(cx, cy) - center
                    let ci = map(atan2(diff.y, diff.x), -.pi, .pi, 0, 1)
                    let hue = Palette.rainbow.color(at: ci * off + t)
                    // Fade toward black with the cell's life.
                    fill(Color(red: hue.red * alpha, green: hue.green * alpha, blue: hue.blue * alpha))

                    withState {
                        translate(cx, cy)
                        rotate(Double(layer) * .pi / 2)
                        drawTriangle(0, 0, side, half)   // wedge: apex at the cell center
                    }
                }
            }
        }

        if frameCount % 20 == 0 { stepLife() }
    }

    /// One Conway step per layer; cells that live too long die and reseed.
    private func stepLife() {
        let n = Self.gridSize
        for layer in 0..<Self.layerCount {
            for i in 0..<n {
                for j in 0..<n {
                    var neighbors = 0
                    for x in (i - 1)...(i + 1) {
                        for y in (j - 1)...(j + 1) {
                            if x == i && y == j { continue }
                            if x >= 0, x < n, y >= 0, y < n, cells[layer][x][y].alive { neighbors += 1 }
                        }
                    }
                    if neighbors < 2 || neighbors > 3 { cells[layer][i][j].alive = false }
                    if neighbors == 3 { cells[layer][i][j].alive = true }
                    if cells[layer][i][j].alive {
                        cells[layer][i][j].gen += 1
                    }
                    if cells[layer][i][j].gen > 60 {
                        cells[layer][i][j].alive = false
                        cells[layer][i][j].gen = 0
                        for _ in 0..<4 {
                            let (sx, sy) = seedCell()
                            cells[layer][sx][sy].alive = true
                        }
                    }
                }
            }
        }
    }
}
