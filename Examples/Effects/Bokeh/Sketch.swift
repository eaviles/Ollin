import Ollin

/// The shape of the opening the light came through.
///
/// A point of light that is out of focus does not land as a point. It lands as a
/// picture of the iris it passed through, scaled up by how far out of focus it is.
/// So a round opening leaves round highlights, six blades leave hexagons, and the
/// whole look people call bokeh is really a portrait of the lens.
///
/// Two things shape it here. `blades` is the iris itself: `0` is a round opening, and
/// 5 to 11 is what a real lens carries. Run the blades down from 11 to 3 and watch the
/// corners arrive: a highlight is nearly round at 11, plainly five-sided at 5, and an
/// unmistakable triangle at 3. `catsEye` is the barrel around the iris. Away from the
/// middle of the frame the barrel clips the opening from both sides, so a highlight
/// that is whole in the middle lies down into a lemon toward the corners, the long way
/// around the frame. Turn `catsEye` up and watch the corners go first.
///
/// A word on how far this can be pushed. The blur gathers a fixed budget of samples,
/// so a light much smaller than the spacing between them shows the pattern of the
/// gather rather than a clean edge. Keep a light a few pixels across, or raise
/// `quality`, and the shape comes back.
///
/// The lights are drawn far away and the near paving is left sharp, so the depth map
/// is two flat grays and nothing more: the shapes come entirely from the opening.
///
/// A 3D scene needs none of this said twice. `Camera3D.apertureBlades` already
/// decides the shape of a flare's ghosts and of the path-traced export's own
/// highlights, and a scene defocused by its own depth reads the same setting, so the
/// live picture and the exported one wear one lens. Naming `blades` at the call, as
/// this sketch does, is for a blur the camera knows nothing about.
@main
final class Bokeh: Sketch {

    @Param(0...11, icon: "hexagon", group: "Iris")
    var blades = 5

    @Param(0...1, icon: "rotate.right", group: "Iris")
    var turn = 0.0

    @Param(0...1, icon: "camera.aperture", group: "Barrel")
    var catsEye = 0.8

    @Param(10...110, icon: "circle.dotted", group: "Blur")
    var blur = 62.0

    /// A fixed scatter of lights, each with a size and a color.
    lazy var lights: [(x: Double, y: Double, size: Double, hue: Double)] = {
        seed(11)
        return (0 ..< 44).map { _ in
            (x: random(1), y: random(0.72), size: random(6, 11), hue: random(1))
        }
    }()

    override func draw() {
        compose {
            layer {
                background(Color(hex: 0x05060B))

                // The lights, small and far brighter than a picture can show. Both
                // halves matter. Small, because a highlight comes out the size of the
                // opening plus the size of the source, so a large source rounds the
                // corners off the shape. Bright, because spreading one point across a
                // whole opening divides its light by the area it now covers. That is
                // what a real lens does, and it is why real lights are so much
                // brighter than everything around them.
                noStroke()
                for light in lights {
                    let drift = sin(time * 0.25 + light.hue * .tau) * 14
                    fill(glow(Color(hue: light.hue, saturation: 0.35, brightness: 1)))
                    drawCircle(light.x * width + drift, light.y * height, light.size)
                }

                // The sharp foreground: a rail the eye can hold on to while the lights
                // behind it melt.
                fill(Color(hex: 0x141824))
                drawRect(0, height * 0.82, width, height * 0.18)
                stroke(Color(hex: 0x2A3247)); strokeWeight(3)
                drawLine(0, height * 0.82, width, height * 0.82)
            }
            .defocused(by: aside {
                background(.white)                          // the lights sit far away
                noStroke(); fill(.black)                    // the rail sits at the focus
                drawRect(0, height * 0.82, width, height * 0.18)
            }, focus: 0, range: 0.05, maxBlur: blur,
               blades: blades, irisAngle: turn * .tau / max(1, Double(blades)),
               catsEye: catsEye)
        }

        let iris = blades < 3 ? "round" : "\(blades) blades"
        drawCaption("bokeh: \(iris), cat's eye \(String(format: "%.1f", catsEye))")
    }

    /// A color far past white, which is what a light is. Nothing can show it as drawn;
    /// the blur is what brings it back into range.
    func glow(_ color: Color, by amount: Double = 4) -> Color {
        Color(red: color.red * amount, green: color.green * amount, blue: color.blue * amount)
    }
}
