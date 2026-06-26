import Foundation
import simd
import COllinShaders

// `OllinVertex`, `Uniforms`, and `SDFInstance` are imported from the
// `COllinShaders` C module: one definition shared with the shaders, so their
// CPU/GPU memory layout can't drift. See Sources/Ollin/Renderer/OllinShaderTypes.h.

extension OllinVertex {
    /// A triangle-path vertex. `aa` (the fringe coverage interpolant) is read only
    /// by the fringe pipeline, so it defaults to zero for ordinary triangles.
    init(position: SIMD2<Float>, color: SIMD4<Float>) {
        self.init(position: position, aa: SIMD2<Float>(0, 0), color: color)
    }
}

/// Which analytic shape an `SDFInstance` carries. The fragment shader switches
/// on this tag and evaluates the matching signed-distance field, so one pipeline
/// and one instance buffer serve every SDF primitive. Raw values must match the
/// `shape` codes the fragment in `ShaderShapes.metal` tests.
enum SDFShape: UInt32 {
    case ellipse  = 0   // size = (rx, ry); circle is rx == ry
    case box      = 1   // size = (w/2, h/2); extra = corner radius
    case capsule  = 2   // a line: param0 = (b-a)/2; extra = half-width; fill = line color
    case arcOpen  = 3   // circular arc, open: size = (ra, ra)
    case arcChord = 4   // circular arc, chord-closed
    case arcPie   = 5   // circular arc, pie-closed
    case triangle = 6   // isosceles: apex at center, size = (base/2, height), opens +y
    case star     = 7   // regular n-gon / star: size = (R, R); param0/param1/extra = fold angles
    case marker   = 8   // point marker: size = (h, h); extra = kind (0 square,1 diamond,2 cross,3 x); param0.x = arm half-width
    case rhombus  = 9   // diamond: size = (w/2, h/2); extra = corner radius
    case vesica   = 10  // pointed lens: param0 = (circle radius, offset); param1.x = horizontal flag; extra = corner radius
    case moon     = 11  // crescent: param0 = (outer radius, inner radius); param1.x = offset; extra = corner radius
    case cross    = 12  // plus: size.x = arm half-length; param0.x = arm half-width; extra = corner radius
    case ring     = 13  // filled annulus: param0 = (mid radius, half thickness); fill only
    case trapezoid     = 14  // isosceles: param0 = (top half-width, bottom half-width); size.y = half-height
    case parallelogram = 15  // param0.x = base half-width; size.y = half-height; extra = skew
    case egg           = 16  // param0 = (bottom radius, top radius); points up
    case heart         = 17  // param0.x = unit->local scale; lobes up
    case cutDisk       = 18  // param0 = (radius, cut height); flat edge down
    case unevenCapsule = 19  // tapered capsule: param0 = (r1, r2); param1 = (cos, sin) axis; extra = length
    case horseshoe     = 20  // thick open arc: param0 = (cos, sin) half-gap; param1 = (cap half-len, half-thick); extra = mid radius
    case parabola      = 21  // filled parabolic arch: param0 = (top half-width, height); opens up
    case roundedX      = 22  // an X with round arms: param0.x = arm reach; extra = arm half-width
    case blobbyCross   = 23  // 4-fold concave cross: param0 = (scale, blobbiness)
    case tunnel        = 24  // archway (rounded top, flat base): param0 = (half-width, wall height)
    case stairs        = 25  // staircase: param0 = (step width, step height); extra = step count
    case coolS         = 26  // the iconic "S": param0.x = scale
    case triangle3     = 27  // general triangle: param0/param1/param2 = the three corners (rel. center)
    case bezier        = 28  // quadratic Bézier stroke: param0/param1/param2 = (start, control, end); extra = half-width
    case orientedBox   = 29  // box between two points: param0/param1 = centerline endpoints (rel. center); extra = thickness
    case orientedVesica = 30 // lens between two points: param0/param1 = tip endpoints (rel. center); extra = waist half-width
}

extension SDFShape {
    /// Whether this shape honors `hollow` mode — a closed region whose interior
    /// can be turned into a constant-width band (opOnion). Point markers, lines,
    /// and arcs aren't closed regions; the ring is already a band; so they ignore
    /// it. (The disk/`ellipse` honors it, becoming an elliptical ring; the
    /// round-dot point path opts out separately, since it shares the tag.)
    var honorsHollow: Bool {
        switch self {
        case .capsule, .marker, .arcOpen, .arcChord, .arcPie, .ring, .bezier:
            return false
        default:
            return true
        }
    }

    /// Whether this shape is a closed region the SDF-combinator VM can evaluate
    /// (`ollin_sdf_distance` handles it). The open marks (lines, the open/chord/pie
    /// arcs, and the Bézier stroke) have no interior to merge, so a combine block
    /// skips them.
    var isCombinable: Bool {
        switch self {
        case .capsule, .arcOpen, .arcChord, .arcPie, .bezier:
            return false
        default:
            return true
        }
    }
}

/// Which pipeline a run of recorded geometry needs. Primitives are recorded in
/// call order; a `Batch` starts wherever the kind changes, so SDF shapes and
/// tessellated triangles still composite front-to-back in the order the sketch
/// drew them (a later shape paints over an earlier one).
enum GeometryKind {
    case triangles    // tessellated fills/strokes in `vertices`
    case sdf          // instanced SDF shapes in `sdfInstances`
    case image        // one textured quad in `imageVertices`, sampling `image`
    case glyphAtlas   // SDF-atlas text quads in `glyphVertices`, sampling `atlas`
    case particles    // instanced GPU-particle discs reading a compute buffer
    case points3D     // instanced 3D point-cloud splats in `points`, through the camera
    case mesh3D       // solid triangle-mesh geometry in `meshVertices`, through the camera
    case fringe       // edge-expanded stroke + ~1px AA fringe in `vertices` (the high-quality stroke path)
    case depthScene   // a backdrop quad in `imageVertices` that also primes the depth buffer from a depth map
    case sdfGroup     // composed SDF field (combinator) in `sdfGroups`, evaluating `sdfNodes`
    case sdfGroup3D   // raymarched composed 3D SDF field in `sdf3DGroups`, evaluating `sdf3DNodes`
}

struct GeometryBatch {
    var kind: GeometryKind
    var vertexStart: Int     // first vertex (triangle batches)
    var instanceStart: Int   // first SDF instance (sdf batches)
    var imageStart: Int = 0  // first image vertex (image batches)
    var glyphStart: Int = 0  // first glyph vertex (glyphAtlas batches)
    var pointStart: Int = 0  // first point (points3D batches)
    var meshStart: Int = 0   // first mesh vertex (mesh3D batches)
    var sdfGroupStart: Int = 0 // first SDF-combinator group (sdfGroup batches)
    var sdf3DGroupStart: Int = 0 // first 3D SDF-combinator field (sdfGroup3D batches)
    /// The blend mode active when this run was recorded; selects the pipeline.
    /// A run breaks (a new batch opens) whenever the blend mode changes, so each
    /// batch composites with a single mode.
    var blendMode: BlendMode = .normal
    /// Texture source for an `.image` batch — `nil` otherwise. Each image draw is
    /// its own batch (one texture per draw call), so it never merges with a
    /// neighbour.
    var image: Image?
    /// SDF atlas for a `.glyphAtlas` batch — `nil` otherwise. One `drawText` call
    /// is one batch (a paragraph's glyphs all sample the same atlas).
    var atlas: GlyphAtlas?
    /// The GPU particle buffer for a `.particles` batch — `nil` otherwise. Each
    /// `drawParticles` call is its own batch carrying its buffer.
    var particleBuffer: ComputeBindable?
    /// Number of particles to draw (instances) for a `.particles` batch.
    var particleCount: Int = 0
    /// Clip-space z (Metal NDC, [0,1]) this 2D batch tests and writes against the
    /// 3D depth buffer — `nil` (the default) means "draw over" (always-pass, no
    /// write), the byte-identical legacy behavior. Set by `depth(at:)` and carried
    /// only on 2D batches in a depth pass; 3D (`points3D`) batches derive their own
    /// depth from the camera and ignore it. A change in depth breaks the batch.
    var depth: Float?
    /// The depth map for a `.depthScene` batch — sampled per pixel and written to
    /// the depth buffer (with `image` as the color backdrop). `nil` otherwise.
    var depthImage: Image?
    /// The *metric* depth map (meters) for a metric `.depthScene` batch, written to
    /// the depth buffer as true clip-space depth against the active camera's near/far
    /// (the conversion coefficients ride in the quad's vertex tint). `nil` for the
    /// normalized gray path — exactly one of `depthImage`/`metricDepth` is set.
    var metricDepth: MetricDepthMap?
    /// The surface material for a *textured* `.mesh3D` batch — its `texture` is bound
    /// to the mesh fragment and `baseColor` is already baked into the vertices. `nil`
    /// for an untextured mesh (the byte-identical solid path). A textured mesh opens
    /// its own batch (one texture per batch), like an image.
    var material: MeshMaterial?
    /// The surface *finish* for a solid/textured `.mesh3D` batch — the shading model and
    /// the Blinn-Phong/rim/subsurface/iridescence parameters, bound to the lit mesh
    /// fragment as an `OllinMaterial` uniform. Constant across the batch (a solid mesh
    /// batch breaks when the finish changes); unused by the wireframe path.
    var finish = OllinMaterial()
    /// Whether a `.mesh3D` batch draws as a wireframe (triangle edges only), selecting
    /// the wireframe pipeline. The edge color is baked into the vertices and the line
    /// width rides `position.w`; lighting/material are unused.
    var meshWireframe = false
    /// The matcap sphere texture for a `.mesh3D` batch — sampled by the view-space
    /// normal, selecting the matcap pipeline. When set, the whole look comes from this
    /// texture and lighting/material/shadow are bypassed. `nil` for a lit mesh. A matcap
    /// mesh opens its own batch (one texture per batch), like a textured one.
    var matcap: Image?
    /// The off-screen effects layer this run draws into. `nil` (the default) is the
    /// main canvas. Set while inside a `withTarget` block, so the renderer routes the
    /// run into that target's texture in a pass before the main one (see `RenderTarget`).
    var target: RenderTarget?
}

/// The drawing state machine and per-frame geometry recorder.
///
/// `Drawer` is a state machine: you set *state* (fill, stroke, weight,
/// background) and then call *primitives* (circle, …). Each primitive is
/// tessellated on the CPU into triangles and appended to `vertices`, which the
/// renderer uploads and draws in a single pass.
///
/// State (fill/stroke/weight/background) persists across frames.
/// Geometry does not: the runner calls `beginFrame()` each frame to clear it.
final class Drawer {
    // MARK: Drawing state (persists across frames)

    /// The clear color for the frame. `nil`-fill / `nil`-stroke mean "don't draw".
    private(set) var backgroundColor: Color = .black
    private var fillPaint: Paint? = .color(.white)     // default: white fill
    private var strokePaint: Paint? = .color(.black)   // default: black stroke
    private var strokeWidth: Double = 1         // default: 1px
    private var pointDiameter: Double = 1       // default: 1px dot (see pointSize / drawPoint)
    private var marker: PointMarker = .circle   // default: round dot (see pointMarker / drawPoint)
    private var hollowWidth: Double = 0         // 0 = solid fill; > 0 = hollow band (see hollow / solid)
    private var strokeAlignment: StrokeAlign = .center   // where the stroke sits on the outline (see strokeAlign)
    private var strokeJoinStyle: StrokeJoin = .miter     // how stroked-path corners turn (see strokeJoin)
    private var strokeCapStyle: StrokeCap = .butt        // how open stroked-path ends finish (see strokeCap)
    private var currentMaterial = Material()    // 3D mesh surface finish (shading model + specular/rim/subsurface/iridescence); see material(_:)
    private var wireframeEnabled = false        // 3D mesh: draw triangle edges only (see wireframe)
    private var currentMatcap: Image?           // 3D mesh: a matcap sphere texture replacing the lit look (see matcap(_:))
    private var currentFont: ActiveFont = .outline(.systemMedium)   // active text font (see textFont / drawText)
    private var textPixelSize: Double = 24               // rendered glyph height in points (see textSize)
    private var textAlignH: TextAlignH = .left           // horizontal text anchor (see textAlign)
    private var textAlignV: TextAlignV = .baseline       // vertical text anchor (see textAlign)
    private var textRenderMode: TextMode = .outline      // outline vs SDF-atlas text (see textMode)
    private var tintColor: Color? = nil                  // multiplies drawImage texels; nil = untinted (see tint / noTint)
    private var currentBlend: BlendMode = .normal        // how shapes combine with the canvas (see blendMode)
    private var currentDepth: Float? = nil               // clip-z for 2D draws in a 3D scene; nil = draw over (see depth(at:))

    /// When true the canvas is *not* cleared each frame — drawing piles up across
    /// frames on a persistent accumulation surface instead (see `noClear` /
    /// `clearEachFrame`). A mode, not per-frame state: it persists until changed.
    /// The renderer reads it to route through the accumulation target; calling
    /// `background(_:)` while it's on wipes the pile (the long-exposure reset),
    /// reported through `backgroundSetThisFrame`.
    private(set) var accumulates: Bool = false

    /// How the linear-float frame is mapped to the 8-bit display in the present
    /// pass (see `toneMap` / `ToneMap`). A frame-wide mode, not per-shape state:
    /// one mapping over the finished frame, so it persists until changed and is
    /// not saved by `withState`. `.clamp` (the default) reproduces the prior
    /// clip-to-[0,1] look. The renderer reads both when it runs the present pass.
    private(set) var toneMapMode: ToneMap = .clamp
    /// Linear exposure multiplier applied before the tone-map (1 = unchanged).
    private(set) var toneMapExposure: Double = 1

    /// Whether `background(_:)` was called during the frame being recorded. Reset
    /// at the start of each frame and set by `background(_:)`. Only consulted by
    /// the renderer in accumulation mode, where it means "wipe the persistent
    /// canvas to the background color this frame" (otherwise the frame loads the
    /// accumulated pile). In the ordinary clear-each-frame path it's ignored — the
    /// frame always clears.
    private(set) var backgroundSetThisFrame: Bool = false

    // MARK: Per-frame geometry (reset every frame)

    private(set) var vertices: [OllinVertex] = []

    /// Instanced SDF shapes recorded this frame (see `SDFInstance`).
    private(set) var sdfInstances: [SDFInstance] = []

    /// Composed SDF fields (combinator groups) recorded this frame, plus the flat
    /// instruction nodes they index into (see `SDFGroupInstance` / `SDFNode` and
    /// ShaderCombinator.metal). One `drawSDF` call appends one group + its nodes.
    private(set) var sdfGroups: [SDFGroupInstance] = []
    private(set) var sdfNodes: [SDFNode] = []
    private(set) var sdf3DGroups: [SDF3DGroupInstance] = []
    private(set) var sdf3DNodes: [SDFNode3D] = []

    /// The open scoped-combine blocks (`smoothUnion { … }` etc.). While the stack is
    /// non-empty, SDF region draw calls are captured as `SDF` leaves into the innermost
    /// frame instead of drawn; closing the outermost frame builds the field and draws
    /// it. `combineGroupTransform` is the CTM when the outermost block opened, so a leaf
    /// drawn under a changed CTM lands in the group's field space.
    private var combineStack: [CombineFrame] = []
    private var combineGroupTransform: matrix_float3x3?
    private var combineGroupModel: matrix_float4x4?
    private var warnedNonCombinable = false
    private var warnedMeshInCombine = false

    /// Textured-quad vertices recorded this frame (see `drawImage`). Each image
    /// draw appends 6 vertices (two triangles) and opens its own `.image` batch,
    /// which carries the texture.
    private(set) var imageVertices: [OllinImageVertex] = []

    /// SDF-atlas text quads recorded this frame (see `drawAtlasText`). Each glyph
    /// is 6 vertices (two triangles) sampling the font's atlas; reuses the image
    /// vertex layout (position + uv + `tint` as the fill color).
    private(set) var glyphVertices: [OllinImageVertex] = []

    /// 3D point-cloud splats recorded this frame (see `drawPointCloud`). World-space
    /// points drawn through `camera3D`; each is one instanced camera-facing quad.
    private(set) var points: [OllinPoint] = []

    /// Solid 3D mesh vertices recorded this frame (see `drawMesh`). The model
    /// matrix and its normal matrix are baked in CPU-side, so these are world-space
    /// positions + normals drawn through `camera3D`; triangle indices are expanded
    /// into this flat list (no index buffer), matching the 2D triangle path.
    private(set) var meshVertices: [OllinMeshVertex] = []

    /// The active 3D camera, or `nil` for a 2D frame (the default). Per-frame state
    /// like the geometry — set with `camera`/`perspective`/`ortho`, reset each
    /// frame. When set, the renderer allocates a depth buffer and draws 3D geometry
    /// through it; a 2D-only frame leaves it `nil` and is untouched.
    private(set) var camera3D: Camera3D?

    /// Lights for the 3D mesh material, set this frame (see `Light`). Per-frame
    /// state like the camera — reset each frame, accumulated by `addLight`.
    private(set) var lights: [Light] = []

    /// Ambient light for the 3D mesh material — a flat term added to every lit
    /// surface (see `ambientLight`). Per-frame state; `nil` means none.
    private(set) var ambientLightColor: Color?

    /// How the 3D mesh material is lit this frame.
    enum LightingMode {
        case auto    // nothing set → the default rig (solids look shaded out of the box)
        case custom  // the sketch set its own lights/ambient
        case off     // `noLights()` → flat, unlit surfaces
    }
    private(set) var lightingMode: LightingMode = .auto

    /// The image-based-lighting environment set this frame (see `Environment`), or `nil`
    /// for none. Per-frame state like the lights; when set, the renderer bakes its IBL
    /// maps once (cached by source) and the physically-based materials gather their
    /// ambient and reflections from it.
    private(set) var environment: Environment?

    /// Whether this frame casts shadows (see `castShadows`). Per-frame state like the
    /// lights — reset each frame, set in `draw()`. When on, the scene's primary
    /// directional light casts; the renderer renders a depth pass from it and the mesh
    /// fragment dims that light where a receiver is occluded.
    private(set) var castsShadows = false

    /// Whether this frame ray-traces scene reflections off its physically-based surfaces
    /// (see `rayTracedReflections`). Per-frame state like the lights. When on (and the
    /// device can trace from the render stages), a PBR metal's environment reflection is
    /// replaced by a traced reflection of the actual scene; the renderer builds the caster
    /// acceleration structure for it and sets `OllinLighting.rtReflections`. A no-op on a
    /// non-ray-tracing GPU (the IBL-prefilter reflection remains).
    private(set) var rayTracedReflectionsEnabled = false

    /// The soft-shadow quality knob (`shadowQuality`/`shadowSamples`) — a persistent setting
    /// (not reset each frame, like `toneMap`): more rays give a smoother ray-traced penumbra
    /// at proportional GPU cost. A `Quality` tier scales with the GPU (the renderer resolves
    /// it, so a hardware-RT GPU gets a richer level than a software-RT one); an absolute count
    /// pins an exact value. Only the ray-traced point path reads it; directional/spot and the
    /// non-RT cube fallback ignore it.
    private(set) var shadowQualitySetting: ShadowQualitySetting = .tier(.default)

    /// The raymarched-3D-SDF (`drawSDF3D`) quality intent: a `RenderQuality` tier the renderer
    /// resolves to a march-step budget + internal render scale, or an exact step count. Read
    /// only by the raymarch path; `.tier(.default)` reproduces the pre-dial constants.
    private(set) var raymarchQualitySetting: RaymarchQualitySetting = .tier(.default)

    /// The shadow map resolution the renderer renders the depth pass into. Kept here
    /// only to size the normal-offset bias in world units (`shadowTexelWorld`); the
    /// renderer owns the actual texture and must use the same value (`MetalRenderer`).
    static let shadowMapResolution = 2048
    /// The per-face resolution of the omnidirectional (point) shadow cube. Same role as
    /// `shadowMapResolution` for the cube bias; mirror of `MetalRenderer`'s value.
    static let pointShadowMapResolution = 1024

    /// The default lighting rig — used when a sketch draws meshes without setting any
    /// light, so a solid is shaded out of the box. It *is* `LightingPreset.standard`
    /// (one source of truth): the `lights()` convenience installs the same preset.
    static var defaultAmbient: Color { LightingPreset.standard.ambient }
    static var defaultLights: [Light] { LightingPreset.standard.lights }

    /// Whether a depth scene (`drawDepthScene`) was recorded this frame. Like an
    /// active camera, it makes the renderer allocate the depth buffer — so a 2D
    /// sketch can prime depth from a depth map and composite 2D against it with no
    /// 3D camera. Reset each frame; the depth buffer is gated on this *or* a camera.
    private(set) var hasDepthScene = false

    /// True when this frame needs a depth buffer — an active 3D camera or a depth
    /// scene. The renderer reads it to allocate (and clear) the depth attachment.
    var usesDepthBuffer: Bool { camera3D != nil || hasDepthScene }

    /// Total GPU particles drawn this frame, summed across `.particles` batches —
    /// for the stats readout, since the particle buffer is GPU-resident and so isn't
    /// in any CPU vertex array (3D point splats live in `points`, counted directly).
    var particleCount: Int {
        batches.reduce(0) { $0 + ($1.kind == .particles ? $1.particleCount : 0) }
    }

    /// Compute dispatches recorded this frame (see `compute` / `Particles`), drained
    /// by the renderer into a compute encoder *ahead* of the geometry pass so a sim
    /// step and the draw that reads its output stay ordered within one frame. Reset
    /// each frame — but NOT by `background(_:)` (a dispatch is a sim step, not
    /// geometry to wipe).
    private(set) var dispatches: [RecordedDispatch] = []

    /// Standard per-frame constants bound into every dispatch at buffer index 10
    /// (`u.time`/`u.dt`/`u.resolution`/`u.mouse`/`u.frameCount`). `particleCount` is
    /// filled per dispatch by the renderer; `custom` per dispatch by the caller.
    /// Set once per frame by the runner via `setComputeFrame`.
    private(set) var computeUniforms = OllinComputeUniforms(
        resolution: .zero, mouse: .zero, time: 0, dt: 0,
        frameCount: 0, particleCount: 0, custom: .zero)

    /// Recorded geometry split into call-ordered runs, so triangles and SDF
    /// shapes composite in draw order rather than in two unordered passes.
    private(set) var batches: [GeometryBatch] = []
    private var currentKind: GeometryKind?
    /// The blend mode of the currently-open batch, so a blend-mode change opens a
    /// fresh batch even when the geometry kind is unchanged.
    private var currentBatchBlend: BlendMode = .normal
    /// The 2D depth of the currently-open batch, so a `depth(at:)`/`noDepth()`
    /// change opens a fresh batch even when kind and blend are unchanged.
    private var currentBatchDepth: Float? = nil

    // MARK: Effects layers (render targets, per-frame)

    /// The off-screen-target redirection stack: while non-empty, drawing is tagged
    /// for the innermost target instead of the main canvas (see `withTarget`). Each
    /// frame records the buffer/batch counts at push, so `background(_:)` inside a
    /// block can clear *just that target*.
    private var targetStack: [TargetFrame] = []
    /// The target drawing currently lands in, if any (the innermost active block).
    private var currentTarget: RenderTarget? { targetStack.last?.target }
    /// Geometry targets drawn into this frame, in first-use order; the renderer
    /// fills each before the main pass that samples it.
    private(set) var renderTargets: [RenderTarget] = []
    /// Filter outputs recorded this frame (`target.filtered(...)`), in record order;
    /// the renderer runs each after the geometry targets it reads are filled.
    private(set) var filterOps: [RenderTarget] = []
    /// Whole-frame filters from `postProcess(_:)`, applied to the finished frame
    /// before the present pass, in record order.
    private(set) var frameFilters: [Filter] = []

    /// A `withTarget` block's start state, so `background(_:)` inside it truncates
    /// back to here (clearing only this target's own geometry).
    private struct TargetFrame {
        let target: RenderTarget
        let snapshot: GeometrySnapshot
    }
    /// Buffer/batch lengths at one moment, for rolling target geometry back.
    private struct GeometrySnapshot {
        let batches, vertices, sdf, image, glyph, points, mesh, sdfGroup, sdfNode: Int
        let sdf3DGroup, sdf3DNode: Int
    }
    private func snapshot() -> GeometrySnapshot {
        GeometrySnapshot(batches: batches.count, vertices: vertices.count,
                         sdf: sdfInstances.count, image: imageVertices.count,
                         glyph: glyphVertices.count, points: points.count,
                         mesh: meshVertices.count,
                         sdfGroup: sdfGroups.count, sdfNode: sdfNodes.count,
                         sdf3DGroup: sdf3DGroups.count, sdf3DNode: sdf3DNodes.count)
    }
    /// The surface finish of the currently-open *solid* mesh batch, so a `material(_:)`
    /// change opens a fresh batch (the finish is bound once per batch as a uniform).
    private var currentBatchMaterial = Material()

    /// When set, draw calls are recorded as vector geometry for SVG export instead
    /// of being tessellated/SDF-encoded for the GPU (see SVGExport.swift). It lives
    /// outside the per-frame reset so the exporter owns its lifecycle.
    var svgRecorder: SVGRecorder?

    // MARK: Gradient rows

    /// One baked LUT row per distinct gradient ramp used this frame, in row
    /// order — the renderer uploads these as the gradient strip texture an SDF
    /// instance's `fillGradient`/`strokeGradient` row indices point into.
    private(set) var gradientRows: [[UInt8]] = []
    private var gradientRowIndex: [Ramp: Int] = [:]

    /// Baked ramps, kept across frames so a steady gradient bakes once, not per
    /// frame. Wiped wholesale past a generous cap (an animated ramp churns keys;
    /// re-baking is microseconds, unbounded growth is not).
    private var bakedGradients: [Ramp: BakedGradient] = [:]

    /// The strip row (and its baked samples) for `ramp`, registering it for this
    /// frame on first use.
    private func gradientRow(for ramp: Ramp) -> (index: Int, baked: BakedGradient) {
        let baked: BakedGradient
        if let cached = bakedGradients[ramp] {
            baked = cached
        } else {
            if bakedGradients.count >= 256 { bakedGradients.removeAll(keepingCapacity: true) }
            baked = BakedGradient(ramp)
            bakedGradients[ramp] = baked
        }
        if let index = gradientRowIndex[ramp] { return (index, baked) }
        let index = gradientRows.count
        gradientRows.append(baked.bytes)
        gradientRowIndex[ramp] = index
        return (index, baked)
    }

    /// Open a new batch when the geometry kind, the blend mode, *or* the 2D depth
    /// changes; a no-op while all three are unchanged, so it's cheap to call per
    /// primitive.
    private func ensureBatch(_ kind: GeometryKind) {
        guard currentKind != kind || currentBatchBlend != currentBlend
            || currentBatchDepth != currentDepth else { return }
        currentKind = kind
        currentBatchBlend = currentBlend
        currentBatchDepth = currentDepth
        batches.append(GeometryBatch(kind: kind, vertexStart: vertices.count,
                                     instanceStart: sdfInstances.count,
                                     imageStart: imageVertices.count,
                                     glyphStart: glyphVertices.count,
                                     pointStart: points.count,
                                     meshStart: meshVertices.count,
                                     sdfGroupStart: sdfGroups.count,
                                     sdf3DGroupStart: sdf3DGroups.count,
                                     blendMode: currentBlend, depth: currentDepth,
                                     target: currentTarget))
    }

