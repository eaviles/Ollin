import CoreGraphics
import Ollin
import Testing

/// Render-correctness snapshot tests: each renders a small, deterministic sketch
/// off-screen and checks it against a committed reference image. They exercise
/// both render pipelines (the instanced SDF path and the tessellated-triangle
/// path) and the front-to-back batch ordering between them.
///
/// Serialized because they share the GPU and the reference directory; gated on a
/// Metal device so they skip on a GPU-less machine instead of failing.
@Suite(.serialized)
@MainActor
struct SnapshotTests {

    @Test(.enabled(if: Snapshot.hasMetal), arguments: snapshotMetalCases)
    func snapshotMatchesReference(_ snapshot: SnapshotCase) throws {
        let diff = try Snapshot.meanDifference(of: snapshot.make(),
                                               against: snapshot.name, frame: snapshot.frame)
        #expect(diff < Snapshot.tolerance,
                "\(snapshot.name): \(snapshot.note) (mean per-channel difference \(diff))")
    }

    // Ray-tracing-gated cases live in their own parameterized test so the extra
    // `Snapshot.hasRaytracing` gate applies only to them (on a non-RT GPU a point caster
    // falls back to the cube path, which the references aren't recorded against).
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing), arguments: snapshotRaytracingCases)
    func raytracingSnapshotMatchesReference(_ snapshot: SnapshotCase) throws {
        let diff = try Snapshot.meanDifference(of: snapshot.make(),
                                               against: snapshot.name, frame: snapshot.frame)
        #expect(diff < Snapshot.tolerance,
                "\(snapshot.name): \(snapshot.note) (mean per-channel difference \(diff))")
    }
}

/// One render-correctness snapshot: a deterministic sketch, the committed reference image
/// it diffs against (`name`), the capture `frame` (0 unless the scene must accumulate
/// state first), and `note`, the documentation of what the snapshot pins. Identifies by
/// `name`, so each row surfaces as its own named sub-test.
struct SnapshotCase: Sendable, CustomTestStringConvertible {
    let name: String
    let frame: Int
    let note: String
    let make: @MainActor @Sendable () -> Sketch

    init(_ name: String, frame: Int = 0, note: String,
         make: @escaping @MainActor @Sendable () -> Sketch) {
        self.name = name
        self.frame = frame
        self.note = note
        self.make = make
    }

    var testDescription: String { name }
}

/// The plain-Metal snapshot table. Each row is one scene + reference name + capture frame,
/// with `note` carrying what that snapshot pins.
private let snapshotMetalCases: [SnapshotCase] = [
    SnapshotCase("solid-shapes", note: "Solid SDF + tessellated shapes.",
                 make: { SolidShapes() }),
    SnapshotCase("mixed-pipelines",
                 note: "The instanced SDF path and the tessellated-triangle path composited front-to-back.",
                 make: { MixedPipelines() }),
    SnapshotCase("user-shader", note: "A user-supplied generator shader.",
                 make: { UserShaderGenerator() }),
    SnapshotCase("eased-dots", frame: 30,
                 note: "Rendered mid-tween (frame 30), so the per-frame auto-advance has run and the three curves have pulled the dots to different positions.",
                 make: { EasedDots() }),
    SnapshotCase("stroke-aligned", note: "strokeAlign center / inside / outside.",
                 make: { StrokeAligned() }),
    SnapshotCase("three-point-shapes",
                 note: "The three-point triangle and quadratic Bezier SDF shapes.",
                 make: { ThreePointShapes() }),
    SnapshotCase("oriented-boxes", note: "The oriented box SDF.",
                 make: { OrientedBoxes() }),
    SnapshotCase("oriented-vesicas", note: "The oriented vesica SDF.",
                 make: { OrientedVesicas() }),
    SnapshotCase("sdf-combinators", note: "The 2D SDF combinator field.",
                 make: { SDFCombinatorsScene() }),
    SnapshotCase("sdf-combinators-3d", note: "A raymarched 3D SDF combinator field.",
                 make: { RaymarchedSDF3DScene() }),
    SnapshotCase("sdf-combinators-3d-block", note: "The raymarched 3D SDF block form.",
                 make: { RaymarchedSDF3DBlockScene() }),
    SnapshotCase("sdf-combinators-3d-domain", note: "Raymarched 3D SDF domain operators.",
                 make: { RaymarchedSDF3DDomainScene() }),
    SnapshotCase("sdf-combinators-3d-shadow", note: "Raymarched 3D SDF self-shadows.",
                 make: { RaymarchedSDF3DShadowScene() }),
    SnapshotCase("sdf-combinators-3d-radial", note: "Raymarched 3D SDF radial repeat.",
                 make: { RaymarchedSDF3DRadialScene() }),
    SnapshotCase("sdf-combinators-3d-plane", note: "The raymarched 3D SDF infinite plane.",
                 make: { RaymarchedSDF3DPlaneScene() }),
    SnapshotCase("sdf-combinators-3d-cast", note: "A raymarched 3D field casting onto meshes.",
                 make: { RaymarchedSDF3DCastShadowScene() }),
    SnapshotCase("sdf-combinators-3d-gradient", note: "Raymarched 3D SDF gradient paint.",
                 make: { RaymarchedSDF3DGradientScene() }),
    SnapshotCase("sdf-combinators-gradient", note: "2D SDF combinator gradient paint.",
                 make: { SDFCombinatorsGradientScene() }),
    SnapshotCase("sdf-combinators-3d-receive", note: "A raymarched 3D field receiving a mesh shadow.",
                 make: { RaymarchedSDF3DReceiveShadowScene() }),
    SnapshotCase("sdf-combinators-3d-pointcast", note: "A raymarched 3D field casting under a point light.",
                 make: { RaymarchedSDF3DPointCastScene() }),
    SnapshotCase("sdf-combinators-stretch", note: "2D SDF combinator per-axis stretch.",
                 make: { SDFCombinatorsStretchScene() }),
    SnapshotCase("sdf-combinators-3d-stretch", note: "Raymarched 3D SDF per-axis stretch.",
                 make: { RaymarchedSDF3DStretchScene() }),
    SnapshotCase("curved-paths", note: "Curved Path fills and strokes.",
                 make: { CurvedPaths() }),
    SnapshotCase("stroke-joins-caps", note: "strokeJoin / strokeCap on the fringe stroke path.",
                 make: { StrokeJoinsCaps() }),
    SnapshotCase("bitmap-text", note: "The bitmap font specimen.",
                 make: { TextSpecimen() }),
    SnapshotCase("tinted-image", note: "A tinted textured-quad image.",
                 make: { TintedImage() }),
    SnapshotCase("gradient-shapes", note: "Gradient paint on shapes.",
                 make: { GradientShapes() }),
    SnapshotCase("status-notices", note: "The drawStatus / drawCaption standard notices.",
                 make: { StatusNotices() }),
    SnapshotCase("additive-blend", note: "The additive blend mode.",
                 make: { AdditiveBlend() }),
    SnapshotCase("accumulation", frame: 12,
                 note: "Captured at frame 12, so the reference can only match if the canvas accumulated across the prior frames (a single frame is a sparse scatter).",
                 make: { AccumulationField() }),
    SnapshotCase("tone-mapped-bloom",
                 note: "Additive light pushes the overlaps well past 1.0; .aces rolls them off instead of clipping. Pins the float intermediate + the present pass's tone-map (a .clamp render would flatten the cores to white).",
                 make: { ToneMappedBloom() }),
    SnapshotCase("effects-layers",
                 note: "Two off-screen layers, one blurred and one bloomed, composited back. Pins the whole effects path: withTarget recording, the per-target render pass, the MPS Gaussian + bloom filters, and the texture-backed-Image hand-off.",
                 make: { EffectsLayers() }),
    SnapshotCase("effects-catalog",
                 note: "A fixed scene through three filters plus a generator tile. Pins the broader filter catalog: the packed-param plumbing, a fragment color/tone pass (posterize), the gradient-map LUT upload + sample, a neighbourhood pass (Sobel edges), and the input-less generator path.",
                 make: { EffectsCatalog() }),
    SnapshotCase("effects-filters",
                 note: "A sample of the extended catalog (vibrance, oilPaint (Kuwahara), emboss, cmykHalftone, kaleidoscope, scanlines), one per family. Pins the added dispatch and the new fragments: a straight-color tone op, a multi-tap variance gather, a neighbourhood relief, a print screen, a uv warp, and a retro line pass.",
                 make: { EffectsFilters() }),
    SnapshotCase("effects-simfield", frame: 60,
                 note: "A reaction-diffusion SimField seeded with a fixed dot grid, evolved to frame 60 and recoloured. Pins the stateful sim substrate end to end: the persistent ping-pong, the seed-inject pass, the multi-substep Gray-Scott stepping, and the headless render-every-frame warmup the built-up state depends on.",
                 make: { EffectsSimField() }),
    SnapshotCase("effects-fluid", frame: 48,
                 note: "A fluid SimField driven by a fixed brush path, run to frame 48. Pins the multi-field fluid pipeline end to end: the velocity + dye splat, curl and vorticity confinement, the Jacobi pressure projection, semi-Lagrangian advection, and the persistent two-pair ping-pong with render-every-frame warmup.",
                 make: { EffectsFluid() }),
    SnapshotCase("effects-feedback", frame: 24,
                 note: "A feedback layer built up over 24 frames: each frame redraws the last, zoomed + spun + faded, plus a new dot. Pins the persistent ping-pong (previous read while writing back, the per-frame swap kept across frames) and the headless render-every-frame warmup the built-up state needs.",
                 make: { EffectsFeedback() }),
    SnapshotCase("effects-compose",
                 note: "The same blurred-band-plus-bloomed-disks scene as effects-layers, declared through compose { }. Pins the DSL's orchestration: per-layer render scale, a post-filter on each layer, the per-layer blend mode, and the bottom-to-top composite order, i.e. that the sugar resolves to the substrate it stands for.",
                 make: { EffectsCompose() }),
    SnapshotCase("effects-combine",
                 note: "Four tiles, each a two-input combine over the same scene: a luminance mask, a displacement by a blurred bump, a cross-dissolve toward a checker generator, and an inverted alpha mask. Pins the multi-input path (the .combine origin resolved after both inputs, the two-texture bind, and the mask/displace/mix fragments).",
                 make: { EffectsCombine() }),
    SnapshotCase("effects-compose-aside",
                 note: "A compose layer masked by an aside (a blurred disc, drawn only to feed the mask). Pins that the aside sugar resolves to the substrate it stands for: the aside rendered to its own layer, run through its post, fed to the combine, and never composited on its own.",
                 make: { EffectsComposeAside() }),
    SnapshotCase("effects-defocus",
                 note: "Three discs at near/mid/far depths, combined with a matching depth map and defocused with the focal plane on the middle disc. Pins the depth-of-field combine: the depth read (perceptual luminance), the circle-of-confusion gather keeping the in-focus band crisp while near and far blur, and the jittered spiral (a reproducible function of pixel position).",
                 make: { EffectsDefocus() }),
    SnapshotCase("scene-defocus-3d",
                 note: "A 3D scene drawn into a render target, defocused by the target's own depth buffer (scene.depth) with the focal plane on the middle sphere. Pins the 3D-in-target path: the target's depth attachment + resolve, the depth normalize pass (clip-space depth linearized over near/far, encoded for the perceptual DoF decode), and the depth layer feeding .defocus as the aux.",
                 make: { SceneDefocus3DScene() }),
    SnapshotCase("ssao-3d",
                 note: "A packed block field on a ground plane, ambient-occluded by the scene's own depth (scene.depth). Pins the ambient-occlusion combine: the view-space position + normal reconstructed from the depth (no normal buffer), the camera geometry stamped on the depth layer, and the spiral obscurance gather darkening crevices and contacts while flat faces stay clean.",
                 make: { AmbientOcclusionScene() }),
    SnapshotCase("ssr-3d",
                 note: "A dark glossy floor under fixed bright spheres + a pillar, reflected by the scene's own depth (scene.depth). Pins the screen-space-reflection combine: the view-space position + mesh normal feeding the reflection march, the forward projection back to the depth layer, the thickness-banded hit + binary refine, and the Fresnel/edge/distance-weighted glossy composite over the base.",
                 make: { ScreenSpaceReflectionsScene() }),
    SnapshotCase("point-cloud-3d",
                 note: "A static 3D heightfield through a fixed camera. Pins the 3D camera, the depth-tested point pipeline, and the instanced disc splats.",
                 make: { PointCloud3DScene() }),
    SnapshotCase("strange-attractor-3d",
                 note: "A Lorenz orbit, RK4-integrated and splatted through a fixed camera. Pins the attractor math, the speed coloring, and the additive point cloud.",
                 make: { StrangeAttractorScene() }),
    SnapshotCase("clifford-attractor", frame: 24,
                 note: "A Clifford map accumulated additively over several frames. Pins the iterated map plus the noClear density build-up.",
                 make: { CliffordAttractorScene() }),
    SnapshotCase("solid-primitives-3d",
                 note: "The five solid primitives through a fixed camera. Pins the depth-tested mesh pipeline, the auto-lit default material (each fill shaded by the default rig), and the model-matrix + normal baking (each shape is placed/rotated by the 3D transform stack).",
                 make: { SolidPrimitives3DScene() }),
    SnapshotCase("mesh-lighting",
                 note: "Custom lighting on solids. Pins the directional/point/spot light kinds, ambient, the spot cone, and the specular highlight (the Blinn-Phong material the auto-lit default scene doesn't exercise).",
                 make: { MeshLightingScene() }),
    SnapshotCase("textured-mesh",
                 note: "A UV-gridded sphere through a fixed camera. Pins the textured-mesh pipeline: UVs on the sphere generator, the base-color texture sampled per fragment, and the shared Blinn-Phong tail (textured surface, auto-lit default rig).",
                 make: { TexturedMesh3DScene() }),
    SnapshotCase("mesh-wireframe",
                 note: "A wireframe icosphere through a fixed camera. Pins the wireframe mesh pipeline: barycentric edge-shading from vid%3, the stroke-colored edges, and the line width from strokeWeight, with the faces see-through.",
                 make: { WireframeMesh3DScene() }),
    SnapshotCase("mesh-shadows",
                 note: "A box and a sphere above a floor, lit by a directional key with castShadows() on. Pins the shadow pass (the depth render from the light) and the shadow sample in the lit fragment (the cast shadows on the floor and between solids).",
                 make: { MeshShadowsScene() }),
    SnapshotCase("spot-shadows",
                 note: "A box and a sphere above a floor under a spot light (no directional, so the spot is the caster) with castShadows() on. Pins the spot path: a perspective shadow map fit to the cone, sampled by the same shadowFactor as the directional map, dropping shadows inside the lit pool.",
                 make: { SpotShadowsScene() }),
    SnapshotCase("point-shadows",
                 note: "Boxes around a central point light (no directional/spot, so the point light is the caster) with castShadows() on, pinning the omnidirectional path: the six-face cube depth pass and the cube depth-compare in the lit fragment, the shadows radiating outward from the light.",
                 make: { PointShadowsScene() }),
    SnapshotCase("lighting-presets",
                 note: "A still life lit by the .goldenHour LightingPreset. Pins the preset path (ambient + warm/cool directionals, the light colors from Color(kelvin:)) through the lit-mesh pipeline.",
                 make: { LightingPresetScene() }),
    SnapshotCase("mesh-materials",
                 note: "A row of spheres in the stylized materials. Pins the per-batch OllinMaterial uniform and each new shader branch: a Fresnel iridescent sheen, the rim glow (velvet), fake subsurface (jade), toon cel bands, and Gooch warm-cool. No time.",
                 make: { MeshMaterialsScene() }),
    SnapshotCase("pbr-materials",
                 note: "A metal / mixed / dielectric x roughness sweep in the physically-based shading model (shadingModel 3). Pins the new OllinMaterial metallic/roughness fields and the Cook-Torrance branch (GGX distribution, Smith visibility, Schlick Fresnel, the (1-metallic) diffuse kill). No time, so it's deterministic.",
                 make: { PBRMaterialsScene() }),
    SnapshotCase("pbr-ibl",
                 note: "Physically-based balls lit by a bundled HDRI environment (image-based lighting): pins the whole IBL path (the equirect->cube / irradiance / GGX-prefilter / BRDF-LUT bake, the split-sum ambient on the mesh fragment, and the skybox backdrop). Fixed camera + environment, no time, so the bake is deterministic.",
                 make: { IBLScene() }),
    SnapshotCase("procedural-sky",
                 note: "PBR balls + a floor lit by a procedural Hosek-Wilkie sky (no asset): pins the .sky path (the CPU coefficient cook (vendored model), the GPU sky-equirect generation, and the same equirect->cube / irradiance / GGX-prefilter bake + skybox the HDRI path uses). Fixed sun elevation + camera, no time, so the generation and bake are deterministic.",
                 make: { ProceduralSkyScene() }),
    SnapshotCase("matcap-mesh",
                 note: "Three spheres wearing built-in matcaps (chrome/clay/toon). Pins the matcap pipeline: the view-space normal sampled into the sphere texture, bypassing the scene lights and material model, tinted by fill(.white). No time.",
                 make: { MatcapMeshScene() }),
    SnapshotCase("transformed-3d",
                 note: "Point-cloud blobs placed entirely by the 3D transform stack (a center blob plus four satellites positioned by rotateY + translate and sized by scale). Pins the model-matrix bake (translate/rotate/scale composing) into the point pipeline; if the stack were ignored every blob would pile at the origin. Seeded, no time.",
                 make: { Transformed3DScene() }),
    SnapshotCase("voronoi-cells",
                 note: "A Lloyd-relaxed Voronoi diagram. Pins the Bowyer-Watson triangulation, the bisector cell clipping, and the relaxation. Seeded, no time.",
                 make: { VoronoiCells() }),
    SnapshotCase("blue-noise",
                 note: "A blue-noise (Poisson-disk) point set stippled as dots. Pins Bridson's dart-throwing sampler: the seeded scatter with a minimum spacing (no two dots closer than the radius, no clumps or gaps). Seeded, no time, so the layout is deterministic.",
                 make: { BlueNoiseScene() }),
    SnapshotCase("truchet",
                 note: "A Truchet tiling: arc tiles in the top half, diagonal tiles in the bottom, each cell's orientation chosen by the seed. Pins both tile geometries and the cross-cell connectivity (the arcs meet at shared edge midpoints, the diagonals at corners). Seeded, no time, so the layout is deterministic.",
                 make: { TruchetScene() }),
    SnapshotCase("circle-packing",
                 note: "Circle packing, both grow-to-touch flavors: a self-seeding gap-filling pack in the top half (big circles first, smaller ones filling the gaps) and a blue-noise foam in the bottom half (a circle grown at each Poisson-disk point until it touches its nearest neighbor). Pins that circles never overlap and land the same way. Seeded, no time, so the layout is deterministic.",
                 make: { CirclePackingScene() }),
    SnapshotCase("l-system",
                 note: "Four L-system presets in a 2x2: the dragon curve and Hilbert curve (turtle turning and F/G forward, no branching), the fern-like plant (the branch [ ] stack), and the stochastic plant (random productions drawn from the seed). Pins the string expansion, the turtle interpretation, branching, and fit-to-bounds. Seeded, no time, so it is deterministic.",
                 make: { LSystemScene() }),
    SnapshotCase("differential-growth", frame: 130,
                 note: "A seeded ring grown by differential growth to a fixed frame: attraction, alignment, and spatial-hash repulsion per step plus edge-splitting fold it into a brain-coral meander. Pins the stepper (forces, node injection, the spatial hash) at a deterministic frame. Seeded, and the frame is fixed, so the fold is reproducible.",
                 make: { DifferentialGrowthScene() }),
    SnapshotCase("wave-function-collapse",
                 note: "A pipe network solved by Wave Function Collapse over a blank + straight/elbow/tee/cross tileset. Pins the solver: min-entropy observation, weighted collapse, and arc-consistency propagation reach a fully legal grid (every internal pipe meets a matching pipe). Seeded, no time, so the layout is deterministic (the sorted-candidate guard keeps the Set-based solve reproducible).",
                 make: { WaveFunctionCollapseScene() }),
    SnapshotCase("shape-packing",
                 note: "A bag of polygons and a star packed by their bounding circles: big shapes first, smaller ones filling the gaps, each a random pick, rotated and scaled to its packed circle. Pins packShapes (the bounding-circle placement over the circle packer, the random rotation, the fit). Seeded, no time, so the layout is deterministic.",
                 make: { ShapePackingScene() }),
    SnapshotCase("streamlines",
                 note: "Evenly-spaced streamlines through a Perlin flow field, seeded from a blue-noise set. Pins the field (angle from noise), the both-directions tracing, and the separation test that keeps the lines from crossing. Seeded, no time, so the lines are deterministic.",
                 make: { StreamlinesScene() }),
    SnapshotCase("depth-compositing-2d",
                 note: "A 2D card standing at a world depth between two point-cloud balls. Pins depth-aware compositing: the near ball draws over the card, the far ball is hidden by it. If 2D ignored depth (always over), the card would cover both, so this fails if the depth-participation path breaks. No time.",
                 make: { DepthComposited2D() }),
    SnapshotCase("depth-scene",
                 note: "A depth-map scene (a near left half, a far right half) with a 2D bar at mid-depth. Pins drawDepthScene + the normalized depth(_:): the bar is hidden on the near half and drawn over the backdrop on the far half. Pins the depth-scene pre-pass writing per-pixel SV_Depth. Synthetic, no time.",
                 make: { DepthSceneScene() }),
    SnapshotCase("metric-depth-scene",
                 note: "The same near-left / far-right split, but the depth is real meters and the camera is built from the frame's intrinsics, so the bar sits at a true 1.5 m depth (hidden over the near (0.5 m) half, drawn over the far (3 m) half). Pins Camera3D.fromIntrinsics + the metric drawDepthScene(RGBDFrame) float-depth path + depth(at: Vector3). Synthetic, no time.",
                 make: { MetricDepthSceneScene() }),
    SnapshotCase("camera-move", frame: 30,
                 note: "A ring of solids viewed through a .turntable cinematic move, captured at a fixed frame, pins the cameraMove() rig (its pose -> Camera3D.orbiting) and the deterministic per-frame dt accumulation (the headless driver advances 1/60).",
                 make: { CameraMoveScene() }),
]

