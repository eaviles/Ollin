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
    }

    let kind: Kind

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

    // MARK: Renderer hooks (internal)

    /// How many kernel steps run per frame. Reaction-diffusion takes many small steps
    /// for a lively, stable integration; a cellular automaton is one discrete
    /// generation per frame.
    var subSteps: Int {
        switch kind {
        case .reactionDiffusion: return 14
        case .gameOfLife:        return 1
        }
    }

    /// The state a freshly allocated field starts at (before any seeding): the sim's
    /// rest state. Reaction-diffusion rests at chemical A = 1, B = 0 (an undisturbed
    /// substrate); the automaton rests dead/black.
    var restState: SIMD4<Float> {
        switch kind {
        case .reactionDiffusion: return SIMD4(1, 0, 0, 1)
        case .gameOfLife:        return SIMD4(0, 0, 0, 1)
        }
    }

    /// The `ollin_sim_*` fragment that advances one step.
    var stepFragment: String {
        switch kind {
        case .reactionDiffusion: return "ollin_sim_reaction_diffusion"
        case .gameOfLife:        return "ollin_sim_life"
        }
    }

    /// The per-step parameters bound alongside the texel size (renderer packs them as
    /// `params[1]`).
    var params: SIMD4<Float> {
        switch kind {
        case let .reactionDiffusion(feed, kill): return SIMD4(Float(feed), Float(kill), 0, 0)
        case .gameOfLife:                        return SIMD4(repeating: 0)
        }
    }
}
