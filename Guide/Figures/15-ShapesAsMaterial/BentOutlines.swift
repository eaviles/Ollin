// figure: frame=0 themed
//
// Guide diagram (Chapter 15): three ways to bend an outline. Left, a word
// set on a straight baseline is bent along a wave, every point at the same
// place along the wave and the same height above it. Middle, a blob is
// pulled toward a point with the untouched outline ghosted, and a rope is
// pulled near one end with both ends held. Right, a jittery trace with two
// corners is smoothed with its corners kept, cut at them into pieces, and
// each piece fitted with a few cubic curves, their handles drawn. Nothing
// here uses randomness.
import Ollin
import OllinDiagram

final class BentOutlines: Sketch {
    override var canvasSize: CanvasSize { .size(1080, 520) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.18) }
    var accent: Color { theme.accent }

    let face = OutlineFont(name: "AvenirNext-Heavy") ?? .systemBold

    override func draw() {
        background(paper)
        bent(at: Vector2(30, 70))
        pulled(at: Vector2(390, 70))
        traced(at: Vector2(750, 70))
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

    /// A word on a straight baseline, bent along a wave.
    func bent(at origin: Vector2) {
        withState {
            translate(origin)
            caption("bent along a curve", "warped(from: baseline, along: wave)")
            textFont(face)
            textAlign(.center, .middle)
            textSize(96)
            let glyphs = textToShapes("bend", 150, 110)
            let baseline = Contour([Vector2(0, 110), Vector2(300, 110)], closed: false)
            let wave = Contour((0 ... 30).map { i -> Vector2 in
                let x = Double(i) * 10
                return Vector2(x, 250 + 40 * sin(x / 300 * .tau))
            }, closed: false)
            noStroke()
            fill(soft)
            for glyph in glyphs { drawShape(glyph) }
            fill(ink)
            for glyph in glyphs { drawShape(glyph.warped(from: baseline, along: wave)) }
            noFill()
            stroke(accent)
            strokeWeight(2)
            drawPolyline(wave.points)
            stroke(ink.withAlpha(0.35))
            strokeWeight(1.5)
            drawLine(Vector2(0, 110), Vector2(300, 110))
            fill(ink.withAlpha(0.8))
            noStroke()
            textAlign(.left, .middle)
            textSize(14)
            drawText("baseline", 0, 128)
            drawText("wave", 306, 244)
        }
    }

    /// A blob pulled toward a point, and a rope pulled near its end.
    func pulled(at origin: Vector2) {
        withState {
            translate(origin)
            caption("pulled toward a point", "pulled(toward:amount:radius:)")
            let blob = Contour((0 ..< 72).map { i -> Vector2 in
                let a = Double(i) / 72 * .tau
                return Vector2(120, 150) + Vector2(angle: a, length: 80 + 12 * sin(3 * a))
            }, closed: true)
            let hand = Vector2(252, 110)
            noStroke()
            fill(soft)
            drawShape(Shape(contours: [blob]))
            fill(ink)
            drawShape(Shape(contours: [blob.pulled(toward: hand, amount: 0.8, radius: 120)]))
            fill(accent)
            drawCircle(center: hand, radius: 6)

            let rope = Contour([Vector2(0, 320), Vector2(300, 320)], closed: false)
            let tug = Vector2(250, 270)
            noFill()
            stroke(soft)
            strokeWeight(3)
            drawPolyline(rope.points)
            stroke(ink)
            strokeWeight(3.5)
            drawPolyline(rope.pulled(toward: tug, amount: 1, radius: 110).points)
            noStroke()
            fill(accent)
            drawCircle(center: tug, radius: 6)
            fill(ink.withAlpha(0.8))
            textAlign(.left, .middle)
            textSize(14)
            drawText("the hand", hand.x - 60, hand.y - 18)
            drawText("ends held", 0, 342)
        }
    }

    /// A jittery trace smoothed with its corners kept, cut at them, and fitted.
    func traced(at origin: Vector2) {
        withState {
            translate(origin)
            caption("smoothed, split, and fitted", "corners kept, split at them, fitted")
            var points: [Vector2] = []
            func run(to target: Vector2, steps: Int) {
                let from = points[points.count - 1]
                for i in 1 ... steps { points.append(from + (target - from) * (Double(i) / Double(steps))) }
            }
            points.append(Vector2(0, 300))
            for i in 1 ... 60 {
                let t = Double(i) / 60
                points.append(Vector2(90 * t, 300 - 230 * sin(t * .pi * 0.5)))
            }
            run(to: Vector2(150, 300), steps: 60)
            for i in 1 ... 70 {
                let t = Double(i) / 70
                points.append(Vector2(150 + 150 * t, 300 - 200 * sin(t * .pi) - 60 * t))
            }
            // A hand's wobble, under the corner angle at every point.
            let shaky = points.enumerated().map { i, p in
                p + Vector2(sin(Double(i) * 1.9) * 0.8, cos(Double(i) * 2.3) * 0.8)
            }
            let trace = Contour(shaky, closed: false)
            let smooth = trace.smoothed(neighbors: 3, keepingCornersOver: .pi / 3)
            let pieces = smooth.split(atCornersOver: .pi / 3, span: 6)

            noFill()
            stroke(soft)
            strokeWeight(7)
            strokeCap(.round)
            drawPolyline(trace.points)
            for (k, piece) in pieces.enumerated() {
                let path = piece.fitted(tolerance: 1.5)
                stroke(k.isMultiple(of: 2) ? ink : accent)
                strokeWeight(2.5)
                drawPolyline(path.contour.points)
                stroke(ink.withAlpha(0.45))
                strokeWeight(1)
                for cubic in path.cubics {
                    drawLine(cubic.start, cubic.control1)
                    drawLine(cubic.end, cubic.control2)
                }
                noStroke()
                fill(ink.withAlpha(0.7))
                for cubic in path.cubics {
                    drawCircle(center: cubic.control1, radius: 2.5)
                    drawCircle(center: cubic.control2, radius: 2.5)
                }
                fill(ink)
                for cubic in path.cubics { drawCircle(center: cubic.start, radius: 3.5) }
                if let last = path.cubics.last { drawCircle(center: last.end, radius: 3.5) }
                noFill()
            }
            let curves = pieces.reduce(0) { $0 + $1.fitted(tolerance: 1.5).cubics.count }
            noStroke()
            fill(ink.withAlpha(0.8))
            textAlign(.left, .top)
            textSize(14)
            drawText("\(trace.count) points, \(pieces.count) pieces, \(curves) curves", 0, 330)
        }
    }
}