/// The ray-tracing-gated snapshots: on a ray-tracing GPU a point caster resolves to the RT
/// path (the field traces the mesh accel), which the references are recorded against; the
/// non-RT cube fallback differs and isn't snapshot-testable here.
private let snapshotRaytracingCases: [SnapshotCase] = [
    SnapshotCase("sdf-combinators-3d-pointreceive",
                 note: "A raymarched 3D field receiving a mesh's shadow under a point light. On a ray-tracing GPU the point caster resolves to the RT path (the field traces the mesh accel), which the reference is recorded against; the non-RT cube fallback differs and isn't snapshot-testable here.",
                 make: { RaymarchedSDF3DPointReceiveScene() }),
    SnapshotCase("rt-reflections-3d",
                 note: "A near-mirror metal floor under fixed metal spheres + a cube, lit by an environment, with rayTracedReflections() on. Pins the hybrid reflection path: the per-pixel closest-hit trace against the caster acceleration structure, the barycentric attribute fetch + 1-bounce hit shade, and the environment miss fallback composited through the PBR IBL specular. RT-gated, so it only runs (and is recorded) on a ray-tracing GPU.",
                 make: { RayTracedReflectionsScene() }),
]

// MARK: - Fixtures

/// A ring of solids on a ground plane, viewed through a `.turntable` cinematic move
/// captured at frame 30, pinning the `cameraMove()` rig (its pose feeding
/// `Camera3D.orbiting`) and the deterministic per-frame dt accumulation. Auto-lit,
/// no hand-set camera.
private final class CameraMoveScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.05))
        cameraMove(.turntable(period: 8), radius: 6, elevation: 0.4, fieldOfView: .pi / 3.2)
        ambientLight(Color(white: 0.12))
        directionalLight(.white, direction: Vector3(-0.4, -0.85, -0.5), intensity: 0.9)
        let count = 6
        for i in 0..<count {
            let a = Double(i) / Double(count) * .tau
            withState {
                fill(Color(hue: Double(i) / Double(count), saturation: 0.6, brightness: 0.9))
                translate(cos(a) * 2.2, 0, sin(a) * 2.2)
                drawBox(size: 1.0)
            }
        }
        withState { fill(Color(white: 0.35)); translate(0, -0.8, 0); drawPlane(width: 8, depth: 8) }
    }
}

/// A static 3D heightfield drawn as a point cloud from a fixed camera — exercises
/// the 3D camera, the depth-tested point pipeline, and the instanced disc splats.
/// No `time`, so it's deterministic at any frame.
private final class PointCloud3DScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.04))
        camera(.orbiting(target: Vector3(0, -0.1, 0), radius: 5,
                         azimuth: 0.6, elevation: 0.5, fieldOfView: .pi / 3.4))
        let n = 64, span = 3.0
        var cloud = PointCloud()
        let step = span / Double(n - 1)
        for i in 0..<n {
            let x = -span / 2 + Double(i) * step
            for j in 0..<n {
                let z = -span / 2 + Double(j) * step
                let rr = (x * x + z * z).squareRoot()
                let h = sin(rr * 3.0) * 0.34 * exp(-rr * 0.35)
                let t = max(0, min(1, h + 0.5))
                cloud.add(Vector3(x, h, z),
                          color: Color(hue: 0.62 - t * 0.52, saturation: 0.85, brightness: 0.42 + t * 0.58),
                          size: 0.07)
            }
        }
        drawPointCloud(cloud)
    }
}

/// The five solid primitives through a fixed camera, each placed and rotated by the
/// 3D transform stack — exercises the depth-tested mesh pipeline, the auto-lit default
/// material (no lights set, so the default rig shades each fill), and the model-matrix
/// + normal-matrix baking. No `time`, so deterministic.
private final class SolidPrimitives3DScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.04))
        camera(.orbiting(target: .zero, radius: 6,
                         azimuth: 0.5, elevation: 0.4, fieldOfView: .pi / 3.4))
        withState { fill(Color(hue: 0.0, saturation: 0.6, brightness: 0.9)); translate(-2.2, 0, 0); rotateY(0.6); rotateX(0.3); drawBox(size: 1.4) }
        withState { fill(Color(hue: 0.3, saturation: 0.6, brightness: 0.9)); drawSphere(radius: 0.85) }
        withState { fill(Color(hue: 0.55, saturation: 0.6, brightness: 0.9)); translate(2.2, 0, 0); rotateZ(0.4); drawCylinder(radius: 0.6, height: 1.5) }
        withState { fill(Color(hue: 0.75, saturation: 0.6, brightness: 0.9)); translate(-1.1, 0, 2.0); rotateX(0.5); drawTorus(radius: 0.6, tube: 0.26) }
        withState { fill(Color(hue: 0.12, saturation: 0.6, brightness: 0.9)); translate(1.1, -0.9, 2.0); drawPlane(width: 1.8, depth: 1.8) }
    }
}

/// Custom lighting on solids: ambient + a directional key + a point light + a spot,
/// with a specular material — pins the three light kinds, the spot cone, ambient, and
/// the specular highlight (the parts the auto-lit default doesn't exercise). No `time`.
/// A 3D scene defocused by its own depth buffer: three spheres at staggered depths
/// drawn into a depth-capturing render target, then `scene.combined(with: scene.depth,
/// .defocus(...))` with the focal plane on the middle one. Pins the 3D-in-target depth
/// path end to end. No `time`.
private final class SceneDefocus3DScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.04))
        let spheres: [(x: Double, z: Double, hue: Double)] =
            [(-2.5, 8, 0.0), (0, 0, 0.35), (2.5, -8, 0.62)]   // near → far
        let scene = renderTarget()
        withTarget(scene) {
            background(Color(white: 0.04))
            perspective(eye: Vector3(0, 1.5, 14), target: Vector3(0, 0, -3),
                        fieldOfView: .pi / 4, near: 5, far: 30)
            for s in spheres {
                withState {
                    translate(s.x, 0, s.z)
                    fill(Color(hue: s.hue, saturation: 0.65, brightness: 1.0))
                    drawSphere(radius: 1.5)
                }
            }
        }
        // The middle sphere sits at depth ≈0.36 over near/far; focus there so the
        // foreground spreads over it and the background blurs behind.
        drawImage(scene.combined(with: scene.depth,
                                 .defocus(focus: 0.36, range: 0.07, maxBlur: 20)).image, 0, 0)
    }
}

private final class AmbientOcclusionScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.07))
        let scene = renderTarget()
        withTarget(scene) {
            background(Color(hex: 0x121318))
            // Fixed camera + near/far bracketing the block field (deterministic).
            camera(.orbiting(target: Vector3(0, 0.4, 0), radius: 8,
                             azimuth: 0.7, elevation: 0.55,
                             fieldOfView: .pi / 4, near: 3, far: 16))
            ambientLight(Color(white: 0.55))
            directionalLight(.white, direction: Vector3(-0.4, -1, -0.3), intensity: 0.7)
            withState {
                fill(Color(white: 0.8)); translate(0, -0.2, 0)
                drawBox(width: 12, height: 0.4, depth: 12)
            }
            let n = 4
            let cell = 1.2, box = 0.95
            for ix in 0 ..< n {
                for iz in 0 ..< n {
                    let fx = Double(ix) - Double(n - 1) / 2
                    let fz = Double(iz) - Double(n - 1) / 2
                    let h = 0.6 + 1.2 * (0.5 + 0.5 * sin(Double(ix) * 1.3 + Double(iz) * 0.7))
                    withState {
                        translate(fx * cell, h / 2, fz * cell)
                        fill(Color(hue: 0.07 + 0.12 * Double(ix + iz), saturation: 0.4, brightness: 0.95))
                        drawBox(width: box, height: h, depth: box)
                    }
                }
            }
        }
        drawImage(scene.combined(with: scene.depth,
                                 .ambientOcclusion(radius: 0.5, intensity: 1.0)).image, 0, 0)
    }
}

private final class ScreenSpaceReflectionsScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        let scene = renderTarget()
        withTarget(scene) {
            background(Color(hex: 0x06080d))
            // Fixed camera + near/far bracketing the scene (deterministic).
            camera(.orbiting(target: Vector3(0, 0.7, 0), radius: 10,
                             azimuth: 0.5, elevation: 0.55,
                             fieldOfView: .pi / 4, near: 2, far: 24))
            ambientLight(Color(white: 0.3))
            directionalLight(.white, direction: Vector3(-0.35, -1, -0.2), intensity: 0.95)
            withState {
                fill(Color(white: 0.05)); translate(0, -0.05, 0)
                drawBox(width: 40, height: 0.1, depth: 40)
            }
            // A loose scatter of well-separated spheres + a cube on a glossy floor.
            let spheres: [(x: Double, z: Double, hue: Double)] = [
                (-3.8, 1.5, 0.02), (3.6, 2.0, 0.33), (-1.0, -3.5, 0.58), (5.2, -2.5, 0.85),
            ]
            for s in spheres {
                withState {
                    translate(s.x, 1.0, s.z)
                    fill(Color(hue: s.hue, saturation: 0.75, brightness: 1.0))
                    drawSphere(radius: 1.0)
                }
            }
            withState {
                fill(Color(hex: 0xeef0fa)); translate(-4.5, 0.7, -3.0); rotateY(0.6)
                drawBox(width: 1.4, height: 1.4, depth: 1.4)
            }
        }
        drawImage(scene.combined(with: scene.depth,
                                 .screenSpaceReflections(intensity: 0.9, roughness: 0.15,
                                                         fresnel: 0.8)).image, 0, 0)
    }
}

private final class RayTracedReflectionsScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x14171d))
        // Fixed camera + near/far bracketing the scene (deterministic).
        camera(.orbiting(target: Vector3(0, 0.7, 0), radius: 8,
                         azimuth: 0.6, elevation: 0.36,
                         fieldOfView: .pi / 4, near: 2, far: 24))
        environment(.studio.intensity(1.1))
        directionalLight(.white, direction: Vector3(-0.4, -1, -0.25), intensity: 0.7)
        castShadows()
        rayTracedReflections()
        // A near-mirror metal floor reflecting the meshes above it.
        withState {
            material(.metal(roughness: 0.06)); fill(Color(hex: 0x8a8f9c))
            translate(0, -0.5, 0); drawBox(width: 24, height: 1.0, depth: 24)
        }
        withState {
            material(.polishedMetal); fill(Color(hex: 0xe8ebf2))
            translate(-2.4, 1.0, 0); drawSphere(radius: 1.0)
        }
        withState {
            material(.metal(roughness: 0.12)); fill(Color(hex: 0xffc94a))
            translate(2.4, 1.0, 0.4); drawSphere(radius: 1.0)
        }
        withState {
            material(.polishedMetal); fill(Color(hex: 0xe2e6f0))
            translate(0, 1.1, -1.2); drawBox(width: 0.9, height: 2.2, depth: 0.9)
        }
    }
}

private final class MeshLightingScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.03))
        camera(.orbiting(target: .zero, radius: 6.5,
                         azimuth: 0.4, elevation: 0.35, fieldOfView: .pi / 3.4))
        ambientLight(Color(white: 0.1))
        directionalLight(Color(hue: 0.09, saturation: 0.3, brightness: 1), direction: Vector3(-0.5, -0.8, -0.4), intensity: 0.7)
        pointLight(Color(hue: 0.5, saturation: 0.8, brightness: 1), at: Vector3(3, 2.5, 2.5), intensity: 1.2)
        spotLight(Color(hue: 0.85, saturation: 0.7, brightness: 1), at: Vector3(-2, 4, 1),
                  direction: Vector3(0.4, -1, -0.2), angle: .pi / 4, penumbra: 0.5, intensity: 1.6)
        withState {
            fill(Color(white: 0.85)); specular(0.7); shininess(80)
            translate(-1.6, 0, 0); drawSphere(radius: 1.0)
        }
        withState {
            fill(Color(hue: 0.05, saturation: 0.5, brightness: 0.9)); specular(0.4); shininess(40)
            translate(1.6, 0, 0); rotateY(0.5); rotateX(0.3); drawBox(size: 1.5)
        }
        withState { fill(Color(white: 0.4)); translate(0, -1.4, 0); drawPlane(width: 6, depth: 6) }
    }
}

/// A UV-gridded sphere through a fixed camera, lit by the default rig — pins the
/// textured-mesh pipeline (sphere UVs, the per-fragment base-color texture sample, the
/// shared lit tail). The texture is built from a pure function of pixel coordinates, so
/// the scene is deterministic. No `time`.
private final class TexturedMesh3DScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private lazy var globe = Mesh.sphere(radius: 1.5, segments: 48, rings: 24)
        .textured(TexturedMesh3DScene.grid)

    override func draw() {
        background(Color(white: 0.05))
        camera(.orbiting(target: .zero, radius: 5,
                         azimuth: 0.6, elevation: 0.3, fieldOfView: .pi / 3.4))
        drawMesh(globe)
    }

    /// A deterministic UV grid: hue by u, a brightness checker, dark gridlines.
    static let grid: Image = {
        let n = 64, cell = 4
        let img = Image(width: n, height: n)
        for y in 0..<n {
            for x in 0..<n {
                if x % cell == 0 || y % cell == 0 {
                    img[x, y] = Color(white: 0.12)
                } else {
                    let checker = ((x / cell) + (y / cell)) % 2 == 0
                    img[x, y] = Color(hue: Double(x) / Double(n - 1),
                                      saturation: 0.7, brightness: checker ? 0.95 : 0.55)
                }
            }
        }
        return img
    }()
}

/// A box and a sphere above a floor, lit by a directional key with `castShadows()` on,
/// through a fixed camera — pins the shadow pass (the depth render from the light) and
/// the shadow sample in the lit mesh fragment (the cast shadows on the floor and the
/// sphere's shadow reaching toward the box). No `time`, so it's deterministic.
private final class MeshShadowsScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.05))
        camera(.orbiting(target: Vector3(0, 0.6, 0), radius: 7,
                         azimuth: 0.5, elevation: 0.45, fieldOfView: .pi / 3.6))
        ambientLight(Color(white: 0.15))
        directionalLight(.white, direction: Vector3(-0.5, -0.85, -0.35), intensity: 1.0)
        castShadows()
        withState { fill(Color(white: 0.8)); specular(0.05); drawPlane(width: 10, depth: 10) }
        withState {
            fill(Color(hue: 0.03, saturation: 0.6, brightness: 0.95)); specular(0.3); shininess(40)
            translate(-1.1, 1.0, 0); rotateY(0.5); drawBox(size: 1.6)
        }
        withState {
            fill(Color(hue: 0.55, saturation: 0.55, brightness: 0.95)); specular(0.3); shininess(40)
            translate(1.3, 1.3, 0.3); drawSphere(radius: 1.1)
        }
    }
}

/// A box and a sphere above a floor under a single spot light with `castShadows()` on,
/// through a fixed camera — pins the spot caster (a perspective shadow map fit to the
/// cone). The scene has no directional light, so the spot is the chosen caster; the
/// solids drop shadows inside its lit pool and the rest falls to ambient + a point
/// fill. No `time`, so it's deterministic.
private final class SpotShadowsScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.04))
        camera(.orbiting(target: Vector3(0, 0.6, 0), radius: 7,
                         azimuth: 0.5, elevation: 0.5, fieldOfView: .pi / 3.6))
        ambientLight(Color(white: 0.12))
        pointLight(Color(white: 0.4), at: Vector3(-4, 3, 4), intensity: 0.4)
        spotLight(.white, at: Vector3(-1.5, 6, 3),
                  direction: (Vector3(0, 0.6, 0) - Vector3(-1.5, 6, 3)).normalized,
                  angle: .pi / 4, penumbra: 0.4, intensity: 1.3)
        castShadows()
        withState { fill(Color(white: 0.82)); specular(0.05); drawPlane(width: 10, depth: 10) }
        withState {
            fill(Color(hue: 0.03, saturation: 0.6, brightness: 0.95)); specular(0.3); shininess(40)
            translate(-1.1, 1.0, 0); rotateY(0.5); drawBox(size: 1.6)
        }
        withState {
            fill(Color(hue: 0.55, saturation: 0.55, brightness: 0.95)); specular(0.3); shininess(40)
            translate(1.3, 1.1, 0.3); drawSphere(radius: 1.1)
        }
    }
}

/// Boxes ringing a central point light over a floor with `castShadows()` on, through a
/// fixed camera, pinning the omnidirectional caster (the six-face cube depth pass and the
/// direction-sampled cube compare). With no directional or spot light the point light is
/// the chosen caster, and the boxes drop shadows radiating outward. No `time`, so it's
/// deterministic.
private final class PointShadowsScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.04))
        camera(.orbiting(target: Vector3(0, 0.6, 0), radius: 8,
                         azimuth: 0.4, elevation: 0.6, fieldOfView: .pi / 3.6))
        ambientLight(Color(white: 0.10))
        pointLight(.white, at: Vector3(0, 2.2, 0), intensity: 1.5)
        castShadows()
        withState { fill(Color(white: 0.82)); specular(0.05); drawPlane(width: 14, depth: 14) }
        for i in 0..<4 {
            let a = Double(i) / 4 * .tau
            withState {
                translate(cos(a) * 2.6, 0.9, sin(a) * 2.6)
                fill(Color(hue: Double(i) / 4, saturation: 0.55, brightness: 0.95))
                specular(0.3); shininess(40)
                drawBox(width: 0.9, height: 1.8, depth: 0.9)
            }
        }
    }
}

/// The same still life lit by the `.goldenHour` `LightingPreset` through a fixed
/// camera — pins the preset path (one call setting the ambient + a warm low
/// directional + a cool sky fill, the lights' colors from `Color(kelvin:)`) feeding
/// the same lit-mesh pipeline. If the preset's lights or the kelvin math regressed,
/// the warm/cool balance would shift. No `time`, so it's deterministic.
private final class LightingPresetScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.04))
        camera(.orbiting(target: Vector3(0, -0.1, 0), radius: 6.5,
                         azimuth: 0.4, elevation: 0.32, fieldOfView: .pi / 3.4))
        lightingPreset(.goldenHour)
        withState { translate(0, -1.2, 0); fill(Color(white: 0.55)); specular(0.05); drawPlane(width: 12, depth: 12) }
        withState {
            fill(Color(white: 0.85)); specular(0.6); shininess(100)
            translate(-1.6, -0.3, 0); drawSphere(radius: 1.0)
        }
        withState {
            fill(Color(hue: 0.04, saturation: 0.5, brightness: 0.9)); specular(0.4); shininess(48)
            translate(1.4, -0.1, -0.2); rotateY(0.5); rotateX(0.3); drawBox(size: 1.4)
        }
    }
}

/// A wireframe icosphere through a fixed camera, stroke-colored — pins the wireframe
/// mesh pipeline (barycentric edges from vid%3, the stroke edge color, the line width
/// from strokeWeight). The faces are see-through, so the back edges show through. No
/// `time`.
private final class WireframeMesh3DScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.04))
        camera(.orbiting(target: .zero, radius: 4,
                         azimuth: 0.5, elevation: 0.4, fieldOfView: .pi / 3.4))
        wireframe()
        strokeWeight(1.5)
        stroke(Color(hue: 0.55, saturation: 0.6, brightness: 1))
        withState { rotateY(0.6); rotateX(0.3); drawMesh(.icosphere(radius: 1.4, subdivisions: 2)) }
    }
}

/// A row of spheres in the stylized materials under a fixed camera and custom lights —
/// pins the per-batch material uniform and the new shader branches (iridescence, rim,
/// subsurface, toon, Gooch). No `time`, so it's deterministic.
private final class MeshMaterialsScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.05))
        camera(.orbiting(target: .zero, radius: 7,
                         azimuth: 0.35, elevation: 0.28, fieldOfView: .pi / 3.2))
        ambientLight(Color(white: 0.14))
        directionalLight(Color(kelvin: 5600), direction: Vector3(-0.4, -0.6, -0.5), intensity: 0.8)
        pointLight(.white, at: Vector3(3, 4, 4), intensity: 1.0)
        let mats: [(Material, Color)] = [
            (.iridescent, Color(white: 0.18)),
            (.velvet,     Color(hue: 0.93, saturation: 0.6, brightness: 0.4)),
            (.jade,       Color(hue: 0.42, saturation: 0.55, brightness: 0.55)),
            (.toon,       Color(hue: 0.07, saturation: 0.8, brightness: 0.95)),
            (.gooch,      Color(white: 0.55)),
        ]
        for (i, m) in mats.enumerated() {
            withState {
                translate(-3.2 + Double(i) * 1.6, 0, 0)
                fill(m.1)
                material(m.0)
                drawSphere(radius: 0.7)
            }
        }
    }
}

/// A metal / mixed / dielectric × roughness grid in the physically-based shading model
/// under a fixed camera and custom lights — pins the metallic/roughness fields and the
/// Cook-Torrance branch (no IBL: the smooth metals read dark, which is correct). No `time`.
private final class PBRMaterialsScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.05))
        camera(.orbiting(target: .zero, radius: 8,
                         azimuth: 0.3, elevation: 0.26, fieldOfView: .pi / 3.4))
        ambientLight(Color(white: 0.12))
        directionalLight(Color(kelvin: 5400), direction: Vector3(-0.4, -0.6, -0.5), intensity: 1.0)
        pointLight(.white, at: Vector3(3, 4, 4), intensity: 1.2)

        let albedos = [
            Color(hue: 0.11, saturation: 0.65, brightness: 0.95),   // gold-ish metal
            Color(white: 0.72),                                     // neutral
            Color(hue: 0.58, saturation: 0.70, brightness: 0.90),   // blue dielectric
        ]
        let cols = 4
        for row in 0..<3 {
            let metallic = 1.0 - Double(row) / 2.0                  // 1, 0.5, 0
            for col in 0..<cols {
                let roughness = map(Double(col), 0, Double(cols - 1), 0.08, 1.0)
                withState {
                    translate(-2.4 + Double(col) * 1.6, 1.7 - Double(row) * 1.7, 0)
                    fill(albedos[row])
                    material(Material(shading: .physicallyBased,
                                      metallic: metallic, roughness: roughness))
                    drawSphere(radius: 0.65)
                }
            }
        }
    }
}

/// Physically-based balls (polished metal, brushed metal, dielectric) lit by the bundled
/// `studio` HDRI environment, which also shows as the backdrop — pins the IBL bake, the
/// split-sum ambient, and the skybox. Fixed camera + environment, no `time`, deterministic.
private final class IBLScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.05))
        toneMap(.aces)
        camera(.orbiting(target: .zero, radius: 6,
                         azimuth: 0.4, elevation: 0.14, fieldOfView: .pi / 3.4))
        environment(.studio)
        let balls: [(Material, Color, Double)] = [
            (.polishedMetal,              .white,                                            -2.0),
            (.metal(roughness: 0.4),      Color(hue: 0.09, saturation: 0.45, brightness: 0.95), 0),
            (.dielectric(roughness: 0.4), Color(hue: 0.58, saturation: 0.55, brightness: 0.9),  2.0),
        ]
        for (m, c, x) in balls {
            withState { translate(x, 0, 0); fill(c); material(m); drawSphere(radius: 0.8) }
        }
    }
}

