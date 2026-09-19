// figure: frame=0 themed
//
// Guide diagram (Chapter 15): three questions put to an outline. Left, a probe
// finds the nearest place on a curve, with the direction of travel and the
// side it faces there, and the stretch already walked. Middle, a loop drawn
// as a seven-pointed star finds its own crossings and weaves over and under
// through them. Right, a
// dense trace simplified to the points it needs, and a star with its corners
// rounded and cut. Nothing here uses randomness.
import Ollin
import OllinDiagram

final class OutlineQuestions: Sketch {
    override var canvasSize: CanvasSize { .size(1080, 520) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.18) }
    var accent: Color { theme.accent }

    override func draw() {
        background(paper)
        nearest(at: Vector2(30, 70))
        weave(at: Vector2(390, 70))
        edits(at: Vector2(750, 70))
    }

    func caption(_ title: String, _ note: String) {
        noStroke()
        fill(ink)
        textSize(19)
        textAlign(.left, .middle)
        drawText(title, 0, -34)
        fill(ink.withAlpha(0.7))
        textSize(15)
        textAlign(.left, .top)
        drawText(note, 0, 392)
    }

    /// The probe: nearest point, fraction, tangent, normal, and the piece walked.
    func nearest(at origin: Vector2) {
        withState {
            translate(origin)
            caption("where is it nearest?", "nearestPoint, tangent, normal, piece")
            let path = Contour(curveThrough: [Vector2(10, 320), Vector2(90, 120), Vector2(170, 250),
                                              Vector2(250, 60), Vector2(300, 200)], closed: false)
            let probe = Vector2(215, 290)
            let t = path.fraction(of: probe)
            let foot = path.point(at: t)

            noFill()
            stroke(soft)
            strokeWeight(3)
            drawPolyline(path.points)
            stroke(ink)
            strokeWeight(3.5)
            drawPolyline(path.piece(from: 0, to: t).points)

            stroke(ink.withAlpha(0.5))
            strokeWeight(1.5)
            drawLine(probe, foot)
            stroke(accent)
            strokeWeight(2.5)
            drawArrow(from: foot, to: foot + path.tangent(at: t) * 70)
            drawArrow(from: foot, to: foot + path.normal(at: t) * 50)

            noStroke()
            fill(ink)
            drawCircle(center: probe, radius: 5)
            fill(accent)
            drawCircle(center: foot, radius: 6)
            fill(ink.withAlpha(0.8))
            textSize(14)
            textAlign(.left, .middle)
            drawText("the point", probe.x + 10, probe.y + 4)
            drawText("tangent", foot.x + path.tangent(at: t).x * 70 + 8, foot.y + path.tangent(at: t).y * 70)
            drawText("normal", foot.x + path.normal(at: t).x * 50 - 56, foot.y + path.normal(at: t).y * 50 + 12)
        }
    }

    /// The knot: crossings found, every second pass sent under.
    func weave(at origin: Vector2) {
        withState {
            translate(origin)
            caption("where does it cross itself?", "crossings, then a gap at every second pass")
            let center = Vector2(150, 175)
            let ring = (0 ..< 7).map { k -> Vector2 in
                let i = (k * 3) % 7
                return center + Vector2(angle: Double(i) / 7 * .tau - .tau / 4, length: 150)
            }
            let knot = Contour(curveThrough: ring, closed: true)
            let crossings = knot.crossings()
            let passes = crossings.flatMap { [$0.fraction, $0.otherFraction] }.sorted()
            let unders = passes.enumerated().filter { !$0.offset.isMultiple(of: 2) }.map(\.element)
            let half = 17 / knot.length
            strokeCap(.butt)
            noFill()
            for (i, under) in unders.enumerated() {
                let next = unders[(i + 1) % unders.count]
                let strand = knot.piece(from: wrapped(under + half), to: wrapped(next - half))
                stroke(paper)
                strokeWeight(12)
                drawPolyline(strand.points)
                stroke(ink)
                strokeWeight(7)
                drawPolyline(strand.points)
            }
            noStroke()
            fill(accent)
            for crossing in crossings { drawCircle(center: crossing.point, radius: 3.5) }
        }
    }

    /// A trace simplified, and a star rounded and cut.
    func edits(at origin: Vector2) {
        withState {
            translate(origin)
            caption("fewer points, softer corners", "simplified, rounded, chamfered")
            let dense = Contour((0 ... 300).map { i -> Vector2 in
                let x = Double(i)
                return Vector2(x, 70 + 34 * sin(x / 26) + 12 * sin(x / 7))
            }, closed: false)
            let lighter = dense.simplified(tolerance: 2)
            noFill()
            stroke(ink.withAlpha(0.3))
            strokeWeight(5)
            drawPolyline(dense.points)
            stroke(ink)
            strokeWeight(1.8)
            drawPolyline(lighter.points)
            noStroke()
            fill(accent)
            for p in lighter { drawCircle(center: p, radius: 3.5) }
            fill(ink.withAlpha(0.8))
            textSize(14)
            textAlign(.left, .top)
            drawText("\(dense.count) points, \(lighter.count) kept", 0, 130)

            let star = Contour((0 ..< 10).map { i in
                Vector2(0, 0) + Vector2(angle: Double(i) / 10 * .tau - .tau / 4,
                                        length: i.isMultiple(of: 2) ? 78 : 34)
            })
            for (x, outline, label) in [(70.0, star.rounded(9), "rounded(9)"),
                                        (230.0, star.chamfered(9), "chamfered(9)")] {
                withState {
                    translate(x, 270)
                    noFill()
                    stroke(soft)
                    strokeWeight(1.5)
                    drawPolyline(star.points + [star.points[0]])
                    noStroke()
                    fill(accent)
                    drawShape(Shape(contours: [outline]))
                    fill(ink.withAlpha(0.8))
                    textSize(14)
                    textAlign(.center, .top)
                    drawText(label, 0, 90)
                }
            }
        }
    }

    func wrapped(_ fraction: Double) -> Double {
        let r = fraction.truncatingRemainder(dividingBy: 1)
        return r < 0 ? r + 1 : r
    }
}
