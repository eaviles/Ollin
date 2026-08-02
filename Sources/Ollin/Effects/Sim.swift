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
        case lenia(radius: Int, growthCenter: Double, growthWidth: Double,
                   timeScale: Double, rings: [Double])
        case ripples(speed: Double, damping: Double)
        case fluid(FluidConfig)
        case multiScaleTuring(scales: [TuringScale], seed: Double)
        case sandpile(pour: Int, topplings: Int)
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

    /// **Lenia**: the continuous Game of Life. The state is a smooth 0...1 mass; each
    /// step convolves it with a soft ring kernel, feeds that neighborhood potential
    /// through a bell-curve growth rule (mass near `growthCenter` grows, mass away from
    /// it decays), and integrates a small time step, so cells become glowing blobs that
    /// pulse, split, and swim. Draw gray-to-white marks into the field to add mass (a
    /// few soft blobs are enough; black erases); the defaults are the classic regime
    /// where creatures self-organize.
    ///
    /// The raw `image` is grayscale mass, made to be recolored with
    /// `.filtered(.gradientMap(...))`. The kernel reads `radius` texels around every
    /// texel each step, so field `scale` is the cost lever; around 0.5 is plenty.
    ///
    /// - Parameters:
    ///   - radius: Kernel reach in field texels (clamped 2...32). Bigger sees further
    ///     and makes larger, slower creatures.
    ///   - growthCenter: The neighborhood mass that grows fastest (0...1).
    ///   - growthWidth: How forgiving growth is around that center. Narrow is stricter
    ///     and more lifelike; wide blooms.
    ///   - timeScale: Steps per unit time; the integration step is its inverse. Higher
    ///     is smoother and slower.
    ///   - rings: Peak height of each concentric kernel ring, up to three, each 0...1.
    ///     The default single ring is the classic kernel; extra rings breed different
    ///     species.
    public static func lenia(radius: Int = 13, growthCenter: Double = 0.15,
                             growthWidth: Double = 0.015, timeScale: Double = 10,
                             rings: [Double] = [1]) -> Sim {
        let clamped = rings.isEmpty ? [1] : rings.prefix(3).map { min(1, max(0, $0)) }
        return Sim(kind: .lenia(radius: min(32, max(2, radius)),
                                growthCenter: min(1, max(0, growthCenter)),
                                growthWidth: max(0.0001, growthWidth),
                                timeScale: max(1, timeScale),
                                rings: clamped))
    }

    /// A water surface: the 2D wave equation on a height field, the classic
    /// interactive **ripple pool**. Draw into the field to drop water: a mark's
    /// brightness is *added* to the surface height (velocity is left alone), the
    /// bump collapses, and rings spread, reflect softly off the borders, and die
    /// away. Soft-edged marks make the cleanest rings: a `drawCircle` under a
    /// radial `Gradient` fading to clear is the ideal drop, where a hard-edged
    /// disc rings at every frequency (a real splash).
    /// Dab marks rather than holding them: an opaque mark held down pours water
    /// every frame.
    ///
    /// The state is height in red, velocity in green, both signed around zero.
    /// The raw `image` is only the debugging view; recolor it, or better, shade
    /// it as a surface with `.filtered(.relight(...))`. `speed` sets how fast
    /// rings run (it is the neighbor-coupling gain) and `damping` (0…1) how long
    /// they last, with a soft absorbing rim at the borders so echoes fade instead
    /// of slapping back hard.
    ///
    /// `speed` is capped at 1 because the step goes unstable at 2: there the
    /// shortest wave the grid can hold (a two-pixel checkerboard) sits on a
    /// repeated root and grows with every step instead of oscillating, so each
    /// drop pumps a grid-scale rattle that damping can only hold at a level
    /// rather than remove. It settles some twenty times stronger than the rings
    /// themselves and shades into glitter. Below 1 that mode behaves like every
    /// other one, and rings still run at a usable pace because the step takes six
    /// substeps a frame.
    public static func ripples(speed: Double = 0.5, damping: Double = 0.995) -> Sim {
        Sim(kind: .ripples(speed: min(max(speed, 0.05), 1), damping: min(max(damping, 0), 1)))
    }

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

    /// **Multi-scale Turing patterns**: one substance, looked at through several
    /// magnifications at once. Each scale averages the field over a small disc
    /// (the *activator*) and a larger one (the *inhibitor*); where the small
    /// average is the greater, the field brightens a little, otherwise it darkens.
    /// Run at a single scale that rule alone grows the stripes and spots of a
    /// zebra or a whale shark. Run at several, each pixel each step picks the
    /// scale whose two averages *disagree least* and lets only that one act, so
    /// broad forms and fine detail settle in the same picture and the result
    /// looks strikingly like an electron micrograph of a diatom.
    ///
    /// The field starts as noise and organizes itself, so a Turing field needs no
    /// seeding to get going. Drawing into it still works and is how you disturb a
    /// settled pattern: a mark's brightness *replaces* the field where it covers
    /// (white pushes toward the top of the range, black toward the bottom), and
    /// the pattern heals around it over the next few hundred steps. Edges wrap, so
    /// the picture tiles.
    ///
    /// The raw `image` is the field as grayscale, ready to recolor with
    /// `.filtered(.gradientMap(...))` or to shade as relief with
    /// `.filtered(.relight(...))`. That lit-from-above look is an accident of a
    /// flat 2D algorithm, and it reads as depth.
    ///
    /// ```swift
    /// var turing: SimField!
    /// override func setup() { turing = simField(.multiScaleTuring(), scale: 0.5) }
    /// override func draw() { drawImage(turing.filtered(.gradientMap(.magma)).image, 0, 0) }
    /// ```
    ///
    /// - Parameters:
    ///   - scales: The magnifications in play, in any order (up to six; see
    ///     `TuringScale`). The default ladder doubles the radii from 2 to 32
    ///     texels, the classic five-scale arrangement.
    ///   - seed: Picks the starting noise, so the same seed replays the same
    ///     pattern. Pass the sketch's `variation` to tie it to the seed the rest of
    ///     the sketch uses.
    public static func multiScaleTuring(scales: [TuringScale] = TuringScale.ladder,
                                        seed: Double = 1) -> Sim {
        let clamped = scales.isEmpty ? TuringScale.ladder : Array(scales.prefix(TuringScale.maxScales))
        return Sim(kind: .multiScaleTuring(scales: clamped, seed: seed))
    }

    /// The **Abelian sandpile**: grains pile up on a grid, and any cell holding four
    /// or more topples, keeping the rest and sending one grain to each of its four
    /// neighbours. A toppling can tip its neighbours over too, so one grain dropped
    /// on a settled pile can set off an avalanche of any size (the model that named
    /// *self-organized criticality*). All the unstable cells topple together each
    /// pass, as many times as each can, which is safe because topplings commute
    /// (the "abelian" in the name): however the work is ordered or batched, the
    /// pile settles into the same configuration. Grains that topple over the
    /// field's edge fall off and are gone; that slow leak is what lets a fed pile
    /// keep settling instead of saturating.
    ///
    /// Draw into the field to pour sand: a full-white mark adds `pour` grains to
    /// every texel it covers, each frame, scaled by the mark's brightness and
    /// rounded to whole grains. Sand is only ever added (nothing erases; easing off
    /// is how you stop). The classic circular figure with its self-similar lobes
    /// comes from the drop-and-relax protocol: pour one heavy mark on a single
    /// frame (`pour: 1024` under a small disc) and let the mountain collapse. A
    /// mark *held* down is a torrent instead: its middle stays molten, cells at
    /// four grains and above, for as long as you keep pouring, and crystallizes
    /// into lacework when you stop.
    ///
    /// The state is the grain count in quarters: a stable cell reads 0, ¼, ½, or ¾
    /// gray for 0…3 grains, and cells holding more flash brighter. Four flat levels
    /// are made for `.filtered(.gradientMap(...))`: one color per count, the
    /// classic way these piles are pictured. An avalanche front moves one texel per
    /// toppling pass, so `topplings` is the pacing dial: a few passes per frame let
    /// you watch each wave roll across the pile, 128 hurries a collapse.
    public static func sandpile(pour: Int = 64, topplings: Int = 32) -> Sim {
        Sim(kind: .sandpile(pour: max(1, min(1024, pour)),
                            topplings: max(1, min(128, topplings))))
    }

    // MARK: Renderer hooks (internal)

    /// Whether this sim runs the dedicated multi-field fluid pipeline (`runFluid`)
    /// rather than the single-texture step path. Its parameters live in `fluidConfig`.
    var isFluid: Bool { if case .fluid = kind { return true }; return false }

    /// The fluid configuration, when this is a `.fluid` (else `nil`).
    var fluidConfig: FluidConfig? { if case let .fluid(c) = kind { return c }; return nil }

    /// The multi-scale Turing configuration, when this is a `.multiScaleTuring`
    /// (else `nil`). Like the fluid it runs its own multi-pass pipeline
    /// (`runMultiScaleTuring`) rather than the single-texture step path, because a
    /// step needs a blur pyramid and a whole-field extent before it can advance.
    var turingConfig: (scales: [TuringScale], seed: Double)? {
        if case let .multiScaleTuring(scales, seed) = kind { return (scales, seed) }
        return nil
    }

    /// How many kernel steps run per frame. Reaction-diffusion takes many small steps
    /// for a lively, stable integration; a cellular automaton is one discrete
    /// generation per frame.
    var subSteps: Int {
        switch kind {
        case .reactionDiffusion: return 14
        case .gameOfLife:        return 1
        case .lenia:             return 1
        case .ripples:           return 6   // rings cross the field at a usable pace:
                                            // wave speed scales as the square root of
                                            // the coupling gain, so a gain held well
                                            // under its stability limit buys its pace
                                            // back in substeps instead
        case .fluid:             return 1   // unused: the fluid runs its own pipeline
        case .multiScaleTuring:  return 1   // unused: Turing runs its own pipeline
        case let .sandpile(_, topplings):
            return topplings                // the pacing dial: an avalanche front
                                            // moves one texel per pass
        }
    }

    /// The state a freshly allocated field starts at (before any seeding): the sim's
    /// rest state. Reaction-diffusion rests at chemical A = 1, B = 0 (an undisturbed
    /// substrate); the automaton rests dead/black.
    var restState: SIMD4<Float> {
        switch kind {
        case .reactionDiffusion: return SIMD4(1, 0, 0, 1)
        case .gameOfLife:        return SIMD4(0, 0, 0, 1)
        case .lenia:             return SIMD4(0, 0, 0, 1)
        case .ripples:           return SIMD4(0, 0, 0, 1)   // a still surface
        case .fluid:             return SIMD4(0, 0, 0, 1)   // unused: runFluid clears its own fields
        case .multiScaleTuring:  return SIMD4(0, 0, 0, 1)   // unused: the field starts as noise,
                                                            // not a constant (a flat field is a
                                                            // fixed point of the rule), so the slot
                                                            // fills it with a seeded hash instead
        case .sandpile:          return SIMD4(0, 0, 0, 1)   // an empty table
        }
    }

    /// The `ollin_sim_*` fragment that advances one step.
    var stepFragment: String {
        switch kind {
        case .reactionDiffusion: return "ollin_sim_reaction_diffusion"
        case .gameOfLife:        return "ollin_sim_life"
        case .lenia:             return "ollin_sim_lenia"
        case .ripples:           return "ollin_sim_ripples"
        case .fluid:             return ""   // unused: the fluid dispatches its own fragments
        case .multiScaleTuring:  return ""   // unused: Turing dispatches its own fragments
        case .sandpile:          return "ollin_sim_sandpile"
        }
    }

    /// The `ollin_sim_*` fragment that composites this frame's drawn seed marks
    /// onto the state before stepping. Most sims *replace* the state's channels
    /// with the mark's color where it covers (the default); ripples instead
    /// *adds* the mark's brightness to the height channel only, since its other
    /// channel is velocity and a mark that overwrote it would pin the surface
    /// (the drop model the wave equation wants).
    var injectFragment: String {
        switch kind {
        case .ripples:          return "ollin_sim_inject_height"
        case .multiScaleTuring: return "ollin_sim_inject_luma"
        case .sandpile:         return "ollin_sim_inject_sand"
        default:                return "ollin_sim_inject"
        }
    }

    /// The per-step parameter rows bound after the texel size (the renderer passes
    /// them to the step fragment as `params[1]` onward).
    var params: [SIMD4<Float>] {
        switch kind {
        case let .reactionDiffusion(feed, kill):
            return [SIMD4(Float(feed), Float(kill), 0, 0)]
        case .gameOfLife:
            return []
        case let .lenia(radius, growthCenter, growthWidth, timeScale, rings):
            var ringRow = SIMD4<Float>(0, 0, 0, Float(rings.count))
            for (i, peak) in rings.prefix(3).enumerated() { ringRow[i] = Float(peak) }
            return [SIMD4(Float(radius), Float(1 / timeScale),
                          Float(growthCenter), Float(growthWidth)),
                    ringRow]
        case let .ripples(speed, damping):
            return [SIMD4(Float(speed), Float(damping), 0, 0)]
        case .fluid:
            return []   // unused: the fluid binds per-pass parameters itself
        case .multiScaleTuring:
            return []   // unused: Turing binds per-pass parameters itself
        case let .sandpile(pour, _):
            return [SIMD4(Float(pour), 0, 0, 0)]   // read by the inject, not the step
        }
    }
}

