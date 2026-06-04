import Ollin

/// The named regular-polygon helpers — `drawPentagon`, `drawHexagon`,
/// `drawHeptagon`, `drawOctagon` — laid out in a row, each labeled. They're sugar
/// over `drawNgon` with the side count fixed, so they draw the same analytic SDF
/// shape; the name just saves you the `sides:` argument. They turn slowly so they
/// read as live geometry rather than stamps.
@main
final class NamedPolygons: Sketch {
    let names = ["Pentagon", "Hexagon", "Heptagon", "Octagon"]

    override func setup() {
        noStroke()
    }

    override func draw() {
        background(Color(white: 0.1))
        let gap = width / Double(names.count + 1)
        let radius = 80 * scale
        textAlign(.center)
        textSize(22 * scale)

        for (i, name) in names.enumerated() {
            let x = gap * Double(i + 1)
            let y = height / 2

            fill(Colormap.viridis.color(at: Double(i) / Double(names.count - 1)))
            withState {
                translate(x, y)
                rotate(time * 0.4 + Double(i) * 0.6)
                switch i {
                case 0:  drawPentagon(0, 0, radius)
                case 1:  drawHexagon(0, 0, radius)
                case 2:  drawHeptagon(0, 0, radius)
                default: drawOctagon(0, 0, radius)
                }
            }

            fill(.white)
            drawText(name, x, y + radius + 50 * scale)
        }
    }
}
