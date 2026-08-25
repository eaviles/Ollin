import Ollin

/// Color harmonies computed in OKLCH: a base color drifts around the hue
/// wheel while its complementary, split-complementary, triadic, and
/// analogous palettes follow, each row a set of swatches that hold the
/// base's lightness. The bottom strip ramps the analogous palette into a
/// smooth gradient with `palette.ramp(in: .oklch)`.
@main
final class Harmonies: Sketch {
    override func setup() {
        noStroke()
        textSize(26)
    }

    override func draw() {
        background(Color(hex: 0x14171C))
        let base = Color(OKHSL(h: time * 0.03, s: 0.85, l: 0.6))
        let rows: [(label: String, palette: Palette)] = [
            ("COMPLEMENTARY", .complementary(of: base)),
            ("SPLIT COMPLEMENTARY", .splitComplementary(of: base)),
            ("TRIADIC", .triadic(of: base)),
            ("ANALOGOUS", .analogous(of: base, count: 5)),
        ]

        let margin = width * 0.08
        let rowHeight = height * 0.1
        let gap = (height - 5 * rowHeight) / 6
        // Five band slots down the canvas: four harmony rows plus the ramp.
        let bands = grid(columns: 1, rows: 5,
                         padding: .symmetric(horizontal: margin, vertical: gap), gutter: gap)
        for (row, entry) in rows.enumerated() {
            let frame = bands.cell(column: 0, row: row).frame
            for cell in Grid(in: frame, columns: entry.palette.count, rows: 1, gutter: 14).cells {
                fill(entry.palette[cell.column])
                drawRect(cell.frame, cornerRadius: 14)
            }
            drawText(entry.label, frame.x, frame.y - 14, color: Color(hex: 0x9AA3AD))
        }

        // The analogous set again, as a continuous gradient.
        let ramp = rows[3].palette.ramp(in: .oklch)
        let band = bands.cell(column: 0, row: 4).frame
        let columns = 160
        for i in 0..<columns {
            fill(ramp.color(at: Double(i) / Double(columns - 1)))
            drawRect(band.x + band.width * Double(i) / Double(columns), band.y,
                     band.width / Double(columns) + 1, band.height)
        }
        drawText("ANALOGOUS.RAMP(IN: .OKLCH)", band.x, band.y - 14, color: Color(hex: 0x9AA3AD))
    }
}
