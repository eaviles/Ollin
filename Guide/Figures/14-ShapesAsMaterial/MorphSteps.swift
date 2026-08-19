// figure: frame=0
//
// Guide diagram (Chapter 14): a shape morph. A star becoming a rounded blob
// with a hole, read at five points along the way. Every in-between is a real
// shape, so it fills, strokes, and exports like anything else.
import Ollin

final class MorphSteps: Sketch {
    override var canvasSize: CanvasSize { .size(880, 380) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x232020)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)
    let accent = Color(hex: 0xE4572E)

    var morph: ShapeMorph?

    override func setup() {
        let star = Shape((0 ..< 10).map { i in
            let a = Double(i) / 10 * .tau - .pi / 2
            let r = i.isMultiple(of: 2) ? 78.0 : 32.0
            return Vector2(cos(a) * r, sin(a) * r)
        })
        let ring = Shape(outer: (0 ..< 64).map { i in
            let a = Double(i) / 64 * .tau
            return Vector2(cos(a) * 70, sin(a) * 70)
        }, holes: [(0 ..< 40).map { i in
            let a = Double(i) / 40 * .tau
            return Vector2(cos(a) * 30, sin(a) * 30)
        }])
        morph = ShapeMorph(from: star, to: ring)
    }

    override func draw() {
        background(paper)
        guard let morph else { return }

        for i in 0 ..< 5 {
            let t = Double(i) / 4
            let panel = Rectangle(x: 25 + Double(i) * 170, y: 60,
                                  width: 160, height: 180)
            withState {
                translate(panel.x + panel.width / 2, panel.y + panel.height / 2)
                noStroke()
                fill(accent)
                drawShape(morph.shape(at: t))
            }
            frame(panel, title: "t = \(String(format: "%.2f", t))")
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("the hole grows in on the way; every step is real geometry",
                 width / 2, 276)
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textSize(16)
        textAlign(.left, .middle)
        drawText(title, r.x, r.y - 18)
    }
}
