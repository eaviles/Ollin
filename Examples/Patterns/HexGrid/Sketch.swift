import Ollin

/// A honeycomb pulse: a pointy-top `HexGrid` where each cell's brightness
/// follows its hex distance from the center, so a wave radiates outward in
/// perfect rings (equal hex distance is exactly what `distance(from:to:)`
/// measures). Move the mouse to pick a hexagon (`cell(at:)` snaps a point to
/// its hex) and the wave re-centers on it, with its neighbor ring lifted.
@main
final class HexGridPulse: Sketch {
    override var loopDuration: Double? { 6 }

    override func draw() {
        background(Color(hex: 0x101318))
        let grid = hexGrid(columns: 15, rows: 13, padding: .all(50 * scale), gutter: 6 * scale)

        // The wave radiates from the hovered hexagon when the mouse is over
        // the grid, else from the middle cell.
        let home = grid.cell(column: grid.columns / 2, row: grid.rows / 2)
        let focus = grid.cell(at: mouse) ?? home
        let neighbors = grid.neighbors(of: focus)

        let phase = loopProgress(over: 6)
        noStroke()
        for cell in grid.cells {
            let rings = Double(grid.distance(from: focus, to: cell))
            let wave = pingPong(over: 1, phase: phase - rings * 0.08)
            fill(Color.mix(Color(hex: 0x15414B), Color(hex: 0x7BE0C8), wave * wave))
            drawPolygon(cell.corners)
        }

        // The picked hexagon and its ring, drawn on top.
        noFill()
        strokeWeight(4 * scale)
        stroke(Color(hex: 0xF6511D))
        drawPolygon(focus.corners)
        stroke(Color(hex: 0xF6511D).withAlpha(0.45))
        for cell in neighbors { drawPolygon(cell.corners) }
    }
}
