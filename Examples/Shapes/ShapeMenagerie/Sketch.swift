import Ollin

/// The newest analytic SDF shapes — rhombus, vesica, moon, cross, ring — one per
/// row, each sweeping across a range of sizes. For the four roundable shapes the
/// corner radius breathes with time, so you can watch sharp corners fillet to
/// round and back; the ring (a full annulus has no corners) breathes its
/// thickness instead. Every cell is a single instanced quad, so the whole grid
/// is effectively free.
@main
final class ShapeMenagerie: Sketch {
    let rows = 5
    let columns = 9
    let names = ["Rhombus", "Vesica", "Moon", "Cross", "Ring"]

    override func setup() {
        noStroke()
    }

    override func draw() {
        background(Color(white: 0.08))
        // The left strip holds the row labels; the shapes span the rest in evenly
        // spaced interior points, so the grid is inset one gap off each edge plus
        // the label strip on the left.
        let labelStrip = width * 0.16
        let colGap = (width - labelStrip) / Double(columns + 1)
        let rowGap = height / Double(rows + 1)
        let g = grid(columns: columns, rows: rows,
                     padding: Insets(top: rowGap, right: colGap, bottom: rowGap, left: labelStrip + colGap),
                     distribution: .spanning)
        textSize(24 * scale)
        textAlign(.right, .middle)

        for p in g.points {
            let x = p.position.x, y = p.position.y
            if p.column == 0 {                        // one label per row, in the left strip
                fill(.white)
                drawText(names[p.row], labelStrip - 24 * scale, y)
            }

            let t = Double(p.column) / Double(columns - 1)
            fill(Colormap.turbo.color(at: t))

            let size = map(t, 0, 1, 26, 92) * scale
            // 0…1 corner-rounding, offset per cell so the row ripples.
            let round = 0.5 - 0.5 * cos(time * 1.6 + Double(p.column) * 0.5 + Double(p.row) * 0.7)

            switch p.row {
            case 0:   // rhombus (square diamond), corners breathing
                drawRhombus(x, y, size, size, cornerRadius: round * size / 2)
            case 1:   // vesica (vertical pointed lens), tips breathing
                let w = size * 0.62
                drawVesica(x, y, w, size * 1.25, cornerRadius: round * w / 2)
            case 2:   // crescent moon, cusps breathing
                let r = size / 2
                drawMoon(x, y, r, r * 0.92, r * 0.62, cornerRadius: round * r * 0.4)
            case 3:   // cross (plus), outer corners breathing
                let thickness = size * 0.36
                drawCross(x, y, size, thickness, cornerRadius: round * thickness / 2)
            default:  // ring, thickness breathing (no corners to round)
                let outer = size / 2
                drawRing(x, y, outer * (0.25 + 0.5 * round), outer)
            }
        }
    }
}
