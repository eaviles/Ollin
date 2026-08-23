import Ollin

/// A slow back-and-forth is the most-written four lines in any sketch, so
/// `sway` is one: `sway(over: 4, in: 100...300)` leaves the low end, reaches
/// the high end halfway through the lap, and is back as the lap closes.
///
/// The five shapes are the five paths it can take between the ends. Each row
/// plots its own shape over one lap, with a dot riding it and a circle on the
/// right sized by the same call, live.
///
/// The plot is drawn with `sway` itself rather than with a copy of its
/// arithmetic. `phase` shifts the lap by a fraction of its length, so asking for
/// `phase: lap - time / duration` asks the shape what it reads at any point of
/// the lap, whatever the clock says.
///
/// Every shape closes its lap exactly, `.wander` included, which is why this
/// sketch can declare a `loopDuration` at all.
///
/// See Docs/Helpers/Animation.md.
@main
final class Sway: Sketch {
    static let lap = 6.0
    override var loopDuration: Double? { Sway.lap }

    static let shapes: [(SwayShape, String, String)] = [
        (.sine, ".sine", "no corners, slowest at the ends"),
        (.triangle, ".triangle", "one speed, a sharp turn at each end"),
        (.saw, ".saw", "a ramp and a jump back"),
        (.square, ".square", "one end or the other, nothing between"),
        (.wander, ".wander", "the noise field, and it still closes the lap"),
    ]

    let paper = Color(hex: 0xF4F1EA)
    let ink = Color(hex: 0x1E2028)
    let accent = Color(hex: 0xC9503A)

    override func setup() {
        textFont(OutlineFont.system)
    }

    override func draw() {
        background(paper)
        drawTitle()
        for (i, entry) in Sway.shapes.enumerated() { row(entry, at: i) }
    }

    // MARK: The rows

    static let left = 150.0, right = 750.0, top = 336.0, gap = 146.0, swing = 34.0

    /// What `shape` reads at `lap` of the way through its lap, asked of `sway`
    /// itself: the phase argument moves the question, so no arithmetic is
    /// repeated here.
    func value(of shape: SwayShape, at lap: Double,
               in range: ClosedRange<Double> = 0...1) -> Double {
        sway(over: Sway.lap, in: range, shape: shape, phase: lap - time / Sway.lap)
    }

    func row(_ entry: (shape: SwayShape, name: String, note: String), at index: Int) {
        let y = Sway.top + Double(index) * Sway.gap
        let lap = loopProgress(over: Sway.lap)

        noStroke()
        fill(ink)
        textSize(25)
        textAlign(.left, .center)
        drawText(entry.name, Sway.left, y - 80)
        fill(ink.withAlpha(0.42))
        textSize(19)
        drawText(entry.note, Sway.left + 132, y - 79)

        // The two ends the value travels between.
        stroke(ink.withAlpha(0.09))
        strokeWeight(1)
        drawLine(Sway.left, y - Sway.swing, Sway.right, y - Sway.swing)
        drawLine(Sway.left, y + Sway.swing, Sway.right, y + Sway.swing)

        plot(entry.shape, at: y)

        // The dot riding the curve, at the lap the clock is on.
        noStroke()
        fill(accent)
        drawCircle(x(of: lap), height(of: value(of: entry.shape, at: lap), at: y), 8)

        // And the same call driving something, live.
        stroke(ink.withAlpha(0.10))
        strokeWeight(1)
        drawLine(Sway.right + 16, y, 830, y)
        noStroke()
        fill(ink.withAlpha(0.85))
        drawCircle(886, y, sway(over: Sway.lap, in: 7...44, shape: entry.shape))
    }

    func x(of lap: Double) -> Double { lerp(Sway.left, Sway.right, lap) }

    /// A value of 0 sits on the low line and 1 on the high one.
    func height(of unit: Double, at y: Double) -> Double {
        y + Sway.swing - unit * Sway.swing * 2
    }

    /// The shape traced across one whole lap. The square is drawn as two runs so
    /// its jump reads as a jump rather than a steep line.
    func plot(_ shape: SwayShape, at y: Double) {
        noFill()
        stroke(ink.withAlpha(0.75))
        strokeWeight(2.5)
        let steps = 200
        var run: [Vector2] = []
        var previous = value(of: shape, at: 0)
        for i in 0...steps {
            let lap = Double(i) / Double(steps)
            let unit = value(of: shape, at: lap)
            if abs(unit - previous) > 0.5 && (shape == .square || shape == .saw) {
                drawPolyline(run)
                run = []
            }
            run.append(Vector2(x(of: lap), height(of: unit, at: y)))
            previous = unit
        }
        drawPolyline(run)
    }

    func drawTitle() {
        noStroke()
        fill(ink)
        textSize(42)
        textAlign(.left, .top)
        drawText("Five ways to go there and back", Sway.left, 120)
        fill(ink.withAlpha(0.45))
        textSize(22)
        drawText("sway(over: \(Int(Sway.lap)), in: 7...44, shape: …), plotted over one lap",
                 Sway.left, 178)
    }
}
