// figure: frame=0 themed
//
// Guide diagram: the clock, wrapped. The top lane plots loopProgress(over: 3)
// against nine seconds of `time`: a saw that climbs from 0 to 1 over each
// three-second lap and snaps back, the lap boundaries ruled. The bottom lane
// plots pingPong(over: 3) over the same seconds: the fold, climbing to 1 at
// the middle of a lap and coming back down to 0 at its end. The dot on each
// lane marks the same moment, seven and a half seconds in.
import Ollin
import OllinDiagram

final class LoopProgress: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    let seconds = 9.0
    let period = 3.0
    let moment = 7.5

    override func draw() {
        background(theme.paper)
        textSize(20)

        lane(y: 60, height: 150, label: "loopProgress(over: 3)   =   fract(time / 3)") { t in
            (t / period).truncatingRemainder(dividingBy: 1)
        }
        lane(y: 300, height: 150, label: "pingPong(over: 3)") { t in
            let lap = (t / period).truncatingRemainder(dividingBy: 1)
            return 1 - abs(lap * 2 - 1)
        }

        // The shared ruler of seconds under the two lanes.
        fill(theme.ink)
        noStroke()
        textAlign(.center, .top)
        for second in 0...Int(seconds) {
            let x = xFor(Double(second))
            drawText("\(second)", x, 478)
        }
        textAlign(.left, .top)
        drawText("time, in seconds", 70, 508)
    }

    /// One plotted lane: the axis box, the lap boundaries, the curve, and the
    /// dot at the chosen moment.
    func lane(y top: Double, height: Double, label: String, _ value: (Double) -> Double) {
        let bottom = top + height

        // The lap boundaries, faint, and the axis.
        stroke(theme.ink(0.18))
        strokeWeight(1.5)
        var lapStart = 0.0
        while lapStart <= seconds {
            let x = xFor(lapStart)
            drawLine(x, top, x, bottom)
            lapStart += period
        }
        stroke(theme.ink(0.5))
        drawLine(xFor(0), bottom, xFor(seconds), bottom)
        drawLine(xFor(0), top, xFor(0), bottom)

        // The curve, sampled finely so the snap in the saw stays vertical.
        noFill()
        stroke(theme.ink)
        strokeWeight(3)
        var points: [Vector2] = []
        let samples = 900
        for i in 0...samples {
            let t = Double(i) / Double(samples) * seconds
            points.append(Vector2(xFor(t), bottom - value(t) * height))
        }
        drawPolyline(points)

        // The chosen moment.
        noStroke()
        fill(theme.accent)
        drawCircle(center: Vector2(xFor(moment), bottom - value(moment) * height), radius: 8)

        // The value labels and the lane's own label.
        fill(theme.ink)
        textAlign(.right, .middle)
        drawText("1", xFor(0) - 12, top)
        drawText("0", xFor(0) - 12, bottom)
        textAlign(.left, .bottom)
        drawText(label, xFor(0), top - 12)
    }

    func xFor(_ t: Double) -> Double {
        70 + t / seconds * 740
    }
}
