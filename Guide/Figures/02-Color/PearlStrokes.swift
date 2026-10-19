// figure: frame=0
//
// Guide figure (Chapter 2): the color of a thin film, on the CPU. A ruler of
// Color.interference from 0 to 1,200 nanometers with the thicknesses marked,
// and under it four strokes that each walk a span of that ruler along their
// length through an .alongPath ramp, so a film's color order becomes a mark.
import Ollin

final class PearlStrokes: Sketch {
    override var canvasSize: CanvasSize { .size(880, 420) }

    override func draw() {
        background(Color(hex: 0x15161B))

        let left = 60.0, right = 820.0, rulerY = 40.0, rulerH = 44.0
        noStroke()
        let steps = 240
        for i in 0..<steps {
            let t = Double(i) / Double(steps)
            fill(Color.interference(thickness: t * 1200))
            drawRect(left + (right - left) * t, rulerY, (right - left) / Double(steps) + 1, rulerH)
        }
        textFont(.system)
        fill(Color(white: 0.6))
        textSize(15)
        textAlign(.center, .top)
        for nm in stride(from: 0, through: 1200, by: 200) {
            let x = left + (right - left) * Double(nm) / 1200
            drawRect(x - 0.5, rulerY + rulerH, 1, 6)
            drawText("\(nm) nm", x, rulerY + rulerH + 9)
        }

        noFill()
        strokeCap(.round)
        strokeJoin(.round)
        let spans: [(Double, Double)] = [(100, 420), (250, 700), (400, 950), (120, 1200)]
        for (row, span) in spans.enumerated() {
            let y = 170 + Double(row) * 62
            let ramp = Ramp((0...32).map { i in
                Color.interference(thickness: span.0 + (span.1 - span.0) * Double(i) / 32)
            })
            stroke(.alongPath(ramp))
            strokeWeight(30 - Double(row) * 3)
            let points = (0...40).map { i -> Vector2 in
                let t = Double(i) / 40
                return Vector2(left + (right - 170 - left) * t, y + sin(t * 9.4 + Double(row) * 1.3) * 11)
            }
            drawCurve(points)
        }
        fill(Color(white: 0.6))
        noStroke()
        textAlign(.right, .middle)
        for (row, span) in spans.enumerated() {
            drawText("\(Int(span.0)) to \(Int(span.1)) nm", right, 170 + Double(row) * 62)
        }
    }
}
