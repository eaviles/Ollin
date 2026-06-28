import Ollin

/// The eight perceptual `Colormap` ramps, each drawn as a horizontal band from
/// `0` on the left to `1` on the right. These map a value to color in a way the
/// eye reads evenly — reach for one whenever a number needs to become color.
@main
final class Colormaps: Sketch {
    let maps = Colormap.allCases

    override func setup() {
        noStroke()
    }

    override func draw() {
        background(.black)
        let g = grid(columns: 256, rows: maps.count)
        for cell in g.cells {
            let t = Double(cell.column) / Double(g.columns - 1)
            fill(maps[cell.row].color(at: t))
            drawRect(cell.frame)
        }
    }
}
