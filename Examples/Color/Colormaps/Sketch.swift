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
        let bandHeight = height / Double(maps.count)
        let columns = 256
        let columnWidth = width / Double(columns)
        for (row, map) in maps.enumerated() {
            for i in 0..<columns {
                let t = Double(i) / Double(columns - 1)
                fill(map.color(at: t))
                drawRect(Double(i) * columnWidth, Double(row) * bandHeight,
                     columnWidth + 1, bandHeight)
            }
        }
    }
}
