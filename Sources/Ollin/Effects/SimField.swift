import Metal

/// A persistent layer that runs a built-in `Sim` on the GPU each frame: the stateful
/// effects surface for reaction-diffusion, cellular automata, and other fields that
/// evolve by reading their own neighbourhood. Make one in `setup()` with `simField(_:)`,
/// draw into it to seed/force it (`withField`), and composite its `image`.
///
/// ```swift
/// var life: SimField!
/// override func setup() { life = simField(.gameOfLife(), scale: 0.15) }   // chunky cells
///
/// override func draw() {
///     background(.black)
///     withField(life) {                       // draw to seed: white = alive, black = dead
///         if mouseIsPressed { fill(.white); drawCircle(mouseX, mouseY, 30) }
///     }
///     drawImage(life.image, 0, 0)             // the evolved field
/// }
/// ```
///
/// Like `Feedback` (and unlike a per-frame `RenderTarget`), a `SimField` is
/// **persistent**: its identity is what carries the field's state from one frame to
/// the next, so create it once and hold it. The renderer keeps the ping-pong pair,
/// renders this frame's drawn seeds onto the current state, runs the sim's steps, and
/// the result becomes both `image` and next frame's state. A reference type, for the
/// same reason `Feedback`/`RenderTarget` are: it names GPU resources the renderer fills.
public final class SimField {

    /// The field's logical size in canvas points (the size `image` draws at and the
    /// coordinate space a `withField` block uses).
    public let width: Int
    public let height: Int

    /// Internal resolution as a fraction of the logical size (1 = full), like
    /// `RenderTarget.scale`. Lower it for a coarser field — bigger reaction-diffusion
    /// features, chunkier automaton cells, and cheaper stepping. Clamped to a sane range.
    public let scale: Double

    /// The simulation this field runs every frame.
    let sim: Sim

    /// The drawer that owns the recording, so a `withField` block records against it.
    weak var drawer: Drawer?

    /// This frame's seed/draw surface: a `RenderTarget` tagged `.simField(self)` so the
    /// renderer routes it to persistent ping-pong storage and runs the sim after the
    /// drawn marks land. Reused across frames (stable identity) so `image` is steady.
    let writeLayer: RenderTarget

    /// Pixel dimensions of the backing field (logical size × `scale`, ≥ 1).
    var pixelWidth: Int { max(1, Int((Double(width) * scale).rounded())) }
    var pixelHeight: Int { max(1, Int((Double(height) * scale).rounded())) }

    init(sim: Sim, width: Int, height: Int, scale: Double, drawer: Drawer?) {
        self.sim = sim
        self.width = max(1, width)
        self.height = max(1, height)
        self.scale = min(4, max(0.02, scale))
        self.drawer = drawer
        self.writeLayer = RenderTarget(width: self.width, height: self.height,
                                       scale: self.scale, drawer: drawer)
        // Stamp the write layer now that `self` exists, so the renderer can recover
        // this field (and its persistent textures + which sim to step) from the target.
        self.writeLayer.origin = .simField(self)
    }

    /// The evolved field this frame, as a drawable `Image` — the raw state, resolved
    /// lazily at draw time. Reaction-diffusion reads reddish (A in red, B in green);
    /// recolor it with `field.filtered(.gradientMap(...))`. Game of Life is already
    /// crisp black-and-white.
    public var image: Image { writeLayer.image }

    /// Recolor or post-process the evolved field through a `Filter`, returning a new
    /// layer to composite. The raw sim state is data, so `field.filtered(.gradientMap(...))`
    /// or `.threshold(...)` turns it into the look you want — the same effects substrate
    /// the rest of the catalog uses.
    public func filtered(_ filter: Filter) -> RenderTarget { writeLayer.filtered(filter) }
}
