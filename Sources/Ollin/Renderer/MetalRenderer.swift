import Foundation
import Metal
import MetalKit
import MetalPerformanceShaders   // tuned image kernels (Gaussian blur) behind the effect filters
import simd
import CoreGraphics
import COllinShaders   // OllinVertex / Uniforms / SDFInstance, shared with the shaders

/// The Metal back end. Deliberately small: one command queue, an enum-keyed
/// cache of render pipelines (keyed by shader pair × blend mode — solid
/// triangles, SDF quads, image quads, glyph quads), and a reusable vertex buffer.
///
/// You'll be editing this as you add primitives. The shape of the thing:
///
///   1. `Drawer` tessellates every primitive this frame into one flat
///      `[OllinVertex]` array (triangles, in sketch-space points).
///   2. `render(...)` uploads that array into `vertexBuffer`, clears to the
///      background color, and issues a single `drawPrimitives(.triangle)`.
///   3. the shaders map points -> clip space and output the vertex color.
///
/// To add a new primitive you usually only touch `Drawer` (more triangles).
/// You only touch this file when you need a *new pipeline* (e.g. instanced or
/// SDF circles, textured quads for images, a new blend mode): add a `Pipeline`
/// case and a branch in `makePipeline(_:)` — don't grow `init`.
///
/// Main-actor isolated: it's created and driven from the main thread (the
/// `MTKViewDelegate` draw callback and the headless export path). The only work
/// that intentionally runs off-actor is the GPU completed-handler, which signals
/// `frameBoundary` (a `Sendable` semaphore) and touches nothing else.
@MainActor
final class MetalRenderer {

    enum RendererError: Error {
        case commandQueue
        case shaderLibrary
        case shaderFunctions
    }

    /// Identifies a render pipeline so it's built once and cached in
    /// `pipelines`. A pipeline is a *combination* of a shader pair, blend mode,
    /// alpha convention, and (for 3D) a depth-attachment format — captured as a
    /// value here rather than one enum case per combination, so a new capability
    /// adds a factory or a field, not a case. The depth axis is the reason this
    /// is a descriptor struct and not an enum (see CLAUDE.md): a pipeline used in
    /// a depth-tested pass must declare its depth format, so it's part of the key.
    /// The `.normal`, no-depth variants are built up front; other combinations (a
    /// combining blend mode, a depth-tested 3D pass) build lazily on first use.
    private struct PipelineKey: Hashable {
        var vertex: String
        var fragment: String
        var blend: BlendMode = .normal
        /// Premultiplied color (the image path) vs straight-alpha (solid/SDF/glyph/points).
        var premultiplied = false
        /// nil for the 2D color-only pass; a depth format when the pass carries a
        /// depth attachment (an active 3D camera). Part of the key because the
        /// descriptor must declare it to be valid in that pass.
        var depthFormat: MTLPixelFormat? = nil
        /// The final tone-map pass is single-sample and targets the display
        /// format, unlike every geometry pipeline; this flag keeps it in the same
        /// cache (so live shader reload rebuilds it too).
        var isPresent = false
        /// The shadow depth pass: single-sample, depth-only (no color attachment, no
        /// fragment). Like `isPresent`, an exception to the geometry-pipeline shape,
        /// kept in the same cache so live shader reload rebuilds it too.
        var isShadow = false
        /// The point (cube) shadow pass writes distance into an `rg32Float` cube with
        /// two passes: 1 = MIN-blend into R (nearest), 2 = MAX-blend into G (farthest),
        /// for mid-point shadow mapping. 0 = not a point-shadow pipeline.
        var pointShadowOp = 0
        /// An effects filter pass: a fullscreen-triangle fragment shader writing the
        /// linear-float intermediate format, single-sample, blending off (replace).
        /// Like `isPresent`, an exception to the geometry-pipeline shape kept in the
        /// same cache so live shader reload rebuilds it too.
        var isEffect = false

