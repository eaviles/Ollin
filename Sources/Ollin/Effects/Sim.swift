import Foundation

/// A built-in feedback **simulation**: a field that evolves on the GPU each frame by
/// reading its own neighborhood, the stateful sibling of the stateless `Filter`.
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
/// override func setup() { rd = makeSimField(.reactionDiffusion(), scale: 0.5) }
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
        case reactionDiffusion(feed: Double, kill: Double, toFeed: Double, toKill: Double)
        case gameOfLife
        case lenia(radius: Int, growthCenter: Double, growthWidth: Double,
                   timeScale: Double, rings: [Double])
        case ripples(speed: Double, damping: Double)
        case fluid(FluidConfig)
        case multiScaleTuring(scales: [TuringScale], seed: Double)
        case sandpile(pour: Int, topplings: Int)
        case fallingSand(passes: Int, friction: Double)
        case watercolor(WatercolorConfig)
        case cyclic(states: Int, threshold: Int, range: Int,
                    neighborhood: CellNeighborhood, seed: Double)
        case excitable(states: Int, threshold: Int, range: Int,
                       neighborhood: CellNeighborhood)
        case briansBrain
        case forestFire(growth: Double, lightning: Double,
                        neighborhood: CellNeighborhood, seed: Double)
        case hodgepodge(states: Int, k1: Int, k2: Int, g: Int,
                        neighborhood: CellNeighborhood, seed: Double)
        case selfWarp(SelfWarpConfig)
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

    /// The fixed configuration a `.selfWarp` hands the renderer's motion-feedback
    /// pipeline. Like the fluid it bypasses the single-texture step hooks and runs a
    /// dedicated pass chain (`runSelfWarp`) over its own source / flow / history
    /// state, so its parameters travel here rather than in `params`.
    struct SelfWarpConfig: Sendable {
        var strength: Float     // how far history rides the measured motion (1 = with it)
        var refresh: Float      // how much of this frame's drawing re-enters (0...1)
        var decay: Float        // per-frame multiplier on the carried history (1 = keep)
        var smoothing: Float    // temporal steadying of the motion field (0...0.98)
    }

    /// Gray-Scott **reaction-diffusion**: two chemicals diffuse and react, and where
    /// they balance, Turing patterns emerge — coral, spots, stripes, mitosis. Draw
    /// light marks into the field to inject chemical B (it spreads from there). `feed`
    /// and `kill` pick the regime; the defaults give persistent dividing cells
    /// (mitosis). State is chemical A in red, B in green, so the raw `image` reads
    /// reddish — recolor it with `.filtered(.gradientMap(...))` or `.threshold(...)`.
    public static func reactionDiffusion(feed: Double = 0.055, kill: Double = 0.062) -> Sim {
        Sim(kind: .reactionDiffusion(feed: max(0, feed), kill: max(0, kill),
                                     toFeed: max(0, feed), toKill: max(0, kill)))
    }

    /// Gray-Scott reaction-diffusion whose regime **varies across the field**. Attach
    /// a layer to the field's `modulation` and its brightness re-tunes the chemistry
    /// per texel: where the map is black the field runs at `feed`/`kill`, where it is
    /// white at `toFeed`/`toKill`, sliding smoothly between. One continuous field then
    /// wears different patterns in different places (stripes inside a camera matte,
    /// spots outside it), and because it is a single simulation the pattern crosses
    /// the boundary instead of seaming at it. Draw the map layer each frame before
    /// reading the field; a frame with no map falls back to the plain `feed`/`kill`
    /// step. Seeding, state channels, and recoloring work exactly as in
    /// `reactionDiffusion(feed:kill:)`.
    public static func reactionDiffusion(feed: Double = 0.055, kill: Double = 0.062,
                                         toFeed: Double, toKill: Double) -> Sim {
        Sim(kind: .reactionDiffusion(feed: max(0, feed), kill: max(0, kill),
                                     toFeed: max(0, toFeed), toKill: max(0, toKill)))
    }

    /// Conway's **Game of Life**: each cell lives or dies by its eight neighbors
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

    /// A real-time **fluid**: an incompressible flow that carries color. Draw into the
    /// field to inject dye (the mark's color) and push the fluid with `withField`'s
    /// `force:` (so dragging or an animated force swirls the color). The flow advects,
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

    /// **Self-warp**: the field watches how its own picture moves and drags its history
    /// along with that motion, so everything you draw trails a smeared echo of itself.
    /// Draw the scene into the field each frame (a `background` inside the block keeps
    /// the seed opaque, the usual whole-picture use); the sim measures a dense motion
    /// field between this frame's drawing and the last one, carries the accumulated
    /// history along it, and mixes `refresh` of the fresh drawing back in. Moving
    /// shapes comb into comets, a panning texture liquefies, and a camera or video
    /// frame drawn into the field smears along whatever moves in it. The raw `image`
    /// is the smeared picture, ready to composite or filter like any layer.
    ///
    /// The motion is estimated from the pictures themselves (a coarse-to-fine
    /// least-squares fit over the luminance, the classic Lucas-Kanade scheme), so it
    /// needs no cooperation from the sketch: anything that visibly moves, moves the
    /// history. It reads best on content with some texture or edges; a flat field has
    /// no motion to measure.
    ///
    /// ```swift
    /// var warp: SimField!
    /// override func setup() { warp = makeSimField(.selfWarp()) }
    ///
    /// override func draw() {
    ///     withField(warp) {
    ///         background(.black)
    ///         fill(.orange); drawCircle(bounds.center.x + cos(time) * 300,
    ///                                   bounds.center.y + sin(time) * 300, 60)
    ///     }
    ///     drawImage(warp.image, 0, 0)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - strength: How far the history rides the measured motion each frame, as a
    ///     multiple of it, and the dial that picks the look. Below 1 the picture
    ///     outruns its history and stretches it into ribbons trailing the motion
    ///     (the default regime); at 1 the carried ghost lands exactly back under the
    ///     mover, which reads as almost nothing; above 1 it overshoots and throws
    ///     glitchy echoes ahead of the motion; negative drags the history against it.
    ///   - refresh: How much of this frame's drawing re-enters per frame (0...1). Low
    ///     values leave long-lived smears; 1 shows only the fresh drawing warped by
    ///     one frame of motion; 0 freezes the first frame and lets later motion push
    ///     it around like wet paint.
    ///   - decay: Per-frame multiplier on the carried history (0...1). 1 never fades,
    ///     so still regions hold; a touch below 1 sinks old trails toward black.
    ///   - smoothing: Temporal steadying of the motion field (0...0.98). Higher reads
    ///     calmer and keeps trails coherent; lower answers faster and twitches more.
    public static func selfWarp(amount: Double = 0.6, refresh: Double = 0.08,
                                decay: Double = 1, smoothing: Double = 0.6) -> Sim {
        Sim(kind: .selfWarp(SelfWarpConfig(
            strength: Float(min(8, max(-8, amount))),
            refresh: Float(min(1, max(0, refresh))),
            decay: Float(min(1, max(0, decay))),
            smoothing: Float(min(0.98, max(0, smoothing))))))
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
    /// override func setup() { turing = makeSimField(.multiScaleTuring(), scale: 0.5) }
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
    /// neighbors. A toppling can tip its neighbors over too, so one grain dropped
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

    /// **Falling sand**: the block automaton behind the falling-sand toys, where
    /// every cell is empty, water, sand, or wall, and gravity is a local rule.
    /// Each pass tiles the field into 2x2 blocks and settles every block on its
    /// own: a grain of sand above an empty cell drops into it, a grain above water
    /// sinks through it and lifts the water into its place, a grain that cannot
    /// drop straight down rolls into the empty diagonal below (so sand piles up
    /// into heaps), and water spreads into an empty cell beside it (so water
    /// levels out and fills a basin). Walls never move, and the field's edge is a
    /// closed box. The tiling's origin walks the four corners of a block over four
    /// passes, which is what lets a grain cross from block to block and reach
    /// both diagonals, and is why `passes` is kept a multiple of four: a frame
    /// always runs every tiling the same number of times.
    ///
    /// `friction` is the chance, 0 to 1, that a grain stays put instead of rolling
    /// diagonally. At 0 every heap slumps to the flattest slope the rule allows;
    /// raising it lets heaps stand steeper, and near 1 sand stacks into towers.
    ///
    /// The field starts empty, so **draw to fill it**. A mark's brightness picks
    /// the material it lays down: black erases, dark gray (a third) is water,
    /// light gray (two thirds) is sand, and white is wall; `SandMaterial` names
    /// those levels so a sketch writes `fill(SandMaterial.sand.color)`. A mark
    /// held down is a tap that keeps pouring. The raw `image` reads back the same
    /// four levels, made for `.filtered(.gradientMap(...))` with one color per
    /// material. One texel is one cell, a grain falls one cell every two passes,
    /// and water spreads one cell per pass, so `passes` is the pacing dial: the
    /// default moves a grain eight cells a frame.
    public static func fallingSand(passes: Int = 16, friction: Double = 0) -> Sim {
        // A multiple of four, so a frame runs each of the four block tilings the
        // same number of times: a frame that ended on a partial cycle would fall
        // and roll unevenly, and a tiling run twice in a row slides water back
        // and forth in place.
        let rounded = max(4, min(64, (passes + 3) / 4 * 4))
        return Sim(kind: .fallingSand(passes: rounded, friction: max(0, min(1, friction))))
    }

    /// Griffeath's **cyclic cellular automaton**: every cell holds one of `states`
    /// colors arranged in a circle, and a cell advances to the next color the moment
    /// at least `threshold` of its neighbors already wear it, so each color eats
    /// the one before it and is eaten by the one after. From its random start the
    /// field self-organizes through the famous four acts: colored static, then
    /// growing single-color droplets, then the first spiral defects, and finally a
    /// field of turning spiral cores that own everything. The defaults are the
    /// classic rule (14 states, threshold 1, the four edge-sharing neighbors);
    /// raising `threshold` with a wider `range` trades spirals for churning block
    /// turbulence, and a high enough threshold freezes the field into still color
    /// fields.
    ///
    /// The field needs no seeding: it starts from seeded random states (a uniform
    /// field is a fixed point, so noise is the required start, and the same `seed`
    /// replays the same picture). Drawing into it *stamps* states instead: a mark's
    /// brightness picks the state it writes (white the top state, black state
    /// zero), and the rule swallows the disturbance back into the spiral flow.
    ///
    /// The raw `image` is the state as grayscale, one flat level per state, made for
    /// `.filtered(.gradientMap(...))`; a cyclic palette keeps the color wheel's
    /// seam invisible. One texel is one cell, so the field's `scale` sets the cell
    /// size, and edges wrap.
    ///
    /// - Parameters:
    ///   - states: How many colors chase each other (2...64). More states make
    ///     slower, broader spirals; fewer make a faster boil.
    ///   - threshold: How many neighbors of the next color it takes to advance
    ///     (1...16). 1 is the classic spiral regime; higher thresholds want a wider
    ///     `range` to fire at all.
    ///   - range: How far a cell looks, in cells (1...4). The neighborhood is the
    ///     full block within that distance, or the diamond under `.vonNeumann`.
    ///   - neighborhood: Which cells count as neighbors. `.vonNeumann` is the edge
    ///     sharers (the classic); `.moore` adds the corners.
    ///   - seed: Picks the random start, so the same seed replays the same run.
    public static func cyclic(states: Int = 14, threshold: Int = 1, range: Int = 1,
                              neighborhood: CellNeighborhood = .vonNeumann,
                              seed: Double = 1) -> Sim {
        Sim(kind: .cyclic(states: max(2, min(64, states)),
                          threshold: max(1, min(16, threshold)),
                          range: max(1, min(4, range)),
                          neighborhood: neighborhood, seed: seed))
    }

    /// The Greenberg-Hastings model, the classic cellular automaton of **excitable
    /// media** (heart tissue, neurons, a chemical oscillator). A resting cell fires
    /// when at least `threshold` of its neighbors are firing, then climbs alone
    /// through its refractory tail back to rest, and a cell mid-recovery cannot be
    /// re-excited, which is exactly what turns a spark into a traveling wave with a
    /// dead zone behind it. Sparks grow into rings, rings annihilate where they
    /// collide (each runs into the other's refractory wake), and a broken wavefront
    /// curls into a pair of counter-rotating spirals that re-excite the medium
    /// forever.
    ///
    /// The field starts at rest, so **draw to spark it**: a bright mark excites the
    /// cells it covers (a black mark calms them back to rest). Dab single sparks for
    /// expanding rings; drag a line and erase half a ring with black to set a spiral
    /// pair turning.
    ///
    /// The raw `image` is grayscale: rest is black, a firing cell is faint gray
    /// (state 1 of `states`), and the refractory tail climbs toward white. Run it
    /// through `.filtered(.gradientMap(...))` with a dark-to-hot ramp to make the
    /// wavefronts glow. One texel is one cell (`scale` sets the size), and edges
    /// wrap.
    ///
    /// - Parameters:
    ///   - states: The full cycle length: rest, firing, then `states - 2` refractory
    ///     steps (3...64). Longer tails make wider dead zones and broader spirals.
    ///   - threshold: How many firing neighbors it takes to fire (1...16).
    ///   - range: How far a cell looks, in cells (1...4).
    ///   - neighborhood: `.vonNeumann` (the classic four) or `.moore` (eight).
    public static func excitable(states: Int = 3, threshold: Int = 1, range: Int = 1,
                                 neighborhood: CellNeighborhood = .vonNeumann) -> Sim {
        Sim(kind: .excitable(states: max(3, min(64, states)),
                             threshold: max(1, min(16, threshold)),
                             range: max(1, min(4, range)),
                             neighborhood: neighborhood))
    }

    /// Silverman's **Brian's Brain**: the three-state automaton where every cell is
    /// ready, firing, or resting. A ready cell fires when exactly two of its eight
    /// neighbors are firing; every firing cell spends the next step resting (and
    /// can't be re-lit); every resting cell returns to ready. Because nothing
    /// settles (almost every pattern explodes into gliders) the field boils forever
    /// with ships racing along diagonals and orthogonals, an automaton that reads
    /// as pure electricity.
    ///
    /// The field starts empty, so **draw to light it**: a white mark sets cells
    /// firing, a black mark clears them, and the afterglow comes from the rule. A
    /// single small blob is enough to fill the field with traffic.
    ///
    /// The raw `image` is already the classic picture (firing cells white, resting
    /// cells mid-gray, ready cells black), and a `.gradientMap` restyles it. One
    /// texel is one cell; edges wrap.
    public static func briansBrain() -> Sim { Sim(kind: .briansBrain) }

    /// The Drossel-Schwabl **forest fire**, the automaton that made self-organized
    /// criticality visible. Every cell is empty, a tree, or burning. A burning cell
    /// is empty next step. A tree catches from any burning neighbor, and otherwise
    /// catches on its own with probability `lightning`. An empty cell grows a tree
    /// with probability `growth`. Nothing in the rule aims at a density, and yet one
    /// arrives: trees fill in until a stand is connected enough for a strike to run
    /// through it, the fire clears exactly that crowd, and the field hovers there
    /// forever, throwing fires of every size from a single tree to most of the map.
    ///
    /// The field starts empty and grows itself in, so it **needs no seeding**, and
    /// the coin each cell throws is a hash of the cell and the field's own frame
    /// count, so a run replays exactly. Drawing stamps states: white sets cells
    /// burning (a fire you start where you want it), mid-gray plants trees, and
    /// black clears a firebreak the flames cannot cross.
    ///
    /// The raw `image` is grayscale, empty black, trees mid, fire white, made for
    /// `.filtered(.gradientMap(...))` with a ramp that runs dark ground to green to
    /// hot. One texel is one cell (`scale` sets the size), and edges wrap.
    ///
    /// - Parameters:
    ///   - growth: The chance an empty cell grows a tree in a step (0...1). This is
    ///     the pace of the whole system.
    ///   - lightning: The chance a tree catches on its own in a step (0...1). Keep it
    ///     far below `growth`: the ratio between them is what sets how big fires get,
    ///     and a rate near `growth` burns every tree as soon as it grows.
    ///   - neighborhood: `.vonNeumann` (the classic four) or `.moore` (eight, which
    ///     spreads fire through diagonal gaps and reads rounder).
    ///   - seed: Picks the run, so the same seed replays the same fires, and two
    ///     fields side by side burn differently.
    public static func forestFire(growth: Double = 0.015, lightning: Double = 0.000006,
                                  neighborhood: CellNeighborhood = .vonNeumann,
                                  seed: Double = 1) -> Sim {
        Sim(kind: .forestFire(growth: max(0, min(1, growth)),
                              lightning: max(0, min(1, lightning)),
                              neighborhood: neighborhood, seed: seed))
    }

    /// The Gerhardt-Schuster **hodgepodge machine**, the automaton built to mimic an
    /// oscillating chemical reaction (its waves are dead ringers for the
    /// Belousov-Zhabotinsky reaction in a dish). Cells run from healthy (0) through
    /// degrees of infection to ill (`states`): a healthy cell catches infection from
    /// its infected and ill neighbors (`⌊a/k1⌋ + ⌊b/k2⌋`), an infected cell's state
    /// climbs to its neighborhood's average infection plus the constant `g`, and an
    /// ill cell recovers to healthy at once. From a random start the field passes
    /// through churning noise into curling wavefronts and finally locked spiral
    /// cores shedding rings, the tempo set by `g`, the speed of infection.
    ///
    /// The field needs no seeding: it starts from seeded random states (all-healthy
    /// is a fixed point, so the random start is the protocol, and the same `seed`
    /// replays the same run). Drawing stamps states (brightness picks the degree of
    /// infection, black heals), and the waves close back over the wound.
    ///
    /// The raw `image` is the infection degree as grayscale, made for
    /// `.filtered(.gradientMap(...))`; the classic pictures map it across a hot
    /// thermal ramp. One texel is one cell (`scale` sets the size), and edges wrap.
    ///
    /// - Parameters:
    ///   - states: The ill state, the top of the ladder (4...200). The classic runs
    ///     use 100.
    ///   - infectedDivisor: Divides the infected-neighbor count in a healthy cell's
    ///     catch rule (1...9). Higher is harder to catch.
    ///   - illDivisor: Divides the ill-neighbor count in the same rule (1...9).
    ///   - infectionRate: How much sicker an infected cell gets per step (1...100),
    ///     the speed of infection and the behavior dial: low dies out, mid plateaus,
    ///     high locks into the spiral regime.
    ///   - neighborhood: `.moore` (the eight-neighbor classic for these spirals) or
    ///     `.vonNeumann` (the original experiment's four).
    ///   - seed: Picks the random start, so the same seed replays the same run.
    public static func hodgepodge(states: Int = 100, infectedDivisor: Int = 2,
                                  illDivisor: Int = 3,
                                  infectionRate: Int = 25,
                                  neighborhood: CellNeighborhood = .moore,
                                  seed: Double = 1) -> Sim {
        Sim(kind: .hodgepodge(states: max(4, min(200, states)),
                              k1: max(1, min(9, infectedDivisor)),
                              k2: max(1, min(9, illDivisor)),
                              g: max(1, min(100, infectionRate)),
                              neighborhood: neighborhood, seed: seed))
    }

    // MARK: Renderer hooks (internal)

    /// The seeded random start a state automaton needs, or `nil` for sims that rest
    /// at a constant: how many evenly spaced state levels to fill and the seed that
    /// picks them. Handed to the renderer's first-allocation fill, because a uniform
    /// field is a fixed point for these rules and noise is the required start.
    var stateSeedFill: (levels: Int, seed: Double)? {
        switch kind {
        case let .cyclic(states, _, _, _, seed): return (states, seed)
        case let .hodgepodge(states, _, _, _, _, seed): return (states + 1, seed)
        default: return nil
        }
    }

    /// Whether this sim runs the dedicated multi-field fluid pipeline (`runFluid`)
    /// rather than the single-texture step path. Its parameters live in `fluidConfig`.
    var isFluid: Bool { if case .fluid = kind { return true }; return false }

    /// The fluid configuration, when this is a `.fluid` (else `nil`).
    var fluidConfig: FluidConfig? { if case let .fluid(c) = kind { return c }; return nil }

    /// The self-warp configuration, when this is a `.selfWarp` (else `nil`). Like the
    /// fluid it runs its own multi-pass pipeline (`runSelfWarp`) over its own source,
    /// motion, and history state rather than the single-texture step path.
    var selfWarpConfig: SelfWarpConfig? {
        if case let .selfWarp(c) = kind { return c }; return nil
    }

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
    var substeps: Int {
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
        case let .fallingSand(passes, _):
            return passes                   // a multiple of four by construction: all
                                            // four block tilings run the same number of times
        case .watercolor:        return 1   // unused: watercolor runs its own pipeline
        case .cyclic:            return 1   // one generation per frame, like Life
        case .excitable:         return 1
        case .briansBrain:       return 1
        case .forestFire:        return 1
        case .hodgepodge:        return 1
        case .selfWarp:          return 1   // unused: self-warp runs its own pipeline
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
        case .fallingSand:       return SIMD4(0, 0, 0, 1)   // an empty box
        case .watercolor:        return SIMD4(0, 0, 0, 0)   // unused: runWatercolor clears its own fields
        case .cyclic:            return SIMD4(0, 0, 0, 1)   // unused: starts as seeded
                                                            // random states (stateSeedFill)
        case .excitable:         return SIMD4(0, 0, 0, 1)   // everything at rest
        case .briansBrain:       return SIMD4(0, 0, 0, 1)   // everything ready
        case .forestFire:        return SIMD4(0, 0, 0, 1)   // bare ground, which
                                                            // grows itself in
        case .hodgepodge:        return SIMD4(0, 0, 0, 1)   // unused: starts as seeded
                                                            // random states (stateSeedFill)
        case .selfWarp:          return SIMD4(0, 0, 0, 0)   // unused: runSelfWarp clears
                                                            // and primes its own state
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
        case .fallingSand:       return "ollin_sim_falling_sand"
        case .watercolor:        return ""   // unused: watercolor dispatches its own fragments
        case .cyclic:            return "ollin_sim_cyclic"
        case .excitable:         return "ollin_sim_excitable"
        case .briansBrain:       return "ollin_sim_brain"
        case .forestFire:        return "ollin_sim_forest_fire"
        case .hodgepodge:        return "ollin_sim_hodgepodge"
        case .selfWarp:          return ""   // unused: self-warp dispatches its own fragments
        }
    }

    /// The `ollin_sim_*` step variant that reads a modulation map as a second input
    /// texture, for sims whose parameters can vary across the field (`nil` when the
    /// sim has none). The renderer selects it only when the field's `modulation`
    /// layer was drawn this frame; the plain `stepFragment` path stays byte-identical
    /// for every unmodulated field.
    var modulatedStepFragment: String? {
        switch kind {
        case .reactionDiffusion: return "ollin_sim_reaction_diffusion_modulated"
        default: return nil
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
        case .fallingSand:      return "ollin_sim_inject_grains"
        case .watercolor:       return ""   // unused: watercolor runs its own two injects
        case .excitable:        return "ollin_sim_inject_excite"
        case .briansBrain:      return "ollin_sim_inject_brain"
        default:                return "ollin_sim_inject"
        }
    }

    /// The per-step parameter rows bound after the texel size (the renderer passes
    /// them to the step fragment as `params[1]` onward).
    var params: [SIMD4<Float>] {
        switch kind {
        case let .reactionDiffusion(feed, kill, toFeed, toKill):
            // x/y are all the plain step reads, so a uniform sim (toFeed == feed,
            // toKill == kill) binds the same bytes as the plain form; z/w feed the
            // modulated step's per-texel lerp.
            return [SIMD4(Float(feed), Float(kill), Float(toFeed), Float(toKill))]
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
        case let .fallingSand(_, friction):
            return [SIMD4(Float(friction), 0, 0, 0)]
        case .watercolor:
            return []   // unused: watercolor binds per-pass parameters itself
        case let .cyclic(states, threshold, range, neighborhood, _):
            return [SIMD4(Float(states), Float(threshold), Float(range),
                          neighborhood == .moore ? 1 : 0)]
        case let .excitable(states, threshold, range, neighborhood):
            // states also read by the inject: a mark excites to state 1 of `states`.
            return [SIMD4(Float(states), Float(threshold), Float(range),
                          neighborhood == .moore ? 1 : 0)]
        case .briansBrain:
            return []
        case let .forestFire(growth, lightning, neighborhood, seed):
            return [SIMD4(Float(growth), Float(lightning),
                          neighborhood == .moore ? 1 : 0, Float(seed))]
        case let .hodgepodge(states, k1, k2, g, neighborhood, _):
            return [SIMD4(Float(states), Float(k1), Float(k2), Float(g)),
                    SIMD4(neighborhood == .moore ? 1 : 0, 0, 0, 0)]
        case .selfWarp:
            return []   // unused: self-warp binds per-pass parameters itself
        }
    }
}

