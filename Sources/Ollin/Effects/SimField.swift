import Metal

/// How a simulation field treats its edge: what a cell on the border reads when its
/// rule looks past the field. The default wraps both ways, so the field is a torus
/// and a glider that leaves on the right comes back on the left. A clamped edge is a
/// wall: a read past it returns the border cell itself, which for a diffusing
/// quantity is an insulated boundary (nothing flows out) and for an automaton a
/// frame of cells that mirror their neighbors. The two axes are set apart, so a
/// scroll that wraps left to right but stops at the top and bottom is
/// `FieldEdge(wrapsX: true, wrapsY: false)`.
///
/// The rule applies to the sims that read their neighbors through the field's own
/// sampler: reaction-diffusion, predator-prey, Life, Lenia, SmoothLife, the state
/// automata, the Ising model, and a `Sim.shader` of your own. The sims whose physics
/// fix their boundary keep it whatever the field says: ripples absorb at a clamped
/// rim, the sandpile is open (grains fall off), the falling sand is a closed box,
/// Schelling's board is bounded, and the fluid, Turing, watercolor, and self-warp
/// pipelines carry their own.
public struct FieldEdge: Sendable, Equatable {
    /// Whether a read past the left or right edge comes back in on the other side.
    public var wrapsX: Bool
    /// Whether a read past the top or bottom edge comes back in on the other side.
    public var wrapsY: Bool

    public init(wrapsX: Bool, wrapsY: Bool) {
        self.wrapsX = wrapsX
        self.wrapsY = wrapsY
    }

    /// A torus, the default: both axes wrap, and the field has no border at all.
    public static let wrapping = FieldEdge(wrapsX: true, wrapsY: true)
    /// Walls on every side: a read past the edge returns the border cell.
    public static let clamped = FieldEdge(wrapsX: false, wrapsY: false)
}

/// The values of a `SimField`, read back to the CPU: `width` by `height` cells of
/// four channels, row-major from the top-left, exactly as the field stores them. A
/// state is data, so nothing is color-converted on the way out; a Game of Life cell
/// reads 1 or 0 in `.x`, a reaction-diffusion cell its two chemicals in `.x` and `.y`.
public struct FieldSnapshot: Sendable {
    /// Cells across, the field's pixel width (its logical width times its `scale`).
    public let width: Int
    /// Cells down.
    public let height: Int
    /// Every cell, row by row from the top-left: `values[y * width + x]`.
    public let values: [SIMD4<Float>]

    public init(width: Int, height: Int, values: [SIMD4<Float>]) {
        self.width = width
        self.height = height
        self.values = values
    }

    /// The cell at column `x`, row `y`. Indices past the edge read the nearest cell.
    public subscript(x: Int, y: Int) -> SIMD4<Float> {
        let cx = min(max(0, x), width - 1), cy = min(max(0, y), height - 1)
        return values[cy * width + cx]
    }
}

/// A persistent layer that runs a `Sim` on the GPU each frame: the stateful effects
/// surface for reaction-diffusion, cellular automata, and other fields that evolve by
/// reading their own neighborhood, including a kernel of your own (`Sim.shader`).
/// Make one in `setup()` with `makeSimField(_:)`, draw into it to seed/force it
/// (`withField`), and composite its `image`.
///
/// ```swift
/// var life: SimField!
/// override func setup() { life = makeSimField(.gameOfLife(), scale: 0.15) }   // chunky cells
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
public class SimField {

    /// The field's logical size in canvas points (the size `image` draws at and the
    /// coordinate space a `withField` block uses).
    public let width: Int
    public let height: Int

    /// Internal resolution as a fraction of the logical size (1 = full), like
    /// `RenderTarget.scale`. Lower it for a coarser field: bigger reaction-diffusion
    /// features, chunkier automaton cells, and cheaper stepping. Clamped to a sane range.
    public let scale: Double

    /// Bits per channel in the field's state (`makeSimField(precision:)`). Half float
    /// by default, which holds a whole number exactly only to 2048; `.float32` for a
    /// state that counts, sums, or carries an id, where every integer to sixteen
    /// million stays exact and a small increment survives being added to a large value.
    public let precision: LayerPrecision

    /// What a cell on the border reads when its rule looks past the field: a torus by
    /// default, walls with `.clamped`, or one axis of each. Settable live; the renderer
    /// reads it every frame. See `FieldEdge` for which sims honor it.
    public var edge: FieldEdge

    /// The simulation this field runs every frame. Settable live: the renderer reads
    /// it each frame, so retuning a sim's parameters (a growth parameter under a `@Param`)
    /// takes effect immediately while the field's evolved state carries on.
    public var sim: Sim

    /// An optional **modulation layer**: a layer whose brightness re-tunes the sim
    /// per texel, for sims that support one (today `.reactionDiffusion`, where it
    /// slides `feed`/`kill` from the factory's first pair where the map is black to
    /// its `to` pair where the map is white; see
    /// `Sim.reactionDiffusion(feed:kill:toFeed:toKill:)`). Set it once and **draw
    /// into the layer each frame** before reading the field: layers are per-frame,
    /// and the sim samples the map at every substep. A frame where the layer was
    /// not drawn (or a sim with no modulated variant) runs the plain step instead,
    /// so an idle map degrades to the uniform field, never to garbage. Attach a
    /// drawn or generated layer, not a `filtered(_:)` output (filters resolve after
    /// the sims each frame, so a filtered map would always be a frame stale).
    public var modulation: RenderTarget?

