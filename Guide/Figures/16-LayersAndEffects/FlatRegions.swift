// figure: frame=0 themed
//
// Guide diagram (Chapter 16): the coherence-enhancing filter. A small still
// life drawn into a layer, then the same layer through `.shock()`: soft shading
// snapped into flat regions with crisp edges, the grain drawn out along its flow.
import Ollin
import OllinDiagram

final class FlatRegions: Sketch {
    override var canvasSize: CanvasSize { .size(880, 400) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }

    override func draw() {
        background(paper)

        let left = Rectangle(x: 90, y: 92, width: 330, height: 180)
        let right = Rectangle(x: 460, y: 92, width: 330, height: 180)

        // The layer is the panel's own size, so the shock's reach and the flow's
        // length stay the pixels the filter counts.
        let scene = makeRenderTarget(width: Int(left.width), height: Int(left.height))
        withTarget(scene) { paint(width: left.width, height: left.height) }

        drawImage(scene.image, in: left)
        drawImage(scene.filtered(.shock()).image, in: right)

        frame(left, title: "the layer")
        frame(right, title: "filtered(.shock())")

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("smoothed along the flow, sharpened across it", width / 2, 312)
    }

    /// A still life: three pieces of fruit on a grained table under a lamp at the
    /// upper left, laid out in the layer's own coordinates.
    func paint(width: Double, height: Double) {
        let lamp = Vector2(width * 0.2, height * 0.1)
        noStroke()

        let horizon = height * 0.58
        fill(.linear(from: Vector2(0, 0), to: Vector2(0, horizon),
                     Ramp([Color(hex: 0xD9CDB8), Color(hex: 0x9C8E78)])))
        drawRect(0, 0, width, horizon)
        fill(.linear(from: Vector2(0, horizon), to: Vector2(0, height),
                     Ramp([Color(hex: 0x9A6B3E), Color(hex: 0x4A2E1A)])))
        drawRect(0, horizon, width, height - horizon)

        seed(4)
        strokeWeight(1.2)
        for i in 0 ..< 36 {
            let y0 = horizon + Double(i) / 36 * (height - horizon) + random(-2, 2)
            let amplitude = random(1.5, 5)
            let period = random(80, 240)
            let phase = random(0, .pi * 2)
            let dark = random(0, 1) < 0.5
            stroke(dark ? Color(hex: 0x3B2213, alpha: random(0.25, 0.5))
                        : Color(hex: 0xC4925C, alpha: random(0.15, 0.35)))
            var points: [Vector2] = []
            for x in stride(from: -10.0, through: width + 10, by: 8) {
                points.append(Vector2(x, y0 + amplitude * sin(x / period * .pi * 2 + phase)))
            }
            drawPolyline(points)
        }
        noStroke()

        let fruit: [(Vector2, Double, Double, Color)] = [
            (Vector2(width * 0.3, height * 0.66), width * 0.11, 1.0, Color(hex: 0xE8842A)),
            (Vector2(width * 0.55, height * 0.72), width * 0.075, 1.0, Color(hex: 0x5B2C6E)),
            (Vector2(width * 0.75, height * 0.64), width * 0.12, 0.72, Color(hex: 0xE9D24A)),
        ]
        for (center, r, squash, tint) in fruit {
            contactShadow(under: Vector2(center.x, center.y + r * squash * 0.95), width: r * 1.7, lamp: lamp)
            let hot = center + (lamp - center).normalized * (r * 0.45)
            fill(.radial(center: hot, radius: r * 1.5,
                         Ramp([Color(hex: 0xFFF4DC), tint, tint.darker(by: 0.55)])))
            drawEllipse(center: center, radiusX: r, radiusY: r * squash)
        }
    }

    func contactShadow(under foot: Vector2, width w: Double, lamp: Vector2) {
        let away = (foot - lamp).normalized
        let at = foot + away * (w * 0.15)
        fill(.radial(center: at, radius: w * 0.9,
                     Ramp([Color(white: 0, alpha: 0.5), Color(white: 0, alpha: 0)])))
        drawEllipse(center: at, radiusX: w * 0.9, radiusY: w * 0.26)
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textSize(17)
        textAlign(.left, .middle)
        drawText(title, r.x, r.y - 20)
    }
}
