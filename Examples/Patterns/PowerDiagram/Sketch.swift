import Ollin

/// Territories for things that have a size.
///
/// A Voronoi cell holds everywhere closer to its site than to any other. That is
/// the right question when the sites are points. It is the wrong one when they are
/// circles, because a big circle and a small one an equal distance apart do not
/// deserve an equal share: the boundary falls halfway, straight through the big
/// one.
///
/// A power diagram gives every site a weight and subtracts it from the squared
/// distance. Weight a circle by the square of its radius and the boundaries land
/// where the two circles would meet if they grew, so every circle that touches no
/// other sits inside its own cell. The cells are still convex, and they still tile
/// the region exactly.
///
/// Hold the mouse to see the plain Voronoi diagram of the same centers, ignoring
/// the sizes. Watch the big circles: their cells cut into them, which is the whole
/// argument for the weighting.
@main
final class PowerDiagram_Example: Sketch {
    override var loopDuration: Double? { 12 }

    private var circles: [Circle] = []

    override func setup() {
        seed(7)
        circles = packCircles(in: bounds.inset(by: 40), count: 90,
                              minRadius: 12, maxRadius: 95, padding: 6)
    }

    override func draw() {
        background(Color(hex: 0x0B0E14))
        let slide = loopProgress(over: 12)

        let cells: [Shape] = mouseIsPressed
            ? voronoi(circles.map(\.center), in: bounds).cells
            : powerDiagram(of: circles, in: bounds).cells

        strokeWeight(1.5)
        for (index, cell) in cells.enumerated() {
            // The golden ratio steps the hue so neighboring cells never share one.
            let t = (Double(index) * 0.6180339887 + slide).truncatingRemainder(dividingBy: 1)
            let paint = CosinePalette.rainbow.color(at: t)
            fill(paint.withAlpha(0.22))
            stroke(paint)
            drawShape(cell)
        }

        // The circles themselves, so it is obvious which ones a cell cuts into.
        noFill()
        stroke(Color(hex: 0xFFFFFF, alpha: 0.75))
        strokeWeight(2)
        for circle in circles { drawCircle(circle) }

        let lost = cells.filter { $0.contours.isEmpty }.count
        drawCaption(mouseIsPressed
            ? "the plain Voronoi diagram of the same centers: the cells cut through the big circles"
            : "\(cells.count - lost) cells from \(circles.count) circles, each one weighted by its own size")
    }
}