    /// Open a fresh `.image` batch carrying `image` as its texture. Unlike
    /// `ensureBatch`, this always appends — each image draw binds its own texture,
    /// so two consecutive images can't share a batch. Resets `currentKind` so a
    /// following triangle/SDF primitive reopens its own batch.
    private func beginImageBatch(_ image: Image) {
        currentKind = .image
        currentBatchBlend = currentBlend
        currentBatchDepth = currentDepth
        batches.append(GeometryBatch(kind: .image, vertexStart: vertices.count,
                                     instanceStart: sdfInstances.count,
                                     imageStart: imageVertices.count,
                                     glyphStart: glyphVertices.count,
                                     pointStart: points.count,
                                     meshStart: meshVertices.count,
                                     sdfGroupStart: sdfGroups.count,
                                     sdf3DGroupStart: sdf3DGroups.count,
                                     blendMode: currentBlend, image: image, depth: currentDepth,
                                     target: currentTarget))
    }

    /// Open a fresh `.mesh3D` batch for a *textured*, *wireframe*, or *matcap* mesh
    /// (carrying its `material` texture, surface `finish`, wireframe flag, or `matcap`
    /// texture). Always appends — each binds its own state, so it can't share a batch —
    /// and clears `currentKind` so a following mesh (any mode) opens its own batch
    /// rather than merging into this one.
    private func beginMeshBatch(material: MeshMaterial?, finish: OllinMaterial,
                                wireframe: Bool = false, matcap: Image? = nil) {
        batches.append(GeometryBatch(kind: .mesh3D, vertexStart: vertices.count,
                                     instanceStart: sdfInstances.count,
                                     imageStart: imageVertices.count,
                                     glyphStart: glyphVertices.count,
                                     pointStart: points.count,
                                     meshStart: meshVertices.count,
                                     sdfGroupStart: sdfGroups.count,
                                     sdf3DGroupStart: sdf3DGroups.count,
                                     blendMode: currentBlend, depth: currentDepth,
                                     material: material, finish: finish,
                                     meshWireframe: wireframe, matcap: matcap,
                                     target: currentTarget))
        currentKind = nil
    }

    /// Open or continue the solid (untextured, non-wireframe) `.mesh3D` batch. Solid
    /// meshes merge into one batch as long as the blend, depth, and surface finish are
    /// unchanged — the finish is bound per batch as one uniform, so a change in
    /// `material(_:)` breaks the batch (like a blend-mode change does).
    private func ensureSolidMeshBatch(_ m: Material) {
        if currentKind == .mesh3D, currentBatchBlend == currentBlend,
           currentBatchDepth == currentDepth, currentBatchMaterial == m {
            return
        }
        currentKind = .mesh3D
        currentBatchBlend = currentBlend
        currentBatchDepth = currentDepth
        currentBatchMaterial = m
        batches.append(GeometryBatch(kind: .mesh3D, vertexStart: vertices.count,
                                     instanceStart: sdfInstances.count,
                                     imageStart: imageVertices.count,
                                     glyphStart: glyphVertices.count,
                                     pointStart: points.count,
                                     meshStart: meshVertices.count,
                                     sdfGroupStart: sdfGroups.count,
                                     sdf3DGroupStart: sdf3DGroups.count,
                                     blendMode: currentBlend, depth: currentDepth,
                                     finish: m.gpuMaterial(), target: currentTarget))
    }

    /// Open a fresh `.glyphAtlas` batch carrying `atlas` as its texture. One
    /// `drawText` call opens one batch (all its glyphs sample the same atlas);
    /// resets `currentKind` so a following primitive reopens its own batch.
    private func beginGlyphBatch(_ atlas: GlyphAtlas) {
        currentKind = .glyphAtlas
        currentBatchBlend = currentBlend
        currentBatchDepth = currentDepth
        batches.append(GeometryBatch(kind: .glyphAtlas, vertexStart: vertices.count,
                                     instanceStart: sdfInstances.count,
                                     imageStart: imageVertices.count,
                                     glyphStart: glyphVertices.count,
                                     pointStart: points.count,
                                     meshStart: meshVertices.count,
                                     sdfGroupStart: sdfGroups.count,
                                     sdf3DGroupStart: sdf3DGroups.count,
                                     blendMode: currentBlend, atlas: atlas, depth: currentDepth,
                                     target: currentTarget))
    }

    /// Record a compute dispatch for this frame (see `Sketch.compute` / `Particles`).
    func recordDispatch(_ dispatch: RecordedDispatch) { dispatches.append(dispatch) }

    // MARK: Effects layers

    /// Redirect drawing in `body` into `target` instead of the main canvas: every
    /// primitive drawn inside the closure is tagged for the target, which the
    /// renderer fills in its own pass before the main one. Nestable; a fresh batch
    /// is forced at each boundary so target and main geometry never merge.
    func withTarget(_ target: RenderTarget, _ body: () -> Void) {
        if !renderTargets.contains(where: { $0 === target }) { renderTargets.append(target) }
        targetStack.append(TargetFrame(target: target, snapshot: snapshot()))
        currentKind = nil    // force the first draw inside the target into a fresh batch
        body()
        targetStack.removeLast()
        currentKind = nil    // and force the next main draw into a fresh, untagged batch
    }

    /// Redirect `body` into a persistent `Feedback` layer's write surface, handing
    /// it last frame's content as `prev`. The block lands in the layer's back buffer
    /// (cleared transparent each frame unless `background(_:)` sets it); the renderer
    /// keeps the ping-pong pair across frames, so what's drawn becomes next frame's
    /// `prev`. Records exactly like `withTarget(_:)`, just with the previous-frame
    /// image passed in.
    func withFeedback(_ feedback: Feedback, _ body: (Image) -> Void) {
        feedback.writeLayer.clearColor = .clear
        withTarget(feedback.writeLayer) { body(feedback.previous) }
    }

    /// The no-argument form: redirect `body` into a `Feedback` layer's write surface,
    /// reading last frame by name via `feedback.previous` inside. Same recording as
    /// `withFeedback`; the closure parameter is the only difference.
    func withTarget(_ feedback: Feedback, _ body: () -> Void) {
        feedback.writeLayer.clearColor = .clear
        withTarget(feedback.writeLayer, body)
    }

    /// Redirect `body` into a persistent `SimField`'s seed surface: the marks drawn
    /// inside are composited onto the field's current state, which the renderer then
    /// evolves one frame by the field's `Sim`. Records exactly like `withTarget(_:)`;
    /// the field carries its own state across frames (no `previous` to read).
    func withField(_ field: SimField, force: Vector2 = .zero, _ body: () -> Void) {
        field.writeLayer.clearColor = .clear
        field.seedForce = force
        withTarget(field.writeLayer, body)
    }

    /// Whether this frame holds cross-frame state the renderer keeps in ping-pong textures:
    /// a `Feedback`/`SimField` layer, or a `.screenSpaceReflections` combine (its temporal
    /// resolve accumulates the reflection across frames). Like the accumulation surface, the
    /// headless frame-grab must render every warmup frame (not just step compute) for that
    /// state to evolve, so a single-frame export of an SSR scene captures the converged
    /// reflection. See `OllinApp.image(of:)`.
    var usesFeedback: Bool {
        renderTargets.contains {
            switch $0.origin { case .feedback, .simField: return true; default: return false }
        } || filterOps.contains {
            if case let .combine(_, _, op) = $0.origin, case .screenSpaceReflections = op.kind { return true }
            return false
        }
    }

    /// Record a procedural generator as a source layer the renderer fills before
    /// any filters run (it reads no input). Returns the layer for compositing/filtering.
    func generate(_ generator: Generator, width: Int, height: Int, scale: Double) -> RenderTarget {
        let target = RenderTarget(width: width, height: height, scale: scale,
                                  drawer: self, origin: .generator(generator))
        renderTargets.append(target)
        return target
    }

    /// Record a filter of `input`, returning the output layer the renderer will fill.
    func recordFilter(_ filter: Filter, of input: RenderTarget) -> RenderTarget {
        let output = RenderTarget(width: input.width, height: input.height, scale: input.scale,
                                  drawer: self, origin: .filter(input: input, filter: filter))
        filterOps.append(output)
        return output
    }

    /// Record a combine of `base` with `aux`, returning the output layer the renderer
    /// will fill. Output follows `base`'s size/resolution. Recorded into the same op
    /// list as filters: in record order, so both inputs (which must already exist to
    /// be referenced, and whose own filter/combine ops were appended earlier) are
    /// resolved before this op runs.
    func recordCombine(_ base: RenderTarget, _ aux: RenderTarget, _ op: Combine) -> RenderTarget {
        // Ambient occlusion and screen-space reflections read a surface normal: ask the
        // renderer to capture a true mesh-normal layer for `base` (instead of the shader
        // reconstructing one from depth, which is ambiguous at concave seams). Only when
        // `base` actually holds a 3D scene; a hand-drawn depth map leaves `needsDepth`
        // false, so the shader keeps its depth-reconstruction path and the frame stays
        // byte-identical.
        if base.needsDepth {
            switch op.kind {
            case .ambientOcclusion, .screenSpaceReflections: base.needsNormals = true
            default: break
            }
        }
        let output = RenderTarget(width: base.width, height: base.height, scale: base.scale,
                                  drawer: self, origin: .combine(base: base, aux: aux, op: op))
        filterOps.append(output)
        return output
    }

    /// Queue a whole-frame filter, applied to the finished frame before present.
    func postProcess(_ filter: Filter) { frameFilters.append(filter) }

    /// Roll the recorded geometry back to `s`, used by `background(_:)` inside a
    /// `withTarget` block to clear just that target's geometry. (Gradient rows are
    /// left as-is: any orphaned row is an unused strip texel, harmless.)
    private func truncate(to s: GeometrySnapshot) {
        if batches.count > s.batches { batches.removeLast(batches.count - s.batches) }
        if vertices.count > s.vertices { vertices.removeLast(vertices.count - s.vertices) }
        if sdfInstances.count > s.sdf { sdfInstances.removeLast(sdfInstances.count - s.sdf) }
        if imageVertices.count > s.image { imageVertices.removeLast(imageVertices.count - s.image) }
        if glyphVertices.count > s.glyph { glyphVertices.removeLast(glyphVertices.count - s.glyph) }
        if points.count > s.points { points.removeLast(points.count - s.points) }
        if meshVertices.count > s.mesh { meshVertices.removeLast(meshVertices.count - s.mesh) }
        if sdfGroups.count > s.sdfGroup { sdfGroups.removeLast(sdfGroups.count - s.sdfGroup) }
        if sdfNodes.count > s.sdfNode { sdfNodes.removeLast(sdfNodes.count - s.sdfNode) }
        if sdf3DGroups.count > s.sdf3DGroup { sdf3DGroups.removeLast(sdf3DGroups.count - s.sdf3DGroup) }
        if sdf3DNodes.count > s.sdf3DNode { sdf3DNodes.removeLast(sdf3DNodes.count - s.sdf3DNode) }
    }

    /// Open a `.particles` batch drawing `count` instances from the GPU `buffer`.
    /// Like `beginImageBatch`, it always appends (each draw carries its own buffer)
    /// and resets `currentKind` so a following primitive reopens its own batch. The
    /// particle buffer's positions are in canvas space, so it rides no CTM.
    func recordParticles(_ buffer: ComputeBindable, count: Int) {
        guard count > 0 else { return }
        currentKind = .particles
        currentBatchBlend = currentBlend
        currentBatchDepth = currentDepth
        batches.append(GeometryBatch(kind: .particles, vertexStart: vertices.count,
                                     instanceStart: sdfInstances.count,
                                     imageStart: imageVertices.count,
                                     glyphStart: glyphVertices.count,
                                     pointStart: points.count,
                                     meshStart: meshVertices.count,
                                     sdfGroupStart: sdfGroups.count,
                                     sdf3DGroupStart: sdf3DGroups.count,
                                     blendMode: currentBlend,
                                     particleBuffer: buffer, particleCount: count,
                                     depth: currentDepth, target: currentTarget))
    }

    /// Set the standard compute uniforms for this frame (called by the runner before
    /// `draw()`). `particleCount`/`custom` are filled per dispatch.
    func setComputeFrame(resolution: SIMD2<Float>, mouse: SIMD2<Float>,
                         time: Float, dt: Float, frameCount: UInt32) {
        computeUniforms = OllinComputeUniforms(
            resolution: resolution, mouse: mouse, time: time, dt: dt,
            frameCount: frameCount, particleCount: 0, custom: .zero)
    }

    /// Record one vector primitive for SVG export, snapshotting the current style
    /// and CTM. Fill and stroke are passed explicitly (a line has no fill; a point
    /// has no stroke); an invisible stroke (no paint or zero width) is dropped.
    private func svgRecord(_ geometry: SVGGeometry, fill: Paint?, stroke: Paint?) {
        let visibleStroke = (stroke != nil && strokeWidth > 0) ? stroke : nil
        let style = SVGStyle(fill: fill, stroke: visibleStroke, strokeWidth: strokeWidth,
                             join: strokeJoinStyle, cap: strokeCapStyle)
        svgRecorder?.commands.append(RecordedSVG(geometry: geometry, style: style, transform: transform))
    }

    /// Shift origin-centered outline points into user space around `c`.
    private func svgOffset(_ points: [Vector2], _ c: Vector2) -> [Vector2] {
        points.map { $0 + c }
    }

    /// Current affine transform (2D homogeneous), applied to every emitted
    /// vertex. Reset to identity each frame.
    private var transform = matrix_identity_float3x3

    /// Tracks whether `transform` is still the identity, so `emit` can skip the
    /// per-vertex matrix multiply for the common case of a sketch that never
    /// translates/rotates/scales (the matmul runs hundreds of thousands of times
    /// a frame otherwise).
    private var transformIsIdentity = true

    /// The 3D model matrix — the spatial sibling of `transform`, for geometry that
    /// rides the `camera3D` rather than the 2D canvas (point clouds today). Built by
    /// the 3D `translate`/`rotate*`/`scale` overloads and reset to identity each
    /// frame. It composes *inside* the camera: a point reaches clip space as
    /// `projection · view · model · p`. Kept separate from the 2D affine so the 2D
    /// path stays byte-identical — a 2D-only sketch never touches it.
    private var modelMatrix = matrix_identity_float4x4

    /// Tracks whether `modelMatrix` is still the identity, so `drawPointCloud` can
    /// skip the per-point matrix multiply when no 3D transform is active (every
    /// existing 3D sketch, so their geometry stays byte-identical).
    private var modelIsIdentity = true

    /// Saved (transform + style) snapshots for `pushState()`/`popState()` / `withState`.
    private var stateStack: [SavedState] = []

    private struct SavedState {
        var transform: matrix_float3x3
        var transformIsIdentity: Bool
        var modelMatrix: matrix_float4x4
        var modelIsIdentity: Bool
        var fillPaint: Paint?
        var strokePaint: Paint?
        var strokeWidth: Double
        var pointDiameter: Double
        var marker: PointMarker
        var hollowWidth: Double
        var strokeAlignment: StrokeAlign
        var strokeJoinStyle: StrokeJoin
        var strokeCapStyle: StrokeCap
        var currentMaterial: Material
        var wireframeEnabled: Bool
        var currentMatcap: Image?
        var currentFont: ActiveFont
        var textPixelSize: Double
        var textAlignH: TextAlignH
        var textAlignV: TextAlignV
        var textRenderMode: TextMode
        var tintColor: Color?
        var currentBlend: BlendMode
        var currentDepth: Float?
    }

    // MARK: State setters (mirrors the bare API on `Sketch`)

    /// Set the background/clear color. This also wipes anything drawn
    /// so far this frame (background paints over everything). In accumulation mode
    /// (`noClear`) it additionally wipes the persistent canvas this frame — the
    /// way to reset a long exposure (see `backgroundSetThisFrame`).
    func background(_ color: Color) {
        // Inside a `withTarget` block, background clears *that target* (its clear
        // color + its geometry so far), leaving the main canvas and global clear
        // color untouched.
        if let frame = targetStack.last {
            frame.target.clearColor = color
            truncate(to: frame.snapshot)
            currentKind = nil
            currentBatchDepth = nil
            return
        }
        backgroundColor = color
        backgroundSetThisFrame = true
        vertices.removeAll(keepingCapacity: true)
        sdfInstances.removeAll(keepingCapacity: true)
        imageVertices.removeAll(keepingCapacity: true)
        glyphVertices.removeAll(keepingCapacity: true)
        points.removeAll(keepingCapacity: true)
        meshVertices.removeAll(keepingCapacity: true)
        sdfGroups.removeAll(keepingCapacity: true)
        sdfNodes.removeAll(keepingCapacity: true)
        sdf3DGroups.removeAll(keepingCapacity: true)
        sdf3DNodes.removeAll(keepingCapacity: true)
        batches.removeAll(keepingCapacity: true)
        currentKind = nil
        currentBatchDepth = nil
        hasDepthScene = false   // background wipes the recorded scene quad too
    }

    /// Stop clearing the canvas each frame: drawing accumulates on a persistent
    /// surface across frames (progressive refinement, long-exposure stills,
    /// paint-on-canvas). Pairs with `blendMode(.add)` for light-accumulation
    /// ("sandpainting") sketches. Call `background(_:)` to wipe the pile, or
    /// `clearEachFrame()` to return to the default.
    func noClear() { accumulates = true }

    /// Return to clearing the canvas every frame (the default).
    func clearEachFrame() { accumulates = false }

    /// Set how the linear-float frame maps to the 8-bit display. A mode like
    /// `accumulates` — it persists across frames (not reset in `beginFrame`).
    func toneMap(_ map: ToneMap, exposure: Double) {
        toneMapMode = map
        toneMapExposure = exposure
    }

    func fill(_ color: Color) { fillPaint = .color(color) }
    func fill(_ gradient: Gradient) { fillPaint = .gradient(gradient) }
    func fill(_ paint: Paint) { fillPaint = paint }
    func noFill() { fillPaint = nil }
    func stroke(_ color: Color) { strokePaint = .color(color) }
    func stroke(_ gradient: Gradient) { strokePaint = .gradient(gradient) }
    func stroke(_ paint: Paint) { strokePaint = paint }
    func noStroke() { strokePaint = nil }
    func strokeWeight(_ weight: Double) { strokeWidth = max(0, weight) }
    func pointSize(_ size: Double) { pointDiameter = max(0, size) }
    func pointMarker(_ marker: PointMarker) { self.marker = marker }

    /// Draw region shapes as a constant-width band hugging their outline instead
    /// of a solid interior: the `fill` color paints the band, and an active
    /// `stroke` borders both of its edges (the way `drawRing` can be stroked).
    /// `width` is the band thickness, centered on the shape's edge.
    func hollow(_ width: Double) { hollowWidth = max(0, width) }

    /// Return to solid fills (the default).
    func solid() { hollowWidth = 0 }

    /// Tint subsequent `drawImage` calls: every texel is multiplied by `color`,
    /// so its RGB recolors the image and its alpha fades it. The default (no tint)
    /// is the image unchanged.
    func tint(_ color: Color) { tintColor = color }

    /// Stop tinting images — back to drawing them unchanged (the default).
    func noTint() { tintColor = nil }

    /// Set how subsequent shapes combine with the canvas (see `BlendMode`):
    /// `.normal` (default, lay over) or a combining mode like `.add` (sum as
    /// light). Applies to every drawn primitive until changed.
    func blendMode(_ mode: BlendMode) { currentBlend = mode }

    /// Set where a shape's stroke sits relative to its outline (see `StrokeAlign`):
    /// `.center` (default), `.inside`, or `.outside`. Affects the analytic SDF
    /// shapes; lines, point markers, and the tessellated paths stay centered.
    func strokeAlign(_ align: StrokeAlign) { strokeAlignment = align }

    /// Set how a stroked path turns its corners (see `StrokeJoin`): `.miter`
    /// (default), `.bevel`, or `.round`. Affects the fringe stroked paths with
    /// interior corners (`drawPolyline`, the `drawPolygon` outline, `drawShape`
    /// contours, the flattened `drawBezier`).
    func strokeJoin(_ join: StrokeJoin) { strokeJoinStyle = join }

    /// Set how the open ends of a stroked path finish (see `StrokeCap`): `.butt`
    /// (default), `.round`, or `.square`. Affects the open fringe stroked paths
    /// (`drawLine`, `drawBezier`, `drawPolyline`, open `drawShape` contours);
    /// closed outlines have no ends.
    func strokeCap(_ cap: StrokeCap) { strokeCapStyle = cap }

    /// Set the active text font to a bitmap (pixel-grid) font. Defaults to
    /// `.builtin`.
    func textFont(_ font: BitmapFont) { currentFont = .bitmap(font) }

    /// Set the active text font to an outline (vector `.ttf`/`.otf`) font.
    func textFont(_ font: OutlineFont) { currentFont = .outline(font) }

    /// Set the active text font to a stroke (single-line / plotter) font.
    func textFont(_ font: StrokeFont) { currentFont = .stroke(font) }

    /// Set the rendered text height in points — the height one line of glyphs
    /// occupies on screen (`drawText`). Defaults to 24.
    func textSize(_ size: Double) { textPixelSize = max(0, size) }

    /// Set the text anchor relative to the `drawText` position (see `TextAlignH` /
    /// `TextAlignV`): horizontal `.left`/`.center`/`.right`, vertical
    /// `.top`/`.middle`/`.baseline`/`.bottom`.
    func textAlign(_ horizontal: TextAlignH, _ vertical: TextAlignV = .baseline) {
        textAlignH = horizontal
        textAlignV = vertical
    }

    /// Set how outline text is rendered (see `TextMode`): `.outline` (default,
    /// per-glyph vector fill) or `.atlas` (the SDF-atlas scale path). A no-op for
    /// bitmap and stroke fonts.
    func textMode(_ mode: TextMode) { textRenderMode = mode }

    // MARK: 3D camera & point clouds

    /// Set the active 3D camera for this frame (see `Camera3D`); drawing a point
    /// cloud needs one. The camera is per-frame state and resets to none each
    /// frame, so set it from `draw()` (3D sketches typically animate it). Setting
    /// it is what puts the frame into 3D — the renderer allocates a depth buffer
    /// and draws 3D geometry through it. A 2D-only frame never calls this.
    func camera(_ camera: Camera3D) { camera3D = camera }

    /// A perspective 3D camera looking from `eye` at `target` (sugar over `camera`).
    func perspective(eye: Vector3, target: Vector3 = .zero, up: Vector3 = .unitY,
                     fieldOfView: Double = .pi / 3, near: Double = 0.1, far: Double = 1000) {
        camera3D = .perspective(eye: eye, target: target, up: up,
                                fieldOfView: fieldOfView, near: near, far: far)
    }

    /// An orthographic 3D camera looking from `eye` at `target`, framing `height`
    /// world units top-to-bottom (sugar over `camera`).
    func ortho(eye: Vector3, target: Vector3 = .zero, up: Vector3 = .unitY,
               height: Double, near: Double = 0.1, far: Double = 1000) {
        camera3D = .orthographic(eye: eye, target: target, up: up,
                                 height: height, near: near, far: far)
    }

    /// Add a light to this frame's 3D scene (see `Light`). Per-frame, like the
    /// camera; meshes drawn after it shade through the material model. Taking control
    /// of the lights this way replaces the default rig.
    func addLight(_ light: Light) { lights.append(light); lightingMode = .custom }

    /// Set the ambient (flat fill) light for this frame's 3D scene. Setting it
    /// replaces the default rig (an ambient alone is a flat, unshaded fill).
    func ambientLight(_ color: Color) { ambientLightColor = color; lightingMode = .custom }

    func environment(_ env: Environment) { environment = env }
    func noEnvironment() { environment = nil }

    /// Turn off lighting for this frame: meshes draw flat in their `fill` color
    /// (unlit), overriding the auto-lit default.
    func noLights() {
        lights.removeAll(keepingCapacity: true)
        ambientLightColor = nil
        lightingMode = .off
    }

    /// Set the material's specular highlight strength (`0` matte; `~0.5` glossy).
    /// Drawing state, saved by `withState`; bound per mesh batch as they're drawn.
    func specular(_ strength: Double) { currentMaterial.specular = max(0, strength) }

    /// Set the material's Blinn-Phong shininess exponent (higher = tighter, sharper
    /// highlight). Drawing state, saved by `withState`.
    func shininess(_ exponent: Double) { currentMaterial.shininess = max(1, exponent) }

    /// Apply a whole `Material` finish at once — its shading model and every finish
    /// (specular, rim, subsurface, iridescence). The surface color stays the current
    /// `fill`. Drawing state, saved by `withState`; bound per mesh batch.
    func material(_ m: Material) { currentMaterial = m }

    /// Draw subsequent meshes as their triangle edges (a wireframe net) rather than
    /// filled surfaces. The edges take the current `stroke` color (or `fill` if no
    /// stroke) and `strokeWeight`; the faces are see-through, so it doesn't light.
    /// Drawing state, saved by `withState`.
    func wireframe(_ on: Bool) { wireframeEnabled = on }

    /// Wrap subsequent meshes in a *matcap* — a sphere texture (`Matcap.chrome`, a
    /// `Matcap.shaded(…)`, or any matcap `Image`) sampled by the view-space normal, so
    /// the whole look (lighting included) comes from the image and the scene lights and
    /// `material(_:)` are bypassed. The surface is tinted by the current `fill`
    /// (`.white` shows the matcap as-is). `noMatcap()` (or `matcap(nil)`) returns to the
    /// lit material path. Drawing state, saved by `withState`.
    func matcap(_ image: Image?) { currentMatcap = image }

    /// Wrap subsequent meshes in a built-in or generated `Matcap` (`.chrome`,
    /// `Matcap.shaded(…)`, …).
    func matcap(_ matcap: Matcap) { currentMatcap = matcap.image }

    /// Stop matcap shading — subsequent meshes light through the normal material model.
    func noMatcap() { currentMatcap = nil }

    /// Cast shadows from the scene's primary directional light this frame. Per-frame
    /// state like the lights — set it in `draw()`. The renderer renders a depth pass
    /// from that light and dims the light on meshes it can't reach. A no-op without a
    /// camera or a directional light. (`noShadows()` turns it back off.)
    func castShadows() { castsShadows = true }

    /// Stop casting shadows (the default). Per-frame state.
    func noShadows() { castsShadows = false }

    /// Ray-trace reflections of the scene off its physically-based surfaces this frame.
    /// Per-frame state like the lights; set it in `draw()`. Every solid mesh reflects (the
    /// renderer reuses the shadow-caster acceleration structure, which already covers them all);
    /// a no-op without a ray-tracing device or an environment to fall back to on a miss.
    func rayTracedReflections(_ enabled: Bool = true) { rayTracedReflectionsEnabled = enabled }

    /// Set the soft-shadow quality to a hardware-relative tier (the renderer picks the ray
    /// count for the GPU). Persistent (set once, in `setup()` or `draw()`).
    func shadowQuality(_ quality: RenderQuality) { shadowQualitySetting = .tier(quality) }

    /// Set the soft-shadow ray count to an exact value, clamped to 1…64 (hardware-independent).
    /// Persistent.
    func shadowSamples(_ count: Int) { shadowQualitySetting = .absolute(max(1, min(count, 64))) }

    /// Set the raymarched-SDF (`drawSDF3D`) quality to a `RenderQuality` tier (the renderer
    /// resolves a march-step budget + internal render scale). Persistent.
    func raymarchQuality(_ quality: RenderQuality) { raymarchQualitySetting = .tier(quality) }

