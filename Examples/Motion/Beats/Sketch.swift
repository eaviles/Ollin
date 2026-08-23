import Ollin

/// A periodic event does not need a counter of its own. `every(seconds)` is
/// true on the one frame that crosses each multiple of that many seconds,
/// `after(seconds)` is true on the one frame that crosses a single moment, and
/// `everyFrames(n)` counts frames instead of seconds.
///
/// Four lanes fill left to right over a twelve-second lap, one mark per beat.
/// The top three are told in seconds, so their marks land under the same ruler
/// ticks whatever the window is doing. The bottom one is told in frames, so it
/// lands under those ticks only while the window holds sixty a second, and
/// drifts the moment it does not. The lap clears itself on `every(12)`.
///
/// See Docs/Helpers/Animation.md.
@main
final class Beats: Sketch {
    /// Seconds in one pass across the canvas.
    static let lap = 12.0

    /// A row of the chart: what it is called, how it beats, and how it draws.
    struct Lane {
        var name: String
        var mark: Mark
        var marks: [Double] = []        // the lap position of each beat so far
    }

    enum Mark { case disc, ring, tick, square }

    var lanes = [Lane(name: "every(1)", mark: .disc),
                 Lane(name: "every(1, phase: 0.5)", mark: .ring),
                 Lane(name: "every(0.25)", mark: .tick),
                 Lane(name: "everyFrames(60)", mark: .square)]

    /// Set once, by the one-shot, and never unset.
    var opened = false

    let ink = Color(red: 0.10, green: 0.11, blue: 0.15, alpha: 1)
    let warm = Color(red: 0.86, green: 0.33, blue: 0.20, alpha: 1)
    let cool = Color(red: 0.25, green: 0.45, blue: 0.80, alpha: 1)

    override func setup() {
        textFont(OutlineFont.system)
    }

    override func draw() {
        // The lap that owns the chart is itself a beat, so the clearing rule is
        // the same rule the marks are made of.
        if every(Beats.lap) { for i in lanes.indices { lanes[i].marks = [] } }
        if after(4) { opened = true }

        let at = loopProgress(over: Beats.lap)
        if every(1) { lanes[0].marks.append(at) }
        if every(1, phase: 0.5) { lanes[1].marks.append(at) }
        if every(0.25) { lanes[2].marks.append(at) }
        if everyFrames(60) { lanes[3].marks.append(at) }

        background(.white)
        drawTitle()
        drawRuler()
        for (i, lane) in lanes.enumerated() { drawLane(lane, row: i) }
        drawPlayhead(at)
        drawOneShot()
    }

    // MARK: The chart

    func drawTitle() {
        noStroke()
        fill(ink)
        textSize(40)
        textAlign(.left, .top)
        drawText("Beats the clock gives you", Beats.left, 122)
        fill(ink.withAlpha(0.45))
        textSize(24)
        drawText("one mark per beat, filling a \(Int(Beats.lap))-second lap", Beats.left, 182)
    }

    static let left = 150.0, right = 930.0, top = 340.0, gap = 150.0

    /// Where a lap position sits across the canvas.
    func x(of position: Double) -> Double {
        lerp(Beats.left, Beats.right, position)
    }

    /// A tick per second, so the eye can check a beat against the clock.
    func drawRuler() {
        textSize(22)
        for second in 0...Int(Beats.lap) {
            let tx = x(of: Double(second) / Beats.lap)
            stroke(ink.withAlpha(second % 2 == 0 ? 0.30 : 0.12))
            strokeWeight(1)
            drawLine(tx, Beats.top - 40, tx, Beats.top + Beats.gap * 3 + 60)
            guard second % 2 == 0, second < Int(Beats.lap) else { continue }
            noStroke()
            fill(ink.withAlpha(0.45))
            textAlign(.center, .top)
            drawText("\(second)s", tx, Beats.top + Beats.gap * 3 + 70)
        }
    }

    func drawLane(_ lane: Lane, row: Int) {
        let y = Beats.top + Double(row) * Beats.gap

        noStroke()
        fill(ink.withAlpha(0.55))
        textSize(26)
        textAlign(.left, .center)
        drawText(lane.name, Beats.left, y - 52)

        stroke(ink.withAlpha(0.18))
        strokeWeight(2)
        drawLine(Beats.left, y, Beats.right, y)

        for position in lane.marks { drawMark(lane.mark, at: Vector2(x(of: position), y)) }
    }

    func drawMark(_ mark: Mark, at point: Vector2) {
        switch mark {
        case .disc:
            noStroke(); fill(ink)
            drawCircle(center: point, radius: 13)
        case .ring:
            noFill(); stroke(warm); strokeWeight(3.5)
            drawCircle(center: point, radius: 12)
        case .tick:
            stroke(cool); strokeWeight(3)
            drawLine(point.x, point.y - 16, point.x, point.y + 16)
        case .square:
            noStroke(); fill(ink.withAlpha(0.75))
            drawRect(center: point, width: 20, height: 20)
        }
    }

    func drawPlayhead(_ at: Double) {
        stroke(warm.withAlpha(0.8))
        strokeWeight(2.5)
        let px = x(of: at)
        drawLine(px, Beats.top - 60, px, Beats.top + Beats.gap * 3 + 60)
    }

    /// The one-shot. It flips a flag four seconds in and the flag stays flipped,
    /// which is the whole difference between `after` and a plain `time > 4`.
    func drawOneShot() {
        noStroke()
        fill(opened ? warm : ink.withAlpha(0.18))
        drawCircle(Beats.right + 60, Beats.top - 60, 16)
        fill(ink.withAlpha(0.55))
        textSize(24)
        textAlign(.right, .center)
        drawText(opened ? "after(4) has fired" : "after(4) is waiting",
                 Beats.right + 30, Beats.top - 60)
    }
}
