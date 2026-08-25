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
        let rowHeight = height * 0.062
        let gap = (height - Double(sets.count) * rowHeight) / Double(sets.count + 1)
        let step = Int(time * 3)
        // One grid gives the rows, and each row is its own grid of swatches.
        let rows = grid(columns: 1, rows: sets.count,
                        padding: .symmetric(horizontal: margin, vertical: gap), gutter: gap)
        for (row, entry) in sets.enumerated() {
            let frame = rows.cell(column: 0, row: row).frame
            let highlightIndex = (step + row) % entry.palette.count
            for cell in Grid(in: frame, columns: entry.palette.count, rows: 1, gutter: 8).cells {
                noStroke()
                fill(entry.palette[cell.column])
                drawRect(cell.frame, cornerRadius: 10)
                if cell.column == highlightIndex {
                    noFill()
                    stroke(.white)
                    strokeWeight(3)
                    drawRect(cell.frame.x - 5, cell.frame.y - 5,
                             cell.frame.width + 10, cell.frame.height + 10, cornerRadius: 13)
                }
            }
            noStroke()
            drawText(entry.label, frame.x, frame.y - 10, color: Color(hex: 0x9AA3AD))
        }
    }
}
