import Ollin

/// Lens flare: the light a camera adds to a picture all by itself.
///
/// Everything else in the renderer models the light and the surface. This one
/// models the *camera*. Some of a bright source reflects off the lens's own
/// interfaces instead of passing through them, comes back down the barrel, and
/// lands on the sensor somewhere it does not belong, which is what strings
/// ghosts along the line from the source through the middle of the frame.
///
/// So the call asks for a lens rather than for a look. `Lens.heliar` is a real
/// prescription, and its nine interfaces are what decide how many ghosts there
/// are, where each one sits, how large it is and what color it comes out. Stop
/// the iris down with `fStop` and every ghost shrinks together. Give the camera
/// blades and every ghost takes their shape, because a ghost is a picture of
/// the opening the light came through. That is also the opening the path-traced
/// export makes its out-of-focus highlights from, so the two cannot disagree.
///
/// Watch the lamp go behind the slab. The flare does not switch off: it fades
/// as the slab covers the source, because the strength follows how much of the
/// lamp the camera can actually see.
@main
final class LensFlare: Sketch {

    @Param(icon: "sun.max", group: "Flare")
    var flare = true

    @Param(0...2.5, icon: "dial.medium", group: "Flare")
    var strength = 1.0

    @Param(1.4...22, icon: "camera.aperture", group: "Iris")
    var fStop = 4.5

    @Param(0...11, icon: "hexagon", group: "Iris")
    var blades = 6

    @Param(icon: "swatchpalette", group: "Flare")
    var multicoated = true

    // A flat white matcap for the bulb prop (cached; an `Image` keeps its texture).
    private let bulbGlow = Image(width: 1, height: 1, color: Color(hex: 0xFFF6E2))

    override func draw() {
        background(Color(white: 0.03))

        var camera = Camera3D(eye: Vector3(0, 1.5, 7.4), target: Vector3(0, 1.5, 0),
                              near: 0.2, far: 60,
                              projection: .perspective(fieldOfView: .pi / 3.2))
        camera.apertureBlades = blades
        self.camera(camera)

        ambientLight(Color(white: 0.06))
        directionalLight(Color(white: 0.85), direction: Vector3(-0.5, -0.8, -0.4), intensity: 0.35)

        // The lamp drifts across the frame and passes behind the slab. It is a
        // real point light, so it lights the room as well as flaring.
        let lamp = Vector3(1.05 * cos(time * 0.35), 2.1 + 0.3 * sin(time * 0.27), -2.0)
        pointLight(Color(hex: 0xFFF2D6), at: lamp, intensity: 18)
        let lens = multicoated ? Lens.heliar.multicoated() : .heliar
        if flare { lensFlare(strength: strength, lens: lens.stopped(to: fStop)) }

        // The bulb itself, so there is something on screen for the flare to come
        // from. A flat single-color matcap ignores the scene lighting, which is
        // what a glowing thing looks like.
        withState {
            translate(lamp)
            fill(.white)
            matcap(bulbGlow)
            drawSphere(radius: 0.17)
        }
        matcap(nil)

        // The slab the lamp passes behind, and a floor to catch the light.
        fill(Color(white: 0.30))
        withState {
            translate(-1.5, 1.9, -1.2)
            drawBox(width: 1.1, height: 3.4, depth: 0.5)
        }
        fill(Color(white: 0.22))
        withState {
            translate(0, -0.05, 0)
            drawBox(width: 22, height: 0.1, depth: 22)
        }
        fill(Color(hex: 0x2E4658))
        for i in 0..<5 {
            withState {
                translate(-4.4 + Double(i) * 2.2, 0.45, -5.0)
                drawBox(width: 0.7, height: 0.9, depth: 0.7)
            }
        }

        // A bloom after the flare, so the ghosts glow the way everything else
        // bright in the frame does. The flare composites before the filters for
        // exactly this reason.
        postProcess(.bloom(threshold: 0.7, intensity: 0.8, radius: 0.05))
    }
}
