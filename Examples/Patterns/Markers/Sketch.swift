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
        let gutter = width * 0.16                 // left column reserved for labels
        let rowGap = height / Double(markers.count + 1)
        let colGap = (width - gutter) / Double(columns + 1)
        textSize(24 * scale)
        textAlign(.right, .middle)
        for (row, marker) in markers.enumerated() {
            pointMarker(marker)
            let y = rowGap * Double(row + 1)
            for col in 0..<columns {
                let x = gutter + colGap * Double(col + 1)
                let t = Double(col) / Double(columns - 1)
                fill(Colormap.turbo.color(at: t))
                let diameter = map(t, 0, 1, 10, 64) * scale
                let pulse = 1 + 0.2 * sin(time * 2 + Double(col) * 0.4 + Double(row) * 0.8)
                drawPoint(x, y, diameter * pulse)
            }
            fill(.white)
            drawText(name(marker), gutter - 24 * scale, y)
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
