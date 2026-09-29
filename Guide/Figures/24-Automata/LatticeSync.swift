// figure: frame=300
//
// Guide figure (Chapter 24): oscillators on a lattice. The section's fragment
// as a sketch: a hex grid of 24 by 20 oscillators, each listening only to the
// cells beside it. Hue is each cell's phase and saturation how closely it
// agrees with its neighbors. Five seconds in, with the seed fixed, so the
// figure renders the same everywhere.
import Ollin

final class LatticeSync: Sketch {
    var grid: HexGrid { hexGrid(columns: 24, rows: 20) }
    let sync = Kuramoto(columns: 24, rows: 20, layout: .hex, coupling: 3, spread: 0.3, range: 1, seed: 7)

    override func draw() {
        background(Color(hex: 0x101318))
        sync.advance()
        let locked = sync.localCoherence
        for (i, cell) in grid.enumerated() {
            fill(Color(hue: sync.phases[i] / .tau, saturation: locked[i], brightness: 0.9))
            drawPolygon(cell.corners)
        }
    }
}
