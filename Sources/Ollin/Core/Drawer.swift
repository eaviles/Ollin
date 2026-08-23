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
    case meshInstanced // one mesh drawn many times: local-space vertices in
                       // `instancedMeshVertices`, per-copy placements in `meshInstances`
                       // (or a GPU-resident instance buffer), placed on the GPU
    case meshField     // a retained `MeshField`: many distinct meshes + copies drawn
                       // by ONE executeCommandsInBuffer, GPU-culled per copy
    case strands       // a `StrandField`: blades a mesh pipeline grows in-draw
                       // (no geometry buffers anywhere), tile-culled + LOD'd on the GPU
    case fringe       // edge-expanded stroke + ~1px AA fringe in `vertices` (the high-quality stroke path)
    case depthScene   // a backdrop quad in `imageVertices` that also primes the depth buffer from a depth map
    case sdfGroup     // composed SDF field (combinator) in `sdfGroups`, evaluating `sdfNodes`
    case sdfGroup3D   // raymarched composed 3D SDF field in `sdf3DGroups`, evaluating `sdf3DNodes`
    case clipPush     // stencil-only: the clip region's fill triangles in `vertices` raise the clip level (withClip)
    case clipPop      // stencil-only: one fullscreen cover lowers the popped clip level (no geometry)
    case retained     // a recorded `Batch` replayed from its own persistent buffers (drawBatch)
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
    /// neighbor.
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
    /// The base-mesh vertex run for a `.meshInstanced` batch: start and count in
    /// `instancedMeshVertices` (local space, indices expanded), plus the placement
    /// run in `meshInstances`. Carried as explicit counts rather than next-batch
    /// arithmetic: an instanced draw is always its own batch, and no other batch
    /// creator records these starts. A GPU-resident instance buffer rides
    /// `particleBuffer`/`particleCount` instead (`meshInstanceCount` then 0).
    var instancedVertexStart: Int = 0
    var instancedVertexCount: Int = 0
    var meshInstanceStart: Int = 0
    var meshInstanceCount: Int = 0
    /// The retained field for a `.meshField` batch (`nil` otherwise), plus the
    /// 3D CTM at draw time (composed onto every copy by the cull kernel and the
    /// field vertex shader; identity when the field is drawn untransformed).
    var field: MeshField?
    var fieldTransform: simd_float4x4 = matrix_identity_float4x4
    /// The strand parameters for a `.strands` batch (`nil` otherwise); the
    /// draw-time CTM rides `fieldTransform` like a mesh field's.
    var strandField: StrandField?
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
    /// The clip-nesting level this run draws at (see `withClip`). 0 = unclipped (the
    /// default, byte-identical). For a content batch it's the stencil reference the
    /// run tests `equal` against; for a `.clipPush` batch it's the level the push
    /// establishes, and for a `.clipPop` the level being dismantled. A change opens
    /// a fresh batch, like a blend-mode change.
    var clipLevel: Int = 0
    /// The recorded `Batch` a `.retained` reference batch replays; `nil` otherwise.
    /// The reference consumes no frame geometry (its starts equal the next batch's),
    /// so it never disturbs the run-length counts around it.
    var retained: Batch?
    /// The CTM at `drawBatch` time, moving the whole replay as a unit; `nil` when
    /// it was the identity, so the encode keeps the flag-gated shader branch
    /// untaken and the replay is byte-identical to the recording.
    var retainedTransform: matrix_float3x3?
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
    var strokeProfileShape: StrokeProfile = .uniform  // how stroke width varies along a path (see strokeProfile)
    // How stroke alpha varies along a path, the width profile's sibling. Set only
    // by drawMark, which is the one thing that measures opacity per point; a
    // `.uniform` value leaves the per-vertex color untouched, so every other
    // stroke in the framework is byte-identical to before it existed.
    var strokeOpacityShape: StrokeProfile = .uniform
    // A shape repeated along a path in place of the continuous ribbon (see
    // strokeBrush). `nil` is the ribbon, so every stroke that does not ask for a
    // brush takes exactly the path it always did.
    var strokeBrushShape: Brush?
    var currentMaterial = Material()    // 3D mesh surface finish (shading model + specular/rim/subsurface/iridescence); see material(_:)
    private var wireframeEnabled = false        // 3D mesh: draw triangle edges only (see wireframe)
    private var currentMatcap: Image?           // 3D mesh: a matcap sphere texture replacing the lit look (see matcap(_:))
    var currentFont: ActiveFont = .outline(.systemMedium)   // active text font (see textFont / drawText)
    var textPixelSize: Double = 24               // rendered glyph height in points (see textSize)
    var textAlignH: TextAlignH = .left           // horizontal text anchor (see textAlign)
    var textAlignV: TextAlignV = .baseline       // vertical text anchor (see textAlign)
    var textRenderMode: TextMode = .outline      // outline vs SDF-atlas text (see textMode)
    var textWritingDirection: TextDirection = .automatic   // base line direction (see textDirection)
    var textJustifies: Bool = false              // stretch wrapped lines to the box (see textJustify)
    var textHangsPunctuation: Bool = false       // let a stop or comma sit past a line end (see textHangingPunctuation)
    /// What the block being drawn right now is stretched to, set by the box form of
    /// `drawText` for the length of that one call. Nothing else may set it: only a
    /// box knows how far a line should run.
    var textJustification: TextJustification? = nil
    /// Whether the block being drawn right now may hang a stop past a line end. Set
    /// by the box form of `drawText` for the length of that one call, and for the
    /// same reason justification is: only a box has an edge to hang past.
    var textHangsInBox = false
    var tintColor: Color? = nil                  // multiplies drawImage texels; nil = untinted (see tint / noTint)
    var currentBlend: BlendMode = .normal        // how shapes combine with the canvas (see blendMode)
    var currentDepth: Float? = nil               // clip-z for 2D draws in a 3D scene; nil = draw over (see depth(at:))

    /// The active symmetry folds (see `symmetry(_:mirrored:)`): canvas-space
    /// transforms, the identity first, that every 2D draw call is replicated
    /// through. `nil` = off (the default). Drawing state like the fill, saved by
    /// `withState`; the folds are canvas-space constants, so they stay valid as
    /// the transform stack keeps moving under them.
    private(set) var symmetryFolds: [matrix_float3x3]?

    /// True while `replicated(_:)` runs its primary body, so a nested emission
    /// path (a stroke funnel called inside a wrapped fill body) emits once and
    /// lets the outer wrapper do the replication. Internal so the emission
    /// funnels in the other `Drawer+*` files can consult it.
    private(set) var isReplicating = false

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

    /// Base-mesh vertices for this frame's instanced draws (see
    /// `drawMeshInstanced`): LOCAL space, indices expanded, the model matrix NOT
    /// baked in (each instance applies its own on the GPU). One run per instanced
    /// batch, addressed by the batch's explicit start/count.
    private(set) var instancedMeshVertices: [OllinMeshVertex] = []

    /// Per-copy placements for this frame's instanced draws: the composed
    /// local -> world matrix (the CTM at draw time times the instance's own) plus
    /// the per-copy tint. One run per instanced batch.
    private(set) var meshInstances: [OllinMeshInstance] = []

    /// The active 3D camera, or `nil` for a 2D frame (the default). Per-frame state
    /// like the geometry — set with `camera`/`perspective`/`ortho`, reset each
    /// frame. When set, the renderer allocates a depth buffer and draws 3D geometry
    /// through it; a 2D-only frame leaves it `nil` and is untouched.
    private(set) var camera3D: Camera3D?

    /// Last frame's camera, kept across `beginFrame`: the cross-frame half of the
    /// motion-blur velocity computation (the mover registry's camera sibling). It
    /// lives here rather than on a renderer history slot so the live, repeat, and
    /// headless-export paths all read the same value: `beginFrame` runs once per
    /// `draw()` on every path, so exported frame k sees frame k-1's camera exactly
    /// like the live window does. `nil` before the first frame that draws a camera;
    /// with no previous camera nothing has moved yet, so there is nothing to blur.
    private(set) var previousCamera3D: Camera3D?

    /// One declared mover's mesh range this frame (`withMotion`): the vertices
    /// `[start, start + count)` of `meshVertices`, plus the transform that takes
    /// their baked *current* world-space positions back to where last frame's
    /// model matrix put them (prevModel · inverse(curModel)). The renderer's
    /// velocity pass re-renders these ranges to give temporal AA exact history
    /// for world-space movers; everything else keeps the depth-reprojection
    /// fallback. Recorded in draw order (the determinism rule).
    struct MoverRange {
        var start: Int
        var count: Int
        var previousOfCurrent: simd_float4x4
    }

    /// A mover's cross-frame identity: the `withMotion` call site, its occurrence
    /// index among same-site calls this frame, and the draw's index within that
    /// block. The `SSRSlotKey` rule applies: a call-site key, never a frame-wide
    /// ordinal, or a sketch that only conditionally opens an *earlier*
    /// `withMotion` block would shift every later block onto another mover's
    /// history.
    private struct MoverKey: Hashable {
        let source: String
        let occurrence: Int
        let draw: Int
    }

    /// The open `withMotion` blocks (innermost last): call-site identity plus a
    /// running draw count, so each mesh draw inside a block gets its own key.
    private struct MoverContext {
        let source: String
        let occurrence: Int
        var draws = 0
    }

    /// Mover ranges recorded this frame, in draw order. The renderer's velocity
    /// pass iterates this array directly (never a Dictionary, the determinism
    /// rule); reset each frame.
    private(set) var moverRanges: [MoverRange] = []

    /// Each mover key's model matrix from the frame it was last drawn. Persists
    /// across frames (it *is* the cross-frame memory); entries not refreshed for
    /// a frame are pruned in `beginFrame`, so a mover that skips a frame starts
    /// over rather than computing a two-frame delta as if it were one.
    private var moverHistory: [MoverKey: (matrix: simd_float4x4, frame: UInt64)] = [:]

    /// The recording frame index the mover history keys against, advanced once
    /// per `beginFrame` (so a frame-grab re-render, which re-encodes without
    /// re-recording, can't double-advance it).
    private var moverFrame: UInt64 = 0

    private var moverStack: [MoverContext] = []
    private var moverOccurrence: [String: Int] = [:]

    /// Lights for the 3D mesh material, set this frame (see `Light`). Per-frame
    /// state like the camera — reset each frame, accumulated by `addLight`.
    private(set) var lights: [Light] = []

    /// Ambient light for the 3D mesh material — a flat term added to every lit
    /// surface (see `ambientLight`). Per-frame state; `nil` means none.
    private(set) var ambientLightColor: Color?

    /// The distinct IES profiles this frame's packed lights reference, in layer
    /// order (a packed light's `shaping.x` indexes this list). Rebuilt by every
    /// `makeLighting` call from the active lights, so repeated calls within a
    /// frame agree; the renderer bakes its profile texture array from it.
    private(set) var usedIESProfiles: [IESProfile] = []

    /// The distinct light cookies this frame's packed spots reference, in layer
    /// order (`shaping.y`); the cookie-array sibling of `usedIESProfiles`.
    private(set) var usedLightCookies: [LightCookie] = []

    /// The frame's placed decals as packed GPU structs, in call order (a later
    /// decal composites over an earlier one), capped at `OLLIN_MAX_DECALS`.
    /// Per-frame state like `lights`; the encode routes every solid/textured
    /// mesh batch through the surface-mapped pipeline while any are placed.
    private(set) var placedDecals: [OllinDecal] = []

    /// The distinct decal images the frame's placements reference, in layer
    /// order (a placement's `params.x` indexes this list); the renderer bakes
    /// its decal texture array from it, the `usedLightCookies` arrangement.
    private(set) var usedDecals: [Decal] = []

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

    /// Whether this frame adds contact shadows (see `contactShadows`). Per-frame state
    /// like the lights. When on (and a caster is active via `castShadows()`), the
    /// renderer marches a short screen-space ray from each mesh pixel toward the
    /// casting light through a scene-depth pre-pass, darkening the fine contact the
    /// shadow map's resolution and bias miss.
    private(set) var contactShadowsEnabled = false

    /// The contact-shadow ray's length in world units. nil = derive from the scene
    /// scale (2.5% of the camera's eye-to-target distance), so the default seats
    /// objects at any scene size. Per-frame state, set alongside `contactShadowsEnabled`.
    private(set) var contactShadowLength: Double?

    /// Whether this frame ray-traces scene reflections off its physically-based surfaces
    /// (see `rayTracedReflections`). Per-frame state like the lights. When on (and the
    /// device can trace from the render stages), a PBR metal's environment reflection is
    /// replaced by a traced reflection of the actual scene; the renderer builds the caster
    /// acceleration structure for it and sets `OllinLighting.rtReflections`. A no-op on a
    /// non-ray-tracing GPU (the IBL-prefilter reflection remains).
    private(set) var rayTracedReflectionsEnabled = false

    /// The lens flare this frame adds, or nil for none (see `lensFlare`). Per-frame
    /// state like the lights. When set, the renderer works out the ghosts the lens
    /// makes of each bright source and adds them to the resolved frame in linear
    /// light, before the tone map. A no-op without a perspective 3D camera and at
    /// least one light.
    private(set) var lensFlareSetting: LensFlare?

    /// Whether this frame gathers real-time global illumination (see `globalIllumination`).
    /// Per-frame state like the lights. When on (and the device can trace), the renderer
    /// keeps a grid of irradiance probes over the scene, re-traced each frame, and the lit
    /// surfaces sample bounce light from them. A no-op on a non-ray-tracing GPU.
    private(set) var globalIlluminationEnabled = false

    /// Whether this frame renders caustics (see `caustics`): light focused through
    /// transmissive glass and off polished metal, photon-traced from the caster light
    /// and splatted onto the rough surfaces it lands on. Per-frame state like the
    /// lights. A no-op on a non-ray-tracing GPU, and inert when no material casts.
    private(set) var causticsEnabled = false

    /// The caustics brightness multiplier (1 = physical) and the dispersion amount
    /// (0 = none, 1 = full rainbow split at every refraction). Per-frame state,
    /// set alongside `causticsEnabled`.
    private(set) var causticsIntensity: Double = 1
    private(set) var causticsDispersion: Double = 0

    /// The caustics quality tier (`causticsQuality(_:)`): the renderer maps it to a
    /// photon budget and an emission-map size. Persistent like `shadowQualitySetting`,
    /// not per-frame.
    private(set) var causticsQualitySetting: RenderQuality = .default

    /// The GI intensity: a multiplier on the sampled bounce light (1 = physical).
    /// Per-frame state, set alongside `globalIlluminationEnabled`.
    private(set) var giIntensity: Double = 1

    /// Whether this frame temporally anti-aliases the 3D scene (see
    /// `temporalAntialiasing`). Per-frame state like the lights. When on (and a 3D
    /// camera is active), the renderer jitters the projection sub-pixel each frame
    /// and accumulates the resolved frames, so edges refine past MSAA; the
    /// headless/export path instead averages N deterministically jittered renders
    /// within each frame. Works on any Metal GPU (no ray tracing involved).
    private(set) var temporalAAEnabled = false

    /// Whether this frame temporally upscales the 3D scene (see
    /// `temporalUpscaling`). Per-frame state like `temporalAAEnabled`. When on
    /// (and a 3D camera is active, on a supporting GPU), the live renderer draws
    /// the whole frame at a reduced resolution and reconstructs the full-size
    /// canvas from the jittered history: quality headroom for a heavy scene.
    /// The headless/export path never upscales: it renders at full resolution
    /// with the deterministic temporal-AA supersample instead, so an export is
    /// always full quality and byte-stable.
    private(set) var temporalUpscalingEnabled = false

    /// The upscaling tier (`temporalUpscaling(_:)`): the renderer maps it to a
    /// render-resolution fraction, clamped to what the GPU supports. Meaningful
    /// while `temporalUpscalingEnabled` is set.
    private(set) var temporalUpscalingQuality: RenderQuality = .default

    /// Whether this frame motion-blurs the 3D scene (see `motionBlur`). Per-frame
    /// state like `temporalAAEnabled`. When on (and a 3D camera is active), the
    /// renderer streaks the resolved frame along per-pixel screen motion: camera
    /// motion from the depth buffer, per-object motion from `withMotion` blocks.
    private(set) var motionBlurEnabled = false

    /// The blur's shutter: the fraction of a frame interval the virtual shutter
    /// stays open, so 0.5 is the film-standard 180-degree shutter (a streak half
    /// the frame-to-frame travel), 1 a full-interval smear, and values past 1 an
    /// artistic overdrive. Meaningful while `motionBlurEnabled` is set.
    private(set) var motionBlurShutter: Double = 0.5

    /// The global-illumination quality knob (`globalIlluminationQuality`): a persistent
    /// `RenderQuality` tier (not reset each frame, like `shadowQualitySetting`) the renderer
    /// resolves to rays per probe per update (per GPU, like the shadow rays) and, on the
    /// headless path, whole in-frame convergence iterations. The probe *grid* stays at its
    /// fixed budget on every tier: more rays refine the same estimate, but a tier-driven
    /// grid would move the probes themselves, and `.default`'s automatic lift on export
    /// would then light an export differently from the live window.
    private(set) var giQualitySetting: RenderQuality = .default

    /// The ray-traced-reflection resolution knob (`reflectionQuality`): a persistent
    /// `RenderQuality` tier (like `giQualitySetting`) the renderer resolves to the fraction
    /// of the drawable the deferred reflection layer traces at. `.performance` halves it in
    /// each direction, so the trace does a quarter of the work; the other tiers keep it
    /// full size. An export resolves `.default` up to `.detail`, so exported art is never
    /// downscaled unless a sketch asks for `.performance` outright.
    private(set) var reflectionQualitySetting: RenderQuality = .default

    /// How many surfaces one reflected ray may shade along its chain (`reflectionBounces`):
    /// a persistent setting like `reflectionQualitySetting`, clamped to 2…8. 2 is the
    /// shipped pair (the hit, then its own mirror image, which ends at the environment);
    /// more keeps the tunnel going where a mirror faces a mirror, at one more traced ray
    /// per reflected pixel per step.
    private(set) var reflectionBouncesSetting: Int = 2

    /// Whether a rough surface's reflection is traced as a *lobe* (`glossyReflections`):
    /// a persistent setting like `reflectionBouncesSetting`. Off, one reflected ray is a
    /// mirror ray, and roughness is served by fading that mirror into the prefiltered
    /// environment, so a satin floor shows the sky where it should show a blurred room.
    /// On, each ray is spread by the surface's own microfacet distribution and the
    /// neighborhood estimator gathers its neighbors' rays back into one integral.
    private(set) var glossyReflectionsEnabled = false

    /// The roughness a traced glossy lobe reaches. Past it the lobe is wide enough that
    /// the prefiltered environment is the honest answer, and the ray budget buys nothing;
    /// the lit fragment fades into that environment over the last fifth of the range.
    static let glossyReflectionCeiling: Float = 0.75

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

    /// Atmosphere (`fog`): the fog's ambient in-scatter color, or nil while this frame set
    /// none. Per-frame state like the lights (set in `draw()`, reset each frame).
    private(set) var fogColor: Color? = nil
    /// The fog's extinction density at height 0, in inverse world units (0.1 fades a surface
    /// about halfway to the fog color over 7 units). Meaningful while `fogColor` is set.
    private(set) var fogDensity: Double = 0
    /// How the fog thins with world height y (density is `fogDensity · e^(−falloff·y)`);
    /// 0 = the same thickness everywhere.
    private(set) var fogHeightFalloff: Double = 0
    /// Aerial perspective (`aerialPerspective`): true while this frame chose the
    /// wavelength-split atmosphere over classic fog. Per-frame state like the lights;
    /// the two models are exclusive, so setting either clears the other.
    private(set) var aerialActive = false
    /// The aerial extinction density (the green channel's, in inverse world units), or
    /// nil to derive it from the camera framing at pack time so a bare call reads
    /// alike at any scene scale (the contact-shadow default's rule).
    private(set) var aerialDensity: Double? = nil
    /// The aerosol (haze) fraction of the aerial extinction, 0…1: 0 is the pure
    /// molecular blue-shift, 1 a gray haze with a strong forward halo.
    private(set) var aerialHaziness: Double = 0.3
    /// An explicit world direction toward the sun, or nil to resolve one from the
    /// `.sky` environment, the first directional light, or a default elevation.
    private(set) var aerialSun: Vector3? = nil
    /// Volumetric light (`volumetricLight`): the in-scatter gain on the shaft march; 0 = no
    /// march. Per-frame like the lights.
    private(set) var volumetricAmount: Double = 0
    /// The shaft march's Henyey-Greenstein anisotropy, −1…1: positive scatters forward
    /// (beams glow looking toward the light), 0 is even in every direction.
    private(set) var volumetricAnisotropy: Double = 0.5
    /// The volumetric march's step budget: a `RenderQuality` tier the renderer resolves per
    /// path (live vs export), or an exact step count. Persistent like `shadowQualitySetting`.
    private(set) var volumetricQualitySetting: VolumetricQualitySetting = .tier(.default)

    /// The shadow map resolution the renderer renders the depth pass into. Kept here
    /// only to size the normal-offset bias in world units (`shadowTexelWorld`); the
    /// renderer owns the actual texture and must use the same value (`MetalRenderer`).
    static let shadowMapResolution = 2048
    /// The per-face resolution of the omnidirectional (point) shadow cube. Same role as
    /// `shadowMapResolution` for the cube bias, and the fragment sizes its own bias from
    /// the same number, so it lives in the shared header rather than in two places.
    static let pointShadowMapResolution = Int(OLLIN_POINT_SHADOW_RESOLUTION)

    /// The default lighting rig — used when a sketch draws meshes without setting any
    /// light, so a solid is shaded out of the box. It *is* `LightingPreset.standard`
    /// (one source of truth): the `lights()` convenience installs the same preset.
    static var defaultAmbient: Color { LightingPreset.standard.ambient }
    static var defaultLights: [Light] { LightingPreset.standard.lights }

    /// The lights actually shading this frame: none when lighting is off or an
    /// environment is standing in for the rig, the default rig when nothing was
    /// set, and the sketch's own once it sets any. What the renderer packs, and
    /// what a spatial export writes out, so the two can't disagree about which
    /// lights the frame had.
    var activeLights: [Light] {
        switch lightingMode {
        case .off: []
        case .auto: environment != nil ? [] : Drawer.defaultLights
        case .custom: lights
        }
    }

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

    /// The virtual canvas sizes of the open `withViewBox` blocks, innermost last.
    /// While one is open, `background(_:)` fills that canvas rather than setting
    /// the frame's clear color, so the same drawing code that starts by wiping a
    /// canvas wipes only the box it was given.
    var viewBoxCanvases: [Vector2] = []
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
        let sdf3DGroup, sdf3DNode, instancedMesh, meshInstance: Int
    }
    private func snapshot() -> GeometrySnapshot {
        GeometrySnapshot(batches: batches.count, vertices: vertices.count,
                         sdf: sdfInstances.count, image: imageVertices.count,
                         glyph: glyphVertices.count, points: points.count,
                         mesh: meshVertices.count,
                         sdfGroup: sdfGroups.count, sdfNode: sdfNodes.count,
                         sdf3DGroup: sdf3DGroups.count, sdf3DNode: sdf3DNodes.count,
                         instancedMesh: instancedMeshVertices.count,
                         meshInstance: meshInstances.count)
    }
    /// The surface finish of the currently-open *solid* mesh batch, so a `material(_:)`
    /// change opens a fresh batch (the finish is bound once per batch as a uniform).
    private var currentBatchMaterial = Material()

    // MARK: Clipping (withClip)

    /// One active clip region: its fill triangles (canvas space, CTM baked at the
    /// push) kept so `background(_:)` can re-emit the push after wiping the recorded
    /// batches, and the surface it applies to. Clipping is per surface: a region
    /// pushed on the canvas doesn't reach into a `withTarget` layer (each pass has
    /// its own stencil), so a layer opened inside a clip block starts unclipped.
    private struct ClipFrame {
        let vertices: [OllinVertex]
        let target: RenderTarget?
    }
    /// The open clip regions, innermost last. Scoped by `withClip`, so frames for
    /// the current surface are always a suffix of the stack.
    private var clipStack: [ClipFrame] = []
    /// The clip-nesting level drawing currently records at: the number of trailing
    /// stack frames on the current surface. Cached (recomputed on push/pop and at
    /// `withTarget` boundaries) because every batch open reads it.
    private(set) var activeClipLevel = 0
    /// The clip level of the currently-open batch, so a push/pop opens a fresh batch
    /// even when kind, blend, and depth are unchanged.
    private var currentBatchClip = 0
    /// Whether the main canvas needs a stencil attachment this frame (a clip was
    /// pushed outside any target). Per-frame, like the geometry; targets carry their
    /// own `needsStencil` flag instead.
    private(set) var usesClipStencil = false

    private func recomputeClipLevel() {
        var n = 0
        for frame in clipStack.reversed() {
            if frame.target === currentTarget { n += 1 } else { break }
        }
        activeClipLevel = n
    }

    /// Confine subsequent drawing to `shape`'s filled region (its `winding` rule
    /// honored; open contours don't fill, so a shape with no fillable region clips
    /// everything out). Nested pushes intersect. The region is fixed where the CTM
    /// places it now, like a drawn fill; the edge anti-aliases at MSAA resolution.
    /// Prefer the scoped `withClip(_:_:)`; push and pop must balance within the
    /// current surface (an unmatched pop is ignored).
    func pushClip(_ shape: Shape) {
        // Clipping is per surface and per frame (stencil levels); a recording is
        // surface-neutral, so a clip inside it can't replay. The body still draws,
        // just unclipped; clip where the batch is drawn instead.
        if isRecordingBatch {
            noteBatchRecording("withClip inside makeBatch { } is not recorded (the content draws unclipped); clip where the batch is drawn instead.")
            return
        }
        if svgRecorder != nil {
            svgRecorder?.commands.append(.clipPush(shape: shape, transform: transform))
            clipStack.append(ClipFrame(vertices: [], target: currentTarget))
            recomputeClipLevel()
            return
        }
        // Tessellate the region like a fill (libtess2, the shape's winding) and bake
        // the CTM, the same funnel `emit` uses. Color is unused (the clip pipelines
        // mask color writes off).
        let triangles = shape.triangulatedFill()
        var clipVertices: [OllinVertex] = []
        clipVertices.reserveCapacity(triangles.count)
        for p in triangles {
            var position = SIMD2<Float>(Float(p.x), Float(p.y))
            if !transformIsIdentity {
                let t = transform * SIMD3<Float>(position.x, position.y, 1)
                position = SIMD2<Float>(t.x, t.y)
            }
            clipVertices.append(OllinVertex(position: position, color: SIMD4<Float>()))
        }
        clipStack.append(ClipFrame(vertices: clipVertices, target: currentTarget))
        recomputeClipLevel()
        if let target = currentTarget {
            target.needsStencil = true
        } else {
            usesClipStencil = true
        }
        appendClipPush(clipVertices, level: activeClipLevel)
    }

    /// Lift the innermost clip region again (the end of a `withClip` block).
    func popClip() {
        guard let last = clipStack.last, last.target === currentTarget else { return }
        let level = activeClipLevel
        clipStack.removeLast()
        recomputeClipLevel()
        if svgRecorder != nil {
            svgRecorder?.commands.append(.clipPop)
            return
        }
        batches.append(GeometryBatch(kind: .clipPop, vertexStart: vertices.count,
                                     instanceStart: sdfInstances.count,
                                     imageStart: imageVertices.count,
                                     glyphStart: glyphVertices.count,
                                     pointStart: points.count,
                                     meshStart: meshVertices.count,
                                     sdfGroupStart: sdfGroups.count,
                                     sdf3DGroupStart: sdf3DGroups.count,
                                     target: currentTarget, clipLevel: level))
        currentKind = nil
    }

    /// Run `body` with drawing confined to `shape`'s filled region, restoring the
    /// previous clip (and, like `withTarget`, any drawing state the block changed)
    /// on exit. Nesting intersects regions.
    func withClip(_ shape: Shape, _ body: () -> Void) {
        pushClip(shape)
        pushState()
        body()
        popState()
        popClip()
    }

    /// Record one clip push as a batch: the region's fill triangles join `vertices`
    /// (they ride the triangle buffer) under a `.clipPush` batch at `level`.
    private func appendClipPush(_ clipVertices: [OllinVertex], level: Int) {
        batches.append(GeometryBatch(kind: .clipPush, vertexStart: vertices.count,
                                     instanceStart: sdfInstances.count,
                                     imageStart: imageVertices.count,
                                     glyphStart: glyphVertices.count,
                                     pointStart: points.count,
                                     meshStart: meshVertices.count,
                                     sdfGroupStart: sdfGroups.count,
                                     sdf3DGroupStart: sdf3DGroups.count,
                                     target: currentTarget, clipLevel: level))
        vertices.append(contentsOf: clipVertices)
        currentKind = nil
    }

    /// Re-record the pushes for the clip frames still open on `target` after
    /// `background(_:)` wiped the recorded batches, so drawing after the wipe stays
    /// clipped (the stencil pass replays from an empty buffer each frame).
    private func reemitClipPushes(target: RenderTarget?) {
        var level = 0
        for frame in clipStack where frame.target === target {
            level += 1
            appendClipPush(frame.vertices, level: level)
        }
    }

    // MARK: Retained batches (makeBatch / drawBatch)

    /// True while a `makeBatch { }` body records. The unsupported funnels (meshes,
    /// 3D fields, particles, layers, clipping, `background`) consult it and skip
    /// with a one-time note instead of corrupting the recording's run structure.
    private(set) var isRecordingBatch = false

    /// One-time notes for content skipped inside `makeBatch { }`, keyed by message
    /// so each prints once per drawer.
    private var batchRecordingNotes = Set<String>()
    func noteBatchRecording(_ message: String) {
        guard !batchRecordingNotes.contains(message) else { return }
        batchRecordingNotes.insert(message)
        print("Ollin: \(message)")
    }

    /// One-time notes for state a path can't honor (a width profile on an analytic
    /// shape, say), keyed by message so each prints once per drawer rather than
    /// every frame.
    private var drawerNotes = Set<String>()
    func noteOnce(_ message: String) {
        guard !drawerNotes.contains(message) else { return }
        drawerNotes.insert(message)
        print("Ollin: \(message)")
    }

    /// Record everything drawn in `body` into a reusable `Batch` (see `Batch`).
    /// The body records into fresh geometry surfaces (swapped in for the frame's),
    /// from an identity transform, on the main canvas, unclipped; drawing-state
    /// changes it makes are restored on exit, like `withState { }`. Under a
    /// whole-run vector export the body's calls are captured as vector commands
    /// instead, so `drawBatch` can splice them into the exported document.
    func makeBatch(_ body: () -> Void) -> Batch {
        if isRecordingBatch {
            noteBatchRecording("a makeBatch { } inside another makeBatch { } is not recorded; returning an empty batch.")
            return Batch()
        }
        // A vector export never builds GPU geometry (the recorder replaces
        // emission per funnel), so capture the body as vector commands instead.
        // The flag spans the whole export run, warmup frames included, so a batch
        // recorded anywhere in it carries the right representation.
        if OllinApp.isVectorExporting {
            let saved = svgRecorder
            let recorder = SVGRecorder()
            svgRecorder = recorder
            isRecordingBatch = true
            pushState()
            transform = matrix_identity_float3x3
            transformIsIdentity = true
            body()
            popState()
            isRecordingBatch = false
            svgRecorder = saved
            return Batch(svgCommands: recorder.commands)
        }

        // Swap fresh recording surfaces in for the frame's, so the body's geometry
        // and batch runs land in arrays the Batch can take whole. The gradient row
        // table swaps too: recorded instances bake row indices, and swapping makes
        // them handle-relative, resolved against the batch's own strip texture.
        var savedVertices: [OllinVertex] = []
        var savedSDF: [SDFInstance] = []
        var savedImage: [OllinImageVertex] = []
        var savedGlyph: [OllinImageVertex] = []
        var savedPoints: [OllinPoint] = []
        var savedGroups: [SDFGroupInstance] = []
        var savedNodes: [SDFNode] = []
        var savedBatches: [GeometryBatch] = []
        var savedRows: [[UInt8]] = []
        var savedRowIndex: [Ramp: Int] = [:]
        swap(&savedVertices, &vertices)
        swap(&savedSDF, &sdfInstances)
        swap(&savedImage, &imageVertices)
        swap(&savedGlyph, &glyphVertices)
        swap(&savedPoints, &points)
        swap(&savedGroups, &sdfGroups)
        swap(&savedNodes, &sdfNodes)
        swap(&savedBatches, &batches)
        swap(&savedRows, &gradientRows)
        swap(&savedRowIndex, &gradientRowIndex)
        // Neutralize the recording context: batch bookkeeping, the target/clip
        // stacks (the recording is target-neutral; drawBatch supplies both), and
        // the CTM. `pushState` restores the drawing state the body may change.
        let savedKind = currentKind
        let savedBatchBlend = currentBatchBlend
        let savedBatchDepth = currentBatchDepth
        let savedBatchClip = currentBatchClip
        var savedTargets: [TargetFrame] = []
        var savedClips: [ClipFrame] = []
        swap(&savedTargets, &targetStack)
        swap(&savedClips, &clipStack)
        let savedClipLevel = activeClipLevel
        activeClipLevel = 0
        currentKind = nil
        currentBatchClip = 0
        isRecordingBatch = true
        pushState()
        transform = matrix_identity_float3x3
        transformIsIdentity = true
        currentDepth = nil
        body()
        popState()
        isRecordingBatch = false

        let recorded = Batch(vertices: vertices, sdfInstances: sdfInstances,
                             imageVertices: imageVertices, glyphVertices: glyphVertices,
                             points: points, sdfGroups: sdfGroups, sdfNodes: sdfNodes,
                             gradientRows: gradientRows, innerBatches: batches)
        vertices = savedVertices
        sdfInstances = savedSDF
        imageVertices = savedImage
        glyphVertices = savedGlyph
        points = savedPoints
        sdfGroups = savedGroups
        sdfNodes = savedNodes
        batches = savedBatches
        gradientRows = savedRows
        gradientRowIndex = savedRowIndex
        targetStack = savedTargets
        clipStack = savedClips
        activeClipLevel = savedClipLevel
        currentKind = savedKind
        currentBatchBlend = savedBatchBlend
        currentBatchDepth = savedBatchDepth
        currentBatchClip = savedBatchClip
        return recorded
    }

    /// Replay a recorded `Batch`. The reference batch it appends carries the
    /// draw-time context: the CTM (moving the whole replay as a unit), the active
    /// target, clip level, and 2D depth; the recorded content's own state (colors,
    /// blends) replays as recorded. Active symmetry does not fold the replay;
    /// record the folds inside the batch instead.
    func drawBatch(_ batch: Batch) {
        if isRecordingBatch {
            noteBatchRecording("drawBatch inside makeBatch { } is not recorded; draw the batch outside the recording.")
            return
        }
        // A vector export splices the batch's captured vector commands under the
        // draw-time CTM. A batch recorded outside this export run has none; it
        // can only be empty here, since the whole run never builds GPU geometry.
        if let recorder = svgRecorder {
            for command in batch.svgCommands {
                guard case let .draw(r) = command else { continue }
                let composed = transformIsIdentity ? r.transform : transform * r.transform
                recorder.commands.append(.draw(RecordedSVG(geometry: r.geometry,
                                                           style: r.style,
                                                           transform: composed)))
            }
            return
        }
        guard !batch.isEmpty else { return }
        if batch.hasPointContent {
            currentTarget?.needsDepth = true   // 3D in a target → that pass carries depth
        }
        batches.append(GeometryBatch(kind: .retained, vertexStart: vertices.count,
                                     instanceStart: sdfInstances.count,
                                     imageStart: imageVertices.count,
                                     glyphStart: glyphVertices.count,
                                     pointStart: points.count,
                                     meshStart: meshVertices.count,
                                     sdfGroupStart: sdfGroups.count,
                                     sdf3DGroupStart: sdf3DGroups.count,
                                     blendMode: currentBlend, depth: currentDepth,
                                     target: currentTarget, clipLevel: activeClipLevel,
                                     retained: batch,
                                     retainedTransform: transformIsIdentity ? nil : transform))
        currentKind = nil   // the next primitive opens its own fresh batch
    }

    /// When set, draw calls are recorded as vector geometry for SVG export instead
    /// of being tessellated/SDF-encoded for the GPU (see SVGExport.swift). It lives
    /// outside the per-frame reset so the exporter owns its lifecycle.
    var svgRecorder: SVGRecorder?

    /// When set, 3D draw calls are collected as scene nodes for spatial export
    /// instead of being encoded for the GPU (see SpatialExport.swift). The
    /// three-dimensional sibling of `svgRecorder`, with the same lifecycle.
    var spatialRecorder: SpatialRecorder?

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

    /// Open a new batch when the geometry kind, the blend mode, the 2D depth, *or*
    /// the clip level changes; a no-op while all four are unchanged, so it's cheap
    /// to call per primitive.
    func ensureBatch(_ kind: GeometryKind) {
        guard currentKind != kind || currentBatchBlend != currentBlend
            || currentBatchDepth != currentDepth
            || currentBatchClip != activeClipLevel else { return }
        currentKind = kind
        currentBatchBlend = currentBlend
        currentBatchDepth = currentDepth
        currentBatchClip = activeClipLevel
        batches.append(GeometryBatch(kind: kind, vertexStart: vertices.count,
                                     instanceStart: sdfInstances.count,
                                     imageStart: imageVertices.count,
                                     glyphStart: glyphVertices.count,
                                     pointStart: points.count,
                                     meshStart: meshVertices.count,
                                     sdfGroupStart: sdfGroups.count,
                                     sdf3DGroupStart: sdf3DGroups.count,
                                     blendMode: currentBlend, depth: currentDepth,
                                     target: currentTarget, clipLevel: activeClipLevel))
    }

    /// Open a fresh `.image` batch carrying `image` as its texture. Unlike
    /// `ensureBatch`, this always appends — each image draw binds its own texture,
    /// so two consecutive images can't share a batch. Resets `currentKind` so a
    /// following triangle/SDF primitive reopens its own batch.
    func beginImageBatch(_ image: Image) {
        currentKind = .image
        currentBatchBlend = currentBlend
        currentBatchDepth = currentDepth
        currentBatchClip = activeClipLevel
        batches.append(GeometryBatch(kind: .image, vertexStart: vertices.count,
                                     instanceStart: sdfInstances.count,
                                     imageStart: imageVertices.count,
                                     glyphStart: glyphVertices.count,
                                     pointStart: points.count,
                                     meshStart: meshVertices.count,
                                     sdfGroupStart: sdfGroups.count,
                                     sdf3DGroupStart: sdf3DGroups.count,
                                     blendMode: currentBlend, image: image, depth: currentDepth,
                                     target: currentTarget, clipLevel: activeClipLevel))
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
                                     target: currentTarget, clipLevel: activeClipLevel))
        currentKind = nil
    }

    /// Open or continue the solid (untextured, non-wireframe) `.mesh3D` batch. Solid
    /// meshes merge into one batch as long as the blend, depth, and surface finish are
    /// unchanged — the finish is bound per batch as one uniform, so a change in
    /// `material(_:)` breaks the batch (like a blend-mode change does).
    private func ensureSolidMeshBatch(_ m: Material) {
        if currentKind == .mesh3D, currentBatchBlend == currentBlend,
           currentBatchDepth == currentDepth, currentBatchMaterial == m,
           currentBatchClip == activeClipLevel {
            return
        }
        currentKind = .mesh3D
        currentBatchBlend = currentBlend
        currentBatchDepth = currentDepth
        currentBatchMaterial = m
        currentBatchClip = activeClipLevel
        batches.append(GeometryBatch(kind: .mesh3D, vertexStart: vertices.count,
                                     instanceStart: sdfInstances.count,
                                     imageStart: imageVertices.count,
                                     glyphStart: glyphVertices.count,
                                     pointStart: points.count,
                                     meshStart: meshVertices.count,
                                     sdfGroupStart: sdfGroups.count,
                                     sdf3DGroupStart: sdf3DGroups.count,
                                     blendMode: currentBlend, depth: currentDepth,
                                     finish: m.gpuMaterial(), target: currentTarget,
                                     clipLevel: activeClipLevel))
    }

    /// Open a new `.sdfGroup3D` batch when the blend, depth, or surface finish changes;
    /// consecutive fields under one material merge (drawn as one instanced pass). Like
    /// the solid meshes, the finish is bound per batch as one `OllinMaterial` uniform,
    /// so a `material(_:)` change must break the batch for the fragment to see it.
    func ensureSDF3DBatch(_ m: Material) {
        if currentKind == .sdfGroup3D, currentBatchBlend == currentBlend,
           currentBatchDepth == currentDepth, currentBatchMaterial == m,
           currentBatchClip == activeClipLevel {
            return
        }
        currentKind = .sdfGroup3D
        currentBatchBlend = currentBlend
        currentBatchDepth = currentDepth
        currentBatchMaterial = m
        currentBatchClip = activeClipLevel
        batches.append(GeometryBatch(kind: .sdfGroup3D, vertexStart: vertices.count,
                                     instanceStart: sdfInstances.count,
                                     imageStart: imageVertices.count,
                                     glyphStart: glyphVertices.count,
                                     pointStart: points.count,
                                     meshStart: meshVertices.count,
                                     sdfGroupStart: sdfGroups.count,
                                     sdf3DGroupStart: sdf3DGroups.count,
                                     blendMode: currentBlend, depth: currentDepth,
                                     finish: m.gpuMaterial(), target: currentTarget,
                                     clipLevel: activeClipLevel))
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
        currentBatchClip = activeClipLevel
        batches.append(GeometryBatch(kind: .glyphAtlas, vertexStart: vertices.count,
                                     instanceStart: sdfInstances.count,
                                     imageStart: imageVertices.count,
                                     glyphStart: glyphVertices.count,
                                     pointStart: points.count,
                                     meshStart: meshVertices.count,
                                     sdfGroupStart: sdfGroups.count,
                                     sdf3DGroupStart: sdf3DGroups.count,
                                     blendMode: currentBlend, atlas: atlas, depth: currentDepth,
                                     target: currentTarget, clipLevel: activeClipLevel))
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
        // Layers are per-frame render passes; a recording holds only replayable
        // geometry, so a layer block inside it is skipped whole (running the body
        // would silently flatten the layer's content into the batch).
        if isRecordingBatch {
            noteBatchRecording("withTarget/withFeedback/withField inside makeBatch { } is not recorded (the block is skipped); draw into layers where the batch is drawn instead.")
            return
        }
        if !renderTargets.contains(where: { $0 === target }) { renderTargets.append(target) }
        targetStack.append(TargetFrame(target: target, snapshot: snapshot()))
        currentKind = nil    // force the first draw inside the target into a fresh batch
        recomputeClipLevel() // clipping is per surface: the layer starts unclipped
        pushState()
        body()
        popState()
        targetStack.removeLast()
        currentKind = nil    // and force the next main draw into a fresh, untagged batch
        recomputeClipLevel() // back on the enclosing surface's clip level
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

    /// Register `field` so the renderer steps it this frame even though nothing was
    /// drawn into it. A sim only evolves while its layer is among this frame's render
    /// targets, and `withField` is what normally puts it there. That is right for a sim
    /// you seed by drawing, but a self-organizing one (multi-scale Turing starts from
    /// noise and needs nothing) would otherwise sit frozen and read black, with no hint
    /// why. So reading the field registers it too, and the layer's clear color is what
    /// makes that safe: an unseeded frame renders a transparent seed, which composites
    /// nothing. Called from `SimField.image` and `SimField.filtered(_:)`.
    func ensureFieldSteps(_ field: SimField) {
        guard !isRecordingBatch, !renderTargets.contains(where: { $0 === field.writeLayer }) else { return }
        field.writeLayer.clearColor = .clear
        renderTargets.append(field.writeLayer)
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
        if instancedMeshVertices.count > s.instancedMesh {
            instancedMeshVertices.removeLast(instancedMeshVertices.count - s.instancedMesh)
        }
        if meshInstances.count > s.meshInstance {
            meshInstances.removeLast(meshInstances.count - s.meshInstance)
        }
    }

    /// Open a `.particles` batch drawing `count` instances from the GPU `buffer`.
    /// Like `beginImageBatch`, it always appends (each draw carries its own buffer)
    /// and resets `currentKind` so a following primitive reopens its own batch. The
    /// particle buffer's positions are in canvas space, so it rides no CTM.
    func recordParticles(_ buffer: ComputeBindable, count: Int) {
        // A particle batch reads a compute buffer the GPU rewrites every frame;
        // there's nothing static to retain.
        if isRecordingBatch {
            noteBatchRecording("drawParticles inside makeBatch { } is not recorded (particles are already GPU-resident); draw them where the batch is drawn.")
            return
        }
        guard count > 0 else { return }
        currentKind = .particles
        currentBatchBlend = currentBlend
        currentBatchDepth = currentDepth
        currentBatchClip = activeClipLevel
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
                                     depth: currentDepth, target: currentTarget,
                                     clipLevel: activeClipLevel))
    }

    /// Open a `.points3D` batch drawing `count` camera-facing splats straight from the
    /// GPU `buffer` (a compute-written `OllinPoint` array), rather than from the
    /// frame's uploaded point list. The 3D sibling of `recordParticles`: world-space
    /// positions the GPU already holds, so nothing round-trips through the CPU. A no-op
    /// without a camera, like `drawPointCloud`.
    func recordPointCloud(_ buffer: ComputeBindable, count: Int) {
        // Same reasoning as the particle path: the buffer is rewritten every frame, so
        // there is nothing static for a retained batch to hold.
        if isRecordingBatch {
            noteBatchRecording("a GPU point cloud inside makeBatch { } is not recorded (its points are already GPU-resident); draw it where the batch is drawn.")
            return
        }
        guard camera3D != nil, count > 0 else { return }
        // Vector export is 2D only, and a splat cloud has no outline to write.
        if svgRecorder != nil { return }
        if let spatialRecorder { spatialRecorder.skip("a GPU particle system"); return }
        currentTarget?.needsDepth = true   // 3D in a target → that pass carries depth
        // Left open to nothing, so a following `drawPointCloud` opens its own batch
        // rather than merging its uploaded points into this one (where they would be
        // passed over: a batch carrying a GPU buffer draws that buffer and nothing else).
        currentKind = nil
        currentBatchBlend = currentBlend
        currentBatchDepth = currentDepth
        currentBatchClip = activeClipLevel
        batches.append(GeometryBatch(kind: .points3D, vertexStart: vertices.count,
                                     instanceStart: sdfInstances.count,
                                     imageStart: imageVertices.count,
                                     glyphStart: glyphVertices.count,
                                     pointStart: points.count,
                                     meshStart: meshVertices.count,
                                     sdfGroupStart: sdfGroups.count,
                                     sdf3DGroupStart: sdf3DGroups.count,
                                     blendMode: currentBlend,
                                     particleBuffer: buffer, particleCount: count,
                                     depth: currentDepth, target: currentTarget,
                                     clipLevel: activeClipLevel))
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
        guard svgRecorder != nil else { return }
        let visibleStroke = (stroke != nil && strokeWidth > 0) ? stroke : nil
        // A width profile has no single `stroke-width` to ride on, so the stroke
        // exports as the region it covers: a filled outline, still vector and still
        // true to size. The fill, if any, stays the shape it was.
        if let visibleStroke, !strokeProfileShape.isUniform,
           let paths = geometry.strokePaths {
            if fill != nil { svgAppend(geometry, fill: fill, stroke: nil) }
            for (points, isClosed) in paths {
                if let outline = variableStrokeOutline(points, closed: isClosed) {
                    svgAppend(.path(outline), fill: visibleStroke, stroke: nil)
                }
            }
            return
        }
        svgAppend(geometry, fill: fill, stroke: visibleStroke)
    }

    /// Append one recorded command (and its symmetry copies) to the vector
    /// recorder. `stroke` is already resolved to what should actually be stroked.
    private func svgAppend(_ geometry: SVGGeometry, fill: Paint?, stroke: Paint?) {
        guard let recorder = svgRecorder else { return }
        let style = SVGStyle(fill: fill, stroke: stroke, strokeWidth: strokeWidth,
                             join: strokeJoinStyle, cap: strokeCapStyle)
        recorder.commands.append(.draw(RecordedSVG(geometry: geometry, style: style,
                                                   transform: transform)))
        // Symmetry replicates in vector form too: one more command per remaining
        // fold, the fold left-composed onto the CTM like the raster paths do.
        if let folds = symmetryFolds {
            for fold in folds.dropFirst() {
                recorder.commands.append(.draw(RecordedSVG(geometry: geometry, style: style,
                                                           transform: fold * transform)))
            }
        }
    }

    /// Shift origin-centered outline points into user space around `c`.
    func svgOffset(_ points: [Vector2], _ c: Vector2) -> [Vector2] {
        points.map { $0 + c }
    }

    /// Record a marching-squares traced outline, loops already in user space. A
    /// single boundary loop stays a plain polygon; a multi-loop trace becomes an
    /// even-odd path, which reconstructs the SDF's region exactly (crossing any
    /// zero contour flips inside/outside, which *is* the even-odd rule).
    func svgRecordTraced(_ loops: [[Vector2]], fill: Paint?, stroke: Paint?) {
        if loops.count == 1 {
            svgRecord(.polygon(loops[0]), fill: fill, stroke: stroke)
        } else if !loops.isEmpty {
            let contours = loops.map { Contour($0, closed: true) }
            svgRecord(.path(Shape(contours: contours, winding: .evenOdd)), fill: fill, stroke: stroke)
        }
    }

    /// The same, for loops in the shape's local space placed at `c`.
    func svgRecordTraced(_ loops: [[Vector2]], at c: Vector2, fill: Paint?, stroke: Paint?) {
        svgRecordTraced(loops.map { svgOffset($0, c) }, fill: fill, stroke: stroke)
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
        var strokeProfileShape: StrokeProfile
        var strokeOpacityShape: StrokeProfile
        var strokeBrushShape: Brush?
        var currentMaterial: Material
        var wireframeEnabled: Bool
        var currentMatcap: Image?
        var currentFont: ActiveFont
        var textPixelSize: Double
        var textAlignH: TextAlignH
        var textAlignV: TextAlignV
        var textRenderMode: TextMode
        var textWritingDirection: TextDirection
        var textJustifies: Bool
        var textHangsPunctuation: Bool
        var tintColor: Color?
        var currentBlend: BlendMode
        var currentDepth: Float?
        var symmetryFolds: [matrix_float3x3]?
    }

    // MARK: State setters (mirrors the bare API on `Sketch`)

    /// Set the background/clear color. This also wipes anything drawn
    /// so far this frame (background paints over everything). In accumulation mode
    /// (`noClear`) it additionally wipes the persistent canvas this frame — the
    /// way to reset a long exposure (see `backgroundSetThisFrame`).
    func background(_ color: Color) {
        // A background inside a batch recording would wipe the recording itself;
        // it's the frame's wipe, not batch content, so it can't be recorded.
        if isRecordingBatch {
            noteBatchRecording("background(_:) inside makeBatch { } is not recorded; set the background where the batch is drawn.")
            return
        }
        // Inside a `withTarget` block, background clears *that target* (its clear
        // color + its geometry so far), leaving the main canvas and global clear
        // color untouched.
        if let frame = targetStack.last {
            frame.target.clearColor = color
            truncate(to: frame.snapshot)
            currentKind = nil
            currentBatchDepth = nil
            // Clip pushes recorded inside this target were truncated too; re-record
            // the still-open ones so drawing after the wipe stays clipped.
            reemitClipPushes(target: frame.target)
            return
        }
        // Inside a view box the frame's clear color belongs to the whole canvas and
        // to every other box on it, so a wipe here is a filled rectangle over this
        // box's own virtual canvas instead. The clip in force keeps it inside the
        // box, and drawing it in call order covers whatever the box drew first.
        if let canvas = viewBoxCanvases.last {
            let saved = fillPaint, savedStroke = strokePaint
            fillPaint = .color(color)
            strokePaint = nil
            drawRect(Rectangle(x: 0, y: 0, width: canvas.x, height: canvas.y))
            fillPaint = saved
            strokePaint = savedStroke
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
        instancedMeshVertices.removeAll(keepingCapacity: true)
        meshInstances.removeAll(keepingCapacity: true)
        // Mover ranges index the mesh list the wipe just emptied; a range left
        // behind would send the velocity pass past the frame's vertex buffer.
        // (The history keeps its entries: a redrawn block this frame takes a
        // fresh occurrence key, and unmatched entries prune next frame.)
        moverRanges.removeAll(keepingCapacity: true)
        sdfGroups.removeAll(keepingCapacity: true)
        sdfNodes.removeAll(keepingCapacity: true)
        sdf3DGroups.removeAll(keepingCapacity: true)
        sdf3DNodes.removeAll(keepingCapacity: true)
        batches.removeAll(keepingCapacity: true)
        currentKind = nil
        currentBatchDepth = nil
        hasDepthScene = false   // background wipes the recorded scene quad too
        // A background inside a withClip block: the recorded pushes were wiped with
        // the batches, so re-record the still-open ones.
        reemitClipPushes(target: nil)
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

    /// Replicate subsequent 2D drawing into `folds` copies rotated evenly around
    /// the current origin; `mirrored: true` adds a reflected copy per fold (the
    /// kaleidoscope's dihedral symmetry, mirrored across the local x-axis). The
    /// fold transforms are built once from the CTM at this call, each local
    /// rotation/reflection conjugated into canvas space, so they pivot on the
    /// origin (and axes) the transform stack has established here, and later
    /// transforms compose *inside* every fold. `folds <= 1` with no mirror turns
    /// symmetry off, as `noSymmetry()` does.
    func symmetry(_ folds: Int, mirrored: Bool = false) {
        let n = max(1, folds)
        guard n > 1 || mirrored else { symmetryFolds = nil; return }
        // Conjugate each local fold by the CTM: F = C · R · C⁻¹, so a replica's
        // effective CTM is F · C · L (later transforms L ride inside the fold).
        // A degenerate CTM (zero scale) can't be conjugated; fold about the
        // canvas origin instead of poisoning the geometry with non-finite math.
        let base = transform
        let invertible = abs(base.determinant) > 1e-12
        let c = invertible ? base : matrix_identity_float3x3
        let cInv = invertible ? c.inverse : matrix_identity_float3x3
        let mirror = Drawer.scaling(1, -1)
        var built: [matrix_float3x3] = []
        built.reserveCapacity(mirrored ? 2 * n : n)
        for k in 0..<n {
            let rot = Drawer.rotation(Float(Double(k) * .tau / Double(n)))
            // Keep fold 0 the exact identity so the primary copy is untouched.
            built.append(k == 0 ? matrix_identity_float3x3 : c * rot * cInv)
            if mirrored { built.append(c * (rot * mirror) * cInv) }
        }
        symmetryFolds = built
    }

    /// Stop replicating; back to drawing each call once (the default).
    func noSymmetry() { symmetryFolds = nil }

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

    /// Set how the stroke width varies along a path (see `StrokeProfile`). The
    /// profile multiplies `strokeWeight`, so `.taper()` makes a mark that swells to
    /// the set weight in the middle and vanishes at both ends. Affects the fringe
    /// stroked paths; the analytic SDF shapes keep their constant width.
    func strokeProfile(_ profile: StrokeProfile) { strokeProfileShape = profile }

    /// Return to a constant-width stroke (the default).
    func noStrokeProfile() { strokeProfileShape = .uniform }

    /// Repeat a shape along the path instead of expanding it into a continuous
    /// ribbon (see `Brush`). The stamp takes its size from `strokeWeight` and its
    /// color from `stroke`, and an ambient `strokeProfile` still shapes the size
    /// along the path. Affects the stroked paths; the analytic SDF shapes keep
    /// their continuous outline.
    func strokeBrush(_ brush: Brush) { strokeBrushShape = brush }

    /// Return to a continuous stroke (the default).
    func noStrokeBrush() { strokeBrushShape = nil }

    /// The half-width at each point of a path, or `nil` when the stroke is the
    /// plain constant-width kind. `points` is the path as it will be expanded
    /// (already flattened and de-duplicated); `closed` wraps the last segment back
    /// to the first, which also makes the profile's `0` and `1` ends meet.
    ///
    /// Width is sampled *per path vertex* rather than per segment, which is what
    /// keeps the joins simple: the two segments meeting at a corner agree on the
    /// width there, so a corner is still the constant-width corner problem, solved
    /// at the local width.
    func strokeHalfWidths(for points: [Vector2], closed: Bool) -> [Double]? {
        guard !strokeProfileShape.isUniform, points.count >= 2 else { return nil }
        let n = points.count
        var cum = [Double](repeating: 0, count: n)
        for i in 1..<n { cum[i] = cum[i - 1] + (points[i] - points[i - 1]).length }
        var total = cum[n - 1]
        if closed { total += (points[0] - points[n - 1]).length }
        let invTotal = total > 0 ? 1 / total : 0

        let hw = strokeWidth / 2
        return (0..<n).map { i in
            // The tangent at a vertex: the mean of the segments meeting there, so a
            // nib's width turns continuously through a corner instead of jumping.
            let prev = (i == 0) ? (closed ? n - 1 : 0) : i - 1
            let next = (i == n - 1) ? (closed ? 0 : n - 1) : i + 1
            let d = points[next] - points[prev]
            let len = d.length
            let dir = len > 1e-9 ? d / len : Vector2(1, 0)
            return hw * strokeProfileShape(cum[i] * invTotal, direction: dir)
        }
    }

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

    /// Set the base direction a line of text runs in (see `TextDirection`).
    func textDirection(_ direction: TextDirection) { textWritingDirection = direction }

    /// Stretch wrapped text so both edges of the box are flush (see `textJustify`).
    func textJustify(_ on: Bool = true) { textJustifies = on }

    /// Leave wrapped text at its natural width, the default.
    func noTextJustify() { textJustifies = false }

    /// Let a full stop or comma at the end of a line sit past that end, rather than
    /// pushing the character it follows onto the next line (see
    /// `textHangingPunctuation`).
    func textHangingPunctuation(_ on: Bool = true) { textHangsPunctuation = on }

    /// Keep every character inside the box, the default.
    func noTextHangingPunctuation() { textHangsPunctuation = false }

    // MARK: 3D camera & point clouds

    /// Set the active 3D camera for this frame (see `Camera3D`); drawing a point
    /// cloud needs one. The camera is per-frame state and resets to none each
    /// frame, so set it from `draw()` (3D sketches typically animate it). Setting
    /// it is what puts the frame into 3D — the renderer allocates a depth buffer
    /// and draws 3D geometry through it. A 2D-only frame never calls this.
    func camera(_ camera: Camera3D) { camera3D = camera }

    /// Re-aim the frame's camera after `draw()` has run, for the two renders the
    /// spatial-video export makes of a single drawn frame.
    ///
    /// A stereo pair has to come out of **one** `draw()`. Running it twice would
    /// roll the sketch's randomness twice and step every simulation twice, and the
    /// sims that document themselves as not reproducible frame for frame would
    /// hand the two eyes genuinely different content. So the frame is drawn once
    /// and rendered twice, with the camera swapped in between. `previous` moves
    /// with it because motion blur measures against the last frame's camera, and
    /// left against right would read the eye separation itself as a sideways
    /// lurch of the whole world.
    ///
    /// What this cannot re-aim is anything the sketch already flattened during
    /// `draw()`: a `project()`, a `depth(at:)` placement, a billboard. Those keep
    /// the center camera's answer in both eyes, which puts them flat on the
    /// screen plane, and for the notices and overlays that use them that is
    /// usually what you want anyway.
    func aimStereoEye(_ camera: Camera3D?, previous: Camera3D?) {
        camera3D = camera
        previousCamera3D = previous
    }

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

    /// Place a decal for this frame: a projection box centered at `position`,
    /// stamping the picture along `direction` onto whatever mesh surfaces sit
    /// inside it. Per-frame like a light; the box's world→box rows are built
    /// once here so the fragment pays one matrix row-dot per axis. `height`
    /// defaults to the picture's own proportions, `depth` to the smaller of
    /// the two sides. Capped at `OLLIN_MAX_DECALS` per frame with a one-time
    /// note; repeated placements of one `Decal` share a texture layer.
    func placeDecal(_ decal: Decal, at position: Vector3, direction: Vector3,
                    width: Double, height: Double?, depth: Double?,
                    roll: Double, opacity: Double) {
        guard placedDecals.count < Int(OLLIN_MAX_DECALS) else {
            noteOnce("a frame holds up to \(Int(OLLIN_MAX_DECALS)) decals; the extras were skipped.")
            return
        }
        let h = height ?? width * decal.aspect
        let dp = depth ?? min(width, h)
        let axisLength = direction.length
        guard width > 0, h > 0, dp > 0, axisLength > 1e-9, opacity > 0 else { return }
        let axis = direction / axisLength
        // The projector frame, the light-cookie convention exactly (the
        // measured `right = axis × ref` order): +up in box space reads as the
        // image's top, and `roll` spins the picture about the projection axis.
        let ref = abs(axis.y) > 0.99 ? Vector3(0, 0, 1) : Vector3(0, 1, 0)
        var right = axis.cross(ref).normalized
        var up = right.cross(axis)
        if roll != 0 {
            let c = cos(roll), s = sin(roll)
            let spun = right * c + up * s
            up = up * c - right * s
            right = spun
        }
        func row(_ a: Vector3, _ size: Double) -> SIMD4<Float> {
            SIMD4<Float>(Float(a.x / size), Float(a.y / size), Float(a.z / size),
                         Float(-(a.x * position.x + a.y * position.y + a.z * position.z) / size))
        }
        let layer: Int
        if let found = usedDecals.firstIndex(of: decal) {
            layer = found
        } else {
            usedDecals.append(decal)
            layer = usedDecals.count - 1
        }
        var gpu = OllinDecal()
        gpu.row0 = row(right, width)
        gpu.row1 = row(up, h)
        gpu.row2 = row(axis, dp)
        gpu.axis = SIMD4<Float>(Float(axis.x), Float(axis.y), Float(axis.z), 0)
        gpu.params = SIMD4<Float>(Float(layer), 0, 0, Float(min(opacity, 1)))
        placedDecals.append(gpu)
    }

    /// The frame's decal list packed for fragment buffer 2 (`OllinDecals`):
    /// the placements in call order behind their count, zero-filled past it.
    func decalsUniform() -> OllinDecals {
        var u = OllinDecals()
        let n = min(placedDecals.count, Int(OLLIN_MAX_DECALS))
        u.count = Int32(n)
        withUnsafeMutableBytes(of: &u.decals) { raw in
            let buf = raw.bindMemory(to: OllinDecal.self)
            for i in 0..<n { buf[i] = placedDecals[i] }
        }
        return u
    }

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

    /// Add contact shadows this frame: a short screen-space ray marched from each mesh
    /// pixel toward the casting light through the scene's depth, darkening the fine
    /// contact where a shadow map's resolution and bias leave a gap (the seam under a
    /// resting object). Per-frame state like the lights; set it in `draw()` beside
    /// `castShadows()`, which it refines (a no-op without a caster or a camera).
    /// `length` is the ray's reach in world units; nil derives it from the scene scale.
    func contactShadows(length: Double? = nil) {
        contactShadowsEnabled = true
        contactShadowLength = length.map { max(0, $0) }
    }

    /// Stop adding contact shadows (the default). Per-frame state.
    func noContactShadows() {
        contactShadowsEnabled = false
        contactShadowLength = nil
    }

    /// Ray-trace reflections of the scene off its physically-based surfaces this frame.
    /// Per-frame state like the lights; set it in `draw()`. Every solid mesh reflects (the
    /// renderer reuses the shadow-caster acceleration structure, which already covers them all);
    /// a no-op without a ray-tracing device or an environment to fall back to on a miss.
    func rayTracedReflections(_ enabled: Bool = true) { rayTracedReflectionsEnabled = enabled }

    /// Gather real-time global illumination this frame: bounce light between the scene's
    /// surfaces through a re-traced probe grid. Per-frame state like the lights; set it
    /// in `draw()`. `intensity` scales the bounce (1 = physical). A no-op without a
    /// ray-tracing device, a camera, or lights.
    func globalIllumination(_ enabled: Bool = true, intensity: Double = 1) {
        globalIlluminationEnabled = enabled
        giIntensity = max(0, intensity)
    }

    /// Stop gathering global illumination (the default). Per-frame state.
    func noGlobalIllumination() { globalIlluminationEnabled = false }

    /// Render caustics this frame: the light patterns a transmissive glass or a
    /// polished metal focuses onto the rough surfaces around it, photon-traced from
    /// the caster light (the shadow system's caster priority: directional, then
    /// spot, then point) and splatted where they land. `intensity` scales the
    /// brightness (1 = physical); `dispersion` splits refracted paths by
    /// wavelength (0 = none, 1 = full rainbow). Per-frame state like the lights;
    /// set it in `draw()`. A no-op without a ray-tracing device, a camera, or a
    /// light, and inert while no material transmits or mirrors.
    func caustics(intensity: Double = 1, dispersion: Double = 0) {
        causticsEnabled = true
        causticsIntensity = max(0, intensity)
        causticsDispersion = max(0, min(1, dispersion))
    }

    /// Stop rendering caustics (the default). Per-frame state.
    func noCaustics() { causticsEnabled = false }

    /// Temporally anti-alias the 3D scene this frame: jitter the projection
    /// sub-pixel and accumulate across frames (live), or average N deterministic
    /// jittered renders within the frame (export). Per-frame state like the lights;
    /// set it in `draw()`. A no-op without an active 3D camera.
    func temporalAntialiasing(_ enabled: Bool = true) { temporalAAEnabled = enabled }

    /// Stop temporally anti-aliasing (the default). Per-frame state.
    func noTemporalAntialiasing() { temporalAAEnabled = false }

    /// Temporally upscale the 3D scene this frame: live, the whole canvas renders
    /// at a reduced resolution and is reconstructed full-size from the jittered
    /// history, buying performance headroom on a heavy scene. `quality` picks the
    /// render fraction (`.performance` half-size, `.default` two-thirds,
    /// `.detail` three-quarters), clamped to what the GPU supports. Per-frame
    /// state like the lights; set it in `draw()`. A no-op without an active 3D
    /// camera or on a GPU without temporal-scaling support; the headless/export
    /// path renders full-resolution with the temporal-AA supersample instead.
    func temporalUpscaling(_ quality: RenderQuality = .default) {
        temporalUpscalingEnabled = true
        temporalUpscalingQuality = quality
    }

    /// Stop temporally upscaling (the default). Per-frame state.
    func noTemporalUpscaling() { temporalUpscalingEnabled = false }

    /// Motion-blur the 3D scene this frame: streak each pixel along its screen
    /// motion, camera motion read from the depth buffer and per-object motion from
    /// `withMotion` blocks. `shutter` is the fraction of a frame the virtual
    /// shutter stays open (0.5 = the film-standard 180-degree look). Per-frame
    /// state like the lights; set it in `draw()`. A no-op without an active 3D
    /// camera, and on the very first frame (nothing has moved yet).
    func motionBlur(shutter: Double = 0.5) {
        motionBlurEnabled = true
        motionBlurShutter = max(0, shutter)
    }

    /// Add the flare this lens makes of the frame's bright lights. Per-frame state
    /// like the lights; set it in `draw()`. A no-op without a perspective 3D camera
    /// or with no lights set.
    func lensFlare(_ flare: LensFlare = LensFlare()) { lensFlareSetting = flare }

    /// Stop flaring (the default). Per-frame state.
    func noLensFlare() { lensFlareSetting = nil }

    /// Stop motion-blurring (the default). Per-frame state.
    func noMotionBlur() { motionBlurEnabled = false }

    /// Set the global-illumination quality to a hardware-relative tier (the renderer picks
    /// the rays per probe for the GPU, and the headless convergence depth). Persistent
    /// (set once, in `setup()` or `draw()`).
    func globalIlluminationQuality(_ quality: RenderQuality) { giQualitySetting = quality }

    /// Set the caustics quality to a hardware-relative tier (the renderer picks the photon
    /// budget and emission-map size for the GPU). Persistent (set once, in `setup()` or
    /// `draw()`).
    func causticsQuality(_ quality: RenderQuality) { causticsQualitySetting = quality }

    /// Set the soft-shadow quality to a hardware-relative tier (the renderer picks the ray
    /// count for the GPU). Persistent (set once, in `setup()` or `draw()`).
    func shadowQuality(_ quality: RenderQuality) { shadowQualitySetting = .tier(quality) }

    func reflectionQuality(_ quality: RenderQuality) { reflectionQualitySetting = quality }

    /// Set how many surfaces a reflected ray may shade, clamped to 2…8. Persistent.
    func reflectionBounces(_ count: Int) {
        reflectionBouncesSetting = max(2, min(count, Int(OLLIN_MAX_REFLECTION_BOUNCES)))
    }

    /// Trace a rough surface's reflection as a lobe rather than a mirror ray. Persistent.
    func glossyReflections(_ enabled: Bool) { glossyReflectionsEnabled = enabled }

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

    /// Wrap this frame's 3D scene in fog. Per-frame state like the lights; set it in
    /// `draw()`. Every 3D surface fades toward the fog color with distance (and, with a
    /// height falloff, with depth below the fog's thinning), and the air itself washes
    /// over the backdrop. (`noFog()` turns it back off.)
    func fog(_ color: Color, density: Double, heightFalloff: Double) {
        fogColor = color
        fogDensity = max(0, density)
        fogHeightFalloff = max(0, heightFalloff)
        aerialActive = false
    }

    /// Clear the fog (the default). Per-frame state.
    func noFog() {
        fogColor = nil
        fogDensity = 0
        fogHeightFalloff = 0
    }

    /// Wrap this frame's 3D scene in aerial perspective: the fog integral split by
    /// wavelength, so a far surface warms as the short wavelengths scatter out of its
    /// light while the air in front of it adds the sun's light scattered toward the
    /// eye (blue side-on, whiter and brighter looking sunward). Replaces `fog`; the
    /// two are exclusive and the last call wins. Per-frame state like the lights.
    func aerialPerspective(density: Double?, haziness: Double, heightFalloff: Double,
                           sun: Vector3?) {
        aerialActive = true
        fogColor = nil
        aerialDensity = density.map { max(0, $0) }
        aerialHaziness = min(1, max(0, haziness))
        fogHeightFalloff = max(0, heightFalloff)
        aerialSun = sun
    }

    /// Turn aerial perspective back off (the default). Per-frame state.
    func noAerialPerspective() { aerialActive = false }

    /// Make this frame's directional and spot lights visible in the air: a per-pixel march
    /// accumulates the light scattered toward the eye, so cones, cookies, IES profiles, and
    /// cast shadows become beams and shafts. Per-frame state like the lights. Works with or
    /// without `fog` (alone, the air stays clear and only the beams appear).
    func volumetricLight(_ amount: Double, anisotropy: Double) {
        volumetricAmount = max(0, amount)
        volumetricAnisotropy = min(0.99, max(-0.99, anisotropy))
    }

    /// Turn the volumetric march back off (the default). Per-frame state.
    func noVolumetricLight() { volumetricAmount = 0 }

    /// Set the volumetric march's quality to a tier (the renderer resolves the step budget;
    /// exports resolve `.default` up to `.detail`). Persistent like `shadowQuality`.
    func volumetricQuality(_ quality: RenderQuality) { volumetricQualitySetting = .tier(quality) }

    /// Set the volumetric march's step count to an exact value, clamped to 8…128
    /// (hardware-independent). Persistent.
    func volumetricSteps(_ count: Int) { volumetricQualitySetting = .absolute(max(8, min(count, 128))) }

    /// The molecular (Rayleigh) extinction's RGB ratios, normalized to the green
    /// channel: the 1/wavelength^4 law at the measured sea-level coefficients
    /// (5.802, 13.558, 33.1) e-6 per meter, so blue extincts ~2.4x green and red
    /// ~0.43x. Normalizing to green keeps `density` meaning what fog's does: the
    /// (green) optical depth per world unit. The shader mirrors these by hand
    /// (`OLLIN_AERIAL_RAYLEIGH`); keep the two in step.
    static let aerialRayleighRatios = SIMD3<Double>(0.428, 1.0, 2.442)
    /// The aerosol phase's forward anisotropy (the standard atmospheric value): the
    /// bright halo leaning into the sun. Fixed rather than a knob; `haziness` decides
    /// how much of the extinction that lobe owns.
    static let aerialMieAnisotropy = 0.76

    /// The world direction toward the sun the aerial in-scatter uses: the sketch's
    /// explicit override, else the `.sky` environment's sun carried through its
    /// rotation (the skybox samples the environment at R_y(rotation) times the view
    /// ray, so content sits at R_y(-rotation) in the world), else the first
    /// directional light (whose `direction` is the light's travel, so the sun is its
    /// negation), else a default 35-degree elevation facing +z.
    private func resolvedAerialSun() -> Vector3 {
        if let s = aerialSun, s.length > 1e-6 { return s.normalized }
        if let env = environment, case .sky(_, let elevation, _) = env.source {
            let ce = cos(elevation)
            return Vector3(-sin(env.rotation) * ce, sin(elevation), cos(env.rotation) * ce)
        }
        if let d = activeLights.first(where: { $0.kind == .directional }),
           d.direction.length > 1e-6 {
            return (-d.direction).normalized
        }
        let e = 35.0 * .pi / 180
        return Vector3(0, sin(e), cos(e))
    }

    /// The sun radiance feeding the aerial in-scatter: white dimmed by the molecular
    /// extinction along the slant path down through the atmosphere (airmass roughly
    /// 1/sin(elevation)), so a low sun feeds the haze warm light and a sunset run
    /// reddens the whole aerial term, times a gain calibrated so a far surface under
    /// the defaults settles near the procedural sky's own horizon tone.
    static func aerialSunRadiance(elevationSine: Double) -> SIMD3<Float> {
        let airmass = 1.0 / max(elevationSine, 0.03)
        let depth = 0.12 * airmass
        let gain = 2.0
        let r = aerialRayleighRatios
        return SIMD3<Float>(Float(exp(-r.x * depth) * gain),
                            Float(exp(-r.y * depth) * gain),
                            Float(exp(-r.z * depth) * gain))
    }

    /// Pack this frame's effective lighting into the GPU uniform. The mode decides
    /// the source: `.off` shades nothing (flat unlit, `enabled == 0`), `.auto` uses
    /// the default rig (the out-of-box shaded look), `.custom` uses the sketch's own
    /// lights and ambient.
    func makeLighting() -> OllinLighting {
        var u = OllinLighting()
        u.shadowLight = -1   // no shadows unless a caster is found below
        // Rebuilt below while packing; cleared first so the `.off`/`.auto` paths
        // leave no stale layers for the renderer's texture-array caches.
        usedIESProfiles.removeAll(keepingCapacity: true)
        usedLightCookies.removeAll(keepingCapacity: true)
        if let eye = camera3D?.eye {
            u.cameraPosition = SIMD4<Float>(Float(eye.x), Float(eye.y), Float(eye.z), 0)
        }
        // Atmosphere: the fog/volumetric constants gate every carrier's fog branch
        // (w = 0 leaves it untaken, byte-identical). Packed ahead of the `.off` early
        // return below on purpose: fog is a property of the air, so an unlit
        // (`noLights()`) scene still fogs; only the shaft march needs the lights.
        if aerialActive {
            // Aerial perspective rides the same slots under mode 2 (every fog gate
            // checks w > 0, so the carriers stay armed and pick the model with one
            // compare), plus the sun and the wavelength split in the two tail fields.
            // A nil density derives from the camera framing (the contact-shadow
            // default's rule), so a bare call reads alike at any scene scale.
            let radius = camera3D.map { max(($0.eye - $0.target).length, 1e-4) } ?? 1000
            let density = aerialDensity ?? 0.35 / radius
            let sun = resolvedAerialSun()
            u.fogColor = SIMD4<Float>(0, 0, 0, 2)
            u.fogParams = SIMD4<Float>(Float(density), Float(fogHeightFalloff),
                                       Float(volumetricAmount), Float(volumetricAnisotropy))
            u.fogParams2 = SIMD4<Float>(0, Float(camera3D?.far ?? 0), 0, 0)
            u.aerialSun = SIMD4<Float>(Float(sun.x), Float(sun.y), Float(sun.z),
                                       Float(Drawer.aerialMieAnisotropy))
            let tint = Drawer.aerialSunRadiance(elevationSine: sun.y)
            u.aerialLight = SIMD4<Float>(tint.x, tint.y, tint.z, Float(aerialHaziness))
        } else if fogColor != nil || volumetricAmount > 0 {
            let c = fogColor ?? .black
            u.fogColor = SIMD4<Float>(Float(Color.srgbToLinear(c.red)),
                                      Float(Color.srgbToLinear(c.green)),
                                      Float(Color.srgbToLinear(c.blue)), 1)
            u.fogParams = SIMD4<Float>(Float(fogDensity), Float(fogHeightFalloff),
                                       Float(volumetricAmount), Float(volumetricAnisotropy))
            // x (the march's step budget) stays 0 here: the renderer owns the
            // quality-to-budget mapping and fills it at encode time. y caps the air
            // backdrop's march at the camera's far plane.
            u.fogParams2 = SIMD4<Float>(0, Float(camera3D?.far ?? 0), 0, 0)
        }
        let ambient: Color
        switch lightingMode {
        case .off:
            u.enabled = 0
            return u   // flat, unlit; lights/ambient/shadows unused
        case .auto:
            // An environment lights the scene through IBL, so it stands in for the
            // auto rig: no default lights, no flat ambient (the irradiance map is the
            // ambient). A sketch that wants both adds its own lights (→ `.custom`).
            ambient = environment != nil ? .black : Drawer.defaultAmbient
        case .custom:
            ambient = ambientLightColor ?? .black
        }
        let activeLights = self.activeLights
        u.enabled = 1
        // The reflection chain's length. Packed always (the shader reads it only past the
        // shipped pair, and only with `rtReflections` on), so it needs no renderer gate.
        u.rtReflectionBounces = Int32(reflectionBouncesSetting)
        // The glossy lobe's roughness ceiling. Packed always and inert until the renderer
        // turns the deferred reflection on (the trace and the fragment both read it inside
        // that branch), so it needs no gate of its own.
        u.rtReflectionGloss = glossyReflectionsEnabled ? Drawer.glossyReflectionCeiling : 0
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
                for i in 0..<count {
                    let light = activeLights[i]
                    // Light shaping rides two texture arrays; the packed layer
                    // index is the profile/cookie's position in the frame's
                    // deduped list (the renderer bakes the arrays from these).
                    var profileLayer = -1, cookieLayer = -1
                    if light.kind == .point || light.kind == .spot, let p = light.profile {
                        if let found = usedIESProfiles.firstIndex(of: p) {
                            profileLayer = found
                        } else {
                            usedIESProfiles.append(p)
                            profileLayer = usedIESProfiles.count - 1
                        }
                    }
                    if light.kind == .spot, let c = light.cookie {
                        if let found = usedLightCookies.firstIndex(of: c) {
                            cookieLayer = found
                        } else {
                            usedLightCookies.append(c)
                            cookieLayer = usedLightCookies.count - 1
                        }
                    }
                    buf[i] = Drawer.packLight(light, profileLayer: profileLayer,
                                              cookieLayer: cookieLayer)
                }
            }
        }
        // Shadow casters. A frame casts from a small ordered list of lights, so a key
        // light and a spot both throw a shadow. Slot 0 is the
        // *primary* caster: it keeps the priority the single caster had (a directional,
        // else a spot, else a point, else a rect/disk panel), the single-caster fields
        // below mirror it, and every dependent system still follows it alone (fog and
        // volumetric shafts, subsurface transmittance, contact shadows, the marched-field
        // cast, caustics, the traced export). The rest fill slots 1 upward in the order
        // the sketch set them, and only the lit mesh path dims by them.
        //
        // Each 2D caster renders into its own layer of the shadow-map array, and **the
        // layer index is the slot index**, so slot 0 owns layer 0 whatever kind it is and
        // a helper that reads the primary caster can name layer 0 as a constant. A tube
        // emits radially with no facing axis to render a map from, so it never casts. A
        // point light casts from any slot: the renderer hands each point caster its own
        // cube of the cube-map array, or traces every one of them against the frame's one
        // acceleration structure.
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

            /// One light packed as a caster: the projection its map is rendered with and
            /// the constants the fragment samples that map by. Every field a kind leaves
            /// alone stays zero, which is the sentinel each consumer already reads.
            func packCaster(at index: Int) -> OllinShadowCaster {
                var c = OllinShadowCaster()
                c.lightIndex = Int32(index)
                c.strength = 1
                let light = activeLights[index]
                switch light.kind {
                case .directional:
                    // Look from above the target along the light's travel direction, an
                    // orthographic box sized to the scene.
                    let dirToLight = simd_normalize((light.direction * -1).normalized.simd3)
                    let d = 2 * r
                    let eye = target + dirToLight * d
                    // Pick an up vector not parallel to the light direction.
                    let up: SIMD3<Float> = abs(dirToLight.y) > 0.99 ? SIMD3<Float>(0, 0, 1) : SIMD3<Float>(0, 1, 0)
                    let view = Camera3D.lookAt(eye: eye, center: target, up: up)
                    let proj = Camera3D.orthographic(height: 2 * r, aspect: 1,
                                                     near: max(0.01, d - 1.5 * r), far: d + 1.5 * r)
                    c.lightViewProjection = proj * view
                    c.texelWorld = (2 * r) / Float(Drawer.shadowMapResolution)
                    // PCSS (`kind` 0): the penumbra radius in texels, and `depthB` = 0, the
                    // sentinel for an orthographic map (the shader uses plain depth
                    // separation, no perspective linearization).
                    c.depthA = lightSizeTexels
                    c.depthB = 0
                    // Depth→world-distance constants for the transmittance thickness read:
                    // an orthographic map's depth is already linear, so the shader only
                    // needs the projection's own scale to speak world units (z = 0 flags
                    // the orthographic form).
                    c.linearize = SIMD4<Float>(proj.columns.2.z, proj.columns.3.z, 0, 0)
                case .spot:
                    // A perspective frustum from the light's position, aimed down its cone
                    // axis, the vertical field of view set to the full cone angle (a small
                    // margin so the soft penumbra edge isn't clipped).
                    let eye = light.position.simd3
                    let axis = simd_normalize(light.direction.normalized.simd3)
                    let dist = max(simd_distance(eye, target), 1)
                    let center = eye + axis * dist
                    let up: SIMD3<Float> = abs(axis.y) > 0.99 ? SIMD3<Float>(0, 0, 1) : SIMD3<Float>(0, 1, 0)
                    let view = Camera3D.lookAt(eye: eye, center: center, up: up)
                    let fovY = Float(min(light.coneAngle * 1.05, Double.pi - 0.05))
                    let proj = Camera3D.perspective(fovY: fovY, aspect: 1,
                                                    near: max(0.1, dist - 1.5 * r), far: dist + 1.5 * r)
                    c.lightViewProjection = proj * view
                    // A perspective texel grows with depth; size the normal-offset bias from
                    // the frustum at the scene center (where the receivers mostly sit).
                    c.texelWorld = (2 * tan(fovY * 0.5) * dist) / Float(Drawer.shadowMapResolution)
                    // PCSS (`kind` 0): the penumbra radius in texels. `depthB` carries the
                    // projection's [2][2] term (column 2, z in column-major simd), which is
                    // all the shader needs to linearize the perspective depth for the
                    // penumbra ratio (the [3][2] term cancels). It's negative, which also
                    // flags the spot path.
                    c.depthA = lightSizeTexels
                    c.depthB = proj.columns.2.z
                    // Both projection constants, for the transmittance thickness read: an
                    // absolute world distance (unlike the penumbra ratio) needs [3][2] too
                    // (z = 1 flags the perspective form).
                    c.linearize = SIMD4<Float>(proj.columns.2.z, proj.columns.3.z, 1, 0)
                case .point:
                    // An omnidirectional caster. The renderer renders the scene into a
                    // six-face cube from the light, each face storing the nearest occluder's
                    // *linear distance to the light* normalized by the far plane. So all we
                    // carry is that far plane (to denormalize the sampled distance): the
                    // light position comes from the light entry. The far plane reaches past
                    // the scene from the light.
                    let dist = max(Float(simd_distance(light.position.simd3, target)), 1)
                    c.kind = 1
                    c.depthA = dist + 1.5 * r      // far plane (linear-distance normalizer)
                    // A 90° cube face spans 2·d wide at distance d, so a texel there is
                    // 2·dist/resolution, the world-space unit for the bias and PCF spread.
                    c.texelWorld = (2 * dist) / Float(Drawer.pointShadowMapResolution)
                    // On a ray-tracing device the renderer traces this caster instead of
                    // sampling the cube (it bumps `kind` to 2); `depthB` then carries the
                    // area-light radius that softens the traced shadow into a
                    // contact-hardening penumbra (light-relative, so it's camera-independent).
                    // The cube path ignores it, so it's harmless to always pack. Driven by the
                    // same `shadowSoftness` knob as the 2D casters (one control for every kind);
                    // the default 0.5 reproduces the previous fixed `dist · 0.03` exactly.
                    c.depthB = dist * 0.06 * Float(shadowSoftnessAmount)
                    // `samples` (rays/pixel) is resolved by the renderer from the GPU's
                    // capability + the sketch's quality tier; left 0 here (it has no device).
                case .rect, .disk:
                    // Rect/disk area caster: a spot-style perspective map rendered from the
                    // panel's center, aimed at the scene (the camera target, the same framing
                    // proxy the directional box uses; a panel lights its whole front
                    // hemisphere, so unlike a spot it has no cone to aim by), its PCSS
                    // penumbra sized by the panel's *real extent* rather than the knob-only
                    // size, so a bigger softbox casts a proportionally softer shadow. The map
                    // is a from-the-center approximation of the panel; on a ray-tracing
                    // device the renderer traces visibility to the panel's actual surface
                    // instead (which also captures a rect's anisotropic penumbra). Receivers
                    // outside the fitted frustum shade lit, the same envelope as the other 2D
                    // casters.
                    let eye = light.position.simd3
                    let toTarget = target - eye
                    let span = simd_length(toTarget)
                    let dist = max(span, 1)
                    // A panel sitting on the target aims along its own facing normal instead.
                    let axis = span > 1e-5 ? toTarget / span
                                           : simd_normalize(light.direction.normalized.simd3)
                    let up: SIMD3<Float> = abs(axis.y) > 0.99 ? SIMD3<Float>(0, 0, 1) : SIMD3<Float>(0, 1, 0)
                    let view = Camera3D.lookAt(eye: eye, center: eye + axis * dist, up: up)
                    // Cover the scene sphere around the target (a margin past the framing
                    // radius), clamped like the spot frustum; a panel inside the scene clamps
                    // wide and loses depth precision (the documented envelope).
                    let fovY = Float(min(Double(2 * atan(1.2 * r / dist)), Double.pi - 0.05))
                    let proj = Camera3D.perspective(fovY: fovY, aspect: 1,
                                                    near: max(0.1, dist - 1.5 * r), far: dist + 1.5 * r)
                    c.lightViewProjection = proj * view
                    c.texelWorld = (2 * tan(fovY * 0.5) * dist) / Float(Drawer.shadowMapResolution)
                    // The PCSS penumbra radius is the panel's own half-extent (the disk's
                    // radius; a rect's geometric-mean half-extent, so a thin strip doesn't
                    // blur like a square of its long side) in map texels. `shadowSoftness`
                    // stays the one dial across every caster: 0 routes to the hard legacy
                    // 3×3, the 0.5 default is the physical extent exactly, 1 doubles it.
                    // The radius caps at 40 texels; past that the fixed tap budget spreads
                    // too thin and the penumbra dissolves into dither.
                    let halfExtent = light.kind == .disk
                        ? light.radius
                        : (light.width * light.height).squareRoot() / 2
                    let sizeTexels = Float(halfExtent) / c.texelWorld * Float(shadowSoftnessAmount * 2)
                    c.depthA = min(max(sizeTexels, 0), 40)
                    // The perspective linearization term for the PCSS ratio, like the spot.
                    // On a ray-tracing device the renderer overwrites this with the traced
                    // panel's sampling scale when it flips `kind` to 2.
                    c.depthB = proj.columns.2.z
                case .tube:
                    break   // never eligible: a tube has no facing axis to render a map from
                }
                return c
            }

            // A tube never casts, and a light opts out with `castsShadow`.
            let eligible = (0..<count).filter {
                activeLights[$0].castsShadow && activeLights[$0].kind != .tube
            }
            var slots: [Int] = []
            if let primary = eligible.first(where: { activeLights[$0].kind == .directional })
                ?? eligible.first(where: { activeLights[$0].kind == .spot })
                ?? eligible.first(where: { activeLights[$0].kind == .point })
                ?? eligible.first(where: { activeLights[$0].kind == .rect || activeLights[$0].kind == .disk }) {
                slots.append(primary)
            }
            // A point light casts from any slot, beside a directional key or a spot: the
            // renderer gives each point caster its own cube of the cube-map array, or
            // traces every one of them against the frame's one acceleration structure.
            for i in eligible where !slots.contains(i) {
                if slots.count >= Int(OLLIN_MAX_SHADOW_CASTERS) { break }
                slots.append(i)
            }
            let built = slots.map(packCaster(at:))
            u.shadowCasterCount = Int32(built.count)
            // A C fixed-size array imports as a homogeneous tuple; fill it through a
            // typed pointer rather than naming each element.
            withUnsafeMutablePointer(to: &u.shadowCasters) { tuplePtr in
                tuplePtr.withMemoryRebound(to: OllinShadowCaster.self,
                                           capacity: Int(OLLIN_MAX_SHADOW_CASTERS)) { buf in
                    for (slot, c) in built.enumerated() { buf[slot] = c }
                }
            }
            // The single-caster fields mirror slot 0. Every dependent system reads the
            // list itself, so this mirror is only what keeps a one-caster frame
            // byte-identical to an unlisted one.
            if let primary = built.first {
                u.shadowLight = primary.lightIndex
                u.shadowKind = primary.kind
                u.shadowStrength = primary.strength
                u.lightViewProjection = primary.lightViewProjection
                u.shadowTexelWorld = primary.texelWorld
                u.shadowDepthA = primary.depthA
                u.shadowDepthB = primary.depthB
                u.shadowLinearize = primary.linearize
            }
            // Contact shadows refine whichever caster the frame resolved: pack the
            // screen-space ray's world length (the gate the mesh carriers and the
            // march pass read; the renderer zeroes it if the mask pass didn't run).
            // A nil length derives from the eye-to-target scene scale, so the
            // default seats objects at any scene size (the world-units-not-tuned-
            // constants rule).
            if contactShadowsEnabled && u.shadowLight >= 0 {
                u.contactShadow.x = Float(contactShadowLength ?? Double(r) * 0.025)
            }
        }
        return u
    }

    /// Convert a `Light` into its GPU form: linearized intensity-scaled color, the
    /// vectors a directional/point/spot light needs, and a spot's cone cosines.
    private static func packLight(_ light: Light, profileLayer: Int = -1,
                                  cookieLayer: Int = -1) -> OllinLight {
        var l = OllinLight()
        // Light shaping: the layer indices into the frame's IES/cookie texture
        // arrays (-1 = none; a zero-initialized struct would wrongly point at
        // layer 0) and the roll about the beam axis. The last lane carries the
        // light's own answer to "do you throw a shadow": the raster resolves that
        // on the CPU into `shadowCasters`, but the traced export sees only this
        // list, so without the flag every light there throws.
        l.shaping = SIMD4<Float>(Float(profileLayer), Float(cookieLayer),
                                 Float(light.roll), light.castsShadow ? 0 : 1)
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
            // The fixture axis an IES profile aims along (straight down by
            // default) rides the otherwise-unused direction slot.
            let axis = light.direction.length > 0 ? light.direction.normalized
                                                  : Vector3(0, -1, 0)
            l.direction = SIMD4<Float>(Float(axis.x), Float(axis.y), Float(axis.z), 0)
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
        case .rect, .disk:
            // A flat panel: center + unit normal (the way it faces, like a spot's axis)
            // + an orthonormal tangent frame with the half-extents riding the w slots.
            // The frame is right-handed (tangent × bitangent = the facing normal), which
            // the shader's corner winding depends on for its one-sided front test.
            l.kind = light.kind == .rect ? 3 : 4
            l.position = SIMD4<Float>(Float(light.position.x), Float(light.position.y),
                                      Float(light.position.z), 0)
            let n = simd_normalize(light.direction.normalized.simd3)
            var up = light.up.simd3
            // Degenerate up hint (zero, or parallel to the normal): fall back to an axis
            // that isn't, so a straight-down panel still gets a stable frame.
            if simd_length(up) < 1e-6 { up = SIMD3<Float>(0, 1, 0) }
            up = simd_normalize(up)
            if abs(simd_dot(up, n)) > 0.999 {
                up = abs(n.y) > 0.999 ? SIMD3<Float>(0, 0, 1) : SIMD3<Float>(0, 1, 0)
            }
            let t = simd_normalize(simd_cross(up, n))
            let b = simd_cross(n, t)
            let halfW = Float(light.kind == .rect ? light.width / 2 : light.radius)
            let halfH = Float(light.kind == .rect ? light.height / 2 : light.radius)
            l.direction = SIMD4<Float>(n.x, n.y, n.z, light.twoSided ? 1 : 0)
            l.axisA = SIMD4<Float>(t.x, t.y, t.z, halfW)
            l.axisB = SIMD4<Float>(b.x, b.y, b.z, halfH)
        case .tube:
            // A glowing cylinder: center + unit axis with the half-length in w, and the
            // tube radius in axisB.w. Emits radially, so there's no facing normal.
            l.kind = 5
            l.position = SIMD4<Float>(Float(light.position.x), Float(light.position.y),
                                      Float(light.position.z), 0)
            let axis = simd_normalize(light.direction.normalized.simd3)
            l.axisA = SIMD4<Float>(axis.x, axis.y, axis.z, Float(light.length / 2))
            l.axisB = SIMD4<Float>(0, 0, 0, Float(max(light.radius, 1e-4)))
        }
        return l
    }

    /// Record a 3D point cloud, drawn as camera-facing disc splats through the
    /// active camera. World-space points (they ride the camera, not the 2D
    /// transform stack). A no-op without a camera or when the cloud is empty.
    func drawPointCloud(_ cloud: PointCloud) {
        // A recording has no camera (it's per-frame state); the points record
        // world-space and the replay draws them through whatever camera is active
        // at drawBatch time, so the guard relaxes while recording.
        guard isRecordingBatch || camera3D != nil, !cloud.isEmpty else { return }
        // SVG export is 2D vector only; a splat cloud has no vector outline.
        if svgRecorder != nil { return }
        if let spatialRecorder { spatialRecorder.skip("a point cloud"); return }
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

    /// Declare that the meshes drawn inside `body` move together as one thing, so
    /// temporal anti-aliasing can reproject their history exactly while they move.
    /// The drawer remembers each draw's model matrix under a call-site identity
    /// and, from the second frame on, records the range with the transform back
    /// to last frame's placement; the renderer's velocity pass turns that into
    /// per-pixel screen motion, which temporal AA reprojects by and motion blur
    /// streaks along. Purely additive: without `temporalAntialiasing()` or
    /// `motionBlur()` (or before a mover's second frame) nothing changes, and
    /// geometry outside any block keeps the camera-only reprojection it has today.
    func withMotion(source: String, _ body: () -> Void) {
        let occurrence = moverOccurrence[source, default: 0]
        moverOccurrence[source] = occurrence + 1
        moverStack.append(MoverContext(source: source, occurrence: occurrence))
        defer { moverStack.removeLast() }
        body()
    }

    /// The `drawMesh` tail hook: record the just-appended vertex range as a mover
    /// when a `withMotion` block is open. Main canvas only (temporal AA never runs
    /// on a render target) and never for a wireframe (the velocity pass rasterizes
    /// solid triangles, which would fill a wireframe's see-through interior).
    /// First sighting of a key records nothing: with no previous matrix there is
    /// no motion to state, and the resolve's fallback handles the frame.
    private func recordMoverRange(from start: Int, wireframe: Bool) {
        guard !moverStack.isEmpty, currentTarget == nil, !wireframe else { return }
        let count = meshVertices.count - start
        guard count > 0 else { return }
        let top = moverStack.count - 1
        let key = MoverKey(source: moverStack[top].source,
                           occurrence: moverStack[top].occurrence,
                           draw: moverStack[top].draws)
        moverStack[top].draws += 1
        let m = modelMatrix
        let previous = moverHistory[key]
        moverHistory[key] = (matrix: m, frame: moverFrame)
        guard moverFrame > 0, let previous, previous.frame == moverFrame - 1 else { return }
        // World now -> world last frame. A degenerate (non-invertible) transform
        // yields non-finite velocities, which the resolve's sentinel test reads
        // as unwritten, so it degrades to the fallback rather than mis-drawing.
        let delta = previous.matrix * simd_inverse(m)
        moverRanges.append(MoverRange(start: start, count: count, previousOfCurrent: delta))
    }

    /// Record a solid 3D mesh, drawn through the active camera with depth testing.
    /// World-aware geometry (it rides the camera and the 3D transform stack, not the
    /// 2D affine): the model matrix bakes into each position and its normal matrix
    /// into each normal CPU-side, so the shader only applies the camera. Triangle
    /// indices are expanded into the flat per-frame `meshVertices` list. The surface
    /// takes the current `fill` color: flat (unlit) with no lights set, Blinn-Phong
    /// shaded once a light is added. A no-op without a camera or when the mesh is empty.
    func drawMesh(_ mesh: Mesh) {
        // A retained mesh would silently drop out of the shadow and reflection
        // passes (they read the frame's mesh buffer), so meshes stay per-frame.
        if isRecordingBatch {
            noteBatchRecording("meshes inside makeBatch { } are not recorded (a retained mesh would cast no shadow); draw meshes where the batch is drawn.")
            return
        }
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
        // Spatial export wants the mesh itself, not a rasterization of it: the
        // geometry in its own space beside the matrix that placed it.
        if let spatialRecorder {
            spatialRecorder.record(mesh: mesh, transform: modelMatrix,
                                   surface: meshSurfaceColor, finish: currentMaterial,
                                   wireframe: wireframeEnabled, matcap: currentMatcap != nil)
            return
        }
        currentTarget?.needsDepth = true   // 3D in a target → that pass carries depth
        // Wireframe draws the triangle edges only (the faces are see-through), so it
        // ignores the texture and lighting; otherwise a texture maps when matching UVs
        // are present, else a flat base-color surface. Wireframe and textured meshes
        // each open their own batch (own pipeline / bound texture); a solid mesh merges.
        let material = mesh.material
        let wireframe = wireframeEnabled
        let matcap = !wireframe ? currentMatcap : nil
        let uvsAligned = mesh.uvs.count == mesh.positions.count
        // Triplanar projection: the base texture (and any normal map) read by
        // world position instead of uvs, so a mesh with none at all (a marched
        // isosurface, a grown or reconstructed shell) can wear a picture. It
        // needs no uvs and no tangents. The rest of the surface-map set stays
        // uv-mapped, the named cut, so a triplanar mesh carrying one draws
        // without it and says so once.
        var triplanar = false
        if !wireframe, matcap == nil, let mat = material, mat.triplanarScale > 0,
           mat.texture != nil || (mat.normalTexture != nil && mat.normalScale > 0) {
            triplanar = true
            if mat.metallicRoughnessTexture != nil || mat.occlusionTexture != nil
                || mat.emissiveTexture != nil || mat.heightTexture != nil
                || mat.detailTexture != nil || mat.detailNormalTexture != nil {
                noteOnce("a triplanar mesh projects its base texture and normal map only; the other surface maps (metallic-roughness / occlusion / emissive / height / detail) stay uv-mapped and were skipped.")
            }
        }
        // A normal map needs the whole basis: matching uvs *and* matching
        // tangents. Attached without either, it degrades honestly (the mesh
        // draws with its geometric normals) and says so once. `normalScale == 0`
        // is the documented off switch, taking the plain textured path so the
        // frame is byte-identical to a mapless one. (A triplanar mesh's normal
        // map projects instead, needing neither, so it skips this gate.)
        var normalMapped = false
        if !triplanar, !wireframe, matcap == nil, let mat = material, mat.normalTexture != nil,
           mat.normalScale > 0 {
            if uvsAligned && mesh.tangents.count == mesh.positions.count {
                normalMapped = true
            } else if !uvsAligned {
                noteOnce("a normal map needs per-vertex uvs; drawing the mesh without it.")
            } else {
                noteOnce("a normal map needs per-vertex tangents (normalMapped(_:) or generatingTangents() sets them up); drawing the mesh without it.")
            }
        }
        // A height map (parallax occlusion) marches the eye ray in tangent
        // space, so it needs the same basis a normal map does: per-vertex uvs
        // and tangents. Attached without either it degrades honestly, like the
        // normal map; `heightScale == 0` is the documented off switch.
        var heightMapped = false
        if !triplanar, !wireframe, matcap == nil, let mat = material, mat.heightTexture != nil,
           mat.heightScale > 0 {
            if uvsAligned && mesh.tangents.count == mesh.positions.count {
                heightMapped = true
            } else if !uvsAligned {
                noteOnce("a height map needs per-vertex uvs; drawing the mesh without it.")
            } else {
                noteOnce("a height map needs per-vertex tangents (parallaxMapped(_:) or generatingTangents() sets them up); drawing the mesh without it.")
            }
        }
        // Detail maps tile a finer second texture pair across the base one.
        // The color half needs uvs like the base texture; the normal half
        // needs the full tangent basis like a normal map. Each degrades
        // honestly on its own; `detailStrength == 0` (or `detailScale == 0`)
        // is the documented off switch, keeping the frame byte-identical to
        // one with no detail maps at all.
        var detailColorMapped = false, detailNormalMapped = false
        if !triplanar, !wireframe, matcap == nil, let mat = material,
           mat.detailScale > 0, mat.detailStrength > 0,
           mat.detailTexture != nil || mat.detailNormalTexture != nil {
            if uvsAligned {
                detailColorMapped = mat.detailTexture != nil
                if mat.detailNormalTexture != nil {
                    if mesh.tangents.count == mesh.positions.count {
                        detailNormalMapped = true
                    } else {
                        noteOnce("a detail normal map needs per-vertex tangents (detailMapped(_:normal:) or generatingTangents() sets them up); drawing the mesh without it.")
                    }
                }
            } else {
                noteOnce("detail maps need per-vertex uvs; drawing the mesh without them.")
            }
        }
        let textured = !wireframe && matcap == nil && uvsAligned
            && (material?.texture != nil || normalMapped)
        // The rest of the surface-map set (a metallic-roughness map, an occlusion
        // map, an emissive map, or a constant emissive factor) routes to the
        // textured path's second twin. The map textures need per-vertex uvs like
        // the base texture (degrading honestly without them); a constant emissive
        // factor alone needs none. The gates ride the per-batch finish (the
        // `normalScale` pattern), doubling as the encode-side pipeline pick and
        // the shader-side sampling gates.
        var mrMapped = false, occlusionMapped = false, emissiveMapped = false
        var emissiveOn = false
        if !wireframe, matcap == nil, let mat = material {
            emissiveOn = mat.emissiveFactor.red > 0 || mat.emissiveFactor.green > 0
                || mat.emissiveFactor.blue > 0
            if triplanar {
                // The sampled surface maps stay uv-mapped (the cut noted above);
                // a constant emissive factor needs no sampling and still adds.
            } else if uvsAligned {
                mrMapped = mat.metallicRoughnessTexture != nil
                occlusionMapped = mat.occlusionTexture != nil && mat.occlusionStrength > 0
                emissiveMapped = mat.emissiveTexture != nil && emissiveOn
            } else if mat.metallicRoughnessTexture != nil || mat.occlusionTexture != nil
                        || (mat.emissiveTexture != nil && emissiveOn) {
                noteOnce("a surface map (metallic-roughness / occlusion / emissive) needs per-vertex uvs; drawing the mesh without it.")
            }
        }
        // A texture-wearing mesh whose uvs are missing draws flat on the solid
        // path; keep it there rather than let an emissive factor route it to a
        // sampling pipeline (which would read the base texture at uv 0).
        // A height map routes here too: the parallax march lives in the
        // surface-mapped fragment, where the shifted uv reaches every map.
        let surfaceMapped = mrMapped || occlusionMapped || emissiveMapped || heightMapped
            || detailColorMapped || detailNormalMapped
            || triplanar || (emissiveOn && (uvsAligned || material?.texture == nil))
        let writesUV = textured || (surfaceMapped && uvsAligned)
        if wireframe {
            beginMeshBatch(material: nil, finish: OllinMaterial(), wireframe: true)
        } else if let matcap {
            beginMeshBatch(material: nil, finish: OllinMaterial(), matcap: matcap)
        } else if surfaceMapped {
            // The gates ride the finish like `normalScale` below; the mesh
            // material's own metallic/roughness fold in as the map's factors
            // (the file's intent), composing with the drawing-state finish the
            // shader then multiplies by the sampled channels.
            var finish = currentMaterial.gpuMaterial()
            if normalMapped, let mat = material {
                finish.normalScale = Float(mat.normalScale)
            }
            if let mat = material {
                // What the maps do outside the uv square. One answer covers the
                // set, and clamp is the zero, so a material that says nothing
                // packs the same bytes it always did.
                finish.uvWrap = mat.wrap.gpuValue
                if triplanar {
                    // The gate carries tiles per world unit; the projected
                    // normal map needs no tangent basis, so its gate rides the
                    // map alone (the drawing-state finish never sets either).
                    finish.triplanar = Float(1 / mat.triplanarScale)
                    if mat.normalTexture != nil, mat.normalScale > 0 {
                        finish.normalScale = Float(mat.normalScale)
                    }
                }
                if mrMapped {
                    finish.mrGate = 1
                    finish.metallic *= Float(mat.metallic)
                    finish.roughness *= Float(mat.roughness)
                }
                if occlusionMapped {
                    finish.occlusionStrength = Float(mat.occlusionStrength)
                }
                if heightMapped {
                    finish.parallax = Float(mat.heightScale)
                }
                if detailColorMapped || detailNormalMapped {
                    finish.detailScale = Float(mat.detailScale)
                    finish.detailStrength = Float(mat.detailStrength)
                    finish.detailGates = SIMD4<Float>(detailColorMapped ? 1 : 0,
                                                      detailNormalMapped ? 1 : 0, 0, 0)
                }
                if emissiveOn {
                    let f = mat.emissiveFactor
                    finish.emissive = SIMD4<Float>(Float(Color.srgbToLinear(f.red)),
                                                   Float(Color.srgbToLinear(f.green)),
                                                   Float(Color.srgbToLinear(f.blue)),
                                                   emissiveMapped ? 1 : 0)
                }
            }
            beginMeshBatch(material: material, finish: finish)
        } else if textured {
            // The map's strength rides the per-batch finish uniform: it's
            // per-mesh state (the drawing-state `material(_:)` knows nothing of
            // it), and nonzero only when the map actually draws, so it doubles
            // as the encode-side and shader-side gate.
            var finish = currentMaterial.gpuMaterial()
            if normalMapped, let mat = material {
                finish.normalScale = Float(mat.normalScale)
            }
            if let mat = material { finish.uvWrap = mat.wrap.gpuValue }
            beginMeshBatch(material: material, finish: finish)
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
        // Per-vertex mesh colors multiply the resolved surface color (the texture
        // contract: fill stays a whole-mesh tint). A wireframe draws its edges in
        // the stroke color alone, so it ignores them; a count that doesn't match
        // `positions` is ignored too (the `uvs` rule). An empty `colors` takes the
        // constant-color path untouched, byte for byte.
        let vertexColored = !wireframe && mesh.colors.count == mesh.positions.count
        let moverStart = meshVertices.count
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
            v.color = vertexColored ? color * mesh.colors[i].simd4 : color
            if writesUV {
                let uv = mesh.uvs[i]
                v.uv = SIMD2<Float>(Float(uv.x), Float(uv.y))
            }
            if normalMapped || heightMapped || detailNormalMapped {
                // The tangent transforms by the model's linear part (it's a
                // surface direction, covariant with positions, unlike the
                // normal's inverse-transpose), then packs as four Float16 bit
                // patterns into the vertex's spare 8 bytes; the shader reads
                // them back as a native half4 and renormalizes after
                // interpolation. A height map rides the same basis (the
                // parallax march projects the eye ray through it), and a
                // detail normal map bends through it too.
                let t = mesh.tangents[i]
                var d = SIMD3<Float>(Float(t.direction.x), Float(t.direction.y),
                                     Float(t.direction.z))
                if !modelIsIdentity {
                    let lin = simd_float3x3(SIMD3<Float>(m.columns.0.x, m.columns.0.y, m.columns.0.z),
                                            SIMD3<Float>(m.columns.1.x, m.columns.1.y, m.columns.1.z),
                                            SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z))
                    d = lin * d
                }
                let len = simd_length(d)
                if len > 1e-8 { d /= len }
                v.tangent = SIMD4<UInt16>(Float16(d.x).bitPattern,
                                          Float16(d.y).bitPattern,
                                          Float16(d.z).bitPattern,
                                          Float16(Float(t.handedness)).bitPattern)
            }
            meshVertices.append(v)
        }
        recordMoverRange(from: moverStart, wireframe: wireframe)
    }

    /// Draw `mesh` once per placement in `instances`, as ONE instanced GPU draw:
    /// the mesh's local-space vertices are expanded once, each copy's matrix is
    /// applied per vertex on the GPU, and the whole field costs one draw call.
    /// Copies shade exactly like solid meshes (the current `fill` and
    /// `material(_:)` finish, lights, shadows received, IBL, GI, fog); the
    /// per-copy `color` tints on top. The surrounding 3D transform stack moves
    /// the whole field. Instanced copies cast into the directional/spot and
    /// point shadow maps, and they stand in the ray-traced scene as well
    /// (reflections, ray-traced shadows, and global illumination all see them);
    /// the screen-space pre-passes still leave them out.
    func drawMeshInstanced(_ mesh: Mesh, instances: [MeshInstance]) {
        guard !instances.isEmpty else { return }
        guard prepareInstancedMeshDraw(mesh) else { return }
        if let spatialRecorder {
            // Spatial export wants each copy as the mesh plus the matrix that
            // placed it, exactly like a loop of drawMesh calls would record.
            for inst in instances {
                let m = modelIsIdentity ? inst.matrix : modelMatrix * inst.matrix
                spatialRecorder.record(mesh: mesh, transform: m,
                                       surface: meshSurfaceColor, finish: currentMaterial,
                                       wireframe: false, matcap: false)
            }
            return
        }
        currentTarget?.needsDepth = true
        let vertexRange = appendInstancedBaseMesh(mesh)
        let iStart = meshInstances.count
        meshInstances.reserveCapacity(iStart + instances.count)
        for inst in instances {
            var gi = OllinMeshInstance()
            gi.model = modelIsIdentity ? inst.matrix : modelMatrix * inst.matrix
            gi.color = inst.color?.simd4 ?? SIMD4<Float>(1, 1, 1, 1)
            meshInstances.append(gi)
        }
        appendInstancedMeshBatch(mesh, vertexRange: vertexRange,
                                 instanceStart: iStart, instanceCount: instances.count)
    }

    /// The GPU-resident sibling: draw `count` copies whose `OllinMeshInstance`
    /// placements live in a compute buffer a kernel writes (positions never
    /// round-trip through the CPU, the particle/point-cloud rule). The matrices
    /// are absolute world space: the transform stack is NOT composed on top,
    /// since the kernel owns the placement. These copies reach the ray-traced
    /// scene too: their placements never visit the CPU, so a kernel writes their
    /// instance descriptors beside the ones the CPU writes for a list.
    func drawMeshInstanced(_ mesh: Mesh, instanceBuffer: ComputeBindable, count: Int) {
        guard count > 0 else { return }
        guard prepareInstancedMeshDraw(mesh) else { return }
        if spatialRecorder != nil {
            noteOnce("a GPU-instanced mesh's placements live on the GPU, so a spatial export can't record them; use the [MeshInstance] form for exportable copies.")
            return
        }
        currentTarget?.needsDepth = true
        let vertexRange = appendInstancedBaseMesh(mesh)
        appendInstancedMeshBatch(mesh, vertexRange: vertexRange,
                                 instanceStart: 0, instanceCount: 0,
                                 gpuInstances: instanceBuffer, gpuCount: count)
    }

    /// The shared gates of an instanced mesh draw (the `drawMesh` set): batch
    /// recording, camera, combine blocks, SVG. Returns false when the draw
    /// should not record. The solid lit path is the one instanced pipeline, so
    /// wireframe and matcap modes fall back to it with a note.
    private func prepareInstancedMeshDraw(_ mesh: Mesh) -> Bool {
        if isRecordingBatch {
            noteBatchRecording("instanced meshes inside makeBatch { } are not recorded (a retained mesh would cast no shadow); draw them where the batch is drawn.")
            return false
        }
        guard camera3D != nil, !mesh.isEmpty else { return false }
        if !combineStack.isEmpty {
            if !warnedMeshInCombine {
                print("Ollin: a mesh inside a combine block is ignored unless it's an SDF-able primitive (drawSphere/drawBox/drawRoundedBox/drawCylinder/drawCone/drawTorus/drawCapsule/drawOctahedron); a 3D combine merges those analytic fields.")
                warnedMeshInCombine = true
            }
            return false
        }
        // SVG export is 2D vector only; a shaded solid has no vector outline.
        if svgRecorder != nil { return false }
        if wireframeEnabled {
            noteOnce("instanced meshes draw on the solid lit path; wireframe() doesn't apply to them yet.")
        }
        if currentMatcap != nil {
            noteOnce("instanced meshes draw on the solid lit path; a matcap doesn't apply to them yet.")
        }
        if mesh.material?.texture != nil || mesh.material?.normalTexture != nil {
            noteOnce("an instanced mesh draws untextured (its base color still tints); texture and surface maps aren't instanced yet.")
        }
        return true
    }

    /// Expand the base mesh once into `instancedMeshVertices`, LOCAL space (no
    /// model bake; each instance's matrix is applied on the GPU). Returns the run.
    private func appendInstancedBaseMesh(_ mesh: Mesh) -> (start: Int, count: Int) {
        // The vertex color is the current fill tinted by the material's base
        // color, times any per-vertex mesh colors (the solid-mesh rules); the
        // PBR metalness/roughness ride the spare w slots like the solid path.
        let color = meshSurfaceColor.simd4 * (mesh.material?.baseColor.simd4 ?? SIMD4<Float>(1, 1, 1, 1))
        let pbr = currentMaterial.shading == .physicallyBased
        let metalW: Float = pbr ? Float(currentMaterial.metallic) : 0
        let posW: Float = pbr ? Float(currentMaterial.roughness) : 1
        let start = instancedMeshVertices.count
        Drawer.expandBaseMesh(mesh, surface: color, posW: posW, metalW: metalW,
                              into: &instancedMeshVertices)
        return (start, instancedMeshVertices.count - start)
    }

    /// Expand `mesh`'s indexed triangles into a flat LOCAL-space vertex list for
    /// an instanced path (no model matrix baked; each copy's matrix applies on
    /// the GPU). `surface` multiplies per-vertex mesh colors when they align
    /// (the solid-mesh rules); `posW`/`metalW` fill the spare w slots. Shared by
    /// the per-frame instanced recorder and the retained `MeshField` build.
    static func expandBaseMesh(_ mesh: Mesh, surface: SIMD4<Float>,
                               posW: Float, metalW: Float,
                               into vertices: inout [OllinMeshVertex]) {
        let vertexColored = mesh.colors.count == mesh.positions.count
        vertices.reserveCapacity(vertices.count + mesh.indices.count)
        for idx in mesh.indices {
            let i = Int(idx)
            guard i < mesh.positions.count else { continue }
            let p = mesh.positions[i]
            let n = i < mesh.normals.count ? mesh.normals[i] : Vector3.unitZ
            var v = OllinMeshVertex()
            v.position = SIMD4<Float>(Float(p.x), Float(p.y), Float(p.z), posW)
            let nn = n.normalized
            v.normal = SIMD4<Float>(Float(nn.x), Float(nn.y), Float(nn.z), metalW)
            v.color = vertexColored ? surface * mesh.colors[i].simd4 : surface
            vertices.append(v)
        }
    }

    /// Open the `.meshInstanced` batch (always its own; never merges).
    private func appendInstancedMeshBatch(_ mesh: Mesh,
                                          vertexRange: (start: Int, count: Int),
                                          instanceStart: Int, instanceCount: Int,
                                          gpuInstances: ComputeBindable? = nil,
                                          gpuCount: Int = 0) {
        guard vertexRange.count > 0 else { return }
        batches.append(GeometryBatch(kind: .meshInstanced, vertexStart: vertices.count,
                                     instanceStart: sdfInstances.count,
                                     imageStart: imageVertices.count,
                                     glyphStart: glyphVertices.count,
                                     pointStart: points.count,
                                     meshStart: meshVertices.count,
                                     sdfGroupStart: sdfGroups.count,
                                     sdf3DGroupStart: sdf3DGroups.count,
                                     blendMode: currentBlend,
                                     particleBuffer: gpuInstances,
                                     particleCount: gpuCount,
                                     depth: currentDepth,
                                     instancedVertexStart: vertexRange.start,
                                     instancedVertexCount: vertexRange.count,
                                     meshInstanceStart: instanceStart,
                                     meshInstanceCount: instanceCount,
                                     finish: currentMaterial.gpuMaterial(),
                                     target: currentTarget, clipLevel: activeClipLevel))
        currentKind = nil
    }

    /// Draw a retained `MeshField`: the whole world of placed meshes in one
    /// GPU-culled indirect draw. The 3D CTM at this call composes onto every
    /// copy (the field moves as a unit); the current `material(_:)` finish
    /// shades it. Once per frame per field: the cull results live on the field's
    /// own buffers, so a second draw of the same field in one frame is skipped
    /// with a note.
    func drawMeshField(_ field: MeshField) {
        if isRecordingBatch {
            noteBatchRecording("a MeshField inside makeBatch { } is not recorded (it is already retained and GPU-resident); draw it where the batch is drawn.")
            return
        }
        guard camera3D != nil, !field.isEmpty else { return }
        if !combineStack.isEmpty {
            if !warnedMeshInCombine {
                print("Ollin: a mesh inside a combine block is ignored unless it's an SDF-able primitive (drawSphere/drawBox/drawRoundedBox/drawCylinder/drawCone/drawTorus/drawCapsule/drawOctahedron); a 3D combine merges those analytic fields.")
                warnedMeshInCombine = true
            }
            return
        }
        // SVG export is 2D vector only; a shaded solid has no vector outline.
        if svgRecorder != nil { return }
        if let spatialRecorder {
            // Spatial export walks the field's CPU-side placements: each copy as
            // the mesh plus the matrix that placed it, like a loop of drawMesh.
            for placement in field.placements {
                for copy in placement.copies {
                    let m = modelIsIdentity ? copy.matrix : modelMatrix * copy.matrix
                    spatialRecorder.record(mesh: placement.mesh, transform: m,
                                           surface: .white, finish: currentMaterial,
                                           wireframe: false, matcap: false)
                }
            }
            return
        }
        if batches.contains(where: { $0.kind == .meshField && $0.field === field }) {
            noteOnce("a MeshField can be drawn once per frame (its cull results live on the field); place more copies in it instead of drawing it twice.")
            return
        }
        currentTarget?.needsDepth = true
        batches.append(GeometryBatch(kind: .meshField, vertexStart: vertices.count,
                                     instanceStart: sdfInstances.count,
                                     imageStart: imageVertices.count,
                                     glyphStart: glyphVertices.count,
                                     pointStart: points.count,
                                     meshStart: meshVertices.count,
                                     sdfGroupStart: sdfGroups.count,
                                     sdf3DGroupStart: sdf3DGroups.count,
                                     blendMode: currentBlend, depth: currentDepth,
                                     field: field,
                                     fieldTransform: modelIsIdentity ? matrix_identity_float4x4 : modelMatrix,
                                     finish: currentMaterial.gpuMaterial(),
                                     target: currentTarget, clipLevel: activeClipLevel))
        currentKind = nil
    }

    /// Draw a `StrandField`: blades a mesh pipeline synthesizes inside the draw
    /// call itself (no geometry buffers exist), tile-culled against the camera
    /// and detail-graded by distance on the GPU. Blades shade on the solid lit
    /// path with the current `material(_:)` finish; the 3D CTM moves the patch.
    /// The geometry exists only in-draw, so strands are skipped by the shadow
    /// casters, the vector recorder, and the spatial recorder (each with a note
    /// where surprising).
    func drawStrands(_ field: StrandField) {
        if isRecordingBatch {
            noteBatchRecording("a StrandField inside makeBatch { } is not recorded (its blades are grown by the GPU each frame); draw it where the batch is drawn.")
            return
        }
        guard camera3D != nil, field.count > 0 else { return }
        if !combineStack.isEmpty {
            if !warnedMeshInCombine {
                print("Ollin: a mesh inside a combine block is ignored unless it's an SDF-able primitive (drawSphere/drawBox/drawRoundedBox/drawCylinder/drawCone/drawTorus/drawCapsule/drawOctahedron); a 3D combine merges those analytic fields.")
                warnedMeshInCombine = true
            }
            return
        }
        if svgRecorder != nil { return }
        if spatialRecorder != nil {
            noteOnce("a StrandField's blades exist only inside the draw, so a spatial export can't record them.")
            return
        }
        currentTarget?.needsDepth = true
        batches.append(GeometryBatch(kind: .strands, vertexStart: vertices.count,
                                     instanceStart: sdfInstances.count,
                                     imageStart: imageVertices.count,
                                     glyphStart: glyphVertices.count,
                                     pointStart: points.count,
                                     meshStart: meshVertices.count,
                                     sdfGroupStart: sdfGroups.count,
                                     sdf3DGroupStart: sdf3DGroups.count,
                                     blendMode: currentBlend, depth: currentDepth,
                                     fieldTransform: modelIsIdentity ? matrix_identity_float4x4 : modelMatrix,
                                     strandField: field,
                                     finish: currentMaterial.gpuMaterial(),
                                     target: currentTarget, clipLevel: activeClipLevel))
        currentKind = nil
    }

    /// Draw every node of a loaded `Scene` at its authored place: walk the node
    /// tree, composing each node's local transform onto the 3D model matrix, and
    /// `drawMesh` each node's geometry. A node with morph targets draws its
    /// blended shape, and a skinned node draws posed by its skin's joints. Every
    /// mesh rule applies unchanged (fill tint, materials, lights, shadows,
    /// reflections); the scene's cameras and lights are data the sketch applies
    /// itself (`camera(_:)` / `light(_:)`). A no-op without a camera, like
    /// `drawMesh`.
    func drawScene(_ scene: Scene) {
        // Skinning reads joints anywhere in the tree, so a scene with skins
        // resolves every node's root-relative transform in one walk up front;
        // a skinless scene skips the walk.
        let worlds = scene.skins.isEmpty ? nil : scene.nodeWorldTransforms()
        // A skinned mesh's placement comes entirely from its joints (its own
        // node chain is ignored, the format's rule), so it draws under the model
        // matrix of this call, not the walk's composed one.
        let root = modelMatrix
        let rootIsIdentity = modelIsIdentity
        for node in scene.nodes {
            drawSceneNode(node, scene: scene, worlds: worlds,
                          root: root, rootIsIdentity: rootIsIdentity)
        }
    }

    private func drawSceneNode(_ node: SceneNode, scene: Scene,
                               worlds: [Int: simd_float4x4]?,
                               root: simd_float4x4, rootIsIdentity: Bool) {
        let saved = modelMatrix
        let savedIdentity = modelIsIdentity
        modelMatrix = modelMatrix * node.localTransform
        modelIsIdentity = false
        if let mesh = node.mesh {
            let shaped = node.morphedMesh() ?? mesh
            if let si = node.skinIndex, let worlds {
                if scene.skins.indices.contains(si),
                   let posed = node.skinnedMesh(shaped, skin: scene.skins[si],
                                                worlds: worlds) {
                    modelMatrix = root
                    modelIsIdentity = rootIsIdentity
                    drawNodeMesh(posed, node: node)
                    modelMatrix = saved * node.localTransform
                    modelIsIdentity = false
                } else {
                    noteOnce("a skinned node's skin or vertex weights don't line up; drawing \"\(node.name)\" undeformed.")
                    drawNodeMesh(shaped, node: node)
                }
            } else {
                drawNodeMesh(shaped, node: node)
            }
        }
        for child in node.children {
            drawSceneNode(child, scene: scene, worlds: worlds,
                          root: root, rootIsIdentity: rootIsIdentity)
        }
        modelMatrix = saved
        modelIsIdentity = savedIdentity
    }

    /// Draw a node's shaped (morphed and posed) mesh: one `drawMesh` per
    /// material slice when the loader split the mesh into `meshParts`, else the
    /// whole mesh in one call. Each slice is an ordinary mesh sharing the shaped
    /// vertex arrays (copy-on-write, so no geometry is duplicated) with its own
    /// triangle list and material, which keeps every mesh rule (fill tint,
    /// lighting, shadows, reflections) applying per slice with no new machinery.
    /// A mesh swapped under the node no longer matches the parts and draws
    /// whole with its own material (the skin-alignment treatment).
    private func drawNodeMesh(_ shaped: Mesh, node: SceneNode) {
        guard !node.meshParts.isEmpty,
              node.partsVertexCount == shaped.positions.count else {
            drawMesh(shaped)
            return
        }
        for part in node.meshParts {
            var slice = shaped
            slice.indices = part.indices
            slice.material = part.material
            drawMesh(slice)
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
        instancedMeshVertices.removeAll(keepingCapacity: true)
        meshInstances.removeAll(keepingCapacity: true)
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
        // Keep last frame's camera for the motion-blur velocity fill before the
        // slot resets; a frame that set none leaves the previous one in place so
        // one camera-less frame doesn't erase the cross-frame memory.
        previousCamera3D = camera3D ?? previousCamera3D
        camera3D = nil
        // The mover registry: ranges and occurrence counters are per-frame; the
        // history persists (it's the cross-frame memory) but drops entries not
        // refreshed last frame, so a mover that skipped a frame starts over.
        moverFrame += 1
        moverRanges.removeAll(keepingCapacity: true)
        moverOccurrence.removeAll(keepingCapacity: true)
        moverStack.removeAll(keepingCapacity: true)
        if !moverHistory.isEmpty {
            let cutoff = moverFrame - 1
            moverHistory = moverHistory.filter { $0.value.frame >= cutoff }
        }
        // Lights are per-frame like the camera (set in `draw()` each frame). They
        // reset here but *not* in `background()`, which only wipes geometry mid-frame
        // while the camera/lights stay — matching the camera's lifetime.
        lights.removeAll(keepingCapacity: true)
        ambientLightColor = nil
        lightingMode = .auto
        // Decals are per-frame like the lights: place them each `draw()`.
        placedDecals.removeAll(keepingCapacity: true)
        usedDecals.removeAll(keepingCapacity: true)
        environment = nil
        castsShadows = false
        contactShadowsEnabled = false
        contactShadowLength = nil
        rayTracedReflectionsEnabled = false
        globalIlluminationEnabled = false
        giIntensity = 1
        causticsEnabled = false
        causticsIntensity = 1
        causticsDispersion = 0
        temporalAAEnabled = false
        temporalUpscalingEnabled = false
        temporalUpscalingQuality = .default
        motionBlurEnabled = false
        motionBlurShutter = 0.5
        lensFlareSetting = nil
        // Atmosphere is per-frame like the lights (the quality setting persists).
        fogColor = nil
        fogDensity = 0
        fogHeightFalloff = 0
        aerialActive = false
        aerialDensity = nil
        aerialHaziness = 0.3
        aerialSun = nil
        volumetricAmount = 0
        volumetricAnisotropy = 0.5
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
        // Clip regions are per-frame (close any block left open by an early exit);
        // the canvas needs a stencil only on frames that actually clip.
        clipStack.removeAll(keepingCapacity: true)
        activeClipLevel = 0
        currentBatchClip = 0
        usesClipStencil = false
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

    /// Compose an arbitrary 4x4 `matrix` onto subsequent 3D geometry, for a
    /// transform that arrives whole (a streamed anchor, a joint pose, a scene
    /// node) rather than as separate translate/rotate/scale steps.
    func transform(_ matrix: simd_float4x4) {
        modelMatrix = modelMatrix * matrix
        modelIsIdentity = false
    }

    /// Draw a capsule spanning `from` to `to` end to end, its round tips on the
    /// two points (the straight section shortens by the radius at each end), the
    /// solid way to draw a bone or strut between two 3D points.
    func drawCapsule(from: Vector3, to: Vector3, radius: Double, segments: Int, rings: Int) {
        let d = to - from
        let length = d.length
        guard length > 1e-9, radius > 0 else { return }
        let savedMatrix = modelMatrix
        let savedIdentity = modelIsIdentity
        defer { modelMatrix = savedMatrix; modelIsIdentity = savedIdentity }
        translate((from + to) * 0.5)
        // Turn the capsule's y axis onto the segment's direction.
        let dir = d / length
        let up = Vector3(0, 1, 0)
        let axis = up.cross(dir)
        if axis.lengthSquared > 1e-12 {
            rotate(acos(max(-1, min(1, up.dot(dir)))), axis: axis)
        } else if dir.y < 0 {
            rotateX(.pi)
        }
        let height = max(0, length - radius * 2)
        drawMeshPrimitive(.capsule(radius: radius, height: height),
                          mesh: .capsule(radius: radius, height: height,
                                         segments: segments, rings: rings))
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

    // MARK: Symmetry replication

    /// Run `body` (one primitive's emission into a single open batch) and then
    /// append a fold-transformed copy of everything it recorded, once per
    /// remaining symmetry fold. The copies transform the recorded canvas-space
    /// vertices directly; a fold is rigid, so the screen-space quantities baked
    /// into them (fringe AA coverage, flattening density, stroke width) stay
    /// exact, and the copies extend the batch the body opened, so draw order and
    /// pipeline selection are untouched. The body must emit into one batch kind:
    /// wrap a primitive's fill section and its stroke section separately (a
    /// stroke funnel reached *inside* a wrapped body passes through untouched;
    /// see `isReplicating`). SDF instances and combinator groups replicate at
    /// their own append sites instead (a matrix column ride, cheaper than a
    /// range copy).
    func replicated(_ body: () -> Void) {
        guard let folds = symmetryFolds, !isReplicating else { body(); return }
        isReplicating = true
        let vertexStart = vertices.count
        let imageStart = imageVertices.count
        let glyphStart = glyphVertices.count
        body()
        isReplicating = false
        Drawer.replicate(&vertices, from: vertexStart, folds: folds)
        Drawer.replicate(&imageVertices, from: imageStart, folds: folds)
        Drawer.replicate(&glyphVertices, from: glyphStart, folds: folds)
    }

    /// Append a fold-transformed copy of `array[start...]` per remaining fold
    /// (the first fold is the identity: the primary copy, already recorded).
    private static func replicate(_ array: inout [OllinVertex], from start: Int,
                                  folds: [matrix_float3x3]) {
        let end = array.count
        guard end > start else { return }
        array.reserveCapacity(end + (end - start) * (folds.count - 1))
        for fold in folds.dropFirst() {
            for i in start..<end {
                var v = array[i]
                let p = fold * SIMD3<Float>(v.position.x, v.position.y, 1)
                v.position = SIMD2<Float>(p.x, p.y)
                array.append(v)
            }
        }
    }

    /// The textured-quad twin of the vertex replicate above (image and glyph
    /// quads share `OllinImageVertex`; uv and tint copy through unchanged).
    private static func replicate(_ array: inout [OllinImageVertex], from start: Int,
                                  folds: [matrix_float3x3]) {
        let end = array.count
        guard end > start else { return }
        array.reserveCapacity(end + (end - start) * (folds.count - 1))
        for fold in folds.dropFirst() {
            for i in start..<end {
                var v = array[i]
                let p = fold * SIMD3<Float>(v.position.x, v.position.y, 1)
                v.position = SIMD2<Float>(p.x, p.y)
                array.append(v)
            }
        }
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
                                     strokeProfileShape: strokeProfileShape,
                                     strokeOpacityShape: strokeOpacityShape,
                                     strokeBrushShape: strokeBrushShape,
                                     currentMaterial: currentMaterial,
                                     wireframeEnabled: wireframeEnabled,
                                     currentMatcap: currentMatcap,
                                     currentFont: currentFont, textPixelSize: textPixelSize,
                                     textAlignH: textAlignH, textAlignV: textAlignV,
                                     textRenderMode: textRenderMode,
                                     textWritingDirection: textWritingDirection,
                                     textJustifies: textJustifies,
                                     textHangsPunctuation: textHangsPunctuation,
                                     tintColor: tintColor,
                                     currentBlend: currentBlend,
                                     currentDepth: currentDepth,
                                     symmetryFolds: symmetryFolds))
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
        strokeProfileShape = s.strokeProfileShape
        strokeOpacityShape = s.strokeOpacityShape
        strokeBrushShape = s.strokeBrushShape
        currentMaterial = s.currentMaterial
        wireframeEnabled = s.wireframeEnabled
        currentMatcap = s.currentMatcap
        currentFont = s.currentFont
        textPixelSize = s.textPixelSize
        textAlignH = s.textAlignH
        textAlignV = s.textAlignV
        textRenderMode = s.textRenderMode
        textWritingDirection = s.textWritingDirection
        textJustifies = s.textJustifies
        textHangsPunctuation = s.textHangsPunctuation
        tintColor = s.tintColor
        currentBlend = s.currentBlend
        currentDepth = s.currentDepth
        symmetryFolds = s.symmetryFolds
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
