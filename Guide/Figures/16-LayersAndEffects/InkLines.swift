// figure: frame=0 themed
//
// Guide diagram (Chapter 16): the flow-based difference of Gaussians. A small
// still life drawn into a layer, then the same layer through `.xdog()`: a line
// where the picture has an edge, ink where it is dark, paper everywhere else.
import Ollin
import OllinDiagram

final class InkLines: Sketch {
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

        // The layer is the panel's own size, so a line keeps the width the filter
        // drew it at and a ball stays round.
        let scene = makeRenderTarget(width: Int(left.width), height: Int(left.height))
        withTarget(scene) { paint(width: left.width, height: left.height) }

        drawImage(scene.image, in: left)
        drawImage(scene.filtered(.xdog()).image, in: right)

        frame(left, title: "the layer")
        frame(right, title: "filtered(.xdog())")

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("a line where there is an edge, ink where it is dark", width / 2, 312)
    }

    /// A still life: a jug and three balls on a table, lit from the upper left,
    /// laid out in the layer's own coordinates.
    func paint(width: Double, height: Double) {
        let lamp = Vector2(width * 0.2, height * 0.1)
        noStroke()

        let horizon = height * 0.62
        fill(.linear(from: Vector2(0, 0), to: Vector2(0, horizon),
                     Ramp([Color(hex: 0xD8D0C2), Color(hex: 0x8F8677)])))
        drawRect(0, 0, width, horizon)
        fill(.linear(from: Vector2(0, horizon), to: Vector2(0, height),
                     Ramp([Color(hex: 0x7A5A3C), Color(hex: 0x2A1D14)])))
        drawRect(0, horizon, width, height - horizon)

        let jugX = width * 0.1, jugY = height * 0.28, jugW = width * 0.13, jugH = height * 0.4
        let jugMid = jugX + jugW / 2
        contactShadow(under: Vector2(jugMid, jugY + jugH), width: jugW * 0.7, lamp: lamp)
        fill(.linear(from: Vector2(jugX, 0), to: Vector2(jugX + jugW, 0),
                     Ramp([Color(hex: 0xDDEBF0), Color(hex: 0x6B8E9F), Color(hex: 0x2A2430)])))
        drawRect(jugX, jugY, jugW, jugH)
        fill(Color(hex: 0x1E1A24))
        drawEllipse(jugMid, jugY, jugW / 2, jugH * 0.06)

        let balls: [(Vector2, Double, Color)] = [
            (Vector2(width * 0.4, height * 0.58), height * 0.2, Color(hex: 0xC94B3F)),
            (Vector2(width * 0.6, height * 0.66), height * 0.14, Color(hex: 0x3F86C9)),
            (Vector2(width * 0.79, height * 0.56), height * 0.24, Color(hex: 0xE0B34A)),
        ]
        for (center, r, tint) in balls {
            contactShadow(under: Vector2(center.x, center.y + r * 0.95), width: r * 1.6, lamp: lamp)
            let hot = center + (lamp - center).normalized * (r * 0.5)
            fill(.radial(center: hot, radius: r * 1.45,
                         Ramp([Color(hex: 0xFFF6E8), tint, Color(hex: 0x14161E)])))
            drawCircle(center: center, radius: r)
        }
    }

    func contactShadow(under foot: Vector2, width w: Double, lamp: Vector2) {
        let away = (foot - lamp).normalized
        let at = foot + away * (w * 0.2)
        fill(.radial(center: at, radius: w * 0.9,
                     Ramp([Color(white: 0, alpha: 0.55), Color(white: 0, alpha: 0)])))
        drawEllipse(center: at, radiusX: w * 0.9, radiusY: w * 0.28)
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
