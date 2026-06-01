import Ollin

/// The analytic SDF shapes that fit a canonical form parameterized by a size and
/// a ratio or two — trapezoid, parallelogram, egg, heart, cut disk, and a tapered
/// (uneven) capsule — laid out one per cell. Each is a single instanced quad with
/// fill, stroke, and anti-aliasing derived in the fragment, so the whole cabinet
/// is effectively free. They spin slowly in place to show the transform stack
/// rotating an SDF primitive (anti-aliasing stays ~1px under any rotation).
@main
final class ShapeCabinet: Sketch {
    let columns = 3
    let rows = 2

    override func setup() {
        strokeWeight(3 * scale)
    }

    override func draw() {
        background(Color(white: 0.08))
        let colGap = width / Double(columns)
        let rowGap = height / Double(rows)
        let s = min(colGap, rowGap)

        for index in 0..<(rows * columns) {
            let col = index % columns
            let row = index / columns
            let x = colGap * (Double(col) + 0.5)
            let y = rowGap * (Double(row) + 0.5)
            fill(Colormap.turbo.color(at: Double(index) / Double(rows * columns - 1)))
            stroke(Color(white: 0.95))

            withState {
                translate(Vector2(x, y))
                rotate(time * 0.4)
                draw(index, unit: s)
            }
        }
    }

    /// Each shape sized off `unit` (the cell's short side) and centered on the
    /// origin (the cell was translated there).
    private func draw(_ index: Int, unit: Double) {
        let u = unit * 0.34
        switch index {
        case 0: drawTrapezoid(0, 0, u * 1.0, u * 1.8, u * 1.4)   // narrow top, wide base
        case 1: drawParallelogram(0, 0, u * 1.5, u * 1.4, u * 0.6)
        case 2: drawEgg(0, 0, u * 0.9, u * 0.45)                 // fat bottom, narrow top
        case 3: drawHeart(0, 0, u * 1.9)
        case 4: drawCutDisk(0, 0, u, -u * 0.15)                  // dome, flat edge down
        default:                                                  // tapered capsule
            drawUnevenCapsule(Vector2(-u, u * 0.7), Vector2(u, -u * 0.7), u * 0.55, u * 0.18)
        }
    }
}