    /// Set the raymarched-SDF camera-march step count to an exact value, clamped to 16…512
    /// (full resolution). Persistent.
    func raymarchSteps(_ count: Int) { raymarchQualitySetting = .absolute(max(16, min(count, 512))) }

    /// Set the raymarched-SDF live-preview resolution to an exact fraction (0.1…1.0), the
    /// custom alternative to the `raymarchQuality` tiers' 1.0/0.5/0.25. Persistent.
    func raymarchResolution(_ fraction: Double) { raymarchQualitySetting = .resolution(min(1.0, max(0.1, fraction))) }

    /// Pack this frame's effective lighting into the GPU uniform. The mode decides
    /// the source: `.off` shades nothing (flat unlit, `enabled == 0`), `.auto` uses
    /// the default rig (the out-of-box shaded look), `.custom` uses the sketch's own
    /// lights and ambient.
    func makeLighting() -> OllinLighting {
        var u = OllinLighting()
        u.shadowLight = -1   // no shadows unless a caster is found below
        if let eye = camera3D?.eye {
            u.cameraPosition = SIMD4<Float>(Float(eye.x), Float(eye.y), Float(eye.z), 0)
        }
        let ambient: Color
        let activeLights: [Light]
        switch lightingMode {
        case .off:
            u.enabled = 0
            return u   // flat, unlit; lights/ambient/shadows unused
        case .auto:
            if environment != nil {
                // An environment lights the scene through IBL, so it stands in for the
                // auto rig: no default lights, no flat ambient (the irradiance map is the
                // ambient). A sketch that wants both adds its own lights (→ `.custom`).
                ambient = .black
                activeLights = []
            } else {
                ambient = Drawer.defaultAmbient
                activeLights = Drawer.defaultLights
            }
        case .custom:
            ambient = ambientLightColor ?? .black
            activeLights = lights
        }
        u.enabled = 1
        // Ray-traced reflections' self-hit ray-origin offset, sized to the scene (the
        // eye→target distance, the scene-scale proxy the shadow framing also uses). The
        // renderer sets `rtReflections` itself (it owns the hardware check); this is inert
        // until then, so it's harmless to always pack.
        if let camera = camera3D {
            let radius = max(Float(simd_distance(camera.eye.simd3, camera.target.simd3)), 1)
            u.rtReflectionBias = radius * 0.0015
        }
        u.ambient = SIMD4<Float>(Float(Color.srgbToLinear(ambient.red)),
                                 Float(Color.srgbToLinear(ambient.green)),
                                 Float(Color.srgbToLinear(ambient.blue)), 0)
        let count = min(activeLights.count, Int(OLLIN_MAX_LIGHTS))
        u.lightCount = Int32(count)
        // A C fixed-size array imports as a homogeneous tuple; fill it through a
        // typed pointer rather than naming each element.
        withUnsafeMutablePointer(to: &u.lights) { tuplePtr in
            tuplePtr.withMemoryRebound(to: OllinLight.self, capacity: Int(OLLIN_MAX_LIGHTS)) { buf in
                for i in 0..<count { buf[i] = Drawer.packLight(activeLights[i]) }
            }
        }
        // Shadow caster: the first directional light, or, when the scene has no
        // directional, the first spot light. Both render into the same 2D shadow map
        // and are sampled by the same `shadowFactor` (which already does the
        // perspective divide), so the only difference is the projection: a directional
        // caster is an orthographic box auto-fit around the camera target, a spot
        // caster is a perspective frustum from the light's position along its cone.
        if castsShadows, let camera = camera3D {
            let target = camera.target.simd3
            // The eye→target distance (the orbit radius) is the scene-size proxy that
            // frames the box / fits the frustum, matching what the camera frames.
            let r = max(Float(simd_distance(camera.eye.simd3, target)), 1)
            if let caster = (0..<count).first(where: { activeLights[$0].kind == .directional }) {
                // Directional: look from above the target along the light's travel
                // direction, an orthographic box sized to the scene.
                let dirToLight = simd_normalize((activeLights[caster].direction * -1).normalized.simd3)
                let d = 2 * r
                let eye = target + dirToLight * d
                // Pick an up vector not parallel to the light direction.
                let up: SIMD3<Float> = abs(dirToLight.y) > 0.99 ? SIMD3<Float>(0, 0, 1) : SIMD3<Float>(0, 1, 0)
                let view = Camera3D.lookAt(eye: eye, center: target, up: up)
                let proj = Camera3D.orthographic(height: 2 * r, aspect: 1,
                                                 near: max(0.01, d - 1.5 * r), far: d + 1.5 * r)
                u.lightViewProjection = proj * view
                u.shadowLight = Int32(caster)
                u.shadowStrength = 1
                u.shadowTexelWorld = (2 * r) / Float(Drawer.shadowMapResolution)
            } else if let caster = (0..<count).first(where: { activeLights[$0].kind == .spot }) {
                // Spot: a perspective frustum from the light's position, aimed down its
                // cone axis, the vertical field of view set to the full cone angle (a
                // small margin so the soft penumbra edge isn't clipped).
                let light = activeLights[caster]
                let eye = light.position.simd3
                let axis = simd_normalize(light.direction.normalized.simd3)
                let dist = max(simd_distance(eye, target), 1)
                let center = eye + axis * dist
                let up: SIMD3<Float> = abs(axis.y) > 0.99 ? SIMD3<Float>(0, 0, 1) : SIMD3<Float>(0, 1, 0)
                let view = Camera3D.lookAt(eye: eye, center: center, up: up)
                let fovY = Float(min(light.coneAngle * 1.05, Double.pi - 0.05))
                let proj = Camera3D.perspective(fovY: fovY, aspect: 1,
                                                near: max(0.1, dist - 1.5 * r), far: dist + 1.5 * r)
                u.lightViewProjection = proj * view
                u.shadowLight = Int32(caster)
                u.shadowStrength = 1
                // A perspective texel grows with depth; size the normal-offset bias from
                // the frustum at the scene center (where the receivers mostly sit).
                u.shadowTexelWorld = (2 * tan(fovY * 0.5) * dist) / Float(Drawer.shadowMapResolution)
            } else if let caster = (0..<count).first(where: { activeLights[$0].kind == .point }) {
                // Point: an omnidirectional caster. The renderer renders the scene into a
                // six-face cube from the light, each face storing the nearest occluder's
                // *linear distance to the light* normalized by the far plane. So all we
                // carry is that far plane (to denormalize the sampled distance) — the
                // light position comes from the light entry. The far plane reaches past
                // the scene from the light.
                let light = activeLights[caster]
                let dist = max(Float(simd_distance(light.position.simd3, target)), 1)
                u.shadowLight = Int32(caster)
                u.shadowKind = 1
                u.shadowStrength = 1
                u.shadowDepthA = dist + 1.5 * r      // far plane (linear-distance normalizer)
                // A 90° cube face spans 2·d wide at distance d, so a texel there is
                // 2·dist/resolution, the world-space unit for the bias and PCF spread.
                u.shadowTexelWorld = (2 * dist) / Float(Drawer.pointShadowMapResolution)
                // On a ray-tracing device the renderer traces this caster instead of
                // sampling the cube (it bumps `shadowKind` to 2); `shadowDepthB` then
                // carries the area-light radius that softens the traced shadow into a
                // contact-hardening penumbra (light-relative, so it's camera-independent).
                // The cube path ignores it, so it's harmless to always pack.
                u.shadowDepthB = dist * 0.03
                // `shadowSamples` (rays/pixel) is resolved by the renderer from the GPU's
                // capability + the sketch's quality tier; left 0 here (it has no device).
            }
        }
        return u
    }

    /// Convert a `Light` into its GPU form: linearized intensity-scaled color, the
    /// vectors a directional/point/spot light needs, and a spot's cone cosines.
    private static func packLight(_ light: Light) -> OllinLight {
        var l = OllinLight()
        let i = light.intensity
        l.color = SIMD4<Float>(Float(Color.srgbToLinear(light.color.red) * i),
                               Float(Color.srgbToLinear(light.color.green) * i),
                               Float(Color.srgbToLinear(light.color.blue) * i), 0)
        // Specular tint: defaults to the diffuse color, so a single-color light shades
        // byte-identically; a distinct `specular` gives a separately-tinted highlight.
        let s = light.specular ?? light.color
        l.specular = SIMD4<Float>(Float(Color.srgbToLinear(s.red) * i),
                                  Float(Color.srgbToLinear(s.green) * i),
                                  Float(Color.srgbToLinear(s.blue) * i), 0)
        l.softness = Float(light.softness)   // 0 = hard Lambert (unchanged)
        switch light.kind {
        case .directional:
            l.kind = 0
            // Store the unit direction *to* the light (the negated travel direction).
            let d = (light.direction * -1).normalized
            l.direction = SIMD4<Float>(Float(d.x), Float(d.y), Float(d.z), 0)
        case .point:
            l.kind = 1
            l.position = SIMD4<Float>(Float(light.position.x), Float(light.position.y),
                                      Float(light.position.z), 0)
        case .spot:
            l.kind = 2
            l.position = SIMD4<Float>(Float(light.position.x), Float(light.position.y),
                                      Float(light.position.z), 0)
            // The cone axis is the light's travel direction (source → lit surface).
            let axis = light.direction.normalized
            l.direction = SIMD4<Float>(Float(axis.x), Float(axis.y), Float(axis.z), 0)
            let half = max(0, light.coneAngle / 2)
            l.cosOuter = Float(cos(half))
            // Penumbra narrows the full-bright inner cone toward the center.
            let inner = half * (1 - max(0, min(1, light.penumbra)))
            l.cosInner = Float(cos(inner))
        }
        return l
    }

    /// Record a 3D point cloud, drawn as camera-facing disc splats through the
    /// active camera. World-space points (they ride the camera, not the 2D
    /// transform stack). A no-op without a camera or when the cloud is empty.
    func drawPointCloud(_ cloud: PointCloud) {
        guard camera3D != nil, !cloud.isEmpty else { return }
        // SVG export is 2D vector only; a splat cloud has no vector outline.
        if svgRecorder != nil { return }
        currentTarget?.needsDepth = true   // 3D in a target → that pass carries depth
        ensureBatch(.points3D)
        points.reserveCapacity(points.count + cloud.count)
        // The model matrix bakes into each point CPU-side (the 2D affine bakes the
        // same way into triangle vertices), so the splat shader stays untouched. When
        // no 3D transform is active this is the original world-space copy, byte for
        // byte. Splat sizes are world units, so a scaling transform grows them too.
        let m = modelMatrix
        let sizeScale = modelIsIdentity ? 1 : Drawer.averageScale(m)
        for p in cloud.points {
            var op = OllinPoint()
            if modelIsIdentity {
                op.position = SIMD4<Float>(Float(p.position.x), Float(p.position.y), Float(p.position.z), 1)
            } else {
                let w = m * SIMD4<Float>(Float(p.position.x), Float(p.position.y), Float(p.position.z), 1)
                op.position = SIMD4<Float>(w.x, w.y, w.z, 1)
            }
            op.color = p.color.simd4
            op.size = Float(p.size) * sizeScale
            points.append(op)
        }
    }

    /// Record a solid 3D mesh, drawn through the active camera with depth testing.
    /// World-aware geometry (it rides the camera and the 3D transform stack, not the
    /// 2D affine): the model matrix bakes into each position and its normal matrix
    /// into each normal CPU-side, so the shader only applies the camera. Triangle
    /// indices are expanded into the flat per-frame `meshVertices` list. The surface
    /// takes the current `fill` color: flat (unlit) with no lights set, Blinn-Phong
    /// shaded once a light is added. A no-op without a camera or when the mesh is empty.
    func drawMesh(_ mesh: Mesh) {
        guard camera3D != nil, !mesh.isEmpty else { return }
        // Inside a combine block, only the SDF-able primitives (which route through
        // `drawMeshPrimitive` and never reach here) merge; any other mesh is ignored.
        if !combineStack.isEmpty {
            if !warnedMeshInCombine {
                print("Ollin: a mesh inside a combine block is ignored unless it's an SDF-able primitive (drawSphere/drawBox/drawRoundedBox/drawCylinder/drawCone/drawTorus/drawCapsule/drawOctahedron); a 3D combine merges those analytic fields.")
                warnedMeshInCombine = true
            }
            return
        }
        // SVG export is 2D vector only; a shaded solid has no vector outline.
        if svgRecorder != nil { return }
        currentTarget?.needsDepth = true   // 3D in a target → that pass carries depth
        // Wireframe draws the triangle edges only (the faces are see-through), so it
        // ignores the texture and lighting; otherwise a texture maps when matching UVs
        // are present, else a flat base-color surface. Wireframe and textured meshes
        // each open their own batch (own pipeline / bound texture); a solid mesh merges.
        let material = mesh.material
        let wireframe = wireframeEnabled
        let matcap = !wireframe ? currentMatcap : nil
        let textured = !wireframe && matcap == nil && material?.texture != nil
            && mesh.uvs.count == mesh.positions.count
        if wireframe {
            beginMeshBatch(material: nil, finish: OllinMaterial(), wireframe: true)
        } else if let matcap {
            beginMeshBatch(material: nil, finish: OllinMaterial(), matcap: matcap)
        } else if textured {
            beginMeshBatch(material: material, finish: currentMaterial.gpuMaterial())
        } else {
            ensureSolidMeshBatch(currentMaterial)
        }
        let m = modelMatrix
        let nm = modelIsIdentity ? matrix_identity_float3x3 : m.normalMatrix
        // The vertex color: for a wireframe, the edge (stroke) color; otherwise the
        // current fill tinted by the material's base color (white = the fill unchanged,
        // so a material-less mesh's color is exactly the fill, and a base-color-only
        // material just tints — the textured fragment multiplies its sample by this).
        // For a wireframe, the edge (stroke) color; for a matcap, the fill alone (the
        // matcap carries the surface color, so its mesh's base-color material is ignored);
        // otherwise the fill tinted by the material's base color.
        let color: SIMD4<Float>
        if wireframe {
            color = meshStrokeColor.simd4
        } else if matcap != nil {
            color = meshSurfaceColor.simd4
        } else {
            color = meshSurfaceColor.simd4 * (material?.baseColor.simd4 ?? SIMD4<Float>(1, 1, 1, 1))
        }
        // The material finish is bound per batch as an `OllinMaterial` uniform, with two
        // exceptions baked into the otherwise-spare vertex `w` slots: the wireframe line width
        // (position.w, 0 for a lit mesh) and, for a physically-based lit mesh, its metalness
        // (normal.w) + roughness (position.w). A ray-traced reflection hit reads those to shade
        // the surface as the metal it is (its tinted environment reflection) instead of a flat
        // diffuse blob. The lit vertex shaders read only the xyz, so this is inert for the
        // primary render; non-PBR / wireframe bake metalness 0 (a reflection treats them as
        // diffuse).
        let pbr = !wireframe && currentMaterial.shading == .physicallyBased
        let metalW: Float = pbr ? Float(currentMaterial.metallic) : 0
        let posW: Float = wireframe ? Float(strokeWidth) : (pbr ? Float(currentMaterial.roughness) : 1)
        meshVertices.reserveCapacity(meshVertices.count + mesh.indices.count)
        for idx in mesh.indices {
            let i = Int(idx)
            guard i < mesh.positions.count else { continue }
            let p = mesh.positions[i]
            let n = i < mesh.normals.count ? mesh.normals[i] : Vector3.unitZ
            var v = OllinMeshVertex()
            if modelIsIdentity {
                v.position = SIMD4<Float>(Float(p.x), Float(p.y), Float(p.z), posW)
                let nn = n.normalized
                v.normal = SIMD4<Float>(Float(nn.x), Float(nn.y), Float(nn.z), metalW)
            } else {
                let wp = m * SIMD4<Float>(Float(p.x), Float(p.y), Float(p.z), 1)
                v.position = SIMD4<Float>(wp.x, wp.y, wp.z, posW)
                let wn = simd_normalize(nm * SIMD3<Float>(Float(n.x), Float(n.y), Float(n.z)))
                v.normal = SIMD4<Float>(wn.x, wn.y, wn.z, metalW)
            }
            v.color = color
            if textured {
                let uv = mesh.uvs[i]
                v.uv = SIMD2<Float>(Float(uv.x), Float(uv.y))
            }
            meshVertices.append(v)
        }
    }

    /// The base color baked into a mesh's vertices: the current solid `fill`, or
    /// white for a gradient/`noFill` (mesh surfaces take a solid color — gradient
    /// paint isn't supported on the 3D path). It's the surface color, flat without
    /// lights and the diffuse color when lit.
    private var meshSurfaceColor: Color {
        switch fillPaint {
        case .color(let c): return c
        case .gradient, .none: return .white
        }
    }

    /// The edge color for a wireframe mesh: the current solid `stroke`, falling back to
    /// the fill color when there's no stroke (so the net is always visible).
    private var meshStrokeColor: Color {
        switch strokePaint {
        case .color(let c): return c
        case .gradient, .none: return meshSurfaceColor
        }
    }

    /// Place subsequent 2D drawing at the depth of a world point in the active 3D
    /// scene, so it z-tests against 3D geometry — hidden where the scene is nearer,
    /// hiding the scene where it's in front. The world point's clip-space z (against
    /// this frame's camera) is what the 2D vertex shaders emit. A no-op without a
    /// camera (the depth resets to "draw over"). Camera-derived, so it resets each
    /// frame with the camera; saved by `withState`.
    func depth(at worldPoint: Vector3) {
        guard let camera = camera3D else { currentDepth = nil; return }
        // The point is in the current model space (like the geometry it accompanies),
        // so push it through the model matrix first — identity today, so unchanged.
        let p = modelIsIdentity ? worldPoint : modelMatrix.transforming(worldPoint)
        // Clip-space z is independent of the viewport aspect (the projection's z and
        // w rows don't touch x/y), so any aspect gives the right NDC depth.
        let clip = camera.projectionMatrix(aspect: 1) * camera.viewMatrix * SIMD4<Float>(p.simd3, 1)
        currentDepth = clip.w != 0 ? clip.z / clip.w : nil
    }

    /// Return subsequent 2D drawing to drawing *over* the 3D scene (the default):
    /// it ignores the depth buffer and composites in draw order.
    func noDepth() { currentDepth = nil }

    /// Place subsequent 2D drawing at a normalized scene depth `t` (0 = nearest, 1
    /// = farthest), the companion to `depth(at:)` for a depth-map scene
    /// (`drawDepthScene`) that has no 3D camera. The value is the clip-space depth
    /// directly, so it tests against the depth the scene wrote from its map: a mark
    /// at `t` is hidden where the scene is nearer (smaller depth) and drawn over
    /// where it's farther. Clamped to 0…1; saved by `withState`.
    func depth(_ t: Double) { currentDepth = Float(min(max(t, 0), 1)) }

    /// Project a world point through the active camera to its canvas-space position
    /// (top-left origin, points), or `nil` if there's no camera or the point is
    /// behind it. `viewport` is the canvas size (the `Sketch` passes `width`/`height`).
    func project(_ worldPoint: Vector3, viewport: SIMD2<Float>) -> Vector2? {
        guard let camera = camera3D else { return nil }
        let p = modelIsIdentity ? worldPoint : modelMatrix.transforming(worldPoint)
        let aspect = viewport.y > 0 ? Double(viewport.x / viewport.y) : 1
        let clip = camera.viewProjectionMatrix(aspect: aspect) * SIMD4<Float>(p.simd3, 1)
        // clip.w = −z_camera: positive only for points in front of the camera.
        guard clip.w > 0 else { return nil }
        let ndx = clip.x / clip.w, ndy = clip.y / clip.w
        return Vector2((Double(ndx) + 1) / 2 * Double(viewport.x),
                       (1 - Double(ndy)) / 2 * Double(viewport.y))
    }

    // MARK: Frame lifecycle

    /// Drop last frame's geometry but keep drawing state. Called once per frame
    /// by the runner before `Sketch.draw()`.
    func beginFrame() {
        vertices.removeAll(keepingCapacity: true)
        sdfInstances.removeAll(keepingCapacity: true)
        imageVertices.removeAll(keepingCapacity: true)
        glyphVertices.removeAll(keepingCapacity: true)
        points.removeAll(keepingCapacity: true)
        meshVertices.removeAll(keepingCapacity: true)
        sdfGroups.removeAll(keepingCapacity: true)
        sdfNodes.removeAll(keepingCapacity: true)
        sdf3DGroups.removeAll(keepingCapacity: true)
        sdf3DNodes.removeAll(keepingCapacity: true)
        combineStack.removeAll(keepingCapacity: true)   // close any block left open by an early exit
        combineGroupTransform = nil
        combineGroupModel = nil
        warnedMeshInCombine = false
        batches.removeAll(keepingCapacity: true)
        dispatches.removeAll(keepingCapacity: true)
        currentKind = nil
        camera3D = nil
        // Lights are per-frame like the camera (set in `draw()` each frame). They
        // reset here but *not* in `background()`, which only wipes geometry mid-frame
        // while the camera/lights stay — matching the camera's lifetime.
        lights.removeAll(keepingCapacity: true)
        ambientLightColor = nil
        lightingMode = .auto
        environment = nil
        castsShadows = false
        rayTracedReflectionsEnabled = false
        hasDepthScene = false
        // The 2D depth is camera-derived (a clip-z against this frame's camera), so
        // it resets with the camera each frame — set it from `draw()` after the
        // camera, like the camera itself.
        currentDepth = nil
        // `accumulates` is a mode and persists; only the per-frame "did the sketch
        // wipe the pile this frame" flag resets here.
        backgroundSetThisFrame = false
        // The row table is per-frame like the geometry (a row index is only
        // meaningful against this frame's strip); the bake cache persists.
        gradientRows.removeAll(keepingCapacity: true)
        gradientRowIndex.removeAll(keepingCapacity: true)
        // Effects layers are per-frame: targets are created inside draw() and their
        // recorded geometry/filters reset here with everything else.
        targetStack.removeAll(keepingCapacity: true)
        renderTargets.removeAll(keepingCapacity: true)
        filterOps.removeAll(keepingCapacity: true)
        frameFilters.removeAll(keepingCapacity: true)
        transform = matrix_identity_float3x3
        transformIsIdentity = true
        modelMatrix = matrix_identity_float4x4
        modelIsIdentity = true
        stateStack.removeAll(keepingCapacity: true)
    }

    // MARK: Transforms & state stack

    /// Shift the origin by `offset` (points). Composes with the current
    /// transform; reset each frame.
    func translate(_ offset: Vector2) {
        transform = transform * Drawer.translation(Float(offset.x), Float(offset.y))
        transformIsIdentity = false
    }

    /// Rotate subsequent drawing by `radians` (clockwise, in Ollin's y-down space).
    func rotate(_ radians: Double) {
        transform = transform * Drawer.rotation(Float(radians))
        transformIsIdentity = false
    }

    /// Scale subsequent drawing by `(sx, sy)`.
    func scale(_ sx: Double, _ sy: Double) {
        transform = transform * Drawer.scaling(Float(sx), Float(sy))
        transformIsIdentity = false
    }

    // MARK: 3D transforms (the model matrix)
    //
    // The spatial siblings of the 2D `translate`/`rotate`/`scale` above: these build
    // the `modelMatrix` and move 3D geometry (point clouds) inside the active camera,
    // not the 2D canvas. World space is right-handed, y-up (the `Camera3D`
    // convention); rotations are right-handed (counter-clockwise looking from the
    // positive axis toward the origin). They compose by post-multiplication like the
    // 2D affine, so `translate` then `rotateY` then draw places a point at
    // `T · R · p`. A 2D-only sketch never calls these.

    /// Move subsequent 3D geometry by `offset` in world units.
    func translate(_ offset: Vector3) {
        modelMatrix = modelMatrix * Drawer.translation3(offset.simd3)
        modelIsIdentity = false
    }

    /// Move subsequent 3D geometry by `(x, y, z)` in world units.
    func translate(_ x: Double, _ y: Double, _ z: Double) {
        translate(Vector3(x, y, z))
    }

    /// Rotate subsequent 3D geometry by `radians` about the world x-axis.
    func rotateX(_ radians: Double) {
        modelMatrix = modelMatrix * Drawer.rotationX(Float(radians))
        modelIsIdentity = false
    }

    /// Rotate subsequent 3D geometry by `radians` about the world y-axis.
    func rotateY(_ radians: Double) {
        modelMatrix = modelMatrix * Drawer.rotationY(Float(radians))
        modelIsIdentity = false
    }

    /// Rotate subsequent 3D geometry by `radians` about the world z-axis.
    func rotateZ(_ radians: Double) {
        modelMatrix = modelMatrix * Drawer.rotationZ(Float(radians))
        modelIsIdentity = false
    }

    /// Rotate subsequent 3D geometry by `radians` about an arbitrary `axis`
    /// (need not be unit length). A no-op for a zero-length axis.
    func rotate(_ radians: Double, axis: Vector3) {
        let a = axis.normalized
        guard a.lengthSquared > 0 else { return }
        modelMatrix = modelMatrix * Drawer.rotation3(Float(radians), axis: a.simd3)
        modelIsIdentity = false
    }

    /// Scale subsequent 3D geometry by `(x, y, z)` per axis.
    func scale(_ x: Double, _ y: Double, _ z: Double) {
        modelMatrix = modelMatrix * Drawer.scaling3(Float(x), Float(y), Float(z))
        modelIsIdentity = false
    }

    /// Scale subsequent 3D geometry by per-axis `factors`. Uniform scale is
    /// `scale(Vector3(s, s, s))`.
    func scale(_ factors: Vector3) {
        scale(factors.x, factors.y, factors.z)
    }

    /// Save the current transform and style (fill/stroke/weight).
    func pushState() {
        stateStack.append(SavedState(transform: transform, transformIsIdentity: transformIsIdentity,
                                     modelMatrix: modelMatrix, modelIsIdentity: modelIsIdentity,
                                     fillPaint: fillPaint, strokePaint: strokePaint,
                                     strokeWidth: strokeWidth, pointDiameter: pointDiameter,
                                     marker: marker, hollowWidth: hollowWidth,
                                     strokeAlignment: strokeAlignment,
                                     strokeJoinStyle: strokeJoinStyle,
                                     strokeCapStyle: strokeCapStyle,
                                     currentMaterial: currentMaterial,
                                     wireframeEnabled: wireframeEnabled,
                                     currentMatcap: currentMatcap,
                                     currentFont: currentFont, textPixelSize: textPixelSize,
                                     textAlignH: textAlignH, textAlignV: textAlignV,
                                     textRenderMode: textRenderMode,
                                     tintColor: tintColor,
                                     currentBlend: currentBlend,
                                     currentDepth: currentDepth))
    }

    /// Restore the most recently pushed transform and style. No-op if unbalanced.
    func popState() {
        guard let s = stateStack.popLast() else { return }
        transform = s.transform
        transformIsIdentity = s.transformIsIdentity
        modelMatrix = s.modelMatrix
        modelIsIdentity = s.modelIsIdentity
        fillPaint = s.fillPaint
        strokePaint = s.strokePaint
        strokeWidth = s.strokeWidth
        pointDiameter = s.pointDiameter
        marker = s.marker
        hollowWidth = s.hollowWidth
        strokeAlignment = s.strokeAlignment
        strokeJoinStyle = s.strokeJoinStyle
        strokeCapStyle = s.strokeCapStyle
        currentMaterial = s.currentMaterial
        wireframeEnabled = s.wireframeEnabled
        currentMatcap = s.currentMatcap
        currentFont = s.currentFont
        textPixelSize = s.textPixelSize
        textAlignH = s.textAlignH
        textAlignV = s.textAlignV
        textRenderMode = s.textRenderMode
        tintColor = s.tintColor
        currentBlend = s.currentBlend
        currentDepth = s.currentDepth
    }

