import Ollin

/// A loop that knows where it crosses itself. A smooth closed curve is
/// threaded through a ring of drifting points taken out of order, so it
/// tangles into a star. Every frame the outline is asked where it crosses itself
/// (`crossings()`). Walking once round, each crossing is passed twice, and the
/// passes alternate over and under; a closed curve always passes an even
/// number of crossings between its two visits to one, so every crossing gets
/// one of each. Where the strand goes under, a short stretch is cut out of it
/// (`piece(from:to:)`), and what is left reads as a knot that weaves. The
/// color runs once round the loop and carries on across every gap, so a
/// strand can be followed through the crossings.
///
/// A probe asks the curve one more question: the nearest place on it
/// (`nearestPoint(to:)`, `fraction(of:)`), with the direction of travel there
/// (`tangent(at:)`) and the side it faces (`normal(at:)`). Hold the mouse
/// down to drive the probe yourself.
///
/// ```sh
/// swift run Example-Shapes-OverUnder --export-loop /tmp/over-under.gif
/// ```
///
/// Pure geometry on the way out: every strand is an ordinary open contour,
/// so `--export-svg` writes the woven knot as plottable lines.
@main
final class OverUnder: Sketch {
    @Param(5 ... 9, icon: "point.3.connected.trianglepath.dotted") var anchors = 7
    @Param(0 ... 100, icon: "scissors") var gap = 64.0
    @Param(icon: "circle.dotted") var marksCrossings = false

    private let period = 18.0
    override var loopDuration: Double? { period }

    override func draw() {
        background(Color(hex: 0x14161C))
        let phase = loopProgress(over: period)
        let knot = tangle(at: phase)

        // Every pass through a crossing, in order round the loop; the odd
        // ones go under.
        let crossings = knot.crossings()
        let passes = crossings.flatMap { [$0.fraction, $0.otherFraction] }.sorted()
        let unders = passes.enumerated().filter { !$0.offset.isMultiple(of: 2) }.map(\.element)

        // Cut a gap around each under pass, and draw what lies between.
        let half = gap * scale / 2 / knot.length
        var spans: [(from: Double, to: Double)] = [(0, 1)]
        if !unders.isEmpty {
            spans = unders.indices.map { i in
                (wrapped(unders[i] + half), wrapped(unders[(i + 1) % unders.count] - half))
            }
        }
        strokeCap(.butt)
        strokeJoin(.round)
        noFill()
        for span in spans {
            let strand = knot.piece(from: span.from, to: span.to)
            // Its slice of one hue wheel that runs once round the loop.
            let length = span.to > span.from ? span.to - span.from : span.to - span.from + 1
            let colors = (0 ... 6).map { j in
                Color(hue: span.from + length * Double(j) / 6, saturation: 0.5, brightness: 0.98)
            }
            stroke(Color(hex: 0x14161C))
            strokeWeight(32 * scale)
            drawPolyline(strand.points)
            stroke(.alongPath(colors))
            strokeWeight(20 * scale)
            drawPolyline(strand.points)
        }

        if marksCrossings {
            noFill()
            stroke(Color(hex: 0xF4EAD6).withAlpha(0.7))
            strokeWeight(1.5 * scale)
            for crossing in crossings { drawCircle(center: crossing.point, radius: 24 * scale) }
        }

        // The probe: where on the loop is nearest, and which way it runs there.
        let probe = mouseIsPressed
            ? mouse
            : Vector2(width / 2, height / 2) + Vector2(angle: phase * .tau * 2, length: 330 * scale)
        let t = knot.fraction(of: probe)
        let foot = knot.point(at: t)
        let along = knot.tangent(at: t), side = knot.normal(at: t)

        stroke(Color(hex: 0xF4EAD6).withAlpha(0.45))
        strokeWeight(1.5 * scale)
        drawLine(probe, foot)
        stroke(Color(hex: 0xF4EAD6))
        strokeWeight(3 * scale)
        drawArrow(from: foot, to: foot + along * 90 * scale)
        stroke(Color(hex: 0x7FD1C2))
        drawArrow(from: foot, to: foot + side * 60 * scale)

        noStroke()
        fill(Color(hex: 0xF4EAD6))
        drawCircle(center: probe, radius: 6 * scale)
        drawCircle(center: foot, radius: 8 * scale)
        textSize(22 * scale)
        textAlign(.left, .top)
        drawText("\(crossings.count) crossings", 40 * scale, 40 * scale)
        drawText("nearest at \((t * 100).rounded() / 100) of the way round",
                 40 * scale, 72 * scale)
    }

    /// A smooth loop through `anchors` points on a ring, visited in star order
    /// so it tangles, each point drifting on its own slice of looping noise.
    private func tangle(at phase: Double) -> Contour {
        let count = anchors
        // The longest step under half the ring that still visits every point
        // before coming home: a star, crossing itself at open angles.
        var step = (count - 1) / 2
        while gcd(step, count) != 1 { step -= 1 }
        let center = Vector2(width / 2, height / 2 + 20 * scale)
        let ring = (0 ..< count).map { k -> Vector2 in
            let i = (k * step) % count
            let angle = Double(i) / Double(count) * .tau - .tau / 4
            let radius = 380 * scale * (1 + signedNoise(Double(i) * 1.7, loop: phase, radius: 0.5) * 0.12)
            let turn = signedNoise(Double(i) * 1.7 + 40, loop: phase, radius: 0.5) * 0.12
            return center + Vector2(angle: angle + turn, length: radius)
        }
        return Contour(curveThrough: ring, closed: true)
    }

    private func wrapped(_ fraction: Double) -> Double {
        let r = fraction.truncatingRemainder(dividingBy: 1)
        return r < 0 ? r + 1 : r
    }

    private func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
}
