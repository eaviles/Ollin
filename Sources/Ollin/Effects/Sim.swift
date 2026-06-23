import Foundation

/// A built-in feedback **simulation**: a field that evolves on the GPU each frame by
/// reading its own neighbourhood, the stateful sibling of the stateless `Filter`.
/// Where a `Filter` transforms an image once, a `Sim` runs on a *persistent* layer
/// (a `SimField`) whose state carries from one frame to the next — reaction-diffusion
/// patterns spreading, cellular-automaton cells living and dying.
///
/// You don't write the kernel: pick a `Sim` from the catalog, make a `SimField` with
/// it, and *draw into the field to seed/force it*. The field evolves by the sim and
/// you composite its `image` like any layer (filter or recolor it freely):
///
/// ```swift
/// var rd: SimField!
/// override func setup() { rd = simField(.reactionDiffusion(), scale: 0.5) }
///
/// override func draw() {
///     withField(rd) {                       // draw to seed: marks inject chemical
///         if mouseIsPressed { fill(.white); drawCircle(mouseX, mouseY, 16) }
///     }
///     drawImage(rd.filtered(.gradientMap(.magma)).image, 0, 0)   // evolve + recolor
/// }
/// ```
///
/// The state lives in the field's texels; what a drawn mark means is per-sim (see
/// each factory). Like `Filter`, a `Sim` is a small `Sendable` value descriptor — the
/// renderer reads it and runs the matching GPU passes.
public struct Sim: Sendable {

    /// The concrete simulations the renderer knows how to step. Internal: a sketch
    /// builds a `Sim` through the static factories below.
    enum Kind: Sendable {
        case reactionDiffusion(feed: Double, kill: Double)
        case gameOfLife
        case fluid(FluidConfig)
    }

    let kind: Kind

    /// The fixed configuration a `.fluid` hands the renderer's multi-pass solver. A
    /// fluid is the one multi-field sim: it bypasses the single-texture step hooks
    /// below and runs a dedicated pipeline (`runFluid`) over its own velocity + dye
    /// state, so its parameters travel here rather than in `params`.
    struct FluidConfig: Sendable {
        var curl: Float                 // vorticity-confinement strength (swirl detail)
        var velocityDissipation: Float  // how fast the flow slows
        var densityDissipation: Float   // how fast the dye fades
        var pressureIterations: Int     // Jacobi iterations of the pressure solve
        var buoyancy: Float             // upward lift per unit dye brightness (smoke)
        var dt: Float                   // fixed timestep (deterministic; not frame time)
    }

    /// Gray-Scott **reaction-diffusion**: two chemicals diffuse and react, and where
    /// they balance, Turing patterns emerge — coral, spots, stripes, mitosis. Draw
    /// light marks into the field to inject chemical B (it spreads from there). `feed`
    /// and `kill` pick the regime; the defaults give persistent dividing cells
    /// (mitosis). State is chemical A in red, B in green, so the raw `image` reads
    /// reddish — recolor it with `.filtered(.gradientMap(...))` or `.threshold(...)`.
    public static func reactionDiffusion(feed: Double = 0.055, kill: Double = 0.062) -> Sim {
        Sim(kind: .reactionDiffusion(feed: max(0, feed), kill: max(0, kill)))
    }

    /// Conway's **Game of Life**: each cell lives or dies by its eight neighbours
    /// (B3/S23). Draw white to make cells alive, black to kill them, then watch the
    /// gliders and oscillators evolve. A cell is read alive where its red channel is
    /// > 0.5, so the `image` is crisp black-and-white. Use a low `scale` on the field
    /// for visible, chunky cells (one texel is one cell).
    public static func gameOfLife() -> Sim { Sim(kind: .gameOfLife) }

    /// A real-time **fluid**: an incompressible flow that carries colour. Draw into the
    /// field to inject dye (the mark's colour) and push the fluid with `withField`'s
    /// `force:` (so dragging or an animated force swirls the colour). The flow advects,
    /// confines its vorticity (for fine swirling detail), and stays divergence-free via
    /// a Jacobi pressure solve. The raw `image` is the dye, ready to composite or
    /// `.filtered(.bloom)`. `curl` sets the swirliness, the dissipations how fast flow
    /// and dye fade, `pressureIterations` the solve accuracy, and `buoyancy` an optional
    /// upward lift on bright dye (a smoke that rises on its own, even unforced). Use a
    /// `scale` below 1 on the field for a cheaper, softer-featured fluid.
    public static func fluid(curl: Double = 30, velocityDissipation: Double = 0.2,
                             densityDissipation: Double = 1.0, pressureIterations: Int = 20,
                             buoyancy: Double = 0) -> Sim {
        Sim(kind: .fluid(FluidConfig(
            curl: Float(max(0, curl)),
            velocityDissipation: Float(max(0, velocityDissipation)),
            densityDissipation: Float(max(0, densityDissipation)),
            pressureIterations: max(1, min(60, pressureIterations)),
            buoyancy: Float(max(0, buoyancy)),
            dt: 0.016)))
    }

    // MARK: Renderer hooks (internal)

    /// Whether this sim runs the dedicated multi-field fluid pipeline (`runFluid`)
    /// rather than the single-texture step path. Its parameters live in `fluidConfig`.
    var isFluid: Bool { if case .fluid = kind { return true }; return false }

    /// The fluid configuration, when this is a `.fluid` (else `nil`).
    var fluidConfig: FluidConfig? { if case let .fluid(c) = kind { return c }; return nil }

    /// How many kernel steps run per frame. Reaction-diffusion takes many small steps
    /// for a lively, stable integration; a cellular automaton is one discrete
    /// generation per frame.
    var subSteps: Int {
        switch kind {
        case .reactionDiffusion: return 14
        case .gameOfLife:        return 1
        case .fluid:             return 1   // unused: the fluid runs its own pipeline
        }
    }

    /// The state a freshly allocated field starts at (before any seeding): the sim's
    /// rest state. Reaction-diffusion rests at chemical A = 1, B = 0 (an undisturbed
    /// substrate); the automaton rests dead/black.
    var restState: SIMD4<Float> {
        switch kind {
        case .reactionDiffusion: return SIMD4(1, 0, 0, 1)
        case .gameOfLife:        return SIMD4(0, 0, 0, 1)
        case .fluid:             return SIMD4(0, 0, 0, 1)   // unused: runFluid clears its own fields
        }
    }

    /// The `ollin_sim_*` fragment that advances one step.
    var stepFragment: String {
        switch kind {
        case .reactionDiffusion: return "ollin_sim_reaction_diffusion"
        case .gameOfLife:        return "ollin_sim_life"
        case .fluid:             return ""   // unused: the fluid dispatches its own fragments
        }
    }

    /// The per-step parameters bound alongside the texel size (renderer packs them as
    /// `params[1]`).
    var params: SIMD4<Float> {
        switch kind {
        case let .reactionDiffusion(feed, kill): return SIMD4(Float(feed), Float(kill), 0, 0)
        case .gameOfLife:                        return SIMD4(repeating: 0)
        case .fluid:                             return SIMD4(repeating: 0)   // unused
        }
    }
}
