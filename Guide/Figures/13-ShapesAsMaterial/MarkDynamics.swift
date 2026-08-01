// figure: frame=0
//
// Guide diagram (Chapter 13): one curve, walked three times by a synthetic hand
// that is nearly still at the ends and flicks through the middle. The first
// panel ignores the pace, the second lets it drive width, the third lets it
// drive opacity. Same path, same strokeWeight, same points.
import Ollin

final class MarkDynamics: Sketch {
    override var canvasSize: CanvasSize { .size(880, 340) }

    let ink = Color(hex: 0x2B2B2B)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(17)

        let titles = ["ignoring the pace", "pace drives width", "pace drives opacity"]
        let brushes = [
            StrokeDynamics.uniform,
            StrokeDynamics(width: .speed(reference: 620, fast: 0.1)),
            StrokeDynamics(opacity: .speed(reference: 620, fast: 0.12)),
        ]

        for i in 0 ..< 3 {
            let r = Rectangle(x: 68 + Double(i) * 260, y: 56, width: 230, height: 196)
            noFill()
            stroke(soft)
            strokeWeight(2)
            drawRect(r)

            withState {
                stroke(ink)
                strokeWeight(17)
                strokeCap(.round)
                drawMark(walk(r, brushes[i]))
            }

            noStroke()
            fill(ink)
            textAlign(.center, .top)
            drawText(titles[i], r.center.x, r.corner.y + r.height + 18)
        }
    }

    /// Record the S-curve with a hand whose pace changes. Easing the *parameter*
    /// is what varies the speed: the curve is the same either way, but the hand
    /// covers its middle far faster than its ends.
    func walk(_ r: Rectangle, _ dynamics: StrokeDynamics) -> StrokeMark {
        var mark = StrokeMark(dynamics, smoothing: 0.4)
        let steps = 220
        for i in 0 ... steps {
            let t = Double(i) / Double(steps)
            let u = t * t * t * (t * (t * 6 - 15) + 10)      // smootherstep
            mark.record(Vector2(r.corner.x + 28 + u * (r.width - 56),
                                r.center.y + sin(u * .tau * 0.85 + 0.6) * (r.height * 0.31)),
                        dt: 1.0 / 240)
        }
        return mark
    }
}
