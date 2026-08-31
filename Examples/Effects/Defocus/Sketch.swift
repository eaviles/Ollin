import Ollin

/// Depth of field through the two-input combine path: a layer **defocused by** a
/// depth map. The depth map is just another layer, its luminance read as
/// distance (0 near, 1 far), so it can be anything you draw. Here the scene is
/// a scatter of orbs at staggered depths, and the depth `aside` redraws each
/// orb filled with a gray that *is* its depth (black near, white far). Drag
/// left/right to rack the focal plane through them: whichever orbs sit at the
/// focus depth stay crisp while the rest melt into bokeh.
///
/// The blur is a single-pass circle-of-confusion gather, so a nearer, more
/// defocused orb spills softly over the farther ones. `focus` is the in-focus
/// depth, `range` the half-width of the sharp band, `maxBlur` how far the most
/// defocused orbs blur.
///
/// The iris shapes the melt. An out-of-focus point of light lands as a picture
/// of the opening it passed through, so the row of far lights along the top
/// blurs into polygons of `blades` sides (0 is a round opening, 5 to 11 is what
/// a real lens carries), `turn` rotates the opening, and `catsEye` is the
/// barrel around the iris, clipping a highlight toward the corners until it
/// lies down into a lemon. The lights are drawn small, because a highlight
/// comes out the size of the opening plus the size of the source, and far past
/// white, because spreading one point across a whole opening divides its light
/// by the area it now covers; the blur is what brings that color back into
/// range. A 3D scene says none of this twice: `Camera3D.apertureBlades` already
/// shapes its own defocus, flare ghosts, and path-traced export, and naming
/// `blades` at the call is for a blur the camera knows nothing about.
///
/// Try it: widen `range` for a deeper focus, run `blades` down from 11 to 3 and
/// watch the corners arrive, or feed `.defocused(by:)` a smooth top-to-bottom
/// gradient aside instead of the per-orb map (a tilt-shift look).
@main
final class Defocus_Example: Sketch {

    @Param(0 ... 11, icon: "hexagon", group: "Iris")
    var blades = 5

    @Param(0 ... 1, icon: "rotate.right", group: "Iris")
    var turn = 0.0

    @Param(0 ... 1, icon: "camera.aperture", group: "Iris")
    var catsEye = 0.5

    /// One orb: a depth (0 near, 1 far), a screen position, and a hue.
    struct Orb { let depth, x, y, hue: Double }

    /// A fixed scatter, sorted far-first so nearer orbs occlude, in both the
    /// color scene and the depth map, which must agree on what's in front.
    lazy var orbs: [Orb] = {
        seed(7)
        return (0 ..< 48).map { _ in
            Orb(depth: random(1), x: random(1), y: random(1), hue: random(1))
        }.sorted { $0.depth > $1.depth }
    }()

    override func draw() {
        // Drag to rack focus by hand; left idle, the focal plane sweeps on its own.
        let focus = mouseIsPressed ? clamp(mouseX / width, 0, 1)
                                   : 0.5 + 0.45 * sin(time * 0.4)

        compose {
            layer {
                background(Color(white: 0.05))
                noStroke()

                // The far point lights, drawn first so nearer orbs occlude them.
                for i in 0 ..< 12 {
                    let x = (Double(i) + 0.5) / 12 * width
                    let y = height * 0.08 + sin(time * 0.25 + Double(i)) * 10
                    fill(glow(Color(hue: Double(i) / 12, saturation: 0.35, brightness: 1)))
                    drawCircle(x, y, 8)
                }

                // The orbs, far-first. Nearer orbs read brighter and larger,
                // the usual distance cues.
                for orb in orbs {
                    let near = 1 - orb.depth
                    fill(Color(hue: orb.hue, saturation: 0.7, brightness: 0.45 + 0.55 * near))
                    drawCircle(orb.x * width, orb.y * height, radius(orb))
                }
            }
            .defocused(by: aside {
                background(.white)                        // gaps and the lights read as far
                noStroke()
                for orb in orbs {
                    fill(Color(white: orb.depth))         // the gray IS the depth
                    drawCircle(orb.x * width, orb.y * height, radius(orb))
                }
            }, focus: focus, range: 0.07, maxBlur: 48,
               blades: blades, irisAngle: turn * .tau / max(1, Double(blades)),
               catsEye: catsEye)
        }

        let iris = blades < 3 ? "round" : "\(blades) blades"
        drawCaption("depth of field: focus \(String(format: "%.2f", focus)), \(iris) (drag to rack)")
    }

    func radius(_ orb: Orb) -> Double { 26 + (1 - orb.depth) * 96 }

    /// A color far past white, which is what a light is. Nothing can show it as
    /// drawn; the blur is what brings it back into range.
    func glow(_ color: Color, by amount: Double = 4) -> Color {
        Color(red: color.red * amount, green: color.green * amount, blue: color.blue * amount)
    }
}
