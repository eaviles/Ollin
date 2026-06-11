import Ollin

/// The built-in qualitative palettes as labeled swatch rows — the curated
/// sets `Palette` ships (the ColorBrewer qualitative families). A roaming
/// highlight steps through each row by wrapping index, the way
/// `palette[frameCount]` cycles.
@main
final class Swatchbook: Sketch {
    let sets: [(label: String, palette: Palette)] = [
        ("SET1", .set1),
        ("SET2", .set2),
        ("SET3", .set3),
        ("PAIRED", .paired),
        ("PASTEL1", .pastel1),
        ("PASTEL2", .pastel2),
        ("DARK2", .dark2),
        ("ACCENT", .accent),
    ]

    override func setup() {
        textSize(22)
    }

    override func draw() {
        background(Color(hex: 0x14171C))
        let margin = width * 0.08
        let contentWidth = width - margin * 2
        let rowHeight = height * 0.062
        let gap = (height - Double(sets.count) * rowHeight) / Double(sets.count + 1)
        let pad = 8.0
        let step = Int(time * 3)
        for (row, entry) in sets.enumerated() {
            let y = gap + Double(row) * (rowHeight + gap)
            let n = entry.palette.count
            let swatchWidth = (contentWidth - Double(n - 1) * pad) / Double(n)
            let highlightIndex = (step + row) % n
            for i in 0..<n {
                let highlighted = i == highlightIndex
                noStroke()
                fill(entry.palette[i])
                drawRect(margin + Double(i) * (swatchWidth + pad), y,
                         swatchWidth, rowHeight, cornerRadius: 10)
                if highlighted {
                    noFill()
                    stroke(.white)
                    strokeWeight(3)
                    drawRect(margin + Double(i) * (swatchWidth + pad) - 5, y - 5,
                             swatchWidth + 10, rowHeight + 10, cornerRadius: 13)
                }
            }
            noStroke()
            fill(Color(hex: 0x9AA3AD))
            drawText(entry.label, margin, y - 10)
        }
    }
}