/// PBR balls + a floor lit by a procedural Hosek-Wilkie sky (no asset) under a fixed sun and
/// camera, pins the `.sky` path end to end: the CPU coefficient cook, the GPU sky-equirect
/// generation, and the same cube / irradiance / prefilter bake + skybox the HDRI path uses.
private final class ProceduralSkyScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.black)
        toneMap(.aces)
        camera(.orbiting(target: Vector3(0, 0.4, 0), radius: 7,
                         azimuth: 0.4, elevation: 0.12, fieldOfView: .pi / 3.4))
        environment(.sky(turbidity: 3, sunElevation: 0.5))
        let balls: [(Material, Double)] = [
            (.polishedMetal, -2.0), (.metal(roughness: 0.4), 0), (.dielectric(roughness: 0.4), 2.0),
        ]
        for (m, x) in balls {
            withState { translate(x, 0.4, 0); fill(.white); material(m); drawSphere(radius: 0.8) }
        }
        withState {
            translate(0, -0.6, 0); fill(Color(white: 0.55)); material(.roughPlastic)
            drawBox(width: 20, height: 0.3, depth: 20)
        }
    }
}

/// Three spheres each wearing a built-in matcap (chrome, clay, toon) under a fixed
/// camera — pins the matcap pipeline: the view-space normal → sphere-texture lookup,
/// independent of the scene lights, tinted by fill(.white). No `time`, so deterministic.
private final class MatcapMeshScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.05))
        camera(.orbiting(target: .zero, radius: 5,
                         azimuth: 0.3, elevation: 0.25, fieldOfView: .pi / 3.2))
        fill(.white)
        let caps: [Matcap] = [.chrome, .clay, .toon]
        for (i, cap) in caps.enumerated() {
            withState {
                translate(-2.0 + Double(i) * 2.0, 0, 0)
                matcap(cap)
                drawSphere(radius: 0.8)
            }
        }
    }
}

/// Point-cloud blobs placed entirely by the 3D transform stack: a central blob and
/// four satellites positioned with `rotateY` + `translate` and sized with `scale`,
/// under a fixed camera. Exercises the model matrix baking into the point pipeline.
/// Seeded and `time`-free, so it's deterministic.
private final class Transformed3DScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.04))
        seed(3)
        camera(.orbiting(target: .zero, radius: 6.5, azimuth: 0.5, elevation: 0.4,
                         fieldOfView: .pi / 3.2))
        let center = makeBlob(count: 1400, dot: 0.06,
                              color: Color(hue: 0.09, saturation: 0.85, brightness: 1))
        let satellite = makeBlob(count: 900, dot: 0.09,
                                 color: Color(hue: 0.58, saturation: 0.7, brightness: 0.95))

        withState {
            scale(Vector3(0.9, 0.9, 0.9))
            drawPointCloud(center)
        }
        for i in 0..<4 {
            withState {
                rotateY(Double(i) * .pi / 2 + 0.3)
                translate(2.6, 0, 0)
                scale(Vector3(0.4, 0.4, 0.4))
                drawPointCloud(satellite)
            }
        }
    }

    private func makeBlob(count: Int, dot: Double, color: Color) -> PointCloud {
        var cloud = PointCloud()
        for _ in 0..<count {
            let dir = Vector3(randomGaussian(), randomGaussian(), randomGaussian()).normalized
            cloud.add(dir * (0.9 + random(0.2)), color: color, size: dot)
        }
        return cloud
    }
}

/// A Lloyd-relaxed Voronoi diagram of seeded sites, each cell filled from a
/// colormap and outlined — exercises the Bowyer–Watson triangulation, the
/// bisector cell clipping (incl. the boundary cells clamped to the canvas), and
/// the relaxation. Seeded and `time`-free, so it's deterministic.
private final class VoronoiCells: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.1))
        seed(11)
        let scattered = (0..<40).map { _ in randomVector(in: canvasRectangle) }
        let sites = lloyd(scattered, iterations: 4)
        let cells = voronoi(sites).cells
        stroke(Color(white: 0.1)); strokeWeight(1.5)
        for (i, cell) in cells.enumerated() {
            fill(Colormap.viridis.color(at: Double(i) / Double(max(cells.count - 1, 1))))
            drawShape(cell)
        }
    }
}

/// A blue-noise (Poisson-disk) point set stippled as dots — exercises Bridson's
/// dart-throwing sampler: a seeded scatter with a guaranteed minimum spacing, so
/// the coverage is even with no clumps or gaps. Seeded and `time`-free, so it's
/// deterministic.
private final class BlueNoiseScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x11141C))
        seed(9)
        let points = poissonDisk(radius: 12)
        noStroke()
        for p in points {
            let flow = signedNoise(p.x * 0.01, p.y * 0.01)
            fill(Color.mix(Color(hex: 0xE8ECF4), Color(hex: 0x5AA9E6), t: (flow + 1) * 0.5))
            drawCircle(center: p, radius: 1.6 + (flow + 1) * 1.4)
        }
    }
}

/// A Truchet tiling with both built-in tiles — arc tiles in the top half,
/// diagonal tiles in the bottom — exercising both tile geometries and the
/// cross-cell connectivity (arcs meeting at shared edge midpoints, diagonals at
/// corners). Seeded and `time`-free, so it's deterministic.
private final class TruchetScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x101418))
        seed(3)
        noFill()
        strokeCap(.round)
        strokeWeight(4)

        let top = Rectangle(x: 0, y: 0, width: 256, height: 128)
        let bottom = Rectangle(x: 0, y: 128, width: 256, height: 128)

        stroke(Color(hex: 0x2EC4B6))
        for c in truchet(in: top, columns: 6, rows: 3, tile: .arcs) {
            drawPolyline(c.points, closed: false)
        }
        stroke(Color(hex: 0xF6511D))
        for c in truchet(in: bottom, columns: 6, rows: 3, tile: .diagonals) {
            drawPolyline(c.points, closed: false)
        }
    }
}

/// Circle packing with both grow-to-touch flavors: a self-seeding gap-filling
/// pack in the top half and a blue-noise foam (a circle grown at each Poisson-disk
/// point) in the bottom. Pins that the circles never overlap and land the same
/// way. Seeded and `time`-free, so it's deterministic.
private final class CirclePackingScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0E1116))
        seed(11)
        noStroke()

        let top = Rectangle(x: 0, y: 0, width: 256, height: 128)
        fill(Color(hex: 0xF2C14E))
        drawCircles(packCircles(in: top, count: 200, minRadius: 2, maxRadius: 28, padding: 1.5))

        let bottom = Rectangle(x: 0, y: 128, width: 256, height: 128)
        let sites = poissonDisk(in: bottom, radius: 20)
        fill(Color(hex: 0xE86A5B))
        drawCircles(packCircles(around: sites, in: bottom, padding: 1.5))
    }
}

/// Four L-system presets in a 2x2: two curves (dragon, Hilbert), the fern-like
/// plant (the branch stack), and the stochastic plant (random productions from
/// the seed). Pins expansion, turtle interpretation, branching, and fit. Seeded
/// and `time`-free, so it's deterministic.
private final class LSystemScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0E1013))
        seed(7)
        noFill()
        strokeCap(.round)
        strokeWeight(1)

        let tiles: [(LSystem, Int, Rectangle, UInt32)] = [
            (.dragonCurve, 11, Rectangle(x: 0, y: 0, width: 128, height: 128), 0x7EC8E3),
            (.hilbertCurve, 4, Rectangle(x: 128, y: 0, width: 128, height: 128), 0xB18AE0),
            (.plant, 5, Rectangle(x: 0, y: 128, width: 128, height: 128), 0x77DD9B),
            (.randomPlant, 6, Rectangle(x: 128, y: 128, width: 128, height: 128), 0x9BE06E),
        ]
        for (system, iterations, frame, hex) in tiles {
            stroke(Color(hex: hex))
            for c in lSystem(system, iterations: iterations, in: frame, padding: 8) {
                drawPolyline(c.points, closed: false)
            }
        }
    }
}

/// A seeded ring grown by differential growth to a fixed frame, folded into a
/// brain-coral meander. Pins the stepper (forces, node injection, the spatial
/// hash). Seeded and rendered at a fixed frame, so it's deterministic.
private final class DifferentialGrowthScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    private let growth = DifferentialGrowth.ring(
        center: Vector2(128, 128), radius: 26, count: 30, seed: 7,
        maxSegmentLength: 4, repulsionRadius: 8,
        attraction: 0.18, repulsion: 0.6, alignment: 0.25,
        jitter: 0.4, growthRate: 0.8, maxNodes: 1600,
        bounds: Rectangle(x: 10, y: 10, width: 236, height: 236))

    override func draw() {
        growth.step(3)
        background(Color(hex: 0x0F1012))
        noFill()
        strokeWeight(1.4)
        strokeCap(.round)
        strokeJoin(.round)
        stroke(Color(hex: 0x7FE0C4))
        drawPolyline(growth.nodes, closed: true)
    }
}

/// A pipe network solved by Wave Function Collapse over a blank + straight /
/// elbow / tee / cross tileset. Pins the solver (min-entropy observation,
/// weighted collapse, arc-consistency propagation). Seeded and `time`-free, so
/// it's deterministic.
private final class WaveFunctionCollapseScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0E1116))
        seed(4)
        let tiles = [WFCTile([0, 0, 0, 0], weight: 1.1)]
            + WFCTile([1, 0, 1, 0], weight: 1.6).rotations(2)
            + WFCTile([1, 1, 0, 0], weight: 1.3).rotations(4)
            + WFCTile([1, 1, 1, 0], weight: 0.5).rotations(4)
            + [WFCTile([1, 1, 1, 1], weight: 0.3)]
        guard let grid = wfc(tiles: tiles, columns: 9, rows: 9) else { return }

        strokeCap(.round); strokeJoin(.round); strokeWeight(3); noFill()
        stroke(Color(hex: 0x6FD3C7))
        drawWFC(grid, padding: .all(12)) { index, cell in
            let sockets = tiles[index].sockets
            let mids = [Vector2(cell.center.x, cell.y),
                        Vector2(cell.x + cell.width, cell.center.y),
                        Vector2(cell.center.x, cell.y + cell.height),
                        Vector2(cell.x, cell.center.y)]
            for edge in 0 ..< 4 where sockets[edge] != 0 {
                drawLine(cell.center, mids[edge])
            }
        }
    }
}

/// A bag of polygons and a star packed by their bounding circles, rotated and
/// scaled to fit. Pins `packShapes` (bounding-circle placement over the circle
/// packer, random rotation, the fit). Seeded and `time`-free, so it's
/// deterministic.
private final class ShapePackingScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    private func polygon(_ sides: Int, star: Bool = false) -> Shape {
        let count = star ? sides * 2 : sides
        let points = (0 ..< count).map { i -> Vector2 in
            let a = Double(i) / Double(count) * 2 * .pi - .pi / 2
            let r = (star && i % 2 == 1) ? 0.46 : 1.0
            return Vector2(cos(a) * r, sin(a) * r)
        }
        return Shape(points, closed: true)
    }

    override func draw() {
        background(Color(hex: 0x11121A))
        seed(4)
        noStroke()
        let bag = [polygon(3), polygon(4), polygon(5), polygon(6), polygon(5, star: true)]
        let packed = packShapes(bag, count: 160, minRadius: 4, maxRadius: 34, padding: 1.5, scale: 0.9)
        for shape in packed {
            let pts = shape.contours.flatMap(\.points)
            let c = pts.reduce(Vector2.zero, +) * (1 / Double(max(pts.count, 1)))
            fill(Color.mix(Color(hex: 0x6FD3C7), Color(hex: 0xF2799E), t: c.x / 256))
            drawShape(shape)
        }
    }
}

/// Evenly-spaced streamlines through a Perlin flow field, seeded from a
/// blue-noise set. Pins the field, the both-directions tracing, and the
/// separation test that keeps lines from crossing. Seeded and `time`-free.
private final class StreamlinesScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0F1117))
        seed(7)
        let field = flowField(scale: 0.006)
        let seeds = poissonDisk(radius: 6)
        strokeCap(.round); noFill(); strokeWeight(1.5)
        for line in field.streamlines(from: seeds, stepLength: 2, steps: 120,
                                      bounds: bounds, separation: 8) {
            let mid = line[line.count / 2]
            let v = (signedNoise(mid.x * 0.004, mid.y * 0.004) + 1) * 0.5
            stroke(Color(hue: 0.52 + v * 0.34, saturation: 0.5, brightness: 0.96))
            drawPolyline(line)
        }
    }
}

/// A 2D card placed at a world depth between two point-cloud balls — exercises
/// depth-aware compositing (`withBillboard`/`depth(at:)`): the near ball composites
/// over the card, the far ball is hidden by it. The camera looks down −z from +z,
/// so the +z ball is in front of the origin (over the card) and the −z ball behind
/// it (occluded). No `time`, deterministic blob.
private final class DepthComposited2D: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    // A small fixed cloud of offsets (deterministic hash), so the balls hold still.
    private let blob: [Vector3] = {
        func h(_ n: Int) -> Double {
            let x = sin(Double(n) * 12.9898) * 43758.5453
            return (x - floor(x)) * 2 - 1
        }
        return (0..<120).map { i in
            Vector3(h(i * 4), h(i * 4 + 1), h(i * 4 + 2)) * (abs(h(i * 4 + 3)) * 0.22 + 0.05)
        }
    }()

    override func draw() {
        background(Color(white: 0.04))
        camera(.perspective(eye: Vector3(0, 0, 4.2), target: .zero, fieldOfView: .pi / 3))
        var cloud = PointCloud()
        for off in blob {
            cloud.add(Vector3(-0.85, 0, 1.25) + off, color: Color(hue: 0.5, saturation: 0.7, brightness: 1.0), size: 0.07)
            cloud.add(Vector3(0.85, 0, -1.25) + off, color: Color(hue: 0.07, saturation: 0.8, brightness: 1.0), size: 0.07)
        }
        drawPointCloud(cloud)
        withBillboard(at: .zero) {
            noStroke()
            fill(Color(white: 0.95))
            drawRect(center: .zero, width: 150, height: 92, cornerRadius: 12)
        }
    }
}

