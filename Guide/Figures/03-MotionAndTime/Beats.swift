// figure: frame=540 themed
//
// Guide diagram: the three timers, charted against a ruler of seconds. Each
// lane stamps a mark on the frame its own question answers yes. every(1) lands
// on every tick, the phase-shifted copy lands between them, and after(4) lands
// once. Rendered at nine seconds, by which time the eight-second window is
// full.
import Ollin

final class Beats: Sketch {
    override var canvasSize: CanvasSize { .size(880, 460) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var faint: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.28) }
    var pale: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.12) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }

    /// Seconds the chart has room for.
    let window = 8.0
    let left = 120.0, right = 800.0

    var onTheSecond: [Double] = []
    var offTheBeat: [Double] = []
    var once: [Double] = []

    override func setup() {
        textFont(OutlineFont.system)
        onTheSecond = []
        offTheBeat = []
        once = []
    }

    override func draw() {
        if every(1), time <= window { onTheSecond.append(time) }
        if every(1, phase: 0.5), time <= window { offTheBeat.append(time) }
        if after(4) { once.append(time) }

        background(paper)
        drawRuler()
        lane("every(1)", at: 150, marks: onTheSecond, filled: true)
        lane("every(1, phase: 0.5)", at: 260, marks: offTheBeat, filled: false)
        lane("after(4)", at: 370, marks: once, filled: true)
    }

    func x(of second: Double) -> Double { lerp(left, right, second / window) }

    func drawRuler() {
        stroke(pale)
        strokeWeight(1)
        for second in 0...Int(window) {
            drawLine(x(of: Double(second)), 105, x(of: Double(second)), 405)
        }
        noStroke()
        fill(faint)
        textSize(17)
        textAlign(.center, .top)
        for second in stride(from: 0, through: Int(window), by: 2) {
            drawText("\(second)s", x(of: Double(second)), 415)
        }
    }

    func lane(_ name: String, at y: Double, marks: [Double], filled: Bool) {
        noStroke()
        fill(faint)
        textSize(19)
        textAlign(.left, .center)
        drawText(name, left, y - 42)

        stroke(pale)
        strokeWeight(2)
        drawLine(left, y, right, y)

        for second in marks {
            let point = Vector2(x(of: second), y)
            if filled {
                noStroke()
                fill(name.hasPrefix("after") ? accent : ink)
                drawCircle(center: point, radius: 11)
            } else {
                noFill()
                stroke(accent)
                strokeWeight(3)
                drawCircle(center: point, radius: 10)
            }
        }
    }
}