/// One magnification in a `Sim.multiScaleTuring` field: a pair of averaging radii
/// and how hard that scale pushes when it wins the step.
///
/// A scale is a Turing rule in miniature. It averages the field over a disc of
/// `activatorRadius` and again over a larger disc of `inhibitorRadius`; the sign of
/// the difference says which way to move, and `amount` says how far. What makes the
/// picture multi-scale is that every pixel each step runs *all* the scales and only
/// the one whose two averages are closest together gets to act, so a region settles
/// into whichever magnification currently has the least to say about it.
///
/// The radii are in field texels, so they follow the `SimField`'s `scale`: a field at
/// `scale: 0.5` on a 1080 canvas is 540 texels across, and a radius of 32 spans about
/// 6% of it. Keep a clear gap between the scales (the default ladder doubles both
/// radii each rung); scales that overlap closely tend to produce one blurred texture
/// instead of distinct nested structure.
public struct TuringScale: Sendable, Equatable {

    /// How many scales one field can run. Six is a practical ceiling: the step
    /// samples the blur pyramid twice per scale, times the symmetry count.
    public static let maxScales = 6

    /// Radius of the smaller, activating average, in field texels.
    public var activatorRadius: Double
    /// Radius of the larger, inhibiting average, in field texels. Larger than
    /// `activatorRadius`; the ratio between them sets how separated the features are.
    public var inhibitorRadius: Double
    /// How far the field moves in one step when this scale wins, as a fraction of the
    /// field's full range. Small is the point: large amounts race to a coarse
    /// equilibrium and lose the fine structure, and they flicker in an animation.
    public var amount: Double
    /// Multiplies both averages before they are compared, so it scales this rule's say
    /// in the least-variation contest: above 1 the scale wins more often, below 1 less.
    /// A negative weight inverts the rule, which is what makes a scale carve dark
    /// features where it would otherwise raise light ones.
    public var weight: Double
    /// Folds this scale's averages around the field's center with n-fold rotational
    /// symmetry, by averaging each point with its n counterparts around the circle.
    /// 0 or 1 leaves the scale free. Different symmetries on different scales is the
    /// arrangement behind the diatom-like plates in McCabe's later figures.
    public var symmetry: Int

