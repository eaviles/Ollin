import Ollin

/// A Gray-Scott **reaction-diffusion** field evolving on the GPU through the effects
/// substrate — the stateful sibling of a `Filter`. A `SimField` is a *persistent*
/// layer (like `Feedback`) that the renderer steps every frame; you seed it by
/// *drawing into it* with `withField`, and the chemicals spread from your marks into
/// coral-like Turing patterns. The raw field is data (chemical A in red, B in green),
/// so it's recoloured through the same `Filter` catalog as everything else.
///
/// Drag to inject more chemical and watch the reaction chase your cursor. See
/// `Basic/GameOfLife` for the cellular-automaton sibling.
@main
final class Simulation_Example: Sketch {
    private var rd: SimField!
    private var seeded = false

    override func setup() {
        // Logical size is the canvas; a half-resolution field gives broad, lively coral.
        rd = simField(.reactionDiffusion(), scale: 0.5)
    }

    override func draw() {
        withField(rd) {
            noStroke(); fill(.white)
            if !seeded {                                  // sow chemical B across the field once
                for _ in 0 ..< 90 { drawCircle(random(width), random(height), 7) }
                seeded = true
            }
            if mouseIsPressed { drawCircle(mouseX, mouseY, 16) }   // drag to inject more
        }
        // Recolour the raw field through the Filter catalog — the substrate's payoff.
        drawImage(rd.filtered(.gradientMap(.magma)).image, 0, 0)
        drawCaption("Reaction-diffusion · a SimField evolving on the GPU · drag to seed")
    }
}