/// A depth-map scene with a 2D bar at mid-depth — exercises `drawDepthScene` (the
/// pre-pass that writes per-pixel SV_Depth from a depth map) and the normalized
/// `depth(_:)`. The depth map's left half is near (white), the right half far
/// (black); a white bar at depth 0.5 is hidden on the near half and drawn over the
/// backdrop on the far half. Synthetic Images, no `time`, so it's deterministic.
private final class DepthSceneScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private let n = 64
    private lazy var backdrop = makeBackdrop()
    private lazy var depthMap = makeDepthMap()

    private func makeBackdrop() -> Image {
        var px = [UInt8](repeating: 255, count: n * n * 4)
        for y in 0..<n {
            for x in 0..<n {
                let t = Double(x) / Double(n - 1)
                let i = (y * n + x) * 4
                px[i] = UInt8(40 + t * 200); px[i + 1] = 60; px[i + 2] = UInt8(220 - t * 180)
            }
        }
        return Image(width: n, height: n, premultipliedRGBA: px)!
    }

    private func makeDepthMap() -> Image {
        var px = [UInt8](repeating: 255, count: n * n * 4)
        for y in 0..<n {
            for x in 0..<n {
                let v: UInt8 = x < n / 2 ? 255 : 0   // left near (white), right far (black)
                let i = (y * n + x) * 4
                px[i] = v; px[i + 1] = v; px[i + 2] = v
            }
        }
        return Image(width: n, height: n, premultipliedRGBA: px)!
    }

    override func draw() {
        background(.black)
        drawDepthScene(color: backdrop, depth: depthMap)
        depth(0.5)
        noStroke()
        fill(.white)
        drawRect(center: Vector2(width / 2, height / 2), width: width * 0.7, height: height * 0.26)
    }
}

/// A *metric* depth scene: the same left-near / right-far split, but the depth is
/// real meters and the camera is built from the frame's intrinsics, so the 2D bar is
/// placed at a true 1.5 m depth. The left half (0.5 m, nearer) hides the bar; the
/// right half (3 m, farther) shows it. Pins `Camera3D.fromIntrinsics`, the metric
/// `drawDepthScene(_ frame:)` float-depth path, and a metric `depth(at: Vector3)`.
private final class MetricDepthSceneScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private let n = 64
    private lazy var frame = makeFrame()

    private func makeFrame() -> RGBDFrame {
        var px = [UInt8](repeating: 255, count: n * n * 4)
        var depth = [Float](repeating: 0, count: n * n)
        for y in 0..<n {
            for x in 0..<n {
                let t = Double(x) / Double(n - 1)
                let i = (y * n + x) * 4
                px[i] = UInt8(40 + t * 200); px[i + 1] = 60; px[i + 2] = UInt8(220 - t * 180)
                depth[y * n + x] = x < n / 2 ? 0.5 : 3.0   // left near, right far (meters)
            }
        }
        let color = Image(width: n, height: n, premultipliedRGBA: px)!
        let k = CameraIntrinsics(fx: 60, fy: 60, cx: Double(n) / 2, cy: Double(n) / 2,
                                 width: n, height: n)
        return RGBDFrame(color: color, depth: depth, confidence: nil,
                         depthWidth: n, depthHeight: n, intrinsics: k)
    }

    override func draw() {
        background(.black)
        camera(.fromIntrinsics(frame.intrinsics, near: 0.1, far: 10))
        drawDepthScene(frame)
        depth(at: Vector3(0, 0, -1.5))   // a true 1.5 m depth, between the halves
        noStroke()
        fill(.white)
        drawRect(center: Vector2(width / 2, height / 2), width: width * 0.7, height: height * 0.26)
    }
}

/// A few solid SDF fills on white — large flat regions, so anti-aliased edges
/// are a small fraction of the frame. Pure SDF pipeline.
/// A user-supplied `Shader` run as a generator: pins the compose + compile path,
/// the `ShaderInfo` binding, the wrapper's sRGB round-trip, and the `palette`
/// library helper. Time-independent so the reference is stable at any frame.
private final class UserShaderGenerator: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    private let shader = Shader("""
    float4 shade(float2 uv, ShaderInfo info) {
        float2 p = (uv * 2.0 - 1.0) * 4.0;
        float fx = cos(p.x) * cos(p.y);
        float fy = sin(p.x) * sin(p.y);
        float v = 0.5 + 0.5 * sin((fx * fx + fy * fy) * 6.28318);
        float3 col = palette(v, float3(0.5), float3(0.5),
                             float3(1.0), float3(0.0, 0.33, 0.67));
        return float4(col, 1.0);
    }
    """)

    override func draw() {
        drawImage(generate(shader).image, 0, 0)
    }
}

private final class SolidShapes: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.white)
        noStroke()
        fill(.black)
        drawRect(center: Vector2(width / 2, height / 2), width: width * 0.6, height: height * 0.6)
        fill(Color(red: 0.9, green: 0.2, blue: 0.2))
        drawCircle(width * 0.28, height * 0.28, width * 0.16)
        fill(Color(red: 0.2, green: 0.5, blue: 0.95))
        drawRect(corner: Vector2(width * 0.6, height * 0.6), width: width * 0.28, height: height * 0.28)
    }
}

/// A tessellated triangle (the triangle pipeline) with an SDF star drawn over it
/// (the SDF pipeline), so the test covers both paths and that they composite in
/// draw order.
private final class MixedPipelines: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.1))
        noStroke()
        fill(Color(red: 0.2, green: 0.6, blue: 0.9))
        drawPolygon([Vector2(40, 40), Vector2(220, 70), Vector2(120, 220)])
        fill(Color(red: 1.0, green: 0.85, blue: 0.2))
        drawStar(width * 0.5, height * 0.46, width * 0.22, width * 0.1, points: 5)
    }
}

/// Three `@Eased` values easing toward the same target (set in `setup`) on
/// different curves, so mid-tween the dots sit at different positions. Exercises
/// the sketch's per-frame auto-advance and that each curve shapes motion its own
/// way. Large flat white field, so edge pixels stay a small fraction.
private final class EasedDots: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    @Eased(duration: 1, curve: .linear)  var a = 0.0
    @Eased(duration: 1, curve: .easeIn)  var b = 0.0
    @Eased(duration: 1, curve: .easeOut) var c = 0.0

    override func setup() { a = 1; b = 1; c = 1 }

    override func draw() {
        background(.white)
        noStroke()
        fill(.black)
        let left = width * 0.18, right = width * 0.82
        for (i, t) in [a, b, c].enumerated() {
            let y = height * (0.3 + Double(i) * 0.2)
            drawCircle(left + (right - left) * t, y, width * 0.06)
        }
    }
}

/// A disk and a region shape (rect) stroked under each `StrokeAlign` — one row
/// per alignment — so the test pins the stroke-band bias on both coverage ramps
/// (`diskCoverage` and `regionCoverage`). Static, so it's deterministic at frame 0.
private final class StrokeAligned: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.white)
        fill(Color(white: 0.6))
        stroke(.black)
        strokeWeight(12)
        let aligns: [StrokeAlign] = [.inside, .center, .outside]
        for (i, align) in aligns.enumerated() {
            strokeAlign(align)
            let y = height * (0.22 + Double(i) * 0.28)
            drawCircle(width * 0.3, y, width * 0.09)
            drawRect(center: Vector2(width * 0.7, y), width: width * 0.18, height: width * 0.18)
        }
    }
}

/// The two three-point shapes that drove the `SDFInstance` widening (the `param2`
/// slot): a general scalene `drawTriangle(a, b, c)` — filled+stroked, then drawn
/// hollow (it honors both) — and a quadratic `drawBezier` stroke, plus a Bézier
/// with collinear control points that exercises the straight-line fallback.
/// Static, so it's deterministic at frame 0.
private final class ThreePointShapes: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.white)
        // Filled + stroked scalene triangle (top-left).
        fill(Color(red: 0.2, green: 0.6, blue: 0.9))
        stroke(.black); strokeWeight(6)
        drawTriangle(Vector2(30, 95), Vector2(115, 35), Vector2(90, 135))
        // Hollow triangle — a constant-width band (top-right).
        noStroke(); fill(Color(red: 0.9, green: 0.4, blue: 0.2))
        hollow(10)
        drawTriangle(Vector2(145, 45), Vector2(228, 75), Vector2(165, 125))
        solid()
        // Quadratic Bézier curve (a smile across the middle).
        stroke(Color(red: 0.1, green: 0.5, blue: 0.2)); strokeWeight(10)
        drawBezier(Vector2(25, 205), Vector2(128, 145), Vector2(231, 205))
        // Collinear control points → the straight-line fallback (bottom).
        stroke(.black); strokeWeight(6)
        drawBezier(Vector2(25, 240), Vector2(128, 240), Vector2(231, 240))
    }
}

/// `drawOrientedBox` — a box placed by its two centerline endpoints plus a
/// thickness. Exercises the region features it inherits: a filled + stroked bar
/// (diagonal), a hollow bar (a constant-width band, top), and an outside-aligned
/// stroke (bottom). Static, so it's deterministic at frame 0.
private final class OrientedBoxes: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.white)
        // Filled + stroked diagonal bar.
        fill(Color(red: 0.2, green: 0.6, blue: 0.9))
        stroke(.black); strokeWeight(6)
        drawOrientedBox(Vector2(40, 60), Vector2(216, 130), thickness: 34)
        // Hollow bar — a constant-width band hugging the outline (top).
        noStroke(); fill(Color(red: 0.9, green: 0.4, blue: 0.2))
        hollow(8)
        drawOrientedBox(Vector2(40, 30), Vector2(216, 30), thickness: 28)
        solid()
        // Outside-aligned stroke — the outline sits fully outside the fill (bottom).
        fill(Color(red: 0.1, green: 0.5, blue: 0.2))
        stroke(.black); strokeWeight(6); strokeAlign(.outside)
        drawOrientedBox(Vector2(50, 210), Vector2(206, 226), thickness: 30)
        strokeAlign(.center)
    }
}

/// `drawOrientedVesica` — a pointed lens placed by its two tip points plus a
/// waist width. Exercises the region features it inherits: a filled + stroked lens
/// (diagonal), a hollow lens (a constant-width band, top), and an outside-aligned
/// stroke (bottom). Static, so it's deterministic at frame 0.
private final class OrientedVesicas: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.white)
        // Filled + stroked diagonal lens.
        fill(Color(red: 0.2, green: 0.6, blue: 0.9))
        stroke(.black); strokeWeight(6)
        drawOrientedVesica(Vector2(40, 70), Vector2(216, 140), width: 70)
        // Hollow lens — a constant-width band hugging the outline (top).
        noStroke(); fill(Color(red: 0.9, green: 0.4, blue: 0.2))
        hollow(8)
        drawOrientedVesica(Vector2(40, 32), Vector2(216, 32), width: 44)
        solid()
        // Outside-aligned stroke — the outline sits fully outside the fill (bottom).
        fill(Color(red: 0.1, green: 0.5, blue: 0.2))
        stroke(.black); strokeWeight(5); strokeAlign(.outside)
        drawOrientedVesica(Vector2(50, 224), Vector2(206, 224), width: 40)
        strokeAlign(.center)
    }
}

/// SDF combinators: composed signed-distance fields via `drawSDF` and the scoped
/// block sugar: smooth union (with per-leaf color melt), smooth subtract, intersect,
/// morph, onion, and the domain ops (mirror / repeat). Static, so it's deterministic
/// at frame 0; large flat fills keep the AA-edge fraction (cross-GPU jitter) low.
private final class SDFCombinatorsScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.12))
        noStroke()

        // Smooth union: two colors melt across the seam.
        drawSDF(SDF.circle(radius: 34).colored(Color(red: 1, green: 0.33, blue: 0.44))
            .smoothUnion(SDF.rect(width: 56, height: 40, cornerRadius: 8)
                .colored(Color(red: 0.23, green: 0.52, blue: 1)).at(x: 34, y: 0), k: 16)
            .at(x: 64, y: 56))

        // Smooth subtract: a bite carved out.
        drawSDF(SDF.rect(width: 64, height: 52, cornerRadius: 10)
            .colored(Color(red: 0.02, green: 0.82, blue: 0.63))
            .smoothSubtract(SDF.circle(radius: 26).at(x: 18, y: 0), k: 10)
            .at(x: 192, y: 56))

        // Intersect: the lens where two disks overlap.
        drawSDF(SDF.circle(radius: 38).colored(Color(red: 1, green: 0.82, blue: 0.4))
            .intersect(SDF.circle(radius: 38).at(x: 34, y: 0))
            .at(x: 56, y: 150))

        // Morph (star ⇄ circle) hollowed into a shell with onion.
        drawSDF(SDF.star(outerRadius: 40, innerRadius: 18, points: 5)
            .colored(Color(red: 0.74, green: 0.70, blue: 1))
            .morph(SDF.circle(radius: 36), amount: 0.45)
            .onion(7)
            .at(x: 150, y: 150))

        // Block sugar + domain mirror: a little cluster reflected into a symmetric form.
        withState {
            translate(214, 150)
            fill(Color(red: 0.95, green: 0.60, blue: 0.20))
            mirrored(x: true) {
                smoothUnion(k: 8) {
                    drawCircle(12, 0, 15)
                    drawCircle(26, -12, 9)
                }
            }
        }

        // Block sugar + domain repeat: one melted cell tiled into a row.
        withState {
            translate(128, 224)
            fill(Color(red: 0.50, green: 0.85, blue: 0.95))
            repeated(spacing: Vector2(56, 0), count: 1) {
                smoothUnion(k: 8) {
                    drawRect(-16, -16, 32, 32, cornerRadius: 8)
                    drawCircle(16, 0, 10)
                }
            }
        }
    }
}

// Gradient paint on a merged SDF field: a linear/radial `fill` or `stroke` paints the
// whole region/outline by field position (the leaf colors bypassed), not per leaf.
private final class SDFCombinatorsGradientScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.08))
        let warm = Ramp([Color(hex: 0xFFF3C4), Color(hex: 0xFF8A3D), Color(hex: 0xD81E5B)])
        let cool = Ramp([Color(hex: 0x2BD9C0), Color(hex: 0x3A86FF), Color(hex: 0x7B2FF7)])

        // Linear fill across a melted blob — one continuous surface across the seams.
        withState {
            translate(72, 74)
            noStroke()
            fill(.linear(from: Vector2(-44, -40), to: Vector2(52, 44), warm))
            drawSDF(SDF.circle(radius: 32)
                .smoothUnion(SDF.rect(width: 56, height: 32, cornerRadius: 8).at(x: 36, y: 4), k: 22)
                .smoothUnion(SDF.circle(radius: 18).at(x: 12, y: 32), k: 22))
        }

        // Radial fill on a mandala: a +x petal repeated around the origin; the ramp rings
        // out evenly through every copy (sampled in field space, not per shape).
        withState {
            translate(186, 74)
            noStroke()
            fill(.radial(center: .zero, radius: 58, cool))
            drawSDF(SDF.ellipse(rx: 26, ry: 9).at(x: 34, y: 0)
                .smoothUnion(SDF.circle(radius: 9).at(x: 46, y: 0), k: 7)
                .repeatedRadially(count: 8))
        }

        // Gradient stroke on a merged outline (no fill).
        withState {
            translate(128, 188)
            noFill()
            stroke(.linear(from: Vector2(-62, 0), to: Vector2(62, 0), warm))
            strokeWeight(4)
            drawSDF(SDF.circle(radius: 20).at(x: -42, y: 0)
                .smoothUnion(SDF.rect(width: 56, height: 12, cornerRadius: 6), k: 12)
                .smoothUnion(SDF.circle(radius: 20).at(x: 42, y: 0), k: 12))
        }
    }
}

