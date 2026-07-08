// figure: frame=0
//
// Guide diagram (Appendix B): wrapping a growing clock. Three strips share
// one time axis: raw time rises forever, loopProgress wraps 0...1 every lap,
// and pingPong folds each lap out and back. One marked instant crosses all
// three.
import Ollin

final class Wrap: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.28)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)
    let accent = Color(hex: 0xE4572E)

    let left = 120.0, right = 760.0
    let seconds = 9.0, loop = 3.0
    let marked = 4.2

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(19)

        strip(top: 52, title: "time keeps growing") { t in t / seconds }
        strip(top: 196, title: "loopProgress(over: 3) wraps every lap") { t in fract(t / loop) }
        strip(top: 340, title: "pingPong(over: 3) goes out and back") { t in
            1 - abs(1 - 2 * fract(t / loop))
        }

        // The marked instant, threaded through all three strips.
        let x = left + marked / seconds * (right - left)
        stroke(accent.withAlpha(0.45))
        strokeWeight(2)
        var y = 52.0
        while y < 340 + 92 {
            drawLine(x, y, x, min(y + 9, 340 + 92))
            y += 18
        }
        noStroke()
        fill(ink)
        textAlign(.center, .top)
        drawText("time = 4.2", x, 340 + 92 + 12)
        drawText("one lap is 3 seconds, so 4.2 is 0.4 of the way through its second lap",
                 width / 2, 500)
    }

    func strip(top: Double, title: String, value: (Double) -> Double) {
        let bottom = top + 92
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(left, top, right - left, 92)

        var points: [Vector2] = []
        for i in 0...480 {
            let t = Double(i) / 480 * seconds
            points.append(Vector2(left + Double(i) / 480 * (right - left),
                                  bottom - value(t) * 84 - 4))
        }
        stroke(ink)
        strokeWeight(2.5)
        // Break the polyline where the value wraps, so the cliff edges of the
        // sawtooth stay vertical gaps instead of drawn drops.
        var run: [Vector2] = []
        for (i, p) in points.enumerated() {
            if let last = run.last, abs(p.y - last.y) > 60 {
                drawPolyline(run)
                run = []
            }
            run.append(p)
            if i == points.count - 1 { drawPolyline(run) }
        }

        let markedY = bottom - value(marked) * 84 - 4
        let markedX = left + marked / seconds * (right - left)
        noStroke()
        fill(accent)
        drawCircle(markedX, markedY, 8)
        fill(ink)
        textAlign(.right, .middle)
        drawText(String(format: "%.1f", value(marked) * (title.hasPrefix("time") ? seconds : 1)),
                 markedX - 14, markedY - 16)
        textAlign(.left, .middle)
        drawText(title, left, top - 18)
        textAlign(.right, .middle)
        fill(faint)
        drawText("1", left - 12, top + 8)
        drawText("0", left - 12, bottom - 4)
    }
}
