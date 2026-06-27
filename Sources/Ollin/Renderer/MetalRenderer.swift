import Foundation
import Metal
import MetalKit
import MetalPerformanceShaders   // tuned image kernels (Gaussian blur) behind the effect filters
import simd
import CoreGraphics
import os   // OSAllocatedUnfairLock for the off-thread equirect decode handoff
import COllinShaders   // OllinVertex / Uniforms / SDFInstance, shared with the shaders
import CHosekWilkie   // ollin_hosek_rgb_configs, the procedural-sky coefficient cook

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
        /// Force `rasterSampleCount = 1` instead of the view's MSAA count. The half-res
        /// raymarch pass (and its upsample composite) run single-sample, since the raymarch's
        /// silhouette AA is analytic, so it needs no MSAA, and the half-res target is a
        /// plain (non-multisampled) sampleable texture.
        var singleSample = false
        /// An image-based-lighting bake pass: a fullscreen-triangle `ollin_ibl_vertex`
        /// fragment rendering into one cube face (or the BRDF LUT), single-sample, replace.
        /// Its color format varies (`rgba16Float` cubes, `rg16Float` LUT), so it's part of
        /// the key. Run once per environment (cached), not per frame.
        var isIBL = false
        var iblColorFormat: MTLPixelFormat = .rgba16Float

        // an IBL bake pass (equirect→cube / irradiance / prefilter / BRDF LUT)
        static func ibl(_ fragment: String, color: MTLPixelFormat = .rgba16Float) -> PipelineKey {
            PipelineKey(vertex: "ollin_ibl_vertex", fragment: fragment,
                        isIBL: true, iblColorFormat: color)
        }
        // the environment skybox backdrop: a fullscreen view-ray cube sample into the
        // geometry pass (the view's MSAA + depth format), drawn with depth disabled.
        static func skybox(depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_ibl_skybox_vertex", fragment: "ollin_ibl_skybox_fragment",
                        depthFormat: depth)
        }

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
        // composed SDF fields (combinators): a covering quad whose fragment runs the
        // node-program VM (smooth union/subtract/intersect/morph + domain ops)
        static func sdfGroup(_ blend: BlendMode, depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_sdfgroup_vertex", fragment: "ollin_sdfgroup_fragment", blend: blend, depthFormat: depth)
        }
        // raymarched composed 3D SDF field (the SDF3D combinator path): a fullscreen
        // triangle whose fragment sphere-traces the field and writes depth
        static func raymarch(_ blend: BlendMode, depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_raymarch_vertex", fragment: "ollin_raymarch_fragment", blend: blend, depthFormat: depth)
        }
        // the same raymarch fragment, but single-sample into a half-resolution color + depth
        // target (the `.performance` tier marches a quarter of the pixels). Always `.normal`
        // straight-alpha over a transparent clear, so the stored color is premultiplied.
        static func raymarchHalfRes(depth: MTLPixelFormat) -> PipelineKey {
            PipelineKey(vertex: "ollin_raymarch_vertex", fragment: "ollin_raymarch_fragment",
                        depthFormat: depth, singleSample: true)
        }
        // The half-res point/RT field-cast shadow pre-pass: re-render the receiver meshes
        // (`ollin_mesh_vertex`) at reduced resolution, outputting only the field-shadow factor;
        // depth-tested + single-sample (its own small target, no MSAA), like the raymarch half-res.
        static func fieldShadowHalfRes(depth: MTLPixelFormat) -> PipelineKey {
            PipelineKey(vertex: "ollin_mesh_vertex", fragment: "ollin_mesh_fieldshadow_fragment",
                        depthFormat: depth, singleSample: true)
        }
        // composite the half-resolution field back at full resolution: a fullscreen tri that
        // upsamples the half-res color (bilinear) + depth (point) and re-emits the depth, so a
        // mesh still z-tests against the field. Premultiplied `.normal` (the half-res color is
        // premultiplied); not single-sample, since it runs in the MSAA main pass and inherits
        // the view sample count (singleSample stays false).
        static func raymarchUpsample(depth: MTLPixelFormat) -> PipelineKey {
            PipelineKey(vertex: "ollin_raymarch_vertex", fragment: "ollin_raymarch_upsample_fragment",
                        premultiplied: true, depthFormat: depth)
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
        // mesh view-space normal G-buffer: re-render the meshes MSAA + depth-tested, writing
        // each surface's view-space normal (alpha 1) so the ambient-occlusion combine reads a
        // true normal instead of reconstructing one from depth. MSAA (not single-sample) so a
        // silhouette pixel resolves to a coverage-weighted mesh normal (renormalized on read)
        // rather than toggling between the mesh normal and the cleared background sub-pixel,
        // which shimmered the AO at edges; the resolved alpha carries that coverage. Inherits
        // the view sample count, matching the resolved scene depth the SSAO reads alongside it.
        // Material-agnostic: one pipeline for the solid / textured / matcap meshes. `.normal`
        // blend with the fragment's alpha 1 over a transparent clear is effectively a replace.
        static func meshNormal(depth: MTLPixelFormat) -> PipelineKey {
            PipelineKey(vertex: "ollin_mesh_normal_vertex", fragment: "ollin_mesh_normal_fragment",
                        depthFormat: depth)
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
        // depth-only shadow pass for a raymarched 3D field: the same fullscreen-tri vertex as
        // the main raymarch, marched from the light's POV, writing the hit's light-clip depth
        // into the directional/spot 2D map so meshes receive the field's cast shadow.
        static let raymarchShadow = PipelineKey(vertex: "ollin_raymarch_vertex",
                                                fragment: "ollin_raymarch_shadow_fragment", isShadow: true)
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
            case .sdfGroup:   return .sdfGroup(blend, depth: depth)
            case .sdfGroup3D: return .raymarch(blend, depth: depth)
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

    /// User-supplied shaders (the `Shader` type) compile to their own small library,
    /// like compute kernels: keyed by a hash of the composed source (lib + wrapper +
    /// user code), so a shader recompiles only when its source changes, not per frame.
    /// A *failed* compile is cached too (`userShaderErrors`) so a broken shader doesn't
    /// retry every frame; the cache is cleared on a framework-shader reload.
    enum UserShaderVariant { case generator, filter, combine }
    private var userShaderLibraries: [UInt64: MTLLibrary] = [:]
    private var userShaderPipelines: [UInt64: MTLRenderPipelineState] = [:]
    private var userShaderErrors: [UInt64: ShaderCompileError] = [:]
    /// Contents of `.metal` resource shaders, cached by absolute path (read once, not
    /// per frame). Cleared on invalidation so an edited `.metal` is re-read.
    private var userShaderSources: [String: String] = [:]
    /// Hashes already printed to stderr, so a broken shader logs once (for a plain
    /// `swift run`), not every frame.
    private var printedShaderErrorHashes: Set<UInt64> = []
    /// This frame's user-shader compile state, reset to `nil` at the top of each
    /// render and set when a shader fails to compile. The host (OllinLive) reads it
    /// after each frame to drive the on-screen error overlay; a standalone run
    /// ignores it and relies on the stderr print.
    private(set) var currentUserShaderError: ShaderCompileError?
    /// The current frame's time/mouse/frame values, snapshotted at the top of the
    /// effect pass so a user shader (generator, filter, or combine) can fill its
    /// `ShaderInfo` without threading the drawer through every effect call site.
    private var frameComputeUniforms = OllinComputeUniforms(
        resolution: .zero, mouse: .zero, time: 0, dt: 0, frameCount: 0, particleCount: 0, custom: .zero)

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

    /// Parallel ring + export buffers for the SDF-combinator group instances and
    /// their flat node programs, advanced with `frameIndex` like the others.
    private var sdfGroupBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    private var sdfNodeBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    private var sdfGroupExportBuffer: MTLBuffer?
    private var sdfNodeExportBuffer: MTLBuffer?
    private var sdf3DGroupBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    private var sdf3DNodeBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    private var sdf3DGroupExportBuffer: MTLBuffer?
    private var sdf3DNodeExportBuffer: MTLBuffer?

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
    /// Ray-traced reflections: per-geometry base-vertex offsets (one `UInt32` per coalesced
    /// caster geometry in `shadowAccel`) so a reflection hit's `(geometryId, primitiveId)`
    /// resolves to a vertex in the flat mesh buffer. Grown in place, filled in `buildShadowAccel`.
    /// `dummyGeoOffsets` is the 1-element stand-in bound when reflections are off, so the
    /// RT-compiled mesh fragment's declared offsets argument is always satisfied.
    private var meshGeoOffsetBuffer: MTLBuffer?
    private var dummyGeoOffsets: MTLBuffer?
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

    /// The half-resolution color + depth targets for the `.performance` raymarch tier: the
    /// field is sphere-traced into these at half the drawable size, then a fullscreen pass
    /// upsamples + composites them at full res (writing depth so meshes still occlude it).
    /// Both are sampleable single-sample textures, cached and rebuilt only on a size change.
    private var halfResColor: MTLTexture?
    private var halfResDepth: MTLTexture?
    private var halfResSize = (width: 0, height: 0)

    /// The half-resolution point/RT field-cast shadow target (the live RenderQuality path): the
    /// receiver meshes are re-rendered into it (depth-tested) with only their field-shadow factor,
    /// and the full-res mesh pass samples it instead of marching per pixel. `color` is single-
    /// channel-by-convention (R holds the factor); `depth` keeps the front surface's factor.
    private var halfResFieldShadow: MTLTexture?
    private var halfResFieldShadowDepth: MTLTexture?
    private var halfResFieldShadowSize = (width: 0, height: 0)

    /// Per-frame-ring pools of effects-layer textures, reused across frames so a
    /// sketch that uses render targets every frame allocates them once. Keyed by the
    /// ring slot (`frameIndex`) so a texture is never reused while an in-flight frame
    /// still reads it: the same discipline as the vertex-buffer ring. `*Next` is the
    /// per-frame acquisition cursor, reset at the start of the effects graph.
    private var targetTexPool: [[(msaa: MTLTexture, resolve: MTLTexture, w: Int, h: Int)]] =
        Array(repeating: [], count: MetalRenderer.maxFramesInFlight)
    private var filterTexPool: [[(tex: MTLTexture, w: Int, h: Int)]] =
        Array(repeating: [], count: MetalRenderer.maxFramesInFlight)
    /// Depth attachments for a render target that holds a 3D scene: an MSAA depth
    /// buffer (memoryless, tile-only) that resolves into a single-sample sampleable
    /// `depth32Float`, the `depth` layer reads from. Pooled like the color targets,
    /// but only a depth-carrying target ever pulls from it, so 2D targets cost nothing.
    private var targetDepthPool: [[(msaa: MTLTexture, resolve: MTLTexture, w: Int, h: Int)]] =
        Array(repeating: [], count: MetalRenderer.maxFramesInFlight)
    private var targetTexNext = 0
    private var filterTexNext = 0
    private var targetDepthNext = 0

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
        weak var owner: AnyObject?
        init(a: MTLTexture, b: MTLTexture, w: Int, h: Int, owner: AnyObject) {
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

    /// One fluid `SimField`'s persistent state: the velocity and dye ping-pong pairs
    /// that carry across frames. These are the only fields a fluid must keep — pressure,
    /// divergence, and curl are recomputed each frame from pooled scratch. Each frame
    /// reads the current front of each pair and writes the evolved field into the back,
    /// then `flipped` toggles, exactly like `FeedbackSlot` (just two pairs instead of
    /// one). `owner` is weak so the slot is pruned once the sketch releases the field.
    private final class FluidSlot {
        let velA: MTLTexture, velB: MTLTexture
        let dyeA: MTLTexture, dyeB: MTLTexture
        let w: Int, h: Int
        var flipped = false
        weak var owner: AnyObject?
        init(velA: MTLTexture, velB: MTLTexture, dyeA: MTLTexture, dyeB: MTLTexture,
             w: Int, h: Int, owner: AnyObject) {
            self.velA = velA; self.velB = velB; self.dyeA = dyeA; self.dyeB = dyeB
            self.w = w; self.h = h; self.owner = owner
        }
    }
    /// Persistent fluid storage, kept across frames like `feedbackSlots` and pruned the
    /// same way. Separate map because a fluid keeps two pairs, not the single one a
    /// `FeedbackSlot` holds.
    private var fluidSlots: [ObjectIdentifier: FluidSlot] = [:]
    private var fluidUsedThisFrame: Set<ObjectIdentifier> = []

    /// One screen-space-reflections layer's temporal-accumulation history: the ping-pong pair
    /// carrying the reflection across frames (the back is written this frame and becomes the
    /// front next frame), plus the previous frame's scene view·projection used to reproject it,
    /// and a `valid` flag gating the very first frame (no history yet). Keyed by the SSR op's
    /// ordinal in the frame rather than a layer identity: a sketch makes its render target fresh
    /// each frame, so there is no stable owner to key on the way feedback and fluid do.
    private final class SSRHistorySlot {
        let a: MTLTexture, b: MTLTexture
        let w: Int, h: Int
        var flipped = false
        var valid = false
        var previousViewProjection = matrix_identity_float4x4
        init(a: MTLTexture, b: MTLTexture, w: Int, h: Int) {
            self.a = a; self.b = b; self.w = w; self.h = h
        }
    }
    /// Persistent SSR history, kept across frames like `feedbackSlots`, keyed by SSR-op ordinal.
    /// Bounded by the (small, contiguous) ordinal count, so it isn't pruned per frame; a skipped
    /// SSR frame keeps its history (the reprojection clamp reconverges if it went stale).
    private var ssrHistorySlots: [Int: SSRHistorySlot] = [:]
    /// SSR ops resolved this frame, so only those flip their ping-pong.
    private var ssrHistoryUsedThisFrame: Set<Int> = []
    /// The next SSR op's ordinal this frame; reset at the start of `encodeEffectTargets`.
    private var ssrOrdinalNext = 0

    /// Baked image-based-lighting maps, cached by environment source so the bake (a few
    /// fullscreen passes) runs once, not per frame. `iblBRDFLUT` is environment-independent
    /// (the split-sum scale/bias integral) so it's baked once globally. `currentIBL` is the
    /// set resolved for the frame being encoded, bound to the mesh fragment.
    private var iblCache: [Environment.Source: IBLMaps] = [:]
    private var iblBRDFLUT: MTLTexture?
    private var currentIBL: IBLMaps?
    /// A 1×1 cube bound at the IBL texture slots when no environment is set, so the mesh
    /// fragment's declared cube samplers are always bound (never sampled in that case).
    private var iblPlaceholderCube: MTLTexture?
    /// Processed equirect pixels ready to bake, keyed by source. A heavy `.url` HDRI decodes
    /// off the render thread (live) and lands here for the next frame to upload + bake; the
    /// bundled placeholder shows meanwhile. Locked because the background decode writes it.
    private let equirectReady = OSAllocatedUnfairLock(initialState: [Environment.Source: EquirectBytes]())
    /// Sources whose off-thread decode is in flight, so a repeat request each frame doesn't
    /// start a second decode.
    private let equirectLoading = OSAllocatedUnfairLock(initialState: Set<Environment.Source>())

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
        // Bake the IBL environment maps (once, cached) ahead of the geometry pass, so the
        // mesh fragments can sample them. A no-op when no environment is set.
        _ = resolveIBL(for: drawer.environment, commandBuffer: commandBuffer)
        // Shadow depth pass from the casting light, ahead of the geometry pass in the
        // same command buffer (a no-op returning nil when this frame casts no shadow).
        // It shares the mesh vertex buffer the geometry pass uses.
        let meshBuf = meshBuffer(at: frameIndex, for: drawer.meshVertices.count)
        let renderedShadow = encodeShadowPass(
            drawer, into: commandBuffer, meshBuffer: meshBuf,
            sdf3DGroupBuffer: sdf3DGroupBuffer(at: frameIndex, for: drawer.sdf3DGroups.count),
            sdf3DNodeBuffer: sdf3DNodeBuffer(at: frameIndex, for: drawer.sdf3DNodes.count))

        // Effects layers fill before the main pass (which samples them via drawImage),
        // sharing this frame's geometry buffers. A no-op when the frame used none.
        let buffers = GeometryBuffers(
            triangle: vertexBuffer(at: frameIndex, for: drawer.vertices.count),
            sdf: sdfBuffer(at: frameIndex, for: drawer.sdfInstances.count),
            image: imageBuffer(at: frameIndex, for: drawer.imageVertices.count),
            glyph: glyphBuffer(at: frameIndex, for: drawer.glyphVertices.count),
            point: pointBuffer(at: frameIndex, for: drawer.points.count),
            mesh: meshBuf,
            sdfGroup: sdfGroupBuffer(at: frameIndex, for: drawer.sdfGroups.count),
            sdfNode: sdfNodeBuffer(at: frameIndex, for: drawer.sdfNodes.count),
            sdf3DGroup: sdf3DGroupBuffer(at: frameIndex, for: drawer.sdf3DGroups.count),
            sdf3DNode: sdf3DNodeBuffer(at: frameIndex, for: drawer.sdf3DNodes.count))
        encodeEffectTargets(drawer, into: commandBuffer, buffers: buffers, pooled: true)

        // Half-res raymarch pre-pass (the `.performance` tier): sphere-trace the fields at half
        // resolution into a sampleable color+depth that the main pass upsamples + composites.
        // `nil` on the full-res tiers or a frame with no fields, so those stay byte-identical.
        let halfResField = makeRaymarchUniforms3D(drawer, viewport: viewport).flatMap { u3 in
            let fieldLight = resolveFieldLighting(drawer, shadowMap: renderedShadow.twoD,
                                                  shadowCube: renderedShadow.cube,
                                                  shadowAccelPresent: renderedShadow.accel != nil)
            return encodeRaymarchHalfRes(drawer, into: commandBuffer,
                groupBuffer: buffers.sdf3DGroup, nodeBuffer: buffers.sdf3DNode,
                uniforms3D: u3, lighting: fieldLight.lighting,
                shadowTexture: fieldLight.shadowTexture, shadowCubeTexture: fieldLight.shadowCubeTexture,
                shadowAccel: renderedShadow.accel, fullWidth: width, fullHeight: height)
        }
        // Half-res field-cast shadow pre-pass (the live RenderQuality path): the point/RT field
        // cast onto meshes is per-pixel-marched, so compute it once at reduced resolution and let
        // the mesh pass sample it. `nil` at the full-res tier / no point-RT caster (inline → byte-identical).
        let halfResFieldShadow = makeRaymarchUniforms3D(drawer, viewport: viewport).flatMap { u3 -> MTLTexture? in
            var fl = resolveFieldLighting(drawer, shadowMap: renderedShadow.twoD, shadowCube: renderedShadow.cube,
                                          shadowAccelPresent: renderedShadow.accel != nil).lighting
            fl.fieldCasterCount = resolveFieldCasterCount(fl, drawer)
            return encodeFieldShadowHalfRes(drawer, into: commandBuffer, meshBuffer: buffers.mesh,
                groupBuffer: buffers.sdf3DGroup, nodeBuffer: buffers.sdf3DNode,
                uniforms3D: u3, lighting: fl, fullWidth: width, fullHeight: height)
        }

        guard let geomEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: geomPass) else {
            frameBoundary.signal()   // nothing encoded; hand the slot back
            return
        }
        commandBuffer.addCompletedHandler { [frameBoundary] _ in frameBoundary.signal() }

        encode(drawer, viewport: viewport, into: geomEncoder,
               triangleBuffer: buffers.triangle, sdfBuffer: buffers.sdf,
               imageBuffer: buffers.image, glyphBuffer: buffers.glyph,
               pointBuffer: buffers.point, meshBuffer: buffers.mesh,
                   sdfGroupBuffer: buffers.sdfGroup, sdfNodeBuffer: buffers.sdfNode,
                   sdf3DGroupBuffer: buffers.sdf3DGroup, sdf3DNodeBuffer: buffers.sdf3DNode,
               depthFormat: passDepthFormat, shadowMap: renderedShadow.twoD,
               shadowCube: renderedShadow.cube,
               shadowAccel: renderedShadow.accel,
               reflectAccel: renderedShadow.reflectAccel,
               reflectGeoOffsets: renderedShadow.reflectGeoOffsets,
               halfResField: halfResField,
               halfResFieldShadow: halfResFieldShadow)
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
               sdfGroupBuffer: sdfGroupBuffer(at: frameIndex, for: drawer.sdfGroups.count),
               sdfNodeBuffer: sdfNodeBuffer(at: frameIndex, for: drawer.sdfNodes.count),
               sdf3DGroupBuffer: sdf3DGroupBuffer(at: frameIndex, for: drawer.sdf3DGroups.count),
               sdf3DNodeBuffer: sdf3DNodeBuffer(at: frameIndex, for: drawer.sdf3DNodes.count),
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
               sdfGroupBuffer: exportSDFGroupBuffer(for: drawer.sdfGroups.count),
               sdfNodeBuffer: exportSDFNodeBuffer(for: drawer.sdfNodes.count),
               sdf3DGroupBuffer: exportSDF3DGroupBuffer(for: drawer.sdf3DGroups.count),
               sdf3DNodeBuffer: exportSDF3DNodeBuffer(for: drawer.sdf3DNodes.count),
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
        // Export blocks on a remote-environment download so the exported frame is full-res.
        _ = resolveIBL(for: drawer.environment, commandBuffer: commandBuffer, blocking: true)
        // Shadow depth pass (nil when this frame casts no shadow), sharing the export
        // mesh buffer; so the headless/snapshot path shadows exactly like the window.
        let meshBuf = exportMeshBuffer(for: drawer.meshVertices.count)
        let renderedShadow = encodeShadowPass(
            drawer, into: commandBuffer, meshBuffer: meshBuf,
            sdf3DGroupBuffer: exportSDF3DGroupBuffer(for: drawer.sdf3DGroups.count),
            sdf3DNodeBuffer: exportSDF3DNodeBuffer(for: drawer.sdf3DNodes.count))

        // Effects layers fill before the main pass, sharing the export buffers, so
        // the headless/snapshot path renders targets exactly like the window.
        let buffers = GeometryBuffers(
            triangle: exportVertexBuffer(for: drawer.vertices.count),
            sdf: exportSDFBuffer(for: drawer.sdfInstances.count),
            image: exportImageBuffer(for: drawer.imageVertices.count),
            glyph: exportGlyphBuffer(for: drawer.glyphVertices.count),
            point: exportPointBuffer(for: drawer.points.count),
            mesh: meshBuf,
            sdfGroup: exportSDFGroupBuffer(for: drawer.sdfGroups.count),
            sdfNode: exportSDFNodeBuffer(for: drawer.sdfNodes.count),
            sdf3DGroup: exportSDF3DGroupBuffer(for: drawer.sdf3DGroups.count),
            sdf3DNode: exportSDF3DNodeBuffer(for: drawer.sdf3DNodes.count))
        encodeEffectTargets(drawer, into: commandBuffer, buffers: buffers, pooled: false)

        // Half-res raymarch pre-pass: honours the resolution tier on export too, so an
        // explicit `.performance`/`.default` raymarch quality downscales here as it does live.
        // At `.detail` (the export default) the scale is 1 and this is nil (full resolution).
        let halfResField = makeRaymarchUniforms3D(drawer, viewport: viewport).flatMap { u3 in
            let fieldLight = resolveFieldLighting(drawer, shadowMap: renderedShadow.twoD,
                                                  shadowCube: renderedShadow.cube,
                                                  shadowAccelPresent: renderedShadow.accel != nil)
            return encodeRaymarchHalfRes(drawer, into: commandBuffer,
                groupBuffer: buffers.sdf3DGroup, nodeBuffer: buffers.sdf3DNode,
                uniforms3D: u3, lighting: fieldLight.lighting,
                shadowTexture: fieldLight.shadowTexture, shadowCubeTexture: fieldLight.shadowCubeTexture,
                shadowAccel: renderedShadow.accel, fullWidth: width, fullHeight: height)
        }
        // Half-res field-cast shadow pre-pass: same tier gating as the raymarch one. `.detail`
        // (the export default) → scale 1 → nil → the mesh marches inline full-res → byte-identical.
        let halfResFieldShadow = makeRaymarchUniforms3D(drawer, viewport: viewport).flatMap { u3 -> MTLTexture? in
            var fl = resolveFieldLighting(drawer, shadowMap: renderedShadow.twoD, shadowCube: renderedShadow.cube,
                                          shadowAccelPresent: renderedShadow.accel != nil).lighting
            fl.fieldCasterCount = resolveFieldCasterCount(fl, drawer)
            return encodeFieldShadowHalfRes(drawer, into: commandBuffer, meshBuffer: buffers.mesh,
                groupBuffer: buffers.sdf3DGroup, nodeBuffer: buffers.sdf3DNode,
                uniforms3D: u3, lighting: fl, fullWidth: width, fullHeight: height)
        }

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }

        encode(drawer, viewport: viewport, into: encoder,
               triangleBuffer: buffers.triangle, sdfBuffer: buffers.sdf,
               imageBuffer: buffers.image, glyphBuffer: buffers.glyph,
               pointBuffer: buffers.point, meshBuffer: buffers.mesh,
                   sdfGroupBuffer: buffers.sdfGroup, sdfNodeBuffer: buffers.sdfNode,
                   sdf3DGroupBuffer: buffers.sdf3DGroup, sdf3DNodeBuffer: buffers.sdf3DNode,
               depthFormat: passDepthFormat, shadowMap: renderedShadow.twoD,
               shadowCube: renderedShadow.cube,
               shadowAccel: renderedShadow.accel,
               reflectAccel: renderedShadow.reflectAccel,
               reflectGeoOffsets: renderedShadow.reflectGeoOffsets,
               halfResField: halfResField,
               halfResFieldShadow: halfResFieldShadow)
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
        // The frame's geometry uploads, shared by the effect-target passes and the main
        // pass, so a sketch that uses effects (e.g. a `.defocus` combine) is timed in full.
        let buffers = GeometryBuffers(
            triangle: exportVertexBuffer(for: drawer.vertices.count),
            sdf: exportSDFBuffer(for: drawer.sdfInstances.count),
            image: exportImageBuffer(for: drawer.imageVertices.count),
            glyph: exportGlyphBuffer(for: drawer.glyphVertices.count),
            point: exportPointBuffer(for: drawer.points.count),
            mesh: meshBuf,
            sdfGroup: exportSDFGroupBuffer(for: drawer.sdfGroups.count),
            sdfNode: exportSDFNodeBuffer(for: drawer.sdfNodes.count),
            sdf3DGroup: exportSDF3DGroupBuffer(for: drawer.sdf3DGroups.count),
            sdf3DNode: exportSDF3DNodeBuffer(for: drawer.sdf3DNodes.count))
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
            _ = resolveIBL(for: drawer.environment, commandBuffer: cb)   // bake IBL once
            let renderedShadow = encodeShadowPass(
                drawer, into: cb, meshBuffer: meshBuf,
                sdf3DGroupBuffer: buffers.sdf3DGroup, sdf3DNodeBuffer: buffers.sdf3DNode)
            encodeEffectTargets(drawer, into: cb, buffers: buffers, pooled: false)
            // Half-res raymarch pre-pass (the `.performance` tier), so the benchmark measures
            // the same cost the live path pays. nil otherwise.
            let halfResField = makeRaymarchUniforms3D(drawer, viewport: viewport).flatMap { u3 in
                let fieldLight = resolveFieldLighting(drawer, shadowMap: renderedShadow.twoD,
                                                      shadowCube: renderedShadow.cube,
                                                      shadowAccelPresent: renderedShadow.accel != nil)
                return encodeRaymarchHalfRes(drawer, into: cb,
                    groupBuffer: buffers.sdf3DGroup, nodeBuffer: buffers.sdf3DNode,
                    uniforms3D: u3, lighting: fieldLight.lighting,
                    shadowTexture: fieldLight.shadowTexture, shadowCubeTexture: fieldLight.shadowCubeTexture,
                    shadowAccel: renderedShadow.accel, fullWidth: width, fullHeight: height)
            }
            let halfResFieldShadow = makeRaymarchUniforms3D(drawer, viewport: viewport).flatMap { u3 -> MTLTexture? in
                var fl = resolveFieldLighting(drawer, shadowMap: renderedShadow.twoD, shadowCube: renderedShadow.cube,
                                              shadowAccelPresent: renderedShadow.accel != nil).lighting
                fl.fieldCasterCount = resolveFieldCasterCount(fl, drawer)
                return encodeFieldShadowHalfRes(drawer, into: cb, meshBuffer: buffers.mesh,
                    groupBuffer: buffers.sdf3DGroup, nodeBuffer: buffers.sdf3DNode,
                    uniforms3D: u3, lighting: fl, fullWidth: width, fullHeight: height)
            }
            guard let encoder = cb.makeRenderCommandEncoder(descriptor: pass) else { continue }
            encode(drawer, viewport: viewport, into: encoder,
                   triangleBuffer: buffers.triangle, sdfBuffer: buffers.sdf,
                   imageBuffer: buffers.image, glyphBuffer: buffers.glyph,
                   pointBuffer: buffers.point, meshBuffer: buffers.mesh,
                   sdfGroupBuffer: buffers.sdfGroup, sdfNodeBuffer: buffers.sdfNode,
                   sdf3DGroupBuffer: buffers.sdf3DGroup, sdf3DNodeBuffer: buffers.sdf3DNode,
                   depthFormat: passDepthFormat, shadowMap: renderedShadow.twoD,
                   shadowCube: renderedShadow.cube, shadowAccel: renderedShadow.accel,
                   reflectAccel: renderedShadow.reflectAccel,
                   reflectGeoOffsets: renderedShadow.reflectGeoOffsets,
                   halfResField: halfResField,
                   halfResFieldShadow: halfResFieldShadow)
            encoder.endEncoding()
            let presented = applyFrameFilters(drawer, resolved: resolveTexture, width: width,
                                              height: height, into: cb, pooled: false)
            if let presentEncoder = cb.makeRenderCommandEncoder(descriptor: presentPass(into: displayTexture)) {
                encodePresent(from: presented, drawer: drawer, into: presentEncoder)
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
               sdfGroupBuffer: exportSDFGroupBuffer(for: drawer.sdfGroups.count),
               sdfNodeBuffer: exportSDFNodeBuffer(for: drawer.sdfNodes.count),
               sdf3DGroupBuffer: exportSDF3DGroupBuffer(for: drawer.sdf3DGroups.count),
               sdf3DNodeBuffer: exportSDF3DNodeBuffer(for: drawer.sdf3DNodes.count),
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
        var sdfGroup: MTLBuffer?
        var sdfNode: MTLBuffer?
        var sdf3DGroup: MTLBuffer?
        var sdf3DNode: MTLBuffer?
    }

    /// Fill every effects layer this frame, ahead of the main pass: render each
    /// geometry target's tagged batches into its own texture, then run each filter
    /// op into its output texture. Each layer ends with `texture` set, so the main
    /// pass (and later filters) can sample it. A no-op when the frame used no
    /// targets, so the ordinary path is byte-identical. `pooled` reuses per-frame
    /// textures on the live ring; the headless paths allocate fresh and wait.
    private func encodeEffectTargets(_ drawer: Drawer, into cb: MTLCommandBuffer,
                                     buffers: GeometryBuffers, pooled: Bool) {
        // Reset the user-shader error state for this frame; any failing shader below
        // sets it, and the host reads it afterward to drive the error overlay.
        currentUserShaderError = nil
        frameComputeUniforms = drawer.computeUniforms   // for user-shader ShaderInfo
        guard !drawer.renderTargets.isEmpty || !drawer.filterOps.isEmpty
            || !drawer.frameFilters.isEmpty else { return }
        targetTexNext = 0
        filterTexNext = 0
        targetDepthNext = 0
        ssrOrdinalNext = 0
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
            // A target that holds a 3D scene carries a depth attachment so its meshes
            // z-test (and so the `depth` layer can read it). The MSAA depth resolves
            // (nearest sample) into a sampleable single-sample buffer; a 2D target
            // takes none of this, so its pass is byte-identical to before.
            var depthResolve: MTLTexture? = nil
            if target.needsDepth, let depth = acquireTargetDepth(width: pw, height: ph, pooled: pooled) {
                pass.depthAttachment.texture = depth.msaa
                pass.depthAttachment.resolveTexture = depth.resolve
                pass.depthAttachment.loadAction = .clear
                pass.depthAttachment.clearDepth = 1.0
                pass.depthAttachment.storeAction = .multisampleResolve
                pass.depthAttachment.depthResolveFilter = .min
                depthResolve = depth.resolve
            }
            guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { continue }
            // Geometry inside the block used canvas coordinates, so map by the logical
            // size; a fraction-res layer's smaller attachment just downsamples.
            encode(drawer, viewport: SIMD2(Float(target.width), Float(target.height)), into: enc,
                   triangleBuffer: buffers.triangle, sdfBuffer: buffers.sdf, imageBuffer: buffers.image,
                   glyphBuffer: buffers.glyph, pointBuffer: buffers.point, meshBuffer: buffers.mesh,
                   sdfGroupBuffer: buffers.sdfGroup, sdfNodeBuffer: buffers.sdfNode,
                   sdf3DGroupBuffer: buffers.sdf3DGroup, sdf3DNodeBuffer: buffers.sdf3DNode,
                   depthFormat: depthResolve != nil ? depthPixelFormat : nil, target: target)
            enc.endEncoding()
            target.texture = tex.resolve
            // Expose the scene's depth as a gray layer when the sketch read `.depth`:
            // linearize the clip-space depth over the camera's near/far into 0…1,
            // encoded so the existing perceptual DoF decode recovers it exactly. Only
            // run when the layer was actually accessed: a 3D target you don't defocus
            // pays only for its own occlusion above, not this pass.
            if let depthResolve, let depthLayer = target.depthLayer {
                depthLayer.texture = normalizeDepth(depthResolve, camera: drawer.camera3D,
                                                    width: pw, height: ph, into: cb, pooled: pooled)
                // Stamp the camera geometry on the depth layer so a combine that
                // reconstructs view-space position from it (ambient occlusion) can.
                if let cam = drawer.camera3D {
                    depthLayer.depthReconstruction = DepthReconstruction(camera: cam,
                                                                         pixelWidth: pw, pixelHeight: ph)
                }
            }
            // The mesh-normal G-buffer, when this 3D target feeds an ambient-occlusion
            // combine: a dedicated single-sample mesh pass so SSAO occludes against a true
            // surface normal rather than one reconstructed from depth. Gated on
            // `needsNormals` (set when an `.ambientOcclusion` combine reads a 3D target), so
            // a target that doesn't run AO never encodes it and stays byte-identical. The
            // `normals` accessor instantiates the layer here (the sketch never names it, so
            // unlike `depth` nothing else creates it); the combine then reads its texture.
            if target.needsNormals {
                target.normals.texture = encodeMeshNormals(drawer, into: cb, meshBuffer: buffers.mesh,
                                                           width: pw, height: ph, pooled: pooled)
            }
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
                   sdfGroupBuffer: buffers.sdfGroup, sdfNodeBuffer: buffers.sdfNode,
                   sdf3DGroupBuffer: buffers.sdf3DGroup, sdf3DNodeBuffer: buffers.sdf3DNode,
                   depthFormat: nil, target: target)
            enc.endEncoding()
            target.texture = back                // `image` resolves to this frame
            feedbackUsedThisFrame.insert(ObjectIdentifier(fb))
        }
        // Simulation fields: a persistent ping-pong like feedback, but the renderer
        // evolves the state itself. Render this frame's drawn seeds into a transient
        // texture, then run the field's `Sim` (inject the seeds onto the front state,
        // step it N times) writing the result into the back buffer.
        for target in drawer.renderTargets {
            guard case let .simField(sf) = target.origin else { continue }
            let pw = target.pixelWidth, ph = target.pixelHeight
            guard let msaa = makeFloatMSAA(width: pw, height: ph, storage: .memoryless),
                  let seed = acquireFilterTexture(width: pw, height: ph, pooled: pooled) else { continue }
            // Render this frame's drawn seed marks into `seed` (cleared transparent so
            // an empty block seeds nothing and the field just evolves). Shared by both
            // the single-field sims and the fluid.
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = msaa
            pass.colorAttachments[0].resolveTexture = seed
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = target.clearColor.mtlClearColor
            pass.colorAttachments[0].storeAction = .multisampleResolve
            if let enc = cb.makeRenderCommandEncoder(descriptor: pass) {
                encode(drawer, viewport: SIMD2(Float(target.width), Float(target.height)), into: enc,
                       triangleBuffer: buffers.triangle, sdfBuffer: buffers.sdf, imageBuffer: buffers.image,
                       glyphBuffer: buffers.glyph, pointBuffer: buffers.point, meshBuffer: buffers.mesh,
                   sdfGroupBuffer: buffers.sdfGroup, sdfNodeBuffer: buffers.sdfNode,
                   sdf3DGroupBuffer: buffers.sdf3DGroup, sdf3DNodeBuffer: buffers.sdf3DNode,
                       depthFormat: nil, target: target)
                enc.endEncoding()
            }
            if let config = sf.sim.fluidConfig {
                // Multi-field fluid: its own persistent velocity + dye pairs, evolved by
                // the dedicated solver. `image` resolves to the freshly advected dye.
                guard let slot = fluidSlot(for: sf, width: pw, height: ph, into: cb) else { continue }
                let velFront = slot.flipped ? slot.velB : slot.velA
                let velBack  = slot.flipped ? slot.velA : slot.velB
                let dyeFront = slot.flipped ? slot.dyeB : slot.dyeA
                let dyeBack  = slot.flipped ? slot.dyeA : slot.dyeB
                runFluid(config, force: sf.seedForce, seed: seed,
                         velFront: velFront, velBack: velBack, dyeFront: dyeFront, dyeBack: dyeBack,
                         width: pw, height: ph, into: cb, pooled: pooled)
                target.texture = dyeBack
                fluidUsedThisFrame.insert(ObjectIdentifier(sf))
            } else {
                // Single-field sim (reaction-diffusion, Game of Life): one ping-pong pair.
                let rest = sf.sim.restState
                guard let slot = feedbackSlot(for: sf, width: pw, height: ph,
                                              restState: MTLClearColor(red: Double(rest.x), green: Double(rest.y),
                                                                       blue: Double(rest.z), alpha: Double(rest.w)),
                                              into: cb) else { continue }
                let front = slot.flipped ? slot.b : slot.a
                let back  = slot.flipped ? slot.a : slot.b
                runSimulation(sf.sim, state: front, seed: seed, output: back,
                              width: pw, height: ph, into: cb, pooled: pooled)
                target.texture = back
                feedbackUsedThisFrame.insert(ObjectIdentifier(sf))
            }
        }
        // Filter and combine ops share one list, resolved in record order so an op's
        // inputs (filled earlier in this loop, or by the geometry/generator passes
        // above) are ready before it runs.
        for output in drawer.filterOps {
            switch output.origin {
            case let .filter(input, filter):
                guard let src = input.texture else { continue }
                output.texture = applyFilter(filter, input: src,
                                             width: output.pixelWidth, height: output.pixelHeight,
                                             into: cb, pooled: pooled)
            case let .combine(base, aux, op):
                guard let b = base.texture, let a = aux.texture else { continue }
                // Ambient occlusion reads the base's mesh-normal G-buffer when it was
                // captured (a 3D base feeding AO); nil otherwise → the shader's
                // depth-reconstruction fallback.
                output.texture = applyCombine(op, base: b, aux: a, depth: aux.depthReconstruction,
                                              normals: base.normalLayer?.texture,
                                              width: output.pixelWidth, height: output.pixelHeight,
                                              into: cb, pooled: pooled)
            default:
                continue
            }
        }
        // Advance each feedback layer drawn this frame (its back becomes next frame's
        // front), then prune slots whose owner the sketch has released (live reload,
        // or a layer no longer held) so the map stays bounded.
        for id in feedbackUsedThisFrame { feedbackSlots[id]?.flipped.toggle() }
        feedbackUsedThisFrame.removeAll(keepingCapacity: true)
        if feedbackSlots.contains(where: { $0.value.owner == nil }) {
            feedbackSlots = feedbackSlots.filter { $0.value.owner != nil }
        }
        for id in fluidUsedThisFrame { fluidSlots[id]?.flipped.toggle() }
        fluidUsedThisFrame.removeAll(keepingCapacity: true)
        if fluidSlots.contains(where: { $0.value.owner == nil }) {
            fluidSlots = fluidSlots.filter { $0.value.owner != nil }
        }
        // Advance each SSR temporal history drawn this frame (its back becomes next frame's
        // front). Slots aren't pruned (the ordinal key bounds the map), so a skipped SSR frame
        // keeps its accumulation.
        for id in ssrHistoryUsedThisFrame { ssrHistorySlots[id]?.flipped.toggle() }
        ssrHistoryUsedThisFrame.removeAll(keepingCapacity: true)
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
        case let .shader(shader):
            guard let output = acquireFilterTexture(width: width, height: height, pooled: pooled) else { return nil }
            encodeUserShader(shader, variant: .filter, inputs: [input], output: output,
                             width: width, height: height, into: cb)
            return output
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

        // Color & tone (continued)
        case let .solarize(value, softness):
            return pass("ollin_fx_solarize", [input], [f(value, softness, 0, 0)])
        case let .temperature(amount, tint):
            return pass("ollin_fx_temperature", [input], [f(amount, tint, 0, 0)])
        case .vibrance(let amount):
            return pass("ollin_fx_vibrance", [input], [f(amount, 0, 0, 0)])
        case .exposure(let gain):
            return pass("ollin_fx_exposure", [input], [f(gain, 0, 0, 0)])
        case let .levels(blackPoint, whitePoint, gamma):
            return pass("ollin_fx_levels", [input], [f(blackPoint, whitePoint, gamma, 0)])
        case let .colorama(cycles, shift):
            return pass("ollin_fx_colorama", [input], [f(cycles, shift, 0, 0)])
        case let .lumaKey(low, high, invert):
            return pass("ollin_fx_lumakey", [input], [f(low, high, invert ? 1 : 0, 0)])

        // Blur
        case let .motionBlur(angle, distance):
            return pass("ollin_fx_motion_blur", [input], [f(angle, distance, 0, 0)])
        case .radialBlur(let amount):
            return pass("ollin_fx_radial_blur", [input], [f(amount, 0, 0, 0)])
        case let .bilateral(radius, sigma):
            return pass("ollin_fx_bilateral", [input], [SIMD4(texel.x, texel.y, Float(radius), Float(sigma))])

        // Stylize & optical (continued)
        case let .emboss(amount, angle):
            return pass("ollin_fx_emboss", [input], [SIMD4(texel.x, texel.y, Float(amount), Float(angle))])
        case .oilPaint(let radius):
            return pass("ollin_fx_oilpaint", [input], [SIMD4(texel.x, texel.y, Float(radius), 0)])
        case let .crosshatch(scale, foreground, background):
            return pass("ollin_fx_crosshatch", [input],
                        [SIMD4(Float(scale), aspect, 0, 0), foreground, background])
        case let .toon(levels, edges):
            return pass("ollin_fx_toon", [input], [SIMD4(Float(levels), Float(edges), texel.x, texel.y)])
        case .median:
            return pass("ollin_fx_median", [input], [SIMD4(texel.x, texel.y, 0, 0)])
        case let .contour(levels, intensity):
            return pass("ollin_fx_contour", [input], [f(levels, intensity, 0, 0)])
        case .cmykHalftone(let scale):
            return pass("ollin_fx_cmyk_halftone", [input], [SIMD4(Float(scale), aspect, 0, 0)])
        case .normalMap(let strength):
            return pass("ollin_fx_normal_map", [input], [SIMD4(texel.x, texel.y, Float(strength), 0)])

        // Retro / optical
        case let .scanlines(count, intensity):
            return pass("ollin_fx_scanlines", [input], [f(count, intensity, 0, 0)])
        case let .glitch(amount, seed):
            return pass("ollin_fx_glitch", [input], [f(amount, seed, 0, 0)])
        case let .crt(curvature, scanline, aberration):
            return pass("ollin_fx_crt", [input], [f(curvature, scanline, aberration, 0)])

        // Distortion
        case let .kaleidoscope(segments, angle):
            return pass("ollin_fx_kaleidoscope", [input], [SIMD4(Float(segments), Float(angle), aspect, 0)])
        case let .swirl(angle, radius):
            return pass("ollin_fx_swirl", [input], [SIMD4(Float(angle), Float(radius), aspect, 0)])
        case let .bulge(amount, radius):
            return pass("ollin_fx_bulge", [input], [SIMD4(Float(amount), Float(radius), aspect, 0)])
        case let .wave(amplitude, frequency, phase, vertical):
            return pass("ollin_fx_wave", [input],
                        [SIMD4(Float(amplitude), Float(frequency), Float(phase), vertical ? 1 : 0)])
        case let .ripple(amplitude, frequency, phase):
            return pass("ollin_fx_ripple", [input],
                        [SIMD4(Float(amplitude), Float(frequency), Float(phase), aspect)])
        case let .mirror(vertical, flip):
            return pass("ollin_fx_mirror", [input], [SIMD4(vertical ? 1 : 0, flip ? 1 : 0, 0, 0)])
        case .polar(let amount):
            return pass("ollin_fx_polar", [input], [SIMD4(Float(amount), aspect, 0, 0)])
        case let .tile(count, mirror):
            return pass("ollin_fx_tile", [input], [SIMD4(Float(count), mirror ? 1 : 0, 0, 0)])
        case let .perturb(amount, scale, phase):
            return pass("ollin_fx_perturb", [input],
                        [SIMD4(Float(amount), Float(scale), Float(phase), aspect)])
        }
    }

    /// Run one two-input `op` (mask / displace / mix) over `base` modulated by `aux`
    /// into a freshly acquired output texture, the multi-input sibling of
    /// `applyFilter`. Each is a single fullscreen fragment pass binding both layers,
    /// reading premultiplied-linear and writing the same. The two inputs may differ
    /// in size; the fragment samples by normalized coordinates, so it doesn't matter.
    private func applyCombine(_ op: Combine, base: MTLTexture, aux: MTLTexture,
                              depth: DepthReconstruction? = nil, normals: MTLTexture? = nil,
                              width: Int, height: Int,
                              into cb: MTLCommandBuffer, pooled: Bool) -> MTLTexture? {
        func pass(_ fragment: String, _ params: [SIMD4<Float>]) -> MTLTexture? {
            guard let output = acquireFilterTexture(width: width, height: height, pooled: pooled) else { return nil }
            encodeEffectFragment(fragment, inputs: [base, aux], output: output, params: params, into: cb)
            return output
        }
        switch op.kind {
        case let .shader(shader):
            guard let output = acquireFilterTexture(width: width, height: height, pooled: pooled) else { return nil }
            encodeUserShader(shader, variant: .combine, inputs: [base, aux], output: output,
                             width: width, height: height, into: cb)
            return output
        case let .mask(channel, invert):
            return pass("ollin_fx_mask", [SIMD4(channel.rawIndex, invert ? 1 : 0, 0, 0)])
        case let .displace(amount):
            return pass("ollin_fx_displace", [SIMD4(Float(amount), 0, 0, 0)])
        case let .mix(amount):
            return pass("ollin_fx_mix", [SIMD4(Float(amount), 0, 0, 0)])
        case let .defocus(focus, range, maxBlur, quality):
            // maxBlur is in layer pixels; the gather works in texels, so at this
            // layer's resolution one is the other (the texel-size row keeps the disk
            // round on a non-square layer). The third texel slot carries the resolved
            // bokeh tap budget for the gather.
            let taps = Float(resolveDofTaps(quality))
            let texel = SIMD4<Float>(1 / Float(width), 1 / Float(height), taps, 0)
            return pass("ollin_fx_depth_of_field",
                        [SIMD4(Float(focus), Float(range), Float(maxBlur), 0), texel])
        case let .ambientOcclusion(radius, intensity, bias, quality):
            // Two passes: a hemisphere-kernel occlusion estimate (rebuilding view-space
            // position + normal from the aux depth, with the camera geometry stamped on
            // the depth layer, a neutral perspective when the aux carries none, e.g. a
            // hand-drawn depth map), then a depth-aware blur that softens it and multiplies
            // the base. The sample budget rides the texel row's third slot, as the bokeh
            // gather's does.
            let samples = Float(resolveSSAOSamples(quality))
            let texel = SIMD4<Float>(1 / Float(width), 1 / Float(height), samples, 0)
            let d = depth ?? .neutral
            guard let aoTex = acquireFilterTexture(width: width, height: height, pooled: pooled),
                  let out = acquireFilterTexture(width: width, height: height, pooled: pooled) else { return nil }
            // The mesh-normal G-buffer at texture index 1 (depth stays 0) when it was
            // captured: the shader reads a true view-space normal instead of reconstructing
            // one from depth. A never-sampled stand-in (the depth) keeps the binding valid
            // otherwise, gated by the `hasNormals` flag in params[0].w.
            let hasNormals: Float = normals != nil ? 1 : 0
            encodeEffectFragment("ollin_fx_ssao", inputs: [aux, normals ?? aux], output: aoTex,
                                 params: [SIMD4(Float(radius), Float(intensity), Float(bias), hasNormals), texel,
                                          SIMD4(d.near, d.far, d.tanHalfFovX, d.tanHalfFovY),
                                          SIMD4(d.principalX, d.principalY, d.isPerspective ? 1 : 0, 0)],
                                 into: cb)
            encodeEffectFragment("ollin_fx_ssao_blur", inputs: [base, aoTex, aux], output: out,
                                 params: [SIMD4(Float(intensity), 0, 0, 0), texel], into: cb)
            return out
        case let .screenSpaceReflections(intensity, maxDistance, thickness, roughness, fresnel, edgeFade, quality):
            // Four passes: a screen-space ray march (rebuilding view-space position + normal from
            // the aux depth, reflecting the eye ray about the normal, then marching until it
            // crosses the depth buffer) writes a premultiplied reflection; a depth-aware,
            // roughness-scaled blur softens it; a temporal pass reprojects last frame's reflection
            // and accumulates it (killing the contact-seam flicker that no spatial filter removes);
            // a final pass composites the accumulated reflection over the base. The march/blur/
            // temporal run at a quality-resolved fraction of the resolution and the composite
            // upsamples back to full, so live trades reflection resolution for frame rate while
            // export resolves to full (snapshots and exported art are never downscaled). The
            // camera geometry rides params[2..3] byte-for-byte as SSAO's does; the march budget
            // rides the texel row's third slot.
            let steps = Float(resolveSSRSteps(quality))
            let scale = resolveSSRScale(quality)
            let sw = max(1, Int((Double(width) * scale).rounded()))
            let sh = max(1, Int((Double(height) * scale).rounded()))
            let texel = SIMD4<Float>(1 / Float(sw), 1 / Float(sh), steps, Float(fresnel))
            let d = depth ?? .neutral
            let ordinal = ssrOrdinalNext; ssrOrdinalNext += 1
            guard let reflTex = acquireFilterTexture(width: sw, height: sh, pooled: pooled),
                  let reflBlur = acquireFilterTexture(width: sw, height: sh, pooled: pooled),
                  let slot = ssrHistorySlot(ordinal: ordinal, width: sw, height: sh, into: cb),
                  let out = acquireFilterTexture(width: width, height: height, pooled: pooled) else { return nil }
            let hasNormals: Float = normals != nil ? 1 : 0
            // Pass 1: trace the premultiplied reflection.
            encodeEffectFragment("ollin_fx_ssr", inputs: [base, aux, normals ?? aux], output: reflTex,
                                 params: [SIMD4(Float(intensity), Float(maxDistance), Float(thickness), hasNormals),
                                          texel,
                                          SIMD4(d.near, d.far, d.tanHalfFovX, d.tanHalfFovY),
                                          SIMD4(d.principalX, d.principalY, d.isPerspective ? 1 : 0, 0),
                                          SIMD4(Float(edgeFade), Float(roughness), 6, 0)],
                                 into: cb)
            // Pass 2: roughness blur, reflection only (composite flag 0).
            encodeEffectFragment("ollin_fx_ssr_resolve", inputs: [base, reflTex, aux], output: reflBlur,
                                 params: [SIMD4(Float(roughness), 0, 0, 0), texel], into: cb)
            // Pass 3: temporal accumulation into the history back buffer (reading the front +
            // last frame's view·projection), then advance the slot's previous transform.
            let front = slot.flipped ? slot.b : slot.a
            let back  = slot.flipped ? slot.a : slot.b
            let alpha = slot.valid ? Float(resolveSSRAlpha(quality)) : 0
            let iv = d.inverseView, pv = slot.previousViewProjection
            encodeEffectFragment("ollin_fx_ssr_temporal", inputs: [reflBlur, aux, front], output: back,
                                 params: [SIMD4(1 / Float(sw), 1 / Float(sh), alpha, slot.valid ? 1 : 0),
                                          SIMD4(0, 0, 0, 0),
                                          SIMD4(d.near, d.far, d.tanHalfFovX, d.tanHalfFovY),
                                          SIMD4(d.principalX, d.principalY, d.isPerspective ? 1 : 0, 0),
                                          iv.columns.0, iv.columns.1, iv.columns.2, iv.columns.3,
                                          pv.columns.0, pv.columns.1, pv.columns.2, pv.columns.3],
                                 into: cb)
            slot.previousViewProjection = d.viewProjection
            slot.valid = true
            ssrHistoryUsedThisFrame.insert(ordinal)
            // Pass 4: composite the accumulated reflection (upsampled from `back`) over the base.
            encodeEffectFragment("ollin_fx_ssr_composite", inputs: [base, back], output: out,
                                 params: [SIMD4(0, 0, 0, 0),
                                          SIMD4(1 / Float(width), 1 / Float(height), 0, 0)], into: cb)
            return out
        }
    }

    /// Evolve a `SimField` one frame: inject the drawn `seed` onto the `state` (the
    /// front buffer), then run the sim's step fragment N times, ping-ponging between
    /// two scratch textures and landing the last step in `output` (the back buffer).
    /// All fragment passes on the effect pipeline, reading/writing the float field.
    private func runSimulation(_ sim: Sim, state: MTLTexture, seed: MTLTexture, output: MTLTexture,
                               width: Int, height: Int, into cb: MTLCommandBuffer, pooled: Bool) {
        guard let s0 = acquireFilterTexture(width: width, height: height, pooled: pooled),
              let s1 = acquireFilterTexture(width: width, height: height, pooled: pooled) else { return }
        let texel = SIMD4<Float>(1 / Float(width), 1 / Float(height), 0, 0)
        // Inject the seed marks onto the current state (composited by the seed's alpha).
        encodeEffectFragment("ollin_sim_inject", inputs: [state, seed], output: s0,
                             params: [texel], into: cb)
        // Step: read s0, ping-pong s0↔s1 between steps, write the final step into the
        // back buffer. Read and write are always distinct, so there's no in-pass hazard.
        var read = s0
        let steps = max(1, sim.subSteps)
        for i in 0..<steps {
            let write = (i == steps - 1) ? output : (read === s0 ? s1 : s0)
            encodeEffectFragment(sim.stepFragment, inputs: [read], output: write,
                                 params: [texel, sim.params], into: cb)
            read = write
        }
    }

    /// Evolve a fluid `SimField` one frame: splat the drawn `seed` (its colour into the
    /// dye, the block's `force` into the velocity), confine the vorticity, project the
    /// velocity to a divergence-free field with a Jacobi pressure solve + gradient
    /// subtraction, then advect velocity and dye along the flow. The persistent
    /// `velFront`/`dyeFront` are read; the evolved fields land in `velBack`/`dyeBack`
    /// (next frame's fronts). Every intermediate field is pooled scratch — each
    /// `acquireFilterTexture` call returns a distinct texture, so the passes never
    /// alias — and Metal serializes the read-after-write chain across the passes.
    private func runFluid(_ config: Sim.FluidConfig, force: Vector2, seed: MTLTexture,
                          velFront: MTLTexture, velBack: MTLTexture,
                          dyeFront: MTLTexture, dyeBack: MTLTexture,
                          width: Int, height: Int, into cb: MTLCommandBuffer, pooled: Bool) {
        func scratch() -> MTLTexture? { acquireFilterTexture(width: width, height: height, pooled: pooled) }
        guard let velSplat = scratch(), let dyeSplat = scratch(), let curl = scratch(),
              let velVort = scratch(), let div = scratch(), let pA = scratch(), let pB = scratch(),
              let velProj = scratch() else { return }
        let texel = SIMD4<Float>(1 / Float(width), 1 / Float(height), 0, 0)
        let dt = config.dt

        // 1. Splat: push the velocity by `force`, add the dye colour, where marks landed.
        //    `force` is canvas points per frame (the brush's motion); dividing by the
        //    timestep turns it into a velocity, so advecting by `dt` moves the dye at the
        //    brush's own speed.
        let inv = dt > 0 ? 1 / dt : 0
        encodeEffectFragment("ollin_fluid_splat_velocity", inputs: [velFront, seed], output: velSplat,
                             params: [texel, SIMD4(Float(force.x) * inv, Float(force.y) * inv, 0, 0)], into: cb)
        encodeEffectFragment("ollin_fluid_splat_dye", inputs: [dyeFront, seed], output: dyeSplat,
                             params: [texel], into: cb)
        // 2. Vorticity confinement: read the curl of the splatted velocity, push the
        //    swirl back in (buoyancy reads the dye for an optional upward lift).
        encodeEffectFragment("ollin_fluid_curl", inputs: [velSplat], output: curl,
                             params: [texel], into: cb)
        encodeEffectFragment("ollin_fluid_vorticity", inputs: [velSplat, curl, dyeSplat], output: velVort,
                             params: [texel, SIMD4(config.curl, dt, config.buoyancy, 0)], into: cb)
        // 3. Projection: divergence → clear pressure → Jacobi iterations → subtract its
        //    gradient, leaving the velocity incompressible. The ping-pong leaves the
        //    converged pressure in `pRead`.
        encodeEffectFragment("ollin_fluid_divergence", inputs: [velVort], output: div,
                             params: [texel], into: cb)
        clearFloatTexture(pA, into: cb)
        var pRead = pA, pWrite = pB
        for _ in 0..<max(1, config.pressureIterations) {
            encodeEffectFragment("ollin_fluid_pressure", inputs: [pRead, div], output: pWrite,
                                 params: [texel], into: cb)
            swap(&pRead, &pWrite)
        }
        encodeEffectFragment("ollin_fluid_gradient_subtract", inputs: [pRead, velVort], output: velProj,
                             params: [texel], into: cb)
        // 4. Advect velocity by itself, then the dye by the new velocity, into the
        //    persistent back buffers (next frame's fronts).
        encodeEffectFragment("ollin_fluid_advect", inputs: [velProj, velProj], output: velBack,
                             params: [texel, SIMD4(dt, config.velocityDissipation, 0, 0)], into: cb)
        encodeEffectFragment("ollin_fluid_advect", inputs: [velBack, dyeSplat], output: dyeBack,
                             params: [texel, SIMD4(dt, config.densityDissipation, 0, 0)], into: cb)
    }

    /// Fill a generator's layer: one fullscreen fragment pass that reads no input,
    /// just its parameters. `aspect` lets the fragment keep cells square.
    private func encodeGenerator(_ generator: Generator, output: MTLTexture,
                                 width: Int, height: Int, into cb: MTLCommandBuffer) {
        let aspect = Float(width) / Float(max(1, height))
        switch generator.kind {
        case let .shader(shader):
            encodeUserShader(shader, variant: .generator, inputs: [], output: output,
                             width: width, height: height, into: cb)
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

    /// Encode one user-supplied `Shader` pass: compile (and cache) its pipeline, then
    /// draw the present triangle into `output`, binding the input layer(s) as fragment
    /// textures 0…, the user `params` at buffer 0, and the per-frame `OllinShaderUniforms`
    /// at buffer 1. A compile error is reported (stderr once per source, and to the host
    /// sink) and the pass is skipped, so a broken shader never crashes the frame; a
    /// later clean compile clears the reported error.
    private func encodeUserShader(_ shader: Shader, variant: UserShaderVariant,
                                  inputs: [MTLTexture], output: MTLTexture,
                                  width: Int, height: Int,
                                  into cb: MTLCommandBuffer) {
        let (state, hash) = userShaderState(for: shader, variant: variant)
        guard let state else {
            if let err = userShaderErrors[hash] {
                currentUserShaderError = err   // surfaced to the host after the frame
                if !printedShaderErrorHashes.contains(hash) {
                    FileHandle.standardError.write(Data(
                        "Ollin: shader compile failed\n\(err.message)\n".utf8))
                    printedShaderErrorHashes.insert(hash)
                }
            }
            return
        }

        var u = OllinShaderUniforms(
            resolution: SIMD2(Float(width), Float(height)),
            mouse: frameComputeUniforms.mouse,
            time: frameComputeUniforms.time,
            deltaTime: frameComputeUniforms.dt,
            frame: frameComputeUniforms.frameCount,
            paramCount: UInt32(min(shader.params.count, Int(OLLIN_SHADER_PARAM_COUNT))))
        let params = shader.paddedParams

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(state)
        for (i, tex) in inputs.enumerated() { enc.setFragmentTexture(tex, index: i) }
        enc.setFragmentSamplerState(imageSampler, index: 0)
        params.withUnsafeBytes { enc.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
        enc.setFragmentBytes(&u, length: MemoryLayout<OllinShaderUniforms>.stride, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    /// The compiled pipeline for a user shader, built and cached on first use (keyed by
    /// the composed-source hash, returned alongside). Returns `(nil, hash)` on a compile
    /// error, recording it in `userShaderErrors[hash]` so it isn't retried every frame.
    private func userShaderState(for shader: Shader,
                                 variant: UserShaderVariant) -> (MTLRenderPipelineState?, UInt64) {
        let userSource = resolveUserShaderSource(shader)
        let (composed, offset) = MetalRenderer.composeUserShaderSource(
            userSource: userSource, modules: shader.modules, variant: variant)
        let hash = MetalRenderer.fnv1a(composed)
        if let p = userShaderPipelines[hash] { return (p, hash) }
        if userShaderErrors[hash] != nil { return (nil, hash) }   // cached failure
        do {
            let lib: MTLLibrary
            if let cached = userShaderLibraries[hash] { lib = cached }
            else { lib = try device.makeLibrary(source: composed, options: nil); userShaderLibraries[hash] = lib }
            guard let vfn = lib.makeFunction(name: "ollin_user_vertex"),
                  let ffn = lib.makeFunction(name: "ollin_user_fragment") else {
                userShaderErrors[hash] = ShaderCompileError(
                    message: "The shader has no shade(float2 uv, ShaderInfo info) function.", raw: "")
                return (nil, hash)
            }
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vfn
            desc.fragmentFunction = ffn
            desc.rasterSampleCount = 1
            desc.colorAttachments[0].pixelFormat = linearFormat
            let state = try device.makeRenderPipelineState(descriptor: desc)
            userShaderPipelines[hash] = state
            return (state, hash)
        } catch {
            let cleaned = MetalRenderer.cleanShaderDiagnostics(
                (error as NSError).localizedDescription, userLineOffset: offset)
            userShaderErrors[hash] = ShaderCompileError(
                message: cleaned, raw: (error as NSError).localizedDescription)
            return (nil, hash)
        }
    }

    /// Drop every cached user-shader library, pipeline, and error, so the next encode
    /// recompiles from source. Used on a framework-shader reload (the spliced library
    /// may have changed) and when OllinLive reloads a watched user `.metal` file.
    func invalidateUserShaderCaches() {
        userShaderLibraries.removeAll()
        userShaderPipelines.removeAll()
        userShaderErrors.removeAll()
        userShaderSources.removeAll()
        printedShaderErrorHashes.removeAll()
    }

    /// The user's MSL for a shader: the inline source, or the cached contents of its
    /// `.metal` resource (read once per path, re-read after an invalidation so an
    /// edited file hot-reloads).
    private func resolveUserShaderSource(_ shader: Shader) -> String {
        if !shader.source.isEmpty { return shader.source }
        guard !shader.resourcePath.isEmpty else { return "" }
        if let cached = userShaderSources[shader.resourcePath] { return cached }
        let content = (try? String(contentsOfFile: shader.resourcePath, encoding: .utf8)) ?? ""
        userShaderSources[shader.resourcePath] = content
        return content
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
    private func feedbackSlot(for fb: AnyObject, width: Int, height: Int,
                              restState: MTLClearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0),
                              into cb: MTLCommandBuffer) -> FeedbackSlot? {
        let id = ObjectIdentifier(fb)
        if let slot = feedbackSlots[id], slot.owner === fb, slot.w == width, slot.h == height {
            return slot
        }
        guard let a = makeFloatResolve(width: width, height: height),
              let b = makeFloatResolve(width: width, height: height) else { return nil }
        // A freshly allocated pair starts at the owner's rest state (transparent for a
        // feedback layer, the sim's substrate for a SimField) rather than undefined.
        clearFloatTexture(a, color: restState, into: cb)
        clearFloatTexture(b, color: restState, into: cb)
        let slot = FeedbackSlot(a: a, b: b, w: width, h: height, owner: fb)
        feedbackSlots[id] = slot
        return slot
    }

    /// The SSR temporal-history slot for `ordinal`, allocating the ping-pong pair (cleared to
    /// zero, so the first frame's accumulation starts from a clean, reflection-free history) on
    /// first use or a size change. The key is the op ordinal, so a size change (live half-res
    /// versus full-res export) reallocates and reconverges rather than reading a mismatched slot.
    private func ssrHistorySlot(ordinal: Int, width: Int, height: Int,
                                into cb: MTLCommandBuffer) -> SSRHistorySlot? {
        if let slot = ssrHistorySlots[ordinal], slot.w == width, slot.h == height { return slot }
        guard let a = makeFloatResolve(width: width, height: height),
              let b = makeFloatResolve(width: width, height: height) else { return nil }
        let clear = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        clearFloatTexture(a, color: clear, into: cb)
        clearFloatTexture(b, color: clear, into: cb)
        let slot = SSRHistorySlot(a: a, b: b, w: width, h: height)
        ssrHistorySlots[ordinal] = slot
        return slot
    }

    /// `sf`'s persistent fluid slot, allocating the velocity and dye ping-pong pairs
    /// (cleared to a still, dye-free rest state) on first use, a size change, or after
    /// the address was reused by a different field. The fluid analogue of
    /// `feedbackSlot`, keeping two pairs instead of one.
    private func fluidSlot(for sf: AnyObject, width: Int, height: Int,
                           into cb: MTLCommandBuffer) -> FluidSlot? {
        let id = ObjectIdentifier(sf)
        if let slot = fluidSlots[id], slot.owner === sf, slot.w == width, slot.h == height {
            return slot
        }
        guard let velA = makeFloatResolve(width: width, height: height),
              let velB = makeFloatResolve(width: width, height: height),
              let dyeA = makeFloatResolve(width: width, height: height),
              let dyeB = makeFloatResolve(width: width, height: height) else { return nil }
        let rest = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        for tex in [velA, velB, dyeA, dyeB] { clearFloatTexture(tex, color: rest, into: cb) }
        let slot = FluidSlot(velA: velA, velB: velB, dyeA: dyeA, dyeB: dyeB,
                             w: width, h: height, owner: sf)
        fluidSlots[id] = slot
        return slot
    }

    /// Clear `tex` to `color` with an empty render pass (a render target has no
    /// blit fill-to-color), so a freshly allocated persistent texture starts clean
    /// rather than with undefined contents.
    private func clearFloatTexture(_ tex: MTLTexture,
                                   color: MTLClearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0),
                                   into cb: MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = tex
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = color
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

    /// Acquire an MSAA + resolve depth pair for a 3D-holding render target, mirroring
    /// `acquireTargetTextures`. The MSAA buffer is memoryless (tile-only); the resolve
    /// is the sampleable single-sample `depth32Float` the `depth` layer reads from.
    private func acquireTargetDepth(width: Int, height: Int, pooled: Bool) -> (msaa: MTLTexture, resolve: MTLTexture)? {
        guard pooled else {
            guard let msaa = makeDepthMSAA(width: width, height: height),
                  let resolve = makeDepthResolve(width: width, height: height) else { return nil }
            return (msaa, resolve)
        }
        let slot = targetDepthNext; targetDepthNext += 1
        var pool = targetDepthPool[frameIndex]
        if slot < pool.count, pool[slot].w == width, pool[slot].h == height {
            return (pool[slot].msaa, pool[slot].resolve)
        }
        guard let msaa = makeDepthMSAA(width: width, height: height),
              let resolve = makeDepthResolve(width: width, height: height) else { return nil }
        let entry = (msaa, resolve, width, height)
        if slot < pool.count { pool[slot] = entry } else { pool.append(entry) }
        targetDepthPool[frameIndex] = pool
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
                        sdfGroupBuffer: MTLBuffer? = nil, sdfNodeBuffer: MTLBuffer? = nil,
                        sdf3DGroupBuffer: MTLBuffer? = nil, sdf3DNodeBuffer: MTLBuffer? = nil,
                        depthFormat: MTLPixelFormat?, shadowMap: MTLTexture? = nil,
                        shadowCube: MTLTexture? = nil,
                        shadowAccel: MTLAccelerationStructure? = nil,
                        reflectAccel: MTLAccelerationStructure? = nil,
                        reflectGeoOffsets: MTLBuffer? = nil,
                        halfResField: (color: MTLTexture, depth: MTLTexture)? = nil,
                        halfResFieldShadow: MTLTexture? = nil,
                        target passTarget: RenderTarget? = nil) {
        let vertices = drawer.vertices
        let instances = drawer.sdfInstances
        let imageVertices = drawer.imageVertices
        let glyphVertices = drawer.glyphVertices
        let points = drawer.points
        let meshVertices = drawer.meshVertices
        let groups = drawer.sdfGroups
        let nodes = drawer.sdfNodes
        let groups3D = drawer.sdf3DGroups
        let nodes3D = drawer.sdf3DNodes
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
        if !groups.isEmpty, let sdfGroupBuffer {
            groups.withUnsafeBytes { raw in
                sdfGroupBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
        }
        if !nodes.isEmpty, let sdfNodeBuffer {
            nodes.withUnsafeBytes { raw in
                sdfNodeBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
        }
        if !groups3D.isEmpty, let sdf3DGroupBuffer {
            groups3D.withUnsafeBytes { raw in
                sdf3DGroupBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
        }
        if !nodes3D.isEmpty, let sdf3DNodeBuffer {
            nodes3D.withUnsafeBytes { raw in
                sdf3DNodeBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
        }

        var uniforms = Uniforms(viewport: viewport, clipDepth: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

        // 3D camera constants for the points3D batches, bound once at index 2 —
        // distinct from the 2D Uniforms at index 1, so the 2D batches around a 3D
        // one are undisturbed. Built from the camera and the viewport's aspect.
        var uniforms3D: Uniforms3D? = nil
        if let camera = drawer.camera3D {
            var u3 = makeUniforms3D(drawer, camera: camera, viewport: viewport)
            encoder.setVertexBytes(&u3, length: MemoryLayout<Uniforms3D>.stride, index: 2)
            uniforms3D = u3   // the raymarch fragment also reads it (the ray + depth + step budget)
        }

        // 3D mesh lighting (per-frame), bound to the mesh fragment per mesh batch
        // below. `enabled` is 0 when the sketch set no light, so the mesh fragment
        // keeps the byte-identical normal-as-color path.
        var lighting = drawer.makeLighting()
        // Image-based lighting: when an environment baked successfully this frame (resolved
        // by the caller before this pass), light the physically-based materials through its
        // maps. Otherwise leave iblEnabled 0 — the flat-ambient path, byte-identical.
        if lighting.enabled != 0, drawer.environment != nil, currentIBL != nil {
            lighting.iblEnabled = 1
            // The user intensity times the per-environment auto-exposure normalization.
            lighting.iblIntensity = Float(drawer.environment?.intensity ?? 1) * currentIBLNormalization
            lighting.iblMaxMip = Float(currentIBLMaxMip)
            lighting.iblRotation = Float(drawer.environment?.rotation ?? 0)
        } else {
            lighting.iblEnabled = 0   // noLights() stays flat; no environment → flat ambient
        }
        // Skybox backdrop: when the environment shows as the scene's background, fill the
        // frame with it (a fullscreen view-ray cube sample) before the geometry, with depth
        // disabled, so the depth-tested meshes composite in front and a mirror's reflection
        // matches what's behind it. The per-batch loop resets the pipeline + depth state.
        if lighting.iblEnabled != 0, drawer.environment?.showsBackground == true,
           var skyUniforms = uniforms3D, let skyTex = currentIBLSkyboxTexture,
           let skyPipe = try? pipeline(.skybox(depth: depthFormat)) {
            encoder.setRenderPipelineState(skyPipe)
            encoder.setDepthStencilState(nil)   // always-pass, no write
            encoder.setFragmentBytes(&skyUniforms, length: MemoryLayout<Uniforms3D>.stride, index: 0)
            // params.y is the auto-exposure-normalized intensity (shared with the lighting);
            // params.z the backdrop blur as an equirect mip LOD. The blur is the user's value
            // or auto — a gentle soft-focus at 1K easing to sharp at 4K (a magnified low-res
            // backdrop wants softening; the bicubic reconstruction keeps it un-blocky either way).
            let autoBlur = max(0, min(0.15, 0.15 * (4096 - Float(skyTex.width)) / 3072))
            let blur = drawer.environment?.backgroundBlur.map { Float($0) } ?? autoBlur
            var skyParams = SIMD4<Float>(lighting.iblRotation, lighting.iblIntensity, blur * 4.0, 0)
            encoder.setFragmentBytes(&skyParams, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
            encoder.setFragmentTexture(skyTex, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        // Shadows only apply when the shadow pass actually populated a map / structure
        // (the render/image paths); the accumulation/texture paths pass nil, so clear the
        // caster index there and bind the 1×1 / dummy stand-ins so the fragment never
        // reads them. A directional/spot caster populates the 2D map, a point caster the
        // cube — or, on a ray-tracing device, the acceleration structure.
        // Clear the caster only when nothing can use it: a marched SDF field self-shadows
        // analytically (no map), so it keeps the caster index even when the map pass didn't
        // run. Meshes still see no shadow without a map (they'd sample the all-lit dummy).
        if shadowMap == nil && shadowCube == nil && shadowAccel == nil && drawer.sdf3DGroups.isEmpty {
            lighting.shadowLight = -1
        }
        // A ray-traced point caster: switch the fragment to the RT path (shadowKind 2) and
        // resolve the sketch's quality tier to a concrete ray count for this GPU.
        if shadowAccel != nil {
            lighting.shadowKind = 2
            lighting.shadowSamples = resolveShadowSamples(drawer.shadowQualitySetting)
        } else if lighting.shadowLight >= 0 && lighting.shadowKind == 0 {
            // A directional/spot 2D caster runs PCSS (soft shadows): it budgets texture taps,
            // not rays, and the count is hardware-independent (cheap samples on any GPU).
            lighting.shadowSamples = resolveShadowTaps2D(drawer.shadowQualitySetting)
        }
        // Ray-traced reflections: a physically-based metal traces the caster accel for its
        // reflection (replacing the IBL prefilter sample). The flag gates it; off → the
        // byte-identical IBL-prefilter path. The renderer owns the hardware check, so this is
        // set only when the shadow pass actually built a reflection accel on a tracing device.
        if reflectAccel != nil { lighting.rtReflections = 1 }
        // A directional/spot caster has each field render into the 2D map (so meshes receive it
        // from there); a point/ray-traced caster has no map a field can render into, so the lit
        // mesh fragments resolve the cast another way. `fieldCasterCount` > 0 turns that on (only
        // for a point/RT caster with fields); 0 keeps the mesh path byte-identical.
        lighting.fieldCasterCount = resolveFieldCasterCount(lighting, drawer)
        // How they resolve it: sample a precomputed half-res field-shadow texture by screen
        // position (the live RenderQuality path) when one was rendered this frame, else the inline
        // per-pixel march (full-res / export, byte-identical). The viewport scales the screen uv.
        if halfResFieldShadow != nil {
            lighting.fieldShadowMode = 1
            lighting.fieldShadowScale = Float(resolveRaymarchScale(drawer.raymarchQualitySetting))
        }
        let shadowTexture = shadowMap ?? ensureDummyShadowMap()
        let shadowCubeTexture = shadowCube ?? ensureDummyPointShadowMap()
        // When the mesh fragments are compiled with RT shadows, an acceleration structure
        // is always part of their signature, so bind the real one this frame or a dummy
        // that's never traced (the fragment only traces it when shadowKind == 2).
        // Bind one acceleration structure at fragment buffer 3: the fragment traces it for
        // both the point shadow (shadowKind 2) and the reflection (rtReflections); when both
        // are active they're the same object, otherwise whichever is set (a never-traced dummy
        // when neither). The per-geometry offsets at buffer 7 feed the reflection hit fetch.
        let traceAccel = shadowAccel ?? reflectAccel
        let shadowAccelStructure = rayTracedShadows ? (traceAccel ?? ensureDummyShadowAccel()) : nil
        let geoOffsetsBuffer = rayTracedShadows ? (reflectGeoOffsets ?? ensureDummyGeoOffsets()) : nil

        // The strip must be bound whenever the SDF fragment runs (it references
        // the texture even for all-solid frames), so resolve it once per encode.
        let strip = gradientStripTexture(for: drawer.gradientRows)

        let vertexStride = MemoryLayout<OllinVertex>.stride
        let instanceStride = MemoryLayout<SDFInstance>.stride
        let groupStride = MemoryLayout<SDFGroupInstance>.stride
        let group3DStride = MemoryLayout<SDF3DGroupInstance>.stride
        let imageStride = MemoryLayout<OllinImageVertex>.stride
        let pointStride = MemoryLayout<OllinPoint>.stride
        let meshStride = MemoryLayout<OllinMeshVertex>.stride
        // On the half-res raymarch tier all fields composite in one upsample at the first field
        // batch; this flag skips the rest (their geometry already merged into the half-res target).
        var compositedHalfResFields = false
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
                    || batch.kind == .depthScene || batch.kind == .sdfGroup3D || batch.depth != nil
                encoder.setDepthStencilState(wantsDepth ? depthTestState : noDepthState)
                if batch.kind != .points3D && batch.kind != .mesh3D && batch.kind != .depthScene && batch.kind != .sdfGroup3D {
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
            case .sdfGroup:
                // Composed SDF fields: each group is a covering quad whose fragment runs
                // the node VM. The group buffer is offset to this batch's first group; the
                // node buffer is bound whole to the fragment (groups carry an absolute
                // nodeStart), which walks [nodeStart, nodeStart + nodeCount).
                let end = next?.sdfGroupStart ?? groups.count
                let count = end - batch.sdfGroupStart
                guard count > 0, let sdfGroupBuffer, let sdfNodeBuffer else { continue }
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(sdfGroupBuffer, offset: batch.sdfGroupStart * groupStride, index: 0)
                encoder.setFragmentBuffer(sdfNodeBuffer, offset: 0, index: 0)
                // The gradient strip + sampler (a gradient `fill`/`stroke` paints the merged
                // field/outline by field position); bound at 0 like the per-shape SDF path.
                encoder.setFragmentTexture(strip, index: 0)
                encoder.setFragmentSamplerState(imageSampler, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: count)
            case .sdfGroup3D:
                // Half-res tier: the fields were already sphere-traced into the half-res
                // color+depth in the pre-pass, and all of them composite in one upsample at
                // the first field batch (depth still decides mesh occlusion), so skip the rest.
                if let hf = halfResField {
                    if compositedHalfResFields { continue }
                    compositedHalfResFields = true
                    guard let upState = try? pipeline(.raymarchUpsample(depth: depthFormat ?? depthPixelFormat)) else { continue }
                    encoder.setRenderPipelineState(upState)
                    encoder.setFragmentTexture(hf.color, index: 0)
                    encoder.setFragmentTexture(hf.depth, index: 1)
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                    continue
                }
                // Raymarched composed 3D fields: one instanced fullscreen triangle per
                // field, the fragment sphere-tracing it and writing depth so it z-tests
                // against the meshes (state set above). The group buffer is offset to this
                // batch's first field; the node buffer is bound whole (fields carry an
                // absolute nodeStart). Reuses the mesh lighting / material finish / shadow
                // bindings, plus the camera (with its inverse view-projection) for the ray.
                let end = next?.sdf3DGroupStart ?? groups3D.count
                let count = end - batch.sdf3DGroupStart
                guard count > 0, let sdf3DGroupBuffer, let sdf3DNodeBuffer,
                      var u3 = uniforms3D else { continue }
                encoder.setRenderPipelineState(state)
                encoder.setFragmentBuffer(sdf3DGroupBuffer, offset: batch.sdf3DGroupStart * group3DStride, index: 0)
                encoder.setFragmentBuffer(sdf3DNodeBuffer, offset: 0, index: 1)
                encoder.setFragmentBytes(&lighting, length: MemoryLayout<OllinLighting>.stride, index: 2)
                var finish3D = batch.finish
                encoder.setFragmentBytes(&finish3D, length: MemoryLayout<OllinMaterial>.stride, index: 3)
                encoder.setFragmentBytes(&u3, length: MemoryLayout<Uniforms3D>.stride, index: 4)
                encoder.setFragmentTexture(shadowTexture, index: 1)
                encoder.setFragmentTexture(shadowCubeTexture, index: 2)
                if let shadowSampler { encoder.setFragmentSamplerState(shadowSampler, index: 1) }
                if let shadowCubeSampler { encoder.setFragmentSamplerState(shadowCubeSampler, index: 2) }
                // The gradient strip + sampler (a gradient `fill` paints the field by screen
                // position); bound at 0, free here since the shadow textures take 1/2.
                encoder.setFragmentTexture(strip, index: 0)
                encoder.setFragmentSamplerState(imageSampler, index: 0)
                // The mesh acceleration structure at buffer 5 so a marched field receives a mesh's
                // cast shadow under a ray-traced point caster (it traces toward the light, the
                // reverse of the cast). A dummy when shadowKind != 2, never traced; the cube path
                // (shadowKind 1) needs nothing, its cube + sampler are already bound at 2.
                if let accel = shadowAccelStructure {
                    encoder.useResource(accel, usage: .read, stages: .fragment)
                    encoder.setFragmentAccelerationStructure(accel, bufferIndex: 5)
                }
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3, instanceCount: count)
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
                    // Ray-traced reflections: the flat mesh buffer (whole, offset 0, for absolute
                    // indexing) at fragment buffer 6 and the per-geometry base-vertex offsets at 7,
                    // so a physically-based fragment can fetch a reflection hit's triangle. Bound
                    // whenever the fragment is RT-compiled (a dummy offsets buffer when reflections
                    // are off; `lighting.rtReflections` gates the read). Both feed `ollin_rt_reflection`.
                    if rayTracedShadows {
                        encoder.setFragmentBuffer(meshBuffer, offset: 0, index: 6)
                    }
                    if let geoOffsetsBuffer {
                        encoder.setFragmentBuffer(geoOffsetsBuffer, offset: 0, index: 7)
                    }
                    // The SDF field group + nodes (buffers 4/5) so a lit mesh can march them
                    // toward a point/ray-traced caster (a field's cast shadow). Always allocated
                    // (min one element) for a 3D frame; `lighting.fieldCasterCount` gates the
                    // march, so this is inert (and byte-identical) when there are no fields.
                    if let sdf3DGroupBuffer { encoder.setFragmentBuffer(sdf3DGroupBuffer, offset: 0, index: 4) }
                    if let sdf3DNodeBuffer { encoder.setFragmentBuffer(sdf3DNodeBuffer, offset: 0, index: 5) }
                    // The half-res field-shadow texture (the live RenderQuality path) the fragment
                    // samples when `lighting.fieldShadowMode == 1`; a never-sampled stand-in (the
                    // gradient `strip`) otherwise, so the declared texture is always bound.
                    encoder.setFragmentTexture(halfResFieldShadow ?? strip, index: 3)
                    // The image-based-lighting maps the physically-based fragment samples when
                    // `lighting.iblEnabled == 1`: the irradiance + prefiltered cubes (tex 4/5)
                    // and the BRDF LUT (tex 6). Never-sampled stand-ins (a 1×1 cube, the
                    // gradient strip) otherwise, so the declared textures are always bound.
                    if iblPlaceholderCube == nil { iblPlaceholderCube = makeCubeTexture(face: 1, mipped: false) }
                    encoder.setFragmentTexture(currentIBLIrradiance ?? iblPlaceholderCube, index: 4)
                    encoder.setFragmentTexture(currentIBLPrefilter ?? iblPlaceholderCube, index: 5)
                    encoder.setFragmentTexture(iblBRDFLUTTexture ?? strip, index: 6)
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

    /// A single-sample `depth32Float` the MSAA depth attachment of a 3D render target
    /// resolves into, sampled afterward by the depth-normalize pass. `.shaderRead` so
    /// it's sampleable, `.private` since it lives only on the GPU.
    private func makeDepthResolve(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: depthPixelFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }

    /// Turn a 3D render target's resolved clip-space depth into a sampleable gray
    /// layer (0 near … 1 far): one fullscreen pass that linearizes the depth over the
    /// camera's near/far and encodes it so the perceptual depth-of-field decode reads
    /// back exactly that value (so `ollin_fx_depth_of_field` needs no change). A nil
    /// camera (a non-metric depth scene wrote normalized depth itself) passes through.
    private func normalizeDepth(_ depth: MTLTexture, camera: Camera3D?,
                                width: Int, height: Int,
                                into cb: MTLCommandBuffer, pooled: Bool) -> MTLTexture? {
        guard let output = acquireFilterTexture(width: width, height: height, pooled: pooled) else { return nil }
        let near = Float(camera?.near ?? 0)
        let far = Float(camera?.far ?? 1)
        // Orthographic depth is already linear in distance; perspective and the
        // intrinsic (pinhole) projection are not, so the shader inverts the curve.
        // No camera → the depth is already normalized, so pass it straight through.
        var perspective: Float = 1
        if camera == nil { perspective = 0 }
        else if case .orthographic = camera?.projection { perspective = 0 }
        encodeEffectFragment("ollin_fx_depth_normalize", inputs: [depth], output: output,
                             params: [SIMD4(near, far, perspective, 0)], into: cb)
        return output
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
        /// Ray-traced reflections: the caster acceleration structure to trace reflection
        /// rays against (the same object as `accel` when an RT point caster is also present)
        /// and the per-geometry base-vertex offsets to fetch a hit triangle from the flat
        /// mesh buffer. Set only when `rayTracedReflections()` is on and the device can trace.
        var reflectAccel: MTLAccelerationStructure?
        var reflectGeoOffsets: MTLBuffer?
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
                                  meshBuffer: MTLBuffer?,
                                  sdf3DGroupBuffer: MTLBuffer? = nil,
                                  sdf3DNodeBuffer: MTLBuffer? = nil) -> ShadowMaps {
        let lighting = drawer.makeLighting()
        let meshVertices = drawer.meshVertices
        // Ray-traced reflections want a caster acceleration structure even when no light casts
        // a shadow; build it once and reuse it for both. (A non-RT device can't reflect, so
        // `wantReflect` is already false there and the shadow paths stay byte-identical.)
        let wantReflect = drawer.rayTracedReflectionsEnabled && rayTracedShadows
        guard lighting.enabled != 0, !meshVertices.isEmpty, let meshBuffer,
              lighting.shadowLight >= 0 || wantReflect else { return ShadowMaps() }

        meshVertices.withUnsafeBytes { raw in
            meshBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }

        // A point caster: ray-trace it on a capable device (exact, no cube/depth-compare
        // artifacts), else render the omnidirectional mid-point cube. The one accel serves
        // both the shadow (shadowKind 2) and, when on, reflections.
        if lighting.shadowLight >= 0, lighting.shadowKind == 1 {
            if rayTracedShadows,
               let built = buildShadowAccel(drawer, into: commandBuffer, meshBuffer: meshBuffer) {
                return ShadowMaps(accel: built.accel,
                                  reflectAccel: wantReflect ? built.accel : nil,
                                  reflectGeoOffsets: wantReflect ? built.offsets : nil)
            }
            let cube = encodePointShadowPass(drawer, lighting: lighting,
                                             into: commandBuffer, meshBuffer: meshBuffer)
            return ShadowMaps(cube: cube)
        }

        // Reflections with no shadow-casting light: build only the reflection accel.
        if lighting.shadowLight < 0 {
            guard let built = buildShadowAccel(drawer, into: commandBuffer, meshBuffer: meshBuffer)
            else { return ShadowMaps() }
            return ShadowMaps(reflectAccel: built.accel, reflectGeoOffsets: built.offsets)
        }

        // A directional/spot caster's 2D map below, plus a reflection accel when reflections
        // are on (both precede the main geometry pass, so trace order is satisfied either way).
        let reflect = wantReflect ? buildShadowAccel(drawer, into: commandBuffer, meshBuffer: meshBuffer) : nil
        guard let shadowMap = ensureShadowMap(),
              let shadowPipeline = try? pipeline(.meshShadow) else {
            return ShadowMaps(reflectAccel: reflect?.accel, reflectGeoOffsets: reflect?.offsets)
        }
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
        // Marched 3D fields cast into the same map: sphere-trace each from the light's POV and
        // write its depth, z-tested against the mesh casters already there, so meshes receive a
        // field's shadow too. The field keeps its analytic self-shadow in the main pass and
        // doesn't sample this map, so there's no double-shadowing (directional/spot only).
        encodeFieldShadowCasters(drawer, encoder: encoder, lighting: lighting,
                                 groupBuffer: sdf3DGroupBuffer, nodeBuffer: sdf3DNodeBuffer)
        encoder.endEncoding()
        return ShadowMaps(twoD: shadowMap, reflectAccel: reflect?.accel, reflectGeoOffsets: reflect?.offsets)
    }

    /// Render the marched 3D fields into the active 2D shadow map (directional/spot). Each field
    /// is one instanced fullscreen triangle whose fragment sphere-traces it from the light's
    /// point of view and writes the hit's light-clip depth (depth-only, z-tested against the
    /// mesh casters already in the map). A no-op when the frame has no fields or no buffers.
    private func encodeFieldShadowCasters(_ drawer: Drawer, encoder: MTLRenderCommandEncoder,
                                          lighting: OllinLighting,
                                          groupBuffer: MTLBuffer?, nodeBuffer: MTLBuffer?) {
        let groups3D = drawer.sdf3DGroups
        let nodes3D = drawer.sdf3DNodes
        guard !groups3D.isEmpty, !nodes3D.isEmpty,
              let groupBuffer, let nodeBuffer,
              let fieldPipeline = try? pipeline(.raymarchShadow) else { return }
        // Fill the field buffers here: the shadow pass runs before the main encode (which
        // re-uploads the same bytes), so the GPU sees the geometry when it marches the map.
        groups3D.withUnsafeBytes { raw in
            groupBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
        nodes3D.withUnsafeBytes { raw in
            nodeBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
        let casterSteps = resolveRaymarchSteps(drawer.raymarchQualitySetting).march
        var u = OllinRaymarchShadowUniforms(
            lightViewProjection: lighting.lightViewProjection,
            inverseLightViewProjection: simd_inverse(lighting.lightViewProjection),
            raymarchSteps: Float(casterSteps))
        encoder.setRenderPipelineState(fieldPipeline)
        encoder.setFragmentBuffer(groupBuffer, offset: 0, index: 0)
        encoder.setFragmentBuffer(nodeBuffer, offset: 0, index: 1)
        encoder.setFragmentBytes(&u, length: MemoryLayout<OllinRaymarchShadowUniforms>.stride, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3,
                               instanceCount: groups3D.count)
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
    /// A `Quality` tier scales with the hardware (a dedicated-RT GPU affords more rays of a
    /// software-RT one at the same tier, so better hardware lifts the default quality on its
    /// own); an absolute count passes through unchanged. Frame-rate-band tiers (the software-RT
    /// M2 column is measured at the live drawable via `Scripts/benchmark.sh shadows`):
    /// `.performance` ~120fps (2 rays = 149fps), `.default` 60–90fps (4 = 88fps), `.detail`
    /// 15–30fps (16 = 25fps). The hw (apple9+) column is an estimate until benchmarked there.
    private func resolveShadowSamples(_ setting: ShadowQualitySetting) -> Int32 {
        switch setting {
        case .absolute(let n):
            return Int32(n)
        case .tier(let quality):
            let hw = hasHardwareRayTracing
            switch effectiveQuality(quality) {
            case .performance: return hw ? 8  : 2
            case .default:     return hw ? 16 : 4
            case .detail:      return hw ? 48 : 16
            }
        }
    }

    /// Resolve the soft-shadow quality intent to a PCSS **tap budget** for the directional/spot
    /// 2D maps (shared between the blocker search and the variable-kernel PCF). Unlike the
    /// ray-traced path, these are cheap texture samples that run on every GPU, so the budget is
    /// hardware-independent (a tier maps to a fixed count, not a per-GPU one). Export/headless
    /// lands on `.detail` via `effectiveQuality` for the creamiest penumbra; live stays at
    /// `.default`. An absolute `shadowSamples(_:)` is clamped to a sane disk range.
    private func resolveShadowTaps2D(_ setting: ShadowQualitySetting) -> Int32 {
        switch setting {
        case .absolute(let n):
            return Int32(min(max(n, 12), 96))
        case .tier(let quality):
            switch effectiveQuality(quality) {
            case .performance: return 24
            case .default:     return 40
            case .detail:      return 72
            }
        }
    }

    /// An exact bokeh tap count that, when set, overrides the resolved `.defocus` quality
    /// tier — the hook `Scripts/benchmark-dof.sh` uses to sweep tap counts and measure the
    /// real per-GPU frame cost. `nil` in normal use.
    var dofTapsOverride: Int?

    /// The fallback quality for a feature the sketch left at `.default` (i.e. didn't explicitly
    /// dial). `.default` for the live window (the frame-rate-safe tier); `.detail` for export /
    /// headless (no frame-rate pressure, so best quality), overridable by `--render-quality`. A
    /// sketch that sets a *non-default* tier (`.performance`/`.detail`, or an absolute count) is
    /// treated as explicit and respected as-is on every path, so `.default` doubles as "automatic".
    var automaticQuality: RenderQuality = .default

    /// Map a feature's requested quality through the automatic fallback: `.default` means
    /// "unset", so it resolves to `automaticQuality`; anything else is an explicit choice and
    /// passes through. (Live keeps `.default` as `.default`; export lifts it to `.detail`.)
    private func effectiveQuality(_ q: RenderQuality) -> RenderQuality {
        q == .default ? automaticQuality : q
    }

    /// Resolve a `.ambientOcclusion` quality tier to a gather sample count. Fewer samples
    /// than the bokeh gather (each reconstructs a view-space position and accumulates a
    /// scalar, not a colour), distributed over the same smooth golden-angle spiral so the
    /// occlusion needs no noise texture or separate blur.
    private func resolveSSAOSamples(_ quality: RenderQuality) -> Int {
        if let override = ssaoSamplesOverride { return max(4, min(override, 256)) }
        // Frame-rate-band tiers (measured on M2 at 1080² via `Scripts/benchmark.sh ssao`):
        // `.performance` ~120fps headroom (64 = 192fps), `.default` 60–90fps with headroom
        // (128 = 117fps). SSAO is cheap enough that reaching `.detail`'s 15–30fps target would
        // need ~600+ samples (far past where the occlusion estimate stops improving), so
        // `.detail` is capped at the useful ceiling (256 = 66fps), not the frame-rate band.
        switch effectiveQuality(quality) {
        case .performance: return 64
        case .default:     return 128
        case .detail:      return 256
        }
    }

    /// An exact ambient-occlusion sample count overriding the resolved `.ambientOcclusion`
    /// quality tier, the sweep hook mirroring `dofTapsOverride`. `nil` in normal use.
    var ssaoSamplesOverride: Int?

    /// Resolve a `.screenSpaceReflections` quality tier to a coarse-march step count. The DDA
    /// covers the *whole* reflection ray in this many steps (the stride scales with the ray's
    /// pixel span), so the reach is resolution-independent and this is purely a precision knob:
    /// fewer coarse steps trade hit precision (before the binary refinement) for frame rate.
    /// GPU-independent, like the raymarch resolution. Tune later via `Scripts/benchmark.sh ssr`.
    private func resolveSSRSteps(_ quality: RenderQuality) -> Int {
        if let override = ssrStepsOverride { return max(8, min(override, 1024)) }
        switch effectiveQuality(quality) {
        case .performance: return 128
        case .default:     return 256
        case .detail:      return 512
        }
    }

    /// An exact SSR march-step count overriding the resolved `.screenSpaceReflections`
    /// quality tier, the sweep hook mirroring `ssaoSamplesOverride`. `nil` in normal use.
    var ssrStepsOverride: Int?

    /// Resolve a `.screenSpaceReflections` quality tier to the fraction of the resolution the
    /// march/blur/temporal passes run at (the composite upsamples back to full). Live trades
    /// reflection resolution for frame rate; export resolves to full (1.0) so exported art and
    /// snapshots are never downscaled. Mirrors `resolveRaymarchScale`.
    private func resolveSSRScale(_ quality: RenderQuality) -> Double {
        if let s = ssrScaleOverride { return min(1.0, max(0.1, s)) }
        switch effectiveQuality(quality) {
        case .detail:      return 1.0
        case .default:     return 1.0    // full-res by default: reflections stay sharp + clean
        case .performance: return 0.5    // half-res only when trading quality for frame rate
        }
    }

    /// A scale fraction overriding the resolved SSR tier, the sweep hook for the half-res win
    /// (`Scripts/benchmark.sh ssr`). `nil` in normal use.
    var ssrScaleOverride: Double?

    /// Resolve a `.screenSpaceReflections` quality tier to the temporal history weight (the
    /// exponential-moving-average factor): more accumulation at higher tiers (steadier, slower to
    /// react), lighter at `.performance`. Reprojection + neighborhood clamping keep it responsive.
    private func resolveSSRAlpha(_ quality: RenderQuality) -> Double {
        switch effectiveQuality(quality) {
        case .detail:      return 0.92
        case .default:     return 0.88
        case .performance: return 0.80
        }
    }

    /// Resolve a `.defocus` quality tier to a bokeh tap count, hardware-relative (richer on a
    /// dedicated-RT GPU). The software-RT (M1/M2) column is measured (`Scripts/benchmark.sh dof`
    /// on an M2 at 1080²: 96 taps hold ~120fps, 192 hold 60–90fps, 512 hold 15–30fps); the
    /// dedicated-RT column is a ~1.5× estimate until the benchmark is run on such a GPU (M3+).
    private func resolveDofTaps(_ quality: RenderQuality) -> Int {
        if let override = dofTapsOverride { return max(8, min(override, 1024)) }
        // The tiers target frame-rate bands (measured on M2 at the 1080² `.defocus` layer via
        // `Scripts/benchmark.sh dof`): `.performance` ~120fps (96 taps = 126fps), `.default`
        // 60–90fps (192 = 69fps), `.detail` 15–30fps (512 = 27fps). The hw column (apple9+) is a
        // ~1.5× estimate until benchmarked on such a GPU.
        let hw = hasHardwareRayTracing
        switch effectiveQuality(quality) {
        case .performance: return hw ? 144 : 96
        case .default:     return hw ? 288 : 192
        case .detail:      return hw ? 768 : 512
        }
    }

    /// An exact camera-march step count overriding the resolved `drawSDF3D` quality tier: the
    /// hook `Scripts/benchmark.sh raymarch` sweeps to measure the real per-GPU march cost.
    /// `nil` in normal use. (The shadow budget tracks it at the same 3/8 ratio.)
    var raymarchStepsOverride: Int?

    /// Resolve a raymarch quality setting to the camera-march and self-shadow step budgets.
    /// The `.default` tier returns the pre-dial constants (128 / 48) **exactly**, so a sketch
    /// that sets no quality renders byte-identically to before. The step budget is a fidelity
    /// (surface-resolution) knob, not a hardware-RT one, so the tiers are GPU-independent; the
    /// `.performance` *render-scale* drop (`resolveRaymarchScale`) is the bigger lever.
    private func resolveRaymarchSteps(_ setting: RaymarchQualitySetting) -> (march: Int32, shadow: Int32) {
        func pair(_ march: Int) -> (Int32, Int32) {
            let m = max(16, min(march, 512))
            return (Int32(m), Int32(max(8, m * 3 / 8)))   // shadow ≈ 3/8 of the march (128→48)
        }
        if let override = raymarchStepsOverride { return pair(override) }
        switch setting {
        case .absolute(let n): return pair(n)
        case .resolution: return (128, 48)   // a custom-resolution field keeps the default march budget
        case .tier(let quality):
            switch effectiveQuality(quality) {
            case .performance: return (64, 24)
            case .default:     return (128, 48)   // live `.default`; export lifts to `.detail`
            case .detail:      return (192, 72)
            }
        }
    }

    /// The internal live-preview render scale (a fraction of full resolution) for the raymarch,
    /// the dominant lever: the fullscreen sphere-tracer's cost is bound to pixel count (step
    /// count barely moves it), so the tiers scale resolution: `.detail` full (1.0), `.default`
    /// half (0.5, ¼ the pixels), `.performance` quarter (0.25, 1/16 the pixels), or an exact
    /// fraction from `raymarchResolution`. An upsample composites it back at full res. **This
    /// applies to the live preview only:** a `.detail` export marches at full resolution (scale
    /// 1.0 skips the pre-pass), so `--export`/snapshots are never downscaled and stay
    /// byte-identical. An absolute step count also marches at full resolution.
    private func resolveRaymarchScale(_ setting: RaymarchQualitySetting) -> Double {
        switch setting {
        case .absolute: return 1.0
        case .resolution(let f): return min(1.0, max(0.1, f))   // an exact fraction (clamped)
        case .tier(let q):
            switch effectiveQuality(q) {
            case .detail:      return 1.0
            case .default:     return 0.5
            case .performance: return 0.25
            }
        }
    }

    /// Build the per-frame 3D camera constants (used by the points/mesh/raymarch pipelines),
    /// including the dial-resolved march-step budget. `nil` when no 3D camera is active. Shared
    /// by the main `encode` and the half-res raymarch pre-pass so they can't drift.
    private func makeRaymarchUniforms3D(_ drawer: Drawer, viewport: SIMD2<Float>) -> Uniforms3D? {
        guard let camera = drawer.camera3D else { return nil }
        let aspect = viewport.y > 0 ? Double(viewport.x / viewport.y) : 1
        let proj = camera.projectionMatrix(aspect: aspect)
        let steps = resolveRaymarchSteps(drawer.raymarchQualitySetting)
        return Uniforms3D(view: camera.viewMatrix, projection: proj,
                          inverseViewProjection: simd_inverse(proj * camera.viewMatrix),
                          viewport: viewport,
                          raymarchSteps: SIMD2<Float>(Float(steps.march), Float(steps.shadow)))
    }

    /// Resolve this frame's lighting + shadow bindings (caster index, RT vs map kind, and the
    /// real-or-dummy shadow textures), the block shared by the main `encode` and the half-res
    /// raymarch pre-pass so a marched field shades identically at half resolution. `shadowAccel`
    /// is the frame's acceleration structure (RT point shadows), nil otherwise.
    private func resolveFieldLighting(_ drawer: Drawer, shadowMap: MTLTexture?, shadowCube: MTLTexture?,
                                      shadowAccelPresent: Bool)
        -> (lighting: OllinLighting, shadowTexture: MTLTexture?, shadowCubeTexture: MTLTexture?) {
        var lighting = drawer.makeLighting()
        if shadowMap == nil && shadowCube == nil && !shadowAccelPresent && drawer.sdf3DGroups.isEmpty {
            lighting.shadowLight = -1
        }
        if shadowAccelPresent {
            lighting.shadowKind = 2
            lighting.shadowSamples = resolveShadowSamples(drawer.shadowQualitySetting)
        } else if lighting.shadowLight >= 0 && lighting.shadowKind == 0 {
            lighting.shadowSamples = resolveShadowTaps2D(drawer.shadowQualitySetting)
        }
        return (lighting, shadowMap ?? ensureDummyShadowMap(), shadowCube ?? ensureDummyPointShadowMap())
    }

    /// Sphere-trace every `.normal`-blend field batch into the cached half-resolution color +
    /// depth targets (the `.performance` raymarch tier). Returns the targets for the main pass
    /// to upsample + composite, or `nil` when half-res doesn't apply (full-res tier, no fields,
    /// or any field uses a non-`.normal` blend, which would not composite premultiplied-over,
    /// so the whole frame falls back to the full-res inline march). The field batches share one
    /// depth-tested target, so they occlude one another exactly as in the full-res pass; each is
    /// drawn with its own material, the same fragment + bindings as the inline path.
    private func encodeRaymarchHalfRes(_ drawer: Drawer, into cb: MTLCommandBuffer,
                                       groupBuffer: MTLBuffer?, nodeBuffer: MTLBuffer?,
                                       uniforms3D: Uniforms3D, lighting: OllinLighting,
                                       shadowTexture: MTLTexture?, shadowCubeTexture: MTLTexture?,
                                       shadowAccel: MTLAccelerationStructure? = nil,
                                       fullWidth: Int, fullHeight: Int)
        -> (color: MTLTexture, depth: MTLTexture)? {
        let scale = resolveRaymarchScale(drawer.raymarchQualitySetting)
        let groups3D = drawer.sdf3DGroups
        guard scale < 1.0, !groups3D.isEmpty, let groupBuffer, let nodeBuffer else { return nil }
        for b in drawer.batches where b.kind == .sdfGroup3D && b.blendMode != .normal { return nil }

        let w = max(1, Int((Double(fullWidth) * scale).rounded()))
        let h = max(1, Int((Double(fullHeight) * scale).rounded()))
        if halfResSize != (w, h) || halfResColor == nil || halfResDepth == nil {
            guard let c = makeHalfResColor(width: w, height: h),
                  let d = makeHalfResDepth(width: w, height: h) else { return nil }
            halfResColor = c; halfResDepth = d; halfResSize = (w, h)
        }
        guard let color = halfResColor, let depth = halfResDepth,
              let pipe = try? pipeline(.raymarchHalfRes(depth: depthPixelFormat)) else { return nil }

        // Upload the field buffers here: the pre-pass runs before the main encode (which
        // re-uploads the same bytes), and when the frame casts no shadow nothing else has
        // uploaded them yet, so the GPU would otherwise march stale geometry.
        groups3D.withUnsafeBytes { groupBuffer.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        let nodes3D = drawer.sdf3DNodes
        if !nodes3D.isEmpty {
            nodes3D.withUnsafeBytes { nodeBuffer.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = color
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)  // over transparent → premultiplied
        pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1.0
        pass.depthAttachment.storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        enc.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(w), height: Double(h), znear: 0, zfar: 1))
        enc.setRenderPipelineState(pipe)
        enc.setDepthStencilState(depthTestState)
        var u3 = uniforms3D
        var lit = lighting
        enc.setFragmentBuffer(nodeBuffer, offset: 0, index: 1)
        enc.setFragmentBytes(&lit, length: MemoryLayout<OllinLighting>.stride, index: 2)
        enc.setFragmentBytes(&u3, length: MemoryLayout<Uniforms3D>.stride, index: 4)
        enc.setFragmentTexture(shadowTexture, index: 1)
        enc.setFragmentTexture(shadowCubeTexture, index: 2)
        if let shadowSampler { enc.setFragmentSamplerState(shadowSampler, index: 1) }
        if let shadowCubeSampler { enc.setFragmentSamplerState(shadowCubeSampler, index: 2) }
        enc.setFragmentTexture(gradientStripTexture(for: drawer.gradientRows), index: 0)
        enc.setFragmentSamplerState(imageSampler, index: 0)
        // The mesh acceleration structure at buffer 5 (RT point shadows received by the field),
        // matching the main pass; a dummy when shadowKind != 2, never traced.
        if let accel = rayTracedShadows ? (shadowAccel ?? ensureDummyShadowAccel()) : nil {
            enc.useResource(accel, usage: .read, stages: .fragment)
            enc.setFragmentAccelerationStructure(accel, bufferIndex: 5)
        }

        let group3DStride = MemoryLayout<SDF3DGroupInstance>.stride
        let batches = drawer.batches
        for i in batches.indices {
            let batch = batches[i]
            guard batch.kind == .sdfGroup3D else { continue }
            let next = i + 1 < batches.count ? batches[i + 1] : nil
            let end = next?.sdf3DGroupStart ?? groups3D.count
            let count = end - batch.sdf3DGroupStart
            guard count > 0 else { continue }
            enc.setFragmentBuffer(groupBuffer, offset: batch.sdf3DGroupStart * group3DStride, index: 0)
            var finish = batch.finish
            enc.setFragmentBytes(&finish, length: MemoryLayout<OllinMaterial>.stride, index: 3)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3, instanceCount: count)
        }
        enc.endEncoding()
        return (color, depth)
    }

    /// The number of raymarched SDF fields casting onto meshes under a point/ray-traced caster
    /// (0 for a mesh-only or directional/spot scene, the byte-identical mesh path). Shared by the
    /// main encode and the half-res field-shadow pre-pass so both agree on whether the cast is on.
    private func resolveFieldCasterCount(_ lighting: OllinLighting, _ drawer: Drawer) -> Int32 {
        (lighting.shadowLight >= 0 && lighting.shadowKind != 0 && !drawer.sdf3DGroups.isEmpty)
            ? Int32(drawer.sdf3DGroups.count) : 0
    }

    /// The point/RT field-cast shadow is per-receiver-pixel (the lit mesh fragments march the field
    /// toward the light), which is GPU-heavy on a screen-filling receiver. The live RenderQuality
    /// path computes it once at reduced resolution here (re-rendering the receiver meshes,
    /// depth-tested so the front surface's factor wins, with a fragment that outputs only the
    /// field-shadow factor), and the full-res mesh pass samples it (`fieldShadowMode == 1`). `nil`
    /// at the full-res tier (`.detail`/export march inline → byte-identical), with no fields, or no
    /// point/RT caster. Mirrors `encodeRaymarchHalfRes` (same scale dial, same live-only gating).
    /// Build the 3D camera constants (`Uniforms3D`) for a camera + viewport: the same
    /// view / projection / inverse the geometry pass binds at vertex index 2. Shared with
    /// the inline build in `encode` so the auxiliary mesh passes (the normal G-buffer)
    /// build them identically.
    private func makeUniforms3D(_ drawer: Drawer, camera: Camera3D, viewport: SIMD2<Float>) -> Uniforms3D {
        let aspect = viewport.y > 0 ? Double(viewport.x / viewport.y) : 1
        let proj = camera.projectionMatrix(aspect: aspect)
        let steps = resolveRaymarchSteps(drawer.raymarchQualitySetting)
        return Uniforms3D(view: camera.viewMatrix, projection: proj,
                          inverseViewProjection: simd_inverse(proj * camera.viewMatrix),
                          viewport: viewport,
                          raymarchSteps: SIMD2<Float>(Float(steps.march), Float(steps.shadow)))
    }

    /// The mesh-normal G-buffer pass: re-render a target's meshes MSAA + depth-tested,
    /// writing each surface's view-space normal so the ambient-occlusion combine reads a
    /// true normal instead of one reconstructed from depth (which is ambiguous at a concave
    /// seam and flickers as the camera turns). MSAA (not single-sample) then a depth-aware
    /// resolve (`ollin_mesh_normal_resolve`, front-surface samples only): a silhouette pixel
    /// carries a coverage-weighted mesh normal (renormalized on read) that matches the
    /// `.min`-resolved scene depth the SSAO reconstructs position from, instead of toggling to
    /// the cleared background sub-pixel (which shimmered the edge AO) or blending a farther
    /// surface's normal across an internal silhouette (which dashed it). A dedicated mesh-only
    /// re-encode, not a second attachment on the shared geometry pass (which would force
    /// every 2D pipeline in that pass to be MRT-compatible). Runs only when the target asked
    /// for normals (`needsNormals`, set when an `.ambientOcclusion` combine reads a 3D
    /// target), so a frame without AO pays nothing and is byte-identical. Returns the filled
    /// normal texture at the target's pixel size, or nil when there's no mesh to draw.
    private func encodeMeshNormals(_ drawer: Drawer, into cb: MTLCommandBuffer,
                                   meshBuffer: MTLBuffer?, width: Int, height: Int,
                                   pooled: Bool) -> MTLTexture? {
        guard let camera = drawer.camera3D, let meshBuffer,
              drawer.batches.contains(where: { $0.kind == .mesh3D }),
              let resolve = acquireFilterTexture(width: width, height: height, pooled: pooled),
              let color = makeReadableFloatMSAA(width: width, height: height),
              let depth = makeReadableDepthMSAA(width: width, height: height),
              let pipe = try? pipeline(.meshNormal(depth: depthPixelFormat)) else { return nil }

        // MSAA into a stored target, then a *depth-aware* resolve (`ollin_mesh_normal_resolve`)
        // into the single-sample `resolve` texture the SSAO samples, not the hardware box
        // average, which at an internal silhouette (a near box's edge against a farther box)
        // would blend the front and back surface normals into a tilted one that dashes the AO.
        // The custom resolve averages only the front surface's samples, so the stored normal
        // matches the `.min`-resolved scene depth the SSAO reconstructs position from; the
        // per-sample normal + depth therefore both `.store` (read back in the resolve pass).
        // The resolved alpha is the front-surface coverage (0 = a pixel no mesh touched).
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = color
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)  // alpha 0 = no normal here
        pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1.0
        pass.depthAttachment.storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        enc.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(width), height: Double(height), znear: 0, zfar: 1))
        enc.setRenderPipelineState(pipe)
        enc.setDepthStencilState(depthTestState)
        var u3 = makeUniforms3D(drawer, camera: camera, viewport: SIMD2(Float(width), Float(height)))
        enc.setVertexBytes(&u3, length: MemoryLayout<Uniforms3D>.stride, index: 2)

        let meshStride = MemoryLayout<OllinMeshVertex>.stride
        let meshCount = drawer.meshVertices.count
        let batches = drawer.batches
        for i in batches.indices {
            let batch = batches[i]
            guard batch.kind == .mesh3D else { continue }
            // Wireframe meshes have no surface to occlude; their sparse edge fragments
            // would write stray normals, so skip them. Solid / textured / matcap all
            // carry a real per-vertex normal and feed the buffer (the normal shader
            // ignores material).
            if batch.meshWireframe { continue }
            let next = i + 1 < batches.count ? batches[i + 1] : nil
            let end = next?.meshStart ?? meshCount
            let count = end - batch.meshStart
            guard count > 0 else { continue }
            enc.setVertexBuffer(meshBuffer, offset: batch.meshStart * meshStride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
        }
        enc.endEncoding()

        // Depth-aware resolve: front-surface-only normal average (see above), into `resolve`.
        encodeEffectFragment("ollin_mesh_normal_resolve", inputs: [color, depth],
                             output: resolve, params: [], into: cb)
        return resolve
    }

    /// A multisample `linearFormat` colour target that is *also* shader-readable (per-sample,
    /// as a `texture2d_ms`), for the depth-aware mesh-normal resolve. `.private` + `.store`,
    /// unlike the geometry path's memoryless MSAA (which is hardware-resolved within its pass).
    private func makeReadableFloatMSAA(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: linearFormat, width: width, height: height, mipmapped: false)
        desc.textureType = .type2DMultisample
        desc.sampleCount = sampleCount
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }

    /// A multisample depth target that is shader-readable per-sample (as a `depth2d_ms`), so
    /// the normal resolve can tell the front surface's samples from a farther surface's.
    private func makeReadableDepthMSAA(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: depthPixelFormat, width: width, height: height, mipmapped: false)
        desc.textureType = .type2DMultisample
        desc.sampleCount = sampleCount
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }

    private func encodeFieldShadowHalfRes(_ drawer: Drawer, into cb: MTLCommandBuffer,
                                          meshBuffer: MTLBuffer?, groupBuffer: MTLBuffer?, nodeBuffer: MTLBuffer?,
                                          uniforms3D: Uniforms3D, lighting: OllinLighting,
                                          fullWidth: Int, fullHeight: Int) -> MTLTexture? {
        let scale = resolveRaymarchScale(drawer.raymarchQualitySetting)
        guard scale < 1.0, lighting.fieldCasterCount > 0,
              let meshBuffer, let groupBuffer, let nodeBuffer,
              drawer.batches.contains(where: { $0.kind == .mesh3D }) else { return nil }

        let w = max(1, Int((Double(fullWidth) * scale).rounded()))
        let h = max(1, Int((Double(fullHeight) * scale).rounded()))
        if halfResFieldShadowSize != (w, h) || halfResFieldShadow == nil || halfResFieldShadowDepth == nil {
            guard let c = makeHalfResColor(width: w, height: h),
                  let d = makeHalfResDepth(width: w, height: h) else { return nil }
            halfResFieldShadow = c; halfResFieldShadowDepth = d; halfResFieldShadowSize = (w, h)
        }
        guard let color = halfResFieldShadow, let depth = halfResFieldShadowDepth,
              let pipe = try? pipeline(.fieldShadowHalfRes(depth: depthPixelFormat)) else { return nil }

        // Upload the field buffers here (this pre-pass may run before anything else uploads them).
        let groups3D = drawer.sdf3DGroups, nodes3D = drawer.sdf3DNodes
        groups3D.withUnsafeBytes { groupBuffer.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        if !nodes3D.isEmpty {
            nodes3D.withUnsafeBytes { nodeBuffer.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = color
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)  // lit where no mesh
        pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1.0
        pass.depthAttachment.storeAction = .dontCare
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        enc.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(w), height: Double(h), znear: 0, zfar: 1))
        enc.setRenderPipelineState(pipe)
        enc.setDepthStencilState(depthTestState)
        var u3 = uniforms3D
        var lit = lighting
        enc.setVertexBytes(&u3, length: MemoryLayout<Uniforms3D>.stride, index: 2)
        enc.setFragmentBytes(&lit, length: MemoryLayout<OllinLighting>.stride, index: 0)
        enc.setFragmentBuffer(groupBuffer, offset: 0, index: 4)
        enc.setFragmentBuffer(nodeBuffer, offset: 0, index: 5)

        // Every mesh batch (every receiver) renders, for correct depth occlusion; the factor for a
        // matcap/wireframe mesh is computed but unused (those fragments don't sample it).
        let meshStride = MemoryLayout<OllinMeshVertex>.stride
        let meshCount = drawer.meshVertices.count
        let batches = drawer.batches
        for i in batches.indices {
            let batch = batches[i]
            guard batch.kind == .mesh3D else { continue }
            let next = i + 1 < batches.count ? batches[i + 1] : nil
            let end = next?.meshStart ?? meshCount
            let count = end - batch.meshStart
            guard count > 0 else { continue }
            enc.setVertexBuffer(meshBuffer, offset: batch.meshStart * meshStride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
        }
        enc.endEncoding()
        return color
    }

    /// A half-resolution sampleable linear-float color target for the raymarch pre-pass.
    private func makeHalfResColor(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: linearFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }

    /// A half-resolution sampleable depth target for the raymarch pre-pass (read in the
    /// upsample as a `depth2d<float>`, so meshes still z-test against the field).
    private func makeHalfResDepth(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: depthPixelFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
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
                                  meshBuffer: MTLBuffer)
        -> (accel: MTLAccelerationStructure, offsets: MTLBuffer)? {
        let meshStride = MemoryLayout<OllinMeshVertex>.stride
        let meshVertices = drawer.meshVertices
        let batches = drawer.batches
        // Coalesce maximal runs of contiguous caster batches into one geometry descriptor
        // each (a non-casting batch — wireframe, or a non-mesh kind — breaks the run). The
        // caster vertices of a run are contiguous in `meshBuffer`, so one descriptor covers
        // them; fewer descriptors means a cheaper structure build (its per-geometry overhead
        // dominates at creative-coding triangle counts). A fully solid scene becomes one.
        var geometries: [MTLAccelerationStructureTriangleGeometryDescriptor] = []
        // The base vertex index (the run start) of each geometry, in build order, so a
        // reflection hit's `geometryId` recovers where its triangles begin in `meshBuffer`.
        var geoOffsets: [UInt32] = []
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
            geoOffsets.append(UInt32(runStart))
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
        // The per-geometry base-vertex offsets, uploaded for the reflection hit fetch. Filled
        // CPU-side here (before the command buffer commits), so the main pass reads them this frame.
        let offsetsLength = max(MemoryLayout<UInt32>.stride, geoOffsets.count * MemoryLayout<UInt32>.stride)
        if (meshGeoOffsetBuffer?.length ?? 0) < offsetsLength {
            meshGeoOffsetBuffer = device.makeBuffer(length: offsetsLength, options: .storageModeShared)
        }
        guard let offsetsBuffer = meshGeoOffsetBuffer else { return nil }
        geoOffsets.withUnsafeBytes { raw in
            offsetsBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
        return (accel, offsetsBuffer)
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

    /// A 1-element per-geometry-offset buffer bound at fragment buffer 7 whenever ray-traced
    /// reflections aren't producing real offsets this frame, so the RT-compiled mesh
    /// fragment's declared offsets argument is always satisfied (it's read only on a
    /// reflection hit, which can't happen when `lighting.rtReflections == 0`).
    private func ensureDummyGeoOffsets() -> MTLBuffer? {
        if let b = dummyGeoOffsets { return b }
        var zero: UInt32 = 0
        dummyGeoOffsets = device.makeBuffer(bytes: &zero, length: MemoryLayout<UInt32>.stride,
                                            options: .storageModeShared)
        return dummyGeoOffsets
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
        invalidateUserShaderCaches()
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
        if key.isIBL {
            guard let v = library.makeFunction(name: key.vertex),
                  let f = library.makeFunction(name: key.fragment) else {
                throw RendererError.shaderFunctions
            }
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = v
            d.fragmentFunction = f
            d.rasterSampleCount = 1
            d.colorAttachments[0].pixelFormat = key.iblColorFormat
            return try device.makeRenderPipelineState(descriptor: d)
        }
        return try makePipeline(vertex: key.vertex, fragment: key.fragment, using: library,
                                premultiplied: key.premultiplied, blend: key.blend,
                                depthFormat: key.depthFormat, singleSample: key.singleSample)
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
                              depthFormat: MTLPixelFormat? = nil,
                              singleSample: Bool = false) throws -> MTLRenderPipelineState {
        guard let vertexFunction = library.makeFunction(name: vertex),
              let fragmentFunction = library.makeFunction(name: fragment) else {
            throw RendererError.shaderFunctions
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        // Must match the pass's sample count or pipeline creation fails: the view's MSAA count
        // for the geometry pass, or 1 for the single-sample half-res raymarch pass.
        descriptor.rasterSampleCount = singleSample ? 1 : sampleCount
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

    /// Ring + export buffers for the SDF-combinator group instances and node
    /// programs, grown on demand. Mirror `sdfBuffer(at:for:)`/`exportSDFBuffer(for:)`.
    private func sdfGroupBuffer(at index: Int, for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<SDFGroupInstance>.stride
        if let buffer = sdfGroupBuffers[index], buffer.length >= needed { return buffer }
        sdfGroupBuffers[index] = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return sdfGroupBuffers[index]
    }
    private func exportSDFGroupBuffer(for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<SDFGroupInstance>.stride
        if let buffer = sdfGroupExportBuffer, buffer.length >= needed { return buffer }
        sdfGroupExportBuffer = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return sdfGroupExportBuffer
    }
    private func sdfNodeBuffer(at index: Int, for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<SDFNode>.stride
        if let buffer = sdfNodeBuffers[index], buffer.length >= needed { return buffer }
        sdfNodeBuffers[index] = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return sdfNodeBuffers[index]
    }
    private func exportSDFNodeBuffer(for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<SDFNode>.stride
        if let buffer = sdfNodeExportBuffer, buffer.length >= needed { return buffer }
        sdfNodeExportBuffer = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return sdfNodeExportBuffer
    }

    /// Ring + export buffers for the *3D* SDF-combinator field instances and node
    /// programs (the raymarch path). Mirror the 2D `sdfGroupBuffer`/`sdfNodeBuffer` pair.
    private func sdf3DGroupBuffer(at index: Int, for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<SDF3DGroupInstance>.stride
        if let buffer = sdf3DGroupBuffers[index], buffer.length >= needed { return buffer }
        sdf3DGroupBuffers[index] = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return sdf3DGroupBuffers[index]
    }
    private func exportSDF3DGroupBuffer(for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<SDF3DGroupInstance>.stride
        if let buffer = sdf3DGroupExportBuffer, buffer.length >= needed { return buffer }
        sdf3DGroupExportBuffer = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return sdf3DGroupExportBuffer
    }
    private func sdf3DNodeBuffer(at index: Int, for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<SDFNode3D>.stride
        if let buffer = sdf3DNodeBuffers[index], buffer.length >= needed { return buffer }
        sdf3DNodeBuffers[index] = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return sdf3DNodeBuffers[index]
    }
    private func exportSDF3DNodeBuffer(for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<SDFNode3D>.stride
        if let buffer = sdf3DNodeExportBuffer, buffer.length >= needed { return buffer }
        sdf3DNodeExportBuffer = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return sdf3DNodeExportBuffer
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

    /// Build the full MSL source for a user-supplied `Shader`: the OllinShaderLib
    /// segment (preamble + shared types + helpers, with the header spliced in place of
    /// its `#include` since the runtime compiler has no include path), then the wrapper
    /// (the fullscreen vertex, the `ShaderInfo` struct, the `param`/`sample` helpers),
    /// then the user's source tagged `#line 1 "Shader"` so the compiler reports errors
    /// at the user's own line numbers, then the generated `ollin_user_fragment` that
    /// calls their `shade(uv, info)`. Returns the source and the number of lines that
    /// precede the user's source (the fallback rebase offset for a toolchain that
    /// ignores `#line`).
    static func composeUserShaderSource(userSource: String, modules: Shader.Modules,
                                        variant: UserShaderVariant) -> (source: String, userLineOffset: Int) {
        var lib = ""
        if let url = Bundle.module.url(forResource: "OllinShaderLib", withExtension: "metal"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            lib = filterLibModules(text, modules)
        }
        if let url = Bundle.module.url(forResource: "OllinShaderTypes", withExtension: "h"),
           let header = try? String(contentsOf: url, encoding: .utf8) {
            lib = lib.replacingOccurrences(of: "#include \"OllinShaderTypes.h\"", with: header)
        }
        let head = lib + "\n" + userShaderWrapperHead(variant) + "\n#line 1 \"Shader\"\n"
        let offset = head.reduce(0) { $0 + ($1 == "\n" ? 1 : 0) }
        let tail = "\n#line 1 \"ollin-wrapper\"\n" + userShaderWrapperTail(variant)
        return (head + userSource + tail, offset)
    }

    /// Keep only the requested sections of the shader library, by the
    /// `// OLLIN_LIB_BEGIN <module>` / `// OLLIN_LIB_END <module>` markers. Unmarked
    /// lines (the preamble and the always-on `base` section) are always kept; a
    /// section whose module isn't requested is dropped, trimming compile time. The
    /// dependency `noise → hash` is resolved so a noise-only request still compiles.
    private static func filterLibModules(_ lib: String, _ modules: Shader.Modules) -> String {
        if modules == .all { return lib }   // the common case: splice everything
        var mods = modules
        if mods.contains(.noise) { mods.insert(.hash) }
        let nameToModule: [String: Shader.Modules] = [
            "hash": .hash, "noise": .noise, "color": .color, "sdf": .sdf, "domain": .domain]
        var out: [Substring] = []
        var skipping = false
        for line in lib.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("// OLLIN_LIB_BEGIN ") {
                let name = String(trimmed.dropFirst("// OLLIN_LIB_BEGIN ".count))
                skipping = nameToModule[name].map { !mods.contains($0) } ?? false
                continue
            }
            if trimmed.hasPrefix("// OLLIN_LIB_END ") { skipping = false; continue }
            if !skipping { out.append(line) }
        }
        return out.joined(separator: "\n")
    }

    /// The wrapper preamble: the fullscreen vertex, the user-facing `ShaderInfo`
    /// struct, and the `param`/`sample` accessors. The struct carries the input
    /// layer(s) for the filter (one) and combine (two) variants, so the user reads
    /// them with `sample(info, uv)` / `sampleAux(info, uv)`.
    private static func userShaderWrapperHead(_ variant: UserShaderVariant) -> String {
        let layerFields: String
        let sampleMacros: String
        switch variant {
        case .generator:
            layerFields = ""
            sampleMacros = ""
        case .filter:
            layerFields = "    texture2d<float> in0; sampler in0samp;\n"
            sampleMacros = "#define sample(info, p) ollin_layer_sample((info).in0, (info).in0samp, (p))\n"
        case .combine:
            layerFields = "    texture2d<float> in0; sampler in0samp;\n    texture2d<float> in1; sampler in1samp;\n"
            sampleMacros = """
            #define sample(info, p) ollin_layer_sample((info).in0, (info).in0samp, (p))
            #define sampleAux(info, p) ollin_layer_sample((info).in1, (info).in1samp, (p))

            """
        }
        return """
        struct OllinUserVertexOut { float4 position [[position]]; float2 uv; };
        vertex OllinUserVertexOut ollin_user_vertex(uint vid [[vertex_id]]) {
            float2 p = float2((vid << 1) & 2, vid & 2);
            OllinUserVertexOut o;
            o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
            o.uv = float2(p.x, 1.0 - p.y);
            return o;
        }
        // Read an input layer as straight sRGB (it's stored premultiplied linear), so
        // a shader works in the same color space it returns.
        inline float4 ollin_layer_sample(texture2d<float> t, sampler s, float2 uv) {
            float4 c = t.sample(s, clamp(uv, 0.0, 1.0));
            return float4(linearToSrgb(ollin_unpremul(c)), c.a);
        }
        struct ShaderInfo {
            float2 resolution;
            float2 mouse;
            float time;
            float deltaTime;
            uint frame;
            uint paramCount;
            float4 params[OLLIN_SHADER_PARAM_ROWS];
        \(layerFields)};
        #define param(info, i) ((info).params[(i) >> 2][(i) & 3])
        \(sampleMacros)
        """
    }

    /// The generated fragment: bind the input layer(s) for the variant, assemble
    /// `ShaderInfo` from the uniforms, call the user's `shade`, and convert its
    /// straight sRGB result to the premultiplied linear an Ollin layer composites in.
    private static func userShaderWrapperTail(_ variant: UserShaderVariant) -> String {
        let textureParams: String
        let layerAssign: String
        switch variant {
        case .generator:
            textureParams = ""
            layerAssign = ""
        case .filter:
            textureParams = "                                    texture2d<float> ollin_src0 [[texture(0)]],\n"
                + "                                    sampler ollin_samp [[sampler(0)]],\n"
            layerAssign = "    info.in0 = ollin_src0; info.in0samp = ollin_samp;\n"
        case .combine:
            textureParams = "                                    texture2d<float> ollin_src0 [[texture(0)]],\n"
                + "                                    texture2d<float> ollin_src1 [[texture(1)]],\n"
                + "                                    sampler ollin_samp [[sampler(0)]],\n"
            layerAssign = "    info.in0 = ollin_src0; info.in0samp = ollin_samp;\n"
                + "    info.in1 = ollin_src1; info.in1samp = ollin_samp;\n"
        }
        return """
        fragment float4 ollin_user_fragment(OllinUserVertexOut in [[stage_in]],
        \(textureParams)                                    constant float4 *ollin_params [[buffer(0)]],
                                            constant OllinShaderUniforms &ollin_u [[buffer(1)]]) {
            ShaderInfo info;
            info.resolution = ollin_u.resolution;
            info.mouse = ollin_u.mouse;
            info.time = ollin_u.time;
            info.deltaTime = ollin_u.deltaTime;
            info.frame = ollin_u.frame;
            info.paramCount = ollin_u.paramCount;
            for (uint i = 0u; i < OLLIN_SHADER_PARAM_ROWS; ++i) info.params[i] = ollin_params[i];
        \(layerAssign)    float4 c = shade(in.uv, info);
            return float4(srgbToLinear(c.rgb) * c.a, c.a);
        }
        """
    }

    /// Tidy a Metal compiler diagnostic for a user shader: relabel and rebase the
    /// composed-source line numbers (`program_source:N`) to the user's own source
    /// (`shader:N-offset`), so a reported line matches what they wrote, and drop the
    /// boilerplate header. When the compiler honors `#line` it already reports
    /// `Shader:N`, which passes through unchanged.
    static func cleanShaderDiagnostics(_ raw: String, userLineOffset: Int) -> String {
        let text = raw
            .replacingOccurrences(of: "Compilation failed: \n", with: "")
            .replacingOccurrences(of: "Compilation failed:\n", with: "")
        guard let rx = try? NSRegularExpression(pattern: #"program_source:(\d+):(\d+):"#) else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let ns = text as NSString
        var out = ""
        var last = 0
        rx.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m = m else { return }
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let lineNo = Int(ns.substring(with: m.range(at: 1))) ?? 0
            let col = ns.substring(with: m.range(at: 2))
            out += "shader:\(max(1, lineNo - userLineOffset)):\(col):"
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        // Drop compiler-internal notes that point at system framework headers (e.g. a
        // "did you mean" suggestion from the Metal standard library): they reference
        // absolute paths a sketch author can't act on and only clutter the message.
        let kept = out.split(separator: "\n", omittingEmptySubsequences: false).filter { line in
            !(line.contains("/System/") || line.contains("GPUCompiler.framework")
              || line.contains("/Applications/") || line.contains("/usr/"))
        }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The shader source segments, in concatenation order. They're compiled as one
    /// library, so order matters: `OllinShaderLib` carries the preamble, the shared
    /// CPU/GPU structs, and the general color/hash/noise helpers the rest depend on,
    /// so it goes first (Metal needs a declaration before its use); `ShaderCore`
    /// follows with the 2D core pipelines. The single `Shaders.metal` split into
    /// these once it crossed ~2,000 lines; the renderer never assumes one file.
    static let shaderSourceNames = ["OllinShaderLib", "ShaderCore", "ShaderShapes", "ShaderCombinator", "Shader3D", "ShaderRaymarch", "ShaderEffects", "ShaderIBL"]

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

/// The baked image-based-lighting maps for one environment, cached by source. The
/// `envCube` is the environment itself (for a skybox and mirror reflections), `irradiance`
/// the cosine-convolved diffuse cube, `prefilter` the GGX-prefiltered specular mip-cube.
private final class IBLMaps {
    let irradiance: MTLTexture
    let prefilter: MTLTexture
    let envCube: MTLTexture
    /// The full-resolution equirectangular source, kept so the skybox samples it directly
    /// (sharp) rather than the low-resolution cube. For a procedural sky it's the generated
    /// equirect. Optional only for a bake that produced no source texture.
    let equirect: MTLTexture?
    let maxMip: Int
    /// An auto-exposure factor: the environments range ~800× in average brightness, so each
    /// is scaled to a common target average luminance, applied to both the lighting and the
    /// skybox. Keeps a bright noon or a night from blowing out or crushing.
    let normalization: Float
    init(irradiance: MTLTexture, prefilter: MTLTexture, envCube: MTLTexture,
         equirect: MTLTexture?, maxMip: Int, normalization: Float) {
        self.irradiance = irradiance
        self.prefilter = prefilter
        self.envCube = envCube
        self.equirect = equirect
        self.maxMip = maxMip
        self.normalization = normalization
    }
}

extension MetalRenderer {
    private static let iblEnvFace = 256
    private static let iblIrradianceFace = 32
    private static let iblPrefilterFace = 256   // mirror (roughness 0) reflection sharpness
    private static let iblPrefilterMips = 6
    private static let iblBRDFSize = 256
    private static let iblTargetLuminance: Float = 0.4   // auto-exposure target average
    /// A neutral midday sky used to light a scene while a non-bundled HDRI downloads, instead
    /// of leaving it unlit (see resolveEnvironmentSources). The env's own intensity/rotation
    /// still apply, since the placeholder is a copy of it with only the source swapped.
    static let skyPlaceholderSource = Environment.Source.sky(turbidity: 2.5, sunElevation: 0.6,
                                                             groundAlbedo: 0.3)

    /// Resolve the frame's environment to its baked IBL maps, baking once on the given
    /// command buffer and caching by source (the bake is a few fullscreen passes; a frame
    /// that reuses an environment pays nothing). A `.remote` source resolves to its cached
    /// file (or a downloading placeholder); `blocking` true (the export path) waits for the
    /// download so exported art is the full-resolution version. Returns whether IBL is active.
    func resolveIBL(for environment: Environment?, commandBuffer cb: MTLCommandBuffer,
                    blocking: Bool = false) -> Bool {
        guard let environment else { currentIBL = nil; return false }
        let (primary, placeholder) = resolveEnvironmentSources(environment, blocking: blocking)
        // Bake the requested environment once its pixels are ready; until then (a heavy HDRI
        // still downloading, or decoding off-thread) show the bundled placeholder, so the
        // scene is never unlit and the live window never blocks on the decode.
        if let primary, let maps = bakeReady(primary, blocking: blocking, commandBuffer: cb) {
            currentIBL = maps; return true
        }
        if let placeholder, let maps = bakeReady(placeholder, blocking: false, commandBuffer: cb) {
            currentIBL = maps; return true
        }
        currentIBL = nil; return false
    }

    /// Bake (or reuse) the IBL maps for an already-resolved `.resource`/`.url` environment, or
    /// nil when its equirect isn't decoded yet (a heavy `.url` decodes off-thread). Cached by
    /// source so the bake runs once; the raw float pixels are freed once baked into textures.
    private func bakeReady(_ env: Environment, blocking: Bool,
                           commandBuffer cb: MTLCommandBuffer) -> IBLMaps? {
        // A static sky (or an HDRI) keys on its exact source, so it bakes once and then reuses
        // the cache every frame. An animated sky is a fresh source each frame, so it re-bakes
        // entirely on the GPU (no CPU read-back), which a smoothly moving sun needs.
        if let cached = iblCache[env.source] { return cached }

        let loaded: MTLTexture, avg: Float
        let isSky: Bool
        if case .sky(let t, let e, let a) = env.source {
            guard let sky = generateSkyEquirectTexture(turbidity: t, sunElevation: e,
                                                       groundAlbedo: a, commandBuffer: cb) else { return nil }
            (loaded, avg) = sky
            isSky = true
        } else {
            guard let bytes = equirectBytes(for: env, blocking: blocking),
                  let tex = uploadEquirect(bytes) else { return nil }
            (loaded, avg) = (tex, bytes.avg)
            equirectReady.withLock { $0[env.source] = nil }
            isSky = false
        }
        guard let maps = bakeIBL(env, equirectTexture: loaded, avgLuminance: avg,
                                 fastSky: isSky, commandBuffer: cb) else { return nil }
        // An animated sky makes a fresh source each frame; drop the previous sky bake so its GPU
        // textures don't accumulate over the animation (a static sky keeps its one entry).
        if case .sky = env.source {
            for k in iblCache.keys where k != env.source {
                if case .sky = k { iblCache[k] = nil }
            }
        }
        iblCache[env.source] = maps
        return maps
    }

    /// Resolve an environment to (primary, placeholder): the form to bake when its pixels are
    /// ready, and a bundled fallback to show meanwhile. Handles a `.remote` source: the
    /// cached download if present, else (export) a synchronous download, else (live) kick off
    /// the download and offer the placeholder until it lands.
    private func resolveEnvironmentSources(_ env: Environment, blocking: Bool)
        -> (primary: Environment?, placeholder: Environment?) {
        func with(_ source: Environment.Source) -> Environment { var e = env; e.source = source; return e }
        switch env.source {
        case .resource, .url:
            return (env, nil)
        case .sky:
            return (env, nil)   // generated on the GPU when its pixels are baked
        case .remote(let url, let fallback):
            let cache = EnvironmentCache.shared
            // While a non-bundled HDRI downloads, light the scene with a procedural sky
            // (keeping the env's own intensity/rotation/backdrop) instead of leaving it
            // unlit, unless an explicit bundled placeholder was given.
            let placeholder = fallback.map { with(.resource(name: $0, bundleID: nil)) }
                ?? with(Self.skyPlaceholderSource)
            if let file = cache.cachedFile(for: url) {
                return (with(.url(file)), placeholder)
            }
            if blocking, let file = cache.downloadBlocking(url) {
                return (with(.url(file)), nil)
            }
            cache.ensureDownloading(url)
            return (nil, placeholder)   // not downloaded yet: only the placeholder
        }
    }

    /// The processed equirect pixels for a bakeable env, or nil if not ready. A bundled
    /// `.resource` decodes inline (small, fast). A `.url` HDRI can be large, so it decodes off
    /// the render thread (live), returning nil until it lands, or synchronously when
    /// `blocking` (export). A disk blob of the processed pixels makes a relaunch skip the
    /// expensive PIZ decode.
    private func equirectBytes(for env: Environment, blocking: Bool) -> EquirectBytes? {
        if let ready = equirectReady.withLock({ $0[env.source] }) { return ready }
        switch env.source {
        case .resource:
            guard let bytes = Self.loadEquirectBytes(env) else { return nil }
            equirectReady.withLock { $0[env.source] = bytes }
            return bytes
        case .url:
            if blocking {
                guard let bytes = Self.loadEquirectBytes(env) else { return nil }
                equirectReady.withLock { $0[env.source] = bytes }
                return bytes
            }
            let source = env.source
            let started = equirectLoading.withLock { loading -> Bool in
                guard !loading.contains(source) else { return false }
                loading.insert(source); return true
            }
            if started {
                let envCopy = env, ready = equirectReady, loading = equirectLoading
                Task.detached {
                    let bytes = Self.loadEquirectBytes(envCopy)
                    if let bytes { ready.withLock { $0[source] = bytes } }
                    loading.withLock { _ = $0.remove(source) }
                }
            }
            return nil
        case .sky, .remote:
            // .sky is generated as a texture directly in bakeReady (no CPU pixels); .remote was
            // resolved to a cached .url or a placeholder before reaching here.
            return nil
        }
    }

    /// The IBL maps bound to the mesh fragment this frame (irradiance / prefilter / BRDF
    /// LUT), or `nil` when no environment is set. `nil` for any of these keeps the mesh
    /// fragment on its byte-identical no-IBL path.
    var currentIBLIrradiance: MTLTexture? { currentIBL?.irradiance }
    var currentIBLPrefilter: MTLTexture? { currentIBL?.prefilter }
    var currentIBLEnvCube: MTLTexture? { currentIBL?.envCube }
    var currentIBLSkyboxTexture: MTLTexture? { currentIBL?.equirect }
    var currentIBLMaxMip: Int { currentIBL?.maxMip ?? 0 }
    var currentIBLNormalization: Float { currentIBL?.normalization ?? 1 }
    var iblBRDFLUTTexture: MTLTexture? { iblBRDFLUT }

    private func bakeIBL(_ environment: Environment, equirectTexture loaded: MTLTexture,
                         avgLuminance: Float, fastSky: Bool = false,
                         commandBuffer cb: MTLCommandBuffer) -> IBLMaps? {
        guard let env = makeEnvCube(equirectTexture: loaded, commandBuffer: cb) else { return nil }
        let envCube = env.cube
        if let blit = cb.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: envCube)   // the prefilter samples these mips
            blit.endEncoding()
        }
        guard let irradiance = makeCubeTexture(face: Self.iblIrradianceFace, mipped: false),
              let prefilter = makeCubeTexture(face: Self.iblPrefilterFace, mipped: true),
              let irrPipe = try? pipeline(.ibl("ollin_ibl_irradiance")),
              let prePipe = try? pipeline(.ibl("ollin_ibl_prefilter")) else { return nil }

        // A procedural sky is low-frequency, so its convolutions converge with far fewer samples
        // than an HDRI; the cheaper bake lets a moving sun re-bake every frame smoothly. `0`
        // selects the default fine bake in the shader, keeping the HDRI path byte-identical.
        let irrStep: Float = fastSky ? 0.08 : 0      // coarser hemisphere step (~10x fewer samples)
        let preSamples: Float = fastSky ? 32 : 0     // fewer GGX samples (vs the default 256)
        for face in 0..<6 {
            bakeIBLFace(pipeline: irrPipe, inputs: [envCube], output: irradiance, slice: face,
                        level: 0, params: SIMD4<Float>(Float(face), 0, irrStep, 0), commandBuffer: cb)
        }
        let mips = Self.iblPrefilterMips
        for mip in 0..<mips {
            let roughness = mips > 1 ? Float(mip) / Float(mips - 1) : 0
            for face in 0..<6 {
                bakeIBLFace(pipeline: prePipe, inputs: [envCube], output: prefilter, slice: face,
                            level: mip, params: SIMD4<Float>(Float(face), roughness, preSamples, 0),
                            commandBuffer: cb)
            }
        }
        ensureBRDFLUT(commandBuffer: cb)
        // Auto-exposure: scale to a common target average luminance (clamped so a near-black
        // night or a blinding noon stays sane), applied to the lighting and the skybox.
        let normalization = avgLuminance > 1e-5
            ? min(max(Self.iblTargetLuminance / avgLuminance, 0.01), 12)
            : 1
        return IBLMaps(irradiance: irradiance, prefilter: prefilter, envCube: envCube,
                       equirect: env.equirect, maxMip: mips - 1, normalization: normalization)
    }

    /// Reproject an equirect texture (a decoded HDRI or a generated sky) into an environment
    /// cube map for the bake, returning the cube and the equirect itself (the skybox samples it
    /// directly). Returns nil on cube/pipeline failure, so the frame stays on the no-IBL path.
    private func makeEnvCube(equirectTexture loaded: MTLTexture, commandBuffer cb: MTLCommandBuffer)
        -> (cube: MTLTexture, equirect: MTLTexture)? {
        guard let cube = makeCubeTexture(face: Self.iblEnvFace, mipped: true),
              let pipe = try? pipeline(.ibl("ollin_ibl_equirect_to_cube")) else { return nil }
        // Mip the equirect *before* the cube bake: a high-res equirect → small cube face is a
        // big minification, so the equirect→cube sample needs valid mips (and the skybox blur
        // samples them too). Generating them afterward would leave the cube reading empty mips.
        if let blit = cb.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: loaded)
            blit.endEncoding()
        }
        for face in 0..<6 {
            bakeIBLFace(pipeline: pipe, inputs: [loaded], output: cube, slice: face, level: 0,
                        params: SIMD4<Float>(Float(face), 0, 0, 0), commandBuffer: cb)
        }
        return (cube, loaded)
    }

    /// Upload processed equirect float pixels into a mipmapped `rgba16Float` texture (the
    /// skybox samples a blurred level for soft focus; `makeEnvCube` generates the mips). The
    /// `.shared` storage lets the level-0 upload run regardless of thread.
    private func uploadEquirect(_ bytes: EquirectBytes) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
                                                            width: bytes.width, height: bytes.height,
                                                            mipmapped: true)
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        bytes.data.withUnsafeBytes { raw in
            tex.replace(region: MTLRegionMake2D(0, 0, bytes.width, bytes.height), mipmapLevel: 0,
                        withBytes: raw.baseAddress!, bytesPerRow: bytes.width * 8)
        }
        return tex
    }

    /// Generate a Hosek-Wilkie procedural sky directly as a mipmapped equirect *texture* on the
    /// given (frame) command buffer, plus its average luminance for auto-exposure. The
    /// per-channel sky coefficients are cooked once on the CPU (the vendored model, the step
    /// that reads its dataset); a fullscreen pass then fills the equirect on the GPU. Crucially
    /// there's no CPU round-trip: the texture feeds the cube / irradiance / prefilter bake on the
    /// same command buffer, and the average is integrated analytically from the same coefficients
    /// (a cheap CPU sphere sum), so an animated sun re-bakes entirely on the GPU with no stall.
    /// 1024x512 is ample for the lighting and a smooth backdrop.
    private func generateSkyEquirectTexture(turbidity: Double, sunElevation: Double,
                                            groundAlbedo: Double, commandBuffer cb: MTLCommandBuffer)
        -> (texture: MTLTexture, avgLuminance: Float)? {
        let width = 1024, height = 512
        let turb = min(max(turbidity, 1), 10)
        let albedo = min(max(groundAlbedo, 0), 1)
        let elevation = min(max(sunElevation, 0.001), Double.pi / 2 - 0.001)
        var configs = [Double](repeating: 0, count: 27)
        var radiances = [Double](repeating: 0, count: 3)
        configs.withUnsafeMutableBufferPointer { cp in
            radiances.withUnsafeMutableBufferPointer { rp in
                ollin_hosek_rgb_configs(turb, albedo, elevation, cp.baseAddress, rp.baseAddress)
            }
        }
        // Pack 11 float4s (see ollin_ibl_sky_gen): 9 coefficient rows (rgb = the R/G/B value of
        // coefficient i), the per-channel radiance + ground albedo, the sun direction + radius.
        var sky = [SIMD4<Float>](repeating: .zero, count: 11)
        for i in 0..<9 {
            sky[i] = SIMD4<Float>(Float(configs[i]), Float(configs[9 + i]), Float(configs[18 + i]), 0)
        }
        sky[9] = SIMD4<Float>(Float(radiances[0]), Float(radiances[1]), Float(radiances[2]), Float(albedo))
        // The sun rises in a fixed compass direction (+Z), raised by its elevation; rotated(_:) spins it.
        let solarRadius: Float = 0.0255   // ~1.5 deg disc, a touch wider than the sun for visible reflections
        let sunDir = SIMD3<Float>(0, Float(sin(elevation)), Float(cos(elevation)))
        sky[10] = SIMD4<Float>(sunDir.x, sunDir.y, sunDir.z, solarRadius)

        // Render the sky equirect on the frame's command buffer (no read-back), mipmapped so the
        // cube bake and the skybox blur sample valid levels (makeEnvCube generates the mips).
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
                                                            width: width, height: height, mipmapped: true)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        guard let tex = device.makeTexture(descriptor: desc),
              let pipe = try? pipeline(.ibl("ollin_ibl_sky_gen")) else { return nil }
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = tex
        rp.colorAttachments[0].loadAction = .dontCare
        rp.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: rp) else { return nil }
        enc.setRenderPipelineState(pipe)
        enc.setFragmentBytes(&sky, length: sky.count * MemoryLayout<SIMD4<Float>>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        let avg = Self.skyAverageLuminance(configs: configs, radiances: radiances,
                                           albedo: albedo, sunDir: sunDir)
        return (tex, avg)
    }

    /// The solid-angle-weighted average luminance of the procedural sky, integrated on the CPU
    /// from the Hosek-Wilkie coefficients over a coarse sphere (the same upper-hemisphere-sky /
    /// lower-hemisphere-ground-bounce split the shader uses), so auto-exposure needs no GPU
    /// read-back. Coarse is fine: it only sets the exposure scale.
    nonisolated private static func skyAverageLuminance(configs: [Double], radiances: [Double],
                                                        albedo: Double, sunDir: SIMD3<Float>) -> Float {
        func radiance(_ cosTheta: Double, _ gamma: Double, _ c: Int) -> Double {
            let b = c * 9
            let A = configs[b], B = configs[b + 1], C = configs[b + 2], D = configs[b + 3], E = configs[b + 4]
            let F = configs[b + 5], G = configs[b + 6], H = configs[b + 7], I = configs[b + 8]
            let cg = cos(gamma)
            let mieM = (1 + cg * cg) / pow(max(1 + I * I - 2 * I * cg, 1e-4), 1.5)
            let zenith = cosTheta > 0 ? sqrt(cosTheta) : 0
            let v = (1 + A * exp(B / (cosTheta + 0.01)))
                  * (C + D * exp(E * gamma) + F * cg * cg + G * mieM + H * zenith)
            return max(v, 0) * radiances[c]
        }
        let sx = Double(sunDir.x), sy = Double(sunDir.y), sz = Double(sunDir.z)
        let rows = 32, cols = 16   // coarse: it only sets the exposure scale, and runs per re-bake
        var lumSum = 0.0, weightSum = 0.0
        for y in 0..<rows {
            let lat = (Double(y) + 0.5) / Double(rows) * Double.pi   // 0 top .. pi bottom
            let rowWeight = sin(lat)
            var rowLum = 0.0
            for x in 0..<cols {
                let lon = (Double(x) + 0.5) / Double(cols) * 2 * Double.pi
                var dy = cos(lat)
                let dxz = sin(lat)
                let dx = dxz * cos(lon), dz = dxz * sin(lon)
                var ground = 1.0
                if dy < 0 { dy = -dy; ground = albedo }              // ground = dimmed mirror sky
                let gamma = acos(max(-1, min(1, dx * sx + dy * sy + dz * sz)))
                rowLum += (0.2126 * radiance(dy, gamma, 0)
                         + 0.7152 * radiance(dy, gamma, 1)
                         + 0.0722 * radiance(dy, gamma, 2)) * ground
            }
            lumSum += rowLum / Double(cols) * rowWeight
            weightSum += rowWeight
        }
        return weightSum > 0 ? Float(lumSum / weightSum) : 1
    }

    private func makeCubeTexture(face size: Int, mipped: Bool) -> MTLTexture? {
        let desc = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat: .rgba16Float,
                                                              size: size, mipmapped: mipped)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }

    /// Render one fullscreen-triangle bake pass into a cube face (slice) at a mip level.
    private func bakeIBLFace(pipeline: MTLRenderPipelineState, inputs: [MTLTexture],
                             output: MTLTexture, slice: Int, level: Int,
                             params: SIMD4<Float>, commandBuffer cb: MTLCommandBuffer) {
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = output
        rp.colorAttachments[0].slice = slice
        rp.colorAttachments[0].level = level
        rp.colorAttachments[0].loadAction = .dontCare
        rp.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: rp) else { return }
        enc.setRenderPipelineState(pipeline)
        for (i, t) in inputs.enumerated() { enc.setFragmentTexture(t, index: i) }
        var p = params
        enc.setFragmentBytes(&p, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    /// Bake the environment-independent BRDF integration LUT once (the split-sum scale/bias).
    private func ensureBRDFLUT(commandBuffer cb: MTLCommandBuffer) {
        guard iblBRDFLUT == nil else { return }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg16Float,
                                                            width: Self.iblBRDFSize,
                                                            height: Self.iblBRDFSize, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        guard let lut = device.makeTexture(descriptor: desc),
              let pipe = try? pipeline(.ibl("ollin_ibl_brdf_lut", color: .rg16Float)) else { return }
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = lut
        rp.colorAttachments[0].loadAction = .dontCare
        rp.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: rp) else { return }
        enc.setRenderPipelineState(pipe)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        iblBRDFLUT = lut
    }

    /// The processed equirect pixels for a `.resource`/`.url` env: a cached blob if present (a
    /// fast read, no decode), else decode the source HDRI and (for a `.url`) write the blob
    /// so the next launch skips the decode. CPU-only, so it can run off the render thread.
    nonisolated fileprivate static func loadEquirectBytes(_ env: Environment) -> EquirectBytes? {
        let blobURL: URL? = {
            if case .url(let file) = env.source { return EnvironmentCache.shared.equirectBlobFile(for: file) }
            return nil   // a bundled .resource decodes fast and its EXR is compact: skip the blob
        }()
        if let blobURL, let bytes = readEquirectBlob(blobURL) { return bytes }
        // A real `.url` decode (blob miss): the heavy step after a download, so note it. A
        // bundled `.resource` decodes fast from a compact EXR, so it stays silent.
        if case .url(let file) = env.source { print("Ollin: decoding \(EnvironmentCache.displayName(for: file))…") }
        guard let cg = env.loadEquirectImage(), let bytes = processEquirect(cg) else { return nil }
        if let blobURL { writeEquirectBlob(bytes, to: blobURL) }
        return bytes
    }

    nonisolated private static let equirectBlobMagic: UInt32 = 0x4F4C4548   // "OLEH"

    /// Decode a linear-HDR equirectangular `CGImage` into `rgba16Float` pixels, clamping any
    /// blown-out (inf/NaN half) texel to the max finite half so a bright sun doesn't propagate
    /// inf through the convolutions, and computing the solid-angle-weighted average luminance
    /// (for auto-exposure: the environments range ~800× in brightness).
    nonisolated private static func processEquirect(_ cg: CGImage) -> EquirectBytes? {
        let w = cg.width, h = cg.height
        guard w > 0, h > 0, let cs = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else { return nil }
        let bpr = w * 8
        let info = CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
                 | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 16,
                                  bytesPerRow: bpr, space: cs, bitmapInfo: info) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let raw = ctx.data else { return nil }
        let halfs = raw.bindMemory(to: UInt16.self, capacity: w * h * 4)
        let avg = clampAndAverageLuminance(halfs, width: w, height: h)
        return EquirectBytes(data: Data(bytes: raw, count: w * h * 8), width: w, height: h, avg: avg)
    }

    /// Clamp any blown-out (inf/NaN) half to the max finite half (so a bright sun doesn't push
    /// inf through the convolutions) and return the solid-angle-weighted average luminance (rows
    /// near the poles cover less sky), for auto-exposure. Shared by the HDRI decode and the
    /// procedural-sky readback; mutates the pixels in place.
    nonisolated private static func clampAndAverageLuminance(
        _ halfs: UnsafeMutablePointer<UInt16>, width w: Int, height h: Int) -> Float {
        for i in 0..<(w * h * 4) where (halfs[i] & 0x7C00) == 0x7C00 {
            halfs[i] = (halfs[i] & 0x8000) | 0x7BFF
        }
        var lumSum = 0.0, weightSum = 0.0
        for y in 0..<h {
            let rowWeight = Double(sin((Double(y) + 0.5) / Double(h) * Double.pi))
            var rowLum = 0.0
            let row = y * w * 4
            for x in 0..<w {
                let i = row + x * 4
                let r = Float(Float16(bitPattern: halfs[i]))
                let g = Float(Float16(bitPattern: halfs[i + 1]))
                let b = Float(Float16(bitPattern: halfs[i + 2]))
                rowLum += Double(0.2126 * r + 0.7152 * g + 0.0722 * b)
            }
            lumSum += rowLum / Double(w) * rowWeight
            weightSum += rowWeight
        }
        return weightSum > 0 ? Float(lumSum / weightSum) : 1
    }

    /// Write processed equirect pixels to a cache blob (a small header + raw float16 pixels),
    /// best-effort — a failed write just means the next launch re-decodes.
    nonisolated private static func writeEquirectBlob(_ bytes: EquirectBytes, to url: URL) {
        var header: [UInt32] = [equirectBlobMagic, 1, UInt32(bytes.width), UInt32(bytes.height),
                                bytes.avg.bitPattern]
        var out = Data(bytes: &header, count: header.count * MemoryLayout<UInt32>.size)
        out.append(bytes.data)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let tmp = url.appendingPathExtension("writing")
        if (try? out.write(to: tmp, options: .atomic)) != nil {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.moveItem(at: tmp, to: url)
        }
    }

    /// Read a processed-equirect blob, or nil if absent / corrupt / size-mismatched (any of
    /// which falls back to a fresh decode).
    nonisolated private static func readEquirectBlob(_ url: URL) -> EquirectBytes? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count >= 20 else { return nil }
        let header = data.prefix(20).withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
        guard header[0] == equirectBlobMagic, header[1] == 1 else { return nil }
        let w = Int(header[2]), h = Int(header[3]), avg = Float(bitPattern: header[4])
        guard w > 0, h > 0, data.count == 20 + w * h * 8 else { return nil }
        return EquirectBytes(data: data.subdata(in: 20..<data.count), width: w, height: h, avg: avg)
    }
}

/// Processed equirect float pixels (`rgba16Float`, `width·height·8` bytes) plus the source's
/// solid-angle-weighted average luminance, handed from the decode (possibly off-thread) to
/// the bake. `Sendable` so the off-thread load can return it across the task boundary.
fileprivate struct EquirectBytes: Sendable {
    let data: Data
    let width: Int
    let height: Int
    let avg: Float
}
