import Ollin

/// L-systems: a tiny rewriting grammar unfolds into self-similar, branching
/// line-work. Each cell here is one built-in preset, fit to its frame: the
/// classic fractal curves (Koch, dragon, Hilbert, Gosper, Lévy, Peano,
/// Sierpinski) and the branching plants, plus one stochastic plant that grows a
/// different form for every seed.
///
/// The forms are a pure function of the grammar (and, for the stochastic plant,
/// the seed), so they're computed once and held rather than rebuilt each frame.
/// Every preset returns open `[Contour]`s, so the same line-work feeds stroking,
/// the shape booleans, hatching, and SVG export for the pen plotter.
@main
final class LSystemCatalog: Sketch {
    private struct Item { let system: LSystem; let iterations: Int; let hue: Double }
    private let items: [Item] = [
        Item(system: .kochCurve, iterations: 4, hue: 200),
        Item(system: .kochSnowflake, iterations: 4, hue: 190),
        Item(system: .sierpinskiTriangle, iterations: 6, hue: 30),
        Item(system: .sierpinskiArrowhead, iterations: 7, hue: 20),
        Item(system: .dragonCurve, iterations: 12, hue: 340),
        Item(system: .hilbertCurve, iterations: 5, hue: 280),
        Item(system: .gosperCurve, iterations: 4, hue: 260),
        Item(system: .levyCurve, iterations: 12, hue: 300),
        Item(system: .peanoCurve, iterations: 3, hue: 220),
        Item(system: .plant, iterations: 5, hue: 130),
        Item(system: .bush, iterations: 5, hue: 110),
        Item(system: .tree, iterations: 4, hue: 90),
        Item(system: .randomPlant, iterations: 6, hue: 150),
    ]

    private var cells: [(color: Color, contours: [Contour])] = []

    override func draw() {
        if cells.isEmpty {
            seed(7)
            let grid = grid(columns: 4, rows: 4, padding: .all(24 * scale), gutter: 16 * scale)
            cells = items.enumerated().map { i, item in
                let color = Color(hue: item.hue / 360, saturation: 0.5, brightness: 0.95)
                let line = lSystem(item.system, iterations: item.iterations,
                                   in: grid.cells[i].frame, padding: 10 * scale)
                return (color, line)
            }
        }

        background(Color(hex: 0x0E1013))
        strokeWeight(1.5 * scale)
        strokeCap(.round)
        noFill()

        for cell in cells {
            stroke(cell.color)
            for contour in cell.contours {
                drawPolyline(contour.points, closed: false)
            }
        }
    }
}
