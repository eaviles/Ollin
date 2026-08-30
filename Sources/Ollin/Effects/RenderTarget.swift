import Foundation
import Metal
import simd

/// An off-screen layer a sketch draws into and then reads back: the substrate of
/// layered effects. Draw into it with `withTarget(_:)`, sample it as an `Image`
/// (`target.image`, composited with `drawImage`), or run a `Filter` over it
/// (`target.filtered(_:)`). It lives on the GPU: the texture is filled by the
/// renderer and sampled by later draws with no CPU round-trip.
///
/// ```swift
/// override func draw() {
///     let layer = makeRenderTarget()                 // a full-canvas off-screen layer
///     withTarget(layer) {
///         background(.black)
///         fill(.orange); drawCircle(width / 2, height / 2, 200)
///     }
///     let glow = layer.filtered(.bloom(amount: 1.4))
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
    /// ping-pong storage the renderer keeps across frames; an `.ocean` target is
    /// one frame of a wave field, filled by the spectrum pass, the inverse
    /// Fourier ladder, and the resolve. Internal: the renderer
    /// reads it at render time.
    enum Origin {
        case geometry
        case generator(Generator)
        case filter(input: RenderTarget, filter: Filter)
        case combine(base: RenderTarget, aux: RenderTarget, op: Combine)
        case feedback(Feedback)
        case simField(SimField)
        case ocean(OceanRequest)
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

    /// Set during recording when 3D geometry (a mesh or point cloud) is drawn into
    /// this target. 3D needs a depth attachment to z-test correctly, so this both
    /// makes the target's pass carry depth *and* makes `depth` available. A pure-2D
    /// target leaves it false and allocates no depth, so the 2D path is untouched.
    var needsDepth = false

    /// Set during recording when a clip region (`withClip`) is pushed inside this
    /// target, so its pass carries a stencil attachment. An unclipped target
    /// allocates no stencil and its pass is byte-identical to before.
    var needsStencil = false

    /// The depth layer (`depth`), created lazily the first time it's read. Held here
    /// so the renderer can fill its texture from this target's resolved depth buffer.
    /// `nil` until accessed, so a 3D target you draw but never defocus pays only for
    /// its own occlusion, not the extra depth-resolve + normalize work.
    var depthLayer: RenderTarget?

    /// Set during recording when this 3D target feeds an ambient-occlusion combine
    /// (`combined(with:.ambientOcclusion(...))`). It asks the renderer to also capture
    /// true mesh normals into a `normals` layer, so the occlusion reads a stable
    /// surface normal instead of one reconstructed from depth (which is ambiguous at a
    /// concave seam and flickers slightly as the camera turns). Stays false on a 2D
    /// target or a 3D target that doesn't run AO, so the normal pass (and any cost)
    /// is skipped and the frame is byte-identical to before.
    var needsNormals = false

    /// The view-space normal layer (`normals`), created lazily the first time it's
    /// read. Filled by the renderer's dedicated mesh-normal pass when `needsNormals`,
    /// so a combine that needs a true surface normal (ambient occlusion) can sample it.
    /// `nil` until accessed, like `depthLayer`.
    var normalLayer: RenderTarget?

    /// Camera parameters captured when this layer is filled as a normalized depth layer,
    /// so a combine that reconstructs view-space geometry from the depth (ambient
    /// occlusion) can rebuild it. Stamped by the renderer alongside the depth normalize;
    /// `nil` on any other layer.
    var depthReconstruction: DepthReconstruction?

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

    /// This target's per-pixel depth as a sampleable gray layer (0 near … 1 far),
    /// linearized over the camera's near/far range. Feed it to `.defocus` as the aux
    /// to defocus a real 3D scene by its own depth
    /// (`scene.combined(with: scene.depth, .defocus(...))`), or draw/filter it like
    /// any layer to visualize the scene's depth.
    ///
    /// Available only after 3D geometry was drawn into this target (the depth buffer
    /// the layer reads from doesn't exist otherwise). On a 2D-only target it stays
    /// empty, so the combine that reads it is a no-op.
    ///
    /// ```swift
    /// let scene = makeRenderTarget()
    /// withTarget(scene) {
    ///     camera(.perspective(eye: Vector3(0, 0, 6), target: .zero))
    ///     drawSphere(radius: 1)                       // 3D → depth captured
    /// }
    /// let dof = scene.combined(with: scene.depth, .defocus(focus: 0.4, maxBlur: 30))
    /// drawImage(dof.image, 0, 0)
    /// ```
    public var depth: RenderTarget {
        if let depthLayer { return depthLayer }
        let layer = RenderTarget(width: width, height: height, scale: scale, drawer: drawer)
        depthLayer = layer
        return layer
    }

    /// This target's per-pixel view-space surface normal as a sampleable layer, filled
    /// by the renderer's mesh-normal pass when the target captured 3D geometry. Internal
    /// plumbing: the ambient-occlusion combine reads it to occlude against a true normal
    /// rather than one reconstructed from depth. Like `depth`, it exists only after 3D
    /// was drawn into this target; on a 2D-only target it stays empty.
    var normals: RenderTarget {
        if let normalLayer { return normalLayer }
        let layer = RenderTarget(width: width, height: height, scale: scale, drawer: drawer)
        normalLayer = layer
        return layer
    }

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

/// The camera geometry needed to rebuild a view-space position from a normalized depth
/// layer (0 near … 1 far). A unified form for all three projections: `tanHalfFov*` are
/// the view-frustum half-extents at unit distance (perspective and the intrinsic pinhole
/// frustum) or the framed half-size (orthographic, where `isPerspective` is false and the
/// XY isn't scaled by distance); `principal*` shift the projection center for an off-axis
/// intrinsic frustum (0.5 for a centered one). View-space distance is `near + t·(far−near)`.
struct DepthReconstruction {
    var near: Float
    var far: Float
    var tanHalfFovX: Float
    var tanHalfFovY: Float
    var principalX: Float
    var principalY: Float
    var isPerspective: Bool
    /// The scene camera's view→clip and inverse view→world transforms, stamped so a
    /// combine that reprojects across frames (screen-space reflections' temporal
    /// resolve) can map a reconstructed view-space point to world and into the previous
    /// frame. Identity when the aux carries no camera; only the temporal pass reads
    /// them, so every other depth combine is unaffected.
    var viewProjection: simd_float4x4 = matrix_identity_float4x4
    var inverseView: simd_float4x4 = matrix_identity_float4x4
    /// How many blades the scene camera's iris has, stamped so the depth-of-field
    /// combine shapes its highlights like the opening the rest of the camera already
    /// uses. `0` (a round opening) whenever the aux carries no camera, which is what
    /// leaves a hand-drawn depth ramp round unless the call names a blade count itself.
    var apertureBlades: Int = 0

    /// A neutral default used when a depth combine reads an aux that carries no camera
    /// (a hand-drawn depth map): a centered 60° perspective over a 0.1 … 100 range, so the
    /// op still produces a plausible result rather than nothing.
    static let neutral = DepthReconstruction(
        near: 0.1, far: 100, tanHalfFovX: 0.5774, tanHalfFovY: 0.5774,
        principalX: 0.5, principalY: 0.5, isPerspective: true)

    init(near: Float, far: Float, tanHalfFovX: Float, tanHalfFovY: Float,
         principalX: Float, principalY: Float, isPerspective: Bool) {
        self.near = near; self.far = far
        self.tanHalfFovX = tanHalfFovX; self.tanHalfFovY = tanHalfFovY
        self.principalX = principalX; self.principalY = principalY
        self.isPerspective = isPerspective
    }

    /// Build the reconstruction for `camera` at a layer of `pixelWidth` × `pixelHeight`.
    /// Perspective/orthographic fold the layer aspect into the X half-extent; the
    /// intrinsic frustum takes its aspect (and off-axis center) from the calibration.
    init(camera: Camera3D, pixelWidth: Int, pixelHeight: Int) {
        let aspect = Float(pixelWidth) / Float(max(1, pixelHeight))
        near = Float(camera.near)
        far = Float(camera.far)
        principalX = 0.5
        principalY = 0.5
        switch camera.projection {
        case .perspective(let fov):
            let th = tan(Float(fov) * 0.5)
            tanHalfFovX = th * aspect
            tanHalfFovY = th
            isPerspective = true
        case .orthographic(let height):
            let h = Float(height) * 0.5
            tanHalfFovX = h * aspect
            tanHalfFovY = h
            isPerspective = false
        case .intrinsic(let k):
            let iw = Float(k.width), ih = Float(k.height)
            tanHalfFovX = iw / (2 * Float(k.fx))
            tanHalfFovY = ih / (2 * Float(k.fy))
            principalX = Float(k.cx) / iw
            principalY = Float(k.cy) / ih
            isPerspective = true
        }
        let view = camera.viewMatrix
        viewProjection = camera.projectionMatrix(aspect: Double(aspect)) * view
        inverseView = simd_inverse(view)
        apertureBlades = max(0, camera.apertureBlades)
    }
}