// Per-axis sizing of a 2D SDF field: `stretched` (exact elongation, a clean cross) beside
// `scaled(x:y:)` (a non-uniform-scale bound, an ellipse + bead). Pins both new XFORM sels. Static.
private final class SDFCombinatorsStretchScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.08))
        noStroke()
        // Stretch (exact): two elongated circles smooth-union into a clean cross.
        let cross = SDF.circle(radius: 16).stretched(y: 30).colored(Color(hex: 0x4cc9f0))
            .smoothUnion(SDF.circle(radius: 16).stretched(x: 30).colored(Color(hex: 0xff5d8f)), k: 14)
        withState { translate(78, 128); drawSDF(cross) }
        // Non-uniform scale (bound): a circle scaled into an ellipse, smooth-unioned with a bead.
        let ell = SDF.circle(radius: 30).scaled(x: 1.5, y: 0.55).colored(Color(hex: 0xffd166))
            .smoothUnion(SDF.circle(radius: 13).at(x: 44, y: 0).colored(Color(hex: 0x8ac926)), k: 14)
        withState { translate(180, 128); drawSDF(ell) }
    }
}

// Per-axis sizing of a raymarched 3D SDF field: `stretched` (a clean cross of two capsules) beside
// `scaled(x:y:z:)` (a sphere as an ellipsoid bound). Pins both new 3D XFORM sels. Static.
private final class RaymarchedSDF3DStretchScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0d1018))
        camera(.orbiting(target: Vector3(0, 0, 0), radius: 8.5, azimuth: 0.5, elevation: 0.3,
                         fieldOfView: .pi / 4, near: 2, far: 50))
        directionalLight(.white, direction: Vector3(-0.3, -0.8, -0.5), intensity: 1.2, softness: 0.3)
        ambientLight(Color(white: 0.2))
        material(.glossy)
        let cross = SDF3D.sphere(radius: 0.55).stretched(y: 1.0).colored(Color(hex: 0x67c1ff))
            .smoothUnion(SDF3D.sphere(radius: 0.55).stretched(x: 1.0).colored(Color(hex: 0xff7ab0)), k: 0.5)
        withState { translate(-2.4, 0, 0); drawSDF3D(cross) }
        let ellipsoid = SDF3D.sphere(radius: 1.0).scaled(x: 1.5, y: 0.6, z: 1.0).colored(Color(hex: 0xffd166))
        withState { translate(2.4, 0, 0); drawSDF3D(ellipsoid) }
    }
}

/// The raymarched 3D SDF combinators (`drawSDF3D` / `SDF3D`): a fixed metaball of
/// spheres melting together (the smooth-union color blend) with a sphere carved off
/// the top, skewered by a rasterized box that pins the depth compositing (the bar and
/// the marched field occlude each other). Static, so it's deterministic at frame 0.
private final class RaymarchedSDF3DScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0e1116))
        // Fixed camera + near/far bracketing the field (deterministic).
        camera(.orbiting(target: .zero, radius: 5.5, azimuth: 0.6, elevation: 0.4,
                         fieldOfView: .pi / 4, near: 2, far: 12))
        directionalLight(.white, direction: Vector3(-0.6, 0.7, 0.5),
                         intensity: 1.1, softness: 0.3)
        ambientLight(Color(white: 0.18))

        // A rasterized bar interpenetrating the field (pins depth compositing).
        withState {
            material(.glossy)
            fill(Color(hex: 0xf2c14e))
            rotateZ(0.3)
            drawBox(width: 4.4, height: 0.42, depth: 0.42)
        }

        // A merged metaball: spheres melting (the smin color-melt), a sphere carved off.
        material(.jade)
        let blob = SDF3D.sphere(radius: 1.05).colored(Color(hex: 0x39d0ff))
            .smoothUnion(SDF3D.sphere(radius: 0.85).at(x: 1.0, y: 0.4, z: 0.6)
                .colored(Color(hex: 0xff4f97)), k: 0.7)
            .smoothUnion(SDF3D.sphere(radius: 0.6).at(x: -1.1, y: 0.7, z: 0.4)
                .colored(Color(hex: 0xb6ff5a)), k: 0.5)
            .smoothSubtract(SDF3D.sphere(radius: 0.7).at(x: 0.2, y: 1.15, z: 0), k: 0.25)
        drawSDF3D(blob)
    }
}

/// The 3D SDF-combinator scoped block form: bare mesh primitives (`drawSphere`/`drawBox`/
/// `drawCapsule`/`drawCone`) inside `smoothUnion(k:) { }` captured as fields, posed with the
/// transform stack and per-`fill` colored, melted into one sphere-traced surface. Pins the
/// mesh-builder interception and the relative-model decomposition. Static at frame 0.
private final class RaymarchedSDF3DBlockScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x101418))
        camera(.orbiting(target: Vector3(0, 0.2, 0), radius: 6.0, azimuth: 0.5, elevation: 0.25,
                         fieldOfView: .pi / 4, near: 2, far: 14))
        directionalLight(.white, direction: Vector3(-0.5, 0.8, 0.4),
                         intensity: 1.2, softness: 0.3)
        ambientLight(Color(white: 0.18))
        material(.jade)

        smoothUnion(k: 0.35) {
            fill(Color(hex: 0x3ad6c5))
            withState { translate(0, -0.6, 0); drawSphere(radius: 0.95) }   // body
            withState { translate(0, 0.7, 0); drawSphere(radius: 0.62) }    // head
            fill(Color(hex: 0xffb84d))
            withState { translate(-0.9, -0.4, 0); rotateZ(0.6); drawCapsule(radius: 0.16, height: 0.7) }
            withState { translate(0.9, -0.4, 0); rotateZ(-0.6); drawCapsule(radius: 0.16, height: 0.7) }
            fill(Color(hex: 0xff5d73))
            withState { translate(0, 1.5, 0); drawCone(radius: 0.45, height: 0.7) }   // hat
        }
    }
}

/// The 3D SDF-combinator domain operators: a smooth-union cell tiled into a finite lattice
/// by `repeated`, and a wedge folded four-fold by `mirrored(x:z:)`. Pins the point-rewriting
/// XFORM scopes (the limited tiling + the axis-plane fold). Static at frame 0.
private final class RaymarchedSDF3DDomainScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0d1117))
        camera(.orbiting(target: .zero, radius: 7.0, azimuth: 0.5, elevation: 0.5,
                         fieldOfView: .pi / 4, near: 2, far: 16))
        directionalLight(.white, direction: Vector3(-0.5, 0.85, 0.4),
                         intensity: 1.2, softness: 0.3)
        ambientLight(Color(white: 0.16))
        material(.glossy)

        // A unit cell (sphere melted with a box), tiled into a 3×3 lattice.
        let cell = SDF3D.sphere(radius: 0.4).colored(Color(hex: 0x38bdf8))
            .smoothUnion(SDF3D.box(size: 0.4).at(x: 0, y: 0.5, z: 0)
                .colored(Color(hex: 0xf472b6)), k: 0.25)
        drawSDF3D(cell.repeated(spacing: Vector3(1.6, 0, 1.6), count: 1).at(x: 0, y: -0.6, z: 0))

        // One wedge folded four-fold across x and z.
        let wedge = SDF3D.cone(radius: 0.4, height: 0.9).colored(Color(hex: 0xfacc15))
            .at(x: 0.7, y: 0, z: 0.7)
        drawSDF3D(wedge.mirrored(x: true, y: false, z: true).at(x: 0, y: 1.6, z: 0))
    }
}

/// The raymarched 3D SDF self-shadowing: with `castShadows()`, a merged field (a slab and
/// the shapes standing on it) drops soft penumbra shadows onto itself. Pins the self-shadow
/// march and its gating on the caster light. Static at frame 0.
private final class RaymarchedSDF3DShadowScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0c0f14))
        camera(.orbiting(target: Vector3(0, -0.2, 0), radius: 8.0, azimuth: 0.4, elevation: 0.32,
                         fieldOfView: .pi / 4, near: 2, far: 16))
        directionalLight(.white, direction: Vector3(0.7, -0.95, -0.35),
                         intensity: 1.25, softness: 0.2)
        ambientLight(Color(white: 0.13))
        castShadows()
        material(.glossy)

        union {
            fill(Color(hex: 0x6b7280))
            withState { translate(0, -0.95, 0); drawBox(width: 7, height: 0.4, depth: 7) }
            fill(Color(hex: 0x38bdf8))
            withState { translate(-1.7, -0.05, 0.2); drawSphere(radius: 0.7) }
            fill(Color(hex: 0xf472b6))
            withState { translate(0.4, 0.15, -0.6); rotateZ(0.25); drawCapsule(radius: 0.34, height: 1.2) }
            fill(Color(hex: 0xfacc15))
            withState { translate(1.8, -0.05, 0.7); drawCone(radius: 0.6, height: 1.5) }
        }
    }
}

/// The raymarched 3D SDF polar (radial) domain repetition: `repeatedRadially` folds one built
/// wedge into a ring of evenly spaced copies around an axis. A value-type sunburst (a radial
/// capsule spoke folded 14-fold onto a hub) and a block-form flower (a cone petal folded into a
/// ring of 6 around a bud). Pins the polar fold + its bounding-sphere AABB. Static at frame 0.
private final class RaymarchedSDF3DRadialScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0b1020))
        camera(.orbiting(target: Vector3(0, 0.2, 0), radius: 7.5, azimuth: 0.5, elevation: 0.5,
                         fieldOfView: .pi / 4, near: 2, far: 18))
        directionalLight(.white, direction: Vector3(-0.4, 0.9, 0.35),
                         intensity: 1.25, softness: 0.35)
        ambientLight(Color(white: 0.15))
        material(.glossy)

        // Value-type: a radial capsule spoke folded into a 14-spoke sunburst melted onto a hub.
        let spoke = SDF3D.capsule(radius: 0.12, height: 1.25).rotatedZ(.pi / 2)
            .at(x: 0.95, y: 0, z: 0).colored(Color(hex: 0x38bdf8))
        let hub = SDF3D.sphere(radius: 0.55).colored(Color(hex: 0x22d3ee))
        drawSDF3D(spoke.repeatedRadially(count: 14).smoothUnion(hub, k: 0.25)
            .at(x: 0, y: -0.7, z: 0))

        // Block-form: a cone petal folded into a ring of 6 melted with a central bud.
        withState {
            translate(0, 1.4, 0)
            repeatedRadially(count: 6) {
                smoothUnion(k: 0.22) {
                    fill(Color(hex: 0xfacc15))
                    drawSphere(radius: 0.4)
                    fill(Color(hex: 0xf472b6))
                    withState { translate(1.05, 0.1, 0); rotateZ(-0.7); drawCone(radius: 0.28, height: 1.05) }
                }
            }
        }
    }
}

/// The raymarched 3D SDF infinite plane primitive: a floor with no finite bounds (it marches to
/// the camera's far plane, not an AABB) merged with three shapes as one field under
/// `castShadows()`, so the shapes drop soft self-shadows onto it. Pins the plane SDF and the
/// unbounded-march path. Static at frame 0.
private final class RaymarchedSDF3DPlaneScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0a0e16))
        camera(.orbiting(target: Vector3(0, 0.1, 0), radius: 7, azimuth: 0.5, elevation: 0.32,
                         fieldOfView: .pi / 4, near: 2, far: 60))
        directionalLight(.white, direction: Vector3(0.4, -0.92, -0.25),
                         intensity: 1.3, softness: 0.2)
        ambientLight(Color(white: 0.14))
        castShadows()
        material(.glossy)

        let floor = SDF3D.plane(offset: -0.85).colored(Color(hex: 0x5b6472))
        let ball = SDF3D.sphere(radius: 0.7).colored(Color(hex: 0x38bdf8))
            .at(x: -1.5, y: -0.15, z: 0.2)
        let bar = SDF3D.capsule(radius: 0.3, height: 1.0).colored(Color(hex: 0xf472b6))
            .rotatedZ(0.5).at(x: 0.3, y: 0.05, z: -0.7)
        let pin = SDF3D.cone(radius: 0.55, height: 1.6).colored(Color(hex: 0xfacc15))
            .at(x: 1.7, y: -0.05, z: 0.6)
        drawSDF3D(floor.union(ball).union(bar).union(pin))
    }
}

/// The raymarched 3D SDF field casting into the directional shadow map so a rasterized mesh
/// receives it: a mesh floor and mesh sphere alongside a floating field blob, the blob's soft
/// shadow falling on the mesh floor beside the mesh sphere's. Pins the field-into-shadow-map
/// pass (field → mesh). Static at frame 0.
private final class RaymarchedSDF3DCastShadowScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0c0f16))
        camera(.orbiting(target: Vector3(0, 0, 0), radius: 7.5, azimuth: 0.5, elevation: 0.4,
                         fieldOfView: .pi / 4, near: 2, far: 50))
        directionalLight(.white, direction: Vector3(0.35, -0.92, -0.2),
                         intensity: 1.3, softness: 0.2)
        ambientLight(Color(white: 0.16))
        castShadows()
        material(.glossy)

        fill(Color(hex: 0x5b6472))
        withState { translate(0, -1.1, 0); drawBox(width: 9, height: 0.4, depth: 9) }
        fill(Color(hex: 0xf472b6))
        withState { translate(2.1, -0.3, 0); drawSphere(radius: 0.6) }

        let blob = SDF3D.sphere(radius: 0.7)
            .smoothUnion(SDF3D.sphere(radius: 0.5).at(x: 0.85, y: 0.35, z: 0.2), k: 0.45)
            .smoothUnion(SDF3D.sphere(radius: 0.5).at(x: -0.2, y: 0.5, z: -0.4), k: 0.45)
            .colored(Color(hex: 0x38bdf8))
        withState { translate(-1.8, 0.1, 0); drawSDF3D(blob) }
    }
}

/// A raymarched 3D SDF field *receiving* a rasterized mesh's cast shadow: a mesh sphere floats
/// above a wide SDF slab, dropping a round shadow onto the field surface (sampled from the 2D
/// shadow map in the raymarch fragment), beside the slab's own self-shadowed bumps. Static.
private final class RaymarchedSDF3DReceiveShadowScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0c0f16))
        camera(.orbiting(target: Vector3(0, -0.2, 0), radius: 7.0, azimuth: 0.5, elevation: 0.5,
                         fieldOfView: .pi / 4, near: 2, far: 50))
        directionalLight(.white, direction: Vector3(0.3, -0.95, -0.1),
                         intensity: 1.3, softness: 0.2)
        ambientLight(Color(white: 0.16))
        castShadows()
        material(.glossy)

        let slab = SDF3D.roundBox(width: 5.0, height: 0.6, depth: 4.0, radius: 0.25)
            .smoothUnion(SDF3D.sphere(radius: 0.7).at(x: -1.3, y: 0.4, z: 0.6), k: 0.5)
            .smoothUnion(SDF3D.sphere(radius: 0.55).at(x: 1.4, y: 0.35, z: -0.7), k: 0.5)
            .colored(Color(hex: 0x6aa9ff))
        withState { translate(0, -1.0, 0); drawSDF3D(slab) }

        fill(Color(hex: 0xf472b6))
        withState { translate(0.5, 1.15, 0.4); drawSphere(radius: 0.65) }
    }
}

