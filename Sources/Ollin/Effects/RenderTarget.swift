import Metal

/// An off-screen layer a sketch draws into and then reads back: the substrate of
/// layered effects. Draw into it with `withTarget(_:)`, sample it as an `Image`
/// (`target.image`, composited with `drawImage`), or run a `Filter` over it
/// (`target.filtered(_:)`). It lives on the GPU: the texture is filled by the
/// renderer and sampled by later draws with no CPU round-trip.
///
/// ```swift
/// override func draw() {
///     let layer = renderTarget()                 // a full-canvas off-screen layer
///     withTarget(layer) {
///         background(.black)
///         fill(.orange); drawCircle(width / 2, height / 2, 200)
///     }
///     let glow = layer.filtered(.bloom(intensity: 1.4))
///     drawImage(layer.image, 0, 0)               // the sharp shape…
///     blendMode(.add)
///     drawImage(glow.image, 0, 0)                // …plus its glow, added as light
/// }
/// ```
///
/// Create a target inside `draw()`: it's a per-frame handle, recorded fresh each
/// frame, and the renderer reuses its GPU texture across frames behind the scenes.
/// A reference type: it names a GPU resource, and `filtered(_:)` records work
/// against the drawer that made it.
public final class RenderTarget {

    /// The layer's logical size in canvas points: the size `image` draws at and
    /// the coordinate space `withTarget` geometry uses.
    public let width: Int
    public let height: Int

    /// Internal resolution as a fraction of the logical size (1 = full). Drop it
    /// below 1 to render a layer at fewer pixels: effects are fill-rate bound, so
    /// a blurred or glow layer rarely needs full resolution, and the result
    /// upsamples when drawn back. Clamped to a sane range.
    public let scale: Double

    /// How this target gets filled. A `.geometry` target is drawn into by a
    /// `withTarget` block; a `.generator` target is filled by a procedural pattern
    /// pass; a `.filter` target is the output of `filtered(_:)`, run from `input`;
    /// a `.combine` target is the output of `combined(with:_:)`, run from `base`
    /// modulated by `aux`; a `.feedback` target is a `Feedback` layer's per-frame
    /// write surface, filled like a `.geometry` target but into persistent
    /// ping-pong storage the renderer keeps across frames. Internal: the renderer
    /// reads it at render time.
    enum Origin {
        case geometry
        case generator(Generator)
        case filter(input: RenderTarget, filter: Filter)
        case combine(base: RenderTarget, aux: RenderTarget, op: Combine)
        case feedback(Feedback)
    }
    /// Settable so a `Feedback` can stamp its write layer with `.feedback(self)`
    /// once `self` exists (the layer is built before the back-reference is known).
    var origin: Origin

    /// The drawer that created this target, so `filtered(_:)` can record the effect
    /// op. Weak: the drawer outlives per-frame targets and owns the recording.
    weak var drawer: Drawer?

    /// The clear color for a `.geometry` target, set by `background(_:)` inside the
    /// `withTarget` block. Transparent by default, so an unwritten layer composites
    /// as nothing.
    var clearColor: Color = .clear

    /// The GPU texture the renderer fills for this target this frame, then later
    /// draws sample. Set during the render pass; `nil` before the frame renders.
    var texture: MTLTexture?

    /// Pixel dimensions of the backing texture (logical size × `scale`, ≥ 1).
    var pixelWidth: Int { max(1, Int((Double(width) * scale).rounded())) }
    var pixelHeight: Int { max(1, Int((Double(height) * scale).rounded())) }

    init(width: Int, height: Int, scale: Double, drawer: Drawer?, origin: Origin = .geometry) {
        self.width = max(1, width)
        self.height = max(1, height)
        self.scale = min(4, max(0.05, scale))
        self.drawer = drawer
        self.origin = origin
    }

    /// This layer as a drawable `Image`, for `drawImage`. The image resolves the
    /// target's GPU texture lazily at draw time, so it always reflects what was
    /// drawn into the layer this frame.
    public var image: Image { Image(renderTarget: self) }

    /// Run `filter` over this layer and return the result as a new layer, itself
    /// filterable, so effects chain (`layer.filtered(.bloom()).filtered(...)`).
    /// The work runs on the GPU during the frame's render; this just records it.
    public func filtered(_ filter: Filter) -> RenderTarget {
        drawer?.recordFilter(filter, of: self) ?? self
    }

    /// Combine this layer (the base) with `aux` using a two-input `op` — mask,
    /// displace, or mix — and return the result as a new layer, itself filterable
    /// and combinable, so multi-input effects chain like single-input ones
    /// (`scene.combined(with: mask, .mask()).filtered(.bloom())`). The result takes
    /// this layer's size and resolution; `aux` is sampled by normalized coordinates,
    /// so it may render at a different scale. Runs on the GPU at render time.
    public func combined(with aux: RenderTarget, _ op: Combine) -> RenderTarget {
        drawer?.recordCombine(self, aux, op) ?? self
    }
}
