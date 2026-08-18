import Ollin

/// A wall of superellipse plates: one exponent slides the whole family. Each
/// column raises the Lamé exponent `n`, so the plates sweep from pinched star
/// through diamond, ellipse, and squircle to an almost-rectangle; each row
/// changes the aspect. The exponent breathes a little with time, so the wall
/// leans together toward round and back toward square.
@main
final class Superellipse: Sketch {
    override func draw() {
        background(Color(hex: 0xF4EFE7))

        let columns = 6, rows = 5
        let cells = grid(columns: columns, rows: rows, padding: .all(70 * scale)).cells
        let plate = Color(hex: 0x23425F)
        let rim = Color(hex: 0xC96F4A)
        let lean = sin(time * 0.6) * 0.3   // the whole wall breathes

        for cell in cells {
            // Left column pinches (n < 1), right column squares up.
            let sweep = Double(cell.column) / Double(columns - 1)
            let n = pow(2.0, -1 + sweep * 4.5 + lean)      // ~0.5 ... ~16
            let aspect = 1 - Double(cell.row) * 0.12       // rows flatten

            let inset = cell.frame.inset(by: .all(14 * scale))
            let outline = superellipse(width: inset.width,
                                       height: inset.height * aspect, n: n)

            withState {
                translate(inset.center.x, inset.center.y)
                fill(plate)
                noStroke()
                drawShape(Shape(contours: [outline]))
                stroke(rim)
                strokeWeight(3 * scale)
                noFill()
                drawPolyline(outline.points, closed: true)
            }
        }
    }
}