    /// Extra layers a `Sim.shader` kernel reads beside the state, as `input(info, i)`
    /// for the layer at index `i` (up to four). Like `modulation`, each is a per-frame
    /// layer: draw or generate it every frame before reading the field, and it arrives
    /// exactly as stored (no color conversion), through the field's own edge rule. A
    /// layer not drawn this frame reads as zero rather than stale, and a `filtered(_:)`
    /// output cannot be an input (filters resolve after the sims). The built-in sims
    /// ignore this list.
    public var inputs: [RenderTarget] = []

    /// How many `inputs` a kernel can read.
    public static let maxInputs = 4

    /// The drawer that owns the recording, so a `withField` block records against it.
    weak var drawer: Drawer?

    /// The velocity impulse a `withField(_:force:_:)` block requests this frame: the
    /// renderer's fluid splat adds it to the velocity where the block's marks landed,
    /// so dragging or animating a brush pushes the flow. Set each frame the field is
    /// drawn into (default zero); read by the renderer; ignored by the single-field
    /// sims. Not state: it doesn't persist across frames.
    var seedForce: Vector2 = .zero

    /// This frame's seed/draw surface: a `RenderTarget` tagged `.simField(self)` so the
    /// renderer routes it to persistent ping-pong storage and runs the sim after the
    /// drawn marks land. Reused across frames (stable identity) so `image` is steady.
    let writeLayer: RenderTarget

    /// How the renderer that holds this field's state reads it back for `snapshot()`.
    /// Set by the renderer each frame it steps the field; `nil` until the field has
    /// run once, and again once that renderer is gone.
    var reader: ((SimField) -> FieldSnapshot?)?

    /// Pixel dimensions of the backing field (logical size × `scale`, ≥ 1).
    var pixelWidth: Int { max(1, Int((Double(width) * scale).rounded())) }
    var pixelHeight: Int { max(1, Int((Double(height) * scale).rounded())) }

    init(sim: Sim, width: Int, height: Int, scale: Double, drawer: Drawer?,
         edge: FieldEdge = .wrapping, precision: LayerPrecision = .float16) {
        self.sim = sim
        self.width = max(1, width)
        self.height = max(1, height)
        self.scale = min(4, max(0.02, scale))
        self.edge = edge
        self.precision = precision
        self.drawer = drawer
        self.writeLayer = RenderTarget(width: self.width, height: self.height,
                                       scale: self.scale, drawer: drawer, precision: precision)
        // Stamp the write layer now that `self` exists, so the renderer can recover
        // this field (and its persistent textures + which sim to step) from the target.
        self.writeLayer.origin = .simField(.init(self))
    }

    /// The evolved field this frame, as a drawable `Image`: the raw state, resolved
    /// lazily at draw time. Reaction-diffusion reads reddish (A in red, B in green);
    /// recolor it with `field.filtered(.gradientMap(...))`. Game of Life is already
    /// crisp black-and-white.
    ///
    /// Reading the field also keeps it running: a sim steps while its layer is one of the
    /// frame's render targets, which `withField` does when you draw seeds into it, and
    /// this does when you only read. A field that self-organizes (multi-scale Turing) then
    /// needs nothing but a `drawImage` to run.
    public var image: Image {
        drawer?.ensureFieldSteps(self)
        return writeLayer.image
    }

    /// Recolor or post-process the evolved field through a `Filter`, returning a new
    /// layer to composite. The raw sim state is data, so `field.filtered(.gradientMap(...))`
    /// or `.threshold(...)` turns it into the look you want, through the same effects
    /// substrate the rest of the catalog uses. Like `image`, reading through a filter
    /// keeps the field stepping. A two-channel state (a wind, a gradient) reads as
    /// arrows through `.arrows(spacing:scale:color:width:)`.
    public func filtered(_ filter: Filter) -> RenderTarget {
        drawer?.ensureFieldSteps(self)
        return writeLayer.filtered(filter)
    }

    /// The field's current state, read back to the CPU as a `FieldSnapshot`: every
    /// cell's four channels exactly as stored, `pixelWidth` by `pixelHeight`. Called
    /// from `draw()`, it holds the state the last frame left (this frame's step has
    /// not run yet), so a sketch that steers by what the field did sees it one frame
    /// late, which is the cost of a GPU that runs ahead of the CPU. The read itself
    /// waits for the GPU to finish the frames it holds, so it is for a measurement a
    /// frame (a sum, a count, the busiest cell, a value handed to sound or to a
    /// plotter), never for drawing the field, which `image` does with no round trip.
    /// `nil` before the field has run its first frame.
    @MainActor
    public func snapshot() -> FieldSnapshot? {
        reader?(self)
    }
}