    /// The radius over which this scale's disagreement is averaged before the scales are
    /// compared, in field texels. This is the knob that decides how large a region a
    /// scale can claim, and it is load-bearing rather than a refinement: read at a single
    /// point, a fine scale's disagreement passes through zero along every contour of its
    /// own structure, and since the *least* disagreement wins, it would take a dense web
    /// of pixels everywhere and bury the coarse scales. Averaging over the scale's own
    /// neighbourhood removes those accidental zeros. Defaults to `inhibitorRadius`;
    /// smaller sharpens the boundaries between scale regions, and 0 (single point) gives
    /// the finest, most detailed picture, which is also the least multi-scale one.
    public var variationRadius: Double

    public init(activatorRadius: Double, inhibitorRadius: Double, amount: Double,
                weight: Double = 1, symmetry: Int = 0, variationRadius: Double? = nil) {
        self.activatorRadius = max(0.5, activatorRadius)
        self.inhibitorRadius = max(self.activatorRadius + 0.5, inhibitorRadius)
        self.amount = max(0, amount)
        self.weight = weight
        self.symmetry = max(0, min(24, symmetry))
        self.variationRadius = max(0, variationRadius ?? self.inhibitorRadius)
    }

    /// The classic five-rung ladder: activator radii doubling from 2 to 32 texels, each
    /// rung's inhibitor twice its activator, all pushing equally hard.
    ///
    /// The two choices worth knowing before changing them. **Equal amounts** are what
    /// make the picture nest: whichever rung pushes hardest sets the field's range, and
    /// after every step renormalizes, the rest are squeezed toward mid gray, so an uneven
    /// ladder gives one scale's pattern with the others as a faint wash. **Starting at 2
    /// rather than 1** keeps the finest features a few texels across; a rung at radius 1
    /// works on single texels, and pixel-scale features read as speckle rather than as
    /// detail.
    public static let ladder: [TuringScale] = [
        TuringScale(activatorRadius: 2,  inhibitorRadius: 4,  amount: 0.02),
        TuringScale(activatorRadius: 4,  inhibitorRadius: 8,  amount: 0.02),
        TuringScale(activatorRadius: 8,  inhibitorRadius: 16, amount: 0.02),
        TuringScale(activatorRadius: 16, inhibitorRadius: 32, amount: 0.02),
        TuringScale(activatorRadius: 32, inhibitorRadius: 64, amount: 0.02),
    ]

