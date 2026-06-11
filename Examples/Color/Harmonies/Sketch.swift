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
        let contentWidth = width - margin * 2
        let rowHeight = height * 0.1
        let gap = (height - 5 * rowHeight) / 6
        let pad = 14.0
        for (row, entry) in rows.enumerated() {
            let y = gap + Double(row) * (rowHeight + gap)
            let n = entry.palette.count
            let swatchWidth = (contentWidth - Double(n - 1) * pad) / Double(n)
            for i in 0..<n {
                fill(entry.palette[i])
                drawRect(margin + Double(i) * (swatchWidth + pad), y,
                         swatchWidth, rowHeight, cornerRadius: 14)
            }
            fill(Color(hex: 0x9AA3AD))
            drawText(entry.label, margin, y - 14)
        }

        // The analogous set again, as a continuous gradient.
        let ramp = rows[3].palette.ramp(in: .oklch)
        let y = gap + 4 * (rowHeight + gap)
        let columns = 160
        for i in 0..<columns {
            let t = Double(i) / Double(columns - 1)
            fill(ramp.color(at: t))
            drawRect(margin + contentWidth * Double(i) / Double(columns), y,
                     contentWidth / Double(columns) + 1, rowHeight)
        }
        fill(Color(hex: 0x9AA3AD))
        drawText("ANALOGOUS.RAMP(IN: .OKLCH)", margin, y - 14)
    }
}
