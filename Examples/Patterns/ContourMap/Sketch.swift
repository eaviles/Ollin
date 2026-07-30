import Ollin

/// A topographic map of a noise field, redrawn live.
///
/// `isolines(at:in:resolution:)` traces the level curves of any scalar field
/// by marching squares; stacked levels of one `fbm` terrain read as a
/// contour map, with every fifth line heavier, the cartographer's index
/// contour. The field uses looping noise, so the terrain drifts like weather
/// and returns home each lap:
///
/// ```sh
/// swift run Example-Patterns-ContourMap --export-loop /tmp/contourmap.gif
/// ```
///
/// Pure line work: `--export-svg` writes each curve as a plottable path.
@main
final class ContourMap_Example: Sketch {
    private let period = 12.0
    override var loopDuration: Double? { period }

    private let paper = Color(hex: 0xF4EFE6)
    private let ink = Color(hex: 0x2F3B52)

    override func setup() {
        seed(11)
    }

    override func draw() {
        background(paper)
        let frame = canvasRectangle.inset(by: 84)
        let phase = loopProgress(over: period)

        // The grid is sized so the field's features span many cells: the
        // traced chords stay short against the terrain, and the looping
        // field stays affordable to resample every frame.
        let levels = Array(stride(from: 0.32, through: 0.68, by: 0.04))
        let groups = isolines(at: levels, in: frame, resolution: 80) { p in
            fbm(p.x * 0.004, p.y * 0.004, loop: phase, radius: 0.5, octaves: 3)
        }

        noFill()
        for (i, group) in groups.enumerated() {
            let major = i % 5 == 0
            stroke(major ? ink : ink.withAlpha(0.62))
            strokeWeight((major ? 2.0 : 0.9) * scale)
            for curve in group {
                drawPolyline(curve.points, closed: curve.isClosed)
            }
        }

        // The map sheet's neat line.
        stroke(ink)
        strokeWeight(1.2 * scale)
        drawRect(frame.x, frame.y, frame.width, frame.height)

        drawCaption("level curves of a looping noise field")
    }
}
