import Ollin

/// `strokeDash(_:)` cuts a stroke into dashes. The pattern is a list of lengths,
/// dash then gap, in the path's own units, and a phase slides it along the path,
/// which is all a marching outline is. Every dash is a stroke of its own, so the
/// caps finish each one, and a zero-length dash under round caps is a dot.
///
/// The cut happens before the path is expanded, so the other stroke tools keep
/// working on the whole path: a width profile tapers across the gaps instead of
/// starting over at every dash, and an along-path gradient runs on through them.
/// The analytic shapes hand their outline to the same path while a dash is on,
/// which is why the rings and the star dash the way a polyline does.
///
/// Every cell shares one weight and one clock, and only the pattern changes.
@main
final class DashedStrokes: Sketch {
    let names = ["marching", "dots", "rings", "pattern", "taper", "gradient"]

    override func draw() {
        background(Color(white: 0.09))
        noFill()

        let grid = Grid(in: bounds, columns: 3, rows: 2, padding: .all(60 * scale))
        for cell in grid.cells {
            let i = cell.row * 3 + cell.column
            let radius = min(cell.frame.width, cell.frame.height) * 0.36
            // How far the pattern has walked: the clock at a pace set by the cell.
            let travel = time * radius * 0.4

            withState {
                translate(cell.center.x, cell.center.y - radius * 0.12)
                stroke(rowColor(i, of: names.count))
                strokeWeight(radius * 0.06)
                switch i {
                case 0:
                    // The ants: one pattern, its phase moving with the clock.
                    strokeDash([radius * 0.16, radius * 0.1], phase: travel)
                    drawRect(Rectangle(x: -radius, y: -radius * 0.7, width: radius * 2, height: radius * 1.4),
                             cornerRadius: radius * 0.2)
                case 1:
                    // Dots are zero-length dashes, and the round cap is the dot.
                    strokeCap(.round)
                    strokeWeight(radius * 0.09)
                    strokeDash(.dots(spacing: radius * 0.18, phase: travel * 0.5))
                    drawPolyline(spiral(radius: radius))
                case 2:
                    // Two rings turning against each other, from the phase's sign.
                    strokeDash(.dashes(radius * 0.25, gap: radius * 0.12, phase: -travel))
                    drawCircle(0, 0, radius)
                    strokeDash(.dashes(radius * 0.12, gap: radius * 0.12, phase: travel))
                    drawCircle(0, 0, radius * 0.6)
                case 3:
                    // A four-length pattern, long dash and short, on a closed star.
                    strokeDash([radius * 0.3, radius * 0.08, radius * 0.06, radius * 0.08], phase: travel)
                    drawStar(0, 0, radius, radius * 0.5, points: 5)
                case 4:
                    // The taper reads the whole path, so the dashes shrink together.
                    // A round cap reaches half the weight past each end, so the gap
                    // is cut wider than the weight to stay open at full width.
                    strokeCap(.round)
                    strokeWeight(radius * 0.2)
                    strokeProfile(.taper(start: 1, end: 0))
                    strokeDash([radius * 0.2, radius * 0.32], phase: travel)
                    drawPolyline(spiral(radius: radius))
                default:
                    // An along-path gradient runs on through the gaps.
                    strokeWeight(radius * 0.12)
                    stroke(Gradient.alongPath([.red, .yellow, .white]))
                    strokeDash([radius * 0.14, radius * 0.06], phase: travel)
                    drawPolyline(spiral(radius: radius))
                }
            }
            label(names[i], at: Vector2(cell.center.x, cell.center.y + radius * 1.28))
        }
    }

    /// An open spiral of nearly two turns, sampled densely, so the dashes have a
    /// path that bends through every direction to lie along.
    func spiral(radius: Double) -> [Vector2] {
        let turns = 1.85
        return (0...260).map { i in
            let t = Double(i) / 260
            let angle = t * .tau * turns - .pi / 2
            return Vector2(angle: angle) * (radius * (0.22 + 0.78 * t))
        }
    }

    /// A caption under each cell, drawn unstroked so no pattern reaches the text.
    func label(_ text: String, at p: Vector2) {
        withState {
            noStroke(); fill(.white); textAlign(.center, .baseline); textSize(22 * scale)
            drawText(text, p.x, p.y)
        }
    }

    func rowColor(_ i: Int, of count: Int) -> Color {
        Colormap.turbo.color(at: 0.18 + 0.72 * Double(i) / Double(count - 1))
    }
}
