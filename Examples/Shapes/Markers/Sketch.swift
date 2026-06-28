import Ollin

/// The five `drawPoint` markers — circle, square, diamond, cross, x — one per
/// row. Each row sweeps its marker across a range of sizes, gently pulsing with
/// time, so you can see they share a footprint and stay crisp at any size. The
/// glyph is set once per row with `pointMarker(_:)`, then a run of `drawPoint`s
/// stamps it — the way a scatter plot picks a marker once and reuses it.
@main
final class Markers: Sketch {
    let markers = PointMarker.allCases   // circle, square, diamond, cross, x
    let columns = 13

    override func setup() {
        noStroke()
    }

    override func draw() {
        background(Color(white: 0.08))
        // The left strip holds the row labels; each marker row spans the rest in
        // evenly spaced interior points (the grid is inset one gap off each edge,
        // plus the label strip on the left).
        let labelStrip = width * 0.16
        let colGap = (width - labelStrip) / Double(columns + 1)
        let rowGap = height / Double(markers.count + 1)
        let g = grid(columns: columns, rows: markers.count,
                     padding: Insets(top: rowGap, right: colGap, bottom: rowGap, left: labelStrip + colGap),
                     distribution: .spanning)
        textSize(24 * scale)
        textAlign(.right, .middle)
        for p in g.points {
            let marker = markers[p.row]
            pointMarker(marker)                       // the row's glyph, set per stamp
            let x = p.position.x, y = p.position.y
            if p.column == 0 {                        // one label per row, in the left strip
                fill(.white)
                drawText(name(marker), labelStrip - 24 * scale, y)
            }
            let t = Double(p.column) / Double(columns - 1)
            fill(Colormap.turbo.color(at: t))
            let diameter = map(t, 0, 1, 10, 64) * scale
            let pulse = 1 + 0.2 * sin(time * 2 + Double(p.column) * 0.4 + Double(p.row) * 0.8)
            drawPoint(x, y, diameter * pulse)
        }
    }

    private func name(_ marker: PointMarker) -> String {
        switch marker {
        case .circle:  return "Circle"
        case .square:  return "Square"
        case .diamond: return "Diamond"
        case .cross:   return "Cross"
        case .x:       return "X"
        }
    }
}