/// A raymarched 3D SDF field casting a shadow onto a rasterized mesh under a *point* light: the lit
/// mesh fragments march the field inline toward the bulb (no 2D map for a point caster). A floating
/// blob and a mesh sphere drop shadows onto the floor; the field's should match the mesh's. Static.
private final class RaymarchedSDF3DPointCastScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0A0B10))
        camera(.orbiting(target: Vector3(0, 0.8, 0), radius: 11, azimuth: 0.6, elevation: 0.5,
                         fieldOfView: .pi / 4.6, near: 2, far: 50))
        ambientLight(Color(white: 0.1))
        pointLight(.white, at: Vector3(0, 5.5, 0), intensity: 1.8, specular: .white)
        castShadows()
        material(.glossy)

        withState { fill(Color(white: 0.8)); specular(0.05); translate(0, -0.5, 0); drawPlane(width: 24, depth: 24) }
        withState { fill(Color(hex: 0xf472b6)); translate(2.2, 1.4, 0); drawSphere(radius: 0.8) }

        let blob = SDF3D.sphere(radius: 0.8)
            .smoothUnion(SDF3D.sphere(radius: 0.6).at(x: 0.9, y: 0.3, z: 0.2), k: 0.5)
            .smoothUnion(SDF3D.sphere(radius: 0.55).at(x: -0.3, y: 0.5, z: -0.4), k: 0.5)
            .colored(Color(hex: 0x38bdf8))
        withState { translate(-2.0, 1.5, 0); drawSDF3D(blob) }
    }
}

/// A raymarched 3D SDF field *receiving* a rasterized mesh's cast shadow under a *point* light: the
/// field samples the omnidirectional cube (or, on an RT GPU, traces the mesh structure) toward the
/// bulb, the reverse of casting. A mesh sphere drops a round shadow onto a wide SDF slab, beside the
/// slab's own self-shadowed bumps. Static.
private final class RaymarchedSDF3DPointReceiveScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0b0d14))
        camera(.orbiting(target: Vector3(0, -0.2, 0), radius: 7.0, azimuth: 0.5, elevation: 0.5,
                         fieldOfView: .pi / 4, near: 2, far: 50))
        pointLight(.white, at: Vector3(0, 4.5, 0.5), intensity: 2.0, specular: .white)
        ambientLight(Color(white: 0.16))
        castShadows()
        material(.glossy)

        let slab = SDF3D.roundBox(width: 5.0, height: 0.6, depth: 4.0, radius: 0.25)
            .smoothUnion(SDF3D.sphere(radius: 0.7).at(x: -1.3, y: 0.4, z: 0.6), k: 0.5)
            .smoothUnion(SDF3D.sphere(radius: 0.55).at(x: 1.4, y: 0.35, z: -0.7), k: 0.5)
            .colored(Color(hex: 0x6aa9ff))
        withState { translate(0, -1.0, 0); drawSDF3D(slab) }

        fill(Color(hex: 0xf472b6))
        withState { translate(0.4, 1.0, 0.4); drawSphere(radius: 0.65) }
    }
}

/// Gradient paint on a merged raymarched 3D SDF field: a vertical screen-space gradient painting
/// the whole sphere-traced blob by each hit's projected screen position (rather than a solid
/// color per leaf). Pins the gradient-resolve path on the raymarch fragment. Static at frame 0.
private final class RaymarchedSDF3DGradientScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0b1020))
        camera(.orbiting(target: Vector3(0, 0, 0), radius: 6, azimuth: 0.5, elevation: 0.25,
                         fieldOfView: .pi / 4, near: 2, far: 16))
        directionalLight(.white, direction: Vector3(-0.3, -0.85, -0.45),
                         intensity: 1.2, softness: 0.35)
        ambientLight(Color(white: 0.22))
        material(.glossy)

        fill(.linear(from: Vector2(0, height * 0.18), to: Vector2(0, height * 0.82),
                     [Color(hex: 0xfb923c), Color(hex: 0xec4899), Color(hex: 0x6366f1)]))
        let blob = SDF3D.sphere(radius: 1.05)
            .smoothUnion(SDF3D.sphere(radius: 0.7).at(x: 1.3, y: 0.4, z: 0), k: 0.55)
            .smoothUnion(SDF3D.sphere(radius: 0.7).at(x: -1.1, y: 0.55, z: 0.3), k: 0.55)
            .smoothUnion(SDF3D.sphere(radius: 0.6).at(x: 0.1, y: -1.15, z: 0), k: 0.55)
        drawSDF3D(blob)
    }
}

/// The `Path` builder and `drawCurve` (sample-to-points curved contours): a
/// closed, filled blob whose outline is a smooth Catmull-Rom `curve` run; an open
/// outline built from an explicit `quadCurve` + `cubicCurve`; and an open
/// `drawCurve` wiggle straight from points. Static, so it's deterministic at
/// frame 0.
private final class CurvedPaths: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.white)
        // Closed filled blob through points (curve = Catmull-Rom) + stroked outline.
        fill(Color(red: 0.2, green: 0.6, blue: 0.9)); stroke(.black); strokeWeight(4)
        drawShape { p in
            p.move(to: Vector2(55, 45))
            p.curve(to: Vector2(150, 55))
            p.curve(to: Vector2(165, 120))
            p.curve(to: Vector2(85, 110))
            p.close()
        }
        // Open outline from an explicit quadratic + cubic Bézier, stroke-only.
        noFill(); stroke(Color(red: 0.9, green: 0.3, blue: 0.2)); strokeWeight(6)
        drawShape { p in
            p.move(to: Vector2(28, 158))
            p.quadCurve(to: Vector2(128, 150), control: Vector2(78, 100))
            p.cubicCurve(to: Vector2(230, 165), control1: Vector2(168, 120), control2: Vector2(188, 205))
        }
        // A smooth open wiggle straight from a list of points.
        stroke(.black); strokeWeight(4)
        drawCurve([Vector2(25, 228), Vector2(80, 200), Vector2(130, 236),
                   Vector2(180, 200), Vector2(232, 230)])
    }
}

/// Each `strokeJoin` on a sharp chevron (top three) and each `strokeCap` on an
/// open segment (bottom three), so the corner and end geometry are exercised on
/// the tessellated stroke path. Static, so it's deterministic at frame 0.
private final class StrokeJoinsCaps: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.white)
        stroke(.black); strokeWeight(22)

        let joins: [StrokeJoin] = [.miter, .bevel, .round]
        for (i, join) in joins.enumerated() {
            let cy = 32.0 + Double(i) * 36
            strokeJoin(join)
            drawPolyline([Vector2(40, cy + 14), Vector2(128, cy - 14), Vector2(216, cy + 14)])
        }

        let caps: [StrokeCap] = [.butt, .round, .square]
        strokeJoin(.miter)
        for (i, cap) in caps.enumerated() {
            let cy = 160.0 + Double(i) * 32
            strokeCap(cap)
            drawPolyline([Vector2(70, cy), Vector2(186, cy)])
        }
    }
}

/// The bitmap-font `drawText` with the bundled Cozette font: capitals, lowercase,
/// digits, the Spanish set (accented vowels, ñ/ü, inverted punctuation), Japanese
/// kana (hiragana + katakana), descenders (`g j p q y`), the alignments, and a
/// rotated line that exercises text on the transform stack. Black on white, static.
private final class TextSpecimen: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.white)
        fill(.black)
        textFont(BitmapFont.builtin)   // the fixture is about Cozette, not the default font
        textAlign(.left, .top)
        textSize(24)
        drawText("¡Hola! Ñ", 14, 12)
        textSize(22)
        drawText("ABCxyz 0123", 14, 42)
        drawText("áéíóú ñ ü ¿?", 14, 70)
        textSize(20)
        drawText("こんにちは", 14, 98)        // hiragana
        drawText("ハロー gjpqy", 14, 126)      // katakana + descenders
        // Centered + rotated, through the transform stack.
        textAlign(.center, .middle)
        drawText("centered", width / 2, 172)
        withState {
            translate(width / 2, 212)
            rotate(0.16)
            drawText("rotated", 0, 0)
        }
    }
}

/// An image authored from scratch (`Image(width:height:)` + pixel `set`), drawn
/// once untinted and once under `tint(_:)`, with a row of `get`-sampled swatches
/// below. Pins the whole image-extras path: the texture upload from edited pixels,
/// the tint multiply, top-left pixel orientation (the black corner marker), and
/// that `get` reads the authored colors regardless of tint. Static at frame 0.
private final class TintedImage: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    var img: Image?

    override func setup() {
        let n = 16
        let image = Image(width: n, height: n)
        for y in 0..<n {
            for x in 0..<n {
                image[x, y] = (x + y) % 2 == 0
                    ? Color(red: 0.9, green: 0.35, blue: 0.2)
                    : Color(red: 0.2, green: 0.45, blue: 0.9)
            }
        }
        image[0, 0] = .black   // top-left marker — must land at the drawn top-left
        img = image
    }

    override func draw() {
        background(.white)
        guard let img else { return }
        noTint()
        drawImage(img, 18, 18, 100, 100)
        tint(Color(red: 1, green: 0.7, blue: 0.3, alpha: 0.85))
        drawImage(img, 138, 18, 100, 100)
        // get-sampled swatches of the top row, in true (untinted) color.
        noTint()
        noStroke()
        for i in 0..<8 {
            fill(img[i * 2, 0])
            drawRect(18 + Double(i) * 28, 150, 24, 80)
        }
    }
}

/// Gradient paint across both pipelines: linear and radial SDF fills, a conic
/// (along-path) stroke sweeping a circle outline, a per-vertex linear fill on a
/// tessellated polygon, and along-path ramps on a line capsule and a Bézier.
/// Gradients are smooth fields, so the mean-difference metric stays tight.
private final class GradientShapes: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.1))
        noStroke()
        // Linear fill on the SDF box path.
        fill(.linear(from: Vector2(20, 20), to: Vector2(236, 20),
                     [Color(hex: 0xFF8A3D), Color(hex: 0x2BB3A3)]))
        drawRect(20, 20, 216, 60)
        // Radial fill plus a conic (along-path) stroke on the same circle.
        fill(.radial(center: Vector2(70, 160), radius: 40,
                     [.white, Color(hex: 0xD03060)]))
        stroke(.alongPath([Color(hex: 0xFFF3C4), Color(hex: 0x3C6DD0)]))
        strokeWeight(6)
        drawCircle(70, 160, 40)
        noStroke()
        // Per-vertex linear fill on the tessellated path.
        fill(.linear(from: Vector2(130, 120), to: Vector2(230, 210),
                     [Color(hex: 0x0B1A40), Color(hex: 0xFFB36B)]))
        drawPolygon([Vector2(180, 120), Vector2(230, 210), Vector2(130, 210)])
        // Along-path ramps on a line capsule and a quadratic Bézier.
        stroke(.alongPath([Color(hex: 0xFFF3C4), Color(hex: 0xD03060)]))
        strokeWeight(8)
        drawLine(Vector2(20, 234), Vector2(236, 234))
        drawBezier(Vector2(20, 108), Vector2(128, 86), Vector2(118, 108))
        noStroke()
    }
}

/// The standard notices and caption helpers, plus a closed polyline: an `.info`
/// status filling the canvas, a `.warning` status scoped to a sub-rectangle,
/// captions on both edges, and `drawPolyline(closed:)` joining its seam. Pins
/// the helpers' look and that they leave the drawing state untouched (the
/// rectangle after them still draws with the sketch's own fill).
private final class StatusNotices: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.06))
        drawStatus("Waiting for camera…")
        drawStatus("Model unavailable", style: .warning,
                   in: Rectangle(x: 0, y: 150, width: width, height: 90))
        drawCaption("StatusNotices — a caption")
        drawCaption("top caption", edge: .top)
        // State untouched by the helpers: this still draws white, stroke-free.
        fill(.white)
        noStroke()
        drawRect(10, 118, 20, 20)
        // A closed polyline turns its seam with the join (vs. an open V).
        stroke(.white)
        strokeWeight(6)
        drawPolyline([Vector2(200, 110), Vector2(236, 140), Vector2(200, 140)], closed: true)
    }
}

/// Three translucent primary-color disks on black, drawn with `blendMode(.add)`
/// so they sum as light: each pair overlaps in a secondary and all three meet in
/// a white core. Pins the additive blend factors (and that `.add` rides the SDF
/// path). Deterministic — no time dependence.
private final class AdditiveBlend: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.black)
        blendMode(.add)
        noStroke()
        let r = width * 0.3
        let cx = width * 0.5, cy = height * 0.52, off = width * 0.17
        fill(Color(red: 1, green: 0, blue: 0, alpha: 0.85))
        drawCircle(cx, cy - off, r)
        fill(Color(red: 0, green: 1, blue: 0, alpha: 0.85))
        drawCircle(cx - off * 0.92, cy + off * 0.6, r)
        fill(Color(red: 0, green: 0, blue: 1, alpha: 0.85))
        drawCircle(cx + off * 0.92, cy + off * 0.6, r)
    }
}

/// A persistent (`noClear`) canvas: each frame scatters a seeded ring of faint
/// additive dots that rotates slowly, so by the captured frame the canvas holds
/// the accumulated, overlapping trails — not a single frame's sparse scatter.
/// Pins the accumulation surface (don't-clear + the persistent-target read-back),
/// and that it builds up across frames. Deterministic via the seed + fixed timestep.
private final class AccumulationField: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private var seeds: [(angle: Double, radius: Double)] = []

    override func setup() {
        seed(3)
        background(Color(white: 0.02))     // the one base wipe; then accumulate
        noClear()
        for _ in 0 ..< 200 {
            seeds.append((random(.tau), random(40, 110)))
        }
    }

    override func draw() {
        blendMode(.add)
        noStroke()
        fill(Color(red: 0.5, green: 0.72, blue: 1, alpha: 0.12))
        let cx = width / 2, cy = height / 2
        let spin = time * 0.6
        for s in seeds {
            let a = s.angle + spin
            drawCircle(cx + cos(a) * s.radius, cy + sin(a) * s.radius, 2.2)
        }
    }
}

/// Bright additive disks overlapping past full brightness, mapped down by ACES.
/// The center stacks three saturated colors into a high-dynamic-range core that a
/// clamp would flatten to white; this pins that the linear-float frame is
/// tone-mapped in the present pass (not clipped). Deterministic (no time/random).
private final class ToneMappedBloom: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x05060A))
        toneMap(.aces, exposure: 1.6)
        blendMode(.add)
        noStroke()
        let r = width * 0.32
        let cx = width * 0.5, cy = height * 0.5, off = width * 0.14
        fill(Color(red: 1, green: 0.2, blue: 0.1, alpha: 0.95))
        drawCircle(cx, cy - off, r)
        fill(Color(red: 0.1, green: 1, blue: 0.3, alpha: 0.95))
        drawCircle(cx - off, cy + off * 0.7, r)
        fill(Color(red: 0.2, green: 0.4, blue: 1, alpha: 0.95))
        drawCircle(cx + off, cy + off * 0.7, r)
    }
}

