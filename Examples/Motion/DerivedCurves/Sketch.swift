import Foundation
import Ollin

/// One curve picked on the inspector, and the two curves derived from it: the
/// same curve run from its other end (`reversed()`), and the curve on the way
/// out with its reverse on the way back, squeezed into one trip (`mirrored()`).
/// Three dots make the same out-and-back journey, one per curve, beside a plot
/// of the shape each rides.
///
/// Pick an ease-in and the reversed row becomes its ease-out, the mirrored row
/// its ease-in-out, the catalog's own curves. Pick an ease-out and the mirrored
/// row is an out-in, fast at both ends and slow through the middle, which the
/// catalog does not carry. Pick a back or elastic ease-in and the mirrored row
/// is the plain construction rather than the catalog's tuned ease-in-out.
@main
final class DerivedCurves: Sketch {
    @Param var curve: Easing = .easeInQuad

    override func draw() {
        background(.white)

        // One trip out and back every three seconds, shared by the three rows.
        let u = pingPong(over: 3)

        let rows: [(label: String, curve: Easing)] = [
            ("curve", curve),
            ("curve.reversed()", curve.reversed()),
            ("curve.mirrored()", curve.mirrored()),
        ]

        let plot = width * 0.13
        let plotX = width * 0.08
        let left = width * 0.30, right = width * 0.92
        let dot = 26 * scale
        textSize(18 * scale)

        for (i, row) in rows.enumerated() {
            let y = height * (0.24 + Double(i) * 0.26)
            let top = y - plot / 2, bottom = y + plot / 2

            // The shape the dot rides, as a small plot with its diagonal.
            noFill()
            stroke(Color(white: 0.85)); strokeWeight(2 * scale)
            drawRect(plotX, top, plot, plot)
            drawLine(plotX, bottom, plotX + plot, top)
            stroke(.black); strokeWeight(3 * scale)
            drawPolyline(fractions(120, inclusive: true).map { t in
                Vector2(plotX + t * plot, bottom - row.curve(t) * plot)
            })

            // The track and the dot.
            stroke(Color(white: 0.85)); strokeWeight(2 * scale)
            drawLine(left, y, right, y)
            noStroke(); fill(.black)
            drawCircle(lerp(left, right, row.curve(u)), y, dot)

            fill(Color(white: 0.45))
            textAlign(.left, .bottom)
            drawText(row.label, left, top - 6 * scale)
        }
    }
}
