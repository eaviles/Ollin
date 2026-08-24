// figure: frame=0 themed
//
// Guide diagram (Chapter 16): the droste filter. A ring of lit windows on flat
// ground, then the same ring put through the filter twice: plain concentric
// copies, and the copies wound into one spiral by a single turn's worth of twist.
import Ollin

final class PictureInsideItself: Sketch {
    override var canvasSize: CanvasSize { .size(880, 400) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var soft: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.12) }

    override func draw() {
        background(paper)

        let scene = renderTarget(width: 260, height: 260)
        withTarget(scene) { paintRing() }

        let boxes = [Rectangle(x: 68, y: 56, width: 240, height: 240),
                     Rectangle(x: 320, y: 56, width: 240, height: 240),
                     Rectangle(x: 572, y: 56, width: 240, height: 240)]
        drawImage(scene.image, in: boxes[0])
        drawImage(scene.filtered(.droste(inner: 0.42, twist: 0)).image, in: boxes[1])
        drawImage(scene.filtered(.droste(inner: 0.42, twist: 1)).image, in: boxes[2])

        frame(boxes[0], title: "the layer")
        frame(boxes[1], title: "twist 0: copies in rings")
        frame(boxes[2], title: "twist 1: copies in one spiral")

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("the ring between inner and the edge, repeated at every scale",
                 width / 2, 330)
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

    /// The layer the filter reads: a ring of lit windows on flat ground, with
    /// nothing near either edge of the ring, so no join shows in the copies.
    func paintRing() {
        seed(4)
        background(Color(hex: 0x0A0E1A))
        noStroke()
        // The layer is its own size, not the canvas's, so the ring is placed in it.
        let side = 260.0
        let middle = Vector2(side / 2, side / 2)
        let unit = side / 2
        let count = 12
        for i in 0 ..< count {
            let angle = Double(i) / Double(count) * .tau
            withState {
                translate(middle + Vector2(cos(angle), sin(angle)) * unit * 0.68)
                rotate(angle)
                fill(CosinePalette.rainbow.color(at: Double(i) / Double(count)))
                drawRect(center: .zero, width: unit * 0.22, height: unit * 0.14,
                         cornerRadius: unit * 0.02)
                fill(Color(white: 1, alpha: 0.85))
                drawRect(center: Vector2(unit * 0.04, 0), width: unit * 0.055,
                         height: unit * 0.055, cornerRadius: unit * 0.01)
            }
            fill(Color(hex: 0xFFE08A))
            drawCircle(center: middle + Vector2(cos(angle + 0.26), sin(angle + 0.26)) * unit * 0.53,
                       radius: unit * 0.016)
        }
    }
}