    /// The ladder folded into n-fold rotational symmetry, the arrangement that gives
    /// the radially symmetric plates. Every scale takes the same fold.
    public static func rosette(_ symmetry: Int) -> [TuringScale] {
        ladder.map {
            TuringScale(activatorRadius: $0.activatorRadius, inhibitorRadius: $0.inhibitorRadius,
                        amount: $0.amount, weight: $0.weight, symmetry: symmetry,
                        variationRadius: $0.variationRadius)
        }
    }

    /// A coarser, sparser ladder: three widely separated scales, so the field settles into
    /// big smooth lobes with just a little structure riding on them.
    public static let broad: [TuringScale] = [
        TuringScale(activatorRadius: 5,  inhibitorRadius: 12, amount: 0.02),
        TuringScale(activatorRadius: 16, inhibitorRadius: 40, amount: 0.02),
        TuringScale(activatorRadius: 48, inhibitorRadius: 110, amount: 0.02),
    ]
}

/// The curated arrangements again on the array itself, so they can be written with
/// leading-dot syntax where a `Sim.multiScaleTuring` expects a list of scales:
/// `.multiScaleTuring(scales: .rosette(9))`.
extension [TuringScale] {
    /// See `TuringScale.ladder`.
    public static var ladder: [TuringScale] { TuringScale.ladder }
    /// See `TuringScale.broad`.
    public static var broad: [TuringScale] { TuringScale.broad }
    /// See `TuringScale.rosette(_:)`.
    public static func rosette(_ symmetry: Int) -> [TuringScale] { TuringScale.rosette(symmetry) }
}
