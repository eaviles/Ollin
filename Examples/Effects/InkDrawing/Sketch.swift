import Ollin

/// **XDoG** draws a picture as pen and ink: a line wherever the picture has an
/// edge, solid ink where it is dark, and paper everywhere else. Underneath, two
/// blurs of the brightness are subtracted (the difference of Gaussians), pushed
/// hard over the tone, and cut at a threshold. The blur is taken across each edge
/// and its response gathered along the edge, following the edge's own direction,
/// which is what makes the lines run continuous instead of breaking into speckle.
///
/// A still life of a jug and three balls under a lamp that circles the room, so
/// the shadow side, and the ink with it, moves. `Radius` is the line scale,
/// `Sharpening` how far the edges are pushed over the tone, `Threshold` where
/// paper turns to ink, `Softness` the ramp under it (0 is a two-tone print, larger
/// keeps a gray wash below the cut), and `Flow` how far along an edge the response
/// is gathered (set it to 0 and watch the lines fray). `Compare` shows the layer
/// itself on the left half.
@main
final class InkDrawing: Sketch {

    @Param("Radius", 0.5 ... 6, icon: "scribble", group: "Line") var radius = 2.0
    @Param("Sharpening", 0 ... 40, icon: "bolt", group: "Line") var sharpening = 20.0
    @Param("Flow", 0 ... 12, icon: "wind", group: "Line") var flow = 3.0
    @Param("Threshold", 0 ... 1, icon: "circle.lefthalf.filled", group: "Cut") var threshold = 0.3
    @Param("Softness", 0 ... 0.5, icon: "drop", group: "Cut") var softness = 0.2
    @Param(icon: "paintbrush.pointed", group: "Colors") var ink = Color(hex: 0x1B1040)
    @Param(icon: "doc", group: "Colors") var paper = Color(hex: 0xF3EBDD)
    @Param(icon: "rectangle.split.2x1", group: "View") var compare = false

    override func draw() {
        background(paper)
        let scene = makeRenderTarget()
        withTarget(scene) { paint() }

        let inked = scene.filtered(.xdog(radius: radius, sharpening: sharpening,
                                          threshold: threshold, softness: softness,
                                          flow: flow, foreground: ink, background: paper))
        drawImage(inked.image, 0, 0)

        if compare {
            withClip(Rectangle(x: 0, y: 0, width: width / 2, height: height)) {
                drawImage(scene.image, 0, 0)
            }
            stroke(ink)
            strokeWeight(3)
            drawLine(width / 2, 0, width / 2, height)
        }
    }

    /// A table against a wall, a jug and three balls on it, each shaded toward a
    /// lamp that circles the room.
    private func paint() {
        let lamp = Vector2(width * (0.5 + 0.42 * cos(time * 0.35)),
                           height * (0.22 + 0.08 * sin(time * 0.7)))
        noStroke()

        let horizon = height * 0.6
        fill(.linear(from: Vector2(0, 0), to: Vector2(0, horizon),
                     Ramp([Color(hex: 0xD8D0C2), Color(hex: 0x8F8677)])))
        drawRect(0, 0, width, horizon)
        fill(.linear(from: Vector2(0, horizon), to: Vector2(0, height),
                     Ramp([Color(hex: 0x7A5A3C), Color(hex: 0x2A1D14)])))
        drawRect(0, horizon, width, height - horizon)

        // The jug: a cylinder shaded across, lit from whichever side the lamp is on,
        // with its mouth as an ellipse.
        let jugX = width * 0.12, jugY = height * 0.3, jugW = width * 0.16, jugH = height * 0.36
        let jugMid = jugX + jugW / 2
        contactShadow(under: Vector2(jugMid, jugY + jugH), width: jugW * 0.7, lamp: lamp)
        let litFromRight = lamp.x > jugMid
        fill(.linear(from: Vector2(litFromRight ? jugX + jugW : jugX, 0),
                     to: Vector2(litFromRight ? jugX : jugX + jugW, 0),
                     Ramp([Color(hex: 0xDDEBF0), Color(hex: 0x6B8E9F), Color(hex: 0x2A2430)])))
        drawRect(jugX, jugY, jugW, jugH)
        fill(Color(hex: 0x1E1A24))
        drawEllipse(jugMid, jugY, jugW / 2, jugH * 0.06)

        // Three balls, each with its bright spot turned toward the lamp.
        let balls: [(Vector2, Double, Color)] = [
            (Vector2(width * 0.42, height * 0.56), width * 0.11, Color(hex: 0xC94B3F)),
            (Vector2(width * 0.62, height * 0.63), width * 0.075, Color(hex: 0x3F86C9)),
            (Vector2(width * 0.8, height * 0.55), width * 0.13, Color(hex: 0xE0B34A)),
        ]
        for (center, r, tint) in balls {
            contactShadow(under: Vector2(center.x, center.y + r * 0.95), width: r * 1.6, lamp: lamp)
            let hot = center + (lamp - center).normalized * (r * 0.5)
            fill(.radial(center: hot, radius: r * 1.45,
                         Ramp([Color(hex: 0xFFF6E8), tint, Color(hex: 0x14161E)])))
            drawCircle(center: center, radius: r)
        }
    }

    /// A soft shadow on the table, stretched away from the lamp.
    private func contactShadow(under foot: Vector2, width w: Double, lamp: Vector2) {
        let away = (foot - lamp).normalized
        let at = foot + away * (w * 0.2)
        fill(.radial(center: at, radius: w * 0.9,
                     Ramp([Color(white: 0, alpha: 0.55), Color(white: 0, alpha: 0)])))
        drawEllipse(center: at, radiusX: w * 0.9, radiusY: w * 0.28)
    }
}