/// Layered effects: a blurred soft rectangle behind a row of bloomed disks, each
/// drawn into its own off-screen `renderTarget` and filtered on the GPU before
/// compositing. Deterministic (no time/random), so it pins the effects pipeline —
/// target render passes, the Gaussian-blur and bloom filters, and the
/// texture-backed-`Image` composite.
private final class EffectsLayers: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.04))

        // A blurred soft band (target → gaussianBlur → composite).
        let soft = renderTarget()
        withTarget(soft) {
            background(.clear)
            noStroke()
            fill(Color(red: 0.2, green: 0.5, blue: 1))
            drawRect(width * 0.18, height * 0.24, width * 0.64, height * 0.26)
        }
        drawImage(soft.filtered(.gaussianBlur(radius: 12)).image, 0, 0)

        // A row of bright disks that bloom (target → bloom → additive composite).
        let marks = renderTarget()
        withTarget(marks) {
            background(.clear)
            noStroke()
            fill(.white)
            drawCircle(width * 0.5, height * 0.68, 22)
            fill(Color(red: 1, green: 0.4, blue: 0.1))
            drawCircle(width * 0.30, height * 0.68, 15)
            fill(Color(red: 0.3, green: 1, blue: 0.5))
            drawCircle(width * 0.70, height * 0.68, 15)
        }
        blendMode(.add)
        drawImage(marks.filtered(.bloom(threshold: 0.4, intensity: 1.6, radius: 14)).image, 0, 0)
    }
}

private final class EffectsCatalog: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.05))

        // One fixed scene drawn into a layer, shown through three filters; the
        // fourth tile is a procedural generator (no input).
        let scene = renderTarget()
        withTarget(scene) {
            background(Color(hex: 0x14233B))
            noStroke()
            fill(Color(red: 1, green: 0.3, blue: 0.2)); drawCircle(width * 0.38, height * 0.42, 70)
            fill(Color(red: 0.2, green: 0.8, blue: 1)); drawCircle(width * 0.62, height * 0.58, 70)
            fill(.white); drawCircle(width * 0.5, height * 0.3, 26)
        }
        drawImage(scene.filtered(.posterize(levels: 4)).image, in: Rectangle(x: 0, y: 0, width: 128, height: 128))
        drawImage(scene.filtered(.gradientMap(.turbo)).image, in: Rectangle(x: 128, y: 0, width: 128, height: 128))
        drawImage(scene.filtered(.edges(intensity: 2)).image, in: Rectangle(x: 0, y: 128, width: 128, height: 128))
        drawImage(generate(.checkers(scale: 6)).image, in: Rectangle(x: 128, y: 128, width: 128, height: 128))
    }
}

/// A representative sample of the extended filter catalog — one tile per family,
/// covering a color/tone pass (vibrance), a multi-tap stylize gather (oilPaint), a
/// neighbourhood pass (emboss), a print screen (cmykHalftone), a uv warp
/// (kaleidoscope), and a retro pass (scanlines). Deterministic (no time/random), so
/// it pins the added `applyFilter` dispatch and the new `ollin_fx_*` fragments.
private final class EffectsFilters: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.05))
        let scene = renderTarget()
        withTarget(scene) {
            background(Color(hex: 0x14233B))
            noStroke()
            fill(Color(red: 1, green: 0.3, blue: 0.2)); drawCircle(width * 0.36, height * 0.40, 64)
            fill(Color(red: 0.2, green: 0.8, blue: 1)); drawRect(width * 0.5, height * 0.5, 90, 78)
            fill(.white); drawCircle(width * 0.5, height * 0.3, 22)
        }
        let filters: [Filter] = [
            .vibrance(amount: 0.9), .oilPaint(radius: 4), .emboss(amount: 2),
            .cmykHalftone(scale: 22), .kaleidoscope(segments: 6), .scanlines(count: 64),
        ]
        // 3×2 grid of 85×128 tiles.
        for (i, filter) in filters.enumerated() {
            let x = Double(i % 3) * 85, y = Double(i / 3) * 128
            drawImage(scene.filtered(filter).image, in: Rectangle(x: x, y: y, width: 85, height: 128))
        }
    }
}

/// A reaction-diffusion `SimField` seeded with a fixed dot grid (no random/time), run
/// to frame 60. Pins the stateful sim substrate: the persistent ping-pong carried
/// across frames, the seed-inject pass, and the multi-substep Gray-Scott stepping —
/// the same path Game of Life rides with a different step fragment.
private final class EffectsSimField: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    var rd: SimField!
    var seeded = false

    override func setup() { rd = simField(.reactionDiffusion(), scale: 0.5) }

    override func draw() {
        withField(rd) {
            if !seeded {
                noStroke(); fill(.white)
                for i in 0 ..< 6 {
                    for j in 0 ..< 6 {
                        drawCircle((Double(i) + 0.5) * width / 6, (Double(j) + 0.5) * height / 6, 5)
                    }
                }
                seeded = true
            }
        }
        drawImage(rd.filtered(.gradientMap(.magma)).image, 0, 0)
    }
}

/// A fluid `SimField` driven by a fixed brush path (no random/mouse/time spikes), run to
/// frame 48. Pins the multi-field fluid pipeline: the velocity + dye splat, curl and
/// vorticity confinement, the Jacobi pressure projection, semi-Lagrangian advection, and
/// the persistent velocity + dye ping-pong carried across frames.
private final class EffectsFluid: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    var fluid: SimField!
    var prev = Vector2.zero

    override func setup() {
        fluid = simField(.fluid(curl: 30), scale: 0.5)
        prev = Vector2(width / 2, height / 2)   // start at centre = the path's t = 0 (no jump)
    }

    override func draw() {
        let t = time * 2
        let brush = Vector2(width  * (0.5 + 0.30 * sin(t)),
                            height * (0.5 + 0.30 * sin(t * 1.3)))
        let force = brush - prev
        prev = brush
        withField(fluid, force: force) {
            noStroke(); fill(Color(hue: time * 0.1, saturation: 0.9, brightness: 1))
            drawCircle(brush.x, brush.y, 8)
        }
        drawImage(fluid.image, 0, 0)
    }
}

private final class EffectsFeedback: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    var trail: Feedback!

    override func setup() { trail = feedback() }

    override func draw() {
        background(.black)
        withFeedback(trail) { prev in
            withState {
                translate(width / 2, height / 2)
                rotate(0.12)
                scale(0.95)
                translate(-width / 2, -height / 2)
                tint(Color(white: 1, alpha: 0.9))
                drawImage(prev, 0, 0)
            }
            noStroke()
            let x = width * 0.5 + sin(time * 2.0) * width * 0.3
            let y = height * 0.5 + cos(time * 2.6) * height * 0.3
            fill(Color(red: 1, green: 0.5, blue: 0.1))
            drawCircle(x, y, 12)
        }
        drawImage(trail.image, 0, 0)
    }
}

/// The layered-effects `compose { }` DSL: a blurred half-resolution band beneath a
/// row of bloomed disks added as light, declared as one block. Deterministic (no
/// time/random), so it pins the DSL orchestration: per-layer `.scale`, `.post`
/// filters, the per-layer `.blend`, and the declared composite order.
private final class EffectsCompose: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.04))
        compose {
            layer {
                noStroke()
                fill(Color(red: 0.2, green: 0.5, blue: 1))
                drawRect(width * 0.18, height * 0.24, width * 0.64, height * 0.26)
            }
            .post(.gaussianBlur(radius: 12))
            .scale(0.5)

            layer {
                noStroke()
                fill(.white); drawCircle(width * 0.5, height * 0.68, 22)
                fill(Color(red: 1, green: 0.4, blue: 0.1)); drawCircle(width * 0.30, height * 0.68, 15)
                fill(Color(red: 0.3, green: 1, blue: 0.5)); drawCircle(width * 0.70, height * 0.68, 15)
            }
            .post(.bloom(threshold: 0.4, intensity: 1.6, radius: 14))
            .blend(.add)
        }
    }
}

/// Multi-input combine ops over the substrate: four tiles, each combining the same
/// fixed scene with an aux layer. Deterministic (no time/random), so it pins the
/// two-input path and each combine shader (mask by luminance, displace by a bump,
/// mix toward a generator, mask by alpha inverted).
private final class EffectsCombine: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    private func scene() -> RenderTarget {
        let t = renderTarget()
        withTarget(t) {
            background(Color(hex: 0x14233B))
            noStroke()
            fill(Color(red: 1, green: 0.3, blue: 0.2)); drawCircle(width * 0.38, height * 0.42, 70)
            fill(Color(red: 0.2, green: 0.8, blue: 1)); drawCircle(width * 0.62, height * 0.58, 70)
            fill(.white); drawCircle(width * 0.5, height * 0.3, 26)
        }
        return t
    }

    override func draw() {
        background(Color(white: 0.05))

        // mask (luminance): the scene seen through a soft white disc.
        let mask = renderTarget()
        withTarget(mask) { background(.clear); noStroke(); fill(.white); drawCircle(width * 0.5, height * 0.5, 90) }
        drawImage(scene().combined(with: mask.filtered(.gaussianBlur(radius: 8)), .mask()).image,
                  in: Rectangle(x: 0, y: 0, width: 128, height: 128))

        // displace: the scene pushed around by a blurred off-centre bump on mid-gray.
        let dmap = renderTarget()
        withTarget(dmap) { background(Color(white: 0.5)); noStroke(); fill(.white); drawCircle(width * 0.65, height * 0.35, 80) }
        drawImage(scene().combined(with: dmap.filtered(.gaussianBlur(radius: 20)), .displace(amount: 0.08)).image,
                  in: Rectangle(x: 128, y: 0, width: 128, height: 128))

        // mix: cross-dissolve the scene halfway toward a checker generator.
        drawImage(scene().combined(with: generate(.checkers(scale: 6)), .mix(amount: 0.5)).image,
                  in: Rectangle(x: 0, y: 128, width: 128, height: 128))

        // mask (alpha, inverted): hide the scene under an opaque disc, show it around.
        let amask = renderTarget()
        withTarget(amask) { background(.clear); noStroke(); fill(.white); drawCircle(width * 0.5, height * 0.5, 70) }
        drawImage(scene().combined(with: amask, .mask(channel: .alpha, invert: true)).image,
                  in: Rectangle(x: 128, y: 128, width: 128, height: 128))
    }
}

/// The `aside` compose sugar: one layer masked by an aside (a blurred disc fed to a
/// luminance mask). Deterministic, so it pins the DSL aside path — the aside drawn
/// to its own layer, run through its post, fed to the combine, and never composited.
private final class EffectsComposeAside: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.04))
        compose {
            layer {
                background(Color(hex: 0x14233B))
                noStroke()
                fill(Color(red: 1, green: 0.3, blue: 0.2)); drawCircle(width * 0.40, height * 0.44, 64)
                fill(Color(red: 0.2, green: 0.8, blue: 1)); drawCircle(width * 0.60, height * 0.56, 64)
            }
            .masked(by: aside {
                noStroke(); fill(.white); drawCircle(width * 0.5, height * 0.5, 86)
            }.post(.gaussianBlur(radius: 10)))
        }
    }
}

/// Depth of field over *overlapping* discs at near / mid / far depths with a hard-edged
/// depth map (matching discs on a far background), focused on the middle disc. Pins the
/// gather's hard cases: the mid disc stays crisp, the near and far ones blur into clean
/// bokeh, and where the defocused discs overlap they blend (no hard occlusion cut of the
/// farther along the nearer's silhouette). Deterministic (a fixed golden-angle gather).
private final class EffectsDefocus: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.05))
        // Drawn far → near (blue, green, red) so the nearer discs occlude, in both the
        // colour scene and the matching depth map.
        let far   = (x: 0.60, gray: 0.82, color: Color(red: 0.3, green: 0.6, blue: 1))
        let mid   = (x: 0.50, gray: 0.50, color: Color(red: 0.3, green: 1, blue: 0.5))
        let near  = (x: 0.40, gray: 0.18, color: Color(red: 1, green: 0.35, blue: 0.2))
        let discs = [far, mid, near]

        let scene = renderTarget()
        withTarget(scene) {
            background(Color(white: 0.05)); noStroke()
            for d in discs { fill(d.color); drawCircle(width * d.x, height * 0.5, 58) }
        }
        let depth = renderTarget()
        withTarget(depth) {
            background(.white); noStroke()   // gaps read as far
            for d in discs { fill(Color(white: d.gray)); drawCircle(width * d.x, height * 0.5, 58) }
        }
        drawImage(scene.combined(with: depth, .defocus(focus: 0.5, range: 0.08, maxBlur: 22)).image, 0, 0)
    }
}

/// A Lorenz attractor, RK4-integrated and splatted through a fixed camera. Pins
/// the attractor math, the per-point speed coloring, and the additive point
/// cloud. No `time`/random, so it's deterministic at any frame.
private final class StrangeAttractorScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x04050A))
        blendMode(.add)
        camera(.orbiting(target: .zero, radius: 5.2, azimuth: 0.7,
                         elevation: 0.32, fieldOfView: .pi / 3.4))

        let attractor = StrangeAttractor.lorenz()
        let raw = attractor.orbit(count: 40_000, settle: 2000)
        var lo = raw[0], hi = raw[0]
        for p in raw {
            lo = Vector3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z))
            hi = Vector3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
        }
        let center = (lo + hi) * 0.5
        let fit = 4.6 / max(hi.x - lo.x, max(hi.y - lo.y, hi.z - lo.z))
        let speeds = raw.map { attractor.derivative($0).length }
        let slow = speeds.min() ?? 0, spread = max((speeds.max() ?? 1) - (speeds.min() ?? 0), 1e-6)

        var cloud = PointCloud()
        for (i, p) in raw.enumerated() {
            let c = p - center
            let t = (speeds[i] - slow) / spread
            cloud.add(Vector3(c.x, c.z, c.y) * fit,
                      color: Color(hue: 0.62 - t * 0.62, saturation: 0.85, brightness: 0.45 + t * 0.55),
                      size: 0.02)
        }
        drawPointCloud(cloud)
    }
}

/// A Clifford map accumulated additively over several frames. Pins the iterated
/// map and the `noClear` density build-up. Carries the orbit across frames, so
/// the test renders it at a fixed `frame`.
private final class CliffordAttractorScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private let map = ChaoticMap.clifford()
    private let perFrame = 30_000
    private var current = Vector2(0.1, 0.1)

    override func setup() { noClear(); noStroke() }

    override func draw() {
        if frameCount == 1 { background(.black) }
        let reach = Double(min(width, height)) * 0.22
        let cx = width / 2, cy = height / 2
        var points = [Vector2]()
        points.reserveCapacity(perFrame)
        for _ in 0..<perFrame {
            current = map.next(current)
            points.append(Vector2(cx + current.x * reach, cy + current.y * reach))
        }
        blendMode(.add)
        fill(Color(red: 0.42, green: 0.74, blue: 1.0, alpha: 0.06))
        pointSize(1.0)
        drawPoints(points)
    }
}