    // MARK: Primitives

    /// A circle centered at `(x, y)` with the given `radius` (points).
    ///
    /// Recorded as a single SDF instance, not tessellated: the fragment shader
    /// computes fill, stroke (width `strokeWeight`), and anti-aliasing
    /// analytically. Crisp at any size and effectively free per circle, which is
    /// what makes thousands of them cheap.
    func drawCircle(_ x: Double, _ y: Double, _ radius: Double) {
        guard radius > 0 else { return }
        if svgRecorder != nil {
            svgRecord(.ellipse(center: Vector2(x, y), rx: radius, ry: radius), fill: fillPaint, stroke: strokePaint)
            return
        }
        appendSDF(shape: .ellipse, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(radius), Float(radius)),
                  fill: fillPaint, stroke: strokePaint)
    }

    /// The same circle, given as a `Circle` value.
    func drawCircle(_ c: Circle) { drawCircle(c.center.x, c.center.y, c.radius) }

    /// An axis-aligned ellipse centered at `(x, y)` with horizontal radius `rx`
    /// and vertical radius `ry` (points). Like `drawCircle`, the arguments are
    /// *radii*, not diameters — `drawEllipse(x, y, r, r)` is a circle.
    ///
    /// Recorded as a single SDF instance (see `drawCircle`); fill and a
    /// uniform-width stroke are derived analytically in the fragment shader.
    func drawEllipse(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) {
        guard rx > 0, ry > 0 else { return }
        if svgRecorder != nil {
            svgRecord(.ellipse(center: Vector2(x, y), rx: rx, ry: ry), fill: fillPaint, stroke: strokePaint)
            return
        }
        appendSDF(shape: .ellipse, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(rx), Float(ry)),
                  fill: fillPaint, stroke: strokePaint)
    }

    /// A filled marker at `(x, y)`. `size` is the on-screen *diameter* (points); the
    /// no-`size` form uses the current `pointSize`. The glyph is the current
    /// `pointMarker` (a round dot by default). A point takes the current `fill`
    /// color (not stroke) and ignores `strokeWeight`, so `noFill()` draws nothing.
    /// Recorded as one SDF instance, so it's crisp and effectively free per point.
    /// The round `.circle` marker also stays smooth down to sub-pixel sizes, fading
    /// by area instead of popping or snapping to 1px.
    func drawPoint(_ x: Double, _ y: Double, _ size: Double) {
        guard size > 0, let fill = fillPaint else { return }
        if svgRecorder != nil {
            let r = size / 2, c = Vector2(x, y), arm = (size / 2) * 0.28
            switch marker {
            case .circle:  svgRecord(.ellipse(center: c, rx: r, ry: r), fill: fill, stroke: nil)
            case .square:  svgRecord(.polygon(svgOffset(SDFOutline.markerSquare(r), c)), fill: fill, stroke: nil)
            case .diamond: svgRecord(.polygon(svgOffset(SDFOutline.markerDiamond(r), c)), fill: fill, stroke: nil)
            case .cross:   svgRecord(.polygon(svgOffset(SDFOutline.markerCross(r, arm), c)), fill: fill, stroke: nil)
            case .x:       svgRecord(.polygon(svgOffset(SDFOutline.markerX(r, arm), c)), fill: fill, stroke: nil)
            }
            return
        }
        let h = Float(size / 2)
        // Marker kind code, as the fragment reads it from `extra` (see SDFShape).
        let kind: Float
        switch marker {
        case .circle:
            // The disk path: its own SDF shape, with sub-pixel area conservation.
            // A point is a point — opt out of hollow mode (it shares `.ellipse`).
            appendSDF(shape: .ellipse, center: Vector2(x, y),
                      size: SIMD2<Float>(h, h), fill: fill, stroke: nil, applyHollow: false)
            return
        case .square:  kind = 0
        case .diamond: kind = 1
        case .cross:   kind = 2
        case .x:       kind = 3
        }
        // cross / x are filled bars; their arm half-width is a fixed fraction of
        // the radius (unused by the solid square / diamond).
        let armHalfWidth = h * 0.28
        appendSDF(shape: .marker, center: Vector2(x, y),
                  size: SIMD2<Float>(h, h), fill: fill, stroke: nil,
                  extra: kind, param0: SIMD2<Float>(armHalfWidth, 0))
    }

    func drawPoint(_ x: Double, _ y: Double) { drawPoint(x, y, pointDiameter) }

    /// An equilateral triangle centered at `(x, y)`, point-up, with circumradius
    /// `radius` (center-to-vertex distance, like `drawCircle`'s radius). Recorded
    /// as a single SDF instance — analytic fill + stroke + anti-aliasing — so it's
    /// crisp at any size and effectively free per triangle. Rotate via the
    /// transform stack to aim it; rotation pivots on the center.
    func drawTriangle(_ x: Double, _ y: Double, _ radius: Double) {
        guard radius > 0 else { return }
        if svgRecorder != nil {
            svgRecord(.polygon(svgOffset(SDFOutline.triangleEquilateral(radius: radius), Vector2(x, y))),
                      fill: fillPaint, stroke: strokePaint)
            return
        }
        let height = radius * 1.5                          // apex-to-base distance
        let halfBase = radius * 0.8660254037844386         // radius * √3/2
        // Anchor the centroid at (x, y); the apex (the SDF origin) sits `radius`
        // above it (the centroid is ⅓ of the height up from the base).
        appendSDF(shape: .triangle, center: Vector2(x, y - radius),
                  size: SIMD2<Float>(Float(halfBase), Float(height)),
                  fill: fillPaint, stroke: strokePaint)
    }

    /// An isosceles triangle whose apex (tip) is at `(x, y)`, opening toward +y
    /// (downward, in Ollin's y-down space) by `height`, with the given `base`
    /// width. Recorded as a single SDF instance (see `drawTriangle(_:_:_:)`):
    /// analytic, crisp at any size, effectively free. Rotate via the transform
    /// stack to aim it; rotation pivots on the apex — so to spin a wedge about its
    /// tip, `translate` to the tip, `rotate`, then draw with the apex at the
    /// origin.
    func drawTriangle(_ x: Double, _ y: Double, _ base: Double, _ height: Double) {
        guard base > 0, height > 0 else { return }
        if svgRecorder != nil {
            svgRecord(.polygon(svgOffset(SDFOutline.triangleIsosceles(base: base, height: height), Vector2(x, y))),
                      fill: fillPaint, stroke: strokePaint)
            return
        }
        appendSDF(shape: .triangle, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(base / 2), Float(height)),
                  fill: fillPaint, stroke: strokePaint)
    }

    /// A triangle through three arbitrary corners `a`, `b`, `c` (any winding). Unlike
    /// the equilateral `drawTriangle(_:_:_:)` (circumradius) and isosceles
    /// `drawTriangle(_:_:_:_:)` (apex + base + height) forms, this places the corners
    /// directly, so any triangle is one call. Recorded as a single SDF instance —
    /// analytic fill + stroke + anti-aliasing, crisp at any size and effectively free.
    /// Honors `strokeAlign` and `hollow`. A degenerate (zero-area) triangle draws
    /// nothing.
    func drawTriangle(_ a: Vector2, _ b: Vector2, _ c: Vector2) {
        let area = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        guard abs(area) > 1e-9 else { return }
        let lo = Vector2(min(a.x, min(b.x, c.x)), min(a.y, min(b.y, c.y)))
        let hi = Vector2(max(a.x, max(b.x, c.x)), max(a.y, max(b.y, c.y)))
        if svgRecorder != nil {
            svgRecord(.polygon([a, b, c]), fill: fillPaint, stroke: strokePaint)
            return
        }
        let center = (lo + hi) / 2
        let half = (hi - lo) / 2
        appendSDF(shape: .triangle3, center: center,
                  size: SIMD2<Float>(Float(half.x), Float(half.y)),
                  fill: fillPaint, stroke: strokePaint,
                  param0: (a - center).simd2, param1: (b - center).simd2, param2: (c - center).simd2)
    }

    /// A triangle through three corners given as scalar coordinates — the positional
    /// form of `drawTriangle(_:_:_:)`.
    func drawTriangle(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double,
                      _ x3: Double, _ y3: Double) {
        drawTriangle(Vector2(x1, y1), Vector2(x2, y2), Vector2(x3, y3))
    }

    /// A regular polygon centered at `(x, y)` with `sides` equal-length edges and
    /// circumradius `radius` (center-to-vertex, like `drawCircle`'s radius), one
    /// vertex pointing up. `sides` is 3 (a triangle) or more. Recorded as a single
    /// SDF instance — analytic fill + stroke + anti-aliasing, crisp at any size and
    /// effectively free per shape. Rotate via the transform stack; rotation pivots
    /// on the center.
    func drawNgon(_ x: Double, _ y: Double, _ radius: Double, sides: Int) {
        guard radius > 0, sides >= 3 else { return }
        if svgRecorder != nil {
            svgRecord(.polygon(svgOffset(SDFOutline.ngon(radius: radius, sides: sides), Vector2(x, y))),
                      fill: fillPaint, stroke: strokePaint)
            return
        }
        // A regular polygon is the special case of a star whose inner radius is the
        // apothem (the edge midpoints), which straightens the points into edges.
        appendStar(center: Vector2(x, y), outer: radius,
                   inner: radius * cos(.pi / Double(sides)), points: sides)
    }

    /// Named regular polygons — sugar over `drawNgon` with a fixed side count, the
    /// way `drawCircle` reads better than an equal-radii `drawEllipse`. Same
    /// arguments and behavior: circumradius `radius`, one vertex up, the same
    /// analytic SDF shape. For other side counts, call `drawNgon` directly.
    func drawPentagon(_ x: Double, _ y: Double, _ radius: Double) { drawNgon(x, y, radius, sides: 5) }
    func drawHexagon(_ x: Double, _ y: Double, _ radius: Double)  { drawNgon(x, y, radius, sides: 6) }
    func drawHeptagon(_ x: Double, _ y: Double, _ radius: Double) { drawNgon(x, y, radius, sides: 7) }
    func drawOctagon(_ x: Double, _ y: Double, _ radius: Double)  { drawNgon(x, y, radius, sides: 8) }

    /// A star centered at `(x, y)` with `points` outer points, alternating between
    /// `outerRadius` (the tips) and `innerRadius` (the valleys), one tip pointing
    /// up. `points` is 3 or more, and `innerRadius` is `0...outerRadius` (smaller is
    /// spikier). Recorded as a single SDF instance — analytic fill + stroke +
    /// anti-aliasing, crisp at any size. Rotate via the transform stack; rotation
    /// pivots on the center.
    func drawStar(_ x: Double, _ y: Double, _ outerRadius: Double, _ innerRadius: Double, points: Int) {
        guard outerRadius > 0, innerRadius > 0, innerRadius <= outerRadius, points >= 3 else { return }
        if svgRecorder != nil {
            svgRecord(.polygon(svgOffset(SDFOutline.star(outer: outerRadius, inner: innerRadius, points: points), Vector2(x, y))),
                      fill: fillPaint, stroke: strokePaint)
            return
        }
        appendStar(center: Vector2(x, y), outer: outerRadius, inner: innerRadius, points: points)
    }

    /// A rhombus (diamond) centered at `(x, y)`, `width` wide and `height` tall
    /// (the full diagonals), with vertices at the four points of those diagonals.
    /// `cornerRadius` rounds the corners while keeping the `width`×`height`
    /// footprint. Recorded as a single SDF instance — analytic fill + stroke +
    /// anti-aliasing, crisp at any size. Rotate via the transform stack.
    func drawRhombus(_ x: Double, _ y: Double, _ width: Double, _ height: Double, cornerRadius: Double = 0) {
        guard width > 0, height > 0 else { return }
        let r = max(0, min(cornerRadius, min(width, height) / 2))
        if svgRecorder != nil {
            let pts = r > 0 ? SDFOutline.rhombusRounded(width: width, height: height, cornerRadius: r)
                            : SDFOutline.rhombus(width: width, height: height)
            svgRecord(.polygon(svgOffset(pts, Vector2(x, y))), fill: fillPaint, stroke: strokePaint)
            return
        }
        appendSDF(shape: .rhombus, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(width / 2), Float(height / 2)),
                  fill: fillPaint, stroke: strokePaint, extra: Float(r))
    }

    /// A vesica (a pointed lens / two-circle intersection) centered at `(x, y)`,
    /// `width` by `height`; the tips lie along the longer axis. `cornerRadius`
    /// rounds the tips (and slightly enlarges the lens, like `drawMoon`).
    /// Recorded as a single SDF instance. Rotate via the transform stack.
    func drawVesica(_ x: Double, _ y: Double, _ width: Double, _ height: Double, cornerRadius: Double = 0) {
        guard width > 0, height > 0 else { return }
        if svgRecorder != nil {
            svgRecord(.polygon(svgOffset(SDFOutline.vesica(width: width, height: height, cornerRadius: max(0, cornerRadius)), Vector2(x, y))),
                      fill: fillPaint, stroke: strokePaint)
            return
        }
        let horizontal = width > height
        let a = (horizontal ? width : height) / 2     // half-length toward the tips
        let w = max((horizontal ? height : width) / 2, 1e-4)   // waist half-width
        let rr = max(0, cornerRadius)
        // Map the (along, across) half-extents to iq's circle radius + center
        // offset:  r = (w + a²/w) / 2,  d = (a² − w²) / (2w)  (a ≥ w; a == w is a
        // circle). Derived from the *full* footprint, not an inset one, so r/d stay
        // well-conditioned for any rounding (insetting toward a zero waist sends
        // them to ~1e7 and the shader's sqrt(r²−d²) loses all precision). opRound
        // (− rr) rounds the tips and grows the lens by rr, which the AABB accounts
        // for.
        let rCircle = (w + a * a / w) / 2
        let dOff = (a * a - w * w) / (2 * w)
        appendSDF(shape: .vesica, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(width / 2 + rr), Float(height / 2 + rr)),
                  fill: fillPaint, stroke: strokePaint, extra: Float(rr),
                  param0: SIMD2<Float>(Float(rCircle), Float(dOff)),
                  param1: SIMD2<Float>(horizontal ? 1 : 0, 0))
    }

    /// A crescent moon centered at `(x, y)`: the disk of `outerRadius` with a disk
    /// of `innerRadius` subtracted, the cut disk's center `offset` away (toward
    /// +x). For a classic crescent keep `innerRadius` near `outerRadius` with a
    /// modest `offset`. `cornerRadius` rounds the cusps (and slightly enlarges).
    /// Recorded as a single SDF instance. Rotate via the transform stack to aim it.
    func drawMoon(_ x: Double, _ y: Double, _ outerRadius: Double, _ innerRadius: Double,
                  _ offset: Double, cornerRadius: Double = 0) {
        guard outerRadius > 0, innerRadius > 0, offset > 0 else { return }
        let rr = max(0, cornerRadius)
        if svgRecorder != nil {
            svgRecord(.polygon(svgOffset(SDFOutline.moon(outerRadius: outerRadius, innerRadius: innerRadius, offset: offset, cornerRadius: rr), Vector2(x, y))),
                      fill: fillPaint, stroke: strokePaint)
            return
        }
        appendSDF(shape: .moon, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(outerRadius + rr), Float(outerRadius + rr)),
                  fill: fillPaint, stroke: strokePaint, extra: Float(rr),
                  param0: SIMD2<Float>(Float(outerRadius), Float(innerRadius)),
                  param1: SIMD2<Float>(Float(offset), 0))
    }

    /// A plus-sign cross centered at `(x, y)`, spanning `length` tip-to-tip on both
    /// axes with arms `thickness` wide. `cornerRadius` rounds the outer corners
    /// (the inner notches stay sharp). Recorded as a single SDF instance — analytic
    /// fill + stroke + anti-aliasing. Rotate 45° via the transform stack for an ✕.
    func drawCross(_ x: Double, _ y: Double, _ length: Double, _ thickness: Double, cornerRadius: Double = 0) {
        guard length > 0, thickness > 0 else { return }
        let armHalfLength = length / 2
        let armHalfWidth = min(thickness, length) / 2
        let r = max(0, min(cornerRadius, armHalfWidth))
        if svgRecorder != nil {
            let pts = r > 0 ? SDFOutline.crossRounded(length: length, thickness: thickness, cornerRadius: r)
                            : SDFOutline.cross(length: length, thickness: thickness)
            svgRecord(.polygon(svgOffset(pts, Vector2(x, y))), fill: fillPaint, stroke: strokePaint)
            return
        }
        appendSDF(shape: .cross, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(armHalfLength), Float(armHalfLength)),
                  fill: fillPaint, stroke: strokePaint, extra: Float(r),
                  param0: SIMD2<Float>(Float(armHalfWidth), 0))
    }

    /// A filled ring (annulus) centered at `(x, y)` between `innerRadius` and
    /// `outerRadius`. Takes the current `fill` (not stroke); for two outlined
    /// circles instead, draw `drawCircle` twice with `noFill`. Recorded as a single
    /// SDF instance.
    func drawRing(_ x: Double, _ y: Double, _ innerRadius: Double, _ outerRadius: Double) {
        guard outerRadius > 0, innerRadius >= 0, innerRadius < outerRadius else { return }
        if svgRecorder != nil {
            let c = Vector2(x, y)
            var contours = [Contour(svgOffset(SDFOutline.circle(radius: outerRadius), c), closed: true)]
            if innerRadius > 0 {
                contours.append(Contour(svgOffset(SDFOutline.circle(radius: innerRadius), c), closed: true))
            }
            svgRecord(.path(Shape(contours: contours, winding: .evenOdd)), fill: fillPaint, stroke: nil)
            return
        }
        let mid = (outerRadius + innerRadius) / 2
        let half = (outerRadius - innerRadius) / 2
        appendSDF(shape: .ring, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(outerRadius), Float(outerRadius)),
                  fill: fillPaint, stroke: nil,
                  param0: SIMD2<Float>(Float(mid), Float(half)))
    }

    /// An isosceles trapezoid centered at `(x, y)`, `topWidth` across the top edge
    /// and `bottomWidth` across the bottom, `height` tall. A rectangle when the two
    /// widths match, a triangle when one is `0`. Recorded as a single SDF instance —
    /// analytic fill + stroke + anti-aliasing. Rotate via the transform stack.
    func drawTrapezoid(_ x: Double, _ y: Double, _ topWidth: Double, _ bottomWidth: Double, _ height: Double) {
        guard height > 0, topWidth >= 0, bottomWidth >= 0, topWidth + bottomWidth > 0 else { return }
        if svgRecorder != nil {
            svgRecord(.polygon(svgOffset(SDFOutline.trapezoid(topWidth: topWidth, bottomWidth: bottomWidth, height: height), Vector2(x, y))),
                      fill: fillPaint, stroke: strokePaint)
            return
        }
        let halfMax = max(topWidth, bottomWidth) / 2
        appendSDF(shape: .trapezoid, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(halfMax), Float(height / 2)),
                  fill: fillPaint, stroke: strokePaint,
                  param0: SIMD2<Float>(Float(topWidth / 2), Float(bottomWidth / 2)))
    }

    /// A parallelogram centered at `(x, y)`, `width` wide and `height` tall, with the
    /// top edge sheared `skew` points along +x relative to the bottom (`0` is a
    /// rectangle). Recorded as a single SDF instance. Rotate via the transform stack.
    func drawParallelogram(_ x: Double, _ y: Double, _ width: Double, _ height: Double, _ skew: Double) {
        guard width > 0, height > 0 else { return }
        if svgRecorder != nil {
            svgRecord(.polygon(svgOffset(SDFOutline.parallelogram(width: width, height: height, skew: skew), Vector2(x, y))),
                      fill: fillPaint, stroke: strokePaint)
            return
        }
        appendSDF(shape: .parallelogram, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(width / 2 + abs(skew)), Float(height / 2)),
                  fill: fillPaint, stroke: strokePaint, extra: Float(skew),
                  param0: SIMD2<Float>(Float(width / 2), 0))
    }

    /// An egg centered at `(x, y)`: a circle of `bottomRadius` at the fat lower end
    /// tapering to a rounded tip of `topRadius` at the top, pointing up.
    /// `bottomRadius` must be ≥ `topRadius` (equal is a circle). Recorded as a single
    /// SDF instance. Rotate via the transform stack.
    func drawEgg(_ x: Double, _ y: Double, _ bottomRadius: Double, _ topRadius: Double) {
        guard bottomRadius > 0, topRadius > 0, topRadius <= bottomRadius else { return }
        if svgRecorder != nil {
            svgRecord(.polygon(svgOffset(SDFOutline.egg(bottomRadius: bottomRadius, topRadius: topRadius), Vector2(x, y))),
                      fill: fillPaint, stroke: strokePaint)
            return
        }
        // Native span is y in [-bottomRadius, apex]; the fragment recenters on the
        // quad, so size.y carries the symmetric half-height around that center.
        let apex = 1.7320508075688772 * (bottomRadius - topRadius) + topRadius
        let halfHeight = (apex + bottomRadius) / 2
        appendSDF(shape: .egg, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(bottomRadius), Float(halfHeight)),
                  fill: fillPaint, stroke: strokePaint,
                  param0: SIMD2<Float>(Float(bottomRadius), Float(topRadius)))
    }

    /// A heart centered at `(x, y)`, `size` points wide (a touch shorter than wide),
    /// lobes up and point down. Recorded as a single SDF instance. Rotate via the
    /// transform stack (45° spins it like a playing-card suit, 180° points it up).
    func drawHeart(_ x: Double, _ y: Double, _ size: Double) {
        guard size > 0 else { return }
        if svgRecorder != nil {
            svgRecord(.polygon(svgOffset(SDFOutline.heart(size: size), Vector2(x, y))), fill: fillPaint, stroke: strokePaint)
            return
        }
        // The unit heart spans width 1.2036, height 1.0985 (lobes up); scale so the
        // width matches `size`. The fragment flips Y and recenters.
        let s = size / 1.2036
        appendSDF(shape: .heart, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(0.6018 * s), Float(0.54925 * s)),
                  fill: fillPaint, stroke: strokePaint,
                  param0: SIMD2<Float>(Float(s), 0))
    }

    /// A disk of `radius` centered at `(x, y)` with a straight horizontal slice
    /// removed — a dome, flat edge down and bulge up. `cut` is the signed offset of
    /// the flat edge from the center (`-radius...radius`): `0` is a half disk,
    /// positive raises the cut and keeps a smaller cap, negative keeps more than
    /// half. Recorded as a single SDF instance. Rotate via the transform stack to
    /// aim the flat edge.
    func drawCutDisk(_ x: Double, _ y: Double, _ radius: Double, _ cut: Double) {
        guard radius > 0, abs(cut) < radius else { return }
        if svgRecorder != nil {
            svgRecord(.polygon(svgOffset(SDFOutline.cutDisk(radius: radius, cut: cut), Vector2(x, y))),
                      fill: fillPaint, stroke: strokePaint)
            return
        }
        appendSDF(shape: .cutDisk, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(radius), Float(radius)),
                  fill: fillPaint, stroke: strokePaint,
                  param0: SIMD2<Float>(Float(radius), Float(cut)))
    }

    /// A tapered capsule (a rounded bar with unequal end radii) from `a` (radius
    /// `ra`) to `b` (radius `rb`) — `drawLine` with mismatched round caps, taking
    /// fill + stroke like a shape. The end-to-end distance must be at least
    /// `|ra − rb|` (otherwise one cap swallows the other). Recorded as a single SDF
    /// instance.
    func drawUnevenCapsule(_ a: Vector2, _ b: Vector2, _ ra: Double, _ rb: Double) {
        guard ra > 0, rb > 0 else { return }
        let d = b - a
        let len = d.length
        guard len > 1e-6, len >= abs(ra - rb) else { return }
        if svgRecorder != nil {
            svgRecord(.polygon(svgOffset(SDFOutline.unevenCapsule(a: a, b: b, ra: ra, rb: rb), (a + b) / 2)),
                      fill: fillPaint, stroke: strokePaint)
            return
        }
        let dir = d / len
        let bound = len / 2 + max(ra, rb)
        appendSDF(shape: .unevenCapsule, center: (a + b) / 2,
                  size: SIMD2<Float>(Float(bound), Float(bound)),
                  fill: fillPaint, stroke: strokePaint, extra: Float(len),
                  param0: SIMD2<Float>(Float(ra), Float(rb)),
                  param1: SIMD2<Float>(Float(dir.y), Float(dir.x)))
    }

    /// A horseshoe (a thick arc with a gap) centered at `(x, y)`: a band at mid-
    /// radius `radius`, `thickness` thick, open across an arc of `gap` radians at
    /// the bottom (a smaller `gap` is more nearly closed; `0` is a full ring with a
    /// pinhole, `.pi` is a half-ring). Recorded as a single SDF instance — analytic
    /// fill + stroke + anti-aliasing. Rotate via the transform stack to aim the
    /// opening; rotation pivots on the center.
    func drawHorseshoe(_ x: Double, _ y: Double, _ radius: Double, _ thickness: Double, gap: Double) {
        guard radius > 0, thickness > 0 else { return }
        if svgRecorder != nil {
            svgRecord(.polygon(svgOffset(SDFOutline.horseshoe(radius: radius, thickness: thickness, gap: gap), Vector2(x, y))),
                      fill: fillPaint, stroke: strokePaint)
            return
        }
        // iq's `c` is the (cos, sin) of half the opening angle: the band then wraps
        // the remaining 2·(π − gap/2), so `gap` is the full angular opening.
        let an = min(max(gap / 2, 1e-3), Double.pi - 1e-3)
        let w = Float(thickness / 2)
        let bound = Float(radius + thickness)
        appendSDF(shape: .horseshoe, center: Vector2(x, y),
                  size: SIMD2<Float>(bound, bound),
                  fill: fillPaint, stroke: strokePaint, extra: Float(radius),
                  param0: SIMD2<Float>(Float(cos(an)), Float(sin(an))),
                  param1: SIMD2<Float>(w, w))
    }

    /// A filled parabolic arch centered at `(x, y)`, `width` across the flat base
    /// and `height` tall, the curve peaking at the top (a parabola capping a
    /// straight base). Recorded as a single SDF instance — analytic fill + stroke +
    /// anti-aliasing. Rotate via the transform stack.
    func drawParabola(_ x: Double, _ y: Double, _ width: Double, _ height: Double) {
        guard width > 0, height > 0 else { return }
        if svgRecorder != nil {
            svgRecord(.polygon(svgOffset(SDFOutline.parabola(width: width, height: height), Vector2(x, y))),
                      fill: fillPaint, stroke: strokePaint)
            return
        }
        appendSDF(shape: .parabola, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(width / 2), Float(height / 2)),
                  fill: fillPaint, stroke: strokePaint,
                  param0: SIMD2<Float>(Float(width / 2), Float(height)))
    }

    /// An X (saltire) centered at `(x, y)`, `length` tip-to-tip along each axis,
    /// drawn with round-capped arms `thickness` wide. Like `drawCross` rotated 45°
    /// but with rounded ends. Recorded as a single SDF instance — analytic fill +
    /// stroke + anti-aliasing. Rotate via the transform stack.
    func drawRoundedX(_ x: Double, _ y: Double, _ length: Double, _ thickness: Double) {
        guard length > 0, thickness > 0 else { return }
        if svgRecorder != nil {
            svgRecord(.polygon(svgOffset(SDFOutline.roundedX(length: length, thickness: thickness), Vector2(x, y))),
                      fill: fillPaint, stroke: strokePaint)
            return
        }
        let r = thickness / 2
        // The diagonal tips reach `w/2 + r/√2` per axis; invert to hit `length/2`.
        let w = max(length - thickness * 0.7071067811865476, 0)
        appendSDF(shape: .roundedX, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(length / 2 + r), Float(length / 2 + r)),
                  fill: fillPaint, stroke: strokePaint, extra: Float(r),
                  param0: SIMD2<Float>(Float(w), 0))
    }

    /// A blobby cross centered at `(x, y)`: a four-armed cross with concave,
    /// inward-curving sides, its tips reaching `radius` along each axis.
    /// `blobbiness` (`0...1`, default `0.5`) sets how pinched the waist is — larger
    /// is more bulbous. Recorded as a single SDF instance. Rotate via the transform
    /// stack (45° gives a diagonal four-point pinwheel).
    func drawBlobbyCross(_ x: Double, _ y: Double, _ radius: Double, blobbiness: Double = 0.5) {
        guard radius > 0 else { return }
        if svgRecorder != nil {
            svgRecord(.polygon(svgOffset(SDFOutline.blobbyCross(radius: radius, blobbiness: blobbiness), Vector2(x, y))),
                      fill: fillPaint, stroke: strokePaint)
            return
        }
        let he = min(max(blobbiness, 0.3), 0.6)
        // The unit cross's tip lands at `tipUnit` along each axis; scale so it
        // reaches `radius`. (Larger `he` → shorter tips / fatter arms, so `tipUnit`
        // shrinks and the scale grows — the shape just gets blobbier at fixed reach.)
        let tipUnit = 1 / (he * 2.0.squareRoot()) - 1
        let s = radius / tipUnit
        appendSDF(shape: .blobbyCross, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(radius * 1.08), Float(radius * 1.08)),
                  fill: fillPaint, stroke: strokePaint,
                  param0: SIMD2<Float>(Float(s), Float(he)))
    }

    /// A tunnel / archway centered at `(x, y)`: vertical walls and a flat base under
    /// a semicircular top, `width` wide and `height` tall overall (the arch radius is
    /// half the width, so `height` must be at least `width / 2`). Recorded as a
    /// single SDF instance. Rotate via the transform stack to aim the opening.
    func drawTunnel(_ x: Double, _ y: Double, _ width: Double, _ height: Double) {
        guard width > 0, height >= width / 2 else { return }
        if svgRecorder != nil {
            svgRecord(.polygon(svgOffset(SDFOutline.tunnel(width: width, height: height), Vector2(x, y))),
                      fill: fillPaint, stroke: strokePaint)
            return
        }
        let whx = width / 2                 // half-width = arch radius
        let why = height - whx              // straight-wall height
        appendSDF(shape: .tunnel, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(width / 2), Float(height / 2)),
                  fill: fillPaint, stroke: strokePaint,
                  param0: SIMD2<Float>(Float(whx), Float(why)))
    }

    /// A staircase centered at `(x, y)`: `steps` steps, each `stepWidth` wide and
    /// `stepHeight` tall, ascending to the right. The whole flight spans
    /// `stepWidth · steps` by `stepHeight · steps`. Recorded as a single SDF
    /// instance. Rotate via the transform stack.
    func drawStairs(_ x: Double, _ y: Double, _ stepWidth: Double, _ stepHeight: Double, steps: Int) {
        guard stepWidth > 0, stepHeight > 0, steps >= 1 else { return }
        if svgRecorder != nil {
            svgRecord(.polygon(svgOffset(SDFOutline.stairs(stepWidth: stepWidth, stepHeight: stepHeight, steps: steps), Vector2(x, y))),
                      fill: fillPaint, stroke: strokePaint)
            return
        }
        let n = Double(steps)
        appendSDF(shape: .stairs, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(stepWidth * n / 2), Float(stepHeight * n / 2)),
                  fill: fillPaint, stroke: strokePaint, extra: Float(steps),
                  param0: SIMD2<Float>(Float(stepWidth), Float(stepHeight)))
    }

    /// The iconic hand-drawn "S" centered at `(x, y)`, `size` points tall.
    /// Recorded as a single SDF instance — analytic fill + stroke + anti-aliasing.
    /// Rotate via the transform stack.
    func drawCoolS(_ x: Double, _ y: Double, _ size: Double) {
        guard size > 0 else { return }
        if svgRecorder != nil {
            svgRecord(.polygon(svgOffset(SDFOutline.coolS(size: size), Vector2(x, y))), fill: fillPaint, stroke: strokePaint)
            return
        }
        // The unit "S" spans about y in [-1.05, 1.05]; scale so `size` is its height.
        let s = size / 2.1
        appendSDF(shape: .coolS, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(size / 2 + s * 0.1), Float(size / 2 + s * 0.1)),
                  fill: fillPaint, stroke: strokePaint,
                  param0: SIMD2<Float>(Float(s), 0))
    }

    /// Shared builder for `drawNgon`/`drawStar`. Encodes the star into the SDF
    /// slots the way `sdStar` (in `ShaderShapes.metal`) reads them: `size = (R, R)` (R is
    /// both the outer radius and the bounding half-extent), `param0 = (cos, sin)` of
    /// the half-sector angle `an = π/points`, `param1 = (cos, sin)` of the edge angle
    /// `en`, and `extra = an`. The inner radius sets `en` via
    /// `inner = R·(cos an − sin an / tan en)`, inverted here to
    /// `en = atan2(sin an, cos an − inner/R)` (a regular polygon's apothem gives
    /// `en = π/2`, i.e. straight edges).
    private func appendStar(center: Vector2, outer: Double, inner: Double, points n: Int) {
        let an = Double.pi / Double(n)
        let acs = SIMD2<Float>(Float(cos(an)), Float(sin(an)))
        let en = atan2(sin(an), cos(an) - inner / outer)
        let ecs = SIMD2<Float>(Float(cos(en)), Float(sin(en)))
        appendSDF(shape: .star, center: center,
                  size: SIMD2<Float>(Float(outer), Float(outer)),
                  fill: fillPaint, stroke: strokePaint,
                  extra: Float(an), param0: acs, param1: ecs)
    }

    /// One paint encoded for an `SDFInstance` color slot: a solid color as-is
    /// (kind 0), or a gradient's geometry — made relative to the shape center, so
    /// the fragment evaluates it against `in.local` and it rides the CTM — with
    /// the paint kind for the shape-tag bits and the ramp's strip row.
    private struct EncodedPaint {
        var slot: SIMD4<Float>
        var kind: UInt32      // 0 solid, 1 linear, 2 radial, 3 along-path
        var row: Float

        static let none = EncodedPaint(slot: SIMD4<Float>(repeating: 0), kind: 0, row: 0)
    }

    private func encodePaint(_ paint: Paint, center: Vector2) -> EncodedPaint {
        switch paint {
        case .color(let c):
            return EncodedPaint(slot: c.simd4, kind: 0, row: 0)
        case .gradient(let g):
            let row = Float(gradientRow(for: g.ramp).index)
            switch g.geometry {
            case .linear(let start, let end):
                let s = start - center
                let e = end - center
                return EncodedPaint(slot: SIMD4<Float>(Float(s.x), Float(s.y), Float(e.x), Float(e.y)),
                                    kind: 1, row: row)
            case .radial(let c, let r):
                let cc = c - center
                return EncodedPaint(slot: SIMD4<Float>(Float(cc.x), Float(cc.y), Float(max(r, 1e-6)), 0),
                                    kind: 2, row: row)
            case .alongPath:
                return EncodedPaint(slot: SIMD4<Float>(repeating: 0), kind: 3, row: row)
            }
        }
    }

    /// Record one analytic shape as an SDF instance, carrying the current
    /// transform plus the given fill, stroke, and shape-specific slots. A `nil`
    /// fill/stroke becomes a zero-alpha color the shader treats as "skip"; a
    /// caller passes explicit paints (e.g. a line passes its stroke as `fill`).
    /// No-op when there's nothing to draw.
    private func appendSDF(shape: SDFShape, center: Vector2, size: SIMD2<Float>,
                           fill: Paint?, stroke: Paint?, strokeWidth: Double? = nil,
                           extra: Float = 0,
                           param0: SIMD2<Float> = .zero, param1: SIMD2<Float> = .zero,
                           param2: SIMD2<Float> = .zero,
                           applyHollow: Bool = true) {
        // Inside a scoped-combine block, capture this shape as an SDF leaf instead of
        // drawing it (it merges with its siblings when the block closes).
        if !combineStack.isEmpty {
            captureCombineLeaf(shape: shape, center: center, size: size, fill: fill,
                               extra: extra, param0: param0, param1: param1, param2: param2)
            return
        }
        // SVG export safety net: the only SDF that still funnels here while
        // recording is the bitmap-text pixel (a `.box`); every other shape is
        // intercepted at its public draw method. Emit it as a `<rect>`.
        if svgRecorder != nil {
            if shape == .box {
                let corner = Vector2(center.x - Double(size.x), center.y - Double(size.y))
                svgRecord(.rect(corner: corner, width: Double(size.x) * 2, height: Double(size.y) * 2,
                                cornerRadius: Double(extra)), fill: fill, stroke: stroke)
            }
            return
        }
        let weight = strokeWidth ?? self.strokeWidth
        let hasStroke = stroke != nil && weight > 0
        guard fill != nil || hasStroke else { return }
        // Hollow mode applies only to region shapes the fragment can onion; the
        // round-dot point path shares the `.ellipse` tag, so it opts out here.
        let band = (applyHollow && shape.honorsHollow) ? Float(hollowWidth) : 0
        ensureBatch(.sdf)
        let fillEnc = fill.map { encodePaint($0, center: center) } ?? .none
        let strokeEnc = hasStroke ? encodePaint(stroke!, center: center) : .none
        sdfInstances.append(SDFInstance(
            transform: transform,
            center: center.simd2,
            size: size,
            fillColor: fillEnc.slot,
            strokeColor: strokeEnc.slot,
            param0: param0,
            param1: param1,
            param2: param2,
            strokeWidth: hasStroke ? Float(weight) : 0,
            extra: extra,
            bandWidth: band,
            // Stroke alignment and the two paint kinds ride in the shape tag's
            // high bits (the tag itself is < 256), so they cost no instance room.
            shape: shape.rawValue | (strokeAlignment.shaderCode << 8)
                 | (fillEnc.kind << 10) | (strokeEnc.kind << 12),
            fillGradient: fillEnc.row,
            strokeGradient: strokeEnc.row))
    }

    /// Draw a composed signed-distance field (`SDF`): its shapes merge into one
    /// region, filled with the current `fill` (or each leaf's `.colored`) and
    /// stroked along the *merged* outline with the current `stroke`/`strokeWeight`.
    /// The tree is flattened to an instruction program the fragment evaluates per
    /// pixel (see ShaderCombinator.metal). A solid `fill` colors leaves individually
    /// (`.colored` per leaf, melted at smooth seams); a linear/radial gradient `fill`
    /// or `stroke` paints the whole merged region/outline by field position instead
    /// (along-path has no single path on a merged field, so it isn't supported there).
    func drawSDF(_ sdf: SDF) {
        // A field has no polygonal outline to serialize; SVG export of one would need
        // marching-squares contouring (a follow-up), so for now it records nothing.
        if svgRecorder != nil { return }

        let defaultFill: Color = {
            if case .some(.color(let c)) = fillPaint { return c }
            return .white
        }()
        let nodeStart = sdfNodes.count
        var nodes: [SDFNode] = []
        let bounds = sdf.flatten(defaultFill: defaultFill, into: &nodes)
        guard !nodes.isEmpty else { return }
        // Bound the work: skip (loudly) a field too large or too deeply nested for the
        // shader's fixed stacks, rather than mis-drawing it silently.
        if nodes.count > SDF.maxNodes {
            print("Ollin: drawSDF — field has \(nodes.count) nodes (max \(SDF.maxNodes)); skipping.")
            return
        }
        if bounds.valueDepth > SDF.maxValueDepth || bounds.pointDepth > SDF.maxPointDepth {
            print("Ollin: drawSDF — field nests too deep (combine \(bounds.valueDepth)/\(SDF.maxValueDepth), transform \(bounds.pointDepth)/\(SDF.maxPointDepth)); skipping.")
            return
        }

        // Covering quad = the whole-tree AABB, grown by half the stroke + a small AA
        // margin. The field origin is the CTM origin; `center` offsets the quad onto
        // the AABB while the VM still evaluates in field coordinates.
        let center = (bounds.lo + bounds.hi) * 0.5

        // Fill: the leaves' own (melted) colors by default, or — when the current `fill` is a
        // linear/radial gradient — that gradient painting the whole merged region by field
        // position (the leaf colors bypassed). Geometry is in field coords (`center: .zero`,
        // sampled at `in.field`); along-path has no single path on a merged field, so it's skipped.
        var fillGeo = SIMD4<Float>(repeating: 0)
        var fillKind: Float = 0
        var fillRow: Float = 0
        if let fillPaint, case .gradient = fillPaint {
            let enc = encodePaint(fillPaint, center: .zero)
            if enc.kind == 1 || enc.kind == 2 {
                fillGeo = enc.slot; fillKind = Float(enc.kind); fillRow = enc.row
            }
        }

        // Stroke: a solid color, or a linear/radial gradient traced along the merged outline
        // (its geometry rides the `strokeColor` slot, as `SDFInstance` reuses its color slots).
        // An along-path gradient has no single path on a merged outline, so it draws no stroke.
        var strokeSlot = SIMD4<Float>(repeating: 0)
        var strokeKind: Float = 0
        var strokeRow: Float = 0
        var strokeOn = false
        if strokeWidth > 0, let strokePaint {
            let enc = encodePaint(strokePaint, center: .zero)
            if enc.kind <= 2 {            // 0 solid, 1 linear, 2 radial (3 along-path: unsupported)
                strokeSlot = enc.slot
                strokeKind = Float(enc.kind)
                strokeRow = enc.row
                strokeOn = true
            }
        }
        let weight: Float = strokeOn ? Float(strokeWidth) : 0
        let hw = strokeOn ? Float(strokeWidth) * 0.5 : 0
        let ext = (bounds.hi - bounds.lo) * 0.5 + SIMD2<Float>(repeating: hw + 2)

        sdfNodes.append(contentsOf: nodes)
        ensureBatch(.sdfGroup)
        sdfGroups.append(SDFGroupInstance(
            transform: transform, center: center, size: ext,
            strokeColor: strokeSlot, strokeWidth: weight,
            bandWidth: 0, nodeStart: UInt32(nodeStart), nodeCount: UInt32(nodes.count),
            fillGradientGeo: fillGeo, fillGradientKind: fillKind, fillGradientRow: fillRow,
            strokeGradientKind: strokeKind, strokeGradientRow: strokeRow))
    }

    /// Draw a composed 3D signed-distance field: sphere-traced through the active
    /// camera, lit by the scene's lights, and depth-composited with the rasterized
    /// meshes (see SDF3D / ShaderRaymarch.metal). Requires a camera (3D only). A solid
    /// `fill` colors leaves individually (`.colored` per leaf, melted at smooth seams);
    /// a gradient `fill` paints the whole merged surface by screen position instead.
    func drawSDF3D(_ sdf: SDF3D) {
        guard camera3D != nil else { return }   // 3D only — needs an active camera
        // SVG export is 2D vector only; a sphere-traced surface has no vector outline.
        if svgRecorder != nil { return }
        currentTarget?.needsDepth = true        // 3D in a target → that pass carries depth

        let defaultFill: Color = {
            if case .some(.color(let c)) = fillPaint { return c }
            return .white
        }()
        let nodeStart = sdf3DNodes.count
        var nodes: [SDFNode3D] = []
        let bounds = sdf.flatten(defaultFill: defaultFill, into: &nodes)
        guard !nodes.isEmpty else { return }
        // Bound the work to the shader's fixed stacks: skip (loudly) a field too large
        // or too deeply nested rather than mis-drawing it.
        if nodes.count > SDF3D.maxNodes {
            print("Ollin: drawSDF3D — field has \(nodes.count) nodes (max \(SDF3D.maxNodes)); skipping.")
            return
        }
        if bounds.valueDepth > SDF3D.maxValueDepth || bounds.pointDepth > SDF3D.maxPointDepth {
            print("Ollin: drawSDF3D — field nests too deep (combine \(bounds.valueDepth)/\(SDF3D.maxValueDepth), transform \(bounds.pointDepth)/\(SDF3D.maxPointDepth)); skipping.")
            return
        }

        // Place the field in world space by the current 3D model matrix. The march runs
        // in world space and maps each sample back into the field's local frame, so the
        // group carries the inverse model + the uniform scale (local distance → world
        // distance) and the field's world-space AABB (the 8 local corners transformed,
        // padded a touch for the smooth-blend bulge + AA so the box never clips).
        let m = modelMatrix
        let inv = m.inverse
        let scale = simd_length(SIMD3<Float>(m.columns.0.x, m.columns.0.y, m.columns.0.z))
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for cx in [bounds.lo.x, bounds.hi.x] {
            for cy in [bounds.lo.y, bounds.hi.y] {
                for cz in [bounds.lo.z, bounds.hi.z] {
                    let w = m * SIMD4<Float>(cx, cy, cz, 1)
                    let p = SIMD3<Float>(w.x, w.y, w.z)
                    lo = simd_min(lo, p); hi = simd_max(hi, p)
                }
            }
        }
        let pad = SIMD3<Float>(repeating: 0.05 * max(scale, 1e-4))
        lo -= pad; hi += pad

        // A gradient `fill` paints the whole merged surface by screen position (the leaves'
        // own colors are bypassed). The geometry is in absolute canvas points (center .zero),
        // since the raymarch fragment samples it at each hit's projected screen position;
        // along-path has no meaning on a field, so only linear/radial paint the surface.
        var gradientGeo = SIMD4<Float>(repeating: 0)
        var gradientKind: Float = 0
        var gradientRow: Float = 0
        if let fillPaint, case .gradient = fillPaint {
            let encoded = encodePaint(fillPaint, center: .zero)
            if encoded.kind == 1 || encoded.kind == 2 {
                gradientGeo = encoded.slot
                gradientKind = Float(encoded.kind)
                gradientRow = encoded.row
            }
        }

        sdf3DNodes.append(contentsOf: nodes)
        ensureBatch(.sdfGroup3D)
        sdf3DGroups.append(SDF3DGroupInstance(
            inverseModel: inv,
            boundsMin: SIMD4<Float>(lo.x, lo.y, lo.z, 0),
            boundsMax: SIMD4<Float>(hi.x, hi.y, hi.z, 0),
            fillGradientGeo: gradientGeo,
            modelScale: scale, nodeStart: UInt32(nodeStart),
            nodeCount: UInt32(nodes.count), unbounded: bounds.unbounded ? 1 : 0,
            fillGradientKind: gradientKind, fillGradientRow: gradientRow,
            _pad0: 0, _pad1: 0))
    }

    // MARK: SDF-combinator scoped blocks (sugar over the `SDF` value type)

    private enum CombineFrameKind {
        case combine(SDF.Combine, Float)   // fold children under this op (k = smoothing, 0 = hard)
        // Union the children, then apply this domain op. Carried for both dimensions (the
        // 2D `SDF.Transform` for captured 2D shapes, the 3D `SDF3D.Transform` for 3D ones).
        case domain(SDF.Transform, SDF3D.Transform)
    }
    private final class CombineFrame {
        let kind: CombineFrameKind
        var children: [SDF] = []        // 2D region leaves captured in this block
        var children3D: [SDF3D] = []    // 3D mesh-primitive leaves captured in this block
        init(_ kind: CombineFrameKind) { self.kind = kind }
    }

    /// Open a scoped combine block (`smoothUnion(k:) { … }` etc.). Both 2D SDF region
    /// draws and 3D mesh-primitive draws (`drawSphere`/`drawBox`/…) inside are captured
    /// and folded under `op` when the block closes; one block serves both dimensions, and
    /// a sketch is in one or the other (the captured-but-empty dimension just draws nothing).
    func beginCombine(op: SDF.Combine, k: Double) {
        if combineStack.isEmpty { combineGroupTransform = transform; combineGroupModel = modelMatrix }
        combineStack.append(CombineFrame(.combine(op, Float(k))))
    }
    /// Open a scoped domain block (`mirrored { … }` / `repeated(…) { … }`): the contents
    /// are unioned, then the matching domain op is applied to the whole field (the 2D op to
    /// captured 2D shapes, the 3D op to captured 3D primitives; one block serves both).
    func beginCombineDomain(_ op2D: SDF.Transform, _ op3D: SDF3D.Transform) {
        if combineStack.isEmpty { combineGroupTransform = transform; combineGroupModel = modelMatrix }
        combineStack.append(CombineFrame(.domain(op2D, op3D)))
    }
    /// Close the innermost combine block: fold its children into one field (per dimension),
    /// then attach to the enclosing block, or (if this was the outermost) draw it.
    func endCombine() {
        guard let frame = combineStack.popLast() else { return }
        let field = buildCombineField(frame)
        let field3D = buildCombine3DField(frame)
        if let parent = combineStack.last {
            if let field { parent.children.append(field) }
            if let field3D { parent.children3D.append(field3D) }
            return
        }
        // Outermost: draw under the group's transforms (captured when it opened), restored
        // after in case the body changed the CTM / model matrix without scoping it.
        let groupT = combineGroupTransform
        let groupM = combineGroupModel
        combineGroupTransform = nil
        combineGroupModel = nil
        warnedNonCombinable = false
        warnedMeshInCombine = false
        if let field {
            let saved = transform
            if let groupT { transform = groupT }
            drawSDF(field)
            transform = saved
        }
        if let field3D {
            let savedM = modelMatrix
            if let groupM { modelMatrix = groupM }
            drawSDF3D(field3D)
            modelMatrix = savedM
        }
    }
    private func buildCombineField(_ frame: CombineFrame) -> SDF? {
        guard var result = frame.children.first else { return nil }
        let rest = frame.children.dropFirst()
        switch frame.kind {
        case let .combine(op, k):
            for child in rest { result = SDF(.combine(op, result, child, k)) }
            return result
        case let .domain(t, _):
            for child in rest { result = SDF(.combine(.union, result, child, 0)) }
            return SDF(.transformed(t, result))
        }
    }
    private func buildCombine3DField(_ frame: CombineFrame) -> SDF3D? {
        guard var result = frame.children3D.first else { return nil }
        let rest = frame.children3D.dropFirst()
        switch frame.kind {
        case let .combine(op, k):
            let op3 = SDF3D.Combine(rawValue: op.rawValue) ?? .union
            for child in rest { result = SDF3D(.combine(op3, result, child, k)) }
            return result
        case let .domain(_, t):
            for child in rest { result = SDF3D(.combine(.union, result, child, 0)) }
            return SDF3D(.transformed(t, result))
        }
    }
    /// Capture one region shape (already decoded by its draw method) as an `SDF` leaf,
    /// placed in the active group's field space via the relative CTM.
    private func captureCombineLeaf(shape: SDFShape, center: Vector2, size: SIMD2<Float>,
                                    fill: Paint?, extra: Float,
                                    param0: SIMD2<Float>, param1: SIMD2<Float>, param2: SIMD2<Float>) {
        guard let frame = combineStack.last else { return }
        guard shape.isCombinable else {
            if !warnedNonCombinable {
                print("Ollin: a non-region shape inside a combine block is ignored; a combine merges filled regions (circle/rect/ngon/star/…).")
                warnedNonCombinable = true
            }
            return
        }
        let color: Color? = { if case .some(.color(let c)) = fill { return c }; return nil }()
        var leaf = SDF(.leaf(shape: shape, size: size, p0: param0, p1: param1, p2: param2,
                             extra: extra, color: color))
        // Map the shape into the group's field space: rel = groupCTM⁻¹ · drawCTM, applied
        // to the shape center (position) and decomposed into a uniform scale + rotation.
        let groupT = combineGroupTransform ?? transform
        let rel = simd_inverse(groupT) * transform
        let cc = rel * SIMD3<Float>(Float(center.x), Float(center.y), 1)
        let col0 = SIMD2<Float>(rel.columns.0.x, rel.columns.0.y)
        let scale = simd_length(col0)
        let angle = atan2(col0.y, col0.x)
        if abs(scale - 1) > 1e-4 { leaf = leaf.scaled(Double(scale)) }
        if abs(angle) > 1e-4 { leaf = leaf.rotated(Double(angle)) }
        leaf = leaf.at(Vector2(Double(cc.x), Double(cc.y)))
        frame.children.append(leaf)
    }

    /// The chokepoint for the SDF-able mesh primitives (`drawSphere`/`drawBox`/…). Inside a
    /// combine block the primitive is captured as an `SDF3D` leaf (merged with the others on
    /// close); otherwise it tessellates and draws as a normal mesh. `leaf` is the matching
    /// analytic field; `mesh` is built lazily so the capture path never tessellates.
    func drawMeshPrimitive(_ leaf: SDF3D, mesh: @autoclosure () -> Mesh) {
        if !combineStack.isEmpty {
            captureCombine3DLeaf(leaf)
            return
        }
        drawMesh(mesh())
    }

    /// Capture an SDF-able primitive as an `SDF3D` leaf, placed in the active group's field
    /// space via the relative model matrix (decomposed into translate + rotate + uniform
    /// scale, the only similarity an SDF respects).
    private func captureCombine3DLeaf(_ baseLeaf: SDF3D) {
        guard let frame = combineStack.last, camera3D != nil else { return }
        var leaf = baseLeaf
        if case .some(.color(let c)) = fillPaint { leaf = leaf.colored(c) }
        // rel = groupModel⁻¹ · drawModel — where this leaf sits relative to the group origin.
        let groupM = combineGroupModel ?? modelMatrix
        let rel = simd_inverse(groupM) * modelMatrix
        let t = SIMD3<Float>(rel.columns.3.x, rel.columns.3.y, rel.columns.3.z)
        let col0 = SIMD3<Float>(rel.columns.0.x, rel.columns.0.y, rel.columns.0.z)
        let s = simd_length(col0)
        if abs(s - 1) > 1e-4 { leaf = leaf.scaled(Double(s)) }
        if s > 1e-6 {
            // Strip the uniform scale to read the pure rotation, then its axis-angle.
            let r = simd_float3x3(
                SIMD3<Float>(rel.columns.0.x, rel.columns.0.y, rel.columns.0.z) / s,
                SIMD3<Float>(rel.columns.1.x, rel.columns.1.y, rel.columns.1.z) / s,
                SIMD3<Float>(rel.columns.2.x, rel.columns.2.y, rel.columns.2.z) / s)
            let q = simd_quatf(r)
            let angle = q.angle
            if angle.isFinite && angle > 1e-4 {
                let a = q.axis
                if simd_length(a) > 1e-6 {
                    leaf = leaf.rotated(Double(angle), axis: Vector3(Double(a.x), Double(a.y), Double(a.z)))
                }
            }
        }
        leaf = leaf.at(x: Double(t.x), y: Double(t.y), z: Double(t.z))
        frame.children3D.append(leaf)
    }

    /// An elliptical arc centered at `(x, y)` with radii `rx`/`ry`, sweeping from
    /// `start` to `stop` (radians, clockwise). `mode` decides how the ends close:
    /// `.open` leaves the curve open, `.chord` joins them with a straight line,
    /// `.pie` joins them through the center. A fill paints the enclosed region
    /// (segment for open/chord, wedge for pie); a stroke traces the outline.
    ///
    /// A *circular* arc (`rx == ry`) under less than a full turn is recorded as a
    /// single SDF instance — analytic fill + stroke + anti-aliasing, crisp at any
    /// size and effectively free. Elliptical arcs and full sweeps fall back to
    /// CPU tessellation, which renders them exactly; both composite in draw order.
    func drawArc(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double,
                 start: Double, stop: Double, mode: ArcMode) {
        guard rx > 0, ry > 0 else { return }
        let sweep = stop - start
        guard abs(sweep) > 1e-9 else { return }

        if svgRecorder != nil {
            let full = circleSegments(for: max(rx, ry))
            let segments = max(2, Int((Double(full) * abs(sweep) / (2.0 * .pi)).rounded(.up)))
            var pts: [Vector2] = []
            pts.reserveCapacity(segments + 1)
            for i in 0...segments {
                let a = start + sweep * (Double(i) / Double(segments))
                pts.append(Vector2(x + cos(a) * rx, y + sin(a) * ry))
            }
            let center = Vector2(x, y)
            if let fill = fillPaint {
                svgRecord(.polygon(mode == .pie ? [center] + pts : pts), fill: fill, stroke: nil)
            }
            if strokePaint != nil, strokeWidth > 0 {
                switch mode {
                case .open:  svgRecord(.polyline(pts), fill: nil, stroke: strokePaint)
                case .chord: svgRecord(.polygon(pts), fill: nil, stroke: strokePaint)
                case .pie:   svgRecord(.polygon([center] + pts), fill: nil, stroke: strokePaint)
                }
            }
            return
        }

        if abs(rx - ry) < 1e-6, abs(sweep) < Double.tau - 1e-4 {
            appendArcSDF(center: Vector2(x, y), radius: rx, start: start, stop: stop, mode: mode)
            return
        }

        // Sample the arc, scaling the segment count to the swept fraction so a
        // short arc stays cheap and a near-full one stays smooth.
        let full = circleSegments(for: max(rx, ry))
        let segments = max(2, Int((Double(full) * abs(sweep) / (2.0 * .pi)).rounded(.up)))
        var pts: [Vector2] = []
        pts.reserveCapacity(segments + 1)
        for i in 0...segments {
            let a = start + sweep * (Double(i) / Double(segments))
            pts.append(Vector2(x + cos(a) * rx, y + sin(a) * ry))
        }
        let center = Vector2(x, y)

        if let fill = fillPaint {
            // Anchored on the arc center, so an along-path fill sweeps the same
            // conic the SDF arc evaluates.
            let vp = vertexPaint(fill, anchor: center)
            switch mode {
            case .open, .chord:
                // Circular segment — convex, so a fan from the first point fills it.
                let p0 = pts[0].simd2
                let c0 = vp.color(at: pts[0])
                for i in 1..<(pts.count - 1) {
                    emit(p0, color: c0)
                    emit(pts[i].simd2, color: vp.color(at: pts[i]))
                    emit(pts[i + 1].simd2, color: vp.color(at: pts[i + 1]))
                }
            case .pie:
                // Wedge — fan from the center.
                let cc = center.simd2
                let centerColor = vp.color(at: center)
                for i in 0..<(pts.count - 1) {
                    emit(cc, color: centerColor)
                    emit(pts[i].simd2, color: vp.color(at: pts[i]))
                    emit(pts[i + 1].simd2, color: vp.color(at: pts[i + 1]))
                }
            }
        }

        if let stroke = strokePaint, strokeWidth > 0 {
            let vp = vertexPaint(stroke, anchor: center)
            let half = strokeWidth / 2
            for i in 1..<pts.count {
                appendSegment(from: pts[i - 1], to: pts[i], half: half,
                              colorA: vp.color(at: pts[i - 1]), colorB: vp.color(at: pts[i]))
            }
            switch mode {
            case .open:
                break
            case .chord:
                appendSegment(from: pts[pts.count - 1], to: pts[0], half: half,
                              colorA: vp.color(at: pts[pts.count - 1]), colorB: vp.color(at: pts[0]))
            case .pie:
                appendSegment(from: center, to: pts[0], half: half,
                              colorA: vp.color(at: center), colorB: vp.color(at: pts[0]))
                appendSegment(from: pts[pts.count - 1], to: center, half: half,
                              colorA: vp.color(at: pts[pts.count - 1]), colorB: vp.color(at: center))
            }
        }
    }

    /// Record one circular arc as an SDF instance. The fragment evaluates the
    /// pie / segment / arc-band field in a canonical frame where the arc's
    /// bisector points to +Y: `param1` is `(cos, sin)` of the rotation that takes
    /// it there, `param0` is `(sin, cos)` of the half-aperture, and `size.x` is
    /// the radius. The arc spans the same angular set the tessellated path does,
    /// so the two render identically.
    private func appendArcSDF(center: Vector2, radius: Double,
                              start: Double, stop: Double, mode: ArcMode) {
        let shape: SDFShape
        switch mode {
        case .open:  shape = .arcOpen
        case .chord: shape = .arcChord
        case .pie:   shape = .arcPie
        }
        let halfAperture = abs(stop - start) / 2
        let bisector = (start + stop) / 2
        // Rotate local points by φ = π/2 − bisector so the bisector maps to +Y.
        let phi = Double.pi / 2 - bisector
        let r = Float(radius)
        appendSDF(shape: shape, center: center,
                  size: SIMD2<Float>(r, r),
                  fill: fillPaint, stroke: strokePaint,
                  param0: SIMD2<Float>(Float(sin(halfAperture)), Float(cos(halfAperture))),
                  param1: SIMD2<Float>(Float(cos(phi)), Float(sin(phi))))
    }

    /// A connected open path through `points`, stroked with the current stroke
    /// paint and weight (solid, translucent, or gradient).
    ///
    /// Stroke-only — fills belong to closed shapes (`drawShape`). Open by
    /// default (the last point is not joined back to the first); `closed: true`
    /// joins it, turning that seam with `strokeJoin` like every other corner.
    /// Corners turn per `strokeJoin` (mitered by default, so fat strokes stay
    /// clean at sharp turns) and open ends finish per `strokeCap` (butt by
    /// default). Needs at least two points and a stroke to draw anything.
    func drawPolyline(_ points: [Vector2], closed: Bool = false) {
        guard points.count >= 2, let stroke = strokePaint, strokeWidth > 0 else { return }
        if svgRecorder != nil {
            svgRecord(closed ? .polygon(points) : .polyline(points), fill: nil, stroke: stroke)
            return
        }
        // The full stroke (solid / translucent / gradient) renders through the
        // high-quality fringe expander — joins per strokeJoin, smooth at any angle.
        appendFringeStroke(points, closed: closed,
                           paint: vertexPaint(stroke, anchor: points[0]))
    }

    /// An axis-aligned `Rectangle`. Recorded as a single SDF instance (a box
    /// signed-distance field), not tessellated: the fragment derives fill, a
    /// stroke straddling the edges (width `strokeWeight`), and anti-aliasing
    /// analytically. `cornerRadius` rounds the corners (clamped to half the
    /// shorter side); the default `0` is a sharp rectangle. Crisp at any size and
    /// effectively free per rect, like `drawCircle`.
    func drawRect(_ rect: Rectangle, cornerRadius: Double = 0) {
        guard rect.width > 0, rect.height > 0 else { return }
        let r = max(0, min(cornerRadius, min(rect.width, rect.height) / 2))
        if svgRecorder != nil {
            svgRecord(.rect(corner: Vector2(rect.x, rect.y), width: rect.width, height: rect.height, cornerRadius: r),
                      fill: fillPaint, stroke: strokePaint)
            return
        }
        appendSDF(shape: .box, center: rect.center,
                  size: SIMD2<Float>(Float(rect.width / 2), Float(rect.height / 2)),
                  fill: fillPaint, stroke: strokePaint, extra: Float(r))
    }

    // MARK: Batches

    // Collection-call sugar over the single-shape primitives: one Swift call
    // emits the whole array. The current fill/stroke/transform applies to every
    // shape (vary them per shape with the single-shape calls in a loop instead).
    // Each shape is still its own instanced quad, so the array draws at the same
    // per-shape cost as the loop it replaces.

    /// Draw every circle in `circles`.
    func drawCircles(_ circles: [Circle]) {
        for c in circles { drawCircle(c.center.x, c.center.y, c.radius) }
    }

    /// Draw a circle of the same `radius` at each center in `centers`.
    func drawCircles(_ centers: [Vector2], radius: Double) {
        for c in centers { drawCircle(c.x, c.y, radius) }
    }

    /// Draw a `pointSize` marker at each point in `points`.
    func drawPoints(_ points: [Vector2]) {
        for p in points { drawPoint(p.x, p.y) }
    }

    /// Draw a marker of the same `size` at each point in `points`.
    func drawPoints(_ points: [Vector2], size: Double) {
        for p in points { drawPoint(p.x, p.y, size) }
    }

    /// Draw every rectangle in `rectangles`, each with the same `cornerRadius`.
    func drawRects(_ rectangles: [Rectangle], cornerRadius: Double = 0) {
        for r in rectangles { drawRect(r, cornerRadius: cornerRadius) }
    }

    // MARK: Images

    /// Draw `image` into `rect` (sketch space), stretched to fit. The image rides
    /// the transform stack like everything else, so `translate`/`rotate`/`scale`
    /// move and warp it. Recorded as one textured quad with its own batch, so it
    /// composites in draw order with the shapes around it. A zero-area rect or a
    /// non-uploadable image draws nothing.
    func drawImage(_ image: Image, in rect: Rectangle) {
        guard rect.width > 0, rect.height > 0, image.width > 0, image.height > 0 else { return }
        if let recorder = svgRecorder {
            recorder.skippedImages += 1   // raster has no place in a vector file
            return
        }
        let x0 = Float(rect.x), y0 = Float(rect.y)
        let x1 = Float(rect.x + rect.width), y1 = Float(rect.y + rect.height)
        // The four corners with their UVs: (0,0) top-left … (1,1) bottom-right.
        // A CPU-decoded texture's origin is top-left and sketch space is y-down, so
        // uv.y and screen y run the same way — no flip. A vertically-flipped image
        // (a GL/Syphon-origin texture) swaps the top and bottom V so it lands upright.
        let (vTop, vBot): (Float, Float) = image.flipsVertically ? (1, 0) : (0, 1)
        let tint = tintColor?.simd4 ?? SIMD4<Float>(1, 1, 1, 1)   // nil tint = the image unchanged
        let tl = imageVertex(x0, y0, 0, vTop, tint)
        let tr = imageVertex(x1, y0, 1, vTop, tint)
        let br = imageVertex(x1, y1, 1, vBot, tint)
        let bl = imageVertex(x0, y1, 0, vBot, tint)
        beginImageBatch(image)
        imageVertices.append(contentsOf: [tl, tr, br, tl, br, bl])
    }

    /// Draw a depth scene into `rect`: `color` is the backdrop and `depth` is a
    /// gray depth map (white = nearest by default) sampled per pixel and written to
    /// the depth buffer. After it, 2D placed at a normalized `depth(_:)` is occluded
    /// by the scene — the way a sprite is hidden by a nearer subject. Allocates the
    /// depth buffer (like a camera) with no 3D camera needed; raster only.
    func drawDepthScene(color: Image, depth: Image, in rect: Rectangle, whiteIsNear: Bool) {
        guard rect.width > 0, rect.height > 0,
              color.width > 0, color.height > 0, depth.width > 0, depth.height > 0 else { return }
        if svgRecorder != nil { return }   // a depth scene has no vector form
        hasDepthScene = true
        currentTarget?.needsDepth = true   // depth scene in a target → that pass carries depth
        let x0 = Float(rect.x), y0 = Float(rect.y)
        let x1 = Float(rect.x + rect.width), y1 = Float(rect.y + rect.height)
        let (vTop, vBot): (Float, Float) = color.flipsVertically ? (1, 0) : (0, 1)
        // The whiteIsNear flag rides in tint.r (the fragment reads it; the backdrop
        // color is drawn untinted), so no new per-batch field is needed.
        let flag = SIMD4<Float>(whiteIsNear ? 1 : 0, 0, 0, 0)
        let tl = imageVertex(x0, y0, 0, vTop, flag)
        let tr = imageVertex(x1, y0, 1, vTop, flag)
        let br = imageVertex(x1, y1, 1, vBot, flag)
        let bl = imageVertex(x0, y1, 0, vBot, flag)
        beginDepthSceneBatch(color: color, depth: depth, metricDepth: nil)
        imageVertices.append(contentsOf: [tl, tr, br, tl, br, bl])
    }

    /// Draw a *metric* depth scene from an `RGBDFrame`: `frame.color` is the backdrop
    /// and `frame.depth` (meters) is written into the depth buffer as true clip-space
    /// depth against the active camera's near/far — so 3D geometry placed at real
    /// world coordinates (`drawPointCloud`, `depth(at:)`) occludes and is occluded by
    /// the feed in one metric space. Needs an active camera (`Camera3D.fromIntrinsics`
    /// is the matching one); a no-op without one, or for SVG (no vector form). The
    /// backdrop is **letterboxed** into `rect` by the feed's aspect (no stretch),
    /// matching the metric camera's own letterbox so backdrop and placed geometry
    /// align. Raster only.
    func drawDepthScene(metricFrame frame: RGBDFrame, in rect: Rectangle) {
        guard rect.width > 0, rect.height > 0,
              frame.color.width > 0, frame.color.height > 0,
              frame.depthWidth > 0, frame.depthHeight > 0,
              frame.depth.count >= frame.depthWidth * frame.depthHeight else { return }
        guard let camera = camera3D else { return }   // metric depth needs near/far
        if svgRecorder != nil { return }
        hasDepthScene = true
        currentTarget?.needsDepth = true   // depth scene in a target → that pass carries depth
        // Map metric depth d → Metal NDC z ∈ [0,1] as ndc_z = P − Q/d, where
        // P = far/(far−near), Q = far·near/(far−near) (the perspective depth curve).
        // These ride in the quad's vertex tint so the fragment needs no extra buffer.
        let denom = camera.far - camera.near
        let p = denom != 0 ? camera.far / denom : 0
        let q = denom != 0 ? camera.far * camera.near / denom : 0
        // Letterbox the feed into `rect` by the intrinsics' aspect — the same fit the
        // metric camera applies in clip space, so the backdrop and the projected 3D
        // geometry land on the same pixels.
        let k = frame.intrinsics
        let fit = Rectangle(fitting: Vector2(Double(k.width), Double(k.height)), in: rect)
        let x0 = Float(fit.x), y0 = Float(fit.y)
        let x1 = Float(fit.x + fit.width), y1 = Float(fit.y + fit.height)
        let (vTop, vBot): (Float, Float) = frame.color.flipsVertically ? (1, 0) : (0, 1)
        // tint.a = 1 selects the metric branch (the normalized path leaves it 0);
        // tint.r/.g carry P/Q.
        let flag = SIMD4<Float>(Float(p), Float(q), 0, 1)
        let tl = imageVertex(x0, y0, 0, vTop, flag)
        let tr = imageVertex(x1, y0, 1, vTop, flag)
        let br = imageVertex(x1, y1, 1, vBot, flag)
        let bl = imageVertex(x0, y1, 0, vBot, flag)
        let carrier = MetricDepthMap(depth: frame.depth,
                                     width: frame.depthWidth, height: frame.depthHeight)
        beginDepthSceneBatch(color: frame.color, depth: nil, metricDepth: carrier)
        imageVertices.append(contentsOf: [tl, tr, br, tl, br, bl])
    }

    /// Open a fresh `.depthScene` batch carrying the color backdrop and either a
    /// normalized gray `depth` map or a `metricDepth` map (meters). Always appends
    /// (like `beginImageBatch`); resets `currentKind`.
    private func beginDepthSceneBatch(color: Image, depth: Image?, metricDepth: MetricDepthMap?) {
        currentKind = .depthScene
        currentBatchBlend = currentBlend
        currentBatchDepth = currentDepth
        batches.append(GeometryBatch(kind: .depthScene, vertexStart: vertices.count,
                                     instanceStart: sdfInstances.count,
                                     imageStart: imageVertices.count,
                                     glyphStart: glyphVertices.count,
                                     pointStart: points.count,
                                     meshStart: meshVertices.count,
                                     sdfGroupStart: sdfGroups.count,
                                     sdf3DGroupStart: sdf3DGroups.count,
                                     blendMode: currentBlend, image: color,
                                     depthImage: depth, metricDepth: metricDepth,
                                     target: currentTarget))
    }

    /// Build one textured-quad vertex, transforming its position by the current
    /// CTM (mirrors `emit` for the triangle path).
    private func imageVertex(_ x: Float, _ y: Float, _ u: Float, _ v: Float,
                             _ tint: SIMD4<Float>) -> OllinImageVertex {
        var position = SIMD2<Float>(x, y)
        if !transformIsIdentity {
            let p = transform * SIMD3<Float>(x, y, 1)
            position = SIMD2<Float>(p.x, p.y)
        }
        return OllinImageVertex(position: position, uv: SIMD2<Float>(u, v), tint: tint)
    }

    // MARK: Text

    /// Draw `string` at `(x, y)` using the active `textFont` / `textSize` /
    /// `textAlign`. `\n` starts a new line; text rides the transform stack and
    /// stays crisp at any size. A **bitmap** font stamps each lit pixel as a fill
    /// color square on the SDF path; an **outline** font draws each glyph as a
    /// vector `Shape`, so — like every other shape — it takes the current `fill`
    /// *and* an active `stroke` (call `noStroke()` for plain filled text, or
    /// `noFill()` for outline-only text); a **stroke** (single-line) font draws each
    /// glyph as open pen paths with the current `stroke` and no fill. Unknown
    /// characters advance the pen but draw nothing.
    func drawText(_ string: String, _ x: Double, _ y: Double) {
        guard textPixelSize > 0, !string.isEmpty else { return }
        switch currentFont {
        case .bitmap(let font):  drawBitmapText(string, x, y, font: font)
        case .outline(let font):
            // The atlas path is opt-in and raster, so SVG export keeps the vector
            // outline path; everything else honors `textMode`.
            if textRenderMode == .atlas, svgRecorder == nil {
                drawAtlasText(string, x, y, font: font)
            } else {
                drawOutlineText(string, x, y, font: font)
            }
        case .stroke(let font):  drawStrokeText(string, x, y, font: font)
        }
    }

    /// Stroke path: each glyph is a set of open pen polylines, drawn with the
    /// current `stroke` (weight, join, cap). Fill is ignored — the inverse of
    /// outline text.
    private func drawStrokeText(_ string: String, _ x: Double, _ y: Double, font: StrokeFont) {
        guard strokePaint != nil, strokeWidth > 0 else { return }
        forEachStrokeGlyphPolyline(string, x, y, font: font) { polyline in
            drawPolyline(polyline)
        }
    }

    /// Walk the pen polylines of `string`, laid out with the active text state,
    /// calling `body` with each polyline in canvas space. Shared by
    /// `drawStrokeText` and `textToShapes` so the stroke layout lives in one place.
    private func forEachStrokeGlyphPolyline(_ string: String, _ x: Double, _ y: Double,
                                            font: StrokeFont, _ body: ([Vector2]) -> Void) {
        guard font.unitsPerEm > 0 else { return }
        let scale = textPixelSize / font.unitsPerEm
        let ascent = font.ascentUnits * scale
        let descent = font.descentUnits * scale
        let leading = (font.ascent + font.descent + font.leading) * textPixelSize   // baseline-to-baseline
        let lines = string.split(separator: "\n", omittingEmptySubsequences: false)
        let blockHeight = Double(lines.count - 1) * leading + ascent + descent

        // First line's baseline, from the vertical anchor.
        let firstBaseline: Double
        switch textAlignV {
        case .top:      firstBaseline = y + ascent
        case .baseline: firstBaseline = y
        case .middle:   firstBaseline = y - blockHeight / 2 + ascent
        case .bottom:   firstBaseline = y - blockHeight + ascent
        }

        for (lineIndex, line) in lines.enumerated() {
            let baselineY = firstBaseline + Double(lineIndex) * leading
            let lineWidth = font.lineAdvanceUnits(of: line) * scale
            // Left edge of this line, from the horizontal anchor.
            var penX: Double
            switch textAlignH {
            case .left:   penX = x
            case .center: penX = x - lineWidth / 2
            case .right:  penX = x - lineWidth
            }
            for ch in line {
                if let glyph = font.glyph(for: ch) {
                    for polyline in glyph.polylines {
                        body(polyline.map { Vector2(penX + $0.x * scale, baselineY + $0.y * scale) })
                    }
                }
                penX += font.advanceUnits(for: ch) * scale
            }
        }
    }

    /// Bitmap path: one fill color square per lit pixel (see `forEachBitmapPixel`).
    private func drawBitmapText(_ string: String, _ x: Double, _ y: Double, font: BitmapFont) {
        guard let fill = fillPaint else { return }
        forEachBitmapPixel(string, x, y, font: font) { center, module in
            let half = SIMD2<Float>(Float(module / 2), Float(module / 2))
            // Fill-only square; opt out of hollow so a set band doesn't turn each
            // pixel into a ring.
            appendSDF(shape: .box, center: center, size: half,
                      fill: fill, stroke: nil, applyHollow: false)
        }
    }

    /// Outline path: each glyph fills (and strokes) like any other shape. The
    /// per-glyph flatten + triangulation are cached in local space and reused, so a
    /// redrawn label only translates cached vertices — the same geometry a
    /// `glyphShapes` + `drawShape` pass would emit, without re-tessellating every
    /// frame. SVG export keeps the `drawShape` path (its recorder wants `Shape`s).
    private func drawOutlineText(_ string: String, _ x: Double, _ y: Double, font: OutlineFont) {
        let hasFill = fillPaint != nil
        let hasStroke = strokePaint != nil && strokeWidth > 0
        guard hasFill || hasStroke else { return }

        if svgRecorder != nil {
            for shape in font.glyphShapes(for: string, size: textPixelSize,
                                          alignH: textAlignH, alignV: textAlignV, at: Vector2(x, y)) {
                drawShape(shape)
            }
            return
        }

        // One paint resolution for the whole run; an along-path fill sweeps
        // around the text anchor.
        let fillVP = fillPaint.map { vertexPaint($0, anchor: Vector2(x, y)) }
        let strokeVP = strokePaint.map { vertexPaint($0, anchor: Vector2(x, y)) }
        for glyph in font.placedGlyphs(for: string, size: textPixelSize,
                                       alignH: textAlignH, alignV: textAlignV, at: Vector2(x, y)) {
            let origin = glyph.origin
            if let vp = fillVP {
                let tri = glyph.localFill
                for i in stride(from: 0, to: tri.count - 2, by: 3) {
                    let p0 = tri[i] + origin
                    let p1 = tri[i + 1] + origin
                    let p2 = tri[i + 2] + origin
                    emit(p0.simd2, color: vp.color(at: p0))
                    emit(p1.simd2, color: vp.color(at: p1))
                    emit(p2.simd2, color: vp.color(at: p2))
                }
            }
            if hasStroke, let vp = strokeVP {
                let half = strokeWidth / 2
                for contour in glyph.localContours where contour.points.count >= 2 {
                    appendStrokedPath(contour.points.map { $0 + origin },
                                      closed: contour.isClosed, half: half, paint: vp)
                }
            }
        }
    }

    /// Atlas path (`textMode(.atlas)`): each glyph is one textured quad sampling
    /// the font's SDF atlas, so a paragraph costs a handful of vertex writes per
    /// glyph instead of a flatten + triangulation. Fill-only (the volume case is
    /// filled body text); the outline path keeps fill + stroke. The whole call is
    /// one batch — all glyphs share the atlas texture.
    private func drawAtlasText(_ string: String, _ x: Double, _ y: Double, font: OutlineFont) {
        guard let fill = fillPaint else { return }
        let placed = font.placedAtlasGlyphs(for: string, size: textPixelSize,
                                            alignH: textAlignH, alignV: textAlignV, at: Vector2(x, y))
        guard !placed.isEmpty else { return }

        // The tint carries the fill: per-corner for a gradient (glyph quads are
        // small, so corner interpolation tracks the paint), constant for a color.
        let vp = vertexPaint(fill, anchor: Vector2(x, y))
        beginGlyphBatch(font.atlas)
        for g in placed {
            guard let slot = font.atlas.slot(for: g.glyph, font: g.font) else { continue }   // space / unplaced
            // Cell rect (em, y-up) → canvas: x grows with em-x, canvas-y falls as
            // em-y rises (font y-up vs Ollin y-down).
            let left = Float(g.origin.x + slot.emLeft * textPixelSize)
            let right = Float(g.origin.x + slot.emRight * textPixelSize)
            let top = Float(g.origin.y - slot.emTop * textPixelSize)
            let bottom = Float(g.origin.y - slot.emBottom * textPixelSize)
            let tl = imageVertex(left, top, slot.u0, slot.v0,
                                 vp.color(at: Vector2(Double(left), Double(top))))
            let tr = imageVertex(right, top, slot.u1, slot.v0,
                                 vp.color(at: Vector2(Double(right), Double(top))))
            let br = imageVertex(right, bottom, slot.u1, slot.v1,
                                 vp.color(at: Vector2(Double(right), Double(bottom))))
            let bl = imageVertex(left, bottom, slot.u0, slot.v1,
                                 vp.color(at: Vector2(Double(left), Double(bottom))))
            glyphVertices.append(contentsOf: [tl, tr, br, tl, br, bl])
        }
    }

    /// Walk the lit pixels of `string`, laid out with the active text state,
    /// calling `body` with each pixel's center (canvas space) and module size (its
    /// on-screen side). Shared by `drawBitmapText` and `textToShapes` so the
    /// bitmap layout lives in one place.
    private func forEachBitmapPixel(_ string: String, _ x: Double, _ y: Double,
                                    font: BitmapFont, _ body: (Vector2, Double) -> Void) {
        guard font.pixelHeight > 0 else { return }
        let module = textPixelSize / Double(font.pixelHeight)
        let lines = string.split(separator: "\n", omittingEmptySubsequences: false)
        let blockHeight = Double((lines.count - 1) * font.lineHeight + font.pixelHeight) * module

        // First line's top edge, from the vertical anchor.
        let topY0: Double
        switch textAlignV {
        case .top:      topY0 = y
        case .baseline: topY0 = y - Double(font.baseline) * module
        case .middle:   topY0 = y - blockHeight / 2
        case .bottom:   topY0 = y - blockHeight
        }

        for (lineIndex, line) in lines.enumerated() {
            let lineTop = topY0 + Double(lineIndex * font.lineHeight) * module
            let lineWidth = Double(font.inkWidth(of: String(line))) * module
            // Left edge of this line, from the horizontal anchor.
            var penX: Double
            switch textAlignH {
            case .left:   penX = x
            case .center: penX = x - lineWidth / 2
            case .right:  penX = x - lineWidth
            }

            var previous: Character? = nil
            for ch in line {
                if let prev = previous { penX += Double(font.kerning(between: prev, ch)) * module }
                if let glyph = font.glyph(for: ch) {
                    let cellLeft = penX + Double(glyph.xOffset) * module
                    let cellTop = lineTop + Double(glyph.yOffset) * module
                    for row in 0..<glyph.height {
                        for col in 0..<glyph.width where glyph.isSet(col, row) {
                            let cx = cellLeft + (Double(col) + 0.5) * module
                            let cy = cellTop + (Double(row) + 0.5) * module
                            body(Vector2(cx, cy), module)
                        }
                    }
                }
                penX += Double(font.advance(for: ch)) * module
                previous = ch
            }
        }
    }

    /// The glyph geometry of `string` as `Shape`s positioned at `(x, y)` with the
    /// active `textFont` / `textSize` / `textAlign` — text as first-class geometry
    /// you can fill, stroke, warp, sample, or animate. An **outline** font returns
    /// one `Shape` per glyph (a letter with a counter keeps its hole); a **bitmap**
    /// font returns its lit pixels as little squares.
    func textToShapes(_ string: String, _ x: Double, _ y: Double) -> [Shape] {
        guard textPixelSize > 0, !string.isEmpty else { return [] }
        switch currentFont {
        case .outline(let font):
            return font.glyphShapes(for: string, size: textPixelSize,
                                    alignH: textAlignH, alignV: textAlignV, at: Vector2(x, y))
        case .bitmap(let font):
            var squares: [Contour] = []
            forEachBitmapPixel(string, x, y, font: font) { center, module in
                let h = module / 2
                squares.append(Contour([
                    Vector2(center.x - h, center.y - h), Vector2(center.x + h, center.y - h),
                    Vector2(center.x + h, center.y + h), Vector2(center.x - h, center.y + h),
                ], closed: true))
            }
            return squares.isEmpty ? [] : [Shape(contours: squares)]
        case .stroke(let font):
            // A stroke font's geometry is open pen polylines (no fill) — stroke
            // them, or warp and re-stroke.
            var strokes: [Contour] = []
            forEachStrokeGlyphPolyline(string, x, y, font: font) { polyline in
                strokes.append(Contour(polyline, closed: false))
            }
            return strokes.isEmpty ? [] : [Shape(contours: strokes)]
        }
    }

    /// The on-screen width of `string`'s widest line, in points, at the active
    /// `textFont` / `textSize` — for laying text out.
    func textWidth(_ string: String) -> Double {
        switch currentFont {
        case .bitmap(let font):
            guard font.pixelHeight > 0 else { return 0 }
            let module = textPixelSize / Double(font.pixelHeight)
            return Double(font.inkWidth(of: string)) * module
        case .outline(let font):
            return font.width(of: string, size: textPixelSize)
        case .stroke(let font):
            return font.width(of: string, size: textPixelSize)
        }
    }

    /// Distance from the baseline up to the top of the tallest glyphs, in points,
    /// at the active font and size.
    func textAscent() -> Double {
        switch currentFont {
        case .bitmap(let font):
            guard font.pixelHeight > 0 else { return 0 }
            return Double(font.baseline) * (textPixelSize / Double(font.pixelHeight))
        case .outline(let font):
            return font.ascent * textPixelSize
        case .stroke(let font):
            return font.ascent * textPixelSize
        }
    }

    /// Distance from the baseline down to the bottom of the lowest descenders, in
    /// points, at the active font and size.
    func textDescent() -> Double {
        switch currentFont {
        case .bitmap(let font):
            guard font.pixelHeight > 0 else { return 0 }
            let module = textPixelSize / Double(font.pixelHeight)
            return Double(font.pixelHeight - font.baseline) * module
        case .outline(let font):
            return font.descent * textPixelSize
        case .stroke(let font):
            return font.descent * textPixelSize
        }
    }

    /// The baseline-to-baseline distance for a new line, in points, at the active
    /// font and size (what `\n` advances by).
    func textLeading() -> Double {
        switch currentFont {
        case .bitmap(let font):
            guard font.pixelHeight > 0 else { return 0 }
            return Double(font.lineHeight) * (textPixelSize / Double(font.pixelHeight))
        case .outline(let font):
            return (font.ascent + font.descent + font.leading) * textPixelSize
        case .stroke(let font):
            return (font.ascent + font.descent + font.leading) * textPixelSize
        }
    }

    /// The bounding box `string` occupies if drawn at `(x, y)` with the active text
    /// state — width is the widest line, height spans the whole block.
    func textBounds(_ string: String, _ x: Double, _ y: Double) -> Rectangle {
        let w = textWidth(string)
        let ascent = textAscent(), descent = textDescent(), advance = textLeading()
        let lineCount = string.split(separator: "\n", omittingEmptySubsequences: false).count
        let blockHeight = Double(max(0, lineCount - 1)) * advance + ascent + descent
        let top: Double
        switch textAlignV {
        case .top:      top = y
        case .baseline: top = y - ascent
        case .middle:   top = y - blockHeight / 2
        case .bottom:   top = y - blockHeight
        }
        let left: Double
        switch textAlignH {
        case .left:   left = x
        case .center: left = x - w / 2
        case .right:  left = x - w
        }
        return Rectangle(x: left, y: top, width: w, height: blockHeight)
    }

    /// Draw `string` wrapped into `rect`: words break to the next line at the box
    /// width, and `textAlign` positions the wrapped block within the box —
    /// horizontal `.left`/`.center`/`.right` against the box edges, vertical
    /// `.top`/`.middle`/`.bottom`. Explicit `\n`s start new paragraphs. The text
    /// overflows below the box if it's too tall (no vertical clip yet).
    func drawText(_ string: String, in rect: Rectangle) {
        guard textPixelSize > 0, !string.isEmpty, rect.width > 0 else { return }
        let wrapped = wrapToWidth(string, rect.width)
        let anchorX: Double
        switch textAlignH {
        case .left:   anchorX = rect.x
        case .center: anchorX = rect.center.x
        case .right:  anchorX = rect.x + rect.width
        }
        let anchorY: Double
        switch textAlignV {
        case .top, .baseline: anchorY = rect.y   // a box anchors the block's top edge
        case .middle:         anchorY = rect.center.y
        case .bottom:         anchorY = rect.y + rect.height
        }
        drawText(wrapped, anchorX, anchorY)
    }

    /// Greedily break `string` into lines no wider than `maxWidth` at the current
    /// font/size, breaking on spaces (a word wider than the box keeps its own
    /// line). Existing `\n`s are kept as paragraph breaks. Returns the rewrapped
    /// string for the normal `drawText` to lay out.
    private func wrapToWidth(_ string: String, _ maxWidth: Double) -> String {
        var lines: [String] = []
        for paragraph in string.split(separator: "\n", omittingEmptySubsequences: false) {
            var current = ""
            for word in paragraph.split(separator: " ", omittingEmptySubsequences: true) {
                let candidate = current.isEmpty ? String(word) : current + " " + String(word)
                if current.isEmpty || textWidth(candidate) <= maxWidth {
                    current = candidate
                } else {
                    lines.append(current)
                    current = String(word)
                }
            }
            lines.append(current)
        }
        return lines.joined(separator: "\n")
    }

    /// Draw `string` glyph by glyph, handing each to `perGlyph` so you can give it
    /// its own transform or color before stamping it (`TextGlyph.draw()`). Laid out
    /// on a single line with the active `textFont` / `textSize` / `textAlign`; you
    /// do the drawing, so `fill` / `stroke` and any transform apply per glyph.
    func drawText(_ string: String, _ x: Double, _ y: Double, perGlyph: (TextGlyph) -> Void) {
        guard textPixelSize > 0, !string.isEmpty else { return }
        let run = glyphRun(string)
        guard !run.isEmpty else { return }

        let runWidth = (run.last?.penX ?? 0) + (run.last?.advance ?? 0)
        let startX: Double
        switch textAlignH {
        case .left:   startX = x
        case .center: startX = x - runWidth / 2
        case .right:  startX = x - runWidth
        }
        let ascent = textAscent(), descent = textDescent()
        let baselineY: Double
        switch textAlignV {
        case .top:      baselineY = y + ascent
        case .baseline: baselineY = y
        case .middle:   baselineY = y + (ascent - descent) / 2
        case .bottom:   baselineY = y - descent
        }
        // A stroke font's glyph geometry is open pen paths: stroke them rather than
        // fill (the same split `drawText` makes between the font kinds).
        let strokesGlyphs = currentFont.isStroke

        for (index, item) in run.enumerated() {
            let origin = Vector2(startX + item.penX, baselineY)
            let shapes = item.localShapes.map { shifted($0, by: origin) }
            let bounds = Rectangle(x: origin.x, y: origin.y - ascent,
                                   width: item.advance, height: ascent + descent)
            let glyph = TextGlyph(character: item.character, index: index, count: run.count,
                                  position: origin, bounds: bounds, shapes: shapes,
                                  drawThunk: { [weak self] in
                                      guard let self else { return }
                                      if strokesGlyphs {
                                          shapes.forEach { $0.contours.forEach { self.drawPolyline($0.points) } }
                                      } else {
                                          shapes.forEach { self.drawShape($0) }
                                      }
                                  })
            perGlyph(glyph)
        }
    }

    /// Draw `string` with its glyphs riding `path`: each glyph is centered on the
    /// point `offset + (its distance along the run)` measured as arc length from the
    /// path's start, and rotated to the path's tangent there (its baseline sits on
    /// the curve). Glyphs that fall before the start or past the end are skipped, so
    /// animating `offset` flows the text on and off the ends. Single-line; takes
    /// `fill` and `stroke` like `drawText`.
    func drawText(_ string: String, along path: Path, offset: Double) {
        guard textPixelSize > 0, !string.isEmpty else { return }
        guard fillPaint != nil || (strokePaint != nil && strokeWidth > 0) else { return }
        let run = glyphRun(string)
        let points = path.contour.points
        guard run.count > 0, points.count >= 2 else { return }

        // Cumulative arc length along the flattened path.
        var cumulative: [Double] = [0]
        cumulative.reserveCapacity(points.count)
        for i in 1..<points.count { cumulative.append(cumulative[i - 1] + (points[i] - points[i - 1]).length) }
        let total = cumulative.last ?? 0
        guard total > 0 else { return }
        let strokesGlyphs = currentFont.isStroke   // stroke open pen paths, don't fill

        for item in run {
            let distance = offset + item.penX + item.advance / 2
            guard distance >= 0, distance <= total else { continue }   // off the path: skip
            let (anchor, angle) = pointAndTangent(points: points, cumulative: cumulative, at: distance)
            let cosA = cos(angle), sinA = sin(angle)
            for shape in item.localShapes {
                let placed = shape.mapPoints { q in
                    // Center the glyph on its anchor, then rotate to the tangent.
                    let lx = q.x - item.advance / 2
                    let ly = q.y
                    return Vector2(anchor.x + lx * cosA - ly * sinA,
                                   anchor.y + lx * sinA + ly * cosA)
                }
                if strokesGlyphs {
                    placed.contours.forEach { drawPolyline($0.points) }
                } else {
                    drawShape(placed)
                }
            }
        }
    }

    /// The point and tangent angle at arc-length `distance` along a flattened path.
    private func pointAndTangent(points: [Vector2], cumulative: [Double],
                                 at distance: Double) -> (Vector2, Double) {
        let d = min(max(distance, 0), cumulative.last ?? 0)
        var i = 1
        while i < cumulative.count, cumulative[i] < d { i += 1 }
        guard i < points.count else {
            let dir = points[points.count - 1] - points[points.count - 2]
            return (points[points.count - 1], atan2(dir.y, dir.x))
        }
        let segmentLength = cumulative[i] - cumulative[i - 1]
        let t = segmentLength > 0 ? (d - cumulative[i - 1]) / segmentLength : 0
        let a = points[i - 1], b = points[i]
        let dir = b - a
        return (a + dir * t, atan2(dir.y, dir.x))
    }

    /// The active font's single-line glyph run (see `GlyphRunItem`), dispatched on
    /// the font kind.
    private func glyphRun(_ string: String) -> [GlyphRunItem] {
        switch currentFont {
        case .outline(let font): return font.glyphRun(for: string, size: textPixelSize)
        case .bitmap(let font):  return bitmapGlyphRun(string, font: font)
        case .stroke(let font):  return strokeGlyphRun(string, font: font)
        }
    }

    /// A stroke font's single-line glyph run — each glyph's pen polylines as local
    /// open `Contour`s (pen origin at the origin, baseline at `y = 0`).
    private func strokeGlyphRun(_ string: String, font: StrokeFont) -> [GlyphRunItem] {
        guard font.unitsPerEm > 0, textPixelSize > 0 else { return [] }
        let scale = textPixelSize / font.unitsPerEm
        var items: [GlyphRunItem] = []
        var penX = 0.0
        for ch in string.replacingOccurrences(of: "\n", with: " ") {
            var contours: [Contour] = []
            if let glyph = font.glyph(for: ch) {
                for polyline in glyph.polylines {
                    contours.append(Contour(polyline.map { Vector2($0.x * scale, $0.y * scale) }, closed: false))
                }
            }
            let advance = font.advanceUnits(for: ch) * scale
            items.append(GlyphRunItem(character: ch, penX: penX, advance: advance,
                                      localShapes: contours.isEmpty ? [] : [Shape(contours: contours)]))
            penX += advance
        }
        return items
    }

    /// A bitmap font's single-line glyph run — each glyph's lit pixels as local
    /// square `Contour`s (pen origin at the origin, baseline at `y = 0`).
    private func bitmapGlyphRun(_ string: String, font: BitmapFont) -> [GlyphRunItem] {
        guard font.pixelHeight > 0, textPixelSize > 0 else { return [] }
        let module = textPixelSize / Double(font.pixelHeight)
        let baselineLocal = Double(font.baseline) * module
        var items: [GlyphRunItem] = []
        var penX = 0.0
        var previous: Character? = nil
        for ch in string.replacingOccurrences(of: "\n", with: " ") {
            if let prev = previous { penX += Double(font.kerning(between: prev, ch)) * module }
            var squares: [Contour] = []
            if let glyph = font.glyph(for: ch) {
                let cellLeft = Double(glyph.xOffset) * module
                let cellTop = Double(glyph.yOffset) * module - baselineLocal   // baseline at y = 0
                for row in 0..<glyph.height {
                    for col in 0..<glyph.width where glyph.isSet(col, row) {
                        let cx = cellLeft + (Double(col) + 0.5) * module
                        let cy = cellTop + (Double(row) + 0.5) * module
                        let h = module / 2
                        squares.append(Contour([Vector2(cx - h, cy - h), Vector2(cx + h, cy - h),
                                                Vector2(cx + h, cy + h), Vector2(cx - h, cy + h)], closed: true))
                    }
                }
            }
            let advance = Double(font.advance(for: ch)) * module
            items.append(GlyphRunItem(character: ch, penX: penX, advance: advance,
                                      localShapes: squares.isEmpty ? [] : [Shape(contours: squares)]))
            penX += advance
            previous = ch
        }
        return items
    }

    /// A `Shape` with every contour point shifted by `offset` (winding preserved).
    private func shifted(_ shape: Shape, by offset: Vector2) -> Shape {
        shape.mapPoints { $0 + offset }
    }

    /// A straight line segment from `a` to `b`, stroked with the current stroke
    /// paint and weight. Rendered through the high-quality fringe expander — edge-
    /// expanded triangles plus a ~1px AA fringe — so it's crisp at any angle and
    /// resolution, honoring `strokeCap` (`.butt` by default). Solid, translucent,
    /// and gradient strokes all take this path. Needs a stroke to draw.
    func drawLine(_ a: Vector2, _ b: Vector2) {
        guard let stroke = strokePaint, strokeWidth > 0 else { return }
        if svgRecorder != nil {
            svgRecord(.line(a, b), fill: nil, stroke: stroke)
            return
        }
        guard (b - a).length > 1e-9 else { return }
        appendFringeStroke([a, b], closed: false, paint: vertexPaint(stroke, anchor: (a + b) / 2))
    }

    /// A rectangle whose long axis runs from `a` to `b` with the given `thickness`
    /// across it — a thick bar between two points, with square (not round) ends.
    /// Unlike `drawRect`, which is axis-aligned and rotated via the transform stack,
    /// this places the bar by its two endpoints, so connecting a pair of moving
    /// points is one call. It's a filled region (takes `fill`, an outline `stroke`,
    /// `strokeAlign`, and `hollow`), where `drawLine` is a round-capped stroke.
    /// Recorded as a single analytic SDF instance — crisp at any size and
    /// effectively free. A zero-length bar (`a == b`) or non-positive thickness
    /// draws nothing.
    func drawOrientedBox(_ a: Vector2, _ b: Vector2, thickness: Double) {
        guard thickness > 0, (b - a).length > 1e-9 else { return }
        let center = (a + b) / 2
        let dir = (b - a) / (b - a).length
        let halfLen = (b - a).length / 2
        let halfThick = thickness / 2
        // AABB half-extent of the rotated box: each axis is reached by the
        // corner that combines the box's half-length along `dir` and half-thickness
        // along the perpendicular (|perp.x| == |dir.y|, |perp.y| == |dir.x|).
        let half = SIMD2<Float>(
            Float(halfLen * abs(dir.x) + halfThick * abs(dir.y)),
            Float(halfLen * abs(dir.y) + halfThick * abs(dir.x)))
        if svgRecorder != nil {
            let perp = Vector2(-dir.y, dir.x)
            let along = dir * halfLen, across = perp * halfThick
            svgRecord(.polygon([center + along + across, center + along - across,
                                center - along - across, center - along + across]),
                      fill: fillPaint, stroke: strokePaint)
            return
        }
        appendSDF(shape: .orientedBox, center: center, size: half,
                  fill: fillPaint, stroke: strokePaint, extra: Float(thickness),
                  param0: (a - center).simd2, param1: (b - center).simd2)
    }

    /// An oriented box through scalar endpoint coordinates — the positional form of
    /// `drawOrientedBox(_:_:thickness:)`: the centerline from `(x1, y1)` to `(x2, y2)`.
    func drawOrientedBox(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, thickness: Double) {
        drawOrientedBox(Vector2(x1, y1), Vector2(x2, y2), thickness: thickness)
    }

    /// A vesica (a pointed lens) whose two tips are placed at `a` and `b`, bulging
    /// to `width` across the middle. Like `drawOrientedBox`, it's positioned by its
    /// two endpoints rather than a center and rotation, so spanning a moving pair of
    /// points is one call. It's a filled region (takes `fill`, an outline `stroke`,
    /// `strokeAlign`, and `hollow`). `width` is the full waist width; keeping it
    /// below the tip distance gives a lens, equal to it gives a circle. A zero-length
    /// span (`a == b`) or non-positive width draws nothing. Recorded as a single
    /// analytic SDF instance — crisp at any size and effectively free.
    func drawOrientedVesica(_ a: Vector2, _ b: Vector2, width: Double) {
        guard width > 0, (b - a).length > 1e-9 else { return }
        let center = (a + b) / 2
        let dir = (b - a) / (b - a).length
        let halfLen = (b - a).length / 2
        let halfWidth = width / 2
        // The lens is inscribed in the oriented box of half-length `halfLen` (along
        // the tip axis) and half-width `halfWidth` (across it), so its AABB is the
        // same as that box's (see drawOrientedBox).
        let half = SIMD2<Float>(
            Float(halfLen * abs(dir.x) + halfWidth * abs(dir.y)),
            Float(halfLen * abs(dir.y) + halfWidth * abs(dir.x)))
        if svgRecorder != nil {
            let perp = Vector2(-dir.y, dir.x)
            let local = SDFOutline.orientedVesica(halfLength: halfLen, halfWidth: halfWidth)
            svgRecord(.polygon(local.map { center + dir * $0.x + perp * $0.y }),
                      fill: fillPaint, stroke: strokePaint)
            return
        }
        appendSDF(shape: .orientedVesica, center: center, size: half,
                  fill: fillPaint, stroke: strokePaint, extra: Float(halfWidth),
                  param0: (a - center).simd2, param1: (b - center).simd2)
    }

    /// An oriented vesica through scalar tip coordinates — the positional form of
    /// `drawOrientedVesica(_:_:width:)`: tips at `(x1, y1)` and `(x2, y2)`.
    func drawOrientedVesica(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, width: Double) {
        drawOrientedVesica(Vector2(x1, y1), Vector2(x2, y2), width: width)
    }

    /// A quadratic Bézier curve stroked with the current stroke paint and weight:
    /// from `start` to `end`, bending toward the single control point `control`.
    /// The curve flattens to a polyline and renders through the high-quality fringe
    /// expander — smooth at any angle and resolution, no tessellated fill or SDF.
    /// Solid, translucent, and gradient strokes all take this path. Stroke-only: a
    /// curve has no interior, so it takes the current stroke (not fill). For a cubic
    /// curve (two control points), sample it into a `Shape` contour. Needs a stroke
    /// to draw.
    func drawBezier(_ start: Vector2, _ control: Vector2, _ end: Vector2) {
        guard let stroke = strokePaint, strokeWidth > 0 else { return }
        if svgRecorder != nil {
            svgRecord(.quad(start: start, control: control, end: end), fill: nil, stroke: stroke)
            return
        }
        var pts = [start]
        pts.append(contentsOf: CurveSampling.quadratic(from: start, control: control, end: end))
        appendFringeStroke(pts, closed: false, paint: vertexPaint(stroke, anchor: (start + end) / 2))
    }

    /// A quadratic Bézier curve through scalar coordinates — the positional form of
    /// `drawBezier(_:_:_:)`: `(x1, y1)` start, `(cx, cy)` control, `(x2, y2)` end.
    func drawBezier(_ x1: Double, _ y1: Double, _ cx: Double, _ cy: Double,
                    _ x2: Double, _ y2: Double) {
        drawBezier(Vector2(x1, y1), Vector2(cx, cy), Vector2(x2, y2))
    }

    /// A filled, **convex** polygon through `points` (triangle fan), plus a
    /// stroked closed outline if a stroke is set. The fan only fills correctly
    /// for convex inputs (triangles, quads, regular n-gons, convex pieces); for
    /// concave outlines or holes, build a `Shape` and use `drawShape`, which
    /// triangulates properly.
    func drawPolygon(_ points: [Vector2]) {
        guard points.count >= 3 else { return }
        if svgRecorder != nil {
            svgRecord(.polygon(points), fill: fillPaint, stroke: strokePaint)
            return
        }
        if let fill = fillPaint {
            let vp = vertexPaint(fill, anchor: Drawer.boundsCenter(points))
            let p0 = points[0].simd2
            let c0 = vp.color(at: points[0])
            for i in 1..<(points.count - 1) {        // fan from the first vertex
                emit(p0, color: c0)
                emit(points[i].simd2, color: vp.color(at: points[i]))
                emit(points[i + 1].simd2, color: vp.color(at: points[i + 1]))
            }
        }
        if let stroke = strokePaint, strokeWidth > 0 {
            appendFringeStroke(points, closed: true,
                               paint: vertexPaint(stroke, anchor: Drawer.boundsCenter(points)))
        }
    }

    /// A vector `Shape`: a filled region that may be **concave** and may have
    /// **holes**, plus a stroked outline of each contour. The fill is
    /// triangulated (even-odd winding, so nested contours cut holes); open
    /// contours are stroke-only. Both fill and stroke go through the triangle
    /// path, so a `Shape` composites in draw order with everything else.
    func drawShape(_ shape: Shape) {
        if svgRecorder != nil {
            svgRecord(.path(shape), fill: fillPaint, stroke: strokePaint)
            return
        }
        if let fill = fillPaint {
            let vp = vertexPaint(fill, anchor: Drawer.boundsCenter(shape.contours.flatMap(\.points)))
            let triangles = shape.triangulatedFill()
            for i in stride(from: 0, to: triangles.count - 2, by: 3) {
                emit(triangles[i].simd2, color: vp.color(at: triangles[i]))
                emit(triangles[i + 1].simd2, color: vp.color(at: triangles[i + 1]))
                emit(triangles[i + 2].simd2, color: vp.color(at: triangles[i + 2]))
            }
        }
        if let stroke = strokePaint, strokeWidth > 0 {
            for contour in shape.contours where contour.points.count >= 2 {
                appendFringeStroke(contour.points, closed: contour.isClosed,
                                   paint: vertexPaint(stroke, anchor: contour.points[0]))
            }
        }
    }

    // MARK: Tessellation helpers

    /// A paint resolved for CPU-side, per-vertex evaluation on the tessellated
    /// path. A solid paint returns its constant; a gradient samples its baked
    /// LUT row at the vertex position (linear/radial) or path parameter
    /// (along-path), so the tessellated path paints the same colors the SDF
    /// fragment derives analytically.
    private enum VertexPaint {
        case solid(SIMD4<Float>)
        case linear(origin: Vector2, dir: Vector2, invLen2: Double, baked: BakedGradient)
        case radial(center: Vector2, invRadius: Double, baked: BakedGradient)
        /// Along-path paint: stroked paths pass their arc-length fraction; fills
        /// (no path parameter) sweep once around `center`, matching the SDF
        /// fragment's conic fallback.
        case along(center: Vector2, baked: BakedGradient)

        var isGradient: Bool {
            if case .solid = self { return false }
            return true
        }

        /// The paint color at a vertex position.
        func color(at p: Vector2) -> SIMD4<Float> {
            switch self {
            case .solid(let c):
                return c
            case .linear(let origin, let dir, let invLen2, let baked):
                return baked.sample(((p.x - origin.x) * dir.x + (p.y - origin.y) * dir.y) * invLen2)
            case .radial(let center, let invRadius, let baked):
                return baked.sample((p - center).length * invRadius)
            case .along(let center, let baked):
                // Conic sweep: 0 at 12 o'clock, increasing clockwise (y-down) —
                // the same wrap the SDF fragment computes.
                let raw = atan2(p.x - center.x, -(p.y - center.y)) / Double.tau
                return baked.sample(raw - raw.rounded(.down))
            }
        }

        /// The paint color for a stroked-path vertex: along-path paint reads the
        /// arc-length fraction `t`; the others read the position like a fill.
        func color(at p: Vector2, pathT t: Double) -> SIMD4<Float> {
            if case .along(_, let baked) = self { return baked.sample(t) }
            return color(at: p)
        }
    }

    /// Resolve `paint` for per-vertex evaluation. `anchor` is the center an
    /// along-path gradient sweeps around when the geometry has no path parameter
    /// (a fill's conic fallback); it's only evaluated in that case.
    private func vertexPaint(_ paint: Paint, anchor: @autoclosure () -> Vector2) -> VertexPaint {
        switch paint {
        case .color(let c):
            return .solid(c.simd4)
        case .gradient(let g):
            let baked = gradientRow(for: g.ramp).baked
            switch g.geometry {
            case .linear(let start, let end):
                let d = end - start
                let len2 = max(d.x * d.x + d.y * d.y, 1e-12)
                return .linear(origin: start, dir: d, invLen2: 1 / len2, baked: baked)
            case .radial(let center, let radius):
                return .radial(center: center, invRadius: 1 / max(radius, 1e-6), baked: baked)
            case .alongPath:
                return .along(center: anchor(), baked: baked)
            }
        }
    }

    /// The center of `points`' bounding box — the conic anchor for an
    /// along-path fill on tessellated geometry.
    private static func boundsCenter(_ points: [Vector2]) -> Vector2 {
        guard let first = points.first else { return .zero }
        var lo = first, hi = first
        for p in points.dropFirst() {
            lo = Vector2(min(lo.x, p.x), min(lo.y, p.y))
            hi = Vector2(max(hi.x, p.x), max(hi.y, p.y))
        }
        return (lo + hi) / 2
    }

    /// Append one tessellated vertex, transformed by the current CTM. Every
    /// triangle primitive funnels through here, so the transform applies
    /// uniformly and the vertex joins the current triangle batch. `aa` is left
    /// zero — the triangle pipeline ignores it (only the fringe pipeline reads it).
    private func emit(_ position: SIMD2<Float>, color: SIMD4<Float>) {
        ensureBatch(.triangles)
        guard !transformIsIdentity else {
            vertices.append(OllinVertex(position: position, color: color))
            return
        }
        let p = transform * SIMD3<Float>(position.x, position.y, 1)
        vertices.append(OllinVertex(position: SIMD2<Float>(p.x, p.y), color: color))
    }

    /// The current CTM's average linear scale (canvas units → post-transform units),
    /// used to keep the AA fringe ~1px on screen regardless of zoom: a fringe of
    /// `1/ctmScale` local units becomes ~1px after the transform. Exact for
    /// uniform scale + rotation (the common case); approximate under non-uniform
    /// scale/skew (documented limitation).
    private var ctmScale: Double {
        guard !transformIsIdentity else { return 1 }
        let c0 = transform.columns.0, c1 = transform.columns.1
        let sx = (c0.x * c0.x + c0.y * c0.y).squareRoot()
        let sy = (c1.x * c1.x + c1.y * c1.y).squareRoot()
        return max(Double(sx + sy) / 2, 1e-6)
    }

    /// Append one fringe-stroke vertex (CTM-transformed) into `vertices` under a
    /// `.fringe` batch. The AA coverage rides in `aa.x` (its own interpolant the
    /// fringe fragment remaps to perceptual alpha), while `color` carries the
    /// stroke's rgb and its own paint alpha — the two kept separate so a translucent
    /// stroke composites at its true opacity.
    private func emitFringe(_ position: SIMD2<Float>, cov: Float, color: SIMD4<Float>) {
        ensureBatch(.fringe)
        let aa = SIMD2<Float>(cov, 0)
        if transformIsIdentity {
            vertices.append(OllinVertex(position: position, aa: aa, color: color))
        } else {
            let p = transform * SIMD3<Float>(position.x, position.y, 1)
            vertices.append(OllinVertex(position: SIMD2<Float>(p.x, p.y), aa: aa, color: color))
        }
    }

    /// Stroke a polyline (or closed loop) as edge-expanded triangles plus a
    /// screen-space ~1px anti-aliasing fringe — the technique behind the smooth
    /// `drawLine`/`drawBezier`/polyline lines (no SDF/fwidth, no supersampling: the
    /// AA is carried in the geometry). Each segment is its own butt-ended quad with
    /// a fringe band on each long edge whose coverage ramps 1→0, GPU-interpolated so
    /// the edge stays smooth at any angle. The fringe straddles the true edge so
    /// perceived width = `strokeWidth`, and is ~1px in screen space (`fw = 1/ctmScale`).
    /// Interior vertices fill the outer gap per `strokeJoin` (`.miter` — bevelling past
    /// the miter limit — / `.bevel` / `.round`); the inner side is covered by the
    /// segments' overlap. Open ends take the `strokeCap` style.
    ///
    /// The whole stroke path runs through here — solid, translucent, and gradient. The
    /// paint is sampled per path vertex (`cols[i]`) exactly like the tessellated path
    /// (along-path reads the arc-length fraction, the rest read position) and rides in
    /// each vertex's `color` (rgb + paint alpha), constant across the stroke width; a
    /// gradient first splits long segments so the baked LUT is tracked. The AA coverage
    /// rides separately in `aa.x`, so the fragment can keep the paint alpha linear while
    /// remapping only the coverage perceptually.
    private func appendFringeStroke(_ points: [Vector2], closed: Bool, paint: VertexPaint) {
        // Drop repeated points (a zero-length segment has no direction) and a
        // closed loop's closing duplicate, so every join is well-defined.
        var pts: [Vector2] = []
        for p in points where (pts.last.map { ($0 - p).length > 1e-9 } ?? true) { pts.append(p) }
        if closed, pts.count > 1, (pts[0] - pts[pts.count - 1]).length <= 1e-9 { pts.removeLast() }
        // A gradient varies along the run, so split long segments first (like the
        // tessellated path) — the per-vertex color samples the baked LUT densely
        // instead of interpolating straight through its stops. Solid strokes are
        // untouched, so their geometry is unchanged.
        if paint.isGradient { pts = Drawer.subdivided(pts, closed: closed, maxLength: 12) }
        let n = pts.count
        guard n >= 2 else { return }

        let hw = strokeWidth / 2
        let fw = 1.0 / ctmScale                 // ~1px AA fringe in screen space
        let outerHalf = hw + fw / 2
        let coreHalf = max(0, hw - fw / 2)
        let miterLimit = 8.0

        // Per-vertex paint color (rgb + the paint's own alpha). Along-path reads the
        // arc-length fraction; the rest read the position — matching the tessellated
        // path. Constant across the stroke width (a stroke's gradient runs along it).
        var cols = [SIMD4<Float>](repeating: .zero, count: n)
        if case .solid(let c) = paint {
            for i in 0..<n { cols[i] = c }
        } else {
            var cum = [Double](repeating: 0, count: n)
            for i in 1..<n { cum[i] = cum[i - 1] + (pts[i] - pts[i - 1]).length }
            var total = cum[n - 1]
            if closed { total += (pts[0] - pts[n - 1]).length }
            for i in 0..<n {
                cols[i] = paint.color(at: pts[i], pathT: total > 0 ? cum[i] / total : 0)
            }
        }

        // Coverage vs. distance from the centerline: 1 in the solid core, ramping to
        // 0 across the outer fringe (and < 1 at the center for a sub-pixel stroke, so
        // thin lines fade by width instead of snapping to a 1px floor).
        func covU(_ off: Double) -> Float { Float(min(max((outerHalf - abs(off)) / fw, 0), 1)) }
        let offs = [outerHalf, coreHalf, -coreHalf, -outerHalf]
        let centerCov = covU(0), coreCov = covU(coreHalf)

        func segDir(_ a: Vector2, _ b: Vector2) -> Vector2 {
            let d = b - a; let l = d.length
            return l > 1e-9 ? d / l : Vector2(1, 0)
        }
        func leftNormal(_ d: Vector2) -> Vector2 { Vector2(-d.y, d.x) }

        // A fringe vertex: position, AA coverage, and the path color at this point.
        typealias FV = (SIMD2<Float>, Float, SIMD4<Float>)
        func tri(_ a: FV, _ b: FV, _ d: FV) {
            emitFringe(a.0, cov: a.1, color: a.2)
            emitFringe(b.0, cov: b.1, color: b.2)
            emitFringe(d.0, cov: d.1, color: d.2)
        }
        func quad(_ a: FV, _ b: FV, _ d: FV, _ e: FV) { tri(a, b, d); tri(a, d, e) }
        // A cross-section at `p` along `perp` in path vertex `i`'s color, coverage
        // scaled by `s` (1 on the line, 0 at a length-fringe tip so butt/square ends
        // fade out across the fringe).
        func crossAt(_ p: Vector2, _ perp: Vector2, _ s: Float, _ col: SIMD4<Float>) -> [FV] {
            offs.map { ((p + perp * $0).simd2, covU($0) * s, col) }
        }
        // Connect two cross-sections into 3 quad bands (outer-fringe | core | outer-fringe).
        func ribbon(_ a: [FV], _ b: [FV]) { for k in 0..<3 { quad(a[k], b[k], b[k + 1], a[k + 1]) } }

        // Body: each segment is its own butt-ended fringe quad along its perpendicular,
        // its two ends carrying their path vertices' colors (the GPU interpolates).
        let segCount = closed ? n : n - 1
        for i in 0..<segCount {
            let j = (i + 1) % n
            let perp = leftNormal(segDir(pts[i], pts[j]))
            ribbon(crossAt(pts[i], perp, 1, cols[i]), crossAt(pts[j], perp, 1, cols[j]))
        }

        // Interior joins: fill the outer gap between the two segment quads at each
        // shared vertex (the inner side is covered by their overlap). The join style
        // honors `strokeJoin`; `.miter` bevels past the miter limit so an acute corner
        // doesn't spike. The whole join takes the corner vertex's color.
        let joins = closed ? Array(0..<n) : Array(1..<(n - 1))
        for v in joins {
            let prev = pts[(v - 1 + n) % n], curr = pts[v], next = pts[(v + 1) % n]
            let d0 = segDir(prev, curr), d1 = segDir(curr, next)
            let cross = d0.x * d1.y - d0.y * d1.x
            guard abs(cross) > 1e-6 else { continue }       // collinear: no gap to fill
            let p0 = leftNormal(d0), p1 = leftNormal(d1)
            let side: Double = cross >= 0 ? -1 : 1          // outer side of the turn
            let col = cols[v]
            let center:  FV = (curr.simd2, centerCov, col)
            let inCore:  FV = ((curr + p0 * (side * coreHalf)).simd2, coreCov, col)
            let inEdge:  FV = ((curr + p0 * (side * outerHalf)).simd2, 0, col)
            let outCore: FV = ((curr + p1 * (side * coreHalf)).simd2, coreCov, col)
            let outEdge: FV = ((curr + p1 * (side * outerHalf)).simd2, 0, col)
            func bevel() {
                tri(center, inCore, outCore)                // inner core wedge
                quad(inCore, inEdge, outEdge, outCore)      // fringe band across the bevel
            }
            func miter() -> Bool {
                let b = p0 + p1, bl = b.length
                let cosHalf = bl > 1e-6 ? (b.x * p0.x + b.y * p0.y) / bl : 0
                guard cosHalf > 1e-4, 1 / cosHalf <= miterLimit else { return false }
                let m = b / bl                              // unit bisector of the normals
                let miterCore: FV = ((curr + m * (side * coreHalf / cosHalf)).simd2, coreCov, col)
                let miterEdge: FV = ((curr + m * (side * outerHalf / cosHalf)).simd2, 0, col)
                tri(center, inCore, miterCore); tri(center, miterCore, outCore)
                quad(inCore, inEdge, miterEdge, miterCore)
                quad(miterCore, miterEdge, outEdge, outCore)
                return true
            }
            func roundJoin() {
                let oa = p0 * side, ob = p1 * side          // unit outward dirs to the corners
                let a0 = atan2(oa.y, oa.x)
                let sweep = atan2(oa.x * ob.y - oa.y * ob.x, oa.x * ob.x + oa.y * ob.y)
                let steps = max(1, Int((abs(sweep) / (2 * .pi)
                                        * Double(circleSegments(for: outerHalf))).rounded(.up)))
                var prevD = oa
                for s in 1...steps {
                    let ang = a0 + sweep * Double(s) / Double(steps)
                    let curD = Vector2(cos(ang), sin(ang))
                    let inA: FV = ((curr + prevD * coreHalf).simd2, coreCov, col)
                    let inB: FV = ((curr + curD  * coreHalf).simd2, coreCov, col)
                    let edA: FV = ((curr + prevD * outerHalf).simd2, 0, col)
                    let edB: FV = ((curr + curD  * outerHalf).simd2, 0, col)
                    tri(center, inA, inB)                   // core fan wedge
                    quad(inA, edA, edB, inB)                // fringe band along the arc
                    prevD = curD
                }
            }
            switch strokeJoinStyle {
            case .round: roundJoin()
            case .bevel: bevel()
            case .miter: if !miter() { bevel() }
            }
        }

        // Caps on the two open ends (honor strokeCap; ends fade over the fringe).
        guard !closed else { return }
        func cap(at p: Vector2, perp: Vector2, outward: Vector2, _ col: SIMD4<Float>) {
            switch strokeCapStyle {
            case .butt:
                ribbon(crossAt(p, perp, 1, col), crossAt(p + outward * fw, perp, 0, col))
            case .square:
                let tip = p + outward * hw
                ribbon(crossAt(p, perp, 1, col), crossAt(tip, perp, 1, col))
                ribbon(crossAt(tip, perp, 1, col), crossAt(tip + outward * fw, perp, 0, col))
            case .round:
                let steps = max(4, Int((outerHalf * ctmScale).rounded()))
                let base = atan2(perp.y, perp.x)
                let rot90 = Vector2(-perp.y, perp.x)
                let sweep: Double = (outward.x * rot90.x + outward.y * rot90.y) >= 0 ? 1 : -1
                for s in 0..<steps {
                    let aθ = base + .pi * (Double(s) / Double(steps)) * sweep
                    let bθ = base + .pi * (Double(s + 1) / Double(steps)) * sweep
                    let da = Vector2(cos(aθ), sin(aθ)), db = Vector2(cos(bθ), sin(bθ))
                    let inA: FV = ((p + da * coreHalf).simd2, coreCov, col), inB: FV = ((p + db * coreHalf).simd2, coreCov, col)
                    let edA: FV = ((p + da * outerHalf).simd2, 0, col), edB: FV = ((p + db * outerHalf).simd2, 0, col)
                    tri((p.simd2, centerCov, col), inA, inB)
                    quad(inA, edA, edB, inB)
                }
            }
        }
        let d0 = segDir(pts[0], pts[1]), dL = segDir(pts[n - 2], pts[n - 1])
        cap(at: pts[0], perp: leftNormal(d0), outward: d0 * -1, cols[0])
        cap(at: pts[n - 1], perp: leftNormal(dL), outward: dL, cols[n - 1])
    }

    /// Pick a vertex count that keeps each edge segment ≲ 8 points long, so big
    /// circles stay smooth and small ones stay cheap. With 4× MSAA smoothing the
    /// edges, an 8-point chord is visually indistinguishable from a finer one at
    /// these sizes, for roughly half the tessellated vertices.
    private func circleSegments(for radius: Double) -> Int {
        let targetEdgeLength = 8.0
        let circumference = 2.0 * .pi * radius
        return max(24, Int((circumference / targetEdgeLength).rounded(.up)))
    }

    /// One straight stroke segment as a rectangle (two triangles) of width
    /// `2 * half`, offset perpendicular to the segment direction. Each end takes
    /// its own color, so a gradient stroke shades across the quad; a solid
    /// stroke passes the same color twice.
    private func appendSegment(from a: Vector2, to b: Vector2, half: Double,
                               colorA: SIMD4<Float>, colorB: SIMD4<Float>) {
        let d = b - a
        let len = d.length
        guard len > 0 else { return }   // skip zero-length (repeated) points
        // Perpendicular to the segment, scaled to the half-width.
        let n = Vector2(-d.y, d.x) / len * half
        let a0 = (a + n).simd2
        let a1 = (a - n).simd2
        let b0 = (b + n).simd2
        let b1 = (b - n).simd2
        // Quad (a0, b0, b1, a1) -> two triangles.
        emit(a0, color: colorA)
        emit(b0, color: colorB)
        emit(b1, color: colorB)
        emit(a0, color: colorA)
        emit(b1, color: colorB)
        emit(a1, color: colorA)
    }

    /// Stroke a polyline or closed contour as butt segment quads plus a join
    /// filler at each shared vertex, so corners close cleanly instead of leaving
    /// the gap two independent butt ends make. The join style (`strokeJoin`)
    /// decides each corner: `.miter` extends the outer edges to a point (bevel
    /// past `miterLimit` so an acute corner doesn't spike), `.bevel` always cuts
    /// it flat, `.round` fills it with an arc. Open paths finish their ends with
    /// the cap style (`strokeCap`); closed ones join every vertex and have no
    /// ends. The inner side of a turn is already covered by the overlapping
    /// segment quads, so only the outer gap is filled.
    private func appendStrokedPath(_ points: [Vector2], closed: Bool,
                                   half: Double, paint: VertexPaint) {
        guard half > 0 else { return }
        // Drop repeated points; a zero-length segment has no direction.
        var pts: [Vector2] = []
        for p in points where (pts.last.map { ($0 - p).length > 1e-9 } ?? true) {
            pts.append(p)
        }
        if closed, pts.count > 1, (pts[0] - pts[pts.count - 1]).length <= 1e-9 {
            pts.removeLast()
        }
        // A segment quad carries color only at its two ends, so a gradient
        // crossing a long straight run would interpolate straight through its
        // stops (and a radial sweep would corner instead of curve) — split long
        // segments first. The inserted points are collinear, so the join filler
        // below skips them. Solid strokes keep their geometry untouched.
        if paint.isGradient {
            pts = Drawer.subdivided(pts, closed: closed, maxLength: 12)
        }
        let n = pts.count
        guard n >= 2 else { return }

        // Arc-length fraction at each vertex (0…1 over the path, the closing
        // segment included), read by along-path paint.
        var ts: [Double] = []
        var solidColor: SIMD4<Float>? = nil
        if case .solid(let c) = paint { solidColor = c }
        if solidColor == nil {
            var cumulative: [Double] = [0]
            cumulative.reserveCapacity(n)
            for i in 1..<n { cumulative.append(cumulative[i - 1] + (pts[i] - pts[i - 1]).length) }
            var total = cumulative[n - 1]
            if closed { total += (pts[0] - pts[n - 1]).length }
            ts = total > 0 ? cumulative.map { $0 / total } : Array(repeating: 0, count: n)
        }
        func colorAt(_ i: Int) -> SIMD4<Float> {
            solidColor ?? paint.color(at: pts[i], pathT: ts[i])
        }

        let segments = closed ? n : n - 1
        for i in 0..<segments {
            // The closing segment runs back to the start: its far end is the
            // path's t = 1, not the first vertex's t = 0.
            let j = (i + 1) % n
            let colorB = (closed && j == 0 && solidColor == nil)
                ? paint.color(at: pts[0], pathT: 1) : colorAt(j)
            appendSegment(from: pts[i], to: pts[j], half: half,
                          colorA: colorAt(i), colorB: colorB)
        }

        let miterLimit = 8.0
        let joins = closed ? Array(0..<n) : Array(1..<(n - 1))
        for v in joins {
            let curr = pts[v]
            let d0v = curr - pts[(v - 1 + n) % n]
            let d1v = pts[(v + 1) % n] - curr
            let l0 = d0v.length, l1 = d1v.length
            guard l0 > 1e-9, l1 > 1e-9 else { continue }
            let d0 = d0v / l0, d1 = d1v / l1
            let n0 = Vector2(-d0.y, d0.x)   // unit left normals
            let n1 = Vector2(-d1.y, d1.x)
            let cross = d0.x * d1.y - d0.y * d1.x
            guard abs(cross) > 1e-6 else { continue }   // collinear: no gap to fill
            // Fill on the outer side of the turn (where the two quads diverge).
            // The whole join takes the corner vertex's color (it spans no length).
            let color = colorAt(v)
            let side: Double = cross >= 0 ? -1 : 1
            let cornerA = curr + n0 * (side * half)
            let cornerB = curr + n1 * (side * half)
            switch strokeJoinStyle {
            case .round:
                // Arc the outer gap from one corner to the other about `curr`,
                // sweeping the short (minor) way between them.
                let va = cornerA - curr, vb = cornerB - curr
                let startAngle = atan2(va.y, va.x)
                let sweep = atan2(va.x * vb.y - va.y * vb.x, va.x * vb.x + va.y * vb.y)
                appendArcFan(center: curr, radius: half,
                             startAngle: startAngle, sweep: sweep, color: color)
            case .bevel:
                emit(curr.simd2, color: color); emit(cornerA.simd2, color: color); emit(cornerB.simd2, color: color)
            case .miter:
                let bisector = n0 + n1
                let bisectorLength = bisector.length
                let cosHalf = bisectorLength > 1e-6 ? (bisector.x * n0.x + bisector.y * n0.y) / bisectorLength : 0
                if cosHalf > 1e-4, 1 / cosHalf <= miterLimit {
                    let miter = (curr + bisector / bisectorLength * (side * half / cosHalf)).simd2
                    emit(curr.simd2, color: color); emit(cornerA.simd2, color: color); emit(miter, color: color)
                    emit(curr.simd2, color: color); emit(miter, color: color); emit(cornerB.simd2, color: color)
                } else {
                    emit(curr.simd2, color: color); emit(cornerA.simd2, color: color); emit(cornerB.simd2, color: color)
                }
            }
        }

        // Cap the two open ends (closed paths have none). The cap direction points
        // outward — away from the path — along the end segment.
        guard !closed else { return }
        let dStart = pts[1] - pts[0]
        if dStart.length > 1e-9 {
            appendCap(at: pts[0], outward: dStart / dStart.length * -1, half: half, color: colorAt(0))
        }
        let dEnd = pts[n - 1] - pts[n - 2]
        if dEnd.length > 1e-9 {
            appendCap(at: pts[n - 1], outward: dEnd / dEnd.length, half: half, color: colorAt(n - 1))
        }
    }

    /// `pts` with every segment longer than `maxLength` split into equal pieces
    /// (the closing segment of a closed path included), so per-vertex gradient
    /// color tracks the paint instead of skipping its stops.
    private static func subdivided(_ pts: [Vector2], closed: Bool, maxLength: Double) -> [Vector2] {
        guard pts.count >= 2 else { return pts }
        var out: [Vector2] = []
        out.reserveCapacity(pts.count)
        let segments = closed ? pts.count : pts.count - 1
        for i in 0..<segments {
            let a = pts[i]
            let b = pts[(i + 1) % pts.count]
            out.append(a)
            let pieces = Int(((b - a).length / maxLength).rounded(.up))
            if pieces > 1 {
                for k in 1..<pieces {
                    out.append(a + (b - a) * (Double(k) / Double(pieces)))
                }
            }
        }
        if !closed { out.append(pts[pts.count - 1]) }
        return out
    }

    /// Finish one open end of a stroked path per `strokeCap`. `outward` is the
    /// unit direction pointing away from the path; `.butt` adds nothing, `.round`
    /// caps with a half-disk, `.square` extends a flat quad `half` past the end.
    private func appendCap(at point: Vector2, outward: Vector2,
                           half: Double, color: SIMD4<Float>) {
        let perp = Vector2(-outward.y, outward.x)   // unit, across the stroke
        switch strokeCapStyle {
        case .butt:
            return
        case .round:
            // Half-disk: a π sweep from one edge to the other, bulging outward.
            // `perp` is 90° from `outward`, so sweeping −π routes through it.
            appendArcFan(center: point, radius: half,
                         startAngle: atan2(perp.y, perp.x), sweep: -.pi, color: color)
        case .square:
            let n = perp * half
            let ext = outward * half
            let a0 = (point + n).simd2
            let a1 = (point - n).simd2
            let b0 = (point + n + ext).simd2
            let b1 = (point - n + ext).simd2
            emit(a0, color: color); emit(b0, color: color); emit(b1, color: color)
            emit(a0, color: color); emit(b1, color: color); emit(a1, color: color)
        }
    }

    /// Triangle-fan an arc of `radius` about `center`, starting at `startAngle`
    /// and sweeping `sweep` radians (signed). The step count scales with the arc
    /// length, so round joins and caps stay smooth without over-tessellating.
    private func appendArcFan(center: Vector2, radius: Double,
                              startAngle: Double, sweep: Double, color: SIMD4<Float>) {
        guard radius > 0, abs(sweep) > 1e-6 else { return }
        let full = Double(circleSegments(for: radius))
        let steps = max(1, Int((abs(sweep) / (2 * .pi) * full).rounded(.up)))
        let c = center.simd2
        var prev = SIMD2<Float>(Float(center.x + cos(startAngle) * radius),
                                Float(center.y + sin(startAngle) * radius))
        for i in 1...steps {
            let a = startAngle + sweep * Double(i) / Double(steps)
            let curr = SIMD2<Float>(Float(center.x + cos(a) * radius),
                                    Float(center.y + sin(a) * radius))
            emit(c, color: color); emit(prev, color: color); emit(curr, color: color)
            prev = curr
        }
    }

    // MARK: Affine matrix builders (column-major, 2D homogeneous)

    private static func translation(_ tx: Float, _ ty: Float) -> matrix_float3x3 {
        matrix_float3x3(columns: (SIMD3<Float>(1, 0, 0),
                                  SIMD3<Float>(0, 1, 0),
                                  SIMD3<Float>(tx, ty, 1)))
    }
    private static func rotation(_ a: Float) -> matrix_float3x3 {
        let c = cos(a), s = sin(a)
        return matrix_float3x3(columns: (SIMD3<Float>(c, s, 0),
                                         SIMD3<Float>(-s, c, 0),
                                         SIMD3<Float>(0, 0, 1)))
    }
    private static func scaling(_ sx: Float, _ sy: Float) -> matrix_float3x3 {
        matrix_float3x3(columns: (SIMD3<Float>(sx, 0, 0),
                                  SIMD3<Float>(0, sy, 0),
                                  SIMD3<Float>(0, 0, 1)))
    }

    // MARK: 3D model-matrix builders (column-major, right-handed, y-up)

    private static func translation3(_ t: SIMD3<Float>) -> matrix_float4x4 {
        matrix_float4x4(columns: (SIMD4<Float>(1, 0, 0, 0),
                                  SIMD4<Float>(0, 1, 0, 0),
                                  SIMD4<Float>(0, 0, 1, 0),
                                  SIMD4<Float>(t.x, t.y, t.z, 1)))
    }
    private static func scaling3(_ sx: Float, _ sy: Float, _ sz: Float) -> matrix_float4x4 {
        matrix_float4x4(columns: (SIMD4<Float>(sx, 0, 0, 0),
                                  SIMD4<Float>(0, sy, 0, 0),
                                  SIMD4<Float>(0, 0, sz, 0),
                                  SIMD4<Float>(0, 0, 0, 1)))
    }
    private static func rotationX(_ a: Float) -> matrix_float4x4 {
        let c = cos(a), s = sin(a)
        return matrix_float4x4(columns: (SIMD4<Float>(1, 0, 0, 0),
                                         SIMD4<Float>(0, c, s, 0),
                                         SIMD4<Float>(0, -s, c, 0),
                                         SIMD4<Float>(0, 0, 0, 1)))
    }
    private static func rotationY(_ a: Float) -> matrix_float4x4 {
        let c = cos(a), s = sin(a)
        return matrix_float4x4(columns: (SIMD4<Float>(c, 0, -s, 0),
                                         SIMD4<Float>(0, 1, 0, 0),
                                         SIMD4<Float>(s, 0, c, 0),
                                         SIMD4<Float>(0, 0, 0, 1)))
    }
    private static func rotationZ(_ a: Float) -> matrix_float4x4 {
        let c = cos(a), s = sin(a)
        return matrix_float4x4(columns: (SIMD4<Float>(c, s, 0, 0),
                                         SIMD4<Float>(-s, c, 0, 0),
                                         SIMD4<Float>(0, 0, 1, 0),
                                         SIMD4<Float>(0, 0, 0, 1)))
    }
    /// Rotation about a unit `axis` by `a` radians (right-handed), via a quaternion
    /// so it stays consistent with the axis-aligned builders above.
    private static func rotation3(_ a: Float, axis: SIMD3<Float>) -> matrix_float4x4 {
        matrix_float4x4(simd_quatf(angle: a, axis: axis))
    }
    /// The mean of the model matrix's three basis-column lengths — the factor a
    /// scaling transform applies to a splat's world-unit size (exact for uniform
    /// scale, a sensible average otherwise; 1 for a rigid transform).
    private static func averageScale(_ m: matrix_float4x4) -> Float {
        let x = simd_length(SIMD3<Float>(m.columns.0.x, m.columns.0.y, m.columns.0.z))
        let y = simd_length(SIMD3<Float>(m.columns.1.x, m.columns.1.y, m.columns.1.z))
        let z = simd_length(SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z))
        return (x + y + z) / 3
    }
}

extension Color {
    /// GPU vertex-color representation.
    var simd4: SIMD4<Float> {
        SIMD4<Float>(Float(red), Float(green), Float(blue), Float(alpha))
    }
}

extension Vector2 {
    /// GPU-boundary representation: components narrowed to `Float`. Mirrors
    /// `Color.simd4`; the renderer's vertices are `SIMD2<Float>` positions.
    var simd2: SIMD2<Float> {
        SIMD2<Float>(Float(x), Float(y))
    }
}
