// figure: frame=0
//
// Guide diagram (Chapter 14): line integral convolution, the whole field
// drawn at once. A sheet of gray grain is brushed along a noise field read as
// an angle: every pixel becomes the average of the grain along the streamline
// through it, so the field shows up as combed fiber with no line traced by
// hand. Two panels: the field on the left, a few gray discs blurred into one
// smooth sheet (black to white is two full turns of heading), and the streaks
// it makes on the right. Ink on cream, so it reads beside the chapter's other
// diagrams.
import Ollin

final class StreaksFigure: Sketch {
    override var canvasSize: CanvasSize { .size(1360, 680) }

    override func draw() {
        background(Color(hex: 0xF5F1E6))
        let gap = 40.0
        let panel = (width - gap * 3) / 2

        // The field: a few gray discs on a mid-gray ground, blurred until they
        // are one smooth sheet. Both panels read this layer.
        let discs = makeRenderTarget(scale: 0.5)
        withTarget(discs) {
            background(Color(white: 0.5))
            noStroke()
            let marks: [(x: Double, y: Double, r: Double, tone: Double)] = [
                (0.22, 0.28, 0.2, 0.05), (0.7, 0.2, 0.16, 0.95), (0.8, 0.62, 0.22, 0.25),
                (0.35, 0.72, 0.18, 0.85), (0.55, 0.45, 0.1, 0.6), (0.1, 0.85, 0.12, 0.4)]
            for m in marks {
                fill(Color(white: m.tone))
                drawCircle(m.x * width, m.y * height, m.r * width)
            }
        }
        let field = discs.filtered(.gaussianBlur(radius: 70))

        // The base: flat gray, grained so the walk has something to average.
        let base = makeRenderTarget()
        withTarget(base) { background(Color(white: 0.62)) }
        let streaks = base.filtered(.grain(amount: 1))
            .combined(with: field, .lineIntegralConvolution(length: 0.1, field: .angle(turns: 2)))
            .filtered(.levels(blackPoint: 0.3, whitePoint: 0.7))   // the averaged grain is faint; stretch it

        drawImage(field.image, gap, gap, panel, panel)
        drawImage(streaks.image, gap * 2 + panel, gap, panel, panel)
    }
}
