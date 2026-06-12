import Ollin

/// `strokeAlign(_:)` sets where a shape's stroke sits on its outline: `.inside`
/// (entirely within, so the footprint stays fixed), `.center` (the default —
/// half in, half out), or `.outside` (entirely beyond the edge, so the footprint
/// grows by the weight). The three columns — inside, center, outside, left to
/// right — draw the same shapes under each. The pale fill marks the true
/// outline; the thick stroke pulses its weight with `time`, so you can watch the
/// inside column hold its footprint while the outside column balloons. On these
/// analytic SDF shapes the inset/outset is a geometrically exact offset.
@main
final class StrokeAlignment: Sketch {
    let aligns: [StrokeAlign] = [.inside, .center, .outside]
    let names = ["inside", "center", "outside"]
    let rows = 3

    override func draw() {
        background(Color(white: 0.1))

        let pulse = 0.5 - 0.5 * cos(time * 1.6)
        strokeWeight((6 + 22 * pulse) * scale)

        let colGap = width / Double(aligns.count)
        let rowGap = height / Double(rows + 1)
        let r = min(colGap, rowGap) * 0.30

        for (col, align) in aligns.enumerated() {
            strokeAlign(align)
            let cx = colGap * (Double(col) + 0.5)
            stroke(Colormap.turbo.color(at: Double(col) / Double(aligns.count - 1)))

            // Column header (drawn unstroked so the pulsing weight doesn't reach it).
            withState {
                noStroke(); fill(.white); textAlign(.center, .middle); textSize(30 * scale)
                drawText(names[col], cx, rowGap * 0.45)
            }

            for row in 0..<rows {
                let cy = rowGap * Double(row + 1)
                fill(Color(white: 0.32))                 // marks the geometric edge
                switch row {
                case 0: drawCircle(cx, cy, r)
                case 1: drawRect(cx - r, cy - r, r * 2, r * 2, cornerRadius: r * 0.25)
                default: drawStar(cx, cy, r, r * 0.55, points: 6)
                }
            }
        }
    }
}
