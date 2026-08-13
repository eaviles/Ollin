import Ollin

/// Parametric L-systems: the same rewriting grammar as an ordinary L-system, but
/// every symbol carries numbers and every rule does arithmetic on them.
///
/// That is what each cell here is showing off. A plain grammar can only pick
/// which symbols come next, so every length it draws is a whole multiple of one
/// step; a parametric one carries the length itself. So a segment can be exactly
/// three tenths of its parent (top left), a bud can count down a few seasons
/// before it opens (top middle), and a trunk can be told its own width as well
/// as its own length (bottom right, the only cell drawn with `tapered`).
///
/// The forms are a pure function of the grammar, and of the seed for the
/// stochastic one, so they are worked out once and held rather than rebuilt each
/// frame. Every cell but the last comes back as open `[Contour]`s, so the same
/// line-work feeds stroking, the shape booleans, hatching, and SVG export for
/// the pen plotter.
@main
final class ParametricLSystemCatalog: Sketch {
    private struct Item {
        let system: ParametricLSystem
        let iterations: Int
        let hue: Double
        let tapered: Bool
        init(_ system: ParametricLSystem, _ iterations: Int, _ hue: Double, tapered: Bool = false) {
            self.system = system
            self.iterations = iterations
            self.hue = hue
            self.tapered = tapered
        }
    }

    private let items: [Item] = [
        Item(.triangleCurve, 6, 200),
        Item(.delayedTriangleCurve, 10, 190),
        Item(.snowflake, 5, 210),
        Item(.selfSimilarBranch, 9, 150),
        Item(.compoundLeaf, 16, 120),
        Item(.alternatingLeaf, 20, 110),
        Item(.mesotonicBranch, 14, 90),
        Item(.randomBranch, 9, 60),
        Item(.taperedTree(), 10, 30, tapered: true),
    ]

    private var cells: [(color: Color, contours: [Contour], marks: [StrokeMark])] = []

    override func draw() {
        if cells.isEmpty {
            seed(11)
            let grid = grid(columns: 3, rows: 3, padding: .all(24 * scale), gutter: 14 * scale)
            cells = items.enumerated().map { i, item in
                let color = Color(hue: item.hue / 360, saturation: 0.45, brightness: 0.95)
                let frame = grid.cells[i].frame
                let padding = 14 * scale
                if item.tapered {
                    return (color, [], lSystemMarks(item.system, iterations: item.iterations,
                                                    in: frame, padding: padding))
                }
                return (color, lSystem(item.system, iterations: item.iterations,
                                       in: frame, padding: padding), [])
            }
        }

        background(Color(hex: 0x0E1013))
        strokeCap(.round)
        strokeJoin(.round)
        noFill()

        for cell in cells {
            stroke(cell.color)
            strokeWeight(1.4 * scale)
            for contour in cell.contours {
                drawPolyline(contour.points, closed: false)
            }
            // A mark carries a width at every point of it, so the trunk of the
            // tapered tree is `strokeWeight` and every twig is a fraction of it.
            strokeWeight(11 * scale)
            for mark in cell.marks { drawMark(mark) }
        }
    }
}
