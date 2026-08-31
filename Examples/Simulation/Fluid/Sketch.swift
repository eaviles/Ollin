import Ollin

/// A real-time **fluid** evolving on the GPU through the effects substrate — the
/// multi-field sibling of reaction-diffusion and Game of Life. A `.fluid` `SimField`
/// keeps a velocity field and a dye (color) field across frames; each frame it carries
/// the flow along itself (advection), confines its vorticity for fine swirling detail,
/// and stays incompressible through a Jacobi pressure solve. You *draw into it* to
/// inject dye (the mark's color) and pass `withField`'s `force:` to push the flow.
///
/// A single brush wanders on its own so the fluid is always moving; press and drag to
/// stir it yourself. The dye color cycles over time, and a bloom gives the swirls glow.
/// See `Simulation/GrayScott` and `Simulation/Automata` for the single-field stateful sims.
@main
final class Fluid_Example: Sketch {
    private var fluid: SimField!
    private var prev = Vector2.zero
    private var wasPressed = false

    override func setup() {
        // A half-resolution field: cheaper, with broad, creamy swirls. A gentle `curl`
        // and a little more velocity damping keep the flow soft rather than gusty.
        fluid = makeSimField(.fluid(curl: 12, velocityDissipation: 0.8), scale: 0.5)
        prev = Vector2(width * 0.5, height * 0.5)   // the brush starts at center (orbit's t = 0)
    }

    override func draw() {
        // The brush: the mouse while pressed, otherwise a smooth Lissajous orbit that
        // passes through the center at t = 0, so there's no jump on the first frame.
        let brush: Vector2
        if mouseIsPressed {
            brush = mouse
        } else {
            let t = time * 0.6
            brush = Vector2(width  * (0.5 + 0.32 * sin(t * 1.3)),
                            height * (0.5 + 0.32 * sin(t * 0.9)))
        }
        // Grabbing or releasing the mouse shouldn't fling the fluid, so zero the push on
        // the frame the brush mode changes (otherwise the jump becomes a huge impulse).
        if mouseIsPressed != wasPressed { prev = brush }
        wasPressed = mouseIsPressed

        // The brush's motion gives the push (softened a little so it nudges rather than
        // gusts); its slowly cycling color is the dye it lays down (hue/sat/value 0…1).
        let force = (brush - prev) * 0.5
        prev = brush
        withField(fluid, force: force) {
            noStroke()
            fill(Color(hue: time * 0.08, saturation: 0.9, brightness: 1, alpha: 0.6))
            drawCircle(brush.x, brush.y, 16)
        }

        // The dye covers the canvas, bloomed for glow. (`drawImage` already fills the
        // frame, so no `background` is needed — and a main-canvas `background` here would
        // wipe the seed drawn above, since it runs before the field is composited.)
        drawImage(fluid.filtered(.bloom(threshold: 0.15, amount: 0.9)).image, 0, 0)
        drawCaption("Fluid · a SimField evolving on the GPU · drag to stir")
    }
}
