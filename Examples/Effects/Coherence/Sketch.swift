import Ollin

/// **Shock** flattens a picture into regions with crisp edges that follow its
/// own flow, the coherence-enhancing filter. Each round smooths the layer along
/// the direction of least change at every pixel and sharpens it across that
/// direction with a shock filter: where the brightness bends toward bright a
/// pixel takes the brightest pixel within reach, where it bends toward dark the
/// darkest, so soft shading snaps into flat bands and everything along an edge
/// is drawn out into one coherent stroke. No color is invented; every pixel is a
/// blend, along its own contour, of colors the layer holds.
///
/// Fruit on a grained table under a lamp that circles the room, so the shading,
/// and the bands it snaps into, keeps moving. The filter counts in pixels, so
/// the scene is drawn into a layer at `Scale` of the canvas: at 0.5 the shock's
/// reach and the flow's length are twice what they would be at full size, which
/// is what makes the bands read on a big canvas. `Rounds` is how many times the
/// smoothing and the shock are applied, and so the level of abstraction (2 is a
/// light clean-up, 10 a poster). `Flow` is how far along the flow each round
/// smooths, `Radius` how far across an edge the shock reaches, `Smoothing` the
/// blur on the brightness the shock reads its sign from (raise it and the grain
/// stops making edges), and `Threshold` the bend under which nothing is
/// sharpened. `Compare` shows the layer itself on the left half.
@main
final class Coherence: Sketch {

    @Param("Rounds", 1 ... 10, icon: "arrow.clockwise", group: "Filter") var rounds = 3
    @Param("Flow", 1 ... 16, icon: "wind", group: "Filter") var flow = 6.0
    @Param("Radius", 1 ... 6, icon: "bolt", group: "Filter") var radius = 2.0
    @Param("Smoothing", 0 ... 6, icon: "drop", group: "Filter") var smoothing = 0.0
    @Param("Threshold", 0 ... 0.02, icon: "circle.lefthalf.filled", group: "Filter") var threshold = 0.005
    @Param("Scale", 0.25 ... 1, icon: "arrow.down.right.and.arrow.up.left", group: "Layer") var layerScale = 0.5
    @Param(icon: "rectangle.split.2x1", group: "View") var compare = false

    override func draw() {
        background(Color(hex: 0x1C1A1F))
        let scene = makeRenderTarget(scale: layerScale)
        withTarget(scene) { paint() }

        let flattened = scene.filtered(.shock(iterations: rounds, flow: flow, radius: radius,
                                              smoothing: smoothing, threshold: threshold))
        drawImage(flattened.image, 0, 0)

        if compare {
            withClip(Rectangle(x: 0, y: 0, width: width / 2, height: height)) {
                drawImage(scene.image, 0, 0)
            }
            stroke(Color(hex: 0xF3EBDD))
            strokeWeight(3)
            drawLine(width / 2, 0, width / 2, height)
        }
    }

    /// A wall, a grained table, and three pieces of fruit, each shaded toward a
    /// lamp that circles the room.
    private func paint() {
        let lamp = Vector2(width * (0.5 + 0.42 * cos(time * 0.3)),
                           height * (0.2 + 0.08 * sin(time * 0.6)))
        noStroke()

        // The wall, and a soft pool of light on it under the lamp.
        let horizon = height * 0.58
        fill(.linear(from: Vector2(0, 0), to: Vector2(0, horizon),
                     Ramp([Color(hex: 0xD9CDB8), Color(hex: 0x9C8E78)])))
        drawRect(0, 0, width, horizon)
        fill(.radial(center: Vector2(lamp.x, horizon * 0.5), radius: width * 0.45,
                     Ramp([Color(white: 1, alpha: 0.35), Color(white: 1, alpha: 0)])))
        drawRect(0, 0, width, horizon)

        // The table: a warm gradient, then the grain as long wavy lines that
        // darken and lighten along their length.
        fill(.linear(from: Vector2(0, horizon), to: Vector2(0, height),
                     Ramp([Color(hex: 0x9A6B3E), Color(hex: 0x4A2E1A)])))
        drawRect(0, horizon, width, height - horizon)
        seed(4)
        strokeWeight(1.5)
        for i in 0 ..< 70 {
            let y0 = horizon + Double(i) / 70 * (height - horizon) + random(-3, 3)
            let amplitude = random(2, 9)
            let period = random(140, 420)
            let phase = random(0, .pi * 2)
            let dark = random(0, 1) < 0.5
            stroke(dark ? Color(hex: 0x3B2213, alpha: random(0.25, 0.5))
                        : Color(hex: 0xC4925C, alpha: random(0.15, 0.35)))
            var points: [Vector2] = []
            for x in stride(from: -20.0, through: width + 20, by: 12) {
                points.append(Vector2(x, y0 + amplitude * sin(x / period * .pi * 2 + phase)))
            }
            drawPolyline(points)
        }
        noStroke()

        // An orange, a plum, and a lemon, each with its bright side toward the lamp.
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

    /// A soft shadow on the table, stretched away from the lamp.
    private func contactShadow(under foot: Vector2, width w: Double, lamp: Vector2) {
        let away = (foot - lamp).normalized
        let at = foot + away * (w * 0.15)
        fill(.radial(center: at, radius: w * 0.9,
                     Ramp([Color(white: 0, alpha: 0.5), Color(white: 0, alpha: 0)])))
        drawEllipse(center: at, radiusX: w * 0.9, radiusY: w * 0.26)
    }
}
