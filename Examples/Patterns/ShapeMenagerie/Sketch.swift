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

    override func setup() {
        noStroke()
    }

    override func draw() {
        background(Color(white: 0.08))
        let rowGap = height / Double(rows + 1)
        let colGap = width / Double(columns + 1)

        for row in 0..<rows {
            let y = rowGap * Double(row + 1)
            for col in 0..<columns {
                let x = colGap * Double(col + 1)
                let t = Double(col) / Double(columns - 1)
                fill(Colormap.turbo.color(at: t))

                let size = map(t, 0, 1, 26, 92) * scale
                // 0…1 corner-rounding, offset per cell so the row ripples.
                let round = 0.5 - 0.5 * cos(time * 1.6 + Double(col) * 0.5 + Double(row) * 0.7)

                switch row {
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
}
