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
/// You only touch the renderer when you need a *new pipeline* (e.g. instanced or
/// SDF circles, textured quads for images, a new blend mode): add a `Pipeline`
/// case and a branch in `makePipeline(_:)` (in MetalRenderer+Pipelines.swift);
/// don't grow `init`. The renderer spans this file (the state and frame loop)
/// plus its topic extensions (Effects, Targets, Pipelines, IBL).
///
/// Main-actor isolated: it's created and driven from the main thread (the
/// `MTKViewDelegate` draw callback and the headless export path). The only work
/// that intentionally runs off-actor is the GPU completed-handler, which signals
/// `frameBoundary` (a `Sendable` semaphore), drops the frame count that mirrors
/// it, records the GPU time, and touches nothing else.
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
    struct PipelineKey: Hashable {
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
        /// The present pass fitted to a wall: the same pass through the twin that
        /// reads the frame back through a corner-pin warp and fades its edges (see
        /// `Installation.Projection`). Only ever set with `isPresent`, and only on
        /// the two paths that present into a drawable, so an export never warps.
        var isProjected = false
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
        /// The attachment format an effect pass writes. `nil` is the shared linear-float
        /// intermediate every filter uses; a wider one is for a pass whose *intermediate*
        /// magnitudes leave half float's range, which the convolution pyramid's do.
        var effectFormat: MTLPixelFormat? = nil
        /// The color attachment a *geometry* pipeline writes. `nil` is the shared
        /// linear-float intermediate; a layer made with `precision: .float32` sets
        /// its format here so every batch drawn into it builds against it. Left
        /// nil for the canvas and every half-float layer, so those keys (and the
        /// pipelines behind them) are untouched.
        var colorFormat: MTLPixelFormat? = nil
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
        /// The reflection G-buffer pass: two color attachments (world normal, metal/rough)
        /// plus depth, single-sample, blending off: the one MRT pipeline, so it gets its
        /// own descriptor branch in `makePipeline`.
        var isGBuffer = false
        /// How many color attachments a G-buffer pipeline declares: 2 for the
        /// reflection pass, 3 for the caustics pass (which adds the baked albedo).
        var gBufferAttachments = 2
        /// The caustics splat pass: instanced photon-footprint quads additively
        /// blended (one + one) into a single-sample float layer, no depth attachment
        /// (the fragment depth-tests manually against the caustics G-buffer).
        var isCausticSplat = false
        /// The subsurface-scatter mask pass: one float attachment written with blending
        /// off (the mask's alpha channel carries a profile index, which alpha blending
        /// would corrupt), single-sample, depth-tested into its own depth.
        var isScatterMask = false
        /// The mover-velocity pass (temporal AA): one `rg16Float` attachment written
        /// with blending off (the fragment's value is a signed pixel delta, not a
        /// color), single-sample, depth-tested + writing into its own depth.
        var isVelocity = false
        /// The velocity pass's occluder phase: the same pass shape drawn depth-only
        /// (nil fragment, color writes masked off), so geometry in front of a mover
        /// keeps it from writing velocity through its occluder.
        var isVelocityOccluder = false
        /// Set (to `.stencil8`) when the pass carries a stencil attachment (clipping is
        /// active on that surface). Part of the key because *every* pipeline drawn into
        /// a stencil-carrying pass must declare the format, clipped or not; a pass with
        /// no stencil leaves it nil so those pipelines stay byte-identical.
        var stencilFormat: MTLPixelFormat? = nil
        /// A clip-write pipeline (the stencil-clipping push/pop): rasterizes into the
        /// stencil only, with the color write mask empty and blending off.
        var isClipWrite = false
        /// A mesh pipeline (Metal 3 [[object]]/[[mesh]] stages) when `mesh` is
        /// non-empty: `object` + `mesh` name the two stages, `vertex` is unused
        /// (""), and the factory builds an MTLMeshRenderPipelineDescriptor.
        var object = ""
        var mesh = ""
        /// The object-stage payload length for a mesh pipeline, bytes.
        var payloadLength = 0

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
        // the air fog backdrop (atmosphere): a fullscreen march of each view ray through
        // the fog + the frame's lights, composited right after the skybox with the same
        // no-depth recipe. Premultiplied source-over: rgb = in-scatter, alpha = 1 −
        // transmittance, so the backdrop shows through by exactly T.
        static func fogAir(depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_ibl_skybox_vertex", fragment: "ollin_fog_air_fragment",
                        premultiplied: true, depthFormat: depth)
        }
        // the path-traced export composite: a fullscreen draw of the traced layer into
        // the geometry pass in place of the raster mesh batches, premultiplied by its
        // coverage (silhouette edges blend over the backdrop) and writing the primary
        // depth so the un-traced 3D kinds still occlude correctly.
        static func pathTraceComposite(depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_ibl_skybox_vertex", fragment: "ollin_pt_composite_fragment",
                        premultiplied: true, depthFormat: depth)
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
        // instanced GPU-particle discs (compute-resident buffer): the perceptual
        // ink discs, or the radiometric light deposit (`ParticleStyle.light`)
        static func points(_ blend: BlendMode, depth: MTLPixelFormat? = nil, light: Bool = false) -> PipelineKey {
            light
                ? PipelineKey(vertex: "ollin_particle_light_vertex", fragment: "ollin_particle_light_fragment",
                              blend: blend, depthFormat: depth)
                : PipelineKey(vertex: "ollin_particle_vertex", fragment: "ollin_particle_fragment",
                              blend: blend, depthFormat: depth)
        }
        // instanced 3D point-cloud splats (camera-facing discs, depth-tested)
        static func pointCloud(_ blend: BlendMode, depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_point_vertex", fragment: "ollin_point_fragment", blend: blend, depthFormat: depth)
        }
        // solid 3D triangle mesh (depth-tested, lit by the material model)
        static func mesh(_ blend: BlendMode, depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_mesh_vertex", fragment: "ollin_mesh_fragment", blend: blend, depthFormat: depth)
        }
        // instanced 3D triangle mesh: one local-space base mesh + a per-copy
        // placement buffer, placed per vertex on the GPU. Shares the solid lit
        // fragment, so copies shade exactly like solid meshes.
        static func meshInstanced(_ blend: BlendMode, depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_mesh_instanced_vertex", fragment: "ollin_mesh_fragment",
                        blend: blend, depthFormat: depth)
        }
        // MeshField: many distinct meshes + copies drawn by GPU-written indirect
        // draws (one per entry). The vertex adds the compacted-copy indirection
        // over the instanced path and the copies shade through the same solid
        // lit fragment, so the pipeline is an ordinary lit mesh pipeline. (Not
        // an MTLIndirectCommandBuffer: the RT-compiled fragment is rejected by
        // ICB pipelines, and indirect draws carry the same GPU-authored payload.)
        static func meshField(_ blend: BlendMode, depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_mesh_field_vertex", fragment: "ollin_mesh_fragment",
                        blend: blend, depthFormat: depth)
        }
        // StrandField (drawStrands): a mesh pipeline growing grass-like blades
        // inside the draw itself (no geometry buffers). The mesh stage emits the
        // solid path's MeshOut, so blades shade through the same lit fragment.
        static func strands(_ blend: BlendMode, depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "", fragment: "ollin_mesh_fragment", blend: blend,
                        depthFormat: depth, object: "ollin_strand_object",
                        mesh: "ollin_strand_mesh", payloadLength: 16)
        }
        // OceanField (drawOcean): a grid with no geometry buffers, each vertex
        // working out its own corner from its index and reading the wave field
        // for where the water has moved it. Its own water fragment, not the lit
        // mesh one: the surface is a reflection and a body color rather than a
        // material.
        static func ocean(_ blend: BlendMode, depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_ocean_vertex", fragment: "ollin_ocean_fragment",
                        blend: blend, depthFormat: depth)
        }
        // textured 3D triangle mesh: the surface samples a base-color texture at the
        // vertex UVs, otherwise the same depth-tested, lit mesh path.
        static func meshTextured(_ blend: BlendMode, depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_mesh_textured_vertex", fragment: "ollin_mesh_textured_fragment",
                        blend: blend, depthFormat: depth)
        }
        // normal-mapped textured mesh: the textured path's twin whose fragment bends
        // the lighting normal by a tangent-space normal map (its vertex carries the
        // packed tangent through). A separate function pair rather than a branch in
        // the shipped fragment, so unmapped textured frames stay byte-identical by
        // construction (the codegen rule: control-flow growth re-contracts fast-math).
        static func meshNormalMapped(_ blend: BlendMode, depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_mesh_nm_vertex", fragment: "ollin_mesh_nm_fragment",
                        blend: blend, depthFormat: depth)
        }
        // surface-mapped textured mesh: the textured path's second twin, for the PBR
        // map set (metallic-roughness / occlusion / emissive, the normal-map bend
        // folded in behind its own gate). Shares the nm vertex (it just passes the
        // packed tangent through); the fragment samples the maps and shades through
        // the hand-synced `meshLitColorMapped` tail.
        static func meshSurfaceMapped(_ blend: BlendMode, depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_mesh_nm_vertex", fragment: "ollin_mesh_maps_fragment",
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
        // the live ground-grid overlay: a large y=0 plane whose fragment draws an
        // anti-aliased reference grid from the interpolated world XZ (reusing the mesh
        // vertex stage). Alpha-blended, depth-tested but not depth-writing (the no-write
        // state is selected on the encoder). Live host chrome, never in an export.
        static func grid(_ blend: BlendMode, depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_mesh_vertex", fragment: "ollin_grid_fragment",
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
        // reflection G-buffer: re-render the meshes single-sample into two attachments
        // (world normal + coverage, metalness/roughness) with their own depth, feeding
        // the deferred ray-traced-reflection trace pass. Only encoded when reflections
        // are active on a ray-tracing device.
        static func rtReflectGBuffer(depth: MTLPixelFormat) -> PipelineKey {
            PipelineKey(vertex: "ollin_mesh_gbuffer_vertex", fragment: "ollin_mesh_gbuffer_fragment",
                        depthFormat: depth, isGBuffer: true)
        }
        // the deferred reflection trace: a full-screen pass writing two attachments, the
        // radiance the ray found and the ray that found it. The second is read only by the
        // glossy resolve (which reuses a neighbor's ray as a sample of its own lobe), but
        // it is written either way, so one fragment serves both paths and cannot drift.
        static let rtReflectTrace = PipelineKey(vertex: "ollin_present_vertex",
                                                fragment: "ollin_rt_reflect_trace",
                                                isGBuffer: true, gBufferAttachments: 2)
        // caustics G-buffer: the reflection G-buffer's recipe plus a third attachment
        // for the baked vertex color, which the photon-splat pass shades against.
        // Only encoded when caustics are active on a ray-tracing device.
        static func causticsGBuffer(depth: MTLPixelFormat) -> PipelineKey {
            PipelineKey(vertex: "ollin_caustics_gbuffer_vertex",
                        fragment: "ollin_caustics_gbuffer_fragment",
                        depthFormat: depth, isGBuffer: true, gBufferAttachments: 3)
        }
        // caustics photon splat: instanced elliptical footprints, additively blended
        // into the single-sample caustics layer; the fragment depth-tests manually
        // against the caustics G-buffer's depth, so the pass carries no depth.
        static let causticsSplat = PipelineKey(vertex: "ollin_caustics_splat_vertex",
                                               fragment: "ollin_caustics_splat_fragment",
                                               isCausticSplat: true)
        // subsurface-scatter mask: re-render the meshes single-sample into one float
        // attachment (uv-space blur step, mark, view depth, profile index) with its own
        // depth, so occluders suppress hidden scattering surfaces. Feeds the separable
        // diffusion blur; only encoded when the frame carries a scattering material.
        static func scatterMask(depth: MTLPixelFormat) -> PipelineKey {
            PipelineKey(vertex: "ollin_mesh_scatter_vertex", fragment: "ollin_mesh_scatter_fragment",
                        depthFormat: depth, isScatterMask: true)
        }
        // mover velocity (temporal AA): re-render this frame's declared movers
        // single-sample into an rg16Float screen-motion texture with its own depth,
        // so the resolve reprojects their history exactly. Only encoded when TAA is
        // live and the frame declared movers (`withMotion`).
        static func meshVelocity(depth: MTLPixelFormat) -> PipelineKey {
            PipelineKey(vertex: "ollin_mesh_velocity_vertex",
                        fragment: "ollin_mesh_velocity_fragment",
                        depthFormat: depth, isVelocity: true)
        }
        // the velocity pass's depth-only occluder phase: everything that is not a
        // mover, rasterized for depth alone (the plain mesh vertex, no fragment,
        // color masked off) so a hidden mover loses the depth test.
        static func meshVelocityOccluder(depth: MTLPixelFormat) -> PipelineKey {
            PipelineKey(vertex: "ollin_mesh_vertex", fragment: "",
                        depthFormat: depth, isVelocity: true, isVelocityOccluder: true)
        }
        // depth-scene backdrop: a textured quad that also writes per-pixel depth from
        // a depth map (premultiplied color, like the image path; outputs [[depth]]).
        static func depthScene(_ blend: BlendMode, depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_image_vertex", fragment: "ollin_depthscene_fragment",
                        blend: blend, premultiplied: true, depthFormat: depth)
        }
        // clip push: rasterize the clip region's fill triangles into the stencil
        // (increment where the current level passes); stencil-only, color masked off.
        static func clipWrite(depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_vertex", fragment: "ollin_clip_fragment",
                        depthFormat: depth, stencilFormat: .stencil8, isClipWrite: true)
        }
        // clip pop: one fullscreen triangle that decrements the popped level back
        // wherever the push raised it; stencil-only, color masked off.
        static func clipCover(depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_clip_cover_vertex", fragment: "ollin_clip_fragment",
                        depthFormat: depth, stencilFormat: .stencil8, isClipWrite: true)
        }
        // final fullscreen tone-map pass, float -> sRGB drawable
        static let present = PipelineKey(vertex: "ollin_present_vertex",
                                         fragment: "ollin_present_fragment", isPresent: true)
        // the same pass warped onto a wall and faded at its edges (screen only)
        static let presentProjected = PipelineKey(vertex: "ollin_present_vertex",
                                                  fragment: "ollin_present_projected_fragment",
                                                  isPresent: true, isProjected: true)
        // an effects filter pass: a fullscreen-triangle `fragment` (sharing the
        // present vertex) writing the linear-float intermediate, single-sample, replace.
        static func effect(_ fragment: String, format: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_present_vertex", fragment: fragment,
                        isEffect: true, effectFormat: format)
        }
        // depth-only shadow pass (mesh geometry from the light's point of view)
        static let meshShadow = PipelineKey(vertex: "ollin_mesh_shadow_vertex",
                                            fragment: "", isShadow: true)
        // the instanced sibling: instanced-mesh copies cast into the same 2D map
        static let meshInstancedShadow = PipelineKey(vertex: "ollin_mesh_instanced_shadow_vertex",
                                                     fragment: "", isShadow: true)
        // the MeshField siblings: a field casts uncculled, its draw-time matrix composed
        static let meshFieldShadow = PipelineKey(vertex: "ollin_mesh_field_shadow_vertex",
                                                 fragment: "", isShadow: true)
        static let meshFieldPointShadowMin = PipelineKey(
            vertex: "ollin_mesh_field_point_shadow_vertex",
            fragment: "ollin_mesh_point_shadow_fragment", isShadow: true, pointShadowOp: 1)
        static let meshFieldPointShadowMax = PipelineKey(
            vertex: "ollin_mesh_field_point_shadow_vertex",
            fragment: "ollin_mesh_point_shadow_fragment", isShadow: true, pointShadowOp: 2)
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
        // the instanced siblings: each copy into all six cube faces (6 * copies instances)
        static let meshInstancedPointShadowMin = PipelineKey(
            vertex: "ollin_mesh_instanced_point_shadow_vertex",
            fragment: "ollin_mesh_point_shadow_fragment", isShadow: true, pointShadowOp: 1)
        static let meshInstancedPointShadowMax = PipelineKey(
            vertex: "ollin_mesh_instanced_point_shadow_vertex",
            fragment: "ollin_mesh_point_shadow_fragment", isShadow: true, pointShadowOp: 2)

        /// The pipeline a recorded batch needs, from its geometry kind, blend, the
        /// active depth format (nil in 2D), and — for a mesh — whether it's textured.
        static func forBatch(_ kind: GeometryKind, _ blend: BlendMode,
                             depth: MTLPixelFormat? = nil, textured: Bool = false,
                             wireframe: Bool = false, matcap: Bool = false,
                             grid: Bool = false, normalMapped: Bool = false,
                             surfaceMapped: Bool = false, light: Bool = false) -> PipelineKey {
            switch kind {
            case .triangles:  return .solid(blend, depth: depth)
            case .fringe:     return .fringe(blend, depth: depth)
            case .sdf:        return .sdf(blend, depth: depth)
            case .sdfGroup:   return .sdfGroup(blend, depth: depth)
            case .sdfGroup3D: return .raymarch(blend, depth: depth)
            case .image:      return .image(blend, depth: depth)
            case .glyphAtlas: return .glyphAtlas(blend, depth: depth)
            case .particles:  return .points(blend, depth: depth, light: light)
            case .points3D:   return .pointCloud(blend, depth: depth)
            case .mesh3D:
                return grid          ? .grid(blend, depth: depth)
                     : wireframe     ? .meshWireframe(blend, depth: depth)
                     : matcap        ? .meshMatcap(blend, depth: depth)
                     : surfaceMapped ? .meshSurfaceMapped(blend, depth: depth)
                     : normalMapped  ? .meshNormalMapped(blend, depth: depth)
                     : textured      ? .meshTextured(blend, depth: depth)
                                     : .mesh(blend, depth: depth)
            case .meshInstanced: return .meshInstanced(blend, depth: depth)
            case .meshField:  return .meshField(blend, depth: depth)
            case .strands:    return .strands(blend, depth: depth)
            case .ocean:      return .ocean(blend, depth: depth)
            case .depthScene: return .depthScene(blend, depth: depth)
            case .clipPush:   return .clipWrite(depth: depth)
            case .clipPop:    return .clipCover(depth: depth)
            // Never reached: a `.retained` reference batch is handed off before the
            // pipeline lookup (its inner runs each resolve their own key here).
            case .retained:   return .solid(blend, depth: depth)
            }
        }
    }

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var library: MTLLibrary
    /// The display/drawable format. sRGB 8-bit by default; a wide-gamut or
    /// high-dynamic-range sketch presents into `rgba16Float` instead (see
    /// `ColorOutput`). The final present pass writes here; it's never a geometry
    /// render target anymore.
    let pixelFormat: MTLPixelFormat
    /// How the present pass encodes for that format: 8-bit sRGB (the shipped
    /// path), linear Display P3, or PQ Rec. 2020 for an HDR video frame. Fixed
    /// for the renderer's lifetime, like `pixelFormat`, which it pairs with.
    let presentEncoding: PresentEncoding
    /// The brightest value the present pass will send, as a multiple of SDR
    /// white. 1 is standard range and stays that way; an `extended` sketch's
    /// host raises it each frame to the display's reported headroom, so nothing
    /// is sent that the panel would only clip anyway (the host applies
    /// `ColorOutput.ceiling(displayHeadroom:)`, so `wide` stays at 1 whatever
    /// the screen can do). Unused by the 8-bit and PQ paths.
    var presentCeiling: Float
    /// How the presented frame is fitted to what it is thrown onto: nil at a
    /// desk, a resolved placement while a piece runs under an
    /// `Installation.Projection`. Set by the host that owns the window, and read
    /// only where the frame goes to a drawable, so no export carries it.
    var projection: ProjectionPlacement?
    /// How large the canvas has to be drawn to feed every display it goes on,
    /// when it goes on more than one. Nil for the ordinary run, where the one
    /// drawable it is presented into says how large it needs to be.
    ///
    /// A wall asks for more than the display drawing it: a projector carrying
    /// half the canvas at its own resolution needs the whole canvas drawn at
    /// twice that. Set by the host that owns the windows, once the displays are
    /// known and again when they change.
    var wallDemand: CGSize?
    /// The compositing substrate: a linear `rgba16Float` intermediate every
    /// geometry pipeline renders into, so values can exceed 1.0 (additive light)
    /// and many translucent blends don't band the way an 8-bit target would. The
    /// present pass tone-maps + encodes it down to `pixelFormat`.
    let linearFormat: MTLPixelFormat = .rgba16Float
    /// MSAA sample count for the float geometry targets (the drawable itself is
    /// single-sample — MSAA happens in the intermediate, then resolves before the
    /// present pass tone-maps).
    let sampleCount: Int
    /// Depth format for 3D passes (an active `Camera3D`). 2D passes carry no depth
    /// attachment, so a 2D sketch allocates none of this.
    let depthPixelFormat: MTLPixelFormat = .depth32Float

    /// Render pipelines, built on first use and reused. Keyed by `Pipeline` so
    /// a new capability is a new case + a branch in `makePipeline(_:)`, never
    /// more inline construction in `init` (see CLAUDE.md).
    var pipelines: [PipelineKey: MTLRenderPipelineState] = [:]

    /// Compute kernels are open-ended (one per user source), so they can't be a
    /// fixed enum like the render pipelines. They're cached separately, keyed by a
    /// hash of the composed source + the entry name. The composed *library* is
    /// cached per source too, so several entries in one source share one compile.
    struct ComputeKey: Hashable { let sourceHash: UInt64; let entry: String }
    var computePipelines: [ComputeKey: MTLComputePipelineState] = [:]
    var computeLibraries: [UInt64: MTLLibrary] = [:]
    /// The same pipelines keyed by the kernel's own source alone, for a kernel
    /// written in the sketch's source: the library half of its composed text
    /// never changes within a process, so a hit here skips composing it (the
    /// shared library read and its includes resolved, then a hash over the
    /// whole text) on every dispatch of every frame. A runner's sample once
    /// put two thirds of a GPU simulation test's time in that composition.
    /// A kernel loaded from a file is not keyed here, since a file it includes
    /// may have been edited under it and the composed hash is what notices.
    var quickComputePipelines: [ComputeKey: MTLComputePipelineState] = [:]

    /// User-supplied shaders (the `Shader` type) compile to their own small library,
    /// like compute kernels: keyed by a hash of the composed source (lib + wrapper +
    /// user code), so a shader recompiles only when its source changes, not per frame.
    /// A *failed* compile is cached too (`userShaderErrors`) so a broken shader doesn't
    /// retry every frame; the cache is cleared on a framework-shader reload.
    enum UserShaderVariant { case generator, filter, combine }
    var userShaderLibraries: [UInt64: MTLLibrary] = [:]
    var userShaderPipelines: [UInt64: MTLRenderPipelineState] = [:]
    var userShaderErrors: [UInt64: ShaderCompileError] = [:]
    /// Contents of `.metal` resource shaders, with their own `#include`s already
    /// resolved, cached by absolute path (read once, not per frame). Cleared on
    /// invalidation so an edited `.metal`, or an edited file it includes, is re-read.
    var userShaderSources: [String: ResolvedShaderSource] = [:]
    /// A shader's source with its includes resolved, beside anything the resolver could
    /// not honor (a file it could not find, a cycle). A problem is reported as the
    /// shader's compile error, before the compiler is ever asked.
    struct ResolvedShaderSource {
        let source: String
        let problems: [String]
    }
    /// Hashes already printed to stderr, so a broken shader logs once (for a plain
    /// `swift run`), not every frame.
    var printedShaderErrorHashes: Set<UInt64> = []
    /// This frame's user-shader compile state, reset to `nil` at the top of each
    /// render and set when a shader fails to compile. The host (OllinLive) reads it
    /// after each frame to drive the on-screen error overlay; a standalone run
    /// ignores it and relies on the stderr print.
    var currentUserShaderError: ShaderCompileError?
    /// The current frame's time/mouse/frame values, snapshotted at the top of the
    /// effect pass so a user shader (generator, filter, or combine) can fill its
    /// `ShaderInfo` without threading the drawer through every effect call site.
    var frameComputeUniforms = OllinComputeUniforms(
        resolution: .zero, mouse: .zero, time: 0, dt: 0, frameCount: 0, particleCount: 0, custom: .zero)

    /// The frame being encoded, counted as it goes: draw calls, passes, and the
    /// geometry each path carried, plus the four-way time split. The runner
    /// reads it right after `render(...)` and hands it to the extensions on
    /// `FrameInfo`, so a profiler reads the same numbers the renderer acted on.
    var profile = FrameProfile()

    /// Whether to record the name of each pass as it is encoded. Off by default
    /// and armed for a single frame by the GPU capture, so a normal frame pays
    /// one boolean test per pass.
    var logsPassNames = false
    /// The names of the passes encoded while `logsPassNames` was on, in order.
    var passLog: [String] = []

    /// The last finished command buffer's GPU time, in milliseconds. Written
    /// from the completed handler, which runs off the main actor, so it rides a
    /// lock rather than the renderer's own (main-actor) state. Read one or two
    /// frames later, which the smoothing in `FrameStats` hides.
    let gpuFrameMS = OSAllocatedUnfairLock(initialState: 0.0)

    /// Make a render encoder and count the pass. Every pass in the renderer
    /// goes through here, so the profile's pass count stays honest as passes
    /// are added: a new shadow, probe, or filter pass counts itself.
    func countedEncoder(_ buffer: MTLCommandBuffer,
                        _ descriptor: MTLRenderPassDescriptor,
                        caller: String = #function) -> MTLRenderCommandEncoder? {
        // Naming the caller costs nothing at a call site (the compiler fills it
        // in), and it turns the pass count into a pass *list* for one frame when
        // something asks: the GPU capture prints it, so a sketch can see which
        // passes it is paying for and not only how many.
        if logsPassNames { passLog.append(caller) }
        profile.passes += 1
        return buffer.makeRenderCommandEncoder(descriptor: descriptor)
    }

    /// Triple-buffered vertex storage, gated by a semaphore so the CPU never
    /// overwrites vertices the GPU is still reading. Writing one shared buffer
    /// every frame with no synchronization tears the on-screen geometry (e.g.
    /// gaps in a stroked ring) because the next frame stomps it mid-draw. Each
    /// slot is grown on demand to keep steady-state frames allocation-free.
    private static let maxFramesInFlight = 3
    private let frameBoundary = DispatchSemaphore(value: MetalRenderer.maxFramesInFlight)
    /// How many of those slots the GPU still holds, kept beside the semaphore
    /// because a semaphore cannot be asked: waiting on it is the only way to
    /// learn, and that wait lands on whichever thread starts the frame. On the
    /// live path that is the main thread, which is also the one AppKit and
    /// SwiftUI run on, so a frame the GPU has no room for freezes the window
    /// rather than merely slowing the picture. `canStartFrame` is the question
    /// asked instead; every slot claimed and every slot handed back below moves
    /// this with the semaphore, the GPU's completed handler included.
    private let framesInFlight = OSAllocatedUnfairLock(initialState: 0)
    /// Whether a frame can start without the caller waiting on the GPU.
    ///
    /// False means every buffer in the ring is still in flight. A caller that
    /// draws anyway is not wrong, only blocked: it stops until the GPU hands a
    /// slot back. The live path asks first and skips the whole refresh instead,
    /// so a sketch heavy enough to fall behind gives slow frames and a window
    /// that still answers the mouse, rather than a picture and a window that
    /// both stop. Nothing else in the frame is skipped by asking: a skipped
    /// refresh does not draw, so it has nothing to throw away.
    var canStartFrame: Bool {
        framesInFlight.withLock { $0 } < MetalRenderer.maxFramesInFlight
    }

    /// Take a slot in the ring, blocking until one is free. Paired with
    /// `returnFrameSlot()`, and the two must stay in lockstep or the count the
    /// live path reads drifts from the semaphore it mirrors.
    private func takeFrameSlot() {
        frameBoundary.wait()
        framesInFlight.withLock { $0 += 1 }
    }

    /// Hand a slot back on a frame that encoded nothing. The GPU's own
    /// completed handler does the same pair inline, since it runs off-actor.
    private func returnFrameSlot() {
        framesInFlight.withLock { $0 -= 1 }
        frameBoundary.signal()
    }
    var vertexBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    /// Parallel ring for SDF instance data, advanced with `frameIndex` alongside
    /// `vertexBuffers` (one semaphore gates both — they're written and read
    /// together each frame).
    var sdfBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    var frameIndex = 0

    /// A separate vertex buffer for off-screen `image(of:)` renders, so headless
    /// export never shares a slot with the on-screen ring. Export is synchronous
    /// (it waits for the GPU before reading back), so one reusable buffer is
    /// enough — no ring needed — but it must not be a ring slot the live loop
    /// could still be reading for an in-flight frame.
    var exportBuffer: MTLBuffer?
    var sdfExportBuffer: MTLBuffer?

    /// Parallel ring + export buffers for the SDF-combinator group instances and
    /// their flat node programs, advanced with `frameIndex` like the others.
    var sdfGroupBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    var sdfNodeBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    var sdfGroupExportBuffer: MTLBuffer?
    var sdfNodeExportBuffer: MTLBuffer?
    var sdf3DGroupBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    var sdf3DNodeBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    var sdf3DGroupExportBuffer: MTLBuffer?
    var sdf3DNodeExportBuffer: MTLBuffer?

    /// Parallel ring + export buffer for textured-quad (image) vertices, advanced
    /// with `frameIndex` like the others.
    var imageBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    var imageExportBuffer: MTLBuffer?

    /// Parallel ring + export buffer for SDF-atlas text quads (also
    /// `OllinImageVertex`), advanced with `frameIndex` like the others.
    var glyphBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    var glyphExportBuffer: MTLBuffer?

    /// Parallel ring + export buffer for 3D point-cloud splats (`OllinPoint`),
    /// advanced with `frameIndex` like the others.
    var pointBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    var pointExportBuffer: MTLBuffer?

    /// Parallel ring + export buffer for solid 3D mesh vertices (`OllinMeshVertex`),
    /// advanced with `frameIndex` like the others.
    var meshBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    var meshExportBuffer: MTLBuffer?

    /// Parallel rings + export buffers for instanced mesh draws: the local-space
    /// base-mesh vertices (`OllinMeshVertex`) and the per-copy placements
    /// (`OllinMeshInstance`), advanced with `frameIndex` like the others.
    var instancedMeshBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    var instancedMeshExportBuffer: MTLBuffer?
    var meshInstanceBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    var meshInstanceExportBuffer: MTLBuffer?

    /// Depth-stencil states for the 3D path, built once. 3D geometry z-tests
    /// (less-equal) and writes depth; 2D batches in a 3D pass leave depth alone
    /// (always-pass, no write) so they composite over in draw order.
    lazy var depthTestState: MTLDepthStencilState? = {
        let d = MTLDepthStencilDescriptor()
        d.depthCompareFunction = .lessEqual
        d.isDepthWriteEnabled = true
        return device.makeDepthStencilState(descriptor: d)
    }()
    lazy var noDepthState: MTLDepthStencilState? = {
        let d = MTLDepthStencilDescriptor()
        d.depthCompareFunction = .always
        d.isDepthWriteEnabled = false
        return device.makeDepthStencilState(descriptor: d)
    }()
    // The ground-grid overlay: z-tests (so scene meshes occlude it) but does *not* write
    // depth, so its transparent gaps (and the plane itself) occlude nothing.
    lazy var depthTestNoWriteState: MTLDepthStencilState? = {
        let d = MTLDepthStencilDescriptor()
        d.depthCompareFunction = .lessEqual
        d.isDepthWriteEnabled = false
        return device.makeDepthStencilState(descriptor: d)
    }()

    /// Depth-stencil states for the stencil-clipping path (`withClip`), built on first
    /// use. The three content depth configs above each gain a variant that stencil-tests
    /// `equal` against the batch's clip level (the reference value set per batch); the
    /// two clip-write ops raise (`push`: increment where the enclosing level passes) and
    /// lower (`pop`: decrement the popped level) the stencil without touching depth.
    /// Only a stencil-carrying pass ever sets one, so the no-clip paths never look here.
    struct ClipStateKey: Hashable {
        enum Depth { case always, test, testNoWrite }
        enum Stencil { case equal, push, pop }
        var depth: Depth
        var stencil: Stencil
    }
    private var clipDepthStencilStates: [ClipStateKey: MTLDepthStencilState] = [:]
    func clipDepthStencilState(_ key: ClipStateKey) -> MTLDepthStencilState? {
        if let cached = clipDepthStencilStates[key] { return cached }
        let d = MTLDepthStencilDescriptor()
        switch key.depth {
        case .always:
            d.depthCompareFunction = .always
            d.isDepthWriteEnabled = false
        case .test:
            d.depthCompareFunction = .lessEqual
            d.isDepthWriteEnabled = true
        case .testNoWrite:
            d.depthCompareFunction = .lessEqual
            d.isDepthWriteEnabled = false
        }
        let s = MTLStencilDescriptor()
        s.stencilCompareFunction = .equal
        switch key.stencil {
        case .equal: s.depthStencilPassOperation = .keep
        case .push:  s.depthStencilPassOperation = .incrementClamp
        case .pop:   s.depthStencilPassOperation = .decrementClamp
        }
        d.frontFaceStencil = s
        d.backFaceStencil = s
        let made = device.makeDepthStencilState(descriptor: d)
        clipDepthStencilStates[key] = made
        return made
    }

    /// Cached memoryless MSAA stencil attachments for clipping passes, one per size
    /// (see `clipStencilTexture`). Tile-only, so reuse across passes and frames is safe.
    var clipStencilTextures: [MTLTexture] = []

    /// Shadow mapping (opt-in via `castShadows()`). The depth pass from the casting
    /// light renders into `shadowMap` — a square `.private` depth texture sampled in
    /// the lit mesh fragment. `shadowMapResolution` must match `Drawer`'s (which uses
    /// it to size the normal-offset bias in world units). `dummyShadowMap` is a 1×1
    /// depth texture bound when shadows are off, so the mesh fragment's declared
    /// `depth2d` argument is always satisfied without a separate pipeline variant.
    /// `shadowSampler` is a comparison sampler (lessEqual) for hardware PCF.
    static let shadowMapResolution = 2048
    var shadowMap: MTLTexture?
    var dummyShadowMap: MTLTexture?
    var dummyDepth: MTLTexture?
    /// The omnidirectional (point) shadow maps: a **cube array** rendered by the layered
    /// six-face pass and sampled by direction, one cube per point caster in the frame (a
    /// point light casts from any slot). Per-face resolution; allocated lazily on the
    /// first point-casting frame and re-made wider when a frame wants more cubes.
    /// `dummyPointShadowMap` is a 1x1 single-cube array bound when no point caster is
    /// active, so the fragment's declared `texturecube_array` is always satisfied.
    static let pointShadowMapResolution = Int(OLLIN_POINT_SHADOW_RESOLUTION)
    var pointShadowMap: MTLTexture?
    var dummyPointShadowMap: MTLTexture?
    /// The far plane the cube pass fitted to the frame's geometry, per casting light
    /// (keyed by its index in the packed light array), carried from that pass to the
    /// lighting the fragment reads (the packing's own guess is the camera's framing
    /// radius, which the light does not respect). Empty whenever no cube was rendered,
    /// which is every frame on a device that traces its point casters.
    var pointShadowFars: [Int32: Float] = [:]
    /// Whether this device can trace rays from the render stages. When true, a point
    /// caster is shadowed by *ray tracing* (an exact visibility ray against a per-frame
    /// acceleration structure built from the shadow casters) instead of the mid-point
    /// cube — no depth compare, so no acne/peter-pan/teeth tradeoff. The `Shader3D.metal`
    /// mesh fragments are compiled with `OLLIN_RT_SHADOWS` set from this, and the cube
    /// path stays the byte-identical fallback on devices without it.
    let rayTracedShadows: Bool
    /// Whether render-stage ray tracing is available *and* wanted. `OLLIN_NO_RAY_TRACING=1`
    /// in the environment answers false on a device that can trace, which is the only way
    /// to exercise the rasterized fallbacks (chiefly the point caster's mid-point cube) on
    /// a machine that always traces instead. Read in the two places that decide the render
    /// path: this initializer, and the shader compile that sets `OLLIN_RT_SHADOWS`.
    static func rayTracingAvailable(on device: MTLDevice) -> Bool {
        if ProcessInfo.processInfo.environment["OLLIN_NO_RAY_TRACING"] == "1" { return false }
        return device.supportsRaytracing && device.supportsRaytracingFromRender
    }
    /// Whether this device can actually be *driven* through a mesh pipeline: the
    /// strand fields' gate, and the only thing standing between a virtual machine
    /// and a killed process.
    ///
    /// `metal3` is the family the mesh stages require, and it is the only signal
    /// here that tells the truth. A paravirtualized GPU (what a virtual machine
    /// hands through, and what a hosted runner has) reports it false and then
    /// accepts everything built on it anyway: it compiles the `[[object]]` and
    /// `[[mesh]]` stages, builds an `MTLMeshRenderPipelineDescriptor` without
    /// complaint, and its encoder answers `respondsToSelector:` with true for
    /// every one of the calls below. The first one made then raises
    /// `unrecognized selector`, which is an Objective-C exception rather than an
    /// error Swift can catch, so the process dies where a missing feature should
    /// merely have drawn nothing.
    ///
    /// Measured on the hosted runner, 2026-09-01: `Apple Paravirtual device`,
    /// `apple5` and `mac2` true, `apple6` through `apple9` and `metal3` false,
    /// the pipeline built, all four selectors answered true, and
    /// `setObjectBytes` exited 134. So neither building the pipeline nor asking
    /// the encoder can stand in for the family, and both were tried.
    nonisolated static func meshShadersAvailable(on device: MTLDevice) -> Bool {
        if ProcessInfo.processInfo.environment["OLLIN_NO_MESH_SHADERS"] == "1" { return false }
        return device.supportsFamily(.metal3)
    }
    /// Whether the strand fields' mesh pipeline can be driven on this device
    /// (`meshShadersAvailable(on:)`, resolved once at init).
    let hasMeshShaders: Bool
    /// Whether the GPU has *dedicated* ray-tracing units (the A17/M3 generation and later,
    /// `MTLGPUFamily.apple9`+). The M1/M2 trace in software, ~5-10× slower, so the hardware-
    /// relative `Quality` tiers map to a higher ray count here than on a software-RT GPU.
    let hasHardwareRayTracing: Bool
    /// The per-frame acceleration structure (rebuilt each point-RT-shadow frame from the
    /// shadow-caster triangles) and its scratch buffer, both grown in place as the scene
    /// size demands. `dummyShadowAccel` is a 1-triangle structure bound to the lit mesh
    /// fragment whenever no RT point shadow is active this frame, so its declared
    /// `instance_acceleration_structure` argument is always satisfied (the fragment only
    /// traces it when `shadowKind == 2`).
    var shadowAccel: MTLAccelerationStructure?
    var shadowAccelScratch: MTLBuffer?
    var shadowAccelCapacity = 0
    var dummyShadowAccel: MTLAccelerationStructure?
    /// The traced scene is an *instance* structure over the structures above: one
    /// instance for every mesh drawn on its own (`shadowAccel`, its vertices already
    /// placed) and one per copy of an instanced draw, each referring to its base
    /// mesh's own structure (`rtCopyAccels`, one per instanced batch) and carrying
    /// that copy's matrix. That is what puts a copy in a mirror, in a traced shadow,
    /// and in the bounce light, all of which see one structure. Same grow-in-place
    /// rule as the scene structure, and the descriptors ride the per-frame ring
    /// because the build reads them on the GPU.
    var rtCopyAccels: [MTLAccelerationStructure] = []
    var rtCopyAccelCapacities: [Int] = []
    var rtInstanceAccel: MTLAccelerationStructure?
    var rtInstanceAccelCapacity = 0
    var rtInstanceDescriptorBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    var dummyInstanceAccel: MTLAccelerationStructure?
    /// The structures the traced scene's instance structure is built over. An instance
    /// structure reaches them indirectly, so an encoder that binds the top one has to
    /// mark these resident itself, which `useTracedScene` does at every bind site.
    var rtReferencedAccels: [MTLAccelerationStructure] = []
    /// The base-vertex value that marks the plain-mesh instance in the hit-lookup
    /// table: it reads the per-geometry table instead of carrying one vertex of its
    /// own. Mirrors `OLLIN_RT_PLAIN_MESH` in the shader library.
    static let rtPlainMesh: UInt32 = 0xFFFF_FFFF
    /// Ray-traced reflections: per-geometry base-vertex offsets (one `UInt32` per coalesced
    /// caster geometry in `shadowAccel`) so a reflection hit's `(geometryId, primitiveId)`
    /// resolves to a vertex in the flat mesh buffer. Filled CPU-side in `buildShadowAccel`,
    /// so it rides the same per-frame ring as every other CPU-written buffer: an in-flight
    /// frame may still be tracing with the previous offsets while the next frame encodes.
    /// `dummyGeoOffsets` is the 1-element stand-in bound when reflections are off, so the
    /// RT-compiled mesh fragment's declared offsets argument is always satisfied.
    var meshGeoOffsetBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    var dummyGeoOffsets: MTLBuffer?
    /// Per-geometry caustic materials (`OllinCausticGeo`, parallel to the offsets):
    /// what the photon trace needs at a hit that the baked vertex slots don't carry
    /// (transmission, index of refraction, the interior attenuation). CPU-filled at
    /// accel-build time, so it rides the same per-frame ring as the offsets.
    var causticGeoMatBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    /// Per-geometry full batch finishes (`OllinMaterial`, parallel to the offsets) for
    /// the offline path-traced export: the accel build breaks its coalesced runs where
    /// the finish changes while path tracing, so a hit resolves its whole material.
    /// Same per-frame ring rule as the offsets and the caustic materials.
    var ptGeoMatBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    /// The offline path-traced export settings, set only by the headless export
    /// drivers (`--path-traced`); nil live and everywhere else, which is what keeps
    /// the raster pipeline byte-identical whenever the mode is off.
    var pathTracing: PathTracing?
    /// The instanced and field batches this frame's traced scene took, by index into
    /// the drawer's batch list. Filled by the path-traced build, read by the geometry
    /// pass: a batch in the set is already in the traced layer and skips its raster
    /// draw, while one that fell out (an over-budget field, a matcap prop) rasters
    /// instead, depth-tested against the traced depth. Empty whenever the mode is
    /// off, so nothing outside the export ever consults it.
    var pathTracedCopyBatches: Set<Int> = []
    /// Whether the trace prints its rewriting progress line. The still export leaves
    /// it on (a minutes-long render should say where it is); the sequence and video
    /// drivers turn it off and keep their own per-frame line instead.
    var pathTraceReportsProgress = true
    /// Export-only spatial supersampling: the frame is drawn `renderScale` times
    /// across the canvas, then averaged back down to canvas size in linear light,
    /// ahead of the tone map. 1 (the default, and always the live window) renders
    /// exactly as before. `--render-scale` sets it through `OllinApp.exportRenderScale`.
    var renderScale = 1
    /// Set while a linear-light export runs (`--export-exr`): the frame keeps the
    /// float canvas the present pass is about to read, and the scene's own depth
    /// beside it, in `lastLinearFrame`. Off otherwise, so no other export pays for
    /// the copy.
    var capturesLinearFrame = false
    /// The frame kept by the last render under `capturesLinearFrame`.
    var lastLinearFrame: LinearFrame?
    /// Whether the clamp notice was printed, so a sequence says it once, not per frame.
    private var reportedRenderScaleClamp = false
    /// The same, for the notice that a piling canvas does not take the supersample.
    private var reportedAccumulationScale = false
    /// The ceiling on the supersample. 4x is already 16x the fragment work.
    static let maxRenderScale = 4
    /// The widest a Metal 2D texture can be on the supported devices.
    static let maxTextureSide = 16384

    /// How much of the asked-for `renderScale` a frame of this size can take: at
    /// most `maxRenderScale`, and never wider than a texture can be. A reduction
    /// is said out loud once, never silently.
    func supersampleScale(width: Int, height: Int) -> Int {
        let asked = max(1, renderScale)
        guard asked > 1 else { return 1 }
        var scale = min(asked, MetalRenderer.maxRenderScale)
        while scale > 1, max(width, height) * scale > MetalRenderer.maxTextureSide { scale -= 1 }
        if scale < asked, !reportedRenderScaleClamp {
            reportedRenderScaleClamp = true
            print("Ollin: a render scale of \(asked)x is more than this canvas can take; rendering at \(scale)x.")
        }
        return scale
    }
    /// The environment-sampling tables (luminance CDFs + solid-angle pdf grid) the
    /// path-traced export builds per equirect, cached by texture identity so a
    /// sequence export builds them once. Export-only and small (a few hundred KB per
    /// environment), so the cache never needs eviction.
    var ptEnvTableCache: [ObjectIdentifier: MTLBuffer] = [:]
    lazy var shadowSampler: MTLSamplerState? = {
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
    lazy var shadowCubeSampler: MTLSamplerState? = {
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
    var halfResColor: MTLTexture?
    var halfResDepth: MTLTexture?
    var halfResSize = (width: 0, height: 0)

    /// The half-resolution point/RT field-cast shadow target (the live RenderQuality path): the
    /// receiver meshes are re-rendered into it (depth-tested) with only their field-shadow factor,
    /// and the full-res mesh pass samples it instead of marching per pixel. `color` is single-
    /// channel-by-convention (R holds the factor); `depth` keeps the front surface's factor.
    var halfResFieldShadow: MTLTexture?
    var halfResFieldShadowDepth: MTLTexture?
    var halfResFieldShadowSize = (width: 0, height: 0)

    /// The contact-shadow pre-pass targets (`contactShadows()`): the frame's solid canvas
    /// meshes re-rendered depth-only from the camera, then the fullscreen march writes the
    /// per-pixel visibility toward the caster into `mask` (R holds the factor, 1 = lit),
    /// which the mesh fragments sample by screen position. Cached by size, rewritten whole
    /// each frame the feature is on.
    var contactShadowMaskTex: MTLTexture?
    var contactShadowDepthTex: MTLTexture?
    var contactShadowSize = (width: 0, height: 0)

    /// The scene-behind pre-pass targets (`sceneThroughGlass()`): the whole frame drawn
    /// once more with every transmissive run left out, into the same MSAA color format
    /// and depth the main pass uses, resolving into a *mipmapped* texture the glass reads
    /// (the mip chain is the roughness blur, so a frosted body softens the scene the way
    /// it softens the environment). Cached by size, rewritten whole each frame the
    /// feature is on. `.private`, so nothing round-trips to the CPU.
    var sceneBehindMSAATex: MTLTexture?
    var sceneBehindDepthTex: MTLTexture?
    var sceneBehindDepthResolveTex: MTLTexture?
    var sceneBehindResolveTex: MTLTexture?
    var sceneBehindSize = (width: 0, height: 0)

    /// How far into the frame the scene-behind read fades out, in uv. A screen-space
    /// lookup knows only what the camera drew, so rather than smearing the border pixel
    /// across a body's edge, the sample eases back into the refracted environment across
    /// this band. Two percent of the frame is wide enough to read as a soft handover and
    /// narrow enough to leave the middle of a picture untouched.
    var sceneBehindEdgeFade: Float { 0.02 }

    /// Per-frame-ring pools of effects-layer textures, reused across frames so a
    /// sketch that uses render targets every frame allocates them once. Keyed by the
    /// ring slot (`frameIndex`) so a texture is never reused while an in-flight frame
    /// still reads it: the same discipline as the vertex-buffer ring. `*Next` is the
    /// per-frame acquisition cursor, reset at the start of the effects graph.
    var targetTexPool: [[(msaa: MTLTexture, resolve: MTLTexture, w: Int, h: Int, format: MTLPixelFormat)]] =
        Array(repeating: [], count: MetalRenderer.maxFramesInFlight)
    var filterTexPool: [[(tex: MTLTexture, w: Int, h: Int)]] =
        Array(repeating: [], count: MetalRenderer.maxFramesInFlight)
    /// The `rg32Float` pair a measured distance field ping-pongs through, pooled on the
    /// same ring discipline (a flood writes them every pass, so sharing one across frames
    /// in flight would tear the field).
    var fieldTexPool: [[(tex: MTLTexture, w: Int, h: Int)]] =
        Array(repeating: [], count: MetalRenderer.maxFramesInFlight)
    /// The `rgba32Float` pair a summed-area table scans through, pooled on the same ring
    /// discipline. Wide because the table holds sums rather than colors: a canvas of ones
    /// adds up past a million, and a half float cannot count that far in whole numbers.
    var satTexPool: [[(tex: MTLTexture, w: Int, h: Int)]] =
        Array(repeating: [], count: MetalRenderer.maxFramesInFlight)
    /// Depth attachments for a render target that holds a 3D scene: an MSAA depth
    /// buffer (memoryless, tile-only) that resolves into a single-sample sampleable
    /// `depth32Float`, the `depth` layer reads from. Pooled like the color targets,
    /// but only a depth-carrying target ever pulls from it, so 2D targets cost nothing.
    var targetDepthPool: [[(msaa: MTLTexture, resolve: MTLTexture, w: Int, h: Int)]] =
        Array(repeating: [], count: MetalRenderer.maxFramesInFlight)
    var targetTexNext = 0
    var filterTexNext = 0
    var fieldTexNext = 0
    var satTexNext = 0
    var targetDepthNext = 0

    /// One `Feedback` layer's persistent ping-pong pair: two single-sample
    /// linear-float resolve textures. Each frame the block renders into the *back*
    /// (`flipped ? a : b`) while the sketch reads the *front* (`flipped ? b : a`),
    /// then `flipped` toggles so the back becomes next frame's front. `owner` is held
    /// weakly so the slot is pruned once the sketch releases its `Feedback` (a live
    /// reload, or a layer no longer used) and to catch an address reused by a new
    /// layer.
    final class FeedbackSlot {
        let a: MTLTexture, b: MTLTexture
        let w: Int, h: Int
        /// The pair's pixel format (`LayerPrecision`): a layer remade at another
        /// precision reallocates rather than reading a mismatched pair.
        let format: MTLPixelFormat
        var flipped = false
        /// Frames this slot has been stepped, handed to the step passes as a seed
        /// so a per-pass hash (the falling sand's friction coin) is fresh each
        /// frame rather than fixed to a place. The renderer's own frame index
        /// cycles with the in-flight ring, so it cannot serve.
        var age = 0
        weak var owner: AnyObject?
        init(a: MTLTexture, b: MTLTexture, w: Int, h: Int, format: MTLPixelFormat, owner: AnyObject) {
            self.a = a; self.b = b; self.w = w; self.h = h; self.format = format; self.owner = owner
        }
    }

    /// One `Accumulator`'s persistent state: the running sum in single-precision
    /// float (a value that only ever grows wants every bit half float would drop),
    /// and the mean the sketch reads, rewritten from the sum every frame a pass is
    /// added. Both are written by a compute pass in place (each thread its own
    /// texel), so there is no pair to flip; Metal's hazard tracking orders one
    /// frame's write after the previous frame's read. `owner` is weak so the slot
    /// is pruned once the sketch releases its `Accumulator`.
    final class AccumulatorSlot {
        let sum: MTLTexture, mean: MTLTexture
        let w: Int, h: Int
        weak var owner: AnyObject?
        init(sum: MTLTexture, mean: MTLTexture, w: Int, h: Int, owner: AnyObject) {
            self.sum = sum; self.mean = mean; self.w = w; self.h = h; self.owner = owner
        }
    }
    /// Persistent accumulator storage, kept across frames like `feedbackSlots`
    /// and pruned the same way.
    var accumulatorSlots: [ObjectIdentifier: AccumulatorSlot] = [:]

    /// The accumulate pass: add this frame's pass into the running sum (or replace
    /// it, after a reset) and write the mean beside it. `params.x` is one over the
    /// passes so far, `params.y` is 1 to replace.
    static let accumulateKernel = ComputeKernel(entry: "ollin_accumulate", """
        kernel void ollin_accumulate(texture2d<float, access::read> frame [[texture(0)]],
                                     texture2d<float, access::read_write> sum [[texture(1)]],
                                     texture2d<float, access::write> mean [[texture(2)]],
                                     constant float4 &params [[buffer(0)]],
                                     uint2 gid [[thread_position_in_grid]]) {
            if (gid.x >= sum.get_width() || gid.y >= sum.get_height()) { return; }
            float4 pass = frame.read(gid);
            float4 total = params.y > 0.5 ? pass : sum.read(gid) + pass;
            sum.write(total, gid);
            mean.write(total * params.x, gid);
        }
        """)
    /// Persistent feedback storage, kept across frames (and across the live `pooled`
    /// ring and the headless path alike), distinct from the per-frame pools above,
    /// which is the whole point of feedback. Feedback is inherently serial (frame
    /// N+1 reads frame N's output), so Metal's automatic GPU↔GPU hazard tracking
    /// across command buffers serializes the dependency with no extra semaphore.
    var feedbackSlots: [ObjectIdentifier: FeedbackSlot] = [:]
    /// Feedback layers drawn into this frame, so only those flip after the frame
    /// (a layer skipped this frame keeps its content as the next front).
    var feedbackUsedThisFrame: Set<ObjectIdentifier> = []

    /// The 3D lookup textures a live soft proof samples, one per printing
    /// condition. Baking the lattice costs milliseconds and uploading it costs
    /// half a megabyte, while a sketch proofs against the same condition every
    /// frame, so the texture is kept and keyed by the lattice's own identity
    /// (`ProofLUTCache` hands back the same object for the same condition). The
    /// owner is held beside it, as the feedback slots do, so an identity can
    /// never be read as a match for a different lattice.
    var proofLUTTextures: [ObjectIdentifier: (owner: ProofLUT, texture: MTLTexture)] = [:]

    /// One fluid `SimField`'s persistent state: the velocity and dye ping-pong pairs
    /// that carry across frames. These are the only fields a fluid must keep — pressure,
    /// divergence, and curl are recomputed each frame from pooled scratch. Each frame
    /// reads the current front of each pair and writes the evolved field into the back,
    /// then `flipped` toggles, exactly like `FeedbackSlot` (just two pairs instead of
    /// one). `owner` is weak so the slot is pruned once the sketch releases the field.
    final class FluidSlot {
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
    var fluidSlots: [ObjectIdentifier: FluidSlot] = [:]
    var fluidUsedThisFrame: Set<ObjectIdentifier> = []

    /// One watercolor `SimField`'s persistent state: three ping-pong pairs (flow =
    /// velocity/pressure/wet mask, pig = suspended pigment + paper saturation, dep =
    /// settled pigment), the generated paper height field, the dried-glaze stack
    /// (Kubelka-Munk reflectance and transmittance, rebuilt wholesale by `dry()`:
    /// fresh textures each bake, never rewritten in place while a frame may read
    /// them), and the rendered painting the field's `image` serves. `paperSeed` /
    /// `paperGrain` remember what the paper was generated from, so retuning either
    /// live regenerates the sheet without touching the painting's state.
    final class WatercolorSlot {
        let flowA: MTLTexture, flowB: MTLTexture
        let pigA: MTLTexture, pigB: MTLTexture
        let depA: MTLTexture, depB: MTLTexture
        let paper: MTLTexture
        var driedR: MTLTexture, driedT: MTLTexture
        let display: MTLTexture
        let w: Int, h: Int
        var paperSeed: Float, paperGrain: Float
        var flipped = false
        weak var owner: AnyObject?
        init(flowA: MTLTexture, flowB: MTLTexture, pigA: MTLTexture, pigB: MTLTexture,
             depA: MTLTexture, depB: MTLTexture, paper: MTLTexture,
             driedR: MTLTexture, driedT: MTLTexture, display: MTLTexture,
             w: Int, h: Int, paperSeed: Float, paperGrain: Float, owner: AnyObject) {
            self.flowA = flowA; self.flowB = flowB
            self.pigA = pigA; self.pigB = pigB
            self.depA = depA; self.depB = depB
            self.paper = paper
            self.driedR = driedR; self.driedT = driedT
            self.display = display
            self.w = w; self.h = h
            self.paperSeed = paperSeed; self.paperGrain = paperGrain
            self.owner = owner
        }
    }
    /// Persistent watercolor storage, kept and pruned like `fluidSlots`.
    var watercolorSlots: [ObjectIdentifier: WatercolorSlot] = [:]
    var watercolorUsedThisFrame: Set<ObjectIdentifier> = []

    /// One self-warp `SimField`'s persistent state: the previous frame's clean source
    /// (what this frame's motion is measured against), the motion-field ping-pong pair
    /// (kept across frames so the estimate can be temporally steadied, at a quarter of
    /// the field's resolution: motion is a smooth quantity, and the coarser grid both
    /// regularizes the fit and extends the reach of the window), and the history
    /// ping-pong pair the warp accumulates into. `primed` defers the first-frame fill
    /// (source and history start as the first drawn seed, so the first frame measures
    /// zero motion instead of a jump from black). `owner` is weak so the slot is
    /// pruned once the sketch releases the field.
    final class SelfWarpSlot {
        let source: MTLTexture
        let flowA: MTLTexture, flowB: MTLTexture
        let histA: MTLTexture, histB: MTLTexture
        let w: Int, h: Int
        let flowW: Int, flowH: Int
        var primed = false
        var flipped = false
        weak var owner: AnyObject?
        init(source: MTLTexture, flowA: MTLTexture, flowB: MTLTexture,
             histA: MTLTexture, histB: MTLTexture,
             w: Int, h: Int, flowW: Int, flowH: Int, owner: AnyObject) {
            self.source = source
            self.flowA = flowA; self.flowB = flowB
            self.histA = histA; self.histB = histB
            self.w = w; self.h = h; self.flowW = flowW; self.flowH = flowH
            self.owner = owner
        }
    }
    /// Persistent self-warp storage, kept and pruned like `fluidSlots`.
    var selfWarpSlots: [ObjectIdentifier: SelfWarpSlot] = [:]
    var selfWarpUsedThisFrame: Set<ObjectIdentifier> = []

    /// How many blur-pyramid rungs a multi-scale Turing step is handed. Must stay equal
    /// to `OLLIN_TURING_LEVELS` in `ShaderSim.metal`, which sizes the texture binding:
    /// twelve rungs cover a field up to 4096 texels on its longest side, and a shallower
    /// pyramid repeats its top rung to fill the binding.
    static let turingPyramidLevels = 12

    /// One screen-space-reflections layer's temporal-accumulation history: the ping-pong pair
    /// carrying the reflection across frames (the back is written this frame and becomes the
    /// front next frame), plus the previous frame's scene view·projection used to reproject it,
    /// and a `valid` flag gating the very first frame (no history yet). Keyed by the SSR op's
    /// call site rather than a layer identity: a sketch makes its render target fresh each
    /// frame, so there is no stable owner to key on the way feedback and fluid do.
    final class SSRHistorySlot {
        let a: MTLTexture, b: MTLTexture
        let w: Int, h: Int
        var flipped = false
        var valid = false
        var previousViewProjection = matrix_identity_float4x4
        init(a: MTLTexture, b: MTLTexture, w: Int, h: Int) {
            self.a = a; self.b = b; self.w = w; self.h = h
        }
    }
    /// An SSR op's history identity: the call site that built the `Combine` plus its
    /// occurrence index among same-site ops this frame (one call in a loop records
    /// several). NOT a frame-wide ordinal: a sketch that records an *earlier* SSR
    /// combine only conditionally would shift every later op's ordinal, handing it
    /// another op's history until the clamp reconverged (the cross-wire). A call-site
    /// key holds steady however many other SSR ops come and go; only same-site ops
    /// can still shift among themselves, the structural-identity limit.
    struct SSRSlotKey: Hashable {
        let source: String
        let occurrence: Int
    }
    /// Persistent SSR history, kept across frames like `feedbackSlots`, keyed by the op's
    /// call site. Not pruned per frame (a skipped SSR frame keeps its history; the
    /// reprojection clamp reconverges if it went stale), but bounded in `ssrHistorySlot`
    /// against orphaned keys (a live-reload edit can move a call site's line).
    var ssrHistorySlots: [SSRSlotKey: SSRHistorySlot] = [:]
    /// SSR ops resolved this frame, so only those flip their ping-pong.
    var ssrHistoryUsedThisFrame: Set<SSRSlotKey> = []
    /// Occurrence counters per SSR call site this frame; reset at the start of
    /// `encodeEffectTargets`, so both encodes of a repeated frame (a settled
    /// export frame) resolve identical keys.
    var ssrOccurrenceThisFrame: [String: Int] = [:]

    /// The deferred ray-traced reflection's temporal history (the live on-screen path):
    /// one slot for the main canvas, reusing the SSR slot shape (ping-pong pair +
    /// previous view·projection + first-frame gate). The headless/export path never
    /// touches it (it supersamples within the frame instead), so an export beside
    /// a running window can't double-step the accumulation.
    var rtReflectHistory: SSRHistorySlot?

    /// The temporal anti-aliasing history (the live on-screen path): the same
    /// ping-pong-plus-previous-view·projection slot shape as `rtReflectHistory`, but
    /// over the whole resolved frame. The headless/export path never touches it (it
    /// averages N deterministically jittered renders within the frame instead), so an
    /// export beside a running window can't double-step the accumulation.
    var taaHistory: SSRHistorySlot?
    /// The single-sample depth the main geometry pass resolves (`.min`, the front
    /// surface) when temporal AA is on, read by the resolve's camera reprojection.
    /// Cached by size; a TAA-off frame attaches no resolve and stays byte-identical.
    var mainDepthResolve: MTLTexture?
    /// The baked star pattern and the blade count it was baked for. The opening
    /// only changes when the blades or the f-number do, and the f-number scales the
    /// drawn size rather than the pattern, so one bake serves every frame.
    var flareStarCache: (blades: Int, texture: MTLTexture)?

    /// The paraxial description of the lens the flare is drawn through, kept for the
    /// lens it was worked out from. None of it moves when the light does, so a sketch
    /// that holds one lens pays for the ghost enumeration once rather than per frame.
    var flareOpticsCache: (lens: Lens, optics: LensOptics)?

    /// The mover-velocity pass's texture pair (rg16Float screen motion + its own
    /// depth), cached by size like `scatterMaskCache`. Only allocated the first
    /// frame that runs the pass (live TAA + declared movers), so a frame without
    /// `withMotion` costs nothing.
    var velocityCache: (tex: MTLTexture, depth: MTLTexture, w: Int, h: Int)?
    /// The temporal upscaler's persistent state (the live on-screen path): the
    /// platform scaler object (whose accumulation history lives inside it), the
    /// sizes it was built for, its full-screen motion fill and full-resolution
    /// output textures, and the last presented output for same-frame repeats
    /// (a repeat must not step the scaler's internal history, the `taaHistory`
    /// rule). Rebuilt when the render or output size changes; the headless
    /// path never touches it (it renders full-resolution instead).
    var fxSlot: FXScalerSlot?
    /// Whether this GPU supports the platform temporal scaler, resolved once.
    var fxSupportChecked = false
    var fxSupported = false
    /// The frame interpolator and the textures it works between (see
    /// `frameInterpolation`). Rebuilt on a size change; the headless path never
    /// touches it, since an export writes only the frames the sketch drew.
    var interpolationSlot: FXInterpolatorSlot?
    /// Whether this GPU supports the platform frame interpolator, resolved once.
    var interpolationSupportChecked = false
    var interpolationSupported = false
    /// The drawn frame waiting for the next refresh, set when a made frame went
    /// to the screen in its place. Read by the runner through `hasHeldFrame`.
    var heldFrame: MTLTexture?
    /// Whether an export asked for slow motion out of made frames, which is what
    /// makes the headless render keep the picture and the depth a made frame is
    /// built from. Its own slot rather than the live one: the two drives never
    /// run together, and an export starts with no history to carry.
    var exportMadeFrames = false
    var exportInterpolationSlot: FXInterpolatorSlot?
    /// The depth the last export render resolved and the mesh buffer it drew
    /// from, which the made frame's motion fill reads. Held only between one
    /// render and the made frame built right after it.
    var exportInterpolationDepth: MTLTexture?
    var exportInterpolationMesh: MTLBuffer?
    /// Whether the host can give up a refresh to a made frame. The renderer
    /// cannot see the conditions that decide it (a take being played or
    /// recorded, a still sketch, a wall of displays that all want every frame),
    /// so the runner sets it each frame.
    var hostAllowsInterpolation = false
    /// Seconds between the last two drawn frames, which is what a made frame is
    /// placed in the middle of. Set by the host each frame, like `presentCeiling`.
    var frameDelta: Double = 1.0 / 60
    /// The reflection G-buffer's cached targets (world normal + coverage, metal/rough,
    /// own depth), reallocated on a size change. GPU-private and fully rewritten by the
    /// pass each frame, so reuse across in-flight frames is safe (command buffers on
    /// one queue serialize the writes and reads).
    var rtReflectGBuf: (normal: MTLTexture, material: MTLTexture, depth: MTLTexture, w: Int, h: Int)?

    /// The caustics chain's persistent state (`caustics()`, ray-tracing devices).
    /// The G-buffer adds the baked albedo to the reflection G-buffer's recipe; the
    /// GPU-private buffers hold the adaptive-emission state (light-space density,
    /// feedback accumulators, the quadtree task buffer, leaf ray counts), the
    /// photon records, and the splat pass's indirect-draw arguments. All GPU-written
    /// and frame-serialized on the one queue, so none of them ride the CPU ring.
    var causticsGBuf: (normal: MTLTexture, material: MTLTexture, albedo: MTLTexture,
                       depth: MTLTexture, w: Int, h: Int)?
    var causticsDensity: MTLBuffer?      // float per emission texel (live adaptivity)
    var causticsFeedback: MTLBuffer?     // 4 uints per texel: area, variance, count, spare
    var causticsTotals: MTLBuffer?       // 1 uint: the density map's fixed-point sum
    var causticsQuadtree: MTLBuffer?     // uint4 per node, levels 0..depth-1 breadth-first
    var causticsLeafCounts: MTLBuffer?   // uint per texel (a perfect square)
    var causticsPhotons: MTLBuffer?      // OllinPhoton records (capacity = ray budget)
    var causticsArgs: MTLBuffer?         // MTLDrawPrimitivesIndirectArguments (GPU-reset)
    /// The emission-map edge the buffers were sized for (a quality change reallocates).
    var causticsMapEdge = 0
    var causticsPhotonCapacity = 0
    /// Whether the density map holds a converged distribution from a previous live
    /// frame (false forces the uniform seed, e.g. first frame or after a reset).
    var causticsDensityValid = false
    /// The live temporal history (the `rtReflectHistory` shape): resolved caustics
    /// ping-pong + previous view·projection. The headless path never touches it.
    var causticsHistory: SSRHistorySlot?

    /// Compute pipelines built from the *main* shader library (the caustics kernels),
    /// cached by entry name; distinct from `computePipelines`, whose kernels compile
    /// from their own user source. Cleared on live shader reload with the rest.
    var libComputePipelines: [String: MTLComputePipelineState] = [:]

    /// The global-illumination probe field's persistent state (the `rtReflectHistory`
    /// shape, doubled): ping-ponged irradiance + visibility atlases and the *held* probe
    /// volume. The volume holds until the scene's geometry escapes it or shrinks well
    /// inside it, so probe positions stay put across frames and the hysteresis has a
    /// stable field to converge into; a refit moves every probe, so it invalidates the
    /// history (the next update writes fresh values at full weight).
    /// One camera-anchored probe cascade of the vast-scene ladder (the scene-fitted
    /// volume stays cascade 0 on `GIProbeState` itself). `phase` is the infinite-
    /// scroll wrap: grid coordinate g stores into physical tile (g + phase) mod
    /// counts inside the cascade's own 512-probe atlas slot, so a camera move
    /// re-labels only the scrolled-in planes and the field's interior never
    /// re-converges. Axes whose span already covers the scene's slab are pinned
    /// (centered, `scrolls` 0), so a flat scene's cascades never scroll vertically.
    struct GICascadeState: Equatable {
        var origin: SIMD3<Float>
        var spacing: Float
        var counts: SIMD3<Int32>
        var scrolls: SIMD3<Int32>
        var phase = SIMD3<Int32>.zero
        /// Structural equality (spacing/counts/scroll axes): what decides whether a
        /// freshly derived ladder is the same ladder (origins move by scrolling and
        /// phases wrap, neither is a reason to restart the field).
        func matches(_ other: GICascadeState) -> Bool {
            spacing == other.spacing && counts == other.counts && scrolls == other.scrolls
        }
    }

    final class GIProbeState {
        let irrA: MTLTexture, irrB: MTLTexture
        let depA: MTLTexture, depB: MTLTexture
        /// Per-probe relocation offsets (xyz) + validity (w), one texel per physical
        /// probe, ping-ponged like the atlases: the trace reads the front, the
        /// relocation pass writes the back from this update's surfels, so a probe that
        /// landed inside geometry walks out over the next few updates. The offsets
        /// carry their own flip (`offFlipped`) because the live scroll pass advances
        /// them mid-frame without touching the atlases.
        let offA: MTLTexture, offB: MTLTexture
        /// How many 512-probe atlas slots this allocation holds (1 while no camera
        /// cascades exist, 1 + the ladder size otherwise). A capacity change swaps the
        /// whole state (rare: the coarseness threshold crossing is a refit event), so
        /// the single-volume allocation, and the exact sampling UVs its sizes produce,
        /// stay byte-identical to the pre-cascade path.
        let slotCapacity: Int
        var flipped = false
        var offFlipped = false
        var valid = false
        var origin = SIMD3<Float>.zero
        var spacing = SIMD3<Float>(repeating: 1)
        var counts = SIMD3<Int32>(repeating: 2)
        /// The camera-anchored cascade ladder, coarsest first (empty = the shipped
        /// single-volume path); entry i's probes live at atlas slot i + 1.
        var cascades: [GICascadeState] = []
        /// The eye-to-target distance the ladder derived from: held live until it
        /// drifts past the re-derivation band, so cascade spacings stay put and the
        /// fields converge (the volume-hold rule's ladder twin).
        var ladderScale: Float = 0
        /// The offsets the most recent trace actually used: what the carriers must
        /// sample probe positions with (the freshly relocated front is one step ahead
        /// of the atlas content).
        var lastTraceOffsets: MTLTexture?
        init(irrA: MTLTexture, irrB: MTLTexture, depA: MTLTexture, depB: MTLTexture,
             offA: MTLTexture, offB: MTLTexture, slotCapacity: Int = 1) {
            self.irrA = irrA; self.irrB = irrB; self.depA = depA; self.depB = depB
            self.offA = offA; self.offB = offB
            self.slotCapacity = slotCapacity
        }
        var irrFront: MTLTexture { flipped ? irrB : irrA }
        var irrBack: MTLTexture { flipped ? irrA : irrB }
        var depFront: MTLTexture { flipped ? depB : depA }
        var depBack: MTLTexture { flipped ? depA : depB }
        var offFront: MTLTexture { offFlipped ? offB : offA }
        var offBack: MTLTexture { offFlipped ? offA : offB }
    }
    var giState: GIProbeState?

    /// What a frame's GI pass resolved: the atlases + probe offsets the carriers sample
    /// plus the volume the lighting struct describes them with (packed identically at
    /// every consumer by `packGI`, the `resolveFieldLighting`-mirroring rule).
    /// `cascades` is the camera-anchored ladder (empty = single volume).
    struct GIResolved {
        var irradiance: MTLTexture
        var depth: MTLTexture
        var offsets: MTLTexture
        var origin: SIMD3<Float>
        var spacing: SIMD3<Float>
        var counts: SIMD3<Int32>
        var biasScale: Float
        var cascades: [GICascadeState] = []
    }

    /// The subsurface-scatter mask pass's cached targets (the per-pixel step/depth
    /// mask plus its own depth attachment), reallocated on a size change; rewritten
    /// whole by the pass each frame like the reflection G-buffer above.
    var scatterMaskCache: (mask: MTLTexture, depth: MTLTexture, w: Int, h: Int)?
    /// Diffusion-blur kernels, cached by quantized (falloff, strength) profile: a
    /// kernel is a pure function of the two, so a sketch reusing a material never
    /// rebuilds its taps.
    var scatterKernels: [ScatterProfileKey: [SIMD4<Float>]] = [:]

    /// The (drawer, frame) whose stateful passes (feedback / sim fields / fluid / SSR
    /// temporal) have already advanced, so a same-frame re-encode (a settled export
    /// frame, a benchmark loop) reuses their results instead of stepping them again.
    /// Without this, a frame encoded twice steps the sims twice (feedback runs at 2x
    /// speed) and blends the SSR history twice (the second encode one temporal step
    /// ahead of the first). Keyed by the sketch's frame count (`performDraw` stamps
    /// it once per frame), so headless warmup frames each still advance exactly
    /// once. Note for a future benchmark: re-rendering one frame in a timing loop
    /// skips these passes after the first iteration.
    var lastStatefulEncode: (drawer: ObjectIdentifier, frame: UInt32)?
    /// Whether the encode in progress is such a same-frame repeat (set at the top of
    /// `encodeEffectTargets`, read by the stateful blocks and `applyCombine`).
    var statefulEncodeIsRepeat = false

    /// Baked image-based-lighting maps, cached by environment source so the bake (a few
    /// fullscreen passes) runs once, not per frame. Bounded: entries carry their GPU
    /// footprint and last-use tick, and the least-recently-used are evicted past
    /// `iblCacheBudgetBytes` (an 8K HDRI's maps are ~270 MB, so a sketch cycling
    /// environments, a gallery or a varying URL, would otherwise grow without bound; an
    /// evicted source re-bakes from its disk blob in a blink). `iblBRDFLUT` is
    /// environment-independent (the split-sum scale/bias integral) so it's baked once
    /// globally. `currentIBL` is the set resolved for the frame being encoded, bound to
    /// the mesh fragment.
    var iblCache: [IBLKey: IBLCacheEntry] = [:]
    /// The tiling 3D noise volumes the procedural sky's cloud march samples, baked once
    /// per process by compute the first time a `.sky` environment carries clouds (a pure
    /// function of a fixed lattice, so every process bakes identical fields).
    var cloudNoiseTextures: (base: MTLTexture, detail: MTLTexture)?
    /// Monotonic resolve counter: bumped once per `resolveIBL`, stamped on cache entries
    /// (LRU order) and equirect-pixel requests (staleness pruning).
    var iblResolveTick: UInt64 = 0
    /// Test seam: overrides `iblCacheBudgetBytes` so eviction is observable without
    /// baking gigabytes.
    var iblCacheBudgetOverride: Int?
    /// Per-feed bake state for `.feed` environments: the frame last baked and the
    /// generation its cache key carries (see `bakeFeed`).
    var feedBakeStates: [Int: FeedBakeState] = [:]
    var iblBRDFLUT: MTLTexture?
    /// The sheen directional-albedo LUT, environment-independent like the BRDF LUT but
    /// needed with plain lights too, so it bakes on its own trigger: the first frame
    /// whose batches carry a sheen material (`ensureSheenLUT`). Bound at mesh fragment
    /// texture 12 whenever real (a never-sampled stand-in otherwise; the material's
    /// sheen color gates the read).
    var sheenLUT: MTLTexture?
    var currentIBL: IBLMaps?
    /// A 1×1 cube bound at the IBL texture slots when no environment is set, so the mesh
    /// fragment's declared cube samplers are always bound (never sampled in that case).
    var iblPlaceholderCube: MTLTexture?
    /// The two 64×64 LTC lookup tables for area-light shading (`ensureLTCTables()`), loaded
    /// once from the bundled fit (`Resources/LTC/ltc_tables.bin`). Bound at mesh fragment
    /// textures 8/9 whenever real (with a never-sampled stand-in otherwise); the read is
    /// gated by `OllinLighting.ltcEnabled`, so a frame with no area light never samples them.
    var ltcMatTexture: MTLTexture?
    var ltcAmpTexture: MTLTexture?
    /// A failed table load (a corrupt bundle) logs once and stays failed; area lights then
    /// contribute nothing rather than shading through garbage.
    var ltcLoadFailed = false
    /// The frame's baked IES-profile array (one layer per distinct profile among the
    /// lights, in `Drawer.usedIESProfiles` order), bound at mesh fragment texture 10;
    /// `iesArrayKey` is the content-hash list it was baked from, so an unchanged frame
    /// reuses it and a changed one gets a *fresh* texture (never replaced in place; an
    /// in-flight frame may still read the old one, which its command buffer retains).
    var iesArrayTexture: MTLTexture?
    var iesArrayKey: [Int] = []
    /// The cookie sibling (`Drawer.usedLightCookies` order), bound at texture 11.
    var cookieArrayTexture: MTLTexture?
    var cookieArrayKey: [Int] = []
    /// The decal sibling (`Drawer.usedDecals` order, a placement's `params.x` the
    /// layer), bound at mesh fragment texture 24; same fresh-texture cache rule.
    var decalArrayTexture: MTLTexture?
    var decalArrayKey: [Int] = []
    /// A 1×1×1 `texture2d_array` stand-in for the two light-shaping slots when a frame
    /// carries none (the declared array samplers must always be bound; never sampled
    /// with the gates down). The 2D `strip` stand-in can't serve here: the slot's
    /// declared type is an array, and Metal validation rejects a plain 2D texture.
    var lightShapingStandIn: MTLTexture?
    /// A 1×1 white texture for the base-color slot of a normal-map-only mesh: the
    /// textured fragment multiplies its sample onto the surface color, so white is
    /// the identity and the mesh draws in its plain base color under the bent
    /// normals. Built lazily, kept for the session (the `iblPlaceholderCube` shape).
    var whiteStandInTexture: MTLTexture?

    /// The 1×1 white stand-in, built on first use.
    func whiteStandIn() -> MTLTexture? {
        if let whiteStandInTexture { return whiteStandInTexture }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb, width: 1, height: 1, mipmapped: false)
        desc.usage = .shaderRead
        desc.storageMode = ollinUploadStorageMode
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        var white: [UInt8] = [255, 255, 255, 255]
        tex.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                    withBytes: &white, bytesPerRow: 4)
        whiteStandInTexture = tex
        return tex
    }
    /// Processed equirect pixels ready to bake, keyed by source. A heavy `.url` HDRI decodes
    /// off the render thread (live) and lands here for the next frame to upload + bake; the
    /// bundled placeholder shows meanwhile. Locked because the background decode writes it.
    let equirectReady = OSAllocatedUnfairLock(initialState: [Environment.Source: EquirectBytes]())
    /// Sources whose off-thread decode is in flight, so a repeat request each frame doesn't
    /// start a second decode.
    let equirectLoading = OSAllocatedUnfairLock(initialState: Set<Environment.Source>())
    /// Sources whose decode failed (a corrupt or unreadable file), with the file's
    /// (size, mtime) stamp at failure. The request repeats every frame while unresolved, so
    /// without this memo a broken HDRI would re-attempt the multi-second decode and log
    /// continuously; the same bytes won't decode differently, so the memo holds until the
    /// file on disk changes (replacing a broken HDRI retries without a relaunch).
    let equirectFailed = OSAllocatedUnfairLock(initialState: [Environment.Source: EquirectStamp]())
    /// The resolve tick each source's pixels were last requested (`equirectBytes`), so
    /// decoded-but-never-baked pixels (the environment moved on before its off-thread
    /// decode landed) are freed instead of held for the session. Main-thread only (the
    /// background decode never touches it).
    var equirectLastRequest: [Environment.Source: UInt64] = [:]

    /// What the live loop wants of a frame besides showing it: the finished
    /// picture, brought to the canvas's own size, as a CPU image, a GPU texture,
    /// or both. The grab is encoded into the frame's own command buffer (one
    /// tone-map pass and, for an image, one copy) and delivered once the GPU has
    /// finished the frame, so the frame is drawn once and the render loop never
    /// waits for it.
    struct FrameGrabRequest {
        /// The canvas size, which is the size every delivered frame has.
        let width: Int
        let height: Int
        let wantsImage: Bool
        let wantsTexture: Bool
        /// Runs on the main queue, in frame order, with whichever of the two was
        /// asked for. The texture is the renderer's again once this returns.
        let deliver: @MainActor (CGImage?, MTLTexture?) -> Void
    }

    /// A grab between its encode and its delivery: the texture the present pass
    /// wrote, the buffer the image was copied to, and where to hand them.
    /// `@unchecked Sendable` so the completed handler, which runs off the main
    /// thread, can carry it back to the main queue.
    private final class FrameGrabInFlight: @unchecked Sendable {
        let request: FrameGrabRequest
        let texture: MTLTexture
        let buffer: MTLBuffer?
        /// The present kept the canvas's coverage as alpha (a see-through
        /// background), so the image is tagged premultiplied rather than opaque.
        let transparent: Bool
        init(request: FrameGrabRequest, texture: MTLTexture, buffer: MTLBuffer?, transparent: Bool) {
            self.request = request
            self.texture = texture
            self.buffer = buffer
            self.transparent = transparent
        }
    }

    /// Display textures and read-back buffers a grab is written into, each handed
    /// to exactly one delivery and put back when that delivery has run, so nothing
    /// here is written while a consumer still reads it. Let go of on a frame
    /// nobody asks for.
    private var grabTextures: [MTLTexture] = []
    private var grabBuffers: [MTLBuffer] = []
    /// A mipmapped copy of the finished picture for a grab smaller than it, so the
    /// present pass's sampler minifies through the chain rather than skipping
    /// texels. Kept while the picture keeps its size.
    private var grabMipped: MTLTexture?

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
    /// holds the raw linear pile; the present pass (and a frame grab) tone-maps it
    /// into display bytes, so a consumer never sees the raw HDR float.
    private var accumTarget: MTLTexture?
    private var accumResolve: MTLTexture?
    private var accumSize = (width: 0, height: 0)
    /// The display texture the headless accumulation export tone-maps the pile
    /// into and reads back, made when that path first runs at a size.
    private var accumExportDisplay: MTLTexture?
    private var accumNeedsClear = true

    /// Sampler for the image pipeline: linear filtering, clamp to edge. Built once.
    /// Also samples the gradient strip (the same filtering is exactly what a LUT
    /// row wants), and every screen-space pass in the effect chain.
    let imageSampler: MTLSamplerState?

    /// The same sampler for a picture that lies on a *surface*, where the pixel's
    /// footprint on the picture is a real shape rather than one texel. A floor
    /// running away from the camera covers a long thin strip of its texture in one
    /// screen pixel, and a level picked for the long side of that strip softens it
    /// along the view; sixteen readings taken along that axis hold the sharpness
    /// instead. Bound by the textured-mesh draws alone, whose fragment derives the
    /// footprint from an interpolated uv every lane carries. See `imageSampler`
    /// above for why the chain must not have it.
    let surfaceSampler: MTLSamplerState?

    /// The gradient strip: one row per distinct gradient ramp this frame, baked
    /// on the CPU (see `BakedGradient`) and sampled by the SDF fragment. Reused
    /// while the frame's rows are unchanged (the common case — a steady sketch
    /// uploads nothing); a *new* texture is made when they change, because the
    /// old one may still be read by an in-flight frame (the command buffer
    /// retains it until completion, so swapping the reference is safe where
    /// rewriting the contents is not).
    var gradientStrip: MTLTexture?
    var gradientStripRows: [[UInt8]] = []

    init(device: MTLDevice, pixelFormat: MTLPixelFormat, sampleCount: Int,
         encoding: PresentEncoding = .srgb8) throws {
        self.device = device
        self.pixelFormat = pixelFormat
        self.sampleCount = sampleCount
        self.presentEncoding = encoding
        // An extended frame starts unbounded, so an off-screen render keeps its
        // highlights; a live host pulls this down to the display's real headroom
        // every frame. Every other encoding stops at white.
        self.presentCeiling = encoding == .linearDisplayP3Extended
            ? .greatestFiniteMagnitude : 1

        guard let queue = device.makeCommandQueue() else {
            throw RendererError.commandQueue
        }
        self.commandQueue = queue
        self.rayTracedShadows = MetalRenderer.rayTracingAvailable(on: device)
        self.hasHardwareRayTracing = device.supportsFamily(.apple9)
        self.hasMeshShaders = MetalRenderer.meshShadersAvailable(on: device)

        // The sampler every picture is read through: the image quads, a mesh's
        // maps, and the effect chain's own targets. `mipFilter` is what a texture
        // standing away from the camera needs: one screen pixel covers many
        // texels there, and reading a single one of them makes the surface crawl
        // as the camera moves. A target the chain renders into carries one level,
        // so it reads exactly as it did; only a texture that *has* smaller levels
        // can land on one.
        //
        // `maxAnisotropy` stays at 1 on this one, and the second sampler below is
        // the reason. A chain pass reads its input one texel to one pixel: there is
        // no long thin footprint to resolve, the extra readings would buy nothing,
        // and asking for them makes the sampler work out a *derivative* that
        // several of those passes cannot give it. A filter that returns early for a
        // pixel it does not touch (the scatter blur's mark test, the sandpile's
        // open edge, a disoccluded pixel in the temporal resolve) leaves the four
        // neighbors the derivative is formed across missing some of their number,
        // and what the sampler reads then is undefined. That is what made a plain
        // lit box render *differently on every run* on a scene with no picture in
        // it at all: about 450 bytes at up to 12 of 255 between two renders of one
        // frame, which the reproducibility probes caught at once. Those passes name
        // level 0 instead, and the footprint lives where a footprint means something.
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.mipFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        self.imageSampler = device.makeSamplerState(descriptor: samplerDesc)
        samplerDesc.maxAnisotropy = 16
        self.surfaceSampler = device.makeSamplerState(descriptor: samplerDesc)

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

    /// What size to render the frame at, given the drawable it will be presented
    /// into. The drawable's own size, until the piece is fitted to a wall.
    ///
    /// A fitted piece fills the display, and the picture inside it is placed by
    /// the present pass rather than by the window, so the geometry must not take
    /// its shape from the drawable: a square canvas rendered across a wide screen
    /// and then squared back up would carry oval dots and strokes of two
    /// thicknesses. It renders at the canvas's own proportions instead, as large
    /// as fits the drawable, which is the same count of pixels a window holding
    /// the canvas's shape hands over.
    func pictureSize(_ drawableSize: CGSize, canvas: SIMD2<Float>) -> (Int, Int) {
        let drawable = (Int(drawableSize.width.rounded()), Int(drawableSize.height.rounded()))
        guard projection != nil, canvas.x > 0, canvas.y > 0,
              drawable.0 > 0, drawable.1 > 0 else { return drawable }
        // A piece on a wall is drawn once for every display it goes on, so it is
        // the wall that says how large, not the display that happens to be
        // drawing it. Off a wall the two are the same number.
        let asked = wallDemand ?? drawableSize
        let output = (max(1, Int(asked.width.rounded())), max(1, Int(asked.height.rounded())))
        let aspect = Double(canvas.x) / Double(canvas.y)
        let w = Double(output.0), h = Double(output.1)
        let wide = aspect > w / h
        return (max(1, Int((wide ? w : h * aspect).rounded())),
                max(1, Int((wide ? w / aspect : h).rounded())))
    }

    /// One more display the frame is put on, besides the one being drawn in.
    ///
    /// The canvas is drawn once and presented as many times as there are
    /// displays, each with its own placement, so a wall costs one drawing and
    /// one tone-map per beam.
    struct ExtraDisplay {
        let drawable: any CAMetalDrawable
        /// What this display carries, worked out against its own size. Nil
        /// presents the whole canvas straight, as a desk does.
        let placement: ProjectionPlacement?
    }

    /// Encode and present one frame's worth of recorded geometry: composite into
    /// the linear-float intermediate, then run the present pass to tone-map it into
    /// the drawable.
    ///
    /// - Parameter also: the other displays the same frame goes on. They are
    ///   presented from the same command buffer as the drawing display, so every
    ///   beam of a wall carries the same frame rather than one a step behind.
    /// - Parameter grab: what of this frame is wanted besides showing it (a
    ///   recorder's image, a shared texture), delivered once the GPU is done.
    func render(_ drawer: Drawer, viewport: SIMD2<Float>, in view: MTKView,
                also: [ExtraDisplay] = [], grab: FrameGrabRequest? = nil) {
        if drawer.accumulates {
            renderAccumulating(drawer, viewport: viewport, in: view, also: also, grab: grab)
            return
        }
        var (width, height) = pictureSize(view.drawableSize, canvas: viewport)
        // A frame being handed out is drawn no smaller than the canvas: the take
        // is the canvas, so a window smaller than it shows the frame scaled
        // rather than deciding how sharp the recording is. A larger window keeps
        // its size, and the grab is minified from it.
        if let grab, width < grab.width || height < grab.height {
            (width, height) = (grab.width, grab.height)
        }
        guard width > 0, height > 0, let drawable = view.currentDrawable else { return }

        // The temporal upscaler renders the whole frame at a reduced size and
        // reconstructs the full canvas from the jittered history, so every
        // geometry-side pass below uses the render size; the scaler bridges
        // back to the drawable's full size ahead of the motion blur, the frame
        // filters, and the present. Off, the two sizes are equal and the frame
        // is byte-identical by construction.
        let fxActive = temporalUpscalingActive(drawer)
        let (renderWidth, renderHeight) = fxActive
            ? upscaleInputSize(width: width, height: height,
                               quality: drawer.temporalUpscalingQuality)
            : (width, height)

        // (Re)allocate the cached float geometry targets on a size change. The MSAA
        // target is memoryless (tile-only); the resolve is sampled by the present pass.
        if mainSize != (renderWidth, renderHeight) || mainMSAA == nil || mainResolve == nil {
            guard let msaa = makeFloatMSAA(width: renderWidth, height: renderHeight, storage: .memoryless),
                  let resolve = makeFloatResolve(width: renderWidth, height: renderHeight) else { return }
            mainMSAA = msaa; mainResolve = resolve; mainSize = (renderWidth, renderHeight)
        }
        guard let msaa = mainMSAA, let resolve = mainResolve else { return }

        // Block until a vertex-buffer slot frees up, then advance to the next one
        // in the ring, so this frame's upload can't stomp a buffer the GPU is
        // still reading for an in-flight frame. The wait is timed apart from the
        // encode: it is the display's pace rather than work, and counting it as
        // CPU cost pins the number to 1/fps and says nothing (the lesson the
        // frame-time readout already learned).
        profile.resetCounts()
        profile.batches = drawer.batches.count
        let waitStart = CACurrentMediaTime()
        takeFrameSlot()
        let encodeStart = CACurrentMediaTime()
        profile.waitMS = (encodeStart - waitStart) * 1000
        frameIndex = (frameIndex + 1) % MetalRenderer.maxFramesInFlight

        let geomPass = MTLRenderPassDescriptor()
        geomPass.colorAttachments[0].texture = msaa
        geomPass.colorAttachments[0].resolveTexture = resolve
        geomPass.colorAttachments[0].loadAction = .clear
        geomPass.colorAttachments[0].clearColor = drawer.backgroundColor.mtlClearColor
        geomPass.colorAttachments[0].storeAction = .multisampleResolve

        // A 3D camera *or* a depth scene adds a depth attachment, paired to mainMSAA
        // (allocated lazily; a plain 2D sketch never allocates one). Memoryless,
        // cleared to the far plane. Temporal AA additionally resolves the depth
        // (`.min`, the front surface) for its reprojection, and motion blur, the
        // upscaler, the lens flare, and the frame interpolator read the same
        // resolve; a frame using none of them attaches no resolve and stays
        // byte-identical.
        let taaActive = temporalAAActive(drawer)
        let blurActive = motionBlurActive(drawer)
        let interpolationActive = frameInterpolationActive(drawer)
        var passDepthFormat: MTLPixelFormat? = nil
        if drawer.usesDepthBuffer {
            if mainDepth?.width != renderWidth || mainDepth?.height != renderHeight {
                mainDepth = makeDepthMSAA(width: renderWidth, height: renderHeight)
            }
            if let depth = mainDepth {
                geomPass.depthAttachment.texture = depth
                geomPass.depthAttachment.loadAction = .clear
                geomPass.depthAttachment.clearDepth = 1.0
                geomPass.depthAttachment.storeAction = .dontCare
                passDepthFormat = depthPixelFormat
                if taaActive || blurActive || fxActive || interpolationActive || lensFlareActive(drawer) {
                    if mainDepthResolve?.width != renderWidth || mainDepthResolve?.height != renderHeight {
                        mainDepthResolve = makeDepthResolve(width: renderWidth, height: renderHeight)
                    }
                    if let resolve = mainDepthResolve {
                        geomPass.depthAttachment.resolveTexture = resolve
                        geomPass.depthAttachment.storeAction = .multisampleResolve
                        geomPass.depthAttachment.depthResolveFilter = .min
                    }
                }
            }
        }
        // A clipping frame (`withClip` on the canvas) adds a stencil attachment the
        // same lazy way; an unclipped frame allocates none and stays byte-identical.
        let passHasStencil = attachClipStencil(to: geomPass, active: drawer.usesClipStencil,
                                               width: renderWidth, height: renderHeight)

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            returnFrameSlot()   // nothing encoded; hand the slot back
            return
        }
        encodeCompute(drawer, into: commandBuffer)   // sim steps before the render pass
        encodeMeshFieldCulling(drawer, into: commandBuffer,
                               viewport: SIMD2<Float>(Float(width), Float(height)))
        // Bake the IBL environment maps (once, cached) ahead of the geometry pass, so the
        // mesh fragments can sample them. A no-op when no environment is set.
        _ = resolveIBL(for: drawer.environment, commandBuffer: commandBuffer)
        ensureSheenLUT(for: drawer, commandBuffer: commandBuffer)
        ensureBRDFLUT(for: drawer, commandBuffer: commandBuffer)
        // Shadow depth pass from the casting light, ahead of the geometry pass in the
        // same command buffer (a no-op returning nil when this frame casts no shadow).
        // It shares the mesh vertex buffer the geometry pass uses.
        let meshBuf = meshBuffer(at: frameIndex, for: tracedMeshVertexCount(drawer))
        let renderedShadow = encodeShadowPass(
            drawer, into: commandBuffer, meshBuffer: meshBuf,
            instancedMeshBuffer: drawer.instancedMeshVertices.isEmpty ? nil
                : instancedMeshBuffer(at: frameIndex, for: drawer.instancedMeshVertices.count),
            meshInstanceBuffer: drawer.meshInstances.isEmpty ? nil
                : meshInstanceBuffer(at: frameIndex, for: drawer.meshInstances.count),
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
            sdf3DNode: sdf3DNodeBuffer(at: frameIndex, for: drawer.sdf3DNodes.count),
            instancedMesh: drawer.instancedMeshVertices.isEmpty ? nil
                : instancedMeshBuffer(at: frameIndex, for: drawer.instancedMeshVertices.count),
            meshInstance: drawer.meshInstances.isEmpty ? nil
                : meshInstanceBuffer(at: frameIndex, for: drawer.meshInstances.count))
        beginStatefulEncode(drawer)
        // The frame's temporal sub-pixel jitter (zero when neither temporal AA
        // nor the upscaler is on): the live path cycles the sequence by frame
        // count, and every main-canvas 3D pass below carries the same offset so
        // nothing misaligns. A same-frame repeat reads the same frame count, so
        // it re-renders under the same jitter. The upscaler cycles more phases
        // than TAA's 8 (it reconstructs more output pixels per rendered one)
        // and expresses the offsets on the *render* pixel grid.
        let jitterPhases = fxActive
            ? fxJitterPhaseCount(inputWidth: renderWidth, outputWidth: width)
            : 8
        let jitterIndex = Int(frameComputeUniforms.frameCount % UInt32(jitterPhases))
        let taaJitter: SIMD2<Float> = (taaActive || fxActive)
            ? taaJitterNDC(index: jitterIndex, width: renderWidth, height: renderHeight)
            : .zero
        // Global illumination (live): one probe-field update, hysteresis-accumulated
        // into the persistent atlases. Nil when GI isn't active this frame; the
        // carriers' GI branches then stay untaken (byte-identical). Encoded ahead of
        // the effect layers: the field is world-space and frame-wide, so a target
        // drawing 3D samples the same update the main pass does.
        let gi = encodeGIPass(drawer, into: commandBuffer, meshBuffer: meshBuf,
                              accel: renderedShadow.giAccel,
                              geoOffsets: renderedShadow.giGeoOffsets,
                              supersample: false, pooled: true)
        encodeEffectTargets(drawer, into: commandBuffer, buffers: buffers, pooled: true, gi: gi)

        // Half-res raymarch pre-pass (the `.performance` tier): sphere-trace the fields at half
        // resolution into a sampleable color+depth that the main pass upsamples + composites.
        // `nil` on the full-res tiers or a frame with no fields, so those stay byte-identical.
        // Carries the frame's TAA jitter so a reduced-res field shifts with the meshes.
        let halfResField = makeRaymarchUniforms3D(drawer, viewport: viewport, jitter: taaJitter).flatMap { u3 in
            let fieldLight = resolveFieldLighting(drawer, shadowMap: renderedShadow.twoD,
                                                  shadowCube: renderedShadow.cube,
                                                  shadowAccelPresent: renderedShadow.accel != nil,
                                                  reflectAccelPresent: renderedShadow.reflectAccel != nil,
                                                  gi: gi)
            return encodeRaymarchHalfRes(drawer, into: commandBuffer,
                groupBuffer: buffers.sdf3DGroup, nodeBuffer: buffers.sdf3DNode,
                uniforms3D: u3, lighting: fieldLight.lighting,
                shadowTexture: fieldLight.shadowTexture, shadowCubeTexture: fieldLight.shadowCubeTexture,
                traceAccel: renderedShadow.accel ?? renderedShadow.reflectAccel,
                meshBuffer: buffers.mesh, reflectGeoOffsets: renderedShadow.reflectGeoOffsets,
                giTextures: gi.map { ($0.irradiance, $0.depth, $0.offsets) },
                fullWidth: renderWidth, fullHeight: renderHeight)
        }
        // Half-res field-cast shadow pre-pass (the live RenderQuality path): the point/RT field
        // cast onto meshes is per-pixel-marched, so compute it once at reduced resolution and let
        // the mesh pass sample it. `nil` at the full-res tier / no point-RT caster (inline → byte-identical).
        let halfResFieldShadow = makeRaymarchUniforms3D(drawer, viewport: viewport, jitter: taaJitter).flatMap { u3 -> MTLTexture? in
            var fl = resolveFieldLighting(drawer, shadowMap: renderedShadow.twoD, shadowCube: renderedShadow.cube,
                                          shadowAccelPresent: renderedShadow.accel != nil).lighting
            fl.fieldCasterCount = resolveFieldCasterCount(fl, drawer)
            return encodeFieldShadowHalfRes(drawer, into: commandBuffer, meshBuffer: buffers.mesh,
                groupBuffer: buffers.sdf3DGroup, nodeBuffer: buffers.sdf3DNode,
                uniforms3D: u3, lighting: fl, fullWidth: renderWidth, fullHeight: renderHeight)
        }
        // Deferred ray-traced reflections (live): trace one jittered ray per pixel and
        // temporally accumulate it, so the reflection edges (a pillar's mirror image on a
        // polished floor) converge to anti-aliased instead of staying 1px-hard. Nil when
        // reflections aren't active this frame; the mesh fragments then keep the inline path.
        // At `.performance` the layer renders at half the drawable and the fragments read
        // it scaled, which is where a reflective scene buys back most of its frame time.
        let reflectionScale = resolveReflectionScale(drawer.reflectionQualitySetting)
        let reflectionWidth = max(1, Int((Double(renderWidth) * reflectionScale).rounded()))
        let reflectionHeight = max(1, Int((Double(renderHeight) * reflectionScale).rounded()))
        let deferredReflection = encodeReflectionPass(
            drawer, into: commandBuffer, meshBuffer: meshBuf,
            reflectAccel: renderedShadow.reflectAccel,
            reflectGeoOffsets: renderedShadow.reflectGeoOffsets,
            width: reflectionWidth, height: reflectionHeight, supersample: false, pooled: true,
            gi: gi, taaJitter: taaJitter)
            .map { (texture: $0.traced, guide: $0.guide, scale: Float(reflectionScale)) }
        // Caustics (live): trace this frame's photons through the specular casters,
        // splat them, and temporally resolve the layer the mesh fragments add by
        // screen position. Nil when caustics aren't active this frame; the carriers'
        // branch then stays untaken (byte-identical).
        let caustics = encodeCausticsPass(
            drawer, into: commandBuffer, meshBuffer: meshBuf,
            causticAccel: renderedShadow.causticAccel,
            causticGeoOffsets: renderedShadow.causticGeoOffsets,
            causticGeoMats: renderedShadow.causticGeoMats,
            width: renderWidth, height: renderHeight, supersample: false, pooled: true,
            taaJitter: taaJitter)
        // Contact shadows: march the scene's own depth toward the caster once per
        // frame; the mesh fragments sample the verdict by screen position. nil when
        // inactive (their gate then zeroes, byte-identical). Carries the frame's
        // jitter so the mask stays aligned under temporal AA (the scatter-mask rule).
        let contactShadow = encodeContactShadowPass(
            drawer, into: commandBuffer, meshBuffer: buffers.mesh,
            width: renderWidth, height: renderHeight, taaJitter: taaJitter)
        // The scene behind the glass: the frame drawn once more with every transmissive
        // run left out, for a transmissive surface to read along its refracted direction.
        // nil when the sketch didn't ask, when nothing transmits, or when the reflection
        // trace already covers the same view (its gate then zeroes, byte-identical).
        let sceneBehind = encodeSceneBehindPass(
            drawer, into: commandBuffer, viewport: viewport, buffers: buffers,
            width: renderWidth, height: renderHeight,
            shadowMap: renderedShadow.twoD, shadowCube: renderedShadow.cube,
            shadowAccel: renderedShadow.accel,
            reflectAccel: renderedShadow.reflectAccel,
            reflectGeoOffsets: renderedShadow.reflectGeoOffsets,
            halfResField: halfResField, halfResFieldShadow: halfResFieldShadow,
            contactShadow: contactShadow, gi: gi, caustics: caustics)

        guard let geomEncoder = countedEncoder(commandBuffer, geomPass, caller: "canvas") else {
            returnFrameSlot()   // nothing encoded; hand the slot back
            return
        }
        // Runs off the main actor when the GPU finishes, so it touches only the
        // semaphore and the lock. The GPU's own timestamps are the honest half
        // of the frame split: everything else here is measured on the CPU.
        commandBuffer.addCompletedHandler { [frameBoundary, framesInFlight, gpuFrameMS] buffer in
            // Read the timestamps out first: the command buffer is not `Sendable`,
            // so it must not be captured by the lock's own closure.
            let ms = (buffer.gpuEndTime - buffer.gpuStartTime) * 1000
            gpuFrameMS.withLock { $0 = ms }
            framesInFlight.withLock { $0 -= 1 }
            frameBoundary.signal()
        }

        encode(drawer, viewport: viewport, attachment: SIMD2<Float>(Float(width), Float(height)), into: geomEncoder,
               triangleBuffer: buffers.triangle, sdfBuffer: buffers.sdf,
               imageBuffer: buffers.image, glyphBuffer: buffers.glyph,
               pointBuffer: buffers.point, meshBuffer: buffers.mesh,
               instancedMeshBuffer: buffers.instancedMesh,
               meshInstanceBuffer: buffers.meshInstance,
                   sdfGroupBuffer: buffers.sdfGroup, sdfNodeBuffer: buffers.sdfNode,
                   sdf3DGroupBuffer: buffers.sdf3DGroup, sdf3DNodeBuffer: buffers.sdf3DNode,
               depthFormat: passDepthFormat, stencil: passHasStencil,
               shadowMap: renderedShadow.twoD,
               shadowCube: renderedShadow.cube,
               shadowAccel: renderedShadow.accel,
               reflectAccel: renderedShadow.reflectAccel,
               reflectGeoOffsets: renderedShadow.reflectGeoOffsets,
               halfResField: halfResField,
               halfResFieldShadow: halfResFieldShadow,
               deferredReflection: deferredReflection,
               contactShadow: contactShadow,
               gi: gi,
               caustics: caustics,
               sceneBehind: sceneBehind,
               taaJitter: taaJitter)
        geomEncoder.endEncoding()

        // The subsurface-scattering diffusion (returns `resolve` untouched when no
        // material asked for it), then the temporal-AA accumulation resolve (which
        // returns its input untouched when TAA is off), then the whole-frame
        // postProcess filters, run over the resolved frame before present. TAA sits
        // ahead of the filters so a bloom or grade reads the stabilized frame, not
        // the jittered one.
        let scattered = applySubsurfaceScattering(drawer, resolved: resolve, meshBuffer: meshBuf,
                                                  into: commandBuffer, width: renderWidth, height: renderHeight,
                                                  pooled: true, taaJitter: taaJitter)
        // The temporal upscaler replaces TAA's own resolve when it runs (the
        // scaler *is* the jittered accumulation, and it bridges the render size
        // back to the drawable's full size); otherwise the plain TAA chain.
        let stabilized: MTLTexture
        var blurMover: MTLTexture?
        var blurMoverScale = SIMD2<Float>(1, 1)
        if fxActive, let fx = applyTemporalUpscaling(drawer, resolved: scattered,
                                                     depth: mainDepthResolve,
                                                     meshBuffer: meshBuf, into: commandBuffer,
                                                     inputWidth: renderWidth, inputHeight: renderHeight,
                                                     outputWidth: width, outputHeight: height,
                                                     jitterIndex: jitterIndex) {
            stabilized = fx.output
            blurMover = fx.mover
            blurMoverScale = SIMD2(Float(width) / Float(renderWidth),
                                   Float(height) / Float(renderHeight))
        } else {
            // The mover-velocity pass (nil without TAA + declared movers + history),
            // encoded before the resolve updates the slot's previous view·projection
            // so both reproject through the same matrices.
            let velocity = encodeVelocityPass(drawer, into: commandBuffer, meshBuffer: meshBuf,
                                              width: renderWidth, height: renderHeight)
            stabilized = applyTemporalAA(drawer, resolved: scattered,
                                         depth: taaActive ? mainDepthResolve : nil,
                                         velocity: velocity,
                                         jitter: taaJitter, into: commandBuffer,
                                         width: renderWidth, height: renderHeight)
            blurMover = velocity
        }
        // Motion blur streaks the stabilized frame (after the temporal resolve,
        // so the blur reads settled edges; before the filters, so a bloom or
        // grade reads the streaks). Returns its input untouched when off. Under
        // the upscaler it runs at the full output size, reading the
        // render-resolution depth and mover velocity by normalized coordinates
        // (the mover's pixel values rescaled by `moverScale`).
        let blurred = applyMotionBlur(drawer, resolved: stabilized,
                                      depth: blurActive ? mainDepthResolve : nil,
                                      moverVelocity: blurMover, meshBuffer: meshBuf,
                                      into: commandBuffer, width: width, height: height,
                                      pooled: true, moverScale: blurMoverScale)
        // The lens flare, after the blur (a flare is the camera's own light, so
        // the scene's motion never streaks it) and before the filters (so a bloom
        // reads the ghosts as light, which is what they are).
        let flared = applyLensFlare(drawer, resolved: blurred, depth: mainDepthResolve,
                                    into: commandBuffer, width: width, height: height,
                                    pooled: true)
        let presented = applyFrameFilters(drawer, resolved: flared, width: width, height: height,
                                          into: commandBuffer, pooled: true)
        // Frame interpolation keeps this frame back one refresh and shows the
        // frame that belongs between it and the one before. Returns nil (and
        // holds nothing) whenever it is not running, and then the drawable
        // carries the frame just drawn, byte-identically.
        let toPresent = applyFrameInterpolation(drawer, drawn: presented, depth: mainDepthResolve,
                                                upscalerMotion: fxActive ? fxSlot?.motion : nil,
                                                meshBuffer: meshBuf, into: commandBuffer,
                                                inputWidth: renderWidth, inputHeight: renderHeight,
                                                outputWidth: width, outputHeight: height) ?? presented
        if let presentEncoder = countedEncoder(commandBuffer, presentPass(into: drawable.texture), caller: "present") {
            encodePresent(from: toPresent, drawer: drawer, into: presentEncoder, projected: true)
            presentEncoder.endEncoding()
        }
        commandBuffer.present(drawable)
        encodeExtraDisplays(also, from: presented, drawer: drawer, into: commandBuffer)
        // The frame grab reads the drawn frame (not a made in-between one), the
        // same picture the other displays of a wall carry.
        if let grab {
            encodeFrameGrab(grab, from: presented, drawer: drawer, into: commandBuffer)
        } else {
            releaseFrameGrabStorage()
        }
        commandBuffer.commit()
        // The encode ends at the commit (the GPU runs on its own clock after it).
        // The GPU time is the last frame the device finished, one or two frames
        // back, which the reader's smoothing hides.
        profile.cpuEncodeMS = (CACurrentMediaTime() - encodeStart) * 1000
        profile.gpuMS = gpuFrameMS.withLock { $0 }
    }

    // MARK: Accumulation surface (noClear)

    /// Live accumulation path: render this frame's geometry onto the persistent
    /// accumulation surface — loading the prior pile unless this frame resets — then
    /// blit the resolved canvas to the drawable to present it. Reuses the
    /// triple-buffer vertex ring and its semaphore exactly like `render`, so the
    /// upload still can't stomp a buffer an in-flight frame is reading.
    private func renderAccumulating(_ drawer: Drawer, viewport: SIMD2<Float>, in view: MTKView,
                                    also: [ExtraDisplay] = [], grab: FrameGrabRequest? = nil) {
        let (width, height) = pictureSize(view.drawableSize, canvas: viewport)
        guard width > 0, height > 0, let drawable = view.currentDrawable else { return }

        profile.resetCounts()
        profile.batches = drawer.batches.count
        let waitStart = CACurrentMediaTime()
        takeFrameSlot()
        let encodeStart = CACurrentMediaTime()
        profile.waitMS = (encodeStart - waitStart) * 1000
        frameIndex = (frameIndex + 1) % MetalRenderer.maxFramesInFlight

        guard let pass = accumulationPass(drawer, width: width, height: height),
              let resolve = accumResolve,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            returnFrameSlot()      // nothing encoded; hand the slot back
            return
        }
        // Clipping works while accumulating too: the stencil is per-frame (cleared
        // each pass) even though the color pile persists.
        let passHasStencil = attachClipStencil(to: pass, active: drawer.usesClipStencil,
                                               width: width, height: height)
        encodeCompute(drawer, into: commandBuffer)   // sim steps before the render pass
        guard let encoder = countedEncoder(commandBuffer, pass, caller: "canvas (accumulating)") else {
            returnFrameSlot()      // nothing encoded; hand the slot back
            return
        }
        commandBuffer.addCompletedHandler { [frameBoundary, framesInFlight, gpuFrameMS] buffer in
            let ms = (buffer.gpuEndTime - buffer.gpuStartTime) * 1000
            gpuFrameMS.withLock { $0 = ms }
            framesInFlight.withLock { $0 -= 1 }
            frameBoundary.signal()
        }

        encode(drawer, viewport: viewport, attachment: SIMD2<Float>(Float(width), Float(height)), into: encoder,
               triangleBuffer: vertexBuffer(at: frameIndex, for: drawer.vertices.count),
               sdfBuffer: sdfBuffer(at: frameIndex, for: drawer.sdfInstances.count),
               imageBuffer: imageBuffer(at: frameIndex, for: drawer.imageVertices.count),
               glyphBuffer: glyphBuffer(at: frameIndex, for: drawer.glyphVertices.count),
               pointBuffer: pointBuffer(at: frameIndex, for: drawer.points.count),
               meshBuffer: meshBuffer(at: frameIndex, for: tracedMeshVertexCount(drawer)),
               sdfGroupBuffer: sdfGroupBuffer(at: frameIndex, for: drawer.sdfGroups.count),
               sdfNodeBuffer: sdfNodeBuffer(at: frameIndex, for: drawer.sdfNodes.count),
               sdf3DGroupBuffer: sdf3DGroupBuffer(at: frameIndex, for: drawer.sdf3DGroups.count),
               sdf3DNodeBuffer: sdf3DNodeBuffer(at: frameIndex, for: drawer.sdf3DNodes.count),
               depthFormat: nil,   // 3D + accumulation isn't supported in M1
               stencil: passHasStencil)
        encoder.endEncoding()

        // Present: tone-map the resolved float pile into the drawable. (The pile
        // itself stays in linear float, so faint samples keep summing next frame.)
        if let presentEncoder = countedEncoder(commandBuffer, presentPass(into: drawable.texture), caller: "present") {
            encodePresent(from: resolve, drawer: drawer, into: presentEncoder, projected: true)
            presentEncoder.endEncoding()
        }
        commandBuffer.present(drawable)
        encodeExtraDisplays(also, from: resolve, drawer: drawer, into: commandBuffer)
        // The pile keeps its size while a grab is armed (resizing it would wipe
        // the drawing), so a grab of an accumulating sketch is the pile brought
        // to the canvas size, sharper or softer as the window is.
        if let grab {
            encodeFrameGrab(grab, from: resolve, drawer: drawer, into: commandBuffer)
        } else {
            releaseFrameGrabStorage()
        }
        commandBuffer.commit()
        profile.cpuEncodeMS = (CACurrentMediaTime() - encodeStart) * 1000
        profile.gpuMS = gpuFrameMS.withLock { $0 }
    }

    /// Tone-map the frame into every other display it goes on, each through its
    /// own placement.
    ///
    /// The placement travels with the display rather than being read off the
    /// renderer, which holds the drawing display's own: reading the stored one
    /// would put the same part of the canvas on every beam of the wall.
    private func encodeExtraDisplays(_ displays: [ExtraDisplay], from source: MTLTexture,
                                     drawer: Drawer, into commandBuffer: MTLCommandBuffer) {
        for display in displays {
            if let encoder = countedEncoder(commandBuffer,
                                            presentPass(into: display.drawable.texture),
                                            caller: "present") {
                encodePresent(from: source, drawer: drawer, into: encoder,
                              projected: display.placement != nil, placement: display.placement)
                encoder.endEncoding()
            }
            commandBuffer.present(display.drawable)
        }
    }

    /// Headless accumulation: render this frame's geometry onto the persistent
    /// accumulation surface (load/clear per the drawer) and read the resolved
    /// canvas back as a `CGImage`. The off-screen companion to
    /// `renderAccumulating`, used by the export drivers (still / sequence / video /
    /// GIF) — call it once per frame in order and the pile builds across the run.
    /// Synchronous: waits for the GPU before reading back.
    func accumulatedImage(of drawer: Drawer, viewport: SIMD2<Float>, width: Int, height: Int) -> CGImage? {
        guard let frame = accumulatedFrame(of: drawer, viewport: viewport, width: width, height: height)
        else { return nil }
        return displayImage(from: frame.buffer, width: width, height: height,
                            transparent: drawer.hasTransparentBackground)
    }

    /// `accumulatedImage(of:…)` stopping one step earlier, at the read-back
    /// buffer. The HDR video writer takes this instead of the image: its frames
    /// are PQ code values, which no `CGImage` color space names, so the bytes
    /// themselves are the only honest form.
    func accumulatedFrame(of drawer: Drawer, viewport: SIMD2<Float>,
                          width: Int, height: Int) -> (buffer: MTLBuffer, bytesPerRow: Int)? {
        if renderScale > 1, !reportedAccumulationScale {
            reportedAccumulationScale = true
            print("Ollin: a piling canvas (noClear) keeps one surface across frames, "
                  + "so it renders at 1x and the render scale does not reach it.")
        }
        if accumExportDisplay?.width != width || accumExportDisplay?.height != height {
            accumExportDisplay = makeDisplayTexture(width: width, height: height)
        }
        guard width > 0, height > 0,
              let pass = accumulationPass(drawer, width: width, height: height),
              let resolve = accumResolve, let display = accumExportDisplay,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return nil }
        let passHasStencil = attachClipStencil(to: pass, active: drawer.usesClipStencil,
                                               width: width, height: height)
        encodeCompute(drawer, into: commandBuffer)   // sim steps before the render pass
        guard let encoder = countedEncoder(commandBuffer, pass, caller: "canvas (accumulating, headless)") else { return nil }

        encode(drawer, viewport: viewport, attachment: SIMD2<Float>(Float(width), Float(height)), into: encoder,
               triangleBuffer: exportVertexBuffer(for: drawer.vertices.count),
               sdfBuffer: exportSDFBuffer(for: drawer.sdfInstances.count),
               imageBuffer: exportImageBuffer(for: drawer.imageVertices.count),
               glyphBuffer: exportGlyphBuffer(for: drawer.glyphVertices.count),
               pointBuffer: exportPointBuffer(for: drawer.points.count),
               meshBuffer: exportMeshBuffer(for: tracedMeshVertexCount(drawer)),
               sdfGroupBuffer: exportSDFGroupBuffer(for: drawer.sdfGroups.count),
               sdfNodeBuffer: exportSDFNodeBuffer(for: drawer.sdfNodes.count),
               sdf3DGroupBuffer: exportSDF3DGroupBuffer(for: drawer.sdf3DGroups.count),
               sdf3DNodeBuffer: exportSDF3DNodeBuffer(for: drawer.sdf3DNodes.count),
               depthFormat: nil,   // 3D + accumulation isn't supported in M1
               stencil: passHasStencil)
        encoder.endEncoding()

        // The linear pile itself is what a linear-light export wants (a piling
        // canvas draws no 3D, so it carries no depth).
        let linearCapture = capturesLinearFrame
            ? beginLinearCapture(resolve, depth: nil, into: commandBuffer,
                                 width: width, height: height)
            : nil
        // Tone-map the float pile into the sRGB display texture, then read that back.
        if let presentEncoder = countedEncoder(commandBuffer, presentPass(into: display)) {
            encodePresent(from: resolve, drawer: drawer, into: presentEncoder,
                          keepsAlpha: drawer.hasTransparentBackground)
            presentEncoder.endEncoding()
        }

        let bytesPerRow = width * displayBytesPerPixel, byteCount = bytesPerRow * height
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
        if let linearCapture {
            lastLinearFrame = finishLinearCapture(linearCapture, drawer: drawer,
                                                  width: width, height: height)
        }
        return (readbackBuffer, bytesPerRow)
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
                  let resolve = makeFloatResolve(width: width, height: height) else { return nil }
            accumTarget = msaa
            accumResolve = resolve
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

    /// How many bytes one pixel of the display texture takes: four for the 8-bit
    /// sRGB drawable, eight for the float one a wide-gamut or HDR sketch
    /// presents into.
    var displayBytesPerPixel: Int { pixelFormat == .rgba16Float ? 8 : 4 }

    /// The read-back display bytes as a `CGImage`, in whatever form the present
    /// pass left them. The 8-bit path is untouched; a float display texture
    /// comes back as half-float components tagged extended-linear Display P3,
    /// so the wide gamut (and, in an `extended` frame, the values above 1)
    /// survive into the image. `transparent` says the present kept the frame's
    /// coverage as alpha (a see-through canvas, `Drawer.hasTransparentBackground`),
    /// so the bytes are tagged premultiplied and a PNG or a ProRes 4444 clip
    /// carries the transparency; an opaque frame keeps the tag it always had.
    func displayImage(from buffer: MTLBuffer, width: Int, height: Int,
                      transparent: Bool = false) -> CGImage? {
        pixelFormat == .rgba16Float
            ? MetalRenderer.cgImage(fromRGBA16Float: buffer, width: width, height: height,
                                    transparent: transparent)
            : MetalRenderer.cgImage(fromBGRA8: buffer, width: width, height: height,
                                    transparent: transparent)
    }

    /// Build a BGRA8 `CGImage` from a shared buffer of `width*height*4` bytes
    /// (the resolved-texture read-back layout), opaque unless `transparent`
    /// says the alpha byte is real coverage over premultiplied color. Shared by
    /// `image(of:)` and the accumulation read-back paths.
    private static func cgImage(fromBGRA8 buffer: MTLBuffer, width: Int, height: Int,
                                transparent: Bool) -> CGImage? {
        let bytesPerRow = width * 4, byteCount = bytesPerRow * height
        let data = Data(bytes: buffer.contents(), count: byteCount)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        let alpha: CGImageAlphaInfo = transparent ? .premultipliedFirst : .noneSkipFirst
        let bitmapInfo = CGBitmapInfo(rawValue: alpha.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: bitmapInfo, provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Build an opaque half-float `CGImage` from a shared buffer of
    /// `width*height*8` bytes, tagged **extended-linear Display P3**: the space
    /// the wide-gamut present pass writes. Extended-linear is what carries a
    /// component above 1.0, so an `extended` frame's highlights are still in
    /// here; writing it to a PNG or HEIC is where they meet the file format's
    /// own ceiling.
    private static func cgImage(fromRGBA16Float buffer: MTLBuffer, width: Int, height: Int,
                                transparent: Bool) -> CGImage? {
        let bytesPerRow = width * 8, byteCount = bytesPerRow * height
        let data = Data(bytes: buffer.contents(), count: byteCount)
        guard let provider = CGDataProvider(data: data as CFData),
              let space = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3) else { return nil }
        let alpha: CGImageAlphaInfo = transparent ? .premultipliedLast : .noneSkipLast
        let bitmapInfo = CGBitmapInfo(rawValue: CGBitmapInfo.floatComponents.rawValue
                                      | CGBitmapInfo.byteOrder16Little.rawValue
                                      | alpha.rawValue)
        return CGImage(width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 64,
                       bytesPerRow: bytesPerRow, space: space,
                       bitmapInfo: bitmapInfo, provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Render `drawer`'s geometry off-screen to a `CGImage` of `width`×`height`
    /// pixels — same pipeline, MSAA, and blending as on-screen — for frame export
    /// (PNG, and later PNG sequences for video). Headless: needs no view or
    /// window. Synchronous: waits for the GPU before reading back.
    func image(of drawer: Drawer, viewport: SIMD2<Float>, width: Int, height: Int) -> CGImage? {
        guard let frame = renderedFrame(of: drawer, viewport: viewport, width: width, height: height)
        else { return nil }
        return displayImage(from: frame.buffer, width: width, height: height,
                            transparent: drawer.hasTransparentBackground)
    }

    /// `image(of:…)` stopping at the read-back buffer instead of building an
    /// image (see `accumulatedFrame` for why the HDR video writer needs this).
    func renderedFrame(of drawer: Drawer, viewport: SIMD2<Float>,
                       width outWidth: Int, height outHeight: Int) -> (buffer: MTLBuffer, bytesPerRow: Int)? {
        guard outWidth > 0, outHeight > 0 else { return nil }
        // The export supersample (`--render-scale`): the geometry is drawn `scale`
        // times across the canvas and averaged back down before the picture-side
        // chain (motion blur, the flare, the frame filters, the tone map), which
        // stays at canvas size and therefore reads exactly as it does at 1x. The
        // viewport is still in canvas units, so this is a sampling rate rather
        // than a size: the sketch draws in the same canvas either way.
        let scale = supersampleScale(width: outWidth, height: outHeight)
        let width = outWidth * scale, height = outHeight * scale

        // Headless renders count too, so a test (and a batch export) can read the
        // same profile the live window reports. This path waits for the GPU, so
        // the timing it leaves behind belongs to the live loop, not to it.
        profile.resetCounts()
        profile.batches = drawer.batches.count

        // Float MSAA target + float resolve for the geometry, plus an sRGB display
        // texture the present pass tone-maps into and we read back.
        guard let msaaTexture = makeFloatMSAA(width: width, height: height, storage: .memoryless),
              let resolveTexture = makeFloatResolve(width: width, height: height),
              let displayTexture = makeDisplayTexture(width: outWidth, height: outHeight) else { return nil }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = msaaTexture
        pass.colorAttachments[0].resolveTexture = resolveTexture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = drawer.backgroundColor.mtlClearColor
        pass.colorAttachments[0].storeAction = .multisampleResolve

        // A 3D camera or a depth scene adds a (freshly allocated, memoryless) depth
        // attachment so the headless/snapshot path z-tests exactly like the live window.
        // Motion blur and the lens flare additionally resolve the depth (`.min`, the
        // front surface, the live path's rule) for the velocity fill and for reading
        // how much of a source the camera can see; a frame using neither attaches no
        // resolve and stays byte-identical.
        var passDepthFormat: MTLPixelFormat? = nil
        var sceneDepthResolve: MTLTexture? = nil
        if drawer.usesDepthBuffer, let depth = makeDepthMSAA(width: width, height: height) {
            pass.depthAttachment.texture = depth
            pass.depthAttachment.loadAction = .clear
            pass.depthAttachment.clearDepth = 1.0
            pass.depthAttachment.storeAction = .dontCare
            passDepthFormat = depthPixelFormat
            // Slow motion out of made frames reads the same resolved depth the
            // blur and the flare do, so it joins them rather than adding a pass.
            if motionBlurActive(drawer) || lensFlareActive(drawer) || exportMadeFrames
                || capturesLinearFrame,
               let resolve = makeDepthResolve(width: width, height: height) {
                pass.depthAttachment.resolveTexture = resolve
                pass.depthAttachment.storeAction = .multisampleResolve
                pass.depthAttachment.depthResolveFilter = .min
                sceneDepthResolve = resolve
            }
        }
        // A clipping frame adds a stencil attachment, so exports clip like the window.
        let passHasStencil = attachClipStencil(to: pass, active: drawer.usesClipStencil,
                                               width: width, height: height)

        let bytesPerRow = outWidth * displayBytesPerPixel
        let byteCount = bytesPerRow * outHeight

        guard let readback = device.makeBuffer(length: byteCount, options: .storageModeShared),
              let commandBuffer = commandQueue.makeCommandBuffer() else { return nil }
        // Path-traced export (`--path-traced`, headless only): trace the whole mesh
        // scene first, in its own completed command buffers, so the composite in the
        // geometry pass reads finished textures and the frame's own shadow pass can
        // safely re-fill the accel/offsets rings the trace used. nil = pure raster.
        let pathTraced = encodePathTracePass(drawer, width: width, height: height)
        encodeCompute(drawer, into: commandBuffer)   // sim steps before the render pass
        encodeMeshFieldCulling(drawer, into: commandBuffer,
                               viewport: SIMD2<Float>(Float(width), Float(height)))
        // Export blocks on a remote-environment download so the exported frame is full-res.
        _ = resolveIBL(for: drawer.environment, commandBuffer: commandBuffer, blocking: true)
        ensureSheenLUT(for: drawer, commandBuffer: commandBuffer)
        ensureBRDFLUT(for: drawer, commandBuffer: commandBuffer)
        // Shadow depth pass (nil when this frame casts no shadow), sharing the export
        // mesh buffer; so the headless/snapshot path shadows exactly like the window.
        let meshBuf = exportMeshBuffer(for: tracedMeshVertexCount(drawer))
        let renderedShadow = encodeShadowPass(
            drawer, into: commandBuffer, meshBuffer: meshBuf,
            instancedMeshBuffer: drawer.instancedMeshVertices.isEmpty ? nil
                : exportInstancedMeshBuffer(for: drawer.instancedMeshVertices.count),
            meshInstanceBuffer: drawer.meshInstances.isEmpty ? nil
                : exportMeshInstanceBuffer(for: drawer.meshInstances.count),
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
            sdf3DNode: exportSDF3DNodeBuffer(for: drawer.sdf3DNodes.count),
            instancedMesh: drawer.instancedMeshVertices.isEmpty ? nil
                : exportInstancedMeshBuffer(for: drawer.instancedMeshVertices.count),
            meshInstance: drawer.meshInstances.isEmpty ? nil
                : exportMeshInstanceBuffer(for: drawer.meshInstances.count))
        beginStatefulEncode(drawer)
        // Global illumination, historyless: the volume fits this frame's own bounds and
        // K whole trace+blend iterations converge the field within the frame (seed = the
        // iteration index), so the result is a pure function of the frame: byte-stable
        // snapshots, flicker-free video, and an export beside a running window can't
        // double-step the live accumulation. Ahead of the effect layers, so a target
        // drawing 3D samples the converged field.
        let gi = encodeGIPass(drawer, into: commandBuffer, meshBuffer: meshBuf,
                              accel: renderedShadow.giAccel,
                              geoOffsets: renderedShadow.giGeoOffsets,
                              supersample: true, pooled: false)
        encodeEffectTargets(drawer, into: commandBuffer, buffers: buffers, pooled: false, gi: gi)

        // Half-res raymarch pre-pass: honors the resolution tier on export too, so an
        // explicit `.performance`/`.default` raymarch quality downscales here as it does live.
        // At `.detail` (the export default) the scale is 1 and this is nil (full resolution).
        let halfResField = makeRaymarchUniforms3D(drawer, viewport: viewport).flatMap { u3 in
            let fieldLight = resolveFieldLighting(drawer, shadowMap: renderedShadow.twoD,
                                                  shadowCube: renderedShadow.cube,
                                                  shadowAccelPresent: renderedShadow.accel != nil,
                                                  reflectAccelPresent: renderedShadow.reflectAccel != nil,
                                                  gi: gi)
            return encodeRaymarchHalfRes(drawer, into: commandBuffer,
                groupBuffer: buffers.sdf3DGroup, nodeBuffer: buffers.sdf3DNode,
                uniforms3D: u3, lighting: fieldLight.lighting,
                shadowTexture: fieldLight.shadowTexture, shadowCubeTexture: fieldLight.shadowCubeTexture,
                traceAccel: renderedShadow.accel ?? renderedShadow.reflectAccel,
                meshBuffer: buffers.mesh, reflectGeoOffsets: renderedShadow.reflectGeoOffsets,
                giTextures: gi.map { ($0.irradiance, $0.depth, $0.offsets) },
                fullWidth: width, fullHeight: height)
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
        // Deferred ray-traced reflections, historyless: N deterministic jittered rays
        // averaged within this one frame, so a single export is anti-aliased with no
        // warmup, a video export can't flicker, and an export beside a running window
        // never double-steps the on-screen accumulation.
        // Encoded once, outside any TAA sample loop (it is already supersampled
        // internally; the composite reads it at most half a pixel off, which the
        // average absorbs).
        // The same tier the live path reads. An export resolves `.default` to `.detail`, so
        // an exported frame and a snapshot render the layer full size and are never
        // downscaled; only a frame that explicitly asked for `.performance` is halved.
        let reflectionScale = resolveReflectionScale(drawer.reflectionQualitySetting)
        let reflectionWidth = max(1, Int((Double(width) * reflectionScale).rounded()))
        let reflectionHeight = max(1, Int((Double(height) * reflectionScale).rounded()))
        let deferredReflection = encodeReflectionPass(
            drawer, into: commandBuffer, meshBuffer: meshBuf,
            reflectAccel: renderedShadow.reflectAccel,
            reflectGeoOffsets: renderedShadow.reflectGeoOffsets,
            width: reflectionWidth, height: reflectionHeight, supersample: true, pooled: false,
            gi: gi)
            .map { (texture: $0.traced, guide: $0.guide, scale: Float(reflectionScale)) }
        // Caustics, historyless: uniform emission at the export budget, no history
        // slot touched, so a single export is a pure function of the frame and an
        // export beside a running window never steps the on-screen adaptation.
        let caustics = encodeCausticsPass(
            drawer, into: commandBuffer, meshBuffer: meshBuf,
            causticAccel: renderedShadow.causticAccel,
            causticGeoOffsets: renderedShadow.causticGeoOffsets,
            causticGeoMats: renderedShadow.causticGeoMats,
            width: width, height: height, supersample: true, pooled: false)
        // Contact shadows, encoded once outside any TAA sample loop (the deferred-
        // reflection rule: the mask is screen-space and unjittered; a jittered
        // composite reads it at most half a pixel off, which the average absorbs).
        let contactShadow = encodeContactShadowPass(
            drawer, into: commandBuffer, meshBuffer: buffers.mesh,
            width: width, height: height)
        // The scene behind the glass, encoded once outside any TAA sample loop for the
        // same reason the contact mask is: it is screen-space and unjittered, and a
        // jittered composite reads it at most half a pixel off.
        let sceneBehind = encodeSceneBehindPass(
            drawer, into: commandBuffer, viewport: viewport, buffers: buffers,
            width: width, height: height,
            shadowMap: renderedShadow.twoD, shadowCube: renderedShadow.cube,
            shadowAccel: renderedShadow.accel,
            reflectAccel: renderedShadow.reflectAccel,
            reflectGeoOffsets: renderedShadow.reflectGeoOffsets,
            halfResField: halfResField, halfResFieldShadow: halfResFieldShadow,
            contactShadow: contactShadow, gi: gi, caustics: caustics,
            pathTraced: pathTraced)

        // Temporal AA, historyless: render the geometry N times under the fixed
        // jitter sequence and average within this one frame, the deterministic
        // within-frame equivalent of the live accumulation (the deferred-reflection
        // precedent), so a single export is anti-aliased with no warmup, a video
        // can't flicker, and two renders of one frame are byte-identical. The
        // pre-passes above (shadows, GI, effect layers, sims) run once: they are
        // viewpoint-fixed or world-space, and only the camera's rasterization
        // jitters. TAA off (or no camera) takes the single-sample path unchanged.
        // A sketch that asked for temporal *upscaling* supersamples here too: an
        // export never upscales (it renders full-resolution), and the supersample
        // is the deterministic full-quality equivalent of the live scaler.
        let taaSamples = headlessTemporalAAActive(drawer) ? resolveTAASamples() : 1
        let presented: MTLTexture
        if taaSamples > 1,
           var accFront = makeFloatResolve(width: width, height: height),
           var accBack = makeFloatResolve(width: width, height: height) {
            clearFloatTexture(accFront, color: MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0),
                              into: commandBuffer)
            for s in 0..<taaSamples {
                let jitter = taaJitterNDC(index: s, width: width, height: height)
                guard let encoder = countedEncoder(commandBuffer, pass, caller: "canvas (headless)") else { return nil }
                encode(drawer, viewport: viewport, attachment: SIMD2<Float>(Float(width), Float(height)), into: encoder,
                       triangleBuffer: buffers.triangle, sdfBuffer: buffers.sdf,
                       imageBuffer: buffers.image, glyphBuffer: buffers.glyph,
                       pointBuffer: buffers.point, meshBuffer: buffers.mesh,
               instancedMeshBuffer: buffers.instancedMesh,
               meshInstanceBuffer: buffers.meshInstance,
                       sdfGroupBuffer: buffers.sdfGroup, sdfNodeBuffer: buffers.sdfNode,
                       sdf3DGroupBuffer: buffers.sdf3DGroup, sdf3DNodeBuffer: buffers.sdf3DNode,
                       depthFormat: passDepthFormat, stencil: passHasStencil,
                       shadowMap: renderedShadow.twoD,
                       shadowCube: renderedShadow.cube,
                       shadowAccel: renderedShadow.accel,
                       reflectAccel: renderedShadow.reflectAccel,
                       reflectGeoOffsets: renderedShadow.reflectGeoOffsets,
                       halfResField: halfResField,
                       halfResFieldShadow: halfResFieldShadow,
                       deferredReflection: deferredReflection,
                       contactShadow: contactShadow,
                       gi: gi,
                       caustics: caustics,
                       pathTraced: pathTraced,
                       sceneBehind: sceneBehind,
                       taaJitter: jitter)
                encoder.endEncoding()
                let scattered = applySubsurfaceScattering(drawer, resolved: resolveTexture,
                                                          meshBuffer: meshBuf, into: commandBuffer,
                                                          width: width, height: height,
                                                          pooled: false, taaJitter: jitter)
                // acc += sample / N (ping-ponged; a linear-light mean, unbiased).
                encodeEffectFragment("ollin_fx_weighted_sum", inputs: [accFront, scattered],
                                     output: accBack,
                                     params: [SIMD4(1 / Float(taaSamples), 0, 0, 0)],
                                     into: commandBuffer)
                swap(&accFront, &accBack)
            }
            // Down to the canvas first (nothing at all at scale 1), so everything
            // below measures in canvas pixels exactly as it does at 1x.
            let sampled = encodeSupersampleResolve(accFront, scale: scale,
                                                   width: outWidth, height: outHeight,
                                                   into: commandBuffer)
            // Motion blur streaks the supersampled average (the live path's
            // after-TAA slot); the depth resolve holds the last jittered pass's
            // depth, at most half a pixel off, which the average's own tolerance
            // already accepts. Untouched when the blur is off.
            let blurred = applyMotionBlur(drawer, resolved: sampled, depth: sceneDepthResolve,
                                          moverVelocity: nil, meshBuffer: meshBuf,
                                          into: commandBuffer, width: outWidth, height: outHeight,
                                          pooled: false)
            // The flare goes on the averaged frame, not into each jittered pass,
            // so it is added once and reads the same as it does live.
            let flared = applyLensFlare(drawer, resolved: blurred, depth: sceneDepthResolve,
                                        into: commandBuffer, width: outWidth, height: outHeight,
                                        pooled: false)
            presented = applyFrameFilters(drawer, resolved: flared, width: outWidth, height: outHeight,
                                          into: commandBuffer, pooled: false)
        } else {
            guard let encoder = countedEncoder(commandBuffer, pass, caller: "canvas (headless supersample)") else { return nil }
            encode(drawer, viewport: viewport, attachment: SIMD2<Float>(Float(width), Float(height)), into: encoder,
                   triangleBuffer: buffers.triangle, sdfBuffer: buffers.sdf,
                   imageBuffer: buffers.image, glyphBuffer: buffers.glyph,
                   pointBuffer: buffers.point, meshBuffer: buffers.mesh,
               instancedMeshBuffer: buffers.instancedMesh,
               meshInstanceBuffer: buffers.meshInstance,
                       sdfGroupBuffer: buffers.sdfGroup, sdfNodeBuffer: buffers.sdfNode,
                       sdf3DGroupBuffer: buffers.sdf3DGroup, sdf3DNodeBuffer: buffers.sdf3DNode,
                   depthFormat: passDepthFormat, stencil: passHasStencil,
                   shadowMap: renderedShadow.twoD,
                   shadowCube: renderedShadow.cube,
                   shadowAccel: renderedShadow.accel,
                   reflectAccel: renderedShadow.reflectAccel,
                   reflectGeoOffsets: renderedShadow.reflectGeoOffsets,
                   halfResField: halfResField,
                   halfResFieldShadow: halfResFieldShadow,
                   deferredReflection: deferredReflection,
                   contactShadow: contactShadow,
                   gi: gi,
                   caustics: caustics,
                   pathTraced: pathTraced,
                   sceneBehind: sceneBehind)
            encoder.endEncoding()

            // Tone-map the resolved float frame (after the subsurface-scattering
            // diffusion, the motion blur, and the whole-frame postProcess filters)
            // into the sRGB display texture.
            let scattered = applySubsurfaceScattering(drawer, resolved: resolveTexture, meshBuffer: meshBuf,
                                                      into: commandBuffer, width: width, height: height,
                                                      pooled: false)
            // Down to the canvas first (nothing at all at scale 1), so everything
            // below measures in canvas pixels exactly as it does at 1x.
            let sampled = encodeSupersampleResolve(scattered, scale: scale,
                                                   width: outWidth, height: outHeight,
                                                   into: commandBuffer)
            let blurred = applyMotionBlur(drawer, resolved: sampled, depth: sceneDepthResolve,
                                          moverVelocity: nil, meshBuffer: meshBuf,
                                          into: commandBuffer, width: outWidth, height: outHeight,
                                          pooled: false)
            let flared = applyLensFlare(drawer, resolved: blurred, depth: sceneDepthResolve,
                                        into: commandBuffer, width: outWidth, height: outHeight,
                                        pooled: false)
            presented = applyFrameFilters(drawer, resolved: flared, width: outWidth, height: outHeight,
                                          into: commandBuffer, pooled: false)
        }
        // A slow-motion export that fills its gaps with made frames keeps this
        // frame's picture and depth, so the frame between this one and the next
        // can be built from the pair. Does nothing for every other export.
        keepForMadeFrame(drawer, presented: presented, depth: sceneDepthResolve,
                         meshBuffer: meshBuf, into: commandBuffer,
                         inputWidth: width, inputHeight: height,
                         outputWidth: outWidth, outputHeight: outHeight)
        // A linear-light export keeps what the present pass is about to read: the
        // frame one step before the tone map, the dither, and the 8-bit
        // quantization. Nothing is copied unless an export asked.
        let linearCapture = capturesLinearFrame
            ? beginLinearCapture(presented, depth: sceneDepthResolve, into: commandBuffer,
                                 width: outWidth, height: outHeight)
            : nil
        guard let presentEncoder = countedEncoder(commandBuffer, presentPass(into: displayTexture)) else { return nil }
        encodePresent(from: presented, drawer: drawer, into: presentEncoder,
                      keepsAlpha: drawer.hasTransparentBackground)
        presentEncoder.endEncoding()

        // Copy the display texture into a CPU-readable buffer (works on every
        // Mac GPU, unlike texture.getBytes on discrete cards).
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: displayTexture, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: outWidth, height: outHeight, depth: 1),
                  to: readback, destinationOffset: 0,
                  destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: byteCount)
        blit.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let linearCapture {
            lastLinearFrame = finishLinearCapture(linearCapture, drawer: drawer,
                                                  width: outWidth, height: outHeight)
        }
        return (readback, bytesPerRow)
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
        let meshBuf = exportMeshBuffer(for: tracedMeshVertexCount(drawer))
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
            sdf3DNode: exportSDF3DNodeBuffer(for: drawer.sdf3DNodes.count),
            instancedMesh: drawer.instancedMeshVertices.isEmpty ? nil
                : exportInstancedMeshBuffer(for: drawer.instancedMeshVertices.count),
            meshInstance: drawer.meshInstances.isEmpty ? nil
                : exportMeshInstanceBuffer(for: drawer.meshInstances.count))
        var totalMs = 0.0, counted = 0
        for i in 0..<iterations {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = msaaTexture
            pass.colorAttachments[0].resolveTexture = resolveTexture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = drawer.backgroundColor.mtlClearColor
            pass.colorAttachments[0].storeAction = .multisampleResolve
            var passDepthFormat: MTLPixelFormat? = nil
            let taaActive = temporalAAActive(drawer)
            let blurActive = motionBlurActive(drawer)
            if let depthTexture {
                pass.depthAttachment.texture = depthTexture
                pass.depthAttachment.loadAction = .clear
                pass.depthAttachment.clearDepth = 1.0
                pass.depthAttachment.storeAction = .dontCare
                passDepthFormat = depthPixelFormat
                // Temporal AA and motion blur (the live one-update shape): resolve the
                // depth for reprojection, so the benchmark carries the live frame's cost.
                if taaActive || blurActive {
                    if mainDepthResolve?.width != width || mainDepthResolve?.height != height {
                        mainDepthResolve = makeDepthResolve(width: width, height: height)
                    }
                    if let resolve = mainDepthResolve {
                        pass.depthAttachment.resolveTexture = resolve
                        pass.depthAttachment.storeAction = .multisampleResolve
                        pass.depthAttachment.depthResolveFilter = .min
                    }
                }
            }
            let passHasStencil = attachClipStencil(to: pass, active: drawer.usesClipStencil,
                                                   width: width, height: height)
            guard let cb = commandQueue.makeCommandBuffer() else { continue }
            encodeCompute(drawer, into: cb)
            encodeMeshFieldCulling(drawer, into: cb,
                                   viewport: SIMD2<Float>(Float(width), Float(height)))
            _ = resolveIBL(for: drawer.environment, commandBuffer: cb)   // bake IBL once
            ensureSheenLUT(for: drawer, commandBuffer: cb)
            ensureBRDFLUT(for: drawer, commandBuffer: cb)
            let renderedShadow = encodeShadowPass(
                drawer, into: cb, meshBuffer: meshBuf,
                instancedMeshBuffer: buffers.instancedMesh,
                meshInstanceBuffer: buffers.meshInstance,
                sdf3DGroupBuffer: buffers.sdf3DGroup, sdf3DNodeBuffer: buffers.sdf3DNode)
            // Every iteration re-encodes the same sketch frame, which the stateful passes
            // read as a repeat and skip (the frame-grab rule, so a second encode of one
            // frame never steps a history twice). Clearing the stamp makes each iteration
            // a fresh frame to them, which is what puts the reflection trace, the photons,
            // and the probe update inside the number: the passes a heavy scene spends most
            // of its frame on.
            lastStatefulEncode = nil
            beginStatefulEncode(drawer)
            let taaJitter: SIMD2<Float> = taaActive
                ? taaJitterNDC(index: Int(frameComputeUniforms.frameCount % 8),
                               width: width, height: height)
                : .zero
            // Global illumination (the live one-update path), so the benchmark measures
            // the same cost a live frame pays. nil when GI isn't active.
            let gi = encodeGIPass(drawer, into: cb, meshBuffer: meshBuf,
                                  accel: renderedShadow.giAccel,
                                  geoOffsets: renderedShadow.giGeoOffsets,
                                  supersample: false, pooled: false)
            encodeEffectTargets(drawer, into: cb, buffers: buffers, pooled: false, gi: gi)
            // Half-res raymarch pre-pass (the `.performance` tier), so the benchmark measures
            // the same cost the live path pays. nil otherwise.
            let halfResField = makeRaymarchUniforms3D(drawer, viewport: viewport).flatMap { u3 in
                let fieldLight = resolveFieldLighting(drawer, shadowMap: renderedShadow.twoD,
                                                      shadowCube: renderedShadow.cube,
                                                      shadowAccelPresent: renderedShadow.accel != nil,
                                                      reflectAccelPresent: renderedShadow.reflectAccel != nil,
                                                      gi: gi)
                return encodeRaymarchHalfRes(drawer, into: cb,
                    groupBuffer: buffers.sdf3DGroup, nodeBuffer: buffers.sdf3DNode,
                    uniforms3D: u3, lighting: fieldLight.lighting,
                    shadowTexture: fieldLight.shadowTexture, shadowCubeTexture: fieldLight.shadowCubeTexture,
                    traceAccel: renderedShadow.accel ?? renderedShadow.reflectAccel,
                    meshBuffer: buffers.mesh, reflectGeoOffsets: renderedShadow.reflectGeoOffsets,
                    giTextures: gi.map { ($0.irradiance, $0.depth, $0.offsets) },
                    fullWidth: width, fullHeight: height)
            }
            let halfResFieldShadow = makeRaymarchUniforms3D(drawer, viewport: viewport).flatMap { u3 -> MTLTexture? in
                var fl = resolveFieldLighting(drawer, shadowMap: renderedShadow.twoD, shadowCube: renderedShadow.cube,
                                              shadowAccelPresent: renderedShadow.accel != nil).lighting
                fl.fieldCasterCount = resolveFieldCasterCount(fl, drawer)
                return encodeFieldShadowHalfRes(drawer, into: cb, meshBuffer: buffers.mesh,
                    groupBuffer: buffers.sdf3DGroup, nodeBuffer: buffers.sdf3DNode,
                    uniforms3D: u3, lighting: fl, fullWidth: width, fullHeight: height)
            }
            // Contact shadows, so the benchmark pays what a live frame pays.
            let contactShadow = encodeContactShadowPass(
                drawer, into: cb, meshBuffer: buffers.mesh,
                width: width, height: height, taaJitter: taaJitter)
            // The deferred reflection layer, the same one the live drive traces. It has to
            // be here, or the fragments fall back to the inline trace and a reflective
            // scene is timed as a different frame from the one it renders.
            let reflectionScale = resolveReflectionScale(drawer.reflectionQualitySetting)
            let deferredReflection = encodeReflectionPass(
                drawer, into: cb, meshBuffer: meshBuf,
                reflectAccel: renderedShadow.reflectAccel,
                reflectGeoOffsets: renderedShadow.reflectGeoOffsets,
                width: max(1, Int((Double(width) * reflectionScale).rounded())),
                height: max(1, Int((Double(height) * reflectionScale).rounded())),
                supersample: false, pooled: false, gi: gi, taaJitter: taaJitter)
                .map { (texture: $0.traced, guide: $0.guide, scale: Float(reflectionScale)) }
            guard let encoder = countedEncoder(cb, pass) else { continue }
            encode(drawer, viewport: viewport, attachment: SIMD2<Float>(Float(width), Float(height)), into: encoder,
                   triangleBuffer: buffers.triangle, sdfBuffer: buffers.sdf,
                   imageBuffer: buffers.image, glyphBuffer: buffers.glyph,
                   pointBuffer: buffers.point, meshBuffer: buffers.mesh,
               instancedMeshBuffer: buffers.instancedMesh,
               meshInstanceBuffer: buffers.meshInstance,
                   sdfGroupBuffer: buffers.sdfGroup, sdfNodeBuffer: buffers.sdfNode,
                   sdf3DGroupBuffer: buffers.sdf3DGroup, sdf3DNodeBuffer: buffers.sdf3DNode,
                   depthFormat: passDepthFormat, stencil: passHasStencil,
                   shadowMap: renderedShadow.twoD,
                   shadowCube: renderedShadow.cube, shadowAccel: renderedShadow.accel,
                   reflectAccel: renderedShadow.reflectAccel,
                   reflectGeoOffsets: renderedShadow.reflectGeoOffsets,
                   halfResField: halfResField,
                   halfResFieldShadow: halfResFieldShadow,
                   deferredReflection: deferredReflection,
                   contactShadow: contactShadow,
                   gi: gi,
                   taaJitter: taaJitter)
            encoder.endEncoding()
            let scattered = applySubsurfaceScattering(drawer, resolved: resolveTexture, meshBuffer: meshBuf,
                                                      into: cb, width: width, height: height, pooled: false,
                                                      taaJitter: taaJitter)
            // The mover-velocity pass, so the benchmark pays what a live frame pays.
            let velocity = encodeVelocityPass(drawer, into: cb, meshBuffer: meshBuf,
                                              width: width, height: height)
            let stabilized = applyTemporalAA(drawer, resolved: scattered,
                                             depth: taaActive ? mainDepthResolve : nil,
                                             velocity: velocity,
                                             jitter: taaJitter, into: cb,
                                             width: width, height: height)
            let blurred = applyMotionBlur(drawer, resolved: stabilized,
                                          depth: blurActive ? mainDepthResolve : nil,
                                          moverVelocity: velocity, meshBuffer: meshBuf,
                                          into: cb, width: width, height: height,
                                          pooled: false)
            let presented = applyFrameFilters(drawer, resolved: blurred, width: width,
                                              height: height, into: cb, pooled: false)
            if let presentEncoder = countedEncoder(cb, presentPass(into: displayTexture)) {
                encodePresent(from: presented, drawer: drawer, into: presentEncoder)
                presentEncoder.endEncoding()
            }
            cb.commit()
            cb.waitUntilCompleted()
            if i > 0 { totalMs += (cb.gpuEndTime - cb.gpuStartTime) * 1000; counted += 1 }
        }
        return counted > 0 ? totalMs / Double(counted) : 0
    }

    // MARK: The frame grab (the live frame hooks)

    /// Encode a frame grab into the frame's own command buffer: tone-map `source`
    /// (the finished linear-float picture) into a display texture of the canvas's
    /// size, copy it to a shared buffer when an image is wanted, and arrange the
    /// delivery for when the GPU is done. A source larger than the canvas is
    /// minified through a mip chain, so the present pass's sampler averages every
    /// texel it covers; one the same size presents straight, byte for byte the
    /// tone-map the drawable gets.
    private func encodeFrameGrab(_ grab: FrameGrabRequest, from source: MTLTexture,
                                 drawer: Drawer, into commandBuffer: MTLCommandBuffer) {
        guard let texture = takeGrabTexture(width: grab.width, height: grab.height) else { return }

        var presentSource = source
        if source.pixelFormat == linearFormat,
           source.width > grab.width || source.height > grab.height {
            if grabMipped?.width != source.width || grabMipped?.height != source.height {
                grabMipped = makeFloatResolveMipped(width: source.width, height: source.height)
            }
            if let mipped = grabMipped, let blit = commandBuffer.makeBlitCommandEncoder() {
                blit.copy(from: source, sourceSlice: 0, sourceLevel: 0,
                          sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                          sourceSize: MTLSize(width: source.width, height: source.height, depth: 1),
                          to: mipped, destinationSlice: 0, destinationLevel: 0,
                          destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
                blit.generateMipmaps(for: mipped)
                blit.endEncoding()
                presentSource = mipped
            }
        }

        guard let presentEncoder = countedEncoder(commandBuffer, presentPass(into: texture),
                                                  caller: "frame grab") else {
            grabTextures.append(texture)
            return
        }
        encodePresent(from: presentSource, drawer: drawer, into: presentEncoder,
                      keepsAlpha: drawer.hasTransparentBackground)
        presentEncoder.endEncoding()

        // The image's bytes, copied out on the GPU (works on every Mac GPU,
        // unlike `getBytes` on a discrete card) and read on the main queue once
        // the frame is done.
        var buffer: MTLBuffer?
        if grab.wantsImage {
            let bytesPerRow = grab.width * displayBytesPerPixel
            let byteCount = bytesPerRow * grab.height
            if let readback = takeGrabBuffer(length: byteCount),
               let blit = commandBuffer.makeBlitCommandEncoder() {
                blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0,
                          sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                          sourceSize: MTLSize(width: grab.width, height: grab.height, depth: 1),
                          to: readback, destinationOffset: 0,
                          destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: byteCount)
                blit.endEncoding()
                buffer = readback
            }
        }

        // Command buffers complete in the order they were committed and the run
        // loop runs its blocks in the order they were given, so the deliveries
        // land in frame order. They ride the run loop rather than the main queue:
        // a main-queue block cannot run while another one is spinning the run
        // loop (a modal loop, a test's wait), and a run-loop block can. Every
        // common mode, so a frame lands during a drag too, and a wake-up so it
        // lands as soon as the GPU is done rather than at the next event.
        let inFlight = FrameGrabInFlight(request: grab, texture: texture, buffer: buffer,
                                         transparent: drawer.hasTransparentBackground)
        commandBuffer.addCompletedHandler { [weak self] _ in
            RunLoop.main.perform(inModes: [.common]) {
                MainActor.assumeIsolated { self?.finishFrameGrab(inFlight) }
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
    }

    /// The delivery half of a grab, on the main queue once the GPU has finished
    /// the frame: build the image from the copied bytes, hand over what was
    /// asked, and put the texture and buffer back for a later frame.
    private func finishFrameGrab(_ grab: FrameGrabInFlight) {
        let request = grab.request
        let image = request.wantsImage
            ? grab.buffer.flatMap {
                displayImage(from: $0, width: request.width, height: request.height,
                             transparent: grab.transparent)
            }
            : nil
        request.deliver(image, request.wantsTexture ? grab.texture : nil)
        if grabTextures.count <= MetalRenderer.maxFramesInFlight { grabTextures.append(grab.texture) }
        if let buffer = grab.buffer, grabBuffers.count <= MetalRenderer.maxFramesInFlight {
            grabBuffers.append(buffer)
        }
    }

    /// A display texture of the grab's size: one put back by an earlier delivery,
    /// or a fresh one. One of another size is dropped rather than kept.
    private func takeGrabTexture(width: Int, height: Int) -> MTLTexture? {
        while let texture = grabTextures.popLast() {
            if texture.width == width, texture.height == height { return texture }
        }
        return makeDisplayTexture(width: width, height: height)
    }

    /// A shared buffer of the grab's byte count, the same way.
    private func takeGrabBuffer(length: Int) -> MTLBuffer? {
        while let buffer = grabBuffers.popLast() {
            if buffer.length == length { return buffer }
        }
        return device.makeBuffer(length: length, options: .storageModeShared)
    }

    /// Let go of the grab's storage on a frame nobody asked for. A delivery still
    /// in flight puts its own back afterwards, and the next such frame lets go of
    /// that too.
    private func releaseFrameGrabStorage() {
        guard !grabTextures.isEmpty || !grabBuffers.isEmpty || grabMipped != nil else { return }
        grabTextures.removeAll()
        grabBuffers.removeAll()
        grabMipped = nil
    }

    // MARK: Quality-tier override parameters (stored here; the resolve
    // functions live in MetalRenderer+Targets.swift)

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

    /// An exact ambient-occlusion sample count overriding the resolved `.ambientOcclusion`
    /// quality tier, the sweep hook mirroring `dofTapsOverride`. `nil` in normal use.
    var ssaoSamplesOverride: Int?

    /// An exact fraction of the drawable for the deferred reflection layer, overriding the
    /// tier `resolveReflectionScale` resolves: the sweep hook mirroring `ssrScaleOverride`.
    /// `nil` in normal use.
    var reflectionScaleOverride: Double?

    /// An exact SSR march-step count overriding the resolved `.screenSpaceReflections`
    /// quality tier, the sweep hook mirroring `ssaoSamplesOverride`. `nil` in normal use.
    var ssrStepsOverride: Int?

    /// A scale fraction overriding the resolved SSR tier, the sweep hook for the half-res win
    /// (`Scripts/benchmark.sh ssr`). `nil` in normal use.
    var ssrScaleOverride: Double?

    /// An exact camera-march step count overriding the resolved `drawSDF3D` quality tier: the
    /// hook `Scripts/benchmark.sh raymarch` sweeps to measure the real per-GPU march cost.
    /// `nil` in normal use. (The shadow budget tracks it at the same 3/8 ratio.)
    var raymarchStepsOverride: Int?
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
