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
    /// Whether a `.mesh3D` batch is the live ground-grid overlay (a y=0 plane drawn
    /// through `ollin_grid_fragment`), selecting the grid pipeline + its no-depth-write
    /// state. `gridParams` carries its cell size / axis colors / fade. Live host chrome.
    var meshGrid = false
    var gridParams = OllinGridParams()
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
    var fillPaint: Paint? = .color(.white)     // default: white fill
    var strokePaint: Paint? = .color(.black)   // default: black stroke
    var strokeWidth: Double = 1         // default: 1px
    var pointDiameter: Double = 1       // default: 1px dot (see pointSize / drawPoint)
    var marker: PointMarker = .circle   // default: round dot (see pointMarker / drawPoint)
    var hollowWidth: Double = 0         // 0 = solid fill; > 0 = hollow band (see hollow / solid)
    var strokeAlignment: StrokeAlign = .center   // where the stroke sits on the outline (see strokeAlign)
    var strokeJoinStyle: StrokeJoin = .miter     // how stroked-path corners turn (see strokeJoin)
    var strokeCapStyle: StrokeCap = .butt        // how open stroked-path ends finish (see strokeCap)
    var currentMaterial = Material()    // 3D mesh surface finish (shading model + specular/rim/subsurface/iridescence); see material(_:)
    private var wireframeEnabled = false        // 3D mesh: draw triangle edges only (see wireframe)
    private var currentMatcap: Image?           // 3D mesh: a matcap sphere texture replacing the lit look (see matcap(_:))
    var currentFont: ActiveFont = .outline(.systemMedium)   // active text font (see textFont / drawText)
    var textPixelSize: Double = 24               // rendered glyph height in points (see textSize)
    var textAlignH: TextAlignH = .left           // horizontal text anchor (see textAlign)
    var textAlignV: TextAlignV = .baseline       // vertical text anchor (see textAlign)
    var textRenderMode: TextMode = .outline      // outline vs SDF-atlas text (see textMode)
    var tintColor: Color? = nil                  // multiplies drawImage texels; nil = untinted (see tint / noTint)
    var currentBlend: BlendMode = .normal        // how shapes combine with the canvas (see blendMode)
    var currentDepth: Float? = nil               // clip-z for 2D draws in a 3D scene; nil = draw over (see depth(at:))

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

    var vertices: [OllinVertex] = []

    /// Instanced SDF shapes recorded this frame (see `SDFInstance`).
    var sdfInstances: [SDFInstance] = []

    /// Composed SDF fields (combinator groups) recorded this frame, plus the flat
    /// instruction nodes they index into (see `SDFGroupInstance` / `SDFNode` and
    /// ShaderCombinator.metal). One `drawSDF` call appends one group + its nodes.
    var sdfGroups: [SDFGroupInstance] = []
    var sdfNodes: [SDFNode] = []
    var sdf3DGroups: [SDF3DGroupInstance] = []
    var sdf3DNodes: [SDFNode3D] = []

    /// The open scoped-combine blocks (`smoothUnion { … }` etc.). While the stack is
    /// non-empty, SDF region draw calls are captured as `SDF` leaves into the innermost
    /// frame instead of drawn; closing the outermost frame builds the field and draws
    /// it. `combineGroupTransform` is the CTM when the outermost block opened, so a leaf
    /// drawn under a changed CTM lands in the group's field space.
    var combineStack: [CombineFrame] = []
    var combineGroupTransform: matrix_float3x3?
    var combineGroupModel: matrix_float4x4?
    var warnedNonCombinable = false
    var warnedMeshInCombine = false
    var warnedSculptVerbOutside = false

    /// Textured-quad vertices recorded this frame (see `drawImage`). Each image
    /// draw appends 6 vertices (two triangles) and opens its own `.image` batch,
    /// which carries the texture.
    var imageVertices: [OllinImageVertex] = []

    /// SDF-atlas text quads recorded this frame (see `drawAtlasText`). Each glyph
    /// is 6 vertices (two triangles) sampling the font's atlas; reuses the image
    /// vertex layout (position + uv + `tint` as the fill color).
    var glyphVertices: [OllinImageVertex] = []

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

    /// How soft a cast shadow's penumbra is, 0…1. 0 = a hard edge (the legacy 3×3 PCF, so
    /// `shadowSoftness(0)` is byte-identical to the old look); the 0.5 default is contact-
    /// hardening soft (PCSS for the directional/spot 2D maps); 1 = very soft. It drives the
    /// ray-traced point caster's area-light radius too, so one knob softens every caster kind.
    private(set) var shadowSoftnessAmount: Double = 0.5

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
    var hasDepthScene = false

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
    var batches: [GeometryBatch] = []
    var currentKind: GeometryKind?
    /// The blend mode of the currently-open batch, so a blend-mode change opens a
    /// fresh batch even when the geometry kind is unchanged.
    var currentBatchBlend: BlendMode = .normal
    /// The 2D depth of the currently-open batch, so a `depth(at:)`/`noDepth()`
    /// change opens a fresh batch even when kind and blend are unchanged.
    var currentBatchDepth: Float? = nil

    // MARK: Effects layers (render targets, per-frame)

    /// The off-screen-target redirection stack: while non-empty, drawing is tagged
    /// for the innermost target instead of the main canvas (see `withTarget`). Each
    /// frame records the buffer/batch counts at push, so `background(_:)` inside a
    /// block can clear *just that target*.
    private var targetStack: [TargetFrame] = []
    /// The target drawing currently lands in, if any (the innermost active block).
    var currentTarget: RenderTarget? { targetStack.last?.target }
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
    func gradientRow(for ramp: Ramp) -> (index: Int, baked: BakedGradient) {
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
    func ensureBatch(_ kind: GeometryKind) {
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
    func beginImageBatch(_ image: Image) {
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
                                wireframe: Bool = false, matcap: Image? = nil,
                                grid: Bool = false, gridParams: OllinGridParams = OllinGridParams()) {
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
                                     meshWireframe: wireframe, meshGrid: grid,
                                     gridParams: gridParams, matcap: matcap,
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

    /// Open a new `.sdfGroup3D` batch when the blend, depth, or surface finish changes;
    /// consecutive fields under one material merge (drawn as one instanced pass). Like
    /// the solid meshes, the finish is bound per batch as one `OllinMaterial` uniform,
    /// so a `material(_:)` change must break the batch for the fragment to see it.
    func ensureSDF3DBatch(_ m: Material) {
        if currentKind == .sdfGroup3D, currentBatchBlend == currentBlend,
           currentBatchDepth == currentDepth, currentBatchMaterial == m {
            return
        }
        currentKind = .sdfGroup3D
        currentBatchBlend = currentBlend
        currentBatchDepth = currentDepth
        currentBatchMaterial = m
        batches.append(GeometryBatch(kind: .sdfGroup3D, vertexStart: vertices.count,
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

    /// Remove the live ground-grid chrome again, once the on-screen render has
    /// consumed it. The runner appends the grid after the sketch's own draw, so a
    /// same-frame re-consumer of this drawer (the frame-grab and Syphon re-renders)
    /// must not see it. The trailing batch and its vertices go together: a batch's
    /// vertex count is derived from the next start / `meshVertices.count`, so
    /// popping the batch without shrinking the array would hand the grid's
    /// vertices to the preceding mesh batch.
    func removeGridChrome() {
        while let last = batches.last, last.meshGrid {
            meshVertices.removeLast(meshVertices.count - last.meshStart)
            batches.removeLast()
            currentKind = nil
        }
    }

    /// Draw the live ground-grid overlay: one large y=0 quad (centered at `center`'s XZ,
    /// half-width `halfExtent`) routed to the grid pipeline, which computes the
    /// anti-aliased reference grid per pixel from the world XZ. Host chrome the runner
    /// injects after the sketch's `draw()` (live preview only, never an export), so it
    /// opens its own grid batch and reads nothing from the current fill/material.
    func drawGroundGrid(_ params: OllinGridParams, center: Vector3, halfExtent: Double) {
        beginMeshBatch(material: nil, finish: OllinMaterial(), grid: true, gridParams: params)
        let cx = Float(center.x), cz = Float(center.z), h = Float(halfExtent)
        let corners = [SIMD3<Float>(cx - h, 0, cz - h), SIMD3<Float>(cx + h, 0, cz - h),
                       SIMD3<Float>(cx + h, 0, cz + h), SIMD3<Float>(cx - h, 0, cz + h)]
        meshVertices.reserveCapacity(meshVertices.count + 6)
        for k in [0, 1, 2, 0, 2, 3] {
            var v = OllinMeshVertex()
            v.position = SIMD4<Float>(corners[k], 1)
            v.normal = SIMD4<Float>(0, 1, 0, 0)
            v.color = SIMD4<Float>(1, 1, 1, 1)
            meshVertices.append(v)
        }
    }

    /// Open a fresh `.glyphAtlas` batch carrying `atlas` as its texture. One
    /// `drawText` call opens one batch (all its glyphs sample the same atlas);
    /// resets `currentKind` so a following primitive reopens its own batch.
    func beginGlyphBatch(_ atlas: GlyphAtlas) {
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
    /// is forced at each boundary so target and main geometry never merge. Scoped
    /// like `withState`: the drawing state carries in, and any change the block
    /// makes (a blend mode, a fill, a transform) is restored on exit, so a layer's
    /// styling never leaks onto the canvas.
    func withTarget(_ target: RenderTarget, _ body: () -> Void) {
        if !renderTargets.contains(where: { $0 === target }) { renderTargets.append(target) }
        targetStack.append(TargetFrame(target: target, snapshot: snapshot()))
        currentKind = nil    // force the first draw inside the target into a fresh batch
        pushState()
        body()
        popState()
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
    func svgRecord(_ geometry: SVGGeometry, fill: Paint?, stroke: Paint?) {
        let visibleStroke = (stroke != nil && strokeWidth > 0) ? stroke : nil
        let style = SVGStyle(fill: fill, stroke: visibleStroke, strokeWidth: strokeWidth,
                             join: strokeJoinStyle, cap: strokeCapStyle)
        svgRecorder?.commands.append(RecordedSVG(geometry: geometry, style: style, transform: transform))
    }

    /// Shift origin-centered outline points into user space around `c`.
    func svgOffset(_ points: [Vector2], _ c: Vector2) -> [Vector2] {
        points.map { $0 + c }
    }

    /// Current affine transform (2D homogeneous), applied to every emitted
    /// vertex. Reset to identity each frame.
    var transform = matrix_identity_float3x3

    /// Tracks whether `transform` is still the identity, so `emit` can skip the
    /// per-vertex matrix multiply for the common case of a sketch that never
    /// translates/rotates/scales (the matmul runs hundreds of thousands of times
    /// a frame otherwise).
    var transformIsIdentity = true

    /// The 3D model matrix — the spatial sibling of `transform`, for geometry that
    /// rides the `camera3D` rather than the 2D canvas (point clouds today). Built by
    /// the 3D `translate`/`rotate*`/`scale` overloads and reset to identity each
    /// frame. It composes *inside* the camera: a point reaches clip space as
    /// `projection · view · model · p`. Kept separate from the 2D affine so the 2D
    /// path stays byte-identical — a 2D-only sketch never touches it.
    var modelMatrix = matrix_identity_float4x4

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

    /// Set how soft a cast shadow's penumbra is, 0…1 (clamped). 0 = a hard edge, 0.5 = the
    /// contact-hardening default, 1 = very soft. Persistent.
    func shadowSoftness(_ amount: Double) { shadowSoftnessAmount = min(1, max(0, amount)) }

    /// Set the raymarched-SDF (`drawSDF3D`) quality to a `RenderQuality` tier (the renderer
    /// resolves a march-step budget + internal render scale). Persistent.
    func raymarchQuality(_ quality: RenderQuality) { raymarchQualitySetting = .tier(quality) }

    /// Set the raymarched-SDF camera-march step count to an exact value, clamped to 16…512
    /// (full resolution). Persistent.
    func raymarchSteps(_ count: Int) { raymarchQualitySetting = .absolute(max(16, min(count, 512))) }

    /// Set the raymarched-SDF resolution budget to an exact fraction (0.1…1.0), the custom
    /// alternative to the `raymarchQuality` tiers' 1.0/0.5/0.25 (coverage-adaptive like them:
    /// the fraction applies at full screen coverage, a smaller field traces denser). Persistent.
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
            // The same framing proxy sizes the sparkle finish's flake cells, so the
            // default flake size reads alike at any scene scale.
            u.sceneScale = radius
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
            // The directional/spot caster's penumbra radius in shadow-map texels (0 = the hard
            // legacy 3×3). Texel-space, so it's scene-scale-invariant: `shadowTexelWorld` already
            // scales with the scene, so the world penumbra (size · texelWorld) scales with it too,
            // and `castShadows()` "just works" at any scale with no per-scene tuning.
            let lightSizeTexels = shadowSoftnessAmount <= 0 ? Float(0) : Float(1 + shadowSoftnessAmount * 18)
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
                // PCSS (`shadowKind` 0): the penumbra radius in texels, and `shadowDepthB` = 0,
                // the sentinel for an orthographic map (the shader uses plain depth separation,
                // no perspective linearization).
                u.shadowDepthA = lightSizeTexels
                u.shadowDepthB = 0
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
                // PCSS (`shadowKind` 0): the penumbra radius in texels. `shadowDepthB` carries
                // the projection's [2][2] term (column 2, z in column-major simd), which is all
                // the shader needs to linearize the perspective depth for the penumbra ratio
                // (the [3][2] term cancels). It's negative, which also flags the spot path.
                u.shadowDepthA = lightSizeTexels
                u.shadowDepthB = proj.columns.2.z
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
                // The cube path ignores it, so it's harmless to always pack. Driven by the
                // same `shadowSoftness` knob as the 2D casters (one control for every kind);
                // the default 0.5 reproduces the previous fixed `dist · 0.03` exactly.
                u.shadowDepthB = dist * 0.06 * Float(shadowSoftnessAmount)
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
        // The material finish is bound per batch as an `OllinMaterial` uniform; two values
        // also ride the otherwise-spare vertex `w` slots for the ray-traced reflection path
        // to read: metalness in normal.w and roughness in position.w. A physically-based lit
        // mesh bakes its own metalness + roughness, so a reflection hit shades it as the metal
        // it is (its tinted environment reflection); a non-PBR lit mesh bakes metalness 0 +
        // roughness 1, so a reflection treats it as a flat diffuse surface. A wireframe instead
        // stores its line width in position.w (it has no specular to reflect). The lit vertex
        // shaders read only the xyz, so all of this is inert for the primary render.
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

    /// The current solid `fill` color (white for a gradient or `noFill`), for
    /// helpers that bake one flat color into geometry (the point-cloud attractor
    /// sugar).
    var currentFillColor: Color { meshSurfaceColor }

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