/// Which cells count as a cell's neighbors in the grid automata (`Sim.cyclic`,
/// `Sim.excitable`, `Sim.hodgepodge`, `Sim.forestFire`). With a `range` above 1 the same two shapes
/// scale up: `.moore` is the full block within that distance, `.vonNeumann` the
/// diamond.
public enum CellNeighborhood: Sendable, Equatable {
    /// The edge-sharing cells: four at range 1, a diamond further out.
    case vonNeumann
    /// The edge sharers plus the corners: eight at range 1, a full block further out.
    case moore
}

/// What a cell of a `Sim.fallingSand` field holds, and the gray level that lays
/// it down. The field stores one material per texel as a quarter-step gray, so a
/// mark's brightness picks the material: `fill(SandMaterial.sand.color)` before a
/// `drawCircle` drops a disc of sand, and the raw `image` reads back the same
/// levels (empty black, water a third gray, sand two thirds, wall white).
public enum SandMaterial: Int, Sendable, CaseIterable {
    /// Nothing; sand and water fall or flow into it. Drawn as black, it erases.
    case empty = 0
    /// A fluid: it falls, spreads sideways to level out, and lets sand sink through it.
    case water = 1
    /// A grain: it falls, sinks through water, and rolls off a slope into a heap.
    case sand = 2
    /// Fixed: it never moves and nothing passes through it.
    case wall = 3

    /// The gray a mark uses to lay this material down (the level the field stores).
    public var color: Color {
        Color(white: Double(rawValue) / Double(SandMaterial.allCases.count - 1))
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
    /// compared, in field texels. This is the parameter that decides how large a region a
    /// scale can claim, and it is load-bearing rather than a refinement: read at a single
    /// point, a fine scale's disagreement passes through zero along every contour of its
    /// own structure, and since the *least* disagreement wins, it would take a dense web
    /// of pixels everywhere and bury the coarse scales. Averaging over the scale's own
    /// neighborhood removes those accidental zeros. Defaults to `inhibitorRadius`;
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
