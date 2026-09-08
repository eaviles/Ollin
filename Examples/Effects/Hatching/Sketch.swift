import Ollin

/// **Hatching** draws a picture as pen work whose strokes run along its own
/// flow. The direction at every pixel comes from the structure tensor, the same
/// flow the painterly filters follow, so the marks bend around a form instead of
/// running across it the way a fixed screen does, and how many of them go down is
/// the picture's own tone: the ink covers about as much of the paper as the
/// picture is dark.
///
/// An engraved landscape, with the sun crossing the sky so the shading, and the
/// strokes that carry it, keep moving. Watch where the marks go: horizontal
/// across the sky, where the light changes with height alone; in rings around the
/// sun; and along each hill's own slope, which is what makes the hills read as
/// solid. The filter counts in pixels, so the scene is drawn into a layer at
/// `Scale` of the canvas, which is what sets how heavy the pen looks on a big
/// canvas. `Spacing` is the distance between strokes and `Length` how far one
/// runs before it ends: a short length is a stipple of dashes, a long one a comb.
/// `Directions` is how many layers stack as the tone darkens, 1 hatching one way
/// only and 2 crossing the first once it has laid all it may. `Compare` shows the
/// unhatched layer on the left half.
@main
final class Hatching: Sketch {

    @Param("Spacing", 2 ... 20, icon: "arrow.left.and.right", group: "Pen") var spacing = 6.0
    @Param("Length", 2 ... 48, icon: "line.diagonal", group: "Pen") var length = 36.0
    @Param("Directions", 1 ... 3, icon: "number", group: "Pen") var directions = 2
    @Param("Ink", icon: "drop.fill", group: "Pen") var ink = Color(hex: 0x1B2430)
    @Param("Paper", icon: "doc.plaintext", group: "Pen") var paper = Color(hex: 0xF2EAD8)
    @Param("Scale", 0.25 ... 1, icon: "arrow.down.right.and.arrow.up.left", group: "Layer") var layerScale = 1.0
    @Param(icon: "rectangle.split.2x1", group: "View") var compare = false

    override func draw() {
        background(paper)
        let scene = makeRenderTarget(scale: layerScale)
        withTarget(scene) { paint() }

        let drawn = scene.filtered(.hatching(spacing: spacing, length: length,
                                             directions: directions,
                                             foreground: ink, background: paper))
        drawImage(drawn.image, 0, 0)

        if compare {
            withClip(Rectangle(x: 0, y: 0, width: width / 2, height: height)) {
                drawImage(scene.image, 0, 0)
            }
            stroke(ink)
            strokeWeight(3)
            drawLine(width / 2, 0, width / 2, height)
        }
    }

    /// A sky that lightens toward the horizon, a sun crossing it, and four
    /// ridges, each shaded in bands that follow its own crest, so the light runs
    /// along the hill and the strokes run with it.
    private func paint() {
        noStroke()
        let sun = Vector2(width * (0.15 + 0.7 * (0.5 + 0.5 * sin(time * 0.18))),
                          height * (0.30 - 0.10 * sin(time * 0.18 + .pi / 2)))

        // The sky: deeper overhead, pale at the horizon, so its own flow runs
        // level and the strokes lie flat across it.
        let horizon = height * 0.52
        fill(.linear(from: Vector2(0, 0), to: Vector2(0, horizon),
                     Ramp([Color(white: 0.62), Color(white: 0.97)])))
        drawRect(0, 0, width, horizon)

        // The sun and the glow around it, which the strokes ring.
        fill(.radial(center: sun, radius: width * 0.34,
                     Ramp([Color(white: 1, alpha: 0.9), Color(white: 1, alpha: 0)])))
        drawCircle(center: sun, radius: width * 0.34)
        fill(Color(white: 1))
        drawCircle(center: sun, radius: width * 0.04)

        // Four ridges from the far one to the near, each a single shape under its
        // own crest, shaded from a point below it so the light bends around the
        // hill the way it would around something round. A gradient with curvature
        // is what turns the hatching along the slope; a flat band would leave the
        // filter nothing to read and the strokes would all point one way.
        let ridges: [(base: Double, rise: Double, top: Double, foot: Double, period: Double)] = [
            (0.56, 0.05, 0.96, 0.62, 300), (0.66, 0.07, 0.92, 0.50, 220),
            (0.78, 0.09, 0.88, 0.38, 170), (0.93, 0.11, 0.84, 0.31, 130),
        ]
        for ridge in ridges {
            let h = height
            let crestY = { (x: Double) -> Double in
                h * ridge.base - h * ridge.rise * (0.55 + 0.45 * sin(x / ridge.period + ridge.base * 9))
            }
            // The light rolls off from a point under the crest, drawn toward
            // whichever side of the sky the sun is on.
            let lit = width * (0.5 + 0.28 * ((sun.x - width / 2) / width))
            let center = Vector2(lit, height * ridge.base + height * 0.30)
            fill(.radial(center: center, radius: height * 0.42,
                         Ramp([Color(white: ridge.top), Color(white: ridge.foot)])))
            drawShape { path in
                var x = -20.0
                path.move(to: Vector2(x, height + 20))
                while x <= width + 20 {
                    path.line(to: Vector2(x, crestY(x)))
                    x += 6
                }
                path.line(to: Vector2(width + 20, height + 20))
                path.close()
            }
        }
    }
}