        // tessellated triangles (rects, lines, polygons, arcs)
        static func solid(_ blend: BlendMode, depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_vertex", fragment: "ollin_fragment", blend: blend, depthFormat: depth)
        }
        // Expanded stroke + AA fringe (reuses the triangle vertex buffer; its own
        // vertex shader routes the per-vertex coverage as a separate interpolant the
        // fragment remaps to perceptual alpha, scaled by the paint's own alpha).
        static func fringe(_ blend: BlendMode, depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_fringe_vertex", fragment: "ollin_fringe_fragment", blend: blend, depthFormat: depth)
        }
        // instanced SDF quads (circles, ellipses, rects, lines, arcs)
        static func sdf(_ blend: BlendMode, depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_sdf_vertex", fragment: "ollin_sdf_fragment", blend: blend, depthFormat: depth)
        }
        // textured quads (images); the texture keeps the CGImage's premultiplied alpha
        static func image(_ blend: BlendMode, depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_image_vertex", fragment: "ollin_image_fragment",
                        blend: blend, premultiplied: true, depthFormat: depth)
        }
        // SDF-atlas text quads, straight-alpha coverage
        static func glyphAtlas(_ blend: BlendMode, depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_image_vertex", fragment: "ollin_glyph_fragment", blend: blend, depthFormat: depth)
        }
        // instanced GPU-particle discs (compute-resident buffer)
        static func points(_ blend: BlendMode, depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_particle_vertex", fragment: "ollin_particle_fragment", blend: blend, depthFormat: depth)
        }
        // instanced 3D point-cloud splats (camera-facing discs, depth-tested)
        static func pointCloud(_ blend: BlendMode, depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_point_vertex", fragment: "ollin_point_fragment", blend: blend, depthFormat: depth)
        }
        // solid 3D triangle mesh (depth-tested, lit by the material model)
        static func mesh(_ blend: BlendMode, depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_mesh_vertex", fragment: "ollin_mesh_fragment", blend: blend, depthFormat: depth)
        }
        // textured 3D triangle mesh: the surface samples a base-color texture at the
        // vertex UVs, otherwise the same depth-tested, lit mesh path.
        static func meshTextured(_ blend: BlendMode, depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_mesh_textured_vertex", fragment: "ollin_mesh_textured_fragment",
                        blend: blend, depthFormat: depth)
        }
        // wireframe 3D triangle mesh: triangle edges only (barycentric edge-shading),
        // unlit, depth-tested.
        static func meshWireframe(_ blend: BlendMode, depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_mesh_wireframe_vertex", fragment: "ollin_mesh_wireframe_fragment",
                        blend: blend, depthFormat: depth)
        }
        // matcap 3D triangle mesh: the whole look is baked into a sphere texture sampled
        // by the view-space normal, independent of the scene lights. Depth-tested.
        static func meshMatcap(_ blend: BlendMode, depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_mesh_matcap_vertex", fragment: "ollin_mesh_matcap_fragment",
                        blend: blend, depthFormat: depth)
        }
        // depth-scene backdrop: a textured quad that also writes per-pixel depth from
        // a depth map (premultiplied color, like the image path; outputs [[depth]]).
        static func depthScene(_ blend: BlendMode, depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_image_vertex", fragment: "ollin_depthscene_fragment",
                        blend: blend, premultiplied: true, depthFormat: depth)
        }
        // final fullscreen tone-map pass, float -> sRGB drawable
        static let present = PipelineKey(vertex: "ollin_present_vertex",
                                         fragment: "ollin_present_fragment", isPresent: true)
        // an effects filter pass: a fullscreen-triangle `fragment` (sharing the
        // present vertex) writing the linear-float intermediate, single-sample, replace.
        static func effect(_ fragment: String) -> PipelineKey {
            PipelineKey(vertex: "ollin_present_vertex", fragment: fragment, isEffect: true)
        }
        // depth-only shadow pass (mesh geometry from the light's point of view)
        static let meshShadow = PipelineKey(vertex: "ollin_mesh_shadow_vertex",
                                            fragment: "", isShadow: true)
        // omnidirectional shadow pass: six cube faces in one layered pass (instanced,
        // `render_target_array_index`) for a point caster. Two draws into one rg32Float
        // cube (mid-point shadow mapping): MIN-blend the distance into R (nearest),
        // MAX-blend into G (farthest); the receiver shadows past the midpoint.
        static let meshPointShadowMin = PipelineKey(vertex: "ollin_mesh_point_shadow_vertex",
                                                    fragment: "ollin_mesh_point_shadow_fragment",
                                                    isShadow: true, pointShadowOp: 1)
        static let meshPointShadowMax = PipelineKey(vertex: "ollin_mesh_point_shadow_vertex",
                                                    fragment: "ollin_mesh_point_shadow_fragment",
                                                    isShadow: true, pointShadowOp: 2)

        /// The pipeline a recorded batch needs, from its geometry kind, blend, the
        /// active depth format (nil in 2D), and — for a mesh — whether it's textured.
        static func forBatch(_ kind: GeometryKind, _ blend: BlendMode,
                             depth: MTLPixelFormat? = nil, textured: Bool = false,
                             wireframe: Bool = false, matcap: Bool = false) -> PipelineKey {
            switch kind {
            case .triangles:  return .solid(blend, depth: depth)
            case .fringe:     return .fringe(blend, depth: depth)
            case .sdf:        return .sdf(blend, depth: depth)
            case .image:      return .image(blend, depth: depth)
            case .glyphAtlas: return .glyphAtlas(blend, depth: depth)
            case .particles:  return .points(blend, depth: depth)
            case .points3D:   return .pointCloud(blend, depth: depth)
            case .mesh3D:
                return wireframe ? .meshWireframe(blend, depth: depth)
                     : matcap    ? .meshMatcap(blend, depth: depth)
                     : textured  ? .meshTextured(blend, depth: depth)
                                  : .mesh(blend, depth: depth)
            case .depthScene: return .depthScene(blend, depth: depth)
            }
        }
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var library: MTLLibrary
    /// The display/drawable format — sRGB 8-bit. The final present pass writes
    /// here; it's never a geometry render target anymore.
    private let pixelFormat: MTLPixelFormat
    /// The compositing substrate: a linear `rgba16Float` intermediate every
    /// geometry pipeline renders into, so values can exceed 1.0 (additive light)
    /// and many translucent blends don't band the way an 8-bit target would. The
    /// present pass tone-maps + encodes it down to `pixelFormat`.
    private let linearFormat: MTLPixelFormat = .rgba16Float
    /// MSAA sample count for the float geometry targets (the drawable itself is
    /// single-sample — MSAA happens in the intermediate, then resolves before the
    /// present pass tone-maps).
    private let sampleCount: Int
    /// Depth format for 3D passes (an active `Camera3D`). 2D passes carry no depth
    /// attachment, so a 2D sketch allocates none of this.
    private let depthPixelFormat: MTLPixelFormat = .depth32Float

    /// Render pipelines, built on first use and reused. Keyed by `Pipeline` so
    /// a new capability is a new case + a branch in `makePipeline(_:)`, never
    /// more inline construction in `init` (see CLAUDE.md).
    private var pipelines: [PipelineKey: MTLRenderPipelineState] = [:]

    /// Compute kernels are open-ended (one per user source), so they can't be a
    /// fixed enum like the render pipelines. They're cached separately, keyed by a
    /// hash of the composed source + the entry name. The composed *library* is
    /// cached per source too, so several entries in one source share one compile.
    private struct ComputeKey: Hashable { let sourceHash: UInt64; let entry: String }
    private var computePipelines: [ComputeKey: MTLComputePipelineState] = [:]
    private var computeLibraries: [UInt64: MTLLibrary] = [:]

    /// Triple-buffered vertex storage, gated by a semaphore so the CPU never
    /// overwrites vertices the GPU is still reading. Writing one shared buffer
    /// every frame with no synchronization tears the on-screen geometry (e.g.
    /// gaps in a stroked ring) because the next frame stomps it mid-draw. Each
    /// slot is grown on demand to keep steady-state frames allocation-free.
    private static let maxFramesInFlight = 3
    private let frameBoundary = DispatchSemaphore(value: MetalRenderer.maxFramesInFlight)
    private var vertexBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    /// Parallel ring for SDF instance data, advanced with `frameIndex` alongside
    /// `vertexBuffers` (one semaphore gates both — they're written and read
    /// together each frame).
    private var sdfBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    private var frameIndex = 0

    /// A separate vertex buffer for off-screen `image(of:)` renders, so headless
    /// export never shares a slot with the on-screen ring. Export is synchronous
    /// (it waits for the GPU before reading back), so one reusable buffer is
    /// enough — no ring needed — but it must not be a ring slot the live loop
    /// could still be reading for an in-flight frame.
    private var exportBuffer: MTLBuffer?
    private var sdfExportBuffer: MTLBuffer?

    /// Parallel ring + export buffer for textured-quad (image) vertices, advanced
    /// with `frameIndex` like the others.
    private var imageBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    private var imageExportBuffer: MTLBuffer?

    /// Parallel ring + export buffer for SDF-atlas text quads (also
    /// `OllinImageVertex`), advanced with `frameIndex` like the others.
    private var glyphBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    private var glyphExportBuffer: MTLBuffer?

    /// Parallel ring + export buffer for 3D point-cloud splats (`OllinPoint`),
    /// advanced with `frameIndex` like the others.
    private var pointBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    private var pointExportBuffer: MTLBuffer?

    /// Parallel ring + export buffer for solid 3D mesh vertices (`OllinMeshVertex`),
    /// advanced with `frameIndex` like the others.
    private var meshBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    private var meshExportBuffer: MTLBuffer?

    /// Depth-stencil states for the 3D path, built once. 3D geometry z-tests
    /// (less-equal) and writes depth; 2D batches in a 3D pass leave depth alone
    /// (always-pass, no write) so they composite over in draw order.
    private lazy var depthTestState: MTLDepthStencilState? = {
        let d = MTLDepthStencilDescriptor()
        d.depthCompareFunction = .lessEqual
        d.isDepthWriteEnabled = true
        return device.makeDepthStencilState(descriptor: d)
    }()
    private lazy var noDepthState: MTLDepthStencilState? = {
        let d = MTLDepthStencilDescriptor()
        d.depthCompareFunction = .always
        d.isDepthWriteEnabled = false
        return device.makeDepthStencilState(descriptor: d)
    }()

    /// Shadow mapping (opt-in via `castShadows()`). The depth pass from the casting
    /// light renders into `shadowMap` — a square `.private` depth texture sampled in
    /// the lit mesh fragment. `shadowMapResolution` must match `Drawer`'s (which uses
    /// it to size the normal-offset bias in world units). `dummyShadowMap` is a 1×1
    /// depth texture bound when shadows are off, so the mesh fragment's declared
    /// `depth2d` argument is always satisfied without a separate pipeline variant.
    /// `shadowSampler` is a comparison sampler (lessEqual) for hardware PCF.
    static let shadowMapResolution = 2048
    private var shadowMap: MTLTexture?
    private var dummyShadowMap: MTLTexture?
    /// The omnidirectional (point) shadow map: a `depthcube` rendered by the layered
    /// six-face pass and sampled by direction. Per-face resolution; allocated lazily on
    /// the first point-casting frame. `dummyPointShadowMap` is a 1×1 cube bound when no
    /// point caster is active, so the fragment's declared `depthcube` is always satisfied.
    static let pointShadowMapResolution = 1024
    private var pointShadowMap: MTLTexture?
    private var dummyPointShadowMap: MTLTexture?
    /// Whether this device can trace rays from the render stages. When true, a point
    /// caster is shadowed by *ray tracing* (an exact visibility ray against a per-frame
    /// acceleration structure built from the shadow casters) instead of the mid-point
    /// cube — no depth compare, so no acne/peter-pan/teeth tradeoff. The `Shader3D.metal`
    /// mesh fragments are compiled with `OLLIN_RT_SHADOWS` set from this, and the cube
    /// path stays the byte-identical fallback on devices without it.
    private let rayTracedShadows: Bool
    /// Whether the GPU has *dedicated* ray-tracing units (the A17/M3 generation and later,
    /// `MTLGPUFamily.apple9`+). The M1/M2 trace in software, ~5-10× slower, so the hardware-
    /// relative `Quality` tiers map to a higher ray count here than on a software-RT GPU.
    private let hasHardwareRayTracing: Bool
    /// The per-frame acceleration structure (rebuilt each point-RT-shadow frame from the
    /// shadow-caster triangles) and its scratch buffer, both grown in place as the scene
    /// size demands. `dummyShadowAccel` is a 1-triangle structure bound to the lit mesh
    /// fragment whenever no RT point shadow is active this frame, so its declared
    /// `primitive_acceleration_structure` argument is always satisfied (the fragment only
    /// traces it when `shadowKind == 2`).
    private var shadowAccel: MTLAccelerationStructure?
    private var shadowAccelScratch: MTLBuffer?
    private var shadowAccelCapacity = 0
    private var dummyShadowAccel: MTLAccelerationStructure?
    private lazy var shadowSampler: MTLSamplerState? = {
        let d = MTLSamplerDescriptor()
        d.minFilter = .linear
        d.magFilter = .linear
        d.sAddressMode = .clampToEdge
        d.tAddressMode = .clampToEdge
        d.compareFunction = .lessEqual
        return device.makeSamplerState(descriptor: d)
    }()
    /// A plain (non-comparison) sampler for the point-shadow cube, which stores linear
    /// distance and is read with `.sample()` rather than `.sample_compare()`. Nearest
    /// (a `depth32Float` cube isn't linearly filterable); the manual PCF taps soften it.
    private lazy var shadowCubeSampler: MTLSamplerState? = {
        let d = MTLSamplerDescriptor()
        d.minFilter = .nearest
        d.magFilter = .nearest
        d.sAddressMode = .clampToEdge
        d.tAddressMode = .clampToEdge
        return device.makeSamplerState(descriptor: d)
    }()

    /// The on-screen geometry targets: this frame's geometry composites into a
    /// linear-float MSAA target (`mainMSAA`, `.memoryless` — it lives only in tile
    /// memory since the frame clears each time and the samples aren't needed after
    /// the resolve), resolves into a single-sample float texture (`mainResolve`),
    /// and the present pass then tone-maps that into the drawable. Reused across
    /// frames; rebuilt on a size change.
    private var mainMSAA: MTLTexture?
    private var mainResolve: MTLTexture?
    private var mainSize = (width: 0, height: 0)

    /// The depth target for the live 3D path, paired with `mainMSAA` (same size +
    /// sample count). Allocated lazily only when a 3D camera is active — a 2D
    /// sketch never makes one. Memoryless: depth lives only in tile memory.
    private var mainDepth: MTLTexture?

    /// Per-frame-ring pools of effects-layer textures, reused across frames so a
    /// sketch that uses render targets every frame allocates them once. Keyed by the
    /// ring slot (`frameIndex`) so a texture is never reused while an in-flight frame
    /// still reads it: the same discipline as the vertex-buffer ring. `*Next` is the
    /// per-frame acquisition cursor, reset at the start of the effects graph.
    private var targetTexPool: [[(msaa: MTLTexture, resolve: MTLTexture, w: Int, h: Int)]] =
        Array(repeating: [], count: MetalRenderer.maxFramesInFlight)
    private var filterTexPool: [[(tex: MTLTexture, w: Int, h: Int)]] =
        Array(repeating: [], count: MetalRenderer.maxFramesInFlight)
    private var targetTexNext = 0
    private var filterTexNext = 0

    /// One `Feedback` layer's persistent ping-pong pair: two single-sample
    /// linear-float resolve textures. Each frame the block renders into the *back*
    /// (`flipped ? a : b`) while the sketch reads the *front* (`flipped ? b : a`),
    /// then `flipped` toggles so the back becomes next frame's front. `owner` is held
    /// weakly so the slot is pruned once the sketch releases its `Feedback` (a live
    /// reload, or a layer no longer used) and to catch an address reused by a new
    /// layer.
    private final class FeedbackSlot {
        let a: MTLTexture, b: MTLTexture
        let w: Int, h: Int
        var flipped = false
        weak var owner: Feedback?
        init(a: MTLTexture, b: MTLTexture, w: Int, h: Int, owner: Feedback) {
            self.a = a; self.b = b; self.w = w; self.h = h; self.owner = owner
        }
    }
    /// Persistent feedback storage, kept across frames (and across the live `pooled`
    /// ring and the headless path alike), distinct from the per-frame pools above,
    /// which is the whole point of feedback. Feedback is inherently serial (frame
    /// N+1 reads frame N's output), so Metal's automatic GPU↔GPU hazard tracking
    /// across command buffers serializes the dependency with no extra semaphore.
    private var feedbackSlots: [ObjectIdentifier: FeedbackSlot] = [:]
    /// Feedback layers drawn into this frame, so only those flip after the frame
    /// (a layer skipped this frame keeps its content as the next front).
    private var feedbackUsedThisFrame: Set<ObjectIdentifier> = []

    /// Off-screen targets for the GPU-texture frame hook (`texture(of:)`), kept and
    /// reused across frames — rebuilt only when the canvas size changes, so live
    /// frame-sharing (Syphon) doesn't allocate a texture every frame. Geometry
    /// composites into the float MSAA target (`textureTargetMSAA`, `.memoryless`),
    /// resolves into `textureFloatResolve`, and the present pass tone-maps that into
    /// `textureResolve` — the single-sample sRGB texture handed out (`.shaderRead`
    /// so a consumer can sample/copy it, `.pixelFormatView` for Syphon's byte-pass).
    private var textureTargetMSAA: MTLTexture?
    private var textureFloatResolve: MTLTexture?
    private var textureResolve: MTLTexture?
    private var textureTargetSize = (width: 0, height: 0)

    /// The persistent accumulation surface (`Drawer.accumulates` / `noClear`): a
    /// render target the frame *doesn't* clear, so additive samples pile up across
    /// frames. `accumTarget` is an MSAA target kept private (so its samples persist
    /// — never `.memoryless`); each frame loads it, draws this frame's geometry,
    /// and resolves into `accumResolve` (single-sample, `.shaderRead`+blit) for
    /// presentation and read-back. Kept at the active draw size and reset (the next
    /// frame clears) when the size changes or the sketch calls `background(_:)`.
    /// Reusing the same MSAA target keeps the existing pipelines (no new sample-count
    /// variant) and preserves edge anti-aliasing while accumulating. The targets are
    /// linear-float, so faint additive samples (below 1/255) sum correctly instead of
    /// quantizing away — the precision the light-accumulation look needs. `accumResolve`
    /// holds the raw linear pile; presentation/read-back tone-maps it through
    /// `accumDisplay` (a single-sample sRGB texture) so a consumer gets display-ready
    /// bytes, never the raw HDR float.
    private var accumTarget: MTLTexture?
    private var accumResolve: MTLTexture?
    private var accumDisplay: MTLTexture?
    private var accumSize = (width: 0, height: 0)
    private var accumNeedsClear = true

    /// Sampler for the image pipeline: linear filtering, clamp to edge. Built once.
    /// Also samples the gradient strip (the same filtering is exactly what a LUT
    /// row wants).
    private let imageSampler: MTLSamplerState?

    /// The gradient strip: one row per distinct gradient ramp this frame, baked
    /// on the CPU (see `BakedGradient`) and sampled by the SDF fragment. Reused
    /// while the frame's rows are unchanged (the common case — a steady sketch
    /// uploads nothing); a *new* texture is made when they change, because the
    /// old one may still be read by an in-flight frame (the command buffer
    /// retains it until completion, so swapping the reference is safe where
    /// rewriting the contents is not).
    private var gradientStrip: MTLTexture?
    private var gradientStripRows: [[UInt8]] = []

    init(device: MTLDevice, pixelFormat: MTLPixelFormat, sampleCount: Int) throws {
        self.device = device
        self.pixelFormat = pixelFormat
        self.sampleCount = sampleCount

        guard let queue = device.makeCommandQueue() else {
            throw RendererError.commandQueue
        }
        self.commandQueue = queue
        self.rayTracedShadows = device.supportsRaytracing && device.supportsRaytracingFromRender
        self.hasHardwareRayTracing = device.supportsFamily(.apple9)

        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        self.imageSampler = device.makeSamplerState(descriptor: samplerDesc)

        self.library = try MetalRenderer.loadLibrary(device: device)

        // Build the pipelines we know we need now; `pipeline(_:)` builds any
        // added later on first use. Building here surfaces shader errors at
        // startup rather than mid-frame.
        _ = try pipeline(.solid(.normal))
        _ = try pipeline(.sdf(.normal))
        _ = try pipeline(.image(.normal))
        _ = try pipeline(.glyphAtlas(.normal))
        _ = try pipeline(.present)
    }

    /// Encode and present one frame's worth of recorded geometry: composite into
    /// the linear-float intermediate, then run the present pass to tone-map it into
    /// the drawable.
    func render(_ drawer: Drawer, viewport: SIMD2<Float>, in view: MTKView) {
        if drawer.accumulates {
            renderAccumulating(drawer, viewport: viewport, in: view)
            return
        }
        let width = Int(view.drawableSize.width.rounded())
        let height = Int(view.drawableSize.height.rounded())
        guard width > 0, height > 0, let drawable = view.currentDrawable else { return }

        // (Re)allocate the cached float geometry targets on a size change. The MSAA
        // target is memoryless (tile-only); the resolve is sampled by the present pass.
        if mainSize != (width, height) || mainMSAA == nil || mainResolve == nil {
            guard let msaa = makeFloatMSAA(width: width, height: height, storage: .memoryless),
                  let resolve = makeFloatResolve(width: width, height: height) else { return }
            mainMSAA = msaa; mainResolve = resolve; mainSize = (width, height)
        }
        guard let msaa = mainMSAA, let resolve = mainResolve else { return }

        // Block until a vertex-buffer slot frees up, then advance to the next one
        // in the ring — so this frame's upload can't stomp a buffer the GPU is
        // still reading for an in-flight frame.
        frameBoundary.wait()
        frameIndex = (frameIndex + 1) % MetalRenderer.maxFramesInFlight

        let geomPass = MTLRenderPassDescriptor()
        geomPass.colorAttachments[0].texture = msaa
        geomPass.colorAttachments[0].resolveTexture = resolve
        geomPass.colorAttachments[0].loadAction = .clear
        geomPass.colorAttachments[0].clearColor = drawer.backgroundColor.mtlClearColor
        geomPass.colorAttachments[0].storeAction = .multisampleResolve

        // A 3D camera *or* a depth scene adds a depth attachment, paired to mainMSAA
        // (allocated lazily; a plain 2D sketch never allocates one). Memoryless,
        // cleared to the far plane.
        var passDepthFormat: MTLPixelFormat? = nil
        if drawer.usesDepthBuffer {
            if mainDepth?.width != width || mainDepth?.height != height {
                mainDepth = makeDepthMSAA(width: width, height: height)
            }
            if let depth = mainDepth {
                geomPass.depthAttachment.texture = depth
                geomPass.depthAttachment.loadAction = .clear
                geomPass.depthAttachment.clearDepth = 1.0
                geomPass.depthAttachment.storeAction = .dontCare
                passDepthFormat = depthPixelFormat
            }
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            frameBoundary.signal()   // nothing encoded; hand the slot back
            return
        }
        encodeCompute(drawer, into: commandBuffer)   // sim steps before the render pass
        // Shadow depth pass from the casting light, ahead of the geometry pass in the
        // same command buffer (a no-op returning nil when this frame casts no shadow).
        // It shares the mesh vertex buffer the geometry pass uses.
        let meshBuf = meshBuffer(at: frameIndex, for: drawer.meshVertices.count)
        let renderedShadow = encodeShadowPass(drawer, into: commandBuffer, meshBuffer: meshBuf)

        // Effects layers fill before the main pass (which samples them via drawImage),
        // sharing this frame's geometry buffers. A no-op when the frame used none.
        let buffers = GeometryBuffers(
            triangle: vertexBuffer(at: frameIndex, for: drawer.vertices.count),
            sdf: sdfBuffer(at: frameIndex, for: drawer.sdfInstances.count),
            image: imageBuffer(at: frameIndex, for: drawer.imageVertices.count),
            glyph: glyphBuffer(at: frameIndex, for: drawer.glyphVertices.count),
            point: pointBuffer(at: frameIndex, for: drawer.points.count),
            mesh: meshBuf)
        encodeEffectTargets(drawer, into: commandBuffer, buffers: buffers, pooled: true)

        guard let geomEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: geomPass) else {
            frameBoundary.signal()   // nothing encoded; hand the slot back
            return
        }
        commandBuffer.addCompletedHandler { [frameBoundary] _ in frameBoundary.signal() }

        encode(drawer, viewport: viewport, into: geomEncoder,
               triangleBuffer: buffers.triangle, sdfBuffer: buffers.sdf,
               imageBuffer: buffers.image, glyphBuffer: buffers.glyph,
               pointBuffer: buffers.point, meshBuffer: buffers.mesh,
               depthFormat: passDepthFormat, shadowMap: renderedShadow.twoD,
               shadowCube: renderedShadow.cube,
               shadowAccel: renderedShadow.accel)
        geomEncoder.endEncoding()

        // Whole-frame postProcess filters run over the resolved frame before present.
        let presented = applyFrameFilters(drawer, resolved: resolve, width: width, height: height,
                                          into: commandBuffer, pooled: true)
        if let presentEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: presentPass(into: drawable.texture)) {
            encodePresent(from: presented, drawer: drawer, into: presentEncoder)
            presentEncoder.endEncoding()
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: Accumulation surface (noClear)

    /// Live accumulation path: render this frame's geometry onto the persistent
    /// accumulation surface — loading the prior pile unless this frame resets — then
    /// blit the resolved canvas to the drawable to present it. Reuses the
    /// triple-buffer vertex ring and its semaphore exactly like `render`, so the
    /// upload still can't stomp a buffer an in-flight frame is reading.
    private func renderAccumulating(_ drawer: Drawer, viewport: SIMD2<Float>, in view: MTKView) {
        let width = Int(view.drawableSize.width.rounded())
        let height = Int(view.drawableSize.height.rounded())
        guard width > 0, height > 0, let drawable = view.currentDrawable else { return }

        frameBoundary.wait()
        frameIndex = (frameIndex + 1) % MetalRenderer.maxFramesInFlight

        guard let pass = accumulationPass(drawer, width: width, height: height),
              let resolve = accumResolve,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            frameBoundary.signal()      // nothing encoded; hand the slot back
            return
        }
        encodeCompute(drawer, into: commandBuffer)   // sim steps before the render pass
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            frameBoundary.signal()      // nothing encoded; hand the slot back
            return
        }
        commandBuffer.addCompletedHandler { [frameBoundary] _ in frameBoundary.signal() }

        encode(drawer, viewport: viewport, into: encoder,
               triangleBuffer: vertexBuffer(at: frameIndex, for: drawer.vertices.count),
               sdfBuffer: sdfBuffer(at: frameIndex, for: drawer.sdfInstances.count),
               imageBuffer: imageBuffer(at: frameIndex, for: drawer.imageVertices.count),
               glyphBuffer: glyphBuffer(at: frameIndex, for: drawer.glyphVertices.count),
               pointBuffer: pointBuffer(at: frameIndex, for: drawer.points.count),
               meshBuffer: meshBuffer(at: frameIndex, for: drawer.meshVertices.count),
               depthFormat: nil)   // 3D + accumulation isn't supported in M1
        encoder.endEncoding()

        // Present: tone-map the resolved float pile into the drawable. (The pile
        // itself stays in linear float, so faint samples keep summing next frame.)
        if let presentEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: presentPass(into: drawable.texture)) {
            encodePresent(from: resolve, drawer: drawer, into: presentEncoder)
            presentEncoder.endEncoding()
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Headless accumulation: render this frame's geometry onto the persistent
    /// accumulation surface (load/clear per the drawer) and read the resolved
    /// canvas back as a `CGImage`. The off-screen companion to
    /// `renderAccumulating`, used by the export drivers (still / sequence / video /
    /// GIF) — call it once per frame in order and the pile builds across the run.
    /// Synchronous: waits for the GPU before reading back.
    func accumulatedImage(of drawer: Drawer, viewport: SIMD2<Float>, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0,
              let pass = accumulationPass(drawer, width: width, height: height),
              let resolve = accumResolve, let display = accumDisplay,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return nil }
        encodeCompute(drawer, into: commandBuffer)   // sim steps before the render pass
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }

        encode(drawer, viewport: viewport, into: encoder,
               triangleBuffer: exportVertexBuffer(for: drawer.vertices.count),
               sdfBuffer: exportSDFBuffer(for: drawer.sdfInstances.count),
               imageBuffer: exportImageBuffer(for: drawer.imageVertices.count),
               glyphBuffer: exportGlyphBuffer(for: drawer.glyphVertices.count),
               pointBuffer: exportPointBuffer(for: drawer.points.count),
               meshBuffer: exportMeshBuffer(for: drawer.meshVertices.count),
               depthFormat: nil)   // 3D + accumulation isn't supported in M1
        encoder.endEncoding()

        // Tone-map the float pile into the sRGB display texture, then read that back.
        if let presentEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: presentPass(into: display)) {
            encodePresent(from: resolve, drawer: drawer, into: presentEncoder)
            presentEncoder.endEncoding()
        }

        let bytesPerRow = width * 4, byteCount = bytesPerRow * height
        guard let readbackBuffer = device.makeBuffer(length: byteCount, options: .storageModeShared),
              let blit = commandBuffer.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: display, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: readbackBuffer, destinationOffset: 0,
                  destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: byteCount)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return MetalRenderer.cgImage(fromBGRA8: readbackBuffer, width: width, height: height)
    }

    /// Read the current accumulated canvas back as a `CGImage` without re-rendering
    /// the geometry — for the live frame-grab hook (a recorder/Syphon consumer)
    /// while accumulating, since the on-screen pile is exactly what it wants. Runs
    /// the tone-map present pass over the existing float pile first (it can't hand
    /// back the raw HDR float). Nil before the first accumulating frame.
    func accumulatedFrameImage(_ drawer: Drawer) -> CGImage? {
        guard let display = accumulatedDisplayTexture(drawer) else { return nil }
        return readback(display, width: accumSize.width, height: accumSize.height)
    }

    /// The current accumulated canvas as a tone-mapped sRGB texture, for the
    /// GPU-texture frame hook while accumulating — handed straight to a consumer
    /// that stays on the GPU. Nil before the first accumulating frame.
    func accumulatedTexture(_ drawer: Drawer) -> MTLTexture? {
        accumulatedDisplayTexture(drawer)
    }

    /// Tone-map the existing float accumulation pile into `accumDisplay` (no
    /// geometry re-render) and return it. Synchronous: waits for the GPU so the
    /// display texture is complete on return.
    private func accumulatedDisplayTexture(_ drawer: Drawer) -> MTLTexture? {
        guard let resolve = accumResolve, let display = accumDisplay,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let presentEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: presentPass(into: display)) else {
            return nil
        }
        encodePresent(from: resolve, drawer: drawer, into: presentEncoder)
        presentEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return display
    }

    /// Wipe the accumulated canvas on the next accumulating frame — for a live
    /// reload, so a freshly swapped-in sketch starts from a clean surface rather
    /// than inheriting the previous sketch's pile (the fresh-restart reload model).
    func resetAccumulation() { accumNeedsClear = true }

    /// Build the render pass for one accumulation frame, (re)allocating the
    /// persistent target on a size change and choosing load vs clear. The frame
    /// clears (to the background color) only when the target was just (re)allocated
    /// or the sketch called `background(_:)` this frame; otherwise it loads the
    /// accumulated pile. Always resolves to `accumResolve` and stores the samples
    /// back so they persist to the next frame.
    private func accumulationPass(_ drawer: Drawer, width: Int, height: Int) -> MTLRenderPassDescriptor? {
        if accumSize != (width, height) || accumTarget == nil || accumResolve == nil {
            // The MSAA target is `.private` (never memoryless) so its samples
            // persist across frames; both it and the resolve are linear float so
            // faint additive samples accumulate without quantizing away.
            guard let msaa = makeFloatMSAA(width: width, height: height, storage: .private),
                  let resolve = makeFloatResolve(width: width, height: height),
                  let display = makeDisplayTexture(width: width, height: height) else { return nil }
            accumTarget = msaa
            accumResolve = resolve
            accumDisplay = display         // tone-mapped output for hand-off / read-back
            accumSize = (width, height)
            accumNeedsClear = true         // fresh memory: clear before the first load
        }
        guard let msaa = accumTarget, let resolve = accumResolve else { return nil }

        let reset = accumNeedsClear || drawer.backgroundSetThisFrame
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = msaa
        pass.colorAttachments[0].resolveTexture = resolve
        pass.colorAttachments[0].loadAction = reset ? .clear : .load
        pass.colorAttachments[0].clearColor = drawer.backgroundColor.mtlClearColor
        pass.colorAttachments[0].storeAction = .storeAndMultisampleResolve
        accumNeedsClear = false
        return pass
    }

    /// Blit `texture` into a CPU-readable buffer and build a `CGImage`. A
    /// standalone command buffer (commits + waits) for reading a texture an earlier
    /// command buffer already produced (the live accumulation grab).
    private func readback(_ texture: MTLTexture, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4, byteCount = bytesPerRow * height
        guard let buffer = device.makeBuffer(length: byteCount, options: .storageModeShared),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: buffer, destinationOffset: 0,
                  destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: byteCount)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return MetalRenderer.cgImage(fromBGRA8: buffer, width: width, height: height)
    }

    /// Build an opaque BGRA8 `CGImage` from a shared buffer of `width*height*4`
    /// bytes (the resolved-texture read-back layout). Shared by `image(of:)` and
    /// the accumulation read-back paths.
    private static func cgImage(fromBGRA8 buffer: MTLBuffer, width: Int, height: Int) -> CGImage? {
        let bytesPerRow = width * 4, byteCount = bytesPerRow * height
        let data = Data(bytes: buffer.contents(), count: byteCount)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: bitmapInfo, provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Render `drawer`'s geometry off-screen to a `CGImage` of `width`×`height`
    /// pixels — same pipeline, MSAA, and blending as on-screen — for frame export
    /// (PNG, and later PNG sequences for video). Headless: needs no view or
    /// window. Synchronous: waits for the GPU before reading back.
    func image(of drawer: Drawer, viewport: SIMD2<Float>, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0 else { return nil }

        // Float MSAA target + float resolve for the geometry, plus an sRGB display
        // texture the present pass tone-maps into and we read back.
        guard let msaaTexture = makeFloatMSAA(width: width, height: height, storage: .memoryless),
              let resolveTexture = makeFloatResolve(width: width, height: height),
              let displayTexture = makeDisplayTexture(width: width, height: height) else { return nil }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = msaaTexture
        pass.colorAttachments[0].resolveTexture = resolveTexture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = drawer.backgroundColor.mtlClearColor
        pass.colorAttachments[0].storeAction = .multisampleResolve

        // A 3D camera or a depth scene adds a (freshly allocated, memoryless) depth
        // attachment so the headless/snapshot path z-tests exactly like the live window.
        var passDepthFormat: MTLPixelFormat? = nil
        if drawer.usesDepthBuffer, let depth = makeDepthMSAA(width: width, height: height) {
            pass.depthAttachment.texture = depth
            pass.depthAttachment.loadAction = .clear
            pass.depthAttachment.clearDepth = 1.0
            pass.depthAttachment.storeAction = .dontCare
            passDepthFormat = depthPixelFormat
        }

        let bytesPerRow = width * 4
        let byteCount = bytesPerRow * height

        guard let readback = device.makeBuffer(length: byteCount, options: .storageModeShared),
              let commandBuffer = commandQueue.makeCommandBuffer() else { return nil }
        encodeCompute(drawer, into: commandBuffer)   // sim steps before the render pass
        // Shadow depth pass (nil when this frame casts no shadow), sharing the export
        // mesh buffer; so the headless/snapshot path shadows exactly like the window.
        let meshBuf = exportMeshBuffer(for: drawer.meshVertices.count)
        let renderedShadow = encodeShadowPass(drawer, into: commandBuffer, meshBuffer: meshBuf)

        // Effects layers fill before the main pass, sharing the export buffers, so
        // the headless/snapshot path renders targets exactly like the window.
        let buffers = GeometryBuffers(
            triangle: exportVertexBuffer(for: drawer.vertices.count),
            sdf: exportSDFBuffer(for: drawer.sdfInstances.count),
            image: exportImageBuffer(for: drawer.imageVertices.count),
            glyph: exportGlyphBuffer(for: drawer.glyphVertices.count),
            point: exportPointBuffer(for: drawer.points.count),
            mesh: meshBuf)
        encodeEffectTargets(drawer, into: commandBuffer, buffers: buffers, pooled: false)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }

        encode(drawer, viewport: viewport, into: encoder,
               triangleBuffer: buffers.triangle, sdfBuffer: buffers.sdf,
               imageBuffer: buffers.image, glyphBuffer: buffers.glyph,
               pointBuffer: buffers.point, meshBuffer: buffers.mesh,
               depthFormat: passDepthFormat, shadowMap: renderedShadow.twoD,
               shadowCube: renderedShadow.cube,
               shadowAccel: renderedShadow.accel)
        encoder.endEncoding()

        // Tone-map the resolved float frame (after whole-frame postProcess filters)
        // into the sRGB display texture.
        let presented = applyFrameFilters(drawer, resolved: resolveTexture, width: width, height: height,
                                          into: commandBuffer, pooled: false)
        guard let presentEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: presentPass(into: displayTexture)) else { return nil }
        encodePresent(from: presented, drawer: drawer, into: presentEncoder)
        presentEncoder.endEncoding()

        // Copy the display texture into a CPU-readable buffer (works on every
        // Mac GPU, unlike texture.getBytes on discrete cards).
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: displayTexture, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: readback, destinationOffset: 0,
                  destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: byteCount)
        blit.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // BGRA8 bytes -> CGImage. Frames are opaque, so skip the alpha channel.
        return MetalRenderer.cgImage(fromBGRA8: readback, width: width, height: height)
    }

    /// Render `drawer`'s already-recorded scene `iterations` times into off-screen targets
    /// (no read-back) and return the **average GPU milliseconds per frame**, from the command
    /// buffer's GPU start/end timestamps — vsync-independent, so it measures the true frame
    /// cost the on-screen path is bounded by. For the shadow benchmark tool; the first frame
    /// is dropped as warm-up. Returns 0 on setup failure.
    func benchmarkGPUMilliseconds(_ drawer: Drawer, viewport: SIMD2<Float>,
                                  width: Int, height: Int, iterations: Int) -> Double {
        guard width > 0, height > 0, iterations > 1,
              let msaaTexture = makeFloatMSAA(width: width, height: height, storage: .memoryless),
              let resolveTexture = makeFloatResolve(width: width, height: height),
              let displayTexture = makeDisplayTexture(width: width, height: height) else { return 0 }
        let depthTexture = drawer.usesDepthBuffer ? makeDepthMSAA(width: width, height: height) : nil
        let meshBuf = exportMeshBuffer(for: drawer.meshVertices.count)
        var totalMs = 0.0, counted = 0
        for i in 0..<iterations {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = msaaTexture
            pass.colorAttachments[0].resolveTexture = resolveTexture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = drawer.backgroundColor.mtlClearColor
            pass.colorAttachments[0].storeAction = .multisampleResolve
            var passDepthFormat: MTLPixelFormat? = nil
            if let depthTexture {
                pass.depthAttachment.texture = depthTexture
                pass.depthAttachment.loadAction = .clear
                pass.depthAttachment.clearDepth = 1.0
                pass.depthAttachment.storeAction = .dontCare
                passDepthFormat = depthPixelFormat
            }
            guard let cb = commandQueue.makeCommandBuffer() else { continue }
            encodeCompute(drawer, into: cb)
            let renderedShadow = encodeShadowPass(drawer, into: cb, meshBuffer: meshBuf)
            guard let encoder = cb.makeRenderCommandEncoder(descriptor: pass) else { continue }
            encode(drawer, viewport: viewport, into: encoder,
                   triangleBuffer: exportVertexBuffer(for: drawer.vertices.count),
                   sdfBuffer: exportSDFBuffer(for: drawer.sdfInstances.count),
                   imageBuffer: exportImageBuffer(for: drawer.imageVertices.count),
                   glyphBuffer: exportGlyphBuffer(for: drawer.glyphVertices.count),
                   pointBuffer: exportPointBuffer(for: drawer.points.count),
                   meshBuffer: meshBuf,
                   depthFormat: passDepthFormat, shadowMap: renderedShadow.twoD,
                   shadowCube: renderedShadow.cube, shadowAccel: renderedShadow.accel)
            encoder.endEncoding()
            if let presentEncoder = cb.makeRenderCommandEncoder(descriptor: presentPass(into: displayTexture)) {
                encodePresent(from: resolveTexture, drawer: drawer, into: presentEncoder)
                presentEncoder.endEncoding()
            }
            cb.commit()
            cb.waitUntilCompleted()
            if i > 0 { totalMs += (cb.gpuEndTime - cb.gpuStartTime) * 1000; counted += 1 }
        }
        return counted > 0 ? totalMs / Double(counted) : 0
    }

    /// Render `drawer`'s geometry off-screen and return the resolved color texture
    /// (single-sample, sRGB, `.shaderRead`) — same pipeline, MSAA, and blending as
    /// on-screen and as `image(of:)`, but **without** the CPU read-back. The
    /// GPU-only companion to `image(of:)`, for handing the live frame to a consumer
    /// that stays on the GPU (Syphon publishing; later the effects graph).
    ///
    /// The returned texture is reused on the next call (the target is cached and
    /// only rebuilt on a size change), so a consumer must *copy* from it during the
    /// call, not retain it across frames. Synchronous: waits for the GPU so the
    /// texture is complete on return.
    func texture(of drawer: Drawer, viewport: SIMD2<Float>, width: Int, height: Int) -> MTLTexture? {
        guard width > 0, height > 0 else { return nil }

        if textureTargetSize != (width, height) || textureTargetMSAA == nil
            || textureFloatResolve == nil || textureResolve == nil {
            guard let msaa = makeFloatMSAA(width: width, height: height, storage: .memoryless),
                  let floatResolve = makeFloatResolve(width: width, height: height),
                  let display = makeDisplayTexture(width: width, height: height) else { return nil }
            textureTargetMSAA = msaa
            textureFloatResolve = floatResolve
            textureResolve = display
            textureTargetSize = (width, height)
        }
        guard let msaaTexture = textureTargetMSAA,
              let floatResolve = textureFloatResolve,
              let displayTexture = textureResolve else { return nil }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = msaaTexture
        pass.colorAttachments[0].resolveTexture = floatResolve
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = drawer.backgroundColor.mtlClearColor
        pass.colorAttachments[0].storeAction = .multisampleResolve

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return nil }
        encodeCompute(drawer, into: commandBuffer)   // sim steps before the render pass
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }

        encode(drawer, viewport: viewport, into: encoder,
               triangleBuffer: exportVertexBuffer(for: drawer.vertices.count),
               sdfBuffer: exportSDFBuffer(for: drawer.sdfInstances.count),
               imageBuffer: exportImageBuffer(for: drawer.imageVertices.count),
               glyphBuffer: exportGlyphBuffer(for: drawer.glyphVertices.count),
               pointBuffer: exportPointBuffer(for: drawer.points.count),
               meshBuffer: exportMeshBuffer(for: drawer.meshVertices.count),
               depthFormat: nil)   // 3D over the texture/Syphon hand-off isn't supported in M1
        encoder.endEncoding()

        // Tone-map the resolved float frame into the sRGB display texture handed out.
        guard let presentEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: presentPass(into: displayTexture)) else { return nil }
        encodePresent(from: floatResolve, drawer: drawer, into: presentEncoder)
        presentEncoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return displayTexture
    }

    // MARK: Layered effects (render targets + filters)

    /// The frame's geometry buffers, bundled so the effect-target passes and the
    /// main pass draw from the same uploads.
    private struct GeometryBuffers {
        var triangle: MTLBuffer?
        var sdf: MTLBuffer?
        var image: MTLBuffer?
        var glyph: MTLBuffer?
        var point: MTLBuffer?
        var mesh: MTLBuffer?
    }

    /// Fill every effects layer this frame, ahead of the main pass: render each
    /// geometry target's tagged batches into its own texture, then run each filter
    /// op into its output texture. Each layer ends with `texture` set, so the main
    /// pass (and later filters) can sample it. A no-op when the frame used no
    /// targets, so the ordinary path is byte-identical. `pooled` reuses per-frame
    /// textures on the live ring; the headless paths allocate fresh and wait.
    private func encodeEffectTargets(_ drawer: Drawer, into cb: MTLCommandBuffer,
                                     buffers: GeometryBuffers, pooled: Bool) {
        guard !drawer.renderTargets.isEmpty || !drawer.filterOps.isEmpty
            || !drawer.frameFilters.isEmpty else { return }
        targetTexNext = 0
        filterTexNext = 0
        // Generators read no input, so fill them first (a filter may sample one),
        // each a single fullscreen fragment pass into a sampleable filter texture.
        for target in drawer.renderTargets {
            guard case let .generator(generator) = target.origin else { continue }
            guard let out = acquireFilterTexture(width: target.pixelWidth,
                                                 height: target.pixelHeight, pooled: pooled) else { continue }
            encodeGenerator(generator, output: out,
                            width: target.pixelWidth, height: target.pixelHeight, into: cb)
            target.texture = out
        }
        for target in drawer.renderTargets {
            guard case .geometry = target.origin else { continue }
            let pw = target.pixelWidth, ph = target.pixelHeight
            guard let tex = acquireTargetTextures(width: pw, height: ph, pooled: pooled) else { continue }
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = tex.msaa
            pass.colorAttachments[0].resolveTexture = tex.resolve
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = target.clearColor.mtlClearColor
            pass.colorAttachments[0].storeAction = .multisampleResolve
            guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { continue }
            // Geometry inside the block used canvas coordinates, so map by the logical
            // size; a fraction-res layer's smaller attachment just downsamples.
            encode(drawer, viewport: SIMD2(Float(target.width), Float(target.height)), into: enc,
                   triangleBuffer: buffers.triangle, sdfBuffer: buffers.sdf, imageBuffer: buffers.image,
                   glyphBuffer: buffers.glyph, pointBuffer: buffers.point, meshBuffer: buffers.mesh,
                   depthFormat: nil, target: target)
            enc.endEncoding()
            target.texture = tex.resolve
        }
        // Feedback layers: like a geometry target, but rendered into persistent
        // ping-pong storage. The block reads the *front* (last frame, exposed as
        // `previous`) while drawing into the *back*; the pair flips after the frame.
        for target in drawer.renderTargets {
            guard case let .feedback(fb) = target.origin else { continue }
            let pw = target.pixelWidth, ph = target.pixelHeight
            guard let slot = feedbackSlot(for: fb, width: pw, height: ph, into: cb),
                  let msaa = makeFloatMSAA(width: pw, height: ph, storage: .memoryless) else { continue }
            let front = slot.flipped ? slot.b : slot.a
            let back  = slot.flipped ? slot.a : slot.b
            fb.previousLayer.texture = front     // `previous` resolves to last frame
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = msaa
            pass.colorAttachments[0].resolveTexture = back
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = target.clearColor.mtlClearColor
            pass.colorAttachments[0].storeAction = .multisampleResolve
            guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { continue }
            encode(drawer, viewport: SIMD2(Float(target.width), Float(target.height)), into: enc,
                   triangleBuffer: buffers.triangle, sdfBuffer: buffers.sdf, imageBuffer: buffers.image,
                   glyphBuffer: buffers.glyph, pointBuffer: buffers.point, meshBuffer: buffers.mesh,
                   depthFormat: nil, target: target)
            enc.endEncoding()
            target.texture = back                // `image` resolves to this frame
            feedbackUsedThisFrame.insert(ObjectIdentifier(fb))
        }
        for output in drawer.filterOps {
            guard case let .filter(input, filter) = output.origin, let src = input.texture else { continue }
            output.texture = applyFilter(filter, input: src,
                                         width: output.pixelWidth, height: output.pixelHeight,
                                         into: cb, pooled: pooled)
        }
        // Advance each feedback layer drawn this frame (its back becomes next frame's
        // front), then prune slots whose owner the sketch has released (live reload,
        // or a layer no longer held) so the map stays bounded.
        for id in feedbackUsedThisFrame { feedbackSlots[id]?.flipped.toggle() }
        feedbackUsedThisFrame.removeAll(keepingCapacity: true)
        if feedbackSlots.contains(where: { $0.value.owner == nil }) {
            feedbackSlots = feedbackSlots.filter { $0.value.owner != nil }
        }
    }

    /// Apply the whole-frame `postProcess` filters to the resolved float frame,
    /// returning the texture to present (the input itself when there are none).
    private func applyFrameFilters(_ drawer: Drawer, resolved: MTLTexture,
                                   width: Int, height: Int, into cb: MTLCommandBuffer,
                                   pooled: Bool) -> MTLTexture {
        var current = resolved
        for filter in drawer.frameFilters {
            if let out = applyFilter(filter, input: current, width: width, height: height,
                                     into: cb, pooled: pooled) {
                current = out
            }
        }
        return current
    }

    /// Run one `filter` from `input` into a freshly acquired output texture. Blur is
    /// a hardware MPS kernel and bloom a bright-pass + blur + add-back chain; the rest
    /// are single fullscreen fragment passes, each reading premultiplied-linear input
    /// and writing the same. `f` is the float vector of the type's parameters.
    private func applyFilter(_ filter: Filter, input: MTLTexture, width: Int, height: Int,
                             into cb: MTLCommandBuffer, pooled: Bool) -> MTLTexture? {
        // One fragment pass into a fresh output texture (the common shape).
        func pass(_ fragment: String, _ inputs: [MTLTexture], _ params: [SIMD4<Float>]) -> MTLTexture? {
            guard let output = acquireFilterTexture(width: width, height: height, pooled: pooled) else { return nil }
            encodeEffectFragment(fragment, inputs: inputs, output: output, params: params, into: cb)
            return output
        }
        let texel = SIMD4<Float>(1 / Float(width), 1 / Float(height), 0, 0)
        let aspect = Float(width) / Float(max(1, height))
        let f = { (a: Double, b: Double, c: Double, d: Double) in
            SIMD4<Float>(Float(a), Float(b), Float(c), Float(d)) }

        switch filter.kind {
        case .gaussianBlur(let radius):
            guard let output = acquireFilterTexture(width: width, height: height, pooled: pooled) else { return nil }
            let blur = MPSImageGaussianBlur(device: device, sigma: Float(max(0.1, radius)))
            blur.edgeMode = .clamp
            blur.encode(commandBuffer: cb, sourceTexture: input, destinationTexture: output)
            return output
        case .bloom(let threshold, let intensity, let radius):
            guard let bright = acquireFilterTexture(width: width, height: height, pooled: pooled),
                  let blurred = acquireFilterTexture(width: width, height: height, pooled: pooled),
                  let output = acquireFilterTexture(width: width, height: height, pooled: pooled) else { return nil }
            // Bright-pass → blur → add the glow back onto the original.
            encodeEffectFragment("ollin_fx_brightpass", inputs: [input], output: bright,
                                 params: [f(threshold, 0, 0, 0)], into: cb)
            let blur = MPSImageGaussianBlur(device: device, sigma: Float(max(0.1, radius)))
            blur.edgeMode = .clamp
            blur.encode(commandBuffer: cb, sourceTexture: bright, destinationTexture: blurred)
            encodeEffectFragment("ollin_fx_bloom_combine", inputs: [input, blurred], output: output,
                                 params: [f(intensity, 0, 0, 0)], into: cb)
            return output

        case let .colorGrade(brightness, contrast, saturation, hue):
            return pass("ollin_fx_color_grade", [input], [f(brightness, contrast, saturation, hue)])
        case .invert(let amount):
            return pass("ollin_fx_invert", [input], [f(amount, 0, 0, 0)])
        case .posterize(let levels):
            return pass("ollin_fx_posterize", [input], [f(levels, 0, 0, 0)])
        case let .threshold(value, softness):
            return pass("ollin_fx_threshold", [input], [f(value, softness, 0, 0)])
        case .sepia(let amount):
            return pass("ollin_fx_sepia", [input], [f(amount, 0, 0, 0)])
        case let .duotone(dark, light, amount):
            return pass("ollin_fx_duotone", [input], [f(amount, 0, 0, 0), dark, light])
        case let .gradientMap(lut, amount):
            guard let lutTex = makeLUTTexture(lut) else { return nil }
            return pass("ollin_fx_gradient_map", [input, lutTex], [f(amount, 0, 0, 0)])

        case .edges(let intensity):
            return pass("ollin_fx_edges", [input], [SIMD4(texel.x, texel.y, Float(intensity), 0)])
        case .sharpen(let amount):
            return pass("ollin_fx_sharpen", [input], [SIMD4(texel.x, texel.y, Float(amount), 0)])
        case let .vignette(amount, radius, softness):
            return pass("ollin_fx_vignette", [input], [SIMD4(Float(amount), Float(radius), Float(softness), aspect)])
        case .chromaticAberration(let amount):
            return pass("ollin_fx_chromatic", [input], [f(amount, 0, 0, 0)])
        case let .halftone(scale, angle):
            return pass("ollin_fx_halftone", [input], [SIMD4(Float(scale), Float(angle), aspect, 0)])
        case let .dither(levels, pixelSize):
            return pass("ollin_fx_dither", [input], [f(levels, pixelSize, 0, 0)])
        case let .grain(amount, seed):
            return pass("ollin_fx_grain", [input], [f(amount, seed, 0, 0)])
        case let .pixelate(size, channel, tint):
            let cols = max(1, (Double(width) / size).rounded())
            return pass("ollin_fx_pixelate", [input],
                        [SIMD4(Float(cols), aspect, channel.rawIndex, tint == nil ? 0 : 1),
                         tint ?? SIMD4<Float>(repeating: 0)])
        case let .lineScreen(scale, softness, angle, foreground, background):
            return pass("ollin_fx_linescreen", [input],
                        [SIMD4(Float(scale), Float(softness), Float(angle), aspect), foreground, background])
        }
    }

    /// Fill a generator's layer: one fullscreen fragment pass that reads no input,
    /// just its parameters. `aspect` lets the fragment keep cells square.
    private func encodeGenerator(_ generator: Generator, output: MTLTexture,
                                 width: Int, height: Int, into cb: MTLCommandBuffer) {
        let aspect = Float(width) / Float(max(1, height))
        switch generator.kind {
        case let .checkers(scale, fg, bg):
            encodeEffectFragment("ollin_gen_checkers", inputs: [], output: output,
                                 params: [SIMD4(Float(scale), aspect, 0, 0), fg, bg], into: cb)
        case let .gridLines(scale, weight, fg, bg):
            encodeEffectFragment("ollin_gen_grid", inputs: [], output: output,
                                 params: [SIMD4(Float(scale), Float(weight), aspect, 0), fg, bg], into: cb)
        case let .bars(scale, vertical, fg, bg):
            encodeEffectFragment("ollin_gen_bars", inputs: [], output: output,
                                 params: [SIMD4(Float(scale), vertical ? 1 : 0, aspect, 0), fg, bg], into: cb)
        case let .noise(scale, sharpness, fg, bg):
            encodeEffectFragment("ollin_gen_noise", inputs: [], output: output,
                                 params: [SIMD4(Float(scale), Float(sharpness), aspect, 0), fg, bg], into: cb)
        }
    }

    /// Encode one fullscreen filter (or generator) fragment pass: bind `inputs` as
    /// fragment textures 0… (empty for a generator, which reads nothing), the packed
    /// `params` rows as fragment buffer 0, and draw the present triangle into
    /// `output` (single-sample, replace). Shaders read `constant float4 *params`.
    private func encodeEffectFragment(_ fragment: String, inputs: [MTLTexture],
                                      output: MTLTexture, params: [SIMD4<Float>],
                                      into cb: MTLCommandBuffer) {
        guard let state = try? pipeline(.effect(fragment)) else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(state)
        for (i, tex) in inputs.enumerated() { enc.setFragmentTexture(tex, index: i) }
        enc.setFragmentSamplerState(imageSampler, index: 0)
        let p = params.isEmpty ? [SIMD4<Float>(repeating: 0)] : params
        p.withUnsafeBytes { enc.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    /// A small linear-float lookup texture (256×1) for `gradientMap`, uploaded from
    /// baked straight-alpha samples. `rgba32Float` so the `[SIMD4<Float>]` uploads
    /// verbatim; tiny, so allocated per use rather than pooled.
    private func makeLUTTexture(_ samples: [SIMD4<Float>]) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: samples.count, height: 1, mipmapped: false)
        desc.usage = .shaderRead
        desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        samples.withUnsafeBytes {
            tex.replace(region: MTLRegionMake2D(0, 0, samples.count, 1), mipmapLevel: 0,
                        withBytes: $0.baseAddress!, bytesPerRow: samples.count * MemoryLayout<SIMD4<Float>>.stride)
        }
        return tex
    }

    /// `fb`'s persistent ping-pong slot, allocating both textures (and clearing them
    /// to transparent, so the very first frame's `previous` reads clean) on first use,
    /// a size change, or after the address was reused by a different layer.
    private func feedbackSlot(for fb: Feedback, width: Int, height: Int,
                              into cb: MTLCommandBuffer) -> FeedbackSlot? {
        let id = ObjectIdentifier(fb)
        if let slot = feedbackSlots[id], slot.owner === fb, slot.w == width, slot.h == height {
            return slot
        }
        guard let a = makeFloatResolve(width: width, height: height),
              let b = makeFloatResolve(width: width, height: height) else { return nil }
        clearFloatTexture(a, into: cb)
        clearFloatTexture(b, into: cb)
        let slot = FeedbackSlot(a: a, b: b, w: width, h: height, owner: fb)
        feedbackSlots[id] = slot
        return slot
    }

    /// Clear `tex` to transparent with an empty render pass (a render target has no
    /// blit fill-to-color), so a freshly allocated feedback texture starts clean
    /// rather than with undefined contents.
    private func clearFloatTexture(_ tex: MTLTexture, into cb: MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = tex
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        cb.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
    }

    /// Acquire an MSAA + resolve pair for a geometry target. Pooled: reuse the slot
    /// for this frame-ring index (safe: the frame semaphore gates slot reuse).
    private func acquireTargetTextures(width: Int, height: Int, pooled: Bool) -> (msaa: MTLTexture, resolve: MTLTexture)? {
        guard pooled else {
            guard let msaa = makeFloatMSAA(width: width, height: height, storage: .memoryless),
                  let resolve = makeFloatResolve(width: width, height: height) else { return nil }
            return (msaa, resolve)
        }
        let slot = targetTexNext; targetTexNext += 1
        var pool = targetTexPool[frameIndex]
        if slot < pool.count, pool[slot].w == width, pool[slot].h == height {
            return (pool[slot].msaa, pool[slot].resolve)
        }
        guard let msaa = makeFloatMSAA(width: width, height: height, storage: .memoryless),
              let resolve = makeFloatResolve(width: width, height: height) else { return nil }
        let entry = (msaa, resolve, width, height)
        if slot < pool.count { pool[slot] = entry } else { pool.append(entry) }
        targetTexPool[frameIndex] = pool
        return (msaa, resolve)
    }

    /// Acquire a single-sample linear-float intermediate for a filter result.
    private func acquireFilterTexture(width: Int, height: Int, pooled: Bool) -> MTLTexture? {
        guard pooled else { return makeFilterTexture(width: width, height: height) }
        let slot = filterTexNext; filterTexNext += 1
        var pool = filterTexPool[frameIndex]
        if slot < pool.count, pool[slot].w == width, pool[slot].h == height { return pool[slot].tex }
        guard let tex = makeFilterTexture(width: width, height: height) else { return nil }
        let entry = (tex, width, height)
        if slot < pool.count { pool[slot] = entry } else { pool.append(entry) }
        filterTexPool[frameIndex] = pool
        return tex
    }

    /// A single-sample linear-float texture for an intermediate filter result:
    /// sampled, MPS-written, and fragment-rendered, so it carries all three usages.
    private func makeFilterTexture(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: linearFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }

    /// Upload `drawer`'s recorded geometry and issue its draws into `encoder`,
    /// one per batch in call order so triangles and SDF shapes composite
    /// front-to-back as the sketch drew them. Shared by the on-screen and
    /// off-screen (export) paths.
    private func encode(_ drawer: Drawer, viewport: SIMD2<Float>,
                        into encoder: MTLRenderCommandEncoder,
                        triangleBuffer: MTLBuffer?, sdfBuffer: MTLBuffer?,
                        imageBuffer: MTLBuffer?, glyphBuffer: MTLBuffer?,
                        pointBuffer: MTLBuffer?, meshBuffer: MTLBuffer?,
                        depthFormat: MTLPixelFormat?, shadowMap: MTLTexture? = nil,
                        shadowCube: MTLTexture? = nil,
                        shadowAccel: MTLAccelerationStructure? = nil,
                        target passTarget: RenderTarget? = nil) {
        let vertices = drawer.vertices
        let instances = drawer.sdfInstances
        let imageVertices = drawer.imageVertices
        let glyphVertices = drawer.glyphVertices
        let points = drawer.points
        let meshVertices = drawer.meshVertices
        let batches = drawer.batches
        guard !batches.isEmpty else { return }

        if !vertices.isEmpty, let triangleBuffer {
            vertices.withUnsafeBytes { raw in
                triangleBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
        }
        if !instances.isEmpty, let sdfBuffer {
            instances.withUnsafeBytes { raw in
                sdfBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
        }
        if !imageVertices.isEmpty, let imageBuffer {
            imageVertices.withUnsafeBytes { raw in
                imageBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
        }
        if !glyphVertices.isEmpty, let glyphBuffer {
            glyphVertices.withUnsafeBytes { raw in
                glyphBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
        }
        if !points.isEmpty, let pointBuffer {
            points.withUnsafeBytes { raw in
                pointBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
        }
        if !meshVertices.isEmpty, let meshBuffer {
            meshVertices.withUnsafeBytes { raw in
                meshBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
        }

        var uniforms = Uniforms(viewport: viewport, clipDepth: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

        // 3D camera constants for the points3D batches, bound once at index 2 —
        // distinct from the 2D Uniforms at index 1, so the 2D batches around a 3D
        // one are undisturbed. Built from the camera and the viewport's aspect.
        if let camera = drawer.camera3D {
            let aspect = viewport.y > 0 ? Double(viewport.x / viewport.y) : 1
            var u3 = Uniforms3D(view: camera.viewMatrix,
                                projection: camera.projectionMatrix(aspect: aspect),
                                viewport: viewport)
            encoder.setVertexBytes(&u3, length: MemoryLayout<Uniforms3D>.stride, index: 2)
        }

        // 3D mesh lighting (per-frame), bound to the mesh fragment per mesh batch
        // below. `enabled` is 0 when the sketch set no light, so the mesh fragment
        // keeps the byte-identical normal-as-color path.
        var lighting = drawer.makeLighting()
        // Shadows only apply when the shadow pass actually populated a map / structure
        // (the render/image paths); the accumulation/texture paths pass nil, so clear the
        // caster index there and bind the 1×1 / dummy stand-ins so the fragment never
        // reads them. A directional/spot caster populates the 2D map, a point caster the
        // cube — or, on a ray-tracing device, the acceleration structure.
        if shadowMap == nil && shadowCube == nil && shadowAccel == nil { lighting.shadowLight = -1 }
        // A ray-traced point caster: switch the fragment to the RT path (shadowKind 2) and
        // resolve the sketch's quality tier to a concrete ray count for this GPU.
        if shadowAccel != nil {
            lighting.shadowKind = 2
            lighting.shadowSamples = resolveShadowSamples(drawer.shadowQualitySetting)
        }
        let shadowTexture = shadowMap ?? ensureDummyShadowMap()
        let shadowCubeTexture = shadowCube ?? ensureDummyPointShadowMap()
        // When the mesh fragments are compiled with RT shadows, an acceleration structure
        // is always part of their signature, so bind the real one this frame or a dummy
        // that's never traced (the fragment only traces it when shadowKind == 2).
        let shadowAccelStructure = rayTracedShadows ? (shadowAccel ?? ensureDummyShadowAccel()) : nil

        // The strip must be bound whenever the SDF fragment runs (it references
        // the texture even for all-solid frames), so resolve it once per encode.
        let strip = gradientStripTexture(for: drawer.gradientRows)

        let vertexStride = MemoryLayout<OllinVertex>.stride
        let instanceStride = MemoryLayout<SDFInstance>.stride
        let imageStride = MemoryLayout<OllinImageVertex>.stride
        let pointStride = MemoryLayout<OllinPoint>.stride
        let meshStride = MemoryLayout<OllinMeshVertex>.stride
        for i in batches.indices {
            let batch = batches[i]
            let next = i + 1 < batches.count ? batches[i + 1] : nil
            // Each pass draws only its own batches: the main pass (passTarget nil)
            // skips target-tagged runs, and a target pass skips everything but its
            // own. `next` stays the globally-next batch so the buffer range is right.
            if batch.target !== passTarget { continue }
            // The pipeline for this batch's geometry kind, blend mode, *and* the
            // pass's depth format; built on first use of a combination. A mesh batch
            // selects its variant: wireframe (edges only) or textured (a material
            // texture). Skip the batch if it can't be built (never expected — same shaders).
            let meshWireframe = batch.kind == .mesh3D && batch.meshWireframe
            let meshMatcap = batch.kind == .mesh3D && !batch.meshWireframe && batch.matcap != nil
            let meshTextured = batch.kind == .mesh3D && !batch.meshWireframe && !meshMatcap && batch.material?.texture != nil
            guard let state = try? pipeline(.forBatch(batch.kind, batch.blendMode, depth: depthFormat,
                                                      textured: meshTextured, wireframe: meshWireframe,
                                                      matcap: meshMatcap)) else { continue }
            // In a depth pass (active camera): 3D batches z-test + write depth. A 2D
            // batch that opted into a depth (`depth(at:)`) does too — its constant
            // clip-z is fed to the 2D vertex shader so it occludes / is occluded by
            // 3D geometry — while a plain 2D batch leaves depth alone (clip-z 0) and
            // composites over in draw order. With no depth attachment the encoder
            // keeps its default state, so 2D-only frames are byte-identical to before.
            if depthFormat != nil {
                // 3D splats, a depth-scene backdrop, and any depth-placed 2D batch
                // z-test + write; a plain 2D batch leaves depth alone. The depth
                // scene and 3D batches set their own clip-z (a fragment SV_Depth and
                // the camera projection), so only plain 2D batches feed `clipDepth`.
                let wantsDepth = batch.kind == .points3D || batch.kind == .mesh3D
                    || batch.kind == .depthScene || batch.depth != nil
                encoder.setDepthStencilState(wantsDepth ? depthTestState : noDepthState)
                if batch.kind != .points3D && batch.kind != .mesh3D && batch.kind != .depthScene {
                    uniforms.clipDepth = batch.depth ?? 0
                    encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                }
            }
            switch batch.kind {
            case .triangles, .fringe:   // .fringe shares the triangle vertex buffer; only the pipeline differs (coverage rides in `aa.x`)
                let end = next?.vertexStart ?? vertices.count
                let count = end - batch.vertexStart
                guard count > 0, let triangleBuffer else { continue }
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(triangleBuffer, offset: batch.vertexStart * vertexStride, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
            case .sdf:
                let end = next?.instanceStart ?? instances.count
                let count = end - batch.instanceStart
                guard count > 0, let sdfBuffer else { continue }
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(sdfBuffer, offset: batch.instanceStart * instanceStride, index: 0)
                // Rebind per batch — an image/glyph batch in between binds its own
                // texture at the same index.
                encoder.setFragmentTexture(strip, index: 0)
                encoder.setFragmentSamplerState(imageSampler, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: count)
            case .image:
                let end = next?.imageStart ?? imageVertices.count
                let count = end - batch.imageStart
                guard count > 0, let imageBuffer, let source = batch.image,
                      let texture = source.texture(for: device) else { continue }
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(imageBuffer, offset: batch.imageStart * imageStride, index: 0)
                encoder.setFragmentTexture(texture, index: 0)
                encoder.setFragmentSamplerState(imageSampler, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
            case .glyphAtlas:
                let end = next?.glyphStart ?? glyphVertices.count
                let count = end - batch.glyphStart
                guard count > 0, let glyphBuffer, let atlas = batch.atlas,
                      let texture = atlas.texture(for: device) else { continue }
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(glyphBuffer, offset: batch.glyphStart * imageStride, index: 0)
                encoder.setFragmentTexture(texture, index: 0)
                encoder.setFragmentSamplerState(imageSampler, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
            case .particles:
                // GPU-resident particle buffer (written by a compute dispatch this
                // frame), drawn as one instanced disc per particle. Uniforms are
                // already bound at index 1; the particle struct is read at index 0.
                guard batch.particleCount > 0,
                      let buffer = batch.particleBuffer?.metalBuffer(for: device) else { continue }
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6,
                                       instanceCount: batch.particleCount)
            case .points3D:
                // 3D point-cloud splats: one instanced camera-facing quad per point,
                // projected by the camera constants bound at index 2 above. Each draw
                // is a run in the per-frame `points` array (count from the next
                // batch's start), like the SDF/triangle paths.
                let end = next?.pointStart ?? points.count
                let count = end - batch.pointStart
                guard count > 0, let pointBuffer, drawer.camera3D != nil else { continue }
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(pointBuffer, offset: batch.pointStart * pointStride, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: count)
            case .mesh3D:
                // Solid 3D mesh: a flat triangle list (indices already expanded), drawn
                // through the camera constants bound at index 2. Depth-tested + writing
                // (state set above), so meshes occlude each other and the point clouds
                // / depth scene in the same pass.
                let end = next?.meshStart ?? meshVertices.count
                let count = end - batch.meshStart
                guard count > 0, let meshBuffer, drawer.camera3D != nil else { continue }
                // A textured or matcap mesh needs its texture at fragment index 0; if it
                // can't be built, skip rather than draw against the wrong pipeline.
                if meshTextured {
                    guard let texture = batch.material?.texture?.texture(for: device) else { continue }
                    encoder.setFragmentTexture(texture, index: 0)
                    encoder.setFragmentSamplerState(imageSampler, index: 0)
                } else if meshMatcap {
                    guard let texture = batch.matcap?.texture(for: device) else { continue }
                    encoder.setFragmentTexture(texture, index: 0)
                    encoder.setFragmentSamplerState(imageSampler, index: 0)
                }
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(meshBuffer, offset: batch.meshStart * meshStride, index: 0)
                // Lighting, the shadow map, and the material finish feed only the lit
                // solid/textured fragments — the wireframe and matcap pipelines declare
                // none of them (matcap bakes its lighting into the texture).
                if !meshWireframe && !meshMatcap {
                    // Shadow maps at fragment textures 1 (2D, directional/spot) and 2
                    // (cube, point): the real map when that caster is active, a 1×1 dummy
                    // otherwise (`lighting.shadowLight`/`shadowKind` gate the sampling).
                    // Both share the one comparison sampler (lessEqual hardware PCF).
                    encoder.setFragmentTexture(shadowTexture, index: 1)
                    encoder.setFragmentTexture(shadowCubeTexture, index: 2)
                    // 2D map: comparison sampler (hardware PCF). Cube: plain sampler (it
                    // stores linear distance, read with `.sample`, manual PCF in-shader).
                    if let shadowSampler { encoder.setFragmentSamplerState(shadowSampler, index: 1) }
                    if let shadowCubeSampler { encoder.setFragmentSamplerState(shadowCubeSampler, index: 2) }
                    encoder.setFragmentBytes(&lighting, length: MemoryLayout<OllinLighting>.stride, index: 0)
                    // The surface finish (shading model + Blinn-Phong/rim/subsurface/
                    // iridescence) is one uniform bound per batch.
                    var finish = batch.finish
                    encoder.setFragmentBytes(&finish, length: MemoryLayout<OllinMaterial>.stride, index: 1)
                    // Ray-traced point shadows: the fragment traces this acceleration
                    // structure at buffer 3 (a dummy when shadowKind != 2, never traced).
                    if let accel = shadowAccelStructure {
                        encoder.useResource(accel, usage: .read, stages: .fragment)
                        encoder.setFragmentAccelerationStructure(accel, bufferIndex: 3)
                    }
                }
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
            case .depthScene:
                // A backdrop quad (in `imageVertices`, like an image) whose fragment
                // also writes per-pixel depth from the depth map: color at texture 0,
                // depth at texture 1. The depth-test state (set above) writes the
                // fragment's SV_Depth so 2D drawn after composites against it.
                let end = next?.imageStart ?? imageVertices.count
                let count = end - batch.imageStart
                // Depth comes from either a metric float map (meters) or the
                // normalized gray map; the fragment branches on the quad's tint.a.
                let depthTex = batch.metricDepth?.texture(for: device)
                    ?? batch.depthImage?.texture(for: device)
                guard count > 0, let imageBuffer, let color = batch.image,
                      let colorTex = color.texture(for: device), let depthTex
                else { continue }
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(imageBuffer, offset: batch.imageStart * imageStride, index: 0)
                encoder.setFragmentTexture(colorTex, index: 0)
                encoder.setFragmentTexture(depthTex, index: 1)
                encoder.setFragmentSamplerState(imageSampler, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
            }
        }
    }

    /// Encode the frame's recorded compute dispatches into one compute encoder,
    /// ahead of the geometry render pass in the *same* command buffer — so a
    /// simulation step and the draw that reads its output stay ordered within the
    /// frame (Metal's intra-command-buffer hazard tracking inserts the dependency).
    /// The standard `OllinComputeUniforms` are bound at index 10 (with this
    /// dispatch's thread count as `particleCount`) and the custom params, if any, at
    /// index 11; the kernel's own buffers bind at 0…9. Threadgroup size comes from
    /// the pipeline, dispatched non-uniformly so the count needn't be a multiple.
    private func encodeCompute(_ drawer: Drawer, into commandBuffer: MTLCommandBuffer) {
        guard !drawer.dispatches.isEmpty,
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        for dispatch in drawer.dispatches {
            guard dispatch.threadCount > 0,
                  let state = try? computePipeline(for: dispatch.kernel) else { continue }
            encoder.setComputePipelineState(state)
            for (index, bindable) in dispatch.buffers.enumerated() {
                encoder.setBuffer(bindable?.metalBuffer(for: device), offset: 0, index: index)
            }
            for (index, bindable) in dispatch.textures.enumerated() {
                encoder.setTexture(bindable?.metalTexture(for: device), index: index)
            }
            var uniforms = drawer.computeUniforms
            uniforms.particleCount = UInt32(dispatch.threadCount)
            encoder.setBytes(&uniforms, length: MemoryLayout<OllinComputeUniforms>.stride, index: 10)
            if !dispatch.params.isEmpty {
                dispatch.params.withUnsafeBytes {
                    encoder.setBytes($0.baseAddress!, length: $0.count, index: 11)
                }
            }
            // Threadgroup shaped to the grid: the execution width along x, the rest
            // of the budget along y. A 1-D buffer dispatch (height 1) collapses to
            // the old `width × 1`; a 2-D texture dispatch tiles in both axes.
            // `dispatchThreads` handles a grid that isn't a multiple of the group.
            let tew = state.threadExecutionWidth
            let groupWidth = max(1, min(dispatch.gridWidth, tew))
            let groupHeight = max(1, min(dispatch.gridHeight, state.maxTotalThreadsPerThreadgroup / tew))
            encoder.dispatchThreads(
                MTLSize(width: dispatch.gridWidth, height: dispatch.gridHeight, depth: 1),
                threadsPerThreadgroup: MTLSize(width: groupWidth, height: groupHeight, depth: 1))
        }
        encoder.endEncoding()
    }

    /// Execute this frame's recorded compute dispatches *without* rendering geometry —
    /// for headless drivers advancing a stateful sim (a `Simulation`, a ping-pong
    /// `ComputeTexture`) through frames they don't capture: the frames before the one
    /// being grabbed, and `--skip` warmup. The live window and a captured frame run
    /// the steps as part of their full render, but an *un*-captured frame otherwise
    /// records its dispatches and drops them, so the sim never evolves on the GPU.
    /// This runs just the compute, in its own command buffer (no geometry pass, no
    /// readback), so the GPU-resident state carries forward to the next frame at a
    /// fraction of a full render's cost. A no-op when nothing was recorded.
    func stepCompute(_ drawer: Drawer) {
        guard !drawer.dispatches.isEmpty,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        encodeCompute(drawer, into: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    /// The gradient strip texture holding `rows` (one baked ramp per row),
    /// reused while the rows are unchanged and rebuilt — as a fresh texture, see
    /// `gradientStrip` — when they differ. With no gradients in the frame a
    /// 1-row placeholder keeps the SDF fragment's texture argument valid.
    private func gradientStripTexture(for rows: [[UInt8]]) -> MTLTexture? {
        if let existing = gradientStrip, rows == gradientStripRows { return existing }

        let height = max(rows.count, 1)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb, width: BakedGradient.width,
            height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        let bytesPerRow = BakedGradient.width * 4
        var flat: [UInt8] = []
        flat.reserveCapacity(bytesPerRow * height)
        for row in rows { flat.append(contentsOf: row) }
        if rows.isEmpty { flat = [UInt8](repeating: 0, count: bytesPerRow) }
        flat.withUnsafeBytes { raw in
            texture.replace(region: MTLRegionMake2D(0, 0, BakedGradient.width, height),
                            mipmapLevel: 0, withBytes: raw.baseAddress!,
                            bytesPerRow: bytesPerRow)
        }
        gradientStrip = texture
        gradientStripRows = rows
        return texture
    }

    // MARK: Render targets

    /// A linear-float MSAA color target. `storageMode` is `.memoryless` for the
    /// transient per-frame targets (the samples live only in tile memory, never
    /// backed by DRAM, since the frame clears each time) and `.private` for the
    /// accumulation target (its samples must persist across frames).
    private func makeFloatMSAA(width: Int, height: Int, storage: MTLStorageMode) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: linearFormat, width: width, height: height, mipmapped: false)
        desc.textureType = .type2DMultisample
        desc.sampleCount = sampleCount
        desc.usage = .renderTarget
        desc.storageMode = storage
        return device.makeTexture(descriptor: desc)
    }

    /// A multisample depth target for a 3D pass, matching the geometry MSAA target's
    /// size and sample count. Memoryless — depth is consumed within the pass
    /// (storeAction `.dontCare`), never backed by DRAM.
    private func makeDepthMSAA(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: depthPixelFormat, width: width, height: height, mipmapped: false)
        desc.textureType = .type2DMultisample
        desc.sampleCount = sampleCount
        desc.usage = .renderTarget
        desc.storageMode = .memoryless
        return device.makeTexture(descriptor: desc)
    }

    /// The shadow map: a square single-sample `.private` depth texture the shadow
    /// pass renders into and the lit mesh fragment samples. Allocated lazily on the
    /// first shadow-casting frame (a sketch that never casts shadows allocates none),
    /// then reused.
    private func ensureShadowMap() -> MTLTexture? {
        if let m = shadowMap { return m }
        let n = MetalRenderer.shadowMapResolution
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: depthPixelFormat, width: n, height: n, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        shadowMap = device.makeTexture(descriptor: desc)
        return shadowMap
    }

    /// A 1×1 depth texture bound to the mesh fragment's shadow slot when shadows are
    /// off, so its declared `depth2d` argument is always satisfied (the fragment only
    /// samples it when `shadowLight >= 0`). Cleared once on creation so it's never
    /// read uninitialized.
    private func ensureDummyShadowMap() -> MTLTexture? {
        if let m = dummyShadowMap { return m }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: depthPixelFormat, width: 1, height: 1, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }
        // Clear it (a depth-only pass) so the contents are defined.
        if let cb = commandQueue.makeCommandBuffer() {
            let pass = MTLRenderPassDescriptor()
            pass.depthAttachment.texture = texture
            pass.depthAttachment.loadAction = .clear
            pass.depthAttachment.clearDepth = 1.0
            pass.depthAttachment.storeAction = .store
            cb.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
            cb.commit()
        }
        dummyShadowMap = texture
        return dummyShadowMap
    }

    /// The omnidirectional (point) shadow map, a `.private` **`rg32Float` cube** for
    /// mid-point shadow mapping: R holds the nearest occluder's distance to the light
    /// (normalized by the far plane), G the farthest, per direction. The lit fragment
    /// shadows where the receiver's distance exceeds the midpoint `(R+G)/2`. Allocated
    /// lazily on the first point-casting frame, then reused.
    static let pointShadowColorFormat: MTLPixelFormat = .rg32Float
    private func ensurePointShadowMap() -> MTLTexture? {
        if let m = pointShadowMap { return m }
        let n = MetalRenderer.pointShadowMapResolution
        let desc = MTLTextureDescriptor.textureCubeDescriptor(
            pixelFormat: MetalRenderer.pointShadowColorFormat, size: n, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        pointShadowMap = device.makeTexture(descriptor: desc)
        return pointShadowMap
    }

    /// A 1×1 `rg32Float` cube bound to the mesh fragment's cube-shadow slot when no point
    /// caster is active, so its declared `texturecube` argument is always satisfied (the
    /// fragment only samples it when `shadowKind == 1`). Cleared to (1, 0) once on
    /// creation (all six faces in one layered pass) so it's never read uninitialized.
    private func ensureDummyPointShadowMap() -> MTLTexture? {
        if let m = dummyPointShadowMap { return m }
        let desc = MTLTextureDescriptor.textureCubeDescriptor(
            pixelFormat: MetalRenderer.pointShadowColorFormat, size: 1, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }
        if let cb = commandQueue.makeCommandBuffer() {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 0, blue: 0, alpha: 0)
            pass.colorAttachments[0].storeAction = .store
            pass.renderTargetArrayLength = 6      // clear all six faces at once
            cb.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
            cb.commit()
        }
        dummyPointShadowMap = texture
        return dummyPointShadowMap
    }

    /// The shadow map(s) a frame produced: the 2D map for a directional/spot caster, or
    /// the cube map for a point caster (at most one is set; both nil = no shadow).
    struct ShadowMaps {
        var twoD: MTLTexture?
        var cube: MTLTexture?
        /// The ray-traced point caster's acceleration structure (RT devices), in place
        /// of the cube; the lit mesh fragment traces a visibility ray against it.
        var accel: MTLAccelerationStructure?
    }

    /// Render the scene's mesh geometry into the shadow map from the casting light's
    /// point of view (a depth-only pass), so the lit mesh fragment can compare each
    /// receiver against it. Encoded *before* the geometry pass in the same command
    /// buffer, so Metal's intra-buffer hazard tracking orders the geometry pass after it.
    /// Returns the populated map (2D for a directional/spot caster, a cube for a point
    /// caster), or empty when this frame casts no shadow (no `castShadows()`, no eligible
    /// light, or no meshes), in which case the caller shades unshadowed. Uses the same
    /// `meshBuffer` the geometry pass will use (it uploads the vertices here; the
    /// geometry pass re-copies the same bytes).
    private func encodeShadowPass(_ drawer: Drawer, into commandBuffer: MTLCommandBuffer,
                                  meshBuffer: MTLBuffer?) -> ShadowMaps {
        let lighting = drawer.makeLighting()
        let meshVertices = drawer.meshVertices
        guard lighting.shadowLight >= 0, lighting.enabled != 0, !meshVertices.isEmpty,
              let meshBuffer else { return ShadowMaps() }

        meshVertices.withUnsafeBytes { raw in
            meshBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }

        // A point caster: ray-trace it on a capable device (exact, no cube/depth-compare
        // artifacts), else render the omnidirectional mid-point cube. Directional/spot
        // always use the 2D map below (untouched by the RT path).
        if lighting.shadowKind == 1 {
            if rayTracedShadows,
               let accel = buildShadowAccel(drawer, into: commandBuffer, meshBuffer: meshBuffer) {
                return ShadowMaps(accel: accel)
            }
            let cube = encodePointShadowPass(drawer, lighting: lighting,
                                             into: commandBuffer, meshBuffer: meshBuffer)
            return ShadowMaps(cube: cube)
        }

        guard let shadowMap = ensureShadowMap(),
              let shadowPipeline = try? pipeline(.meshShadow) else { return ShadowMaps() }
        let pass = MTLRenderPassDescriptor()
        pass.depthAttachment.texture = shadowMap
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1.0
        pass.depthAttachment.storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return ShadowMaps() }
        encoder.setRenderPipelineState(shadowPipeline)
        encoder.setDepthStencilState(depthTestState)
        // Slope-scaled depth bias on the stored depth keeps self-shadowing acne off
        // (paired with the fragment's normal-offset + constant bias).
        encoder.setDepthBias(0.0015, slopeScale: 2.0, clamp: 0.01)
        var lightVP = lighting.lightViewProjection
        encoder.setVertexBytes(&lightVP, length: MemoryLayout<simd_float4x4>.stride, index: 2)
        drawShadowCasters(drawer, encoder: encoder, meshBuffer: meshBuffer, instanceCount: 1)
        encoder.endEncoding()
        return ShadowMaps(twoD: shadowMap)
    }

    /// The omnidirectional (point) shadow pass: render the scene into all six cube faces
    /// in **one** layered pass (the geometry instanced six times, each instance routed to
    /// a face by `render_target_array_index`). The fragment writes each occluder's linear
    /// distance to the light (normalized by the far plane) as the stored value, so the
    /// lit mesh fragment later compares plain world-space distances. The light position
    /// and far plane come from the lighting uniform. Returns the populated cube.
    private func encodePointShadowPass(_ drawer: Drawer, lighting: OllinLighting,
                                       into commandBuffer: MTLCommandBuffer,
                                       meshBuffer: MTLBuffer) -> MTLTexture? {
        guard let cube = ensurePointShadowMap(),
              let minPipeline = try? pipeline(.meshPointShadowMin),
              let maxPipeline = try? pipeline(.meshPointShadowMax) else { return nil }

        // The casting light's world position from the uniform's fixed-size light array.
        let caster = Int(lighting.shadowLight)
        var lightPos = SIMD3<Float>(0, 0, 0)
        withUnsafePointer(to: lighting.lights) { ptr in
            ptr.withMemoryRebound(to: OllinLight.self, capacity: Int(OLLIN_MAX_LIGHTS)) { buf in
                let p = buf[caster].position
                lightPos = SIMD3<Float>(p.x, p.y, p.z)
            }
        }
        // The far plane is carried directly (`shadowDepthA`); the fragment normalizes the
        // stored linear distance by it. The face perspective near/far only frame the
        // rasterization (the stored value is the fragment's own linear distance), so a
        // small near and that far suffice.
        let far = lighting.shadowDepthA
        let near = max(Float(0.05), far * 0.02)
        let proj = Camera3D.perspective(fovY: .pi / 2, aspect: 1, near: near, far: far)
        // The six cube faces (forward axis, up), in Metal's +X/−X/+Y/−Y/+Z/−Z order.
        let faces: [(SIMD3<Float>, SIMD3<Float>)] = [
            (SIMD3(1,  0,  0), SIMD3(0, -1,  0)),
            (SIMD3(-1,  0,  0), SIMD3(0, -1,  0)),
            (SIMD3(0,  1,  0), SIMD3(0,  0,  1)),
            (SIMD3(0, -1,  0), SIMD3(0,  0, -1)),
            (SIMD3(0,  0,  1), SIMD3(0, -1,  0)),
            (SIMD3(0,  0, -1), SIMD3(0, -1,  0)),
        ]
        let faceVP = faces.map { proj * Camera3D.lookAt(eye: lightPos, center: lightPos + $0.0, up: $0.1) }

        // Mid-point shadow mapping: clear R = 1 (far, for the MIN pass) and G = 0 (near,
        // for the MAX pass), then make two draws of the scene with NO culling — the MIN
        // pass fills R with the nearest occluder distance per direction, the MAX pass
        // fills G with the farthest. The receiver shadows past the midpoint (R+G)/2, so a
        // surface compares against a point *inside* the occluder: no self-shadow acne on
        // edge-on faces, and no contact leak, without any face culling.
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = cube
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        pass.renderTargetArrayLength = 6
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        faceVP.withUnsafeBytes { encoder.setVertexBytes($0.baseAddress!, length: $0.count, index: 2) }
        var lightPosFar = SIMD4<Float>(lightPos.x, lightPos.y, lightPos.z, far)
        encoder.setFragmentBytes(&lightPosFar, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        encoder.setRenderPipelineState(minPipeline)   // nearest -> R
        drawShadowCasters(drawer, encoder: encoder, meshBuffer: meshBuffer, instanceCount: 6)
        encoder.setRenderPipelineState(maxPipeline)   // farthest -> G
        drawShadowCasters(drawer, encoder: encoder, meshBuffer: meshBuffer, instanceCount: 6)
        encoder.endEncoding()
        return cube
    }

    /// Resolve the sketch's soft-shadow quality intent to a concrete ray count for this GPU.
    /// A `Quality` tier scales with the hardware (a dedicated-RT GPU affords ~2× the rays of a
    /// software-RT one at the same tier, so better hardware lifts the default quality on its
    /// own); an absolute count passes through unchanged. The defaults are tuned so `.medium`
    /// holds 60fps on each tier (4 rays in software, 8 with hardware RT).
    private func resolveShadowSamples(_ setting: ShadowQualitySetting) -> Int32 {
        switch setting {
        case .absolute(let n):
            return Int32(n)
        case .tier(let quality):
            // Software RT (M1/M2) values are measured: `.default` = 4 holds 60fps. A
            // dedicated-RT GPU gets 4× at each tier (a placeholder until a per-GPU
            // benchmark — Scripts/benchmark-shadows — tunes real numbers per machine).
            let hw = hasHardwareRayTracing
            switch quality {
            case .performance: return hw ? 8 : 2
            case .default:     return hw ? 16 : 4
            case .detail:      return hw ? 32 : 8
            }
        }
    }

    /// Build (in place) the per-frame primitive acceleration structure over the shadow
    /// casters for a ray-traced point light — one geometry descriptor per solid/textured
    /// mesh batch (wireframe doesn't cast), reading world-space positions straight from
    /// the `meshBuffer` the geometry pass uses (position is the first field of
    /// `OllinMeshVertex`, so a `.float3` read at the vertex stride lands on it). Encoded
    /// ahead of the geometry pass in the same command buffer, so Metal orders build →
    /// trace. The structure + scratch grow in place only when the scene outgrows them.
    /// Returns nil when there's nothing to cast (the caller then falls back / unshadows).
    private func buildShadowAccel(_ drawer: Drawer, into commandBuffer: MTLCommandBuffer,
                                  meshBuffer: MTLBuffer) -> MTLAccelerationStructure? {
        let meshStride = MemoryLayout<OllinMeshVertex>.stride
        let meshVertices = drawer.meshVertices
        let batches = drawer.batches
        // Coalesce maximal runs of contiguous caster batches into one geometry descriptor
        // each (a non-casting batch — wireframe, or a non-mesh kind — breaks the run). The
        // caster vertices of a run are contiguous in `meshBuffer`, so one descriptor covers
        // them; fewer descriptors means a cheaper structure build (its per-geometry overhead
        // dominates at creative-coding triangle counts). A fully solid scene becomes one.
        var geometries: [MTLAccelerationStructureTriangleGeometryDescriptor] = []
        var runStart = -1, runEnd = 0
        func flushRun() {
            guard runStart >= 0, runEnd - runStart >= 3 else { runStart = -1; return }
            let geo = MTLAccelerationStructureTriangleGeometryDescriptor()
            geo.vertexBuffer = meshBuffer
            geo.vertexBufferOffset = runStart * meshStride
            geo.vertexStride = meshStride
            geo.vertexFormat = .float3        // position.xyz from each vertex (field offset 0)
            geo.triangleCount = (runEnd - runStart) / 3
            geo.opaque = true                 // load-bearing: else triangle hits never commit
            geometries.append(geo)
            runStart = -1
        }
        for i in batches.indices {
            let batch = batches[i]
            let isCaster = batch.kind == .mesh3D && !batch.meshWireframe
            let end = i + 1 < batches.count ? batches[i + 1].meshStart : meshVertices.count
            if isCaster {
                if runStart < 0 { runStart = batch.meshStart }
                runEnd = end
            } else {
                flushRun()
            }
        }
        flushRun()
        guard !geometries.isEmpty else { return nil }

        // A plain (non-refittable) build: a refittable structure trades traversal speed for
        // the cheaper refit, and on a software-ray-tracing GPU (no RT hardware, e.g. M1/M2)
        // the per-ray traversal — millions of rays — dwarfs the per-frame build, so the
        // faster-to-traverse tree wins. Rebuild each frame; grow the structure in place only
        // when the scene outgrows it.
        let desc = MTLPrimitiveAccelerationStructureDescriptor()
        desc.geometryDescriptors = geometries
        let sizes = device.accelerationStructureSizes(descriptor: desc)
        if shadowAccel == nil || shadowAccelCapacity < sizes.accelerationStructureSize {
            shadowAccel = device.makeAccelerationStructure(size: sizes.accelerationStructureSize)
            shadowAccelCapacity = sizes.accelerationStructureSize
        }
        if (shadowAccelScratch?.length ?? 0) < sizes.buildScratchBufferSize {
            shadowAccelScratch = device.makeBuffer(length: max(1, sizes.buildScratchBufferSize),
                                                   options: .storageModePrivate)
        }
        guard let accel = shadowAccel, let scratch = shadowAccelScratch,
              let enc = commandBuffer.makeAccelerationStructureCommandEncoder() else { return nil }
        enc.build(accelerationStructure: accel, descriptor: desc,
                  scratchBuffer: scratch, scratchBufferOffset: 0)
        enc.endEncoding()
        return accel
    }

    /// A 1-triangle acceleration structure bound to the lit mesh fragment whenever no
    /// ray-traced point shadow is active this frame, so the fragment's declared
    /// `primitive_acceleration_structure` argument is always satisfied (it only traces
    /// when `shadowKind == 2`). Built once, far from any scene so it never matters.
    private func ensureDummyShadowAccel() -> MTLAccelerationStructure? {
        if let a = dummyShadowAccel { return a }
        var verts: [SIMD3<Float>] = [SIMD3(1e6, 1e6, 1e6), SIMD3(1e6 + 1, 1e6, 1e6),
                                     SIMD3(1e6, 1e6 + 1, 1e6)]
        let vbuf = device.makeBuffer(bytes: &verts, length: MemoryLayout<SIMD3<Float>>.stride * 3,
                                     options: .storageModeShared)
        let geo = MTLAccelerationStructureTriangleGeometryDescriptor()
        geo.vertexBuffer = vbuf
        geo.vertexStride = MemoryLayout<SIMD3<Float>>.stride
        geo.vertexFormat = .float3
        geo.triangleCount = 1
        let desc = MTLPrimitiveAccelerationStructureDescriptor()
        desc.geometryDescriptors = [geo]
        let sizes = device.accelerationStructureSizes(descriptor: desc)
        guard let accel = device.makeAccelerationStructure(size: sizes.accelerationStructureSize),
              let scratch = device.makeBuffer(length: max(1, sizes.buildScratchBufferSize),
                                              options: .storageModePrivate),
              let cb = commandQueue.makeCommandBuffer(),
              let enc = cb.makeAccelerationStructureCommandEncoder() else { return nil }
        enc.build(accelerationStructure: accel, descriptor: desc,
                  scratchBuffer: scratch, scratchBufferOffset: 0)
        enc.endEncoding(); cb.commit(); cb.waitUntilCompleted()
        dummyShadowAccel = accel
        return dummyShadowAccel
    }

    /// Draw every shadow-casting mesh batch into the active shadow encoder. Solid and
    /// textured meshes cast; wireframe (see-through edges) does not. `instanceCount` is
    /// 1 for the 2D pass and 6 for the layered cube pass (one instance per face).
    private func drawShadowCasters(_ drawer: Drawer, encoder: MTLRenderCommandEncoder,
                                   meshBuffer: MTLBuffer, instanceCount: Int) {
        let meshStride = MemoryLayout<OllinMeshVertex>.stride
        let meshVertices = drawer.meshVertices
        let batches = drawer.batches
        for i in batches.indices {
            let batch = batches[i]
            guard batch.kind == .mesh3D, !batch.meshWireframe else { continue }
            let next = i + 1 < batches.count ? batches[i + 1] : nil
            let end = next?.meshStart ?? meshVertices.count
            let count = end - batch.meshStart
            guard count > 0 else { continue }
            encoder.setVertexBuffer(meshBuffer, offset: batch.meshStart * meshStride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0,
                                   vertexCount: count, instanceCount: instanceCount)
        }
    }

    /// The single-sample linear-float resolve target: the MSAA resolve destination
    /// (`.renderTarget`) that the present pass then samples (`.shaderRead`).
    private func makeFloatResolve(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: linearFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }

    /// A single-sample sRGB display texture: the present pass's tone-mapped output,
    /// for the off-screen paths (export read-back, Syphon/grab hand-off).
    /// `.pixelFormatView` lets a consumer (Syphon) reinterpret its sRGB bytes.
    private func makeDisplayTexture(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead, .pixelFormatView]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }

    /// A render-pass descriptor that tone-maps the resolved float frame into
    /// `destination` (the drawable or a display texture). The present pass
    /// overwrites every pixel, so the load action doesn't matter.
    private func presentPass(into destination: MTLTexture) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = destination
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        return pass
    }

    /// Encode the final tone-map pass: a fullscreen triangle sampling `source` (the
    /// resolved linear-float frame) with the drawer's exposure + tone-map mode,
    /// dithering and sRGB-encoding to the bound display attachment. Shared by every
    /// output path (on-screen drawable, export texture, Syphon/grab texture).
    private func encodePresent(from source: MTLTexture, drawer: Drawer,
                               into encoder: MTLRenderCommandEncoder) {
        guard let state = try? pipeline(.present) else { return }
        encoder.setRenderPipelineState(state)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentSamplerState(imageSampler, index: 0)
        var present = OllinPresentUniforms(toneMapMode: drawer.toneMapMode.shaderIndex,
                                           exposure: Float(drawer.toneMapExposure))
        encoder.setFragmentBytes(&present, length: MemoryLayout<OllinPresentUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    // MARK: Pipelines

    /// Return the cached pipeline for `kind`, building and caching it on first
    /// use.
    private func pipeline(_ key: PipelineKey) throws -> MTLRenderPipelineState {
        if let existing = pipelines[key] { return existing }
        let built = try makePipeline(key)
        pipelines[key] = built
        return built
    }

    /// The compiled compute pipeline for `kernel`, built and cached on first use.
    /// Keyed by a hash of the *composed* source (prelude + shared types + user
    /// source) plus the entry name, so re-creating the same kernel value each frame
    /// is free, and the composed library is cached per source so several entries in
    /// one source share one compile.
    private func computePipeline(for kernel: ComputeKernel) throws -> MTLComputePipelineState {
        let composed = MetalRenderer.composeComputeSource(kernel.source)
        let hash = MetalRenderer.fnv1a(composed)
        let key = ComputeKey(sourceHash: hash, entry: kernel.entry)
        if let existing = computePipelines[key] { return existing }
        let lib: MTLLibrary
        if let cached = computeLibraries[hash] {
            lib = cached
        } else {
            lib = try device.makeLibrary(source: composed, options: nil)
            computeLibraries[hash] = lib
        }
        guard let function = lib.makeFunction(name: kernel.entry) else {
            throw RendererError.shaderFunctions
        }
        let state = try device.makeComputePipelineState(function: function)
        computePipelines[key] = state
        return state
    }

    /// Recompile the shader library from `source` and rebuild the cached
    /// pipelines against it — the renderer side of live shader reload. Builds the
    /// replacements *before* committing, so a compile/link error leaves the
    /// current library and pipelines untouched (it throws, and the caller reports
    /// it); a bad shader edit never blanks or crashes the running sketch.
    func reloadLibrary(source: String) throws {
        let newLibrary = try device.makeLibrary(
            source: MetalRenderer.composeShaderSource(source, rayTracing: rayTracedShadows), options: nil)
        let kinds = pipelines.isEmpty ? [PipelineKey.solid(.normal)] : Array(pipelines.keys)
        var rebuilt: [PipelineKey: MTLRenderPipelineState] = [:]
        for kind in kinds {
            rebuilt[kind] = try makePipeline(kind, using: newLibrary)
        }
        library = newLibrary           // commit atomically once all rebuilt
        pipelines = rebuilt
        // User compute kernels compile from their own source, but drop their caches
        // too so they rebuild against any edited shared types/prelude on next use.
        computePipelines.removeAll()
        computeLibraries.removeAll()
    }

    /// The single place pipeline descriptors are constructed. Add a `case` here
    /// when you add a `Pipeline` — e.g. instanced/SDF circles get their own
    /// vertex/fragment functions and (for instancing) a per-instance buffer.
    private func makePipeline(_ key: PipelineKey) throws -> MTLRenderPipelineState {
        try makePipeline(key, using: library)
    }

    private func makePipeline(_ key: PipelineKey, using library: MTLLibrary) throws -> MTLRenderPipelineState {
        // The present pass is the one pipeline that targets the display format at
        // single-sample with blending off; every other key is a geometry pipeline
        // into the float intermediate, fully described by its shader pair + blend +
        // alpha convention + depth format.
        if key.isPresent {
            return try makePresentPipeline(using: library)
        }
        if key.isEffect {
            return try makeEffectPipeline(key, using: library)
        }
        if key.isShadow {
            return try makeShadowPipeline(key, using: library)
        }
        return try makePipeline(vertex: key.vertex, fragment: key.fragment, using: library,
                                premultiplied: key.premultiplied, blend: key.blend,
                                depthFormat: key.depthFormat)
    }

    /// A shadow pass pipeline. Two shapes share this factory: the **2D map**
    /// (directional/spot, `ollin_mesh_shadow_vertex`) is depth-only — no fragment, no
    /// color attachment, the stored value is the rasterized depth. The **point cube**
    /// (`ollin_mesh_point_shadow_vertex`) is layered (all six faces via
    /// `render_target_array_index`, so it needs the triangle input topology) and writes
    /// the distance to the light into an `rg32Float` color cube for mid-point shadow
    /// mapping: `pointShadowOp` 1 MIN-blends into R (nearest), 2 MAX-blends into G
    /// (farthest), each writing only its channel. Single-sample either way.
    private func makeShadowPipeline(_ key: PipelineKey, using library: MTLLibrary) throws -> MTLRenderPipelineState {
        guard let vertexFunction = library.makeFunction(name: key.vertex) else {
            throw RendererError.shaderFunctions
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = key.fragment.isEmpty ? nil : library.makeFunction(name: key.fragment)
        descriptor.rasterSampleCount = 1
        if key.pointShadowOp != 0 {
            // Point cube: a color attachment (rg32Float), no depth. One channel per
            // pass, MIN/MAX-blended, so the two draws build nearest (R) + farthest (G).
            let color = descriptor.colorAttachments[0]!
            color.pixelFormat = MetalRenderer.pointShadowColorFormat
            color.isBlendingEnabled = true
            color.rgbBlendOperation = key.pointShadowOp == 1 ? .min : .max
            color.alphaBlendOperation = key.pointShadowOp == 1 ? .min : .max
            color.sourceRGBBlendFactor = .one
            color.destinationRGBBlendFactor = .one
            color.sourceAlphaBlendFactor = .one
            color.destinationAlphaBlendFactor = .one
            color.writeMask = key.pointShadowOp == 1 ? .red : .green
        } else {
            descriptor.depthAttachmentPixelFormat = depthPixelFormat
        }
        // The cube pass routes each instance to a cube face from the vertex stage, so
        // the pipeline must declare a layered (triangle) input topology.
        if key.vertex == "ollin_mesh_point_shadow_vertex" {
            descriptor.inputPrimitiveTopology = .triangle
        }
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// The final tone-map pass: a fullscreen triangle sampling the resolved
    /// linear-float frame and writing the sRGB drawable. Single-sample (it runs
    /// after the MSAA resolve), blending disabled (it overwrites the drawable),
    /// and it targets the display format rather than the float intermediate.
    private func makePresentPipeline(using library: MTLLibrary) throws -> MTLRenderPipelineState {
        guard let vertexFunction = library.makeFunction(name: "ollin_present_vertex"),
              let fragmentFunction = library.makeFunction(name: "ollin_present_fragment") else {
            throw RendererError.shaderFunctions
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.rasterSampleCount = 1
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// An effects filter pass: a fullscreen-triangle fragment writing the
    /// linear-float intermediate, single-sample (it runs between resolves, not in an
    /// MSAA pass) with blending off, since the filter shader produces the final texel.
    private func makeEffectPipeline(_ key: PipelineKey, using library: MTLLibrary) throws -> MTLRenderPipelineState {
        guard let vertexFunction = library.makeFunction(name: key.vertex),
              let fragmentFunction = library.makeFunction(name: key.fragment) else {
            throw RendererError.shaderFunctions
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.rasterSampleCount = 1
        descriptor.colorAttachments[0].pixelFormat = linearFormat
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// Build a render pipeline from the named vertex/fragment functions with the
    /// shared config: the view's MSAA sample count, the target pixel format, and
    /// the `blend` mode's factors (resolved against the fragment's alpha
    /// convention). `premultiplied` is true for premultiplied color (the image
    /// path), false for straight-alpha color (solid + SDF + glyph). The default
    /// `blend` (`.normal`) reproduces ordinary source-over compositing.
    private func makePipeline(vertex: String, fragment: String,
                              using library: MTLLibrary,
                              premultiplied: Bool = false,
                              blend: BlendMode = .normal,
                              depthFormat: MTLPixelFormat? = nil) throws -> MTLRenderPipelineState {
        guard let vertexFunction = library.makeFunction(name: vertex),
              let fragmentFunction = library.makeFunction(name: fragment) else {
            throw RendererError.shaderFunctions
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        // Must match the MTKView's MSAA sample count or pipeline creation fails.
        descriptor.rasterSampleCount = sampleCount
        // A depth-tested pass (an active 3D camera) needs the pipeline to declare
        // its depth format; 2D leaves it unset (.invalid), so 2D pipelines stay
        // byte-identical to before this descriptor migration.
        if let depthFormat {
            descriptor.depthAttachmentPixelFormat = depthFormat
        }

        let state = blend.blendState(premultiplied: premultiplied)
        let attachment = descriptor.colorAttachments[0]!
        // Geometry composites into the linear-float intermediate, not the drawable.
        attachment.pixelFormat = linearFormat
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = state.colorOperation
        attachment.alphaBlendOperation = state.alphaOperation
        attachment.sourceRGBBlendFactor = state.sourceColor
        attachment.sourceAlphaBlendFactor = state.sourceAlpha
        attachment.destinationRGBBlendFactor = state.destinationColor
        attachment.destinationAlphaBlendFactor = state.destinationAlpha

        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    // MARK: Helpers

    /// Return the ring's vertex buffer at `index`, large enough for `count`
    /// vertices, growing it (and rounding up) only when a frame needs more room.
    private func vertexBuffer(at index: Int, for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinVertex>.stride
        if let buffer = vertexBuffers[index], buffer.length >= needed {
            return buffer
        }
        // Over-allocate a little so steady-state frames stop reallocating.
        let capacity = needed + needed / 2
        vertexBuffers[index] = device.makeBuffer(length: capacity, options: .storageModeShared)
        return vertexBuffers[index]
    }

    /// The off-screen export buffer, grown on demand. Kept distinct from the
    /// on-screen ring so a headless render can't stomp a buffer an in-flight
    /// frame is still reading.
    private func exportVertexBuffer(for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinVertex>.stride
        if let buffer = exportBuffer, buffer.length >= needed { return buffer }
        exportBuffer = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return exportBuffer
    }

    /// Return the SDF instance ring buffer at `index`, large enough for `count`
    /// instances, grown on demand. Mirrors `vertexBuffer(at:for:)`.
    private func sdfBuffer(at index: Int, for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<SDFInstance>.stride
        if let buffer = sdfBuffers[index], buffer.length >= needed {
            return buffer
        }
        let capacity = needed + needed / 2
        sdfBuffers[index] = device.makeBuffer(length: capacity, options: .storageModeShared)
        return sdfBuffers[index]
    }

    /// The off-screen export buffer for SDF instances, grown on demand.
    private func exportSDFBuffer(for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<SDFInstance>.stride
        if let buffer = sdfExportBuffer, buffer.length >= needed { return buffer }
        sdfExportBuffer = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return sdfExportBuffer
    }

    /// Return the image-vertex ring buffer at `index`, grown on demand. Mirrors
    /// `vertexBuffer(at:for:)`.
    private func imageBuffer(at index: Int, for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinImageVertex>.stride
        if let buffer = imageBuffers[index], buffer.length >= needed {
            return buffer
        }
        let capacity = needed + needed / 2
        imageBuffers[index] = device.makeBuffer(length: capacity, options: .storageModeShared)
        return imageBuffers[index]
    }

    /// The off-screen export buffer for image vertices, grown on demand.
    private func exportImageBuffer(for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinImageVertex>.stride
        if let buffer = imageExportBuffer, buffer.length >= needed { return buffer }
        imageExportBuffer = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return imageExportBuffer
    }

    /// Return the glyph-vertex ring buffer at `index`, grown on demand. Mirrors
    /// `imageBuffer(at:for:)` (glyph quads reuse `OllinImageVertex`).
    private func glyphBuffer(at index: Int, for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinImageVertex>.stride
        if let buffer = glyphBuffers[index], buffer.length >= needed {
            return buffer
        }
        let capacity = needed + needed / 2
        glyphBuffers[index] = device.makeBuffer(length: capacity, options: .storageModeShared)
        return glyphBuffers[index]
    }

    /// The off-screen export buffer for glyph vertices, grown on demand.
    private func exportGlyphBuffer(for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinImageVertex>.stride
        if let buffer = glyphExportBuffer, buffer.length >= needed { return buffer }
        glyphExportBuffer = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return glyphExportBuffer
    }

    /// Return the point-cloud ring buffer at `index`, grown on demand. Mirrors
    /// `vertexBuffer(at:for:)`.
    private func pointBuffer(at index: Int, for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinPoint>.stride
        if let buffer = pointBuffers[index], buffer.length >= needed {
            return buffer
        }
        let capacity = needed + needed / 2
        pointBuffers[index] = device.makeBuffer(length: capacity, options: .storageModeShared)
        return pointBuffers[index]
    }

    /// The off-screen export buffer for point-cloud splats, grown on demand.
    private func exportPointBuffer(for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinPoint>.stride
        if let buffer = pointExportBuffer, buffer.length >= needed { return buffer }
        pointExportBuffer = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return pointExportBuffer
    }

    /// Return the solid-mesh ring buffer at `index`, grown on demand. Mirrors
    /// `pointBuffer(at:for:)`.
    private func meshBuffer(at index: Int, for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinMeshVertex>.stride
        if let buffer = meshBuffers[index], buffer.length >= needed {
            return buffer
        }
        let capacity = needed + needed / 2
        meshBuffers[index] = device.makeBuffer(length: capacity, options: .storageModeShared)
        return meshBuffers[index]
    }

    /// The off-screen export buffer for solid-mesh vertices, grown on demand.
    private func exportMeshBuffer(for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinMeshVertex>.stride
        if let buffer = meshExportBuffer, buffer.length >= needed { return buffer }
        meshExportBuffer = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return meshExportBuffer
    }

    /// Splice the shared CPU/GPU type header into shader source for runtime
    /// compilation. `makeLibrary(source:)` has no include search path, so the
    /// `#include "OllinShaderTypes.h"` directive in `ShaderCore.metal` (the first
    /// concatenated segment) can't be resolved the normal way; we replace it with
    /// the header's text (the header ships beside the segments as a resource). A
    /// precompiled metallib resolves the include at build time and skips this path.
    ///
    /// If the header resource is missing we leave the source untouched and let
    /// the compiler report the undefined types — louder than a silent fallback.
    static func composeShaderSource(_ source: String, rayTracing: Bool = false) -> String {
        // Gate the inline-RT mesh-shadow path on device capability (the symbol the
        // `#if OLLIN_RT_SHADOWS` blocks in Shader3D.metal read). A device without
        // render-stage ray tracing compiles it out entirely, so the cube path stays.
        let prefix = "#define OLLIN_RT_SHADOWS \(rayTracing ? 1 : 0)\n"
        guard let url = Bundle.module.url(forResource: "OllinShaderTypes", withExtension: "h"),
              let header = try? String(contentsOf: url, encoding: .utf8) else {
            return prefix + source
        }
        return prefix + source.replacingOccurrences(of: "#include \"OllinShaderTypes.h\"", with: header)
    }

    /// Build the full MSL source for a user compute kernel: the `metal_stdlib`
    /// preamble, the shared CPU↔GPU types (`OllinParticle`/`OllinComputeUniforms`),
    /// and the compute prelude (`OllinCompute.h` — hash/noise/curl/disc), then the
    /// user's source. So a kernel writes no `#include`s and can use those directly.
    /// Both headers ship beside the shaders as resources (the runtime compiler has
    /// no include search path, the same reason `composeShaderSource` splices).
    static func composeComputeSource(_ userSource: String) -> String {
        var source = "#include <metal_stdlib>\nusing namespace metal;\n"
        if let url = Bundle.module.url(forResource: "OllinShaderTypes", withExtension: "h"),
           let header = try? String(contentsOf: url, encoding: .utf8) {
            source += header + "\n"
        }
        if let url = Bundle.module.url(forResource: "OllinCompute", withExtension: "h"),
           let prelude = try? String(contentsOf: url, encoding: .utf8) {
            source += prelude + "\n"
        }
        return source + userSource
    }

    /// FNV-1a hash of a string's UTF-8, for the compute-pipeline cache key.
    /// (`Hasher` is per-process-seeded, so it can't key a stable cache; FNV is
    /// stable — the same lesson the model-tracker cache learned.)
    static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return hash
    }

    /// The shader source segments, in concatenation order. They're compiled as one
    /// library, so order matters: `ShaderCore` carries the preamble and the shared
    /// color/dither/hash helpers the rest depend on, so it goes first (Metal needs a
    /// declaration before its use). The single `Shaders.metal` split into these once
    /// it crossed ~2,000 lines; the renderer never assumes one file.
    static let shaderSourceNames = ["ShaderCore", "ShaderShapes", "Shader3D", "ShaderEffects"]

    /// Read and concatenate the shader segments from a filesystem `directory`, in
    /// `shaderSourceNames` order. This is the source live shader reload feeds back
    /// in (the `Bundle.module` copy is built, not the file being edited). `nil` if
    /// any segment is unreadable.
    static func concatenatedShaderSource(fromDirectory directory: String) -> String? {
        var parts: [String] = []
        for name in shaderSourceNames {
            let path = (directory as NSString).appendingPathComponent("\(name).metal")
            guard let part = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
            parts.append(part)
        }
        return parts.joined(separator: "\n")
    }

    /// Load the built-in shader library.
    ///
    /// SwiftPM's resource rule copies the `Shader*.metal` segments into
    /// `Bundle.module` as *source*; it does not produce a precompiled
    /// `default.metallib`. So the reliable path is to read those segments, splice
    /// the shared header, and compile at runtime. We still try a precompiled
    /// `default.metallib` first in case a future build step produces one.
    private static func loadLibrary(device: MTLDevice) throws -> MTLLibrary {
        let rt = device.supportsRaytracing && device.supportsRaytracingFromRender
        // A precompiled `default.metallib` is built without the device-conditional
        // `OLLIN_RT_SHADOWS` define (it can hold only one variant — the *non*-RT
        // mesh-shadow path). Use it only on a device without render-stage ray tracing;
        // an RT device compiles from source with the define set, which is Ollin's
        // standard runtime-compile path (and what live shader reload already uses).
        if !rt, let library = try? device.makeDefaultLibrary(bundle: Bundle.module) {
            return library
        }
        // Read every segment from the bundle and concatenate in order; the combined
        // source is one compile unit (ShaderCore's `#include` is spliced by
        // composeShaderSource). Require all of them, so a missing segment fails
        // loudly rather than compiling an incomplete library.
        let parts = shaderSourceNames.map { name in
            Bundle.module.url(forResource: name, withExtension: "metal")
                .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        }
        if parts.allSatisfy({ $0 != nil }) {
            let combined = parts.compactMap { $0 }.joined(separator: "\n")
            // Let compile errors propagate: a bad shader should fail loudly here.
            return try device.makeLibrary(source: composeShaderSource(combined, rayTracing: rt), options: nil)
        }
        if !rt, let library = device.makeDefaultLibrary() {
            return library
        }
        throw RendererError.shaderLibrary
    }
}

extension Color {
    /// Background/clear-color representation for a render pass. The render targets
    /// are sRGB-encoded and Metal treats a clear value as *linear* (encoding it on
    /// store), so the RGB is linearized here to land the author's sRGB tone in the
    /// framebuffer — matching the shaders, which linearize their colors too. Alpha
    /// isn't gamma-encoded, so it passes through.
    var mtlClearColor: MTLClearColor {
        MTLClearColorMake(Color.srgbToLinear(red), Color.srgbToLinear(green),
                          Color.srgbToLinear(blue), alpha)
    }
}
