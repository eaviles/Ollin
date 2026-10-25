// figure: frame=0 probe themed
//
// Guide diagram (Chapter 17): the pen. Left, one line written three times at
// three paces, a crawl, the writing speed, and a flick: the ink soaks farther
// into the paper where the pen crawled and breaks into a ballpoint's skips
// where it flicked, and pools at the ends of each. Upper right, a translucent
// pen stroke crossing itself lays a second coat at the crossing. Lower right,
// a frame and a diagonal drawn straight, and the same drawn by a hand.
import Ollin
import OllinDiagram

final class InkPen: Sketch {
    override var canvasSize: CanvasSize { .size(880, 560) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }
    var navy: Color { darkTheme ? Color(red: 0.62, green: 0.68, blue: 0.9) : Color(red: 0.1, green: 0.14, blue: 0.3) }

    override func setup() {
        textFont(OutlineFont.system)
    }

    override func draw() {
        background(paper)
        textSize(16)

        // Left: three paces.
        let left = Rectangle(x: 36, y: 34, width: 420, height: 492)
        panel(left)
        let paces: [(String, Double)] = [("a crawl", 160), ("writing", 700), ("a flick", 2400)]
        for (i, pace) in paces.enumerated() {
            let y = left.y + 90 + Double(i) * 150
            withState {
                noFill()
                stroke(navy)
                strokeWeight(6)
                strokeCap(.round)
                strokeJoin(.round)
                strokeMedium(.ink(feather: 2.5, pooling: 0.6, amount: 0.7))
                drawMark(script(y: y, from: left.x + 30, to: left.x + left.width - 30, speed: pace.1))
            }
            caption(pace.0, left.x + left.width / 2, y + 58)
        }

        // Upper right: a translucent pen crossing itself.
        let right = Rectangle(x: 476, y: 34, width: 368, height: 232)
        panel(right)
        withState {
            noFill()
            stroke(navy.withAlpha(0.55))
            strokeWeight(14)
            strokeCap(.round)
            strokeMedium(.ink(feather: 2, pooling: 0.5))
            let c = right.center
            drawPolyline([Vector2(c.x - 120, c.y - 60), Vector2(c.x + 120, c.y + 50),
                          Vector2(c.x + 120, c.y - 60), Vector2(c.x - 120, c.y + 50)])
        }
        caption("a second coat where it crosses", right.center.x, right.y + right.height - 22)

        // Lower right: drawn straight, and drawn by hand.
        let lower = Rectangle(x: 476, y: 294, width: 368, height: 232)
        panel(lower)
        let frame = Contour([Vector2(0, 0), Vector2(130, 0), Vector2(130, 110), Vector2(0, 110)])
        let diagonal = Contour([Vector2(0, 110), Vector2(130, 0)], closed: false)
        withState {
            noFill()
            stroke(navy)
            strokeWeight(4)
            strokeMedium(.ink(feather: 1.5, pooling: 0.5))
            withState {
                translate(lower.x + 34, lower.y + 40)
                drawShape(Shape(contours: [frame]))
                drawPolyline(diagonal.points)
            }
            withState {
                translate(lower.x + 204, lower.y + 40)
                drawShape(Shape(contours: [frame]).handDrawn(wobble: 1.2, bow: 2, seed: 1))
                let pen = StrokeMark(samples: diagonal.points.map { StrokeMark.Sample(position: $0) })
                drawMark(pen.handDrawn(wobble: 1.2, bow: 2.5, overshoot: 8, blot: 10, seed: 3))
            }
        }
        caption("drawn straight", lower.x + 99, lower.y + lower.height - 22)
        caption("handDrawn()", lower.x + 269, lower.y + lower.height - 22)
    }

    /// One row of a made-up hand from `x0` to `x1`, recorded point by point
    /// at `speed`, so each point carries the speed it was made at.
    private func script(y: Double, from x0: Double, to x1: Double, speed: Double) -> StrokeMark {
        let count = 260
        var written = StrokeMark(StrokeDynamics(width: .speed(reference: 2400, fast: 0.75)),
                                 smoothing: 0.35, minSpacing: 0)
        var previous: Vector2? = nil
        for k in 0 ... count {
            let u = Double(k) / Double(count)
            let word = pow(sin(u * .pi * 4 + 0.3), 2)
            let loop = u * 150
            let p = Vector2(x0 + (x1 - x0) * u + 8 * word * sin(loop),
                            y + (6 + 20 * word) * cos(loop) - 8 * word)
            let elapsed = previous.map { $0.distance(to: p) / speed } ?? 1.0 / 60
            written.record(p, deltaTime: elapsed)
            previous = p
        }
        return written
    }

    private func panel(_ r: Rectangle) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
    }

    private func caption(_ text: String, _ x: Double, _ y: Double) {
        noStroke()
        fill(ink)
        textAlign(.center, .middle)
        drawText(text, x, y)
    }
}
