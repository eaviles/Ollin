// figure: frame=0 themed
//
// Guide diagram (Chapter 16): hatching that follows the picture. A sphere and a
// pot on a table drawn into a layer, then the same layer through `.hatching()`
// one way and crossed: the strokes wrap each form, and the second direction
// crosses the first only where one has laid all it may.
import Ollin
import OllinDiagram

final class Hatched: Sketch {
    override var canvasSize: CanvasSize { .size(880, 400) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }

    override func draw() {
        background(paper)

        let panels = (0 ..< 3).map {
            Rectangle(x: 46 + Double($0) * 274, y: 92, width: 250, height: 180)
        }

        // The layer is the panel's own size, so the spacing and the stroke length
        // stay the pixels the filter counts.
        let scene = makeRenderTarget(width: 250, height: 180)
        withTarget(scene) { paint(width: 250, height: 180) }

        drawImage(scene.image, in: panels[0])
        drawImage(scene.filtered(.hatching(spacing: 3, length: 16, directions: 1)).image,
                  in: panels[1])
        drawImage(scene.filtered(.hatching(spacing: 3, length: 16, directions: 2)).image,
                  in: panels[2])

        frame(panels[0], title: "the layer")
        frame(panels[1], title: "directions: 1")
        frame(panels[2], title: "directions: 2")

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("the strokes run along the picture's own flow, as many as the tone is dark",
                 width / 2, 312)
    }

    /// A sphere and a straight-sided pot on a table, each shaded from the light
    /// so the flow inside them curves the way the form does.
    func paint(width: Double, height: Double) {
        let lamp = Vector2(width * 0.22, height * 0.08)
        noStroke()

        // Wall and table, both level gradients, so their strokes lie flat.
        let horizon = height * 0.56
        fill(.linear(from: Vector2(0, 0), to: Vector2(0, horizon),
                     Ramp([Color(white: 0.72), Color(white: 0.99)])))
        drawRect(0, 0, width, horizon)
        fill(.linear(from: Vector2(0, horizon), to: Vector2(0, height),
                     Ramp([Color(white: 0.97), Color(white: 0.40)])))
        drawRect(0, horizon, width, height - horizon)

        // The pot: shaded across its width, so the strokes run down it.
        let potRect = Rectangle(x: width * 0.60, y: height * 0.30, width: width * 0.20,
                                height: height * 0.44)
        fill(.linear(from: Vector2(potRect.x, 0), to: Vector2(potRect.x + potRect.width, 0),
                     Ramp([Color(white: 0.97), Color(white: 0.16)])))
        drawRect(potRect)

        // The sphere: shaded from the bright spot the lamp puts on it, so every
        // ring of equal light is a circle and the strokes ring it too.
        let center = Vector2(width * 0.33, height * 0.60)
        let radius = width * 0.19
        let hot = center + (lamp - center).normalized * (radius * 0.5)
        fill(.radial(center: Vector2(center.x + radius * 0.2, center.y + radius * 1.05),
                     radius: radius * 1.5,
                     Ramp([Color(white: 0, alpha: 0.45), Color(white: 0, alpha: 0)])))
        drawEllipse(center: Vector2(center.x + radius * 0.2, center.y + radius * 1.02),
                    radiusX: radius * 1.3, radiusY: radius * 0.3)
        fill(.radial(center: hot, radius: radius * 1.7,
                     Ramp([Color(white: 1.0), Color(white: 0.82), Color(white: 0.10)])))
        drawCircle(center: center, radius: radius)
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
