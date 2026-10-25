import Ollin

/// A pen. Ink from a nib soaks a little way into the paper past the line's
/// edge, and farther where the hand slowed; it pools where the pen lands and
/// lifts, lays a second coat where strokes cross, and thins when the hand
/// hurries, down to a ballpoint's skips. Three lines of a made-up hand are
/// written across the sheet at three paces, a crawl, a writing speed, and a
/// flick, each point carrying the speed it was made at, which is what the pen
/// reads (`strokeMedium(.ink(...))`). Below them, a frame and a cross drawn
/// straight, and the same drawn by a hand (`handDrawn`): a wobble off the
/// line, a bow in every side, ends that run short or long, and a blot where the
/// pen lands.
///
/// Drag to write in ink yourself: the mark records how fast your hand moved.
/// `c` clears what you wrote.
@main
final class InkPen: Sketch {
    @Param("Feather", 0 ... 8, icon: "drop") var feather = 2.5
    @Param("Pooling", 0 ... 1) var pooling = 0.6
    @Param("Thinning", 0 ... 1) var thinning = 0.6
    @Param("Writing speed", 200 ... 2000, icon: "hare") var writingSpeed = 900.0
    @Param("Weight", 2 ... 14, icon: "lineweight") var weight = 5.0

    override var loopDuration: Double? { 12 }

    let paper = Color(red: 0.965, green: 0.95, blue: 0.915)
    let inkColor = Color(red: 0.1, green: 0.14, blue: 0.3)

    /// The mark under the pointer, and the marks already written.
    var mark = StrokeMark(InkPen.hand, smoothing: 0.4)
    var drawn: [StrokeMark] = []

    /// A pen's hand: the line thins a little when it hurries, and no more.
    static let hand = StrokeDynamics(width: .speed(reference: 2400, fast: 0.75))

    /// The pen as the parameters set it.
    var pen: StrokeMedium { .ink(feather: feather, pooling: pooling, amount: thinning, speed: writingSpeed) }

    override func setup() {
        textFont(OutlineFont.system)
    }

    override func draw() {
        background(paper)
        // The margin rule a writing pad has.
        stroke(Color(red: 0.85, green: 0.55, blue: 0.55).withAlpha(0.45))
        strokeWeight(2)
        drawLine(118, 70, 118, 1010)

        noFill()
        stroke(inkColor)
        strokeWeight(weight)
        strokeCap(.round)
        strokeJoin(.round)
        strokeMedium(pen)

        // Three lines of a made-up hand, each written over half the loop at
        // its own pace, so the pen reads a crawl, a writing speed, and a flick.
        let t = loopProgress(over: 12)
        let paces: [(name: String, speed: Double)] = [("a crawl", 160), ("writing", 700), ("a flick", 2400)]
        for (i, pace) in paces.enumerated() {
            let y = 170 + Double(i) * 150
            let progress = min(max((t - Double(i) * 0.1) / 0.5, 0), 1)
            drawMark(script(line: i, y: y, speed: pace.speed, upTo: progress))
            label(pace.name, x: 100, y: y)
        }

        // A frame and a cross drawn straight, and the same drawn by a hand.
        let frame = Contour([Vector2(0, 0), Vector2(320, 0), Vector2(320, 210), Vector2(0, 210)])
        let cross = [Contour([Vector2(0, 0), Vector2(320, 210)], closed: false),
                     Contour([Vector2(320, 0), Vector2(0, 210)], closed: false)]
        strokeWeight(weight * 0.8)
        strokeCap(.butt)
        withState {
            translate(170, 690)
            drawShape(Shape(contours: [frame]))
            for line in cross { drawPolyline(line.points) }
        }
        withState {
            translate(600, 690)
            drawShape(Shape(contours: [frame]).handDrawn(wobble: 1.5, bow: 3, seed: 1))
            for (k, line) in cross.enumerated() {
                let pen = StrokeMark(samples: line.points.map { StrokeMark.Sample(position: $0) })
                drawMark(pen.handDrawn(wobble: 1.5, bow: 3, overshoot: 10, blot: weight * 2, seed: 2 + k))
            }
        }
        label("drawn straight", x: 330, y: 940, align: .center)
        label("drawn by hand", x: 760, y: 940, align: .center)

        // Your own writing, and the mark under the pointer.
        for written in drawn { drawMark(written) }
        if mouseIsPressed { record(into: &mark) }
        drawMark(mark)

        label("drag to write in ink  ·  c clears", x: width / 2, y: height - 36, align: .center)
    }

    override func mousePressed() {
        mark = StrokeMark(InkPen.hand, smoothing: 0.4)
    }

    override func mouseReleased() {
        if !mark.isEmpty { drawn.append(mark) }
        mark.clear()
    }

    override func keyPressed() {
        if key == "c" { drawn = []; mark.clear() }
    }

    /// A line of the made-up hand along row `y`, written up to `progress` of
    /// its length at `speed` canvas points a second: a chain of loops whose
    /// height swells and shrinks by word, recorded point by point with the
    /// time each step took, so every point carries the speed it was made at.
    func script(line: Int, y: Double, speed: Double, upTo progress: Double) -> StrokeMark {
        let count = 520
        let last = Int(Double(count) * progress)
        guard last >= 2 else { return StrokeMark() }
        var written = StrokeMark(InkPen.hand, smoothing: 0.35, minSpacing: 0)
        var previous: Vector2? = nil
        for k in 0 ... last {
            let u = Double(k) / Double(count)
            let phase = Double(line) * 1.7
            // The word's height rises and falls seven times across the row,
            // and the loops flatten to a joining stroke between words.
            let word = pow(sin(u * .pi * 7 + phase), 2)
            let loop = u * 300 + phase
            let p = Vector2(150 + 800 * u + 9 * word * sin(loop),
                            y + (8 + 24 * word) * cos(loop) - 10 * word)
            let elapsed = previous.map { $0.distance(to: p) / speed } ?? 1.0 / 60
            written.record(p, deltaTime: elapsed)
            previous = p
        }
        return written
    }

    /// A caption in gray, unstroked, whatever the pen is set to.
    func label(_ text: String, x: Double, y: Double, align: HorizontalTextAlign = .right) {
        withState {
            noStroke()
            fill(Color(white: 0.45))
            textSize(18)
            textAlign(align, .middle)
            drawText(text, x, y)
        }
    }
}
