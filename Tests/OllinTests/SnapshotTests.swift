import CoreGraphics
import Foundation
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
    SnapshotCase("visual-chain", frame: 30,
                 note: "A fluent Visual chain across all five op families, reading one layer.",
                 make: { VisualChainScene() }),
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
    SnapshotCase("sdf-combinators-joinery", note: "2D chamfer and stairs joint ops.",
                 make: { SDFCombinatorsJoineryScene() }),
    SnapshotCase("sdf-combinators-detailing", note: "2D columns/pipe/engrave/groove/tongue ops.",
                 make: { SDFCombinatorsDetailingScene() }),
    SnapshotCase("sdf-combinators-sculpt", note: "The 2D sculpt block (per-child mode/melt).",
                 make: { SDFCombinatorsSculptScene() }),
    SnapshotCase("sdf-combinators-3d-sculpt", note: "The raymarched sculpt block.",
                 make: { RaymarchedSDF3DSculptScene() }),
    SnapshotCase("sdf-combinators-3d-detailing", note: "Raymarched columns + detailing ops.",
                 make: { RaymarchedSDF3DDetailingScene() }),
    SnapshotCase("sdf-combinators-3d-joinery", note: "Raymarched joint ops + hardware leaves.",
                 make: { RaymarchedSDF3DJoineryScene() }),
    SnapshotCase("sdf-combinators-3d-distort", note: "Raymarched twist/bend/displacement.",
                 make: { RaymarchedSDF3DDistortScene() }),
    SnapshotCase("sdf-combinators-3d-receive", note: "A raymarched 3D field receiving a mesh shadow.",
                 make: { RaymarchedSDF3DReceiveShadowScene() }),
    SnapshotCase("sdf-combinators-3d-pointcast", note: "A raymarched 3D field casting under a point light.",
                 make: { RaymarchedSDF3DPointCastScene() }),
    SnapshotCase("sdf-combinators-stretch", note: "2D SDF combinator per-axis stretch.",
                 make: { SDFCombinatorsStretchScene() }),
    SnapshotCase("sdf-combinators-3d-stretch", note: "Raymarched 3D SDF per-axis stretch.",
                 make: { RaymarchedSDF3DStretchScene() }),
    SnapshotCase("sdf-combinators-3d-environment",
                 note: "Raymarched fields lit by an environment beside mesh parity spheres: pins the field IBL ambient (split-sum on a physically-based field, diffuse irradiance on a matte one) and material(_:) reaching the field batch. Fixed camera + bundled HDRI, no time.",
                 make: { RaymarchedSDF3DEnvironmentScene() }),
    SnapshotCase("curved-paths", note: "Curved Path fills and strokes.",
                 make: { CurvedPaths() }),
    SnapshotCase("stroke-joins-caps", note: "strokeJoin / strokeCap on the fringe stroke path.",
                 make: { StrokeJoinsCaps() }),
    SnapshotCase("stroke-profiles", note: "strokeProfile width profiles on the fringe stroke path.",
                 make: { StrokeProfilesScene() }),
    SnapshotCase("brushes", note: "strokeBrush stamps: tips, spacing, jitter, scatter, and a taper.",
                 make: { BrushesScene() }),
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
    SnapshotCase("effects-relight",
                 note: "The relight height-map material pass (metal), the two-tone ordered dither, and the off-center swirl and ripple warps at fixed parameters. Pins the new fragments and dispatches, and the center plumbing on the radial warps.",
                 make: { EffectsRelight() }),
    SnapshotCase("effects-glitter",
                 note: "The iridescence + glitter filters over a fixed heart + star at fixed shift/phase. Pins the thin-film interference color over the domain-warped fbm thickness field, the two hash-cell sparkle layers (dust + cross flares) with their alpha gating, and both dispatches.",
                 make: { EffectsGlitter() }),
    SnapshotCase("mesh-gradient",
                 note: "The mesh-gradient generator at a fixed phase. Pins the inverse-distance-weighted blob blend (power 3.5), the two-pass domain warp + vortex swirl, the sRGB-space palette blending, and the grain overlay + boundary jitter.",
                 make: { MeshGradientPattern() }),
    SnapshotCase("design-filters",
                 note: "The six design filters at fixed phases (no time, no random): liquidMetal, heatmap, and gemSmoke over a drawn heart (pinning the alpha-mask extract + Gaussian interior/halo field passes), and flutedGlass, water, and paperTexture over a fixed mesh-gradient backdrop. Pins each dispatch arm, the multi-pass field prep, and the sRGB palette walks.",
                 make: { DesignFiltersSheet() }),
    SnapshotCase("design-patterns",
                 note: "The nine other design-pattern generators tiled 3×3 at fixed phases (no time, no random): filaments, smokeRing, colorPanels, spiral, waves, dotOrbit, grainGradient, pulsingBorder, godRays. Pins each generator dispatch arm and fragment, incl. the polar-seam blends, the pane projection + scheduling, and the dual over/additive bloom accumulations.",
                 make: { DesignPatternsSheet() }),
    SnapshotCase("pattern-fields",
                 note: "The five pattern-field generators (quasicrystal, moire, gyroid, phyllotaxis, hexPulse) tiled at fixed phases (no time, no random), each generated at its tile's own size. Pins each dispatch arm and fragment (the plane-wave sum, ring interference, gyroid slice, Vogel nearest-floret scan, hex lattice + hashed pulses), the shared palette ramp, and the explicit-size generate(_:width:height:).",
                 make: { PatternFieldsScene() }),
    SnapshotCase("escape-time",
                 note: "The Mandelbrot set and a Julia set at fixed framing and phase (no time, no random). Pins the escape-time generator: the z = z^2 + c iteration, the smooth iteration count, the cosine palette fold, and the interior fill, in both modes.",
                 make: { EscapeTimeScene() }),
    SnapshotCase("orbit-trap",
                 note: "The four orbit traps tiled 2x2 at fixed framing and angles (no time, no random): a turned cross on a Julia set, a point on the Mandelbrot plane, a circle and a turned square on two more Julia sets. Pins the orbit-trap generator: the minimum-distance tracking through the iteration, each trap's distance formula, the trap rotation, and the exp glow ramp.",
                 make: { OrbitTrapScene() }),
    SnapshotCase("noise-toolkit",
                 note: "The noise-toolkit generators tiled 2x2 at a fixed phase (no time, no random): domain-warped noise (the warp knob on .noise), and the cellular generator in its three styles (cells, borders at reduced jitter, mosaic). Pins the warped-fbm displacement chain, the wandering-feature-point Worley scan, the border AA, and the per-cell mosaic hash, plus that each tile generates at its own size.",
                 make: { NoiseToolkitScene() }),
    SnapshotCase("chladni",
                 note: "The Chladni generator tiled 2x2 at fixed phases (no time, no random): the sand style at the default mode, at a higher mode with full grain, and at a fractional (morphing) mode, plus the wave style mid-swing. Pins the standing-wave field, the Gaussian sand gather + speckle threshold and its phase re-throw, the wave color swing, and each tile generating at its own size.",
                 make: { ChladniScene() }),
    SnapshotCase("terrain-3d",
                 note: "A small seeded diamond-square heightfield eroded hydraulically and thermally, emitted as a height-textured mesh under a fixed camera (no time; all randomness seeded). Pins the whole Heightfield chain: the subdivision generator, the droplet erosion (steering, capacity, brush take, bilinear deposit), the thermal relaxation, the mesh emission (positions, smooth normals, winding, UVs), and the height-ramp texture mapping.",
                 make: { TerrainScene() }),
    SnapshotCase("metaballs",
                 note: "Four metaballs at fixed positions (a fusing pair, a lone ball, and a negative ball carving into it) marched into a mesh under a fixed camera (no time, no random). Pins the marching-cubes path end to end: the soft-object falloff and its summed field, the face-contour construction with the asymptotic decider, the welded vertices and gradient normals, the outward winding, and the auto-padded bounds that let the surface close.",
                 make: { MetaballsScene() }),
    SnapshotCase("subdivision-surfaces",
                 note: "A cube and an extruded star smoothed with mesh.subdivided under a fixed camera (no time, no random): the cube through the quad rules at levels 1 and 3 with its wireframe cage ghosted over the level-3 solid, the star through both the quad and triangle rules. Pins the whole pipeline: the positional weld of flat-shaded cage vertices, quad recovery from the generator triangle pattern, the Catmull-Clark and Loop masks with the limit push, and the smooth-normal output the lighting reads.",
                 make: { SubdivisionSurfaceScene() }),
    SnapshotCase("mesh-growth",
                 note: "Two seeded surfaces grown to a fixed step count under a fixed camera (no time, one pinned seed each): a sphere under the uniform driver, which folds evenly all over, and one under a banded field driver, which ruffles only where the band grows. Pins the growth pipeline end to end: the welded input topology, the growth springs and two-hop self-avoidance, the split/collapse/flip remeshing that keeps the surface a closed manifold while its topology churns, and the bending term that decides how big the folds come out.",
                 make: { MeshGrowthScene() }),
    SnapshotCase("surface-from-points",
                 note: "Both point-cloud surfacing paths under a fixed camera (no time, no random): a golden-spiral sphere sample reconstructed closed by reconstructSurface beside the same sample with its top third removed, whose rim stays an honest open hole, and a particleSurface skin over a small helix of points. Pins the tangent-plane fit, the spanning-tree orientation, the validity cutoff that keeps data gaps open, the near-surface band, and the blended-ball field, all through the shared marching-cubes pass.",
                 make: { SurfaceFromPointsScene() }),
    SnapshotCase("effects-simfield", frame: 60,
                 note: "A reaction-diffusion SimField seeded with a fixed dot grid, evolved to frame 60 and recoloured. Pins the stateful sim substrate end to end: the persistent ping-pong, the seed-inject pass, the multi-substep Gray-Scott stepping, and the headless render-every-frame warmup the built-up state depends on.",
                 make: { EffectsSimField() }),
    SnapshotCase("effects-simfield-modulated", frame: 150,
                 note: "The modulated sibling of effects-simfield: the same fixed dot-grid seed under a half-black, half-white modulation layer, spot regime on the left sliding to maze/coral on the right, evolved to frame 150 and recoloured. Pins the modulated step variant: the map layer resolved before the sim passes, the per-texel feed/kill lerp from the params row's z/w, and one continuous field wearing two regimes with the pattern crossing the boundary instead of seaming at it.",
                 make: { EffectsSimFieldModulated() }),
    SnapshotCase("effects-fluid", frame: 48,
                 note: "A fluid SimField driven by a fixed brush path, run to frame 48. Pins the multi-field fluid pipeline end to end: the velocity + dye splat, curl and vorticity confinement, the Jacobi pressure projection, semi-Lagrangian advection, and the persistent two-pair ping-pong with render-every-frame warmup.",
                 make: { EffectsFluid() }),
    SnapshotCase("ripples", frame: 90,
                 note: "A ripples SimField rained on by seeded drops (seed set once in setup), run to frame 90 and shaded by .relight. Pins the wave-equation step (height/velocity coupling, damping, the absorbing rim), the add-to-height inject that keeps the velocity channel clean, the sub-CFL coupling gain and 6-substep pacing that keep the grid-scale mode from rattling, and the render-every-frame headless warmup the evolving surface depends on.",
                 make: { RipplesScene() }),
    SnapshotCase("lenia", frame: 60,
                 note: "A Lenia SimField seeded with a fixed grid of graded-alpha dots, evolved to frame 60 and recoloured. Pins the continuous-CA step end to end: the ring-kernel convolution with in-loop normalization, the bell-curve growth mapping, the dt integration and clip, and the params rows riding after the texel size.",
                 make: { LeniaScene() }),
    SnapshotCase("multi-scale-turing", frame: 150,
                 note: "A multi-scale Turing SimField, unseeded (it self-organizes from its own noise) and read without a withField block, run to frame 150 and shaded as relief. Pins the whole dedicated pipeline: the seeded noise fill a fresh field starts from, the Gaussian blur pyramid and the disc gather that reads it two rungs finer (the rectilinear-lattice fix), the per-scale variation chain that lets coarse scales hold ground, the least-variation scale selection, the 4x4 min/max extent chain and the renormalization that keeps the field from running away, and the read-registers-the-field path that steps a sim nothing is drawn into.",
                 make: { MultiScaleTuringScene() }),
    SnapshotCase("sandpile", frame: 120,
                 note: "An Abelian sandpile on the classic protocol: a mountain dropped once on frame 1 (a fixed dot, no rng), caught mid-collapse at frame 120 so the picture holds both regimes at once, settled counts as lacework at the rim and cells still mid-topple at the hot core. Pins the parallel multiple-toppling gather (fract(q) plus floored neighbour quarters), the open boundary, the add-whole-grains inject with its rounding, the quarters state encoding whose flat levels the gradient map reads, and the render-every-frame headless warmup the collapse depends on. SandpileTests pins the rule itself against a sequential CPU reference (the abelian schedule-independence), which a whole-frame mean diff cannot.",
                 make: { SandpileScene() }),
    SnapshotCase("cyclic-automaton", frame: 300,
                 note: "A cyclic cellular automaton (the classic 14-state, threshold-1, von Neumann rule) from its seeded random start, run to frame 300 and recoloured by a closed hue wheel. Pins the state-automata family end to end: the seeded random state fill a fresh field starts from (a uniform field is a fixed point), the s/(levels-1) state encoding and rint decode, the eat-the-next-color advance, and the toroidal neighbour taps. StateAutomataTests pins the rule itself cell-for-cell against a sequential CPU reference, which a whole-frame mean diff cannot.",
                 make: { CyclicScene() }),
    SnapshotCase("excitable-medium", frame: 90,
                 note: "A Greenberg-Hastings excitable medium sparked by a fixed script (a line and four dots on frame 1, half the plane wiped at frame 30 so the broken front curls into a spiral pair), read at frame 90 through an inferno ramp. Pins the draw-to-spark inject (bright excites, dark calms, the alpha gate that keeps an anti-aliased fringe from sparking) and the fire/recover/rest advance whose one-way recovery makes the rings and spirals.",
                 make: { ExcitableScene() }),
    SnapshotCase("brians-brain", frame: 60,
                 note: "Brian's Brain lit by a seeded sprinkle of single cells on frame 1 (a solid blob dies at once, so the soup is the protocol), run to frame 60 under the classic black/afterglow/white ramp. Pins the three-state advance (fire on exactly two, one step of rest, no re-lighting) and the snapping inject that keeps a mark's anti-aliased rim from reading as resting cells that block every birth.",
                 make: { BriansBrainScene() }),
    SnapshotCase("hodgepodge", frame: 300,
                 note: "A hodgepodge machine (the oscillating-chemical-reaction automaton; 100 states, k1 2, k2 3, g 25, the eight-cell block) from its seeded random start, run to frame 300 and recoloured with turbo. Pins the three-branch rule: the healthy cell's floored catch from infected and ill neighbours, the infected cell's averaged-sum climb plus g with the self-counting denominator, the instant recovery at the top, and the cap.",
                 make: { HodgepodgeScene() }),
    SnapshotCase("watercolor-sim", frame: 140,
                 note: "A watercolor SimField painted by a fixed script: an ultramarine wash laid on frame 1 (its edge darkening as it sits), rose charged into it wet-in-wet on frame 30, the sheet dried on frame 60, and a hansa-yellow band glazed across everything on frame 62, caught at frame 140. Pins the whole three-layer wash pipeline: the staggered-grid shallow-water step with the paper's slope, the divergence relaxation, the blurred-mask edge darkening, upwind pigment advection, the density/staining/granulation exchange with the deposit layer, the capillary re-wet of damp paper, the dry() bake into the glaze stack, and the Kubelka-Munk rendering (wet wash over dried glazes over paper) whose optical mixing the crossing shows. WatercolorSimTests pins the behaviors a mean diff averages away.",
                 make: { WatercolorSimScene() }),
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
                 note: "Three discs at near/mid/far depths, combined with a matching depth map and defocused with the focal plane on the middle disc. Pins the depth-of-field combine: the depth read (perceptual luminance), the circle-of-confusion gather keeping the in-focus band crisp while near and far blur, and the expanding golden-angle spiral (a reproducible function of pixel position, no jitter). The gather's per-silhouette rules are pinned behaviorally by DefocusTests, which a mean-difference comparison averages away.",
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
    SnapshotCase("gumowski-mira", frame: 12,
                 note: "The three newer iterated maps accumulated additively over several frames: a Gumowski-Mira blossom across the canvas, an Ikeda swirl inset lower-left, a hopalong web inset lower-right. Pins all three map rules (each deterministic from its start, no settle, so the Gumowski-Mira transient renders exactly) and the noClear build-up.",
                 make: { NewerMapsScene() }),
    SnapshotCase("bifurcation",
                 note: "One-dimensional maps three ways: the logistic bifurcation diagram as a log-toned density image, the Gauss mouse diagram as swept dots, and a cobweb staircase over its curve and diagonal. Pins the sweep's column-center sampling, the density image's global log tone, the point mapping, and the cobweb/graph geometry. No rng and no time, so it is deterministic.",
                 make: { BifurcationScene() }),
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
    SnapshotCase("contact-shadows",
                 note: "Three solids resting flush on a floor under a low directional caster with a wide soft (PCSS) map and contactShadows() on. Pins the screen-space contact term: the depth pre-pass, the march toward the caster (dithered by static interleaved gradient noise), and the mask sample folded into the caster's shadow attenuation, drawing the dark seam that seats each base where the soft map alone leaves it loose.",
                 make: { ContactShadowsScene() }),
    SnapshotCase("lighting-presets",
                 note: "A still life lit by the .goldenHour LightingPreset. Pins the preset path (ambient + warm/cool directionals, the light colors from Color(kelvin:)) through the lit-mesh pipeline.",
                 make: { LightingPresetScene() }),
    SnapshotCase("mesh-materials",
                 note: "A row of spheres in the stylized materials. Pins the per-batch OllinMaterial uniform and each new shader branch: a Fresnel iridescent sheen, the rim glow (velvet), fake subsurface (jade), toon cel bands, and Gooch warm-cool. No time.",
                 make: { MeshMaterialsScene() }),
    SnapshotCase("sparkle-materials",
                 note: "The sparkle (metallic-flake) finish: .glitter, .sequin, and a gold-flake tint under a fixed camera. Pins the OllinMaterial sparkle fields, the hash-cell flake normal + two-lobe flash, the size-aware paillette mask, and the sceneScale cell sizing. No time, so it's deterministic.",
                 make: { SparkleMaterialsScene() }),
    SnapshotCase("pbr-materials",
                 note: "A metal / mixed / dielectric x roughness sweep in the physically-based shading model (shadingModel 3). Pins the new OllinMaterial metallic/roughness fields and the Cook-Torrance branch (GGX distribution, Smith visibility, Schlick Fresnel, the (1-metallic) diffuse kill). No time, so it's deterministic.",
                 make: { PBRMaterialsScene() }),
    SnapshotCase("pbr-ibl",
                 note: "Physically-based balls lit by a bundled HDRI environment (image-based lighting): pins the whole IBL path (the equirect->cube / irradiance / GGX-prefilter / BRDF-LUT bake, the split-sum ambient on the mesh fragment, and the skybox backdrop). Fixed camera + environment, no time, so the bake is deterministic.",
                 make: { IBLScene() }),
    SnapshotCase("soap-film",
                 note: "A thin glass sphere in the iridescence finish's soap-film mode (iridescenceFlow) at a fixed phase: pins the drainage-plus-warped-swirl thickness field, the per-wavelength interference palette (dark thin film, the straw/magenta/cyan orders, the broadband rolloff toward pale), and the scene-scaled swirl cells. Fixed camera + environment + phase, no time.",
                 make: { SoapFilmScene() }),
    SnapshotCase("glass-materials",
                 note: "Transmissive (glass) physically-based spheres over a bundled environment, no ray tracing: pins the environment-refraction base path every GPU gets (the entry refract + analytic interior span + curvature-blended exit for a solid, the parallel thin exit, the IOR-remapped frosting lod, Beer-Lambert absorption, the f0-from-IOR packing, and the transmitted-for-diffuse swap in the IBL ambient and the direct-light diffKeep). Fixed camera + environment, no time.",
                 make: { GlassScene() }),
    SnapshotCase("normal-maps",
                 note: "Tangent-space normal maps on generated spheres beside a bare control: pins the normal-mapped textured twin pipeline (packed half4 vertex tangents, the raw-data linear texture read, the sign * cross(N, T) bitangent, the glTF-sign MikkTSpace basis from generatingTangents, and normalScale). Authored green-up maps from height functions, fixed camera + light, no time, no rng.",
                 make: { NormalMapScene() }),
    SnapshotCase("surface-maps",
                 note: "The PBR map set on generated spheres beside a bare control, over a bundled environment: a packed metallic-roughness map (worn paint turning to polished metal), an occlusion map paired with a normal map from one height field, and an emissive map on a dark shell. Pins the surface-mapped twin pipeline (the hand-synced meshLitColorMapped / mapped IBL ambient tails), the factor x sample composition, the indirect-only occlusion dimming, and the emissive add ahead of the atmosphere. Authored maps, fixed camera, no time, no rng.",
                 make: { SurfaceMapScene() }),
    SnapshotCase("parallax-relief",
                 note: "One authored crater height map read three ways on generated spheres: parallax occlusion (the tangent-space march + secant refinement in the surface-mapped fragment, round silhouette), CPU displacement (displaced(by:scale:), really cratered rim, weld-aware move + recomputed normals), and the bare color-mapped control. Oblique fixed camera so the parallax shift shows. Authored maps, no time, no rng.",
                 make: { ParallaxScene() }),
    SnapshotCase("triplanar",
                 note: "Triplanar projection on meshes with no uvs: a two-ball metaball skin and an abutting box pair wearing one authored vein texture plus its normal map, projected along the world axes and blended by the normal. Pins the fourth-power weight blend, the per-axis u sign flip, the projected whiteout normal combine, the world anchoring (the boxes continue each other's pattern), and the triplanar gate on the surface-mapped pipeline. Authored maps, fixed camera + light, no time, no rng.",
                 make: { TriplanarScene() }),
    SnapshotCase("detail-maps",
                 note: "Detail maps on a close-up textured sphere beside its undetailed twin: a fine speckle color map (data read, 128-gray neutral, the x2 multiply) and a fine bump normal map reoriented onto the base normal map's relief (the RNM blend), tiled at the detail scale through the repeat sampler. Pins the tiling, the neutral, the reorientation, and the detail gates on the surface-mapped pipeline. Authored maps, fixed camera + light, no time, no rng.",
                 make: { DetailMapScene() }),
    SnapshotCase("decals",
                 note: "Projected decals: a roundel stamped down across a floor and a crate at once (one box conforming over two meshes, the crate's vertical faces fading edge-on), a striped tag stamped sideways onto the crate's front with a roll, and a half-opacity ring overlapping the roundel (call-order compositing, premultiplied blend). Pins the world-to-box rows, the cookie-rule orientation, the facing fade, and the routed surface-mapped pipeline serving plain solid meshes. Authored images, fixed camera + light, no time, no rng.",
                 make: { DecalScene() }),
    SnapshotCase("coat-sheen",
                 note: "The layered physically-based lobes over a bundled environment plus a point light: a coated red metal beside its bare twin (the clear-coat Cook-Torrance lobe, the Kelemen visibility, the coat-interface F0 remap, and the coat's smooth IBL gather), a piano-black lacquer, a white-sheen felt beside its bare twin (the inverted-alpha sine sheen lobe, the cloth visibility, the sheen-LUT energy scaling, and the sheen's own prefiltered gather), and a two-tone velvet. Fixed camera + environment, no time.",
                 make: { CoatSheenScene() }),
    SnapshotCase("subsurface-scattering",
                 note: "Real subsurface scattering (the separable screen-space diffusion): a skin sphere beside its bare twin and a marble torus over a plain floor. Pins the scatter-mask pass (projected step, depth, profile index; the plain floor and twin as occluders writing mark 0), the CPU kernel build for two distinct profiles in one frame, the two-direction blur with its per-pixel early-out, and the radius-relative depth-gap guard. Fixed camera + light, no time.",
                 make: { SubsurfaceScatteringScene() }),
    SnapshotCase("subsurface-transmittance",
                 note: "The scattering transmittance (shadow-map translucency): a thin skin slab beside a deep twin and a sphere, backlit by a directional caster with castShadows() on, so the visible faces are the bodies' dark sides. Pins the 2D-map thickness read (the shrink along the normal, the bilinear linearized depth, the orthographic shadowLinearize constants), the slab-integral transmittance profile (the thin face floods deep red, the deep face keeps only its short-crossing rim, the sphere a warm crescent), and the reversed-normal wrap irradiance. Fixed camera + light, no time.",
                 make: { SubsurfaceTransmittanceScene() }),
    SnapshotCase("area-lights",
                 note: "A rect panel, a disk, and a tube (the LTC area lights) over a glossy floor and a roughness row: pins the bundled LTC table load, the horizon-clipped rect integral, the disk's ellipse/cubic path, the tube's line integral, the physical falloff, and the Blinn-Phong shininess-to-roughness mapping on the standard-material box. Fixed camera, no time.",
                 make: { AreaLightsScene() }),
    SnapshotCase("light-shaping",
                 note: "Light shaping: a ring-profiled IES point light, a rolled asymmetric profile, and a window-gobo cookie spot over a floor + wall. Pins the LM-63 parse, the theta/phi bake + texture-array sampling, the projector-convention cookie mapping, the roll, and the iesEnabled/cookieEnabled gates. Fixed camera, no time.",
                 make: { LightShapingScene() }),
    SnapshotCase("procedural-sky",
                 note: "PBR balls + a floor lit by a procedural Hosek-Wilkie sky (no asset): pins the .sky path (the CPU coefficient cook (vendored model), the GPU sky-equirect generation, and the same equirect->cube / irradiance / GGX-prefilter bake + skybox the HDRI path uses). Fixed sun elevation + camera, no time, so the generation and bake are deterministic.",
                 make: { ProceduralSkyScene() }),
    SnapshotCase("fog",
                 note: "Height fog over a fixed colonnade: near columns crisp, far ones dissolving, the mist pooling low. Pins the closed-form height-fog transmittance on the mesh carriers, the fog gate, and the fullscreen air backdrop washing the empty sky. Fixed camera, no time, no rng.",
                 make: { FogScene() }),
    SnapshotCase("volumetric-light",
                 note: "A window-gobo spot and a bare crossing spot marched as beams through thin haze over a dark set, the props carving shadow shafts. Pins the cone-bounded volumetric march (ray-cone span), the light-leg extinction, cookie/cone/IES shaping evaluated in air, the per-step shadow taps, and the deterministic per-pixel jitter. Fixed camera, no time.",
                 make: { VolumetricLightScene() }),
    SnapshotCase("sky-clouds",
                 note: "A raymarched cloudscape baked into the procedural sky: a scattered deck behind a chrome ball and a matte floor, so one bake carries the backdrop, the dimmed-and-diffused lighting, and the reflection. Pins the cloud noise kernels, the weather/height/erosion density chain, the sun-lit march, the clouds-in-the-cache-key rule, and the sharp cloudy-sky backdrop default. Fixed sun + phase, no time, no rng.",
                 make: { SkyCloudsScene() }),
    SnapshotCase("aerial-perspective",
                 note: "Files of dark ridges receding under a procedural sky with aerial perspective on: near ridges hold their color, far ones veil blue and melt into the horizon, the air brightening toward the sky's own sun. Pins the mode-2 fog gate, the wavelength-split extinction, the closed-form sun in-scatter, the sun resolved from the .sky environment through its rotation, and the air veil stepping aside behind the skybox. Fixed camera + sun, no time, no rng.",
                 make: { AerialPerspectiveScene() }),
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
    SnapshotCase("low-discrepancy",
                 note: "The Halton (2,3) sequence in the left half and the Sobol sequence in the right, dotted at a fixed count. Pins both low-discrepancy constructions exactly (radical inverse digits; Gray-code direction numbers): any change to either sequence moves points. No rng and no time, so it is deterministic.",
                 make: { LowDiscrepancyScene() }),
    SnapshotCase("stipple",
                 note: "A painted radial gradient rebuilt as a weighted-Voronoi stipple: dots pack toward the dark center and thin outward. Pins the density rasterization, the rejection-sampled seeding, and the weighted-Lloyd iteration with its exact nearest-dot assignment. Seeded, no time, so the layout is deterministic.",
                 make: { StippleScene() }),
    SnapshotCase("single-line",
                 note: "The same kind of painted radial gradient rendered as one continuous closed line: a seeded stipple toured by nearest-neighbor plus 2-opt. Pins the tour construction and improvement (any change to the heuristics rewires the meander) on top of the stipple. Seeded, no time, so the line is deterministic.",
                 make: { SingleLineScene() }),
    SnapshotCase("spanning-tree",
                 note: "The same kind of painted radial gradient joined by the minimum spanning tree instead of a tour: branching chains that crowd toward the dark center. Pins the Delaunay-edge Kruskal build and the odd-vertex chain decomposition (any change rewires the branching) on top of the stipple. Seeded, no time, so the tree is deterministic.",
                 make: { SpanningTreeScene() }),
    SnapshotCase("isolines",
                 note: "Level curves two ways: a two-blob metaball field traced at rising levels on the left (outer rings merged, the tightest level split in two), and the tone lines of a painted diagonal gradient with a dark disk on the right. Pins the marching-squares case table, the cell-average saddle rule, the open-chain stitching against the bounds, and the image tone sampling. No rng and no time, so it is deterministic.",
                 make: { IsolineScene() }),
    SnapshotCase("concave-hull",
                 note: "A dotted ring with an offshore cluster wrapped three ways: the alpha shape filled (two islands, the ring keeping its hole), the concave hull stroked dipping into the gulf between them, and the convex hull faint behind. Pins the chi-shape erosion order and its opposite-vertex stop, the hull-notch capping, and the alpha complex's island and hole resolution. Seeded, no time, so it is deterministic.",
                 make: { ConcaveHullScene() }),
    SnapshotCase("medial-axis",
                 note: "A wobbly blob with an off-center hole reduced to its skeleton: branches stroked over the faint outline, a closed ring around the hole, and inscribed circles riding the carried radii. Pins the Voronoi-subcomplex extraction (ring-neighbor filter and inside test), the twig pruning, and the branch decomposition with its canonical ordering. Seeded, no time, so it is deterministic.",
                 make: { MedialAxisScene() }),
    SnapshotCase("straight-skeleton",
                 note: "A lobed blob with an off-center hole carrying its straight skeleton: corner arcs faint, interior ridges strong, and a ladder of mitered insets that rings the hole and splits between the lobes. Pins the wavefront simulation (edge and split events, the clustered simultaneous cases, the hole's LAV merge) and the face-plane inset extraction with its exact stitching. Seeded, no time, so it is deterministic.",
                 make: { StraightSkeletonScene() }),
    SnapshotCase("force-graph",
                 note: "A seeded scale-free web settled by the force-directed layout: hubs ringed by their spokes, chains at the rim, edges and nodes drawn plainly through drawGraph. Pins the force pass (all-pairs repulsion, edge attraction, the temperature cap and frame clamp) and the linear cooling to a frozen standstill. Seeded, no time, so it is deterministic.",
                 make: { ForceGraphScene() }),
    SnapshotCase("marbling",
                 note: "A marbled paper built from fixed operations: a two-ink bull's-eye combed downward into feathers, a stylus pull, and a small vortex. Pins every closed-form transform (the area-preserving drop, the tine/comb falloff law, the swirl rotation), the stretch-driven outline refinement, and drawMarbling's oldest-first stacking. No rng and no time, so it is deterministic.",
                 make: { MarblingScene() }),
    SnapshotCase("watercolor",
                 note: "Two overlapping watercolor pools, layers interleaved so the overlap glazes both ways. Pins the recursive midpoint deformation (Gaussian jumps, inherited decaying variance, the detail floor), the shared-base layering, and the non-zero-wound layer fill (even-odd would cut pinholes where a layer self-crosses). Seeded through a local SplitMix64 in setup, no time, so it is deterministic.",
                 make: { WatercolorScene() }),
    SnapshotCase("glyph-mosaic",
                 note: "A painted diagonal gradient with a bright disk, rebuilt as a glyph mosaic in the bundled bitmap font: dense marks in the bright corner and around the disk, a lone dot at the faint edge, true emptiness below the floor. Pins the measured ink ramp, the nearest-coverage selection, the empty floor, and the cell layout. No rng and no time, so it is deterministic.",
                 make: { GlyphMosaicScene() }),
    SnapshotCase("color-vision",
                 note: "Two palettes drawn four ways: as most people see them, and through each of the three kinds at full severity. The left pair is a familiar chart set, whose orange, green and red arrive on one olive; the right pair is the published safe set, which holds apart. The lower half puts the same strip through Filter.colorVision, so the CPU call and the GPU filter are in one frame and a drift between them shows. Pins the published matrix table, the linear-light application, and the filter dispatch. No rng and no time, so it is deterministic.",
                 make: { ColorVisionScene() }),
    SnapshotCase("halftone",
                 note: "A painted tonal study (gradient, solid-ink disk, bare-paper disk) screened as vector halftone dots twice: the dark-ink reading on the left and the inverted light-ink reading on the right, both on a rotated screen. Pins the rotated-cell binning, the area-exact dot sizing through the edge-clipped branch, the printable-dot cutoff, and the inverted mapping. No rng and no time, so it is deterministic.",
                 make: { HalftoneScene() }),
    SnapshotCase("luminance-melt",
                 note: "A painted tonal study (gradient plus a bright disk) poured through the luminance melt at a fixed phase. Pins the two-level domain warp, the shared displacement (field warp and image liquify from one vector), the luminance steer into the field, the four-stop sRGB ramp, and the highlight bloom. No rng and no time, so it is deterministic.",
                 make: { LuminanceMeltScene() }),
    SnapshotCase("pixel-sort",
                 note: "A painted noisy gradient with guard bands, pixel-sorted vertically then horizontally inside a midtone window, drawn at 1:1 pixels. Pins the interval detection (runs bounded where brightness leaves the window), the brightness key, and the deterministic tie-break. Seeded paint, no time, so it is deterministic.",
                 make: { PixelSortScene() }),
    SnapshotCase("slit-scan",
                 note: "Twelve painted frames of a falling bar pushed into a SlitScan history and read back through a left-to-right delay, so the bar shears into a staircase. Pins the frame ring's ordering, the delay quantization, and the closure delay's uv mapping. No rng and no time, so it is deterministic.",
                 make: { SlitScanScene() }),
    SnapshotCase("levy-flight",
                 note: "A seeded Lévy flight polyline, scaled to fit: tight step clusters strung together by rare long jumps. Pins the truncated power-law inverse-CDF step sampling and the walk's rng call order. Seeded, no time, so the path is deterministic.",
                 make: { LevyFlightScene() }),
    SnapshotCase("self-avoiding-walk",
                 note: "A seeded self-avoiding walk threading a lattice as one stroke, hue along its length. Pins the backtracking DFS (visited cells stay blocked, the longest path wins), the neighbor shuffling's rng order, and the lattice centering. Seeded, no time, so the path is deterministic.",
                 make: { SelfAvoidingWalkScene() }),
    SnapshotCase("crack-growth",
                 note: "A seeded crack-growth field run several hundred ticks in one frame: perpendicular cracks subdividing the plane, each dragging its one-sided grain wash. Pins the angle-grid collision rules, the restart-and-recruit population, the wash's side and sin-eased grain spacing, and the rng call order. Seeded, no time, so it is deterministic.",
                 make: { CrackGrowthScene() }),
    SnapshotCase("string-art",
                 note: "A painted crescent wound as string art in one frame: a few hundred greedy chords of one thread over a ring of pins, drawn translucent. Pins the darkness sampling and its circle mask, the greedy mean-darkness scoring, the ink pay-down, the span and no-repeat rules, and the pin layout. No rng and no time, so it is deterministic.",
                 make: { StringArtScene() }),
    SnapshotCase("percolation",
                 note: "A seeded site-percolation grid just past the critical probability (no time): island clusters tinted by size and the spanning cluster filled warm with its traced boundary loops stroked. Pins the seeded fill, the union-find labeling and largest-first order, the spanning test, cellRects placement, and the outline tracer's loops and collinear merging.",
                 make: { PercolationScene() }),
    SnapshotCase("dither",
                 note: "One painted gradient quantized to a three-color palette four ways, at 1:1 pixels: plain nearest-color (banding), ordered Bayer, blue noise, Floyd-Steinberg. Pins the whole dithering pass (the Bayer recurrence, the void-and-cluster tile, the error-diffusion kernel and its serpentine scan) plus the color space each family chooses its colors in. No rng and no time, so it is deterministic.",
                 make: { DitherScene() }),
    SnapshotCase("print-separation",
                 note: "A two-ink artwork split into spot-color printing masters: the artwork, its halftoned overprint preview, and the two grayscale masters. Pins the separation search (the linear-light overprint model judged in OKLab), the preview reconstruction from the masters, the rotated round-dot screens, and the minimum-dot highlight cutoff. No rng and no time, so it is deterministic.",
                 make: { PrintSeparationScene() }),
    SnapshotCase("truchet",
                 note: "A Truchet tiling: arc tiles in the top half, diagonal tiles in the bottom, each cell's orientation chosen by the seed. Pins both tile geometries and the cross-cell connectivity (the arcs meet at shared edge midpoints, the diagonals at corners). Seeded, no time, so the layout is deterministic.",
                 make: { TruchetScene() }),
    SnapshotCase("hitomezashi",
                 note: "A hitomezashi stitch design: the two-tone parity fill underneath, the dash line-work over it. Pins the per-line dash alternation, the phase each line's bit picks, and that the fill's tone boundaries land exactly on the stitches (the two-coloring). Seeded, no time, so the design is deterministic.",
                 make: { HitomezashiScene() }),
    SnapshotCase("penrose",
                 note: "Penrose tilings, kites and darts left, rhombs right, each with the matching-rule arcs stroked on top. Pins both deflations (the derived P2 rules and the P3 rules), the half-tile merge, the rhombs' intrinsic orientation, and the arc fractions that make the decoration continuous across every edge. No rng and no time, so it is deterministic.",
                 make: { PenroseScene() }),
    SnapshotCase("wang-tiles",
                 note: "A Wang tiling from the complete 2-color set, drawn as edge-color triangles. Pins the scanline fill (west/east and north/south edges always match), the weighted candidate choice's rng order, and the classic quadrant rendering. Seeded, no time, so the layout is deterministic.",
                 make: { WangTilesScene() }),
    SnapshotCase("girih",
                 note: "Star patterns by polygons-in-contact: a honeycomb's strapwork at a fixed contact angle, and the girih-tile flower (a decagon ringed by ten edge-laid pentagons) at the classic 54 degrees. Pins the ray inference (greedy shortest-total-length pairing), cross-tile continuity at edge midpoints, and the exact edge-to-edge tile placement. No rng and no time, so it is deterministic.",
                 make: { GirihScene() }),
    SnapshotCase("spectre",
                 note: "A spectre (einstein) patch with curved chiral edges, colored by metatile with the odd mystic partners accented. Pins the substitution system (slot transforms, per-level mirroring, the mystic pair), the bounds fit, and the alternating edge bumps. No rng and no time, so it is deterministic.",
                 make: { SpectreScene() }),
    SnapshotCase("circle-packing",
                 note: "Circle packing, both grow-to-touch flavors: a self-seeding gap-filling pack in the top half (big circles first, smaller ones filling the gaps) and a blue-noise foam in the bottom half (a circle grown at each Poisson-disk point until it touches its nearest neighbor). Pins that circles never overlap and land the same way. Seeded, no time, so the layout is deterministic.",
                 make: { CirclePackingScene() }),
    SnapshotCase("l-system",
                 note: "Four L-system presets in a 2x2: the dragon curve and Hilbert curve (turtle turning and F/G forward, no branching), the fern-like plant (the branch [ ] stack), and the stochastic plant (random productions drawn from the seed). Pins the string expansion, the turtle interpretation, branching, and fit-to-bounds. Seeded, no time, so it is deterministic.",
                 make: { LSystemScene() }),
    SnapshotCase("parametric-l-system",
                 note: "Four parametric L-systems in a 2x2, one per thing parameters buy: the subdivision curve (segments at fractions of their parent, which no plain grammar can say), the compound leaf (a counter the turtle never reads, delaying each bud), the tapered tree (a width per branch, drawn as marks so strokeWeight is the trunk), and a weighted stochastic branch. Pins the expression evaluator and its precedence, arity-aware matching, the guard conditions, first-match-wins against weighted choice, the width stack, and fit-to-bounds. Seeded, no time, so it is deterministic.",
                 make: { ParametricLSystemScene() }),
    SnapshotCase("differential-growth", frame: 130,
                 note: "A seeded ring grown by differential growth to a fixed frame: attraction, alignment, and spatial-hash repulsion per step plus edge-splitting fold it into a brain-coral meander. Pins the stepper (forces, node injection, the spatial hash) at a deterministic frame. Seeded, and the frame is fixed, so the fold is reproducible.",
                 make: { DifferentialGrowthScene() }),
    SnapshotCase("meander", frame: 170,
                 note: "A seeded river migrated to a fixed frame: curvature-driven drift with upstream weighting bends the channel, the spline resample keeps the spacing even, and the recorded scars ribbon beneath the water. Pins the stepper (curvature, the upstream average, the resample, scar recording) at a deterministic frame. Seeded, and the migration itself is rng-free, so the river is reproducible.",
                 make: { MeanderScene() }),
    SnapshotCase("wave-function-collapse",
                 note: "A pipe network solved by Wave Function Collapse over a blank + straight/elbow/tee/cross tileset. Pins the solver: min-entropy observation, weighted collapse, and arc-consistency propagation reach a fully legal grid (every internal pipe meets a matching pipe). Seeded, no time, so the layout is deterministic (the sorted-candidate guard keeps the Set-based solve reproducible).",
                 make: { WaveFunctionCollapseScene() }),
    SnapshotCase("texture-synthesis",
                 note: "Wave Function Collapse's overlapping model: a 16x16 sample authored in the test teaches its own 3x3 patches, and a larger texture is built out of them so every overlap agrees. Pins the whole chain (pattern extraction with the sample read as wrapping, symmetry augmentation, the overlap rule, the support-counter propagation, and the boundary read-out) end to end; drawn as one rect per pixel, so the picture is the solved grid exactly. Seeded, no time, so it is deterministic.",
                 make: { TextureSynthesisScene() }),
    SnapshotCase("shape-packing",
                 note: "A bag of polygons and a star packed by their bounding circles: big shapes first, smaller ones filling the gaps, each a random pick, rotated and scaled to its packed circle. Pins packShapes (the bounding-circle placement over the circle packer, the random rotation, the fit). Seeded, no time, so the layout is deterministic.",
                 make: { ShapePackingScene() }),
    SnapshotCase("streamlines",
                 note: "Evenly-spaced streamlines through a Perlin flow field, seeded from a blue-noise set. Pins the field (angle from noise), the both-directions tracing, and the separation test that keeps the lines from crossing. Seeded, no time, so the lines are deterministic.",
                 make: { StreamlinesScene() }),
    SnapshotCase("classic-curves",
                 note: "The classic-curve builders on one sheet: a 3:2 Lissajous figure, a 5-petal rose nesting a 7/3 rational rose, a hypotrochoid and an epitrochoid from the same gear pair, a squircle superellipse over a pinched one, a 7-lobe supershape, a phyllotaxis scatter at the golden angle, and a spiky star smoothed by Chaikin corner cutting over its raw outline. Pure closed forms, no rng and no time, so the sheet is deterministic.",
                 make: { ClassicCurvesScene() }),
    SnapshotCase("ant-colony",
                 note: "An ant colony eight iterations into a tour over a seeded scatter: the pheromone web drawn with strength as alpha and width, the best tour so far in bright ink, the cities as dots. Pins the tour construction, the evaporate-and-deposit update, and the normalized trail read-back. Seeded, no time, so the search is deterministic.",
                 make: { AntColonyScene() }),
    SnapshotCase("lichtenberg",
                 note: "A dielectric-breakdown discharge grown 500 sites from a center seed in one frame: field-weighted growth on the lattice, pipe-model widths thickening the main channels, a violet additive halo under a hot core. Pins the Laplace-field growth weights, the parent links, and the width accumulation. Seeded, no time, so the figure is deterministic.",
                 make: { LichtenbergScene() }),
    SnapshotCase("guilloche",
                 note: "A guilloche rosette: concentric rings shaped by a coarse cam plus a fine ripple, each ring turned a hair against its neighbor so braided arms weave through the waves. Pins the stacked-rosette sum, the per-ring twist, and the ring spacing. Pure closed form, no rng and no time, so the face is deterministic.",
                 make: { GuillocheScene() }),
    SnapshotCase("harmonograph",
                 note: "A damped-pendulum harmonograph trace: two pendulums per axis, near-unison fundamentals plus faster overtones, baked once by contour() and drawn as one open polyline. The detune precesses the figure and the damping reels each lap inward. No rng and no time, so the weave is deterministic.",
                 make: { HarmonographScene() }),
    SnapshotCase("ridge-lines",
                 note: "Stacked mountain ridgelines lifted from ridged fractal noise at a fixed loop phase: back-to-front skyline rows, each occluding the last with an opaque panel. Pins the CPU ridged accumulator (the crease fold and its octave feedback) and its looping form. Seeded, fixed phase, so the ranges are deterministic.",
                 make: { RidgeLinesScene() }),
    SnapshotCase("flocking", frame: 120,
                 note: "A seeded flock of boids stepped to a fixed frame, drawn as heading-colored triangles. Pins Reynolds' separation/alignment/cohesion steering and the spatial-hash neighbor search (the force sums are order-stable, so a seeded flock reproduces). Seeded, fixed frame, so it's deterministic.",
                 make: { FlockingScene() }),
    SnapshotCase("steering", frame: 150,
                 note: "Steering vehicles stepped to a fixed frame: followers on a closed path (with separation), a seeded wanderer's trail, and a pursuer leading its target. Pins Reynolds' individual steering behaviors (seek/arrive ramp, wander determinism, path projection + seam wrap, pursuit prediction). Seeded, fixed frame, so it's deterministic.",
                 make: { SteeringScene() }),
    SnapshotCase("ik-chain",
                 note: "Inverse-kinematics chains solved against fixed targets in one frame: an unconstrained FABRIK arm, a stiffness-limited FABRIK arm on the same target (the bend budget spreads the curve), a CCD arm (tip-heavy curl), an out-of-reach chain stretched straight, and a dragged free-base rope. Pins both solvers, the bend clamp, the unreachable stretch, and drag. No rng, no time, deterministic.",
                 make: { IKChainScene() }),
    SnapshotCase("double-pendulum", frame: 140,
                 note: "Three double pendulums a hair apart stepped to a fixed frame, second-bob trails traced. Pins the equations of motion under the fixed-substep integrator (trajectories are exact functions of the start) and the early, still-coherent divergence. No rng, fixed frame, deterministic.",
                 make: { DoublePendulumScene() }),
    SnapshotCase("n-body", frame: 80,
                 note: "A seeded orbital disk stepped to a fixed frame through the quadtree force pass and the leapfrog integrator, bodies tinted by speed. Pins the tree build, the opening criterion, Plummer softening, and the circular-orbit factory (deterministic iteration orders throughout). Seeded, fixed frame, deterministic.",
                 make: { NBodyScene() }),
    SnapshotCase("space-colonization", frame: 140,
                 note: "Space colonization grown to a fixed frame: veins from a bottom root toward a seeded blue-noise attractor set, stroked with pipe-model thickness. Pins the closest-node pull association, average-direction growth, attractor consumption, and the thickness pass (all deterministic given the input). Seeded, fixed frame.",
                 make: { SpaceColonizationScene() }),
    SnapshotCase("stroke-shape",
                 note: "Stroke-as-shape geometry: an open S-curve stroked round into a region with inset bands inside it, a closed square stroked into a band, and a convex-hull outline stroked thin. Pins cc2_stroke (open caps, the closed Joined band, self-overlap union), offset cascades over a stroke region, and convexHull. No time, deterministic.",
                 make: { StrokeShapeScene() }),
    SnapshotCase("svg-import",
                 note: "An inline SVG drawn as authored (left) and as bare outlined contours (right). Pins the importer end to end: the path grammar with arcs, the even-odd ring, nested group transforms incl. a mirror, the quadratic path, the open stroked arc with its cap, paint parsing (hex, rgb(), named), and fitted(in:). Pure CPU parse, no time, deterministic.",
                 make: { SVGImportScene() }),
    SnapshotCase("epicycles",
                 note: "A Fourier epicycle chain over a two-frequency rosette: the full-term path reproduces the outline, an 8-term prefix smooths it, and drawEpicycles renders the circles and spokes at a fixed lap phase. Pins the DFT (term order, phases), point/joints/path agreement, and the drawing sugar. Pure CPU build, no time, deterministic.",
                 make: { EpicyclesScene() }),
    SnapshotCase("shape-morph",
                 note: "Shape morphing mid-blend: a star-to-donut ShapeMorph at a fixed t (pins contour pairing, the rotation correspondence, and the hole growing out of the center), a strip of triangle-to-circle one-offs at five fractions (pins exact endpoints and the blend between), and an open zigzag-to-arc lerp (pins direction alignment for open runs). Pure CPU build, no time, deterministic.",
                 make: { ShapeMorphScene() }),
    SnapshotCase("cellular-automata",
                 note: "Two 1D cellular automata as stacked-row triangles: elementary rule 30 (left) and 3-color totalistic code 777 (right), each from a single center seed. Pins the rule-byte lookup, the totalistic base-k digit table, and row stacking. Pure CPU, no time, no random.",
                 make: { CellularAutomataScene() }),
    SnapshotCase("turmites",
                 note: "Langton's ant run 14,000 steps on a wrapped grid: the chaotic blob plus the emerged highway. Pins the turmite step semantics end to end (read, write, turn, move, state) and the deterministic multi-step drive. Pure CPU, no time, no random.",
                 make: { TurmiteScene() }),
    SnapshotCase("dla", frame: 110,
                 note: "A diffusion-limited aggregation cluster grown to a fixed frame from a center seed, tinted by arrival order. Pins the seeded walker (spawn/kill radii, far-jump stride, exact touch-distance landing) and the spatial-hash touch test. Seeded, fixed frame, so it's deterministic.",
                 make: { DLAScene() }),
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
    SnapshotCase("loaded-scene",
                 note: "A hand-composed Scene (floor, a pedestal whose child torus is tipped and spun through the subscript, an orb) drawn via drawScene through the scene's own camera and three lights. Pins the node-tree walk composing local transforms onto the model matrix, the subscript's in-place mutation, and applying a Scene's camera/lights as ordinary state. Fixed angles, no time, deterministic. (The glTF scene *loader* is pinned by SceneLoaderTests.)",
                 make: { LoadedSceneScene() }),
    SnapshotCase("animated-scene",
                 note: "The bundled orrery asset posed by its authored \"spin\" animation at a fixed 3.2 s: the planet arm swung 144 deg on spherically-blended LINEAR quaternion keys, the moon arm counter-turned, the marker orb mid-descent on its CUBICSPLINE bob, and the base pointer four STEP ticks around. Pins the glTF animation parse (channels grouped to tracks), all three sampler modes, and apply() rebuilding node TRS local transforms drawn through drawScene with the scene's own camera and lights. Fixed sample time, no shadows, deterministic.",
                 make: { AnimatedSceneScene() }),
    SnapshotCase("usd-scene",
                 note: "The bundled USD sculpture court loaded from the repo (the structure-preserving Model I/O walk: named nodes, nested plinth transforms, node-local meshes wearing their authored preview-surface colors) drawn through the file's own camera and its authored UsdLux rig, one light of every mapped kind (distant/sphere/shaped-cone/rect/disk/cylinder), resolved by Ollin's parser through each prim's xformOps. No shadows, no time, deterministic.",
                 make: { USDSceneScene() }),
    SnapshotCase("usd-animated-scene",
                 note: "The bundled USD kinetic mobile posed by its authored timeSamples animation at a fixed 2.7 s: the beam mid-turn, the child beam counter-rotated, the moon mid-bob on translation keys, the gem tumbled on quaternion (orient) keys, the pendulum ring swung off vertical through the baked pivot idiom, and the counterweight mid-breath on scale keys. Pins the raw-tree timeSamples read, the union-of-times bake with its TRS decomposition, the timeCodesPerSecond mapping, name-bound track application, and drawScene under the file's own camera and UsdLux lights. Fixed sample time, no shadows, deterministic.",
                 make: { USDAnimatedSceneScene() }),
    SnapshotCase("usd-skinned-scene",
                 note: "The bundled USD pond posed by its UsdSkel rig at a fixed 2.6 s: the serpent bent by its five-joint skinned chain (two blended influences per point, joint tracks bound by synthesized node identity, a geomBindTransform mapping the local points) and the lotus mid-breath on its two blend shapes (the dense bloom with normal offsets, the sparse tip curl) via the name-bound weights track from an animation bound with no skeleton. Pins the Skeleton synthesis, the raw-tree deforming-mesh rebuild, the primvar expansion, and drawScene posing it all under the file's own camera and UsdLux lights. Fixed sample time, no shadows, deterministic.",
                 make: { USDSkinnedSceneScene() }),
    SnapshotCase("skinned-scene",
                 note: "The bundled tidepool asset posed by its authored \"sway\" animation at a fixed 1.9 s: three kelp blades bent by their four-joint skins (per-vertex JOINTS_0/WEIGHTS_0 blends, u8 joints, shared inverse-bind accessor) and the anemone mid-pulse on its two morph targets (a dense puff and a sparse-accessor ripple) via the morph-weights track. Pins the skin parse, the scene-root joint-matrix pose, the ignored-skinned-node-transform rule on the draw path, sparse displacement decode, and weights-channel sampling, drawn through drawScene with the scene's own camera and lights. Fixed sample time, no shadows, deterministic.",
                 make: { SkinnedSceneScene() }),
    SnapshotCase("symmetry",
                 note: "One wedge of drawing folded by symmetry(6, mirrored: true) around an off-axis pivot, over every replicated 2D path: an SDF circle and star, a tessellated polygon fill with its fringe outline, a stroked polyline, a smooth-union SDF field, and bitmap text; a center dot lands once after noSymmetry(). Pins the CTM-conjugated fold matrices, the per-path replication (instances, range copies, group instances), and the on/off scoping. No time, deterministic.",
                 make: { SymmetryScene() }),
    SnapshotCase("clip",
                 note: "Stencil clipping (withClip): a stripe pattern, SDF circles, and a fringe stroke confined to a star-shaped region; a nested circle clip that intersects it; unclipped drawing after the pop crossing the old boundary; and a rect-clipped text run. Pins the clip push/pop stencil levels, per-batch clip state across the SDF/triangle/fringe/glyph paths, and the pop restoring level 0. No time, deterministic.",
                 make: { ClipScene() }),
    SnapshotCase("retained-batch",
                 note: "One motif recorded into a Batch (SDF shapes incl. a gradient fill, a fringe polyline, a concave tessellated fill, a smooth-union SDF field) and replayed three ways: in place (the identity replay, byte-identical to recording), under a rotate+scale+translate stamp (the flag-gated shader transform), and with a dynamic shape drawn between the replays (draw-order compositing around a .retained reference batch). Pins the retained encode path, the batch's handle-relative gradient strip, and the per-run blend/pipeline selection. No time, deterministic.",
                 make: { RetainedBatchScene() }),
    SnapshotCase("instanced-mesh",
                 note: "A ring of pillars drawn as ONE instanced mesh call (drawMesh(_:instances:)): per-copy positions, y rotations, non-uniform scales, and tints over a floor, lit by a directional key with castShadows() on. Pins the instanced vertex placement (the per-copy matrix applied on the GPU), the adjugate normal transform under non-uniform scale, the per-copy tint multiply, and the instanced casters rendering into the 2D shadow map beside a plain-mesh floor. No time and no rng, deterministic.",
                 make: { InstancedMeshScene() }),
    SnapshotCase("mesh-field",
                 note: "A retained MeshField of three mesh kinds (boxes, spheres, cones) in a ring, drawn by GPU-written indirect draws with per-copy frustum culling ON and the camera framed so part of the ring sits outside the view. Pins the field build (entry table, compact regions), the cull + encode kernels, the per-entry indirect draws, the per-copy tints, and the field casters in the 2D shadow map beside a plain floor. Culling must not change a pixel (a culled copy is off-screen), so this reference also pins that no visible copy is ever lost. No rng and no time, deterministic.",
                 make: { MeshFieldScene() }),
    SnapshotCase("strands",
                 note: "A StrandField meadow patch (drawStrands) grown entirely in-draw by the mesh pipeline: 60k hashed blades over a floor with a box casting a shadow the blades receive, framed so part of the patch is off-screen with tile culling ON. Pins the object-stage tile cull + distance grading, the mesh-stage ribbon synthesis (roots, heights, leans, tapers, tints all from hashes), the blades shading through the shared lit fragment, and that culling never eats a visible tile. No time (phase-zero sway) and no rng, deterministic (the render is pinned byte-exact by its own test).",
                 make: { StrandsScene() }),
    SnapshotCase("tiling-grids",
                 note: "The hex and triangle grids on one sheet: a pointy-top hex grid tinted by hex distance from its center cell (concentric rings), a flat-top grid tinted by column, and a triangle grid whose up/down parity splits two palettes. Pins both hex orientations' lattice math (centers, corners, the offset half-step, axial distance, gutter insets) and the triangle tiling. No rng and no time, so it is deterministic.",
                 make: { TilingGridsScene() }),
    SnapshotCase("subdivision",
                 note: "Recursive subdivision both ways: a binary aspect-aware split with seeded accent fills (the grid-painting look) beside a probabilistic quadtree tinted by depth. Pins the split recursion (axis choice, fraction clamp, the minSize/maxDepth/chance stops) and the exact partition. Seeded, no time, so the layout is deterministic.",
                 make: { SubdivisionScene() }),
    SnapshotCase("maze",
                 note: "Three perfect mazes, one per carving algorithm (backtracker / Kruskal / Wilson), each with its longest path traced through. Pins the three generators, the merged straight wall runs, and the double-BFS longest path. Seeded, no time, so the mazes are deterministic.",
                 make: { MazeScene() }),
    SnapshotCase("apollonian",
                 note: "An Apollonian gasket tinted by generation order. Pins the Descartes-theorem foam: the closed-form seed triple, the linear other-root recursion filling every three-way gap, tangency without overlap, and the min-radius stop. No rng and no time, so it is deterministic.",
                 make: { ApollonianScene() }),
    SnapshotCase("ifs",
                 note: "The three bundled iterated function systems side by side (the fern, the triangle, the carpet), each condensed by a seeded chaos game and fitted to its panel. Pins the preset coefficient tables, the weighted map selection's rng order, the burn-in, and the fitted placement. Seeded, no time, so the clouds are deterministic.",
                 make: { IFSScene() }),
    SnapshotCase("inversion-fractal",
                 note: "The limit set of a ring of five tangent circles plus the inner circle, rendered by the seeded inversion chaos game over the drawn mirrors. Pins the inversion formula, the never-the-same-circle-twice walk, the outside start, and the burn-in. Seeded, no time, so the dust is deterministic.",
                 make: { InversionFractalScene() }),
    SnapshotCase("kleinian",
                 note: "Two Kleinian limit sets, the Apollonian-gasket curve above a lacy quasi-Fuchsian one, each traced as a single ordered closed polyline and fitted to its half. Pins the two-generator trace recipe, the depth-first walk's cyclic ordering and landmark points, and the epsilon termination. No rng and no time, so the curves are deterministic.",
                 make: { KleinianScene() }),
    SnapshotCase("schottky",
                 note: "A Schottky group's circle orbit twice over: four circles in two touching pairs above, the gasket-trace group's orbit below. Pins the pairing map (outside onto inside, the tangency-preserving twist zero point that makes a touching pair's generator parabolic), the closed-form Möbius image of a circle, the radius-pruned walk over reduced words, and the trace-recipe bridge that seats a matrix group's isometric circles as pairing discs. No rng and no time, so both laces are deterministic.",
                 make: { SchottkyScene() }),
    SnapshotCase("fractal-flame",
                 note: "A seeded random fractal flame accumulated to a fixed sample count and developed once. Pins the chaos-game loop (weighted picks, the fuse), the variation formulas and their theta convention, structural coloring, and the log-density display with gamma and vibrancy. Seeded, and the sample count is fixed, so the render is deterministic.",
                 make: { FractalFlameScene() }),
    SnapshotCase("buddhabrot",
                 note: "A seeded Buddhabrot plate accumulated to a fixed orbit count and developed once, in the three-cap false-color split. Pins the orbit test (interior shortcuts, escape step), the half-disc seed region, the mirrored upright deposit, the per-channel cap gating, and the percentile-ceiling gamma develop. Seeded and fixed-count, so the render is deterministic.",
                 make: { BuddhabrotScene() }),
    SnapshotCase("taa",
                 note: "Thin tilted slats and a sphere under temporalAntialiasing(): pins the deterministic export path (N jittered geometry renders under the fixed sequence, averaged within the frame), the jittered-projection plumbing on the mesh path, and the weighted-sum normalization. Fixed camera, no time; runs on any Metal GPU.",
                 make: { TAAScene() }),
    SnapshotCase("motion-blur", frame: 2,
                 note: "A sphere mover crossing a still colonnade under a panning camera with motionBlur() on, captured at frame 2 (frame k reads frame k-1's camera and movers, so the streak is a pure function of the frame pair). Pins the whole chain: the full-screen velocity fill (the mover texture over the depth-reprojected camera motion), the tile/neighbor dominant-velocity pyramid, the three-case reconstruction gather with its position-pure jitter, and the shutter scale. Runs on any Metal GPU.",
                 make: { MotionBlurScene() }),
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
    SnapshotCase("rt-refraction-3d",
                 note: "Glass bodies in front of colored pillars with rayTracedReflections() on: pins the traced refraction walk (the solid's interior leg finding its real exit back face and refracting out, the thin walk hopping through its own shell, Beer-Lambert over the traced span, the shared hit shade, and the environment miss fallback). RT-gated, so it only runs (and is recorded) on a ray-tracing GPU.",
                 make: { GlassRefractionScene() }),
    SnapshotCase("area-shadows",
                 note: "A box and a sphere over a floor, lit by one rect strip panel with castShadows() on. On a ray-tracing GPU the area caster traces visibility to the panel's actual surface, which the reference is recorded against: pins the traced-panel path (the antithetic R2 samples over the rect, the shadowSoftness scale on the extent, the anisotropic penumbra a strip throws) and the shadow dimming inside the LTC area branch. The non-RT spot-style PCSS map differs and is probe-tested instead. Fixed camera, no time.",
                 make: { AreaShadowsScene() }),
    SnapshotCase("area-reflections",
                 note: "A panel-lit white wall seen in a near-mirror metal floor with rayTracedReflections() on: pins the exact LTC diffuse in the traced hit shade (ollin_ltc_diffuse through ollin_rt_direct), the deferred trace pass's amp-table bind and LTC resolve, and the panel's glow carrying into the mirror with the same spread as the direct view. Fixed camera, bundled environment, no time.",
                 make: { AreaReflectionsScene() }),
    SnapshotCase("gi-3d",
                 note: "A Cornell-style room lit by one spot pool with globalIllumination() on: the ceiling and walls carry only bounce light, the colored walls dye the white statue from either side. Pins the whole probe-field pipeline end to end: the auto-fitted volume, the deterministic in-frame convergence (iteration-indexed seeds, progressive-mean hysteresis), probe relocation walking the embedded slab-row probes out, the cage-capped visibility moments, and the perceptually-encoded sampling in the lit carriers. RT-gated, so it only runs (and is recorded) on a ray-tracing GPU.",
                 make: { GlobalIlluminationScene() }),
]

// MARK: - Fixtures

/// Thin bright slats at slight tilts plus a sphere, with `temporalAntialiasing()`
/// on: the geometry where the export supersample's refinement is largest (and
/// where a broken jitter or average shows immediately). No ray-traced features,
/// so it runs on any Metal GPU.
private final class TAAScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.04))
        perspective(eye: Vector3(0, 1.4, 4.4), target: Vector3(0, 0.6, 0),
                    fieldOfView: .pi / 3.2, near: 0.5, far: 30)
        ambientLight(Color(white: 0.10))
        directionalLight(.white, direction: Vector3(-0.4, -1, -0.6), intensity: 0.9)
        temporalAntialiasing()
        fill(Color(white: 0.95))
        for i in 0..<5 {
            withState {
                translate(0, 0.15 + Double(i) * 0.32, 0)
                rotate(0.04 + Double(i) * 0.015, axis: .unitZ)
                drawBox(width: 4.6, height: 0.04, depth: 0.05)
            }
        }
        withState {
            fill(Color(red: 0.75, green: 0.35, blue: 0.25))
            translate(1.2, 0.7, 0.8)
            drawSphere(radius: 0.55)
        }
        withState { fill(Color(white: 0.3)); translate(0, -0.1, 0); drawPlane(width: 9, depth: 9) }
    }
}

/// A fast sphere mover and a still colonnade under a panning camera with
/// `motionBlur()` on: the sphere streaks along its own declared motion, the
/// columns pick up the camera's, and the backdrop holds still. Motion is a pure
/// function of `frameCount`, so frame 2 always reads the same frame-1 state.
private final class MotionBlurScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.04))
        let pan = 0.12 * Double(frameCount)
        perspective(eye: Vector3(pan, 1.4, 4.6), target: Vector3(pan, 0.7, 0),
                    fieldOfView: .pi / 3.2, near: 0.5, far: 30)
        ambientLight(Color(white: 0.10))
        directionalLight(.white, direction: Vector3(-0.4, -1, -0.6), intensity: 0.9)
        motionBlur(shutter: 1)
        fill(Color(white: 0.6))
        for i in 0..<5 {
            withState {
                translate(-2.0 + Double(i), 0.7, -0.8)
                drawBox(width: 0.16, height: 1.8, depth: 0.16)
            }
        }
        withMotion {
            withState {
                fill(Color(red: 0.85, green: 0.62, blue: 0.2))
                translate(-1.6 + 0.55 * Double(frameCount), 0.85, 0.7)
                drawSphere(radius: 0.4)
            }
        }
        withState { fill(Color(white: 0.3)); translate(0, -0.1, 0); drawPlane(width: 9, depth: 9) }
    }
}

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

/// The committed AnimatedScene example asset, loaded from the repo and posed by
/// its authored animation at a fixed time, drawn through its own camera and
/// lights (no shadows: a point-light caster would resolve differently on RT and
/// non-RT GPUs).
private final class AnimatedSceneScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private var orrery: Ollin.Scene!

    override func setup() {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // OllinTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Examples/3D/Geometry/AnimatedScene/scene.gltf")
        orrery = Ollin.Scene(contentsOf: url)
    }

    override func draw() {
        background(Color(white: 0.05))
        camera(orrery.camera ?? .orbiting(target: Vector3(0, 1, 0), radius: 6))
        for l in orrery.lights { light(l) }
        if let spin = orrery.animations.first {
            orrery.apply(spin, at: 3.2)
        }
        fill(.white)
        drawScene(orrery)
    }
}

/// The committed USDScene example asset, loaded from the repo and drawn through
/// its authored camera and its authored UsdLux lighting rig (read by Ollin's
/// own parser). Static, no shadows, no time.
private final class USDSceneScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private var court: Ollin.Scene!

    override func setup() {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // OllinTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Examples/3D/Geometry/USDScene/stage.usda")
        court = Ollin.Scene(contentsOf: url)
    }

    override func draw() {
        background(Color(white: 0.05))
        camera(court.camera ?? .orbiting(target: Vector3(0, 1, 0), radius: 7))
        ambientLight(Color(white: 0.2))
        for l in court.lights { light(l) }
        fill(.white)
        drawScene(court)
    }
}

/// The committed USDAnimatedScene example asset, its authored timeSamples
/// animation applied at a fixed time, drawn through its own camera and UsdLux
/// lights (no shadows: a point-light caster would resolve differently on RT
/// and non-RT GPUs).
private final class USDAnimatedSceneScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private var mobile: Ollin.Scene!

    override func setup() {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // OllinTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Examples/3D/Geometry/USDAnimatedScene/stage.usda")
        mobile = Ollin.Scene(contentsOf: url)
    }

    override func draw() {
        background(Color(white: 0.05))
        camera(mobile.camera ?? .orbiting(target: Vector3(0, 1.6, 0), radius: 7))
        ambientLight(Color(white: 0.2))
        for l in mobile.lights { light(l) }
        if let lap = mobile.animations.first {
            mobile.apply(lap, at: 2.7)
        }
        fill(.white)
        drawScene(mobile)
    }
}

/// The committed USDSkinnedScene pond asset, its UsdSkel deformation applied
/// at a fixed time: the serpent bent by its five-joint skinned chain, the
/// lotus mid-breath on its two blend-shape weights (no shadows: the asset
/// carries a sphere light, whose point caster would resolve differently on RT
/// and non-RT GPUs).
private final class USDSkinnedSceneScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private var pond: Ollin.Scene!

    override func setup() {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // OllinTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Examples/3D/Geometry/USDSkinnedScene/stage.usda")
        pond = Ollin.Scene(contentsOf: url)
    }

    override func draw() {
        background(Color(white: 0.05))
        camera(pond.camera ?? .orbiting(target: Vector3(0, 0.8, 0), radius: 6))
        ambientLight(Color(white: 0.2))
        for l in pond.lights { light(l) }
        if let lap = pond.animations.first {
            pond.apply(lap, at: 2.6)
        }
        fill(.white)
        drawScene(pond)
    }
}

/// The bundled tidepool asset, its "sway" animation applied at a fixed time,
/// drawn through the scene's own camera and lights (no shadows: the asset
/// carries a point light, whose caster would resolve differently on RT and
/// non-RT GPUs).
private final class SkinnedSceneScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private var tidepool: Ollin.Scene!

    override func setup() {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // OllinTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Examples/3D/Geometry/SkinnedScene/scene.gltf")
        tidepool = Ollin.Scene(contentsOf: url)
    }

    override func draw() {
        background(Color(white: 0.05))
        camera(tidepool.camera ?? .orbiting(target: Vector3(0, 0.6, 0), radius: 5))
        for l in tidepool.lights { light(l) }
        if let sway = tidepool.animations.first {
            tidepool.apply(sway, at: 1.9)
        }
        fill(.white)
        drawScene(tidepool)
    }
}

private final class LoadedSceneScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.05))
        var stage = Ollin.Scene(
            nodes: [
                SceneNode(name: "floor", mesh: .box(width: 6, height: 0.1, depth: 6),
                          position: Vector3(0, -0.05, 0)),
                SceneNode(name: "pedestal", mesh: .box(width: 0.8, height: 1, depth: 0.8),
                          position: Vector3(0, 0.5, 0), children: [
                              SceneNode(name: "sculpture", mesh: .torus(radius: 0.34, tube: 0.13),
                                        position: Vector3(0, 0.95, 0)),
                          ]),
                SceneNode(name: "orb", mesh: .sphere(radius: 0.25), position: Vector3(1.2, 0.25, 0.6)),
            ],
            cameras: [.perspective(eye: Vector3(2.4, 1.8, 3.1), target: Vector3(0, 0.8, 0),
                                   fieldOfView: 0.7)],
            lights: [
                .point(Color(hex: 0xFFC780), at: Vector3(-1.4, 2.0, -0.4), intensity: 0.9),
                .spot(.white, at: Vector3(1.9, 2.7, 1.6), direction: Vector3(-1.9, -1.7, -1.6),
                      angle: 1.1, penumbra: 0.5),
                .directional(Color(hex: 0x9FB3E6), direction: Vector3(0.4, -0.8, -0.45),
                             intensity: 0.35),
            ])
        // Reach the nested node through the subscript: tip the torus upright, then
        // spin it a fixed angle about its own pivot.
        stage["sculpture"]?.rotate(.pi / 2, axis: .unitX)
        stage["sculpture"]?.rotate(0.8, axis: .unitY)

        camera(stage.camera ?? .orbiting(radius: 6))
        for l in stage.lights { light(l) }
        fill(.white)
        drawScene(stage)
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

/// A Cornell-style room whose only light is a spot pool on the floor, with
/// `globalIllumination()` on: everything outside the pool is the probes' bounce.
/// Fixed camera, no time.
private final class GlobalIlluminationScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.black)
        camera(.orbiting(target: Vector3(0, 1.9, 0), radius: 9.5,
                         azimuth: 0, elevation: 0.03, fieldOfView: .pi / 3.2,
                         near: 1, far: 40))
        spotLight(.white, at: Vector3(0, 3.8, 0.4), direction: Vector3(0, -1, -0.1),
                  angle: .pi / 3.4, penumbra: 0.5, intensity: 3)
        castShadows()
        globalIllumination()
        withState { fill(Color(white: 0.88)); translate(0, -0.1, 0); drawBox(width: 8.4, height: 0.2, depth: 8.4) }
        withState { fill(Color(white: 0.88)); translate(0, 4.1, 0); drawBox(width: 8.4, height: 0.2, depth: 8.4) }
        withState { fill(Color(white: 0.88)); translate(0, 2, -4.3); drawBox(width: 8.4, height: 4.4, depth: 0.2) }
        withState { fill(Color(hex: 0xd4622a)); translate(-4.3, 2, 0); drawBox(width: 0.2, height: 4.4, depth: 8.4) }
        withState { fill(Color(hex: 0x2a9d9d)); translate(4.3, 2, 0); drawBox(width: 0.2, height: 4.4, depth: 8.4) }
        withState {
            fill(Color(white: 0.9))
            translate(-1.2, 1.1, 0.4); rotateY(0.42)
            drawBox(width: 1.5, height: 2.2, depth: 1.5)
        }
        withState { fill(Color(white: 0.9)); translate(1.7, 0.75, -0.9); drawSphere(radius: 0.75) }
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
/// Three solids resting flush on a floor, a deliberately wide soft shadow map
/// (softness 0.8, so the map alone leaves every base loose), and the contact
/// march closing the seam. Fixed camera, no `time`: deterministic.
private final class ContactShadowsScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.05))
        camera(.orbiting(target: Vector3(0, 0.5, 0), radius: 8,
                         azimuth: 0.4, elevation: 0.3))
        ambientLight(Color(white: 0.2))
        directionalLight(.white, direction: Vector3(-0.7, -0.55, -0.3), intensity: 1.0)
        castShadows()
        shadowSoftness(0.8)
        contactShadows()
        fill(Color(white: 0.85))
        drawPlane(width: 20, depth: 20)
        withState {
            fill(Color(hue: 0.03, saturation: 0.55, brightness: 0.9))
            translate(-0.8, 0.7, 0)
            drawBox(size: 1.4)
        }
        withState {
            fill(Color(hue: 0.55, saturation: 0.5, brightness: 0.9))
            translate(1.2, 0.62, 0.8)
            drawSphere(radius: 0.62)
        }
        withState {
            fill(Color(hue: 0.12, saturation: 0.55, brightness: 0.9))
            translate(0.6, 0.5, -1.4)
            drawCylinder(radius: 0.5, height: 1.0)
        }
    }
}

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

/// A warm strip panel over a white diffuse wall, seen in a near-mirror metal floor
/// under a bundled environment with `rayTracedReflections()` on: the mirrored wall's
/// glow is the traced hit shade's exact LTC area-light diffuse. No `time`, so it's
/// deterministic (the export path averages a fixed in-frame ray set).
private final class AreaReflectionsScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.black)
        camera(.orbiting(target: Vector3(0, 0.8, 0), radius: 9,
                         azimuth: 0.2, elevation: 0.35))
        environment(.night)
        rayTracedReflections()
        rectLight(Color(hue: 0.09, saturation: 0.3, brightness: 1.0),
                  at: Vector3(0, 2.2, -1.0), direction: Vector3(0, -0.35, -1),
                  width: 3.0, height: 0.8, intensity: 10)
        withState {
            fill(Color(white: 0.9))
            material(.metal(roughness: 0.05))
            drawPlane(width: 16, depth: 12)
        }
        withState {
            translate(0, 1.6, -2.6)
            fill(.white)
            material(.dielectric(roughness: 0.85))
            drawBox(width: 5.0, height: 3.2, depth: 0.25)
        }
    }
}

/// The same still life lit by one rect *strip* panel with `castShadows()` on, through
/// the same fixed camera. The scene has no punctual light, so the panel is the caster;
/// on a ray-tracing GPU (this snapshot's gate) each lit pixel traces visibility rays
/// to the panel's actual surface, so the strip's shadow spreads mostly along its long
/// axis (the anisotropy a scalar penumbra can't make). No `time`, so it's deterministic.
private final class AreaShadowsScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.05))
        camera(.orbiting(target: Vector3(0, 0.6, 0), radius: 7,
                         azimuth: 0.5, elevation: 0.45, fieldOfView: .pi / 3.6))
        ambientLight(Color(white: 0.1))
        rectLight(Color(hue: 0.09, saturation: 0.2, brightness: 1.0),
                  at: Vector3(-1.5, 4.5, 1.2), direction: Vector3(0.3, -1, -0.25),
                  width: 4.0, height: 0.8, intensity: 4)
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

/// The three area-light kinds over a glossy floor: a warm rect panel from the left,
/// a cool disk from the right, and a bright thin tube along the front, on
/// physically-based spheres (roughness row) plus one standard-material box (the
/// Blinn-Phong shininess-to-roughness LUT mapping). Fixed camera, no `time`.
private final class AreaLightsScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.03))
        camera(.orbiting(target: Vector3(0, -0.3, 0), radius: 9,
                         azimuth: 0.15, elevation: 0.3, fieldOfView: .pi / 3.4))
        ambientLight(Color(white: 0.02))
        rectLight(Color(hue: 0.09, saturation: 0.32, brightness: 1.0),
                  at: Vector3(-3.0, 1.2, -1.6), direction: Vector3(0.6, -0.35, 0.7),
                  width: 2.6, height: 1.8, intensity: 7)
        diskLight(Color(hue: 0.55, saturation: 0.5, brightness: 1.0),
                  at: Vector3(3.2, 1.4, -0.8), direction: Vector3(-0.62, -0.4, 0.68),
                  radius: 1.0, intensity: 5)
        tubeLight(Color(hue: 0.87, saturation: 0.55, brightness: 1.0),
                  from: Vector3(-3.2, -1.0, 2.4), to: Vector3(3.2, -1.0, 2.4),
                  radius: 0.05, intensity: 24)

        withState {
            translate(0, -1.2, 0)
            fill(Color(white: 0.55))
            material(.dielectric(roughness: 0.15))
            drawPlane(width: 14, depth: 12)
        }
        for (i, r) in [0.06, 0.25, 0.6].enumerated() {
            withState {
                translate(-2.2 + Double(i) * 2.2, -0.5, 0.6)
                fill(Color(white: 0.9))
                material(.dielectric(roughness: r))
                drawSphere(radius: 0.7)
            }
        }
        // The one non-PBR solid: the standard material's area response (the
        // shininess-to-roughness mapping plus the norm-channel specular).
        withState {
            translate(0, -0.65, -1.8)
            rotateY(0.5)
            fill(Color(hue: 0.6, saturation: 0.35, brightness: 0.8))
            specular(0.6)
            shininess(64)
            drawBox(size: 1.1)
        }
    }
}

/// Height fog over a fixed colonnade (no rng: the grid placement is arithmetic), so
/// near columns stay crisp while far ones dissolve and the mist pools low. Pins the
/// analytic fog on the mesh carriers plus the fullscreen air-backdrop draw.
private final class FogScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        let tint = Color(hex: 0xB4BDC9)
        background(tint)
        camera(.orbiting(target: Vector3(0, 1.0, 0), radius: 11,
                         azimuth: 0.35, elevation: 0.2, fieldOfView: .pi / 4))
        directionalLight(Color(white: 1.0), direction: Vector3(0.5, 0.85, 0.3), intensity: 0.9)
        ambientLight(Color(white: 0.22))
        fog(tint, density: 0.16, heightFalloff: 0.55)
        fill(Color(white: 0.45))
        withState {
            translate(0, -0.5, 0)
            drawBox(width: 40, height: 1, depth: 40)
        }
        for i in 0..<5 {
            for j in 0..<5 {
                if i == 2 && j == 2 { continue }
                let h = 1.0 + Double((i * 7 + j * 3) % 9) * 0.45
                withState {
                    translate(Double(i - 2) * 3.0, h / 2, Double(j - 2) * 3.0)
                    fill(Color(white: 0.4 + Double((i + j) % 4) * 0.1))
                    drawCylinder(radius: 0.32, height: h)
                }
            }
        }
    }
}

/// A cloudy procedural sky under a fixed camera: the scattered deck, its light on a
/// matte floor, and its picture in a chrome ball, all from one bake. Fixed phase,
/// no `time`, no rng.
private final class SkyCloudsScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.black)
        toneMap(.aces)
        camera(.orbiting(target: Vector3(0, 1.4, 0), radius: 8.5,
                         azimuth: 0.5, elevation: 0.14, fieldOfView: .pi / 3.2))
        environment(.sky(turbidity: 2.4, sunElevation: 0.5).rotated(0.7)
            .clouds(Clouds(coverage: 0.55, phase: 2)))
        fill(.white)
        material(.polishedMetal)
        drawSphere(radius: 1.2)
        material(.matte)
        fill(Color(white: 0.55))
        withState { translate(0, -1.6, 0); drawBox(width: 36, height: 0.4, depth: 36) }
    }
}

/// Aerial perspective under a fixed camera: files of jagged dark ridges receding
/// beneath a procedural sky, the sky's own sun (through the environment rotation)
/// feeding the wavelength-split veil. Deterministic heights, no `time`, no rng.
private final class AerialPerspectiveScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.black)
        toneMap(.aces)
        camera(.orbiting(target: Vector3(0, 5, -55), radius: 70,
                         azimuth: 0, elevation: 0.055, fieldOfView: .pi / 3.8))
        environment(.sky(turbidity: 2.4, sunElevation: 0.35).rotated(4.4))
        aerialPerspective(density: 0.007, haziness: 0.3)
        fill(Color(hex: 0x2E332C))
        for i in 0 ..< 6 {
            withState {
                translate(0, 0, -2 - Double(i) * 18)
                for k in -24 ... 24 {
                    let a = Double(k) * 0.83 + Double(i) * 2.7
                    let h = 1.5 + Double(i) * 1.6
                          + 3.0 * abs(sin(a)) + 1.6 * abs(sin(a * 2.6))
                    withState {
                        translate(Double(k) * 5, h / 2, 0)
                        drawBox(width: 5.1, height: h, depth: 5)
                    }
                }
            }
        }
    }
}

/// The volumetric march under a fixed camera: a window-gobo key spot and a faint
/// crossing rim beam through thin haze, `castShadows()` carving prop shafts. The
/// gobo is authored inline (the LightShapingScene pattern). No `time`.
private final class VolumetricLightScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    static let gobo: LightCookie = {
        var frame = Image(width: 64, height: 64, color: .black)
        for y in 0..<64 {
            for x in 0..<64 {
                let inFrame = x > 4 && x < 59 && y > 4 && y < 59
                let onMullion = abs(x - 32) < 3 || abs(y - 32) < 3
                if inFrame && !onMullion { frame[x, y] = .white }
            }
        }
        return LightCookie(frame)!
    }()

    override func draw() {
        background(Color(hex: 0x04050A))
        camera(.orbiting(target: Vector3(0, 0.9, 0), radius: 10.5,
                         azimuth: 0.2, elevation: 0.16, fieldOfView: .pi / 4.2))
        ambientLight(Color(white: 0.015))
        spotLight(Color(hue: 0.10, saturation: 0.28, brightness: 1.0),
                  at: Vector3(-4.6, 6.0, 2.6), direction: Vector3(0.62, -0.74, -0.28),
                  angle: .pi / 8, penumbra: 0.22, intensity: 3.2,
                  cookie: VolumetricLightScene.gobo, roll: 0.18)
        spotLight(Color(hue: 0.58, saturation: 0.45, brightness: 1.0),
                  at: Vector3(5.6, 2.6, -4.8), direction: Vector3(-0.92, -0.18, 0.36),
                  angle: .pi / 10, penumbra: 0.5, intensity: 0.7)
        castShadows()
        volumetricLight(0.9, anisotropy: 0.45)
        fog(Color(hex: 0x0A0E18), density: 0.02)

        fill(Color(hex: 0x2E3138))
        withState {
            translate(0, -0.55, 0)
            drawBox(width: 22, height: 1.1, depth: 22)
        }
        fill(Color(hex: 0x8A8478))
        withState {
            translate(-0.4, 1.35, -0.3)
            drawCylinder(radius: 0.42, height: 2.7)
        }
        fill(Color(hex: 0x707A86))
        withState {
            translate(1.7, 0.62, 1.3)
            drawSphere(radius: 0.62)
        }
        fill(Color(hex: 0x66605A))
        withState {
            translate(-2.1, 0.85, 1.8)
            rotateY(0.5)
            drawBox(width: 0.75, height: 1.7, depth: 0.75)
        }
    }
}

/// Light shaping under a fixed camera: a ring-profiled point light pooling on the
/// floor, an asymmetric bilateral profile rolled toward the wall, and a spot
/// projecting a window-frame cookie. All profile data is authored inline, so the
/// scene pins the parser, the bake, the array sampling, and the projector-convention
/// cookie orientation in one image. No `time`.
private final class LightShapingScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    static let ring = IESProfile(string: """
    IESNA:LM-63-2002
    TILT=NONE
    1 1000 1 8 1 1 2 0.1 0.1 0.1
    1.0 1.0 100
    0 10 20 30 40 50 60 90
    0
    1000 700 200 350 600 250 40 0
    """)!

    static let fan = IESProfile(string: """
    IESNA:LM-63-2002
    TILT=NONE
    1 1000 1 6 4 1 2 0.1 0.1 0.1
    1.0 1.0 100
    0 20 40 60 80 90
    0 60 120 180
    500 900 1000 700 200 0
    400 700 750 450 120 0
    150 250 260 150 40 0
    40 60 60 30 8 0
    """)!

    static let gobo: LightCookie = {
        var frame = Image(width: 64, height: 64, color: .black)
        for y in 0..<64 {
            for x in 0..<64 {
                let inFrame = x > 4 && x < 59 && y > 4 && y < 59
                let onMullion = abs(x - 32) < 3 || abs(y - 32) < 3
                if inFrame && !onMullion { frame[x, y] = .white }
            }
        }
        return LightCookie(frame)!
    }()

    override func draw() {
        background(Color(white: 0.02))
        camera(.orbiting(target: Vector3(0, -0.3, 0), radius: 9,
                         azimuth: 0.1, elevation: 0.32, fieldOfView: .pi / 3.4))
        ambientLight(Color(white: 0.015))
        pointLight(Color(hue: 0.09, saturation: 0.4, brightness: 1.0),
                   at: Vector3(-2.4, 0.9, 0.6), intensity: 1.3,
                   profile: LightShapingScene.ring)
        pointLight(Color(hue: 0.58, saturation: 0.35, brightness: 1.0),
                   at: Vector3(2.6, 1.6, 0.8), intensity: 1.5,
                   profile: LightShapingScene.fan,
                   axis: Vector3(0, -0.6, -1), roll: .pi / 2)
        spotLight(Color(hue: 0.13, saturation: 0.3, brightness: 1.0),
                  at: Vector3(-3.4, 2.8, 3.6), direction: Vector3(0.55, -0.6, -0.5),
                  angle: 0.75, penumbra: 0.15, intensity: 1.3,
                  cookie: LightShapingScene.gobo, roll: 0.15)

        withState {
            translate(0, -1.2, 0)
            fill(Color(white: 0.6))
            material(.dielectric(roughness: 0.75))
            drawPlane(width: 14, depth: 12)
        }
        withState {
            translate(0, 1.0, -3.0)
            fill(Color(white: 0.55))
            material(.dielectric(roughness: 0.85))
            drawBox(width: 14, height: 4.4, depth: 0.25)
        }
        withState {
            translate(-2.4, -0.7, 0.6)
            fill(Color(white: 0.85))
            material(.dielectric(roughness: 0.45))
            drawSphere(radius: 0.55)
        }
    }
}

/// The sparkle (metallic-flake) finish under a fixed camera and custom lights: the
/// `.glitter` and `.sequin` built-ins plus a gold-flake tint. Pins the new
/// `OllinMaterial` sparkle fields, the hash-cell flake normal + two-lobe flash, the
/// paillette mask, and the `sceneScale` framing that sizes the cells. No `time`.
private final class SparkleMaterialsScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.05))
        camera(.orbiting(target: .zero, radius: 8,
                         azimuth: 0.3, elevation: 0.26, fieldOfView: .pi / 3.4))
        ambientLight(Color(white: 0.12))
        directionalLight(Color(kelvin: 5400), direction: Vector3(-0.4, -0.6, -0.5), intensity: 1.0)
        pointLight(.white, at: Vector3(3, 4, 4), intensity: 1.2)

        var goldFlake = Material.glitter
        goldFlake.sparkleColor = Color(hue: 0.12, saturation: 0.75, brightness: 1.0)
        goldFlake.sparkleSize = 2
        let entries: [(Material, Color)] = [
            (.glitter, Color(hue: 0.66, saturation: 0.75, brightness: 0.30)),
            (.sequin, Color(hue: 0.93, saturation: 0.80, brightness: 0.55)),
            (goldFlake, Color(hue: 0.02, saturation: 0.80, brightness: 0.35)),
        ]
        for (i, entry) in entries.enumerated() {
            withState {
                translate(-2.4 + Double(i) * 2.4, 0, 0)
                fill(entry.1)
                material(entry.0)
                drawSphere(radius: 1.05)
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

private final class SoapFilmScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.03))
        camera(.orbiting(target: .zero, radius: 4.6, azimuth: 0.0, elevation: 0.02,
                         fieldOfView: .pi / 4.2))
        environment(.studio.intensity(0.9).lightingOnly())
        directionalLight(.white, direction: Vector3(-0.5, -0.6, -0.6), intensity: 1.0)
        var film = Material.glass()
        film.iridescence = 1.0
        film.iridescenceScale = 1.4
        film.iridescenceFlow = 1.0
        film.iridescencePhase = 2.7
        material(film)
        fill(.white)
        drawSphere(radius: 1.5)
    }
}

private final class GlassScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.05))
        toneMap(.aces)
        camera(.orbiting(target: Vector3(0, 0.4, 0), radius: 6.5,
                         azimuth: 0.3, elevation: 0.12, fieldOfView: .pi / 3.4))
        environment(.studio)
        // A solid clear lens, a solid absorbing (bottle-green) body, a frosted solid,
        // and a thin-walled tinted bubble; a matte floor grounds them.
        let bodies: [(Color, Material, Double)] = [
            (.white, .glass(thickness: 1.6), -2.4),
            (.white, .glass(thickness: 1.6, attenuationColor: Color(hex: 0x2e8f5b),
                            attenuationDistance: 1.2), -0.8),
            (.white, .glass(roughness: 0.45, thickness: 1.6), 0.8),
            (Color(hex: 0xcfe4ff), .glass(), 2.4),
        ]
        for (c, m, x) in bodies {
            withState { translate(x, 0.4, 0); fill(c); material(m); drawSphere(radius: 0.8) }
        }
        withState {
            translate(0, -0.6, 0); fill(Color(white: 0.5)); material(.roughPlastic)
            drawBox(width: 20, height: 0.3, depth: 20)
        }
    }
}

private final class NormalMapScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    /// A tiling green-up normal map authored from a height function: engraved
    /// rings on the left sphere, a diagonal weave on the right. Pure math, no
    /// rng, so the render is a fixed function of nothing.
    private func map(strength: Double, height: (Double, Double) -> Double) -> Image {
        let size = 128
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        let d = 1.0 / Double(size)
        for y in 0..<size {
            for x in 0..<size {
                let u = (Double(x) + 0.5) * d, v = (Double(y) + 0.5) * d
                let dx = (height(u + d, v) - height(u - d, v)) / (2 * d) * strength
                let dy = (height(u, v + d) - height(u, v - d)) / (2 * d) * strength
                let len = (dx * dx + dy * dy + 1).squareRoot()
                let i = (y * size + x) * 4
                bytes[i]     = UInt8((-dx / len * 0.5 + 0.5) * 255)
                bytes[i + 1] = UInt8((dy / len * 0.5 + 0.5) * 255)
                bytes[i + 2] = UInt8((1 / len * 0.5 + 0.5) * 255)
                bytes[i + 3] = 255
            }
        }
        return Image(width: size, height: size, premultipliedRGBA: bytes)!
    }

    override func draw() {
        background(Color(white: 0.05))
        camera(.orbiting(target: .zero, radius: 6.4, azimuth: 0.2, elevation: 0.1,
                         fieldOfView: .pi / 3.4))
        directionalLight(.white, direction: Vector3(-0.6, -0.7, -0.5), intensity: 1.1)
        ambientLight(Color(white: 0.08))
        let rings = map(strength: 0.1) { u, v in
            let r = ((u - 0.5) * (u - 0.5) + (v - 0.5) * (v - 0.5)).squareRoot()
            return sin(r * 14 * .tau) * 0.5 + 0.5
        }
        let weave = map(strength: 0.06) { u, v in
            (sin(u * 10 * .tau) * 0.5 + 0.5) * (sin(v * 10 * .tau) * 0.5 + 0.5)
        }
        fill(Color(hex: 0xBFC3CC))
        let base = Mesh.sphere(radius: 1, segments: 64, rings: 32)
        withState { translate(-2.1, 0.3, 0); drawMesh(base.normalMapped(rings)) }
        withState { translate(0, 0.3, 0); drawMesh(base.normalMapped(weave, scale: 1.6)) }
        withState { translate(2.1, 0.3, 0); drawMesh(base) }
        withState {
            translate(0, -1.3, 0); fill(Color(white: 0.4))
            drawBox(width: 20, height: 0.3, depth: 20)
        }
    }
}

private final class SurfaceMapScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    /// An RGBA data map authored per texel from a function of (u, v). Pure
    /// math, no rng, so the render is a fixed function of nothing.
    private func map(_ texel: (Double, Double) -> (Double, Double, Double)) -> Image {
        let size = 128
        var bytes = [UInt8](repeating: 255, count: size * size * 4)
        let d = 1.0 / Double(size)
        for y in 0..<size {
            for x in 0..<size {
                let (r, g, b) = texel((Double(x) + 0.5) * d, (Double(y) + 0.5) * d)
                let i = (y * size + x) * 4
                bytes[i]     = UInt8(max(0, min(255, r * 255)))
                bytes[i + 1] = UInt8(max(0, min(255, g * 255)))
                bytes[i + 2] = UInt8(max(0, min(255, b * 255)))
            }
        }
        return Image(width: size, height: size, premultipliedRGBA: bytes)!
    }

    private func normalMap(strength: Double, height: @escaping (Double, Double) -> Double) -> Image {
        let d = 1.0 / 128.0
        return map { u, v in
            let dx = (height(u + d, v) - height(u - d, v)) / (2 * d) * strength
            let dy = (height(u, v + d) - height(u, v - d)) / (2 * d) * strength
            let len = (dx * dx + dy * dy + 1).squareRoot()
            return (-dx / len * 0.5 + 0.5, dy / len * 0.5 + 0.5, 1 / len * 0.5 + 0.5)
        }
    }

    override func draw() {
        background(Color(white: 0.05))
        camera(.orbiting(target: .zero, radius: 8.6, azimuth: 0.2, elevation: 0.12,
                         fieldOfView: .pi / 3.4))
        environment(.studio)
        let base = Mesh.sphere(radius: 1, segments: 64, rings: 32)

        // Worn paint over metal: one packed map (roughness g, metallic b).
        func wear(_ u: Double, _ v: Double) -> Double {
            let a = sin(u * 5 * .tau) * sin(v * 3 * .tau + 1.3)
            return a > 0.45 ? 1 : 0
        }
        let worn = base.textured(map { u, v in
            let bare = wear(u, v)
            return (0.68 + 0.22 * bare, 0.34 + 0.56 * bare, 0.22 + 0.66 * bare)
        }).surfaceMapped(metallicRoughness: map { u, v in
            let bare = wear(u, v)
            return (1, 0.72 - 0.5 * bare, bare)
        })

        // A coffered grid: one height field authoring relief + occlusion.
        func coffer(_ u: Double, _ v: Double) -> Double {
            let a = min(abs(u * 6 - (u * 6).rounded()), abs(v * 6 - (v * 6).rounded()))
            return min(max((a - 0.06) / 0.14, 0), 1)
        }
        var grooved = base.normalMapped(normalMap(strength: 0.12, height: coffer))
            .surfaceMapped(occlusion: map { u, v in
                let ao = 0.25 + 0.75 * coffer(u, v)
                return (ao, ao, ao)
            })
        grooved.material?.baseColor = Color(red: 0.75, green: 0.73, blue: 0.7)

        // Emissive seams on a dark shell, factor at half strength.
        var lit = base.surfaceMapped(
            emissive: map { u, v in
                func band(_ t: Double) -> Double {
                    let f = abs(t - t.rounded())
                    return f < 0.04 ? 1 : (f < 0.09 ? 1 - (f - 0.04) / 0.05 : 0)
                }
                let seam = max(band(u * 5), band(v * 3))
                return (seam * 0.25, seam * 0.85, seam)
            })
        lit.material?.baseColor = Color(red: 0.09, green: 0.1, blue: 0.12)
        lit.material?.emissiveFactor = Color(white: 0.5)

        let placed: [(Mesh, Material, Double)] = [
            (worn, .physicallyBased(metallic: 1, roughness: 1), -3.15),
            (grooved, .dielectric(roughness: 0.55), -1.05),
            (lit, .dielectric(roughness: 0.85), 1.05),
            (base, .physicallyBased(metallic: 1, roughness: 1), 3.15),
        ]
        fill(.white)
        for (mesh, finish, x) in placed {
            material(finish)
            withState { translate(x, 0.3, 0); drawMesh(mesh) }
        }
        material(Material())
        withState {
            translate(0, -1.3, 0); fill(Color(white: 0.4))
            drawBox(width: 20, height: 0.3, depth: 20)
        }
    }
}

private final class ParallaxScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    private var parallaxSphere = Mesh(positions: [], normals: [], indices: [])
    private var displacedSphere = Mesh(positions: [], normals: [], indices: [])
    private var bare = Mesh(positions: [], normals: [], indices: [])

    /// An RGBA map authored per texel; pure math, no rng.
    private func map(_ texel: (Double, Double) -> (Double, Double, Double)) -> Image {
        let size = 128
        var bytes = [UInt8](repeating: 255, count: size * size * 4)
        let d = 1.0 / Double(size)
        for y in 0..<size {
            for x in 0..<size {
                let (r, g, b) = texel((Double(x) + 0.5) * d, (Double(y) + 0.5) * d)
                let i = (y * size + x) * 4
                bytes[i]     = UInt8(max(0, min(255, r * 255)))
                bytes[i + 1] = UInt8(max(0, min(255, g * 255)))
                bytes[i + 2] = UInt8(max(0, min(255, b * 255)))
            }
        }
        return Image(width: size, height: size, premultipliedRGBA: bytes)!
    }

    /// A wrapping crater field: 1 at the surface, dipping toward 0 in bowls.
    private func craters(_ u: Double, _ v: Double) -> Double {
        var h = 1.0
        for p in haltonPoints(count: 30, in: Rectangle(x: 0, y: 0, width: 1, height: 1)) {
            var dx = abs(u - p.x); dx = min(dx, 1 - dx)
            var dy = abs(v - p.y); dy = min(dy, 1 - dy)
            let d = (dx * dx + dy * dy).squareRoot() / 0.085
            if d < 1 {
                let bowl = 1 - (1 - d * d) * (1 - d * d)
                h = min(h, bowl)
            }
        }
        return h
    }

    override func setup() {
        let heightMap = map { u, v in
            let h = craters(u, v)
            return (h, h, h)
        }
        let colorMap = map { u, v in
            let t = 0.55 + 0.45 * craters(u, v)
            return (0.72 * t, 0.6 * t, 0.5 * t)
        }
        let base = Mesh.sphere(radius: 1, segments: 64, rings: 32)
        parallaxSphere = base.textured(colorMap).parallaxMapped(heightMap, scale: 0.07)
        displacedSphere = base.displaced(by: heightMap, scale: 0.13).textured(colorMap)
        bare = base.textured(colorMap)
    }

    override func draw() {
        background(Color(white: 0.05))
        camera(.orbiting(target: .zero, radius: 8.6, azimuth: 0.45, elevation: 0.12,
                         fieldOfView: .pi / 3.4))
        environment(.studio)
        directionalLight(Color(white: 0.9), direction: Vector3(-0.5, -0.6, -0.6))
        fill(.white)
        material(.dielectric(roughness: 0.75))
        for (mesh, x) in zip([parallaxSphere, displacedSphere, bare], [-2.4, 0.0, 2.4]) {
            withState { translate(x, 0.25, 0); drawMesh(mesh) }
        }
    }
}

private final class TriplanarScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    /// The vein field the maps derive from: thin dark seams over open stone,
    /// tiling both ways. Pure math, no rng.
    private func veinField(_ u: Double, _ v: Double) -> Double {
        let warp = 0.09 * sin(v * 2 * .tau) + 0.05 * sin(u * 3 * .tau + 1.7)
        let a = 0.5 + 0.5 * sin((u * 3 + warp) * .tau)
        let b = 0.5 + 0.5 * sin((v * 4 + 0.14 * sin(u * 2 * .tau) + 0.31) * .tau)
        return min(pow(a, 0.16), pow(b, 0.22))
    }

    private var stone = Image(width: 1, height: 1, color: .white)
    private var veins = Image(width: 1, height: 1, color: .white)

    override func setup() {
        let size = 128
        var color = [UInt8](repeating: 255, count: size * size * 4)
        var normal = [UInt8](repeating: 255, count: size * size * 4)
        let d = 1.0 / Double(size)
        for y in 0..<size {
            for x in 0..<size {
                let u = (Double(x) + 0.5) * d, v = (Double(y) + 0.5) * d
                let h = veinField(u, v)
                let t = 0.45 + 0.55 * h
                let i = (y * size + x) * 4
                color[i] = UInt8(214 * t); color[i + 1] = UInt8(196 * t); color[i + 2] = UInt8(168 * t)
                let dx = (veinField(u + d, v) - veinField(u - d, v)) / (2 * d) * 0.3
                let dy = (veinField(u, v + d) - veinField(u, v - d)) / (2 * d) * 0.3
                let len = (dx * dx + dy * dy + 1).squareRoot()
                normal[i] = UInt8((-dx / len * 0.5 + 0.5) * 255)
                normal[i + 1] = UInt8((dy / len * 0.5 + 0.5) * 255)
                normal[i + 2] = UInt8((1 / len * 0.5 + 0.5) * 255)
            }
        }
        stone = Image(width: size, height: size, premultipliedRGBA: color)!
        veins = Image(width: size, height: size, premultipliedRGBA: normal)!
    }

    override func draw() {
        background(Color(white: 0.05))
        camera(.orbiting(target: .zero, radius: 9, azimuth: 0.35, elevation: 0.18,
                         fieldOfView: .pi / 3.4))
        environment(.studio)
        directionalLight(Color(white: 0.9), direction: Vector3(-0.5, -0.6, -0.55))
        fill(.white)
        material(.dielectric(roughness: 0.65))
        // A no-uv marched skin, and two abutting boxes continuing one pattern.
        var balls = Metaballs()
        balls.add(at: Vector3(-0.5, 0, 0), radius: 1)
        balls.add(at: Vector3(0.7, 0.35, 0.2), radius: 0.75)
        withState {
            translate(-1.9, 0.3, 0)
            drawMesh(balls.mesh(resolution: 48)
                .triplanarTextured(stone, normal: veins, scale: 1.1))
        }
        withState {
            translate(2.1, -0.3, 0)
            for (w, y) in [(2.0, 0.0), (1.3, 0.85)] {
                withState {
                    translate(0, y, 0)
                    drawMesh(Mesh.box(width: w, height: 0.9, depth: 1.4)
                        .triplanarTextured(stone, normal: veins, scale: 1.1))
                }
            }
        }
    }
}

private final class DetailMapScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    private var base = Image(width: 1, height: 1, color: .white)
    private var baseBumps = Image(width: 1, height: 1, color: .white)
    private var grain = Image(width: 1, height: 1, color: .white)
    private var grainBumps = Image(width: 1, height: 1, color: .white)

    /// Broad blotches for the base, a fine deterministic speckle for the
    /// detail, and a normal map derived from each. Pure math, no rng.
    private func blotch(_ u: Double, _ v: Double) -> Double {
        0.5 + 0.25 * sin(u * 2 * .tau + 1.3) * sin(v * 2 * .tau)
            + 0.25 * sin((u + v) * 3 * .tau)
    }

    private func speckle(_ u: Double, _ v: Double) -> Double {
        let a = sin(u * 9 * .tau) * sin(v * 7 * .tau)
        let b = sin((u * 5 + v * 6) * .tau + 2.1)
        return 0.5 + 0.28 * a + 0.22 * b
    }

    private func makeMap(_ size: Int, field: (Double, Double) -> Double,
                         tint: (Double) -> (UInt8, UInt8, UInt8)) -> (Image, Image) {
        var color = [UInt8](repeating: 255, count: size * size * 4)
        var normal = [UInt8](repeating: 255, count: size * size * 4)
        let d = 1.0 / Double(size)
        for y in 0..<size {
            for x in 0..<size {
                let u = (Double(x) + 0.5) * d, v = (Double(y) + 0.5) * d
                let h = min(max(field(u, v), 0), 1)
                let i = (y * size + x) * 4
                let (r, g, b) = tint(h)
                color[i] = r; color[i + 1] = g; color[i + 2] = b
                let dx = (field(u + d, v) - field(u - d, v)) / (2 * d) * 0.2
                let dy = (field(u, v + d) - field(u, v - d)) / (2 * d) * 0.2
                let len = (dx * dx + dy * dy + 1).squareRoot()
                normal[i] = UInt8((-dx / len * 0.5 + 0.5) * 255)
                normal[i + 1] = UInt8((dy / len * 0.5 + 0.5) * 255)
                normal[i + 2] = UInt8((1 / len * 0.5 + 0.5) * 255)
            }
        }
        return (Image(width: size, height: size, premultipliedRGBA: color)!,
                Image(width: size, height: size, premultipliedRGBA: normal)!)
    }

    override func setup() {
        (base, baseBumps) = makeMap(128, field: blotch) { h in
            (UInt8(120 + 100 * h), UInt8(96 + 80 * h), UInt8(70 + 60 * h))
        }
        // The detail color map is data with 128 the neutral: speckle around it.
        (grain, grainBumps) = makeMap(64, field: speckle) { h in
            let v = UInt8(min(max(88 + 80 * h, 0), 255))
            return (v, v, v)
        }
    }

    override func draw() {
        background(Color(white: 0.05))
        camera(.orbiting(target: .zero, radius: 4.6, azimuth: 0.3, elevation: 0.12,
                         fieldOfView: .pi / 3.6))
        directionalLight(Color(white: 0.95), direction: Vector3(-0.6, -0.5, -0.6))
        ambientLight(Color(white: 0.12))
        fill(.white)
        let dressed = Mesh.sphere(radius: 1.05, segments: 48, rings: 24)
            .textured(base).normalMapped(baseBumps, scale: 0.8)
        withState {
            translate(-1.2, 0, 0)
            drawMesh(dressed)
        }
        withState {
            translate(1.2, 0, 0)
            drawMesh(dressed.detailMapped(grain, normal: grainBumps, scale: 7, strength: 0.9))
        }
    }
}

private final class DecalScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    private var roundel = Decal(Image(width: 1, height: 1, color: .white))!
    private var ring = Decal(Image(width: 1, height: 1, color: .white))!
    private var tag = Decal(Image(width: 1, height: 1, color: .white))!

    override func setup() {
        // A roundel (solid disc in two rings), a bare ring, and a striped tag,
        // all authored in pixels; the transparent surrounds stamp nothing.
        let size = 96
        func authored(_ paint: (Double, Double) -> (UInt8, UInt8, UInt8, UInt8)) -> Decal {
            var bytes = [UInt8](repeating: 0, count: size * size * 4)
            for y in 0..<size {
                for x in 0..<size {
                    let u = (Double(x) + 0.5) / Double(size) - 0.5
                    let v = (Double(y) + 0.5) / Double(size) - 0.5
                    let (r, g, b, a) = paint(u, v)
                    let i = (y * size + x) * 4
                    let k = Double(a) / 255
                    bytes[i] = UInt8(Double(r) * k); bytes[i + 1] = UInt8(Double(g) * k)
                    bytes[i + 2] = UInt8(Double(b) * k); bytes[i + 3] = a
                }
            }
            return Decal(Image(width: size, height: size, premultipliedRGBA: bytes)!)!
        }
        roundel = authored { u, v in
            let r = (u * u + v * v).squareRoot()
            if r > 0.48 { return (0, 0, 0, 0) }
            return r > 0.34 ? (200, 40, 40, 255)
                : (r > 0.2 ? (235, 225, 205, 255) : (40, 60, 140, 255))
        }
        ring = authored { u, v in
            let r = (u * u + v * v).squareRoot()
            return (r > 0.28 && r < 0.46) ? (250, 200, 40, 255) : (0, 0, 0, 0)
        }
        tag = authored { u, v in
            guard abs(u) < 0.45, abs(v) < 0.3 else { return (0, 0, 0, 0) }
            let stripe = Int(((u + v * 0.6) * 7).rounded(.down)) % 2 == 0
            return stripe ? (20, 20, 20, 255) : (240, 190, 40, 255)
        }
    }

    override func draw() {
        background(Color(white: 0.05))
        camera(.orbiting(target: Vector3(0, 0.3, 0), radius: 6.4, azimuth: 0.5,
                         elevation: 0.5, fieldOfView: .pi / 3.6))
        directionalLight(Color(white: 0.95), direction: Vector3(-0.4, -0.8, -0.4))
        ambientLight(Color(white: 0.14))
        fill(Color(white: 0.75))
        drawMesh(Mesh.plane(width: 6, depth: 6))
        withState {
            translate(0.7, 0.5, -0.4)
            drawMesh(Mesh.box(width: 1.4, height: 1, depth: 1.2))
        }
        // One box conforming over floor and crate at once; the crate's
        // vertical faces sit edge-on to the downward projection and fade.
        decal(roundel, at: Vector3(0, 0.4, 0.4), width: 2.4, depth: 2)
        // A half-opacity ring composited over the roundel, later in call order.
        decal(ring, at: Vector3(-0.7, 0.2, 0.9), width: 1.8, opacity: 0.5)
        // A tag stamped sideways onto the crate's front face, rolled a little.
        decal(tag, at: Vector3(0.6, 0.55, 0.25), direction: Vector3(0, 0, -1),
              width: 1.1, depth: 1.6, roll: 0.18)
    }
}

private final class CoatSheenScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.05))
        camera(.orbiting(target: .zero, radius: 7.2,
                         azimuth: 0.25, elevation: 0.15, fieldOfView: .pi / 3.4))
        environment(.studio)
        pointLight(.white, at: Vector3(3, 4, 5), intensity: 1.2)
        let red = Color(hue: 0.99, saturation: 0.82, brightness: 0.72)
        let blue = Color(hue: 0.62, saturation: 0.65, brightness: 0.45)
        var velvet = Material.felt
        velvet.sheenColor = Color(hue: 0.07, saturation: 0.9, brightness: 0.95)
        // Top row: coated red metal, its bare twin, piano-black lacquer. Bottom row:
        // white-sheen felt, its bare twin, two-tone velvet.
        let bodies: [(Color, Material, Double, Double)] = [
            (red, .carPaint(roughness: 0.45), -2.0, 1.05),
            (red, .metal(roughness: 0.45), 0, 1.05),
            (Color(white: 0.05), .lacquer, 2.0, 1.05),
            (blue, .felt, -2.0, -1.05),
            (blue, .dielectric(roughness: 0.9), 0, -1.05),
            (Color(hue: 0.99, saturation: 0.9, brightness: 0.3), velvet, 2.0, -1.05),
        ]
        for (c, m, x, y) in bodies {
            withState { translate(x, y, 0); fill(c); material(m); drawSphere(radius: 0.9) }
        }
    }
}

private final class SubsurfaceScatteringScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.05))
        camera(.orbiting(target: Vector3(0, 0.2, 0), radius: 7,
                         azimuth: 0.2, elevation: 0.12, fieldOfView: .pi / 3.6))
        directionalLight(.white, direction: Vector3(-1, -0.3, -0.4), intensity: 1.25)
        pointLight(Color(hex: 0xdfe8ff), at: Vector3(-3, 2.5, 3), intensity: 0.35)
        noStroke()
        // A skin sphere beside its bare twin (the diffusion is the only difference),
        // and a marble torus carrying a second profile in the same frame.
        fill(Color(red: 0.92, green: 0.72, blue: 0.62))
        withState { translate(-1.9, 0.35, 0); material(.skin(radius: 0.4)); drawSphere(radius: 1.0) }
        withState { translate(0, 0.35, 0); material(.dielectric(roughness: 0.45)); drawSphere(radius: 1.0) }
        withState {
            translate(2.0, 0.35, 0); fill(Color(white: 0.85))
            material(.marble(radius: 0.3))
            rotateX(0.9)
            drawTorus(radius: 0.75, tube: 0.38)
        }
        withState {
            translate(0, -0.85, 0); fill(Color(white: 0.4)); material(.roughPlastic)
            drawBox(width: 22, height: 0.3, depth: 14)
        }
    }
}

/// A thin slab, a deep slab, and a sphere, all skin, backlit by a directional
/// caster: the transmittance still (the thin body floods red, the deep one keeps
/// its rim, the sphere its crescent).
private final class SubsurfaceTransmittanceScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.04))
        camera(.orbiting(target: Vector3(0, 0.7, 0), radius: 8, azimuth: 0.1,
                         elevation: 0.08, fieldOfView: .pi / 4, near: 1, far: 30))
        directionalLight(.white, direction: Vector3(0.2, -0.25, 1), intensity: 1.4)
        castShadows()
        noStroke()
        fill(Color(red: 0.92, green: 0.72, blue: 0.62))
        material(.skin(radius: 0.12))
        withState { translate(-1.9, 0.9, 0); drawBox(width: 1.6, height: 2.0, depth: 0.18) }
        withState { translate(0.1, 0.9, 0); drawBox(width: 1.6, height: 2.0, depth: 1.6) }
        withState { translate(2.1, 0.35, 0.8); drawSphere(radius: 0.55) }
        withState {
            translate(0, -0.35, 0); fill(Color(white: 0.35)); material(.roughPlastic)
            drawBox(width: 22, height: 0.3, depth: 14)
        }
    }
}

private final class GlassRefractionScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x14171d))
        camera(.orbiting(target: Vector3(0, 0.8, 0), radius: 8,
                         azimuth: 0.15, elevation: 0.14,
                         fieldOfView: .pi / 4, near: 2, far: 24))
        environment(.studio.intensity(1.1))
        directionalLight(.white, direction: Vector3(-0.4, -1, -0.25), intensity: 0.7)
        rayTracedReflections()
        // The content the glass has to transmit: a floor and three colored pillars.
        withState {
            material(.dielectric(roughness: 0.8)); fill(Color(hex: 0x3a3f4c))
            translate(0, -0.55, 0); drawBox(width: 24, height: 1.0, depth: 14)
        }
        for (i, c) in [Color(hex: 0xe6533c), Color(hex: 0x4fb477), Color(hex: 0x3f7fd6)].enumerated() {
            withState {
                material(.dielectric(roughness: 0.6)); fill(c)
                translate((Double(i) - 1) * 1.8, 1.5, -2.6)
                drawBox(width: 1.2, height: 4.0, depth: 0.5)
            }
        }
        // A solid clear lens, a solid absorbing body, and a thin bubble in front.
        let bodies: [(Color, Material, Double)] = [
            (.white, .glass(thickness: 1.8), -2.0),
            (.white, .glass(thickness: 1.8, attenuationColor: Color(hex: 0x2e8f5b),
                            attenuationDistance: 1.2), 0),
            (Color(hex: 0xcfe4ff), .glass(), 2.0),
        ]
        for (c, m, x) in bodies {
            withState { translate(x, 0.9, 0.8); fill(c); material(m); drawSphere(radius: 0.9) }
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

/// The two low-discrepancy sequences dotted side by side (Halton left, Sobol
/// right) at a fixed count. Both are pure functions of the index, so the scene
/// carries no rng and no `time`: any change to either construction moves dots.
private final class LowDiscrepancyScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x11141C))
        noStroke()
        fill(Color(hex: 0xE8ECF4))
        let left = Rectangle(x: 8, y: 8, width: 116, height: 240)
        let right = Rectangle(x: 132, y: 8, width: 116, height: 240)
        for p in haltonPoints(count: 220, in: left) { drawCircle(center: p, radius: 1.8) }
        for p in sobolPoints(count: 220, in: right) { drawCircle(center: p, radius: 1.8) }
    }
}

/// A painted radial gradient rebuilt as a weighted-Voronoi stipple: dots pack
/// toward the dark center. Seeded and `time`-free, so it's deterministic.
private final class StippleScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private var dots: [Vector2] = []

    override func setup() {
        seed(7)
        let n = 64
        let image = Image(width: n, height: n, color: .white)
        for y in 0 ..< n {
            for x in 0 ..< n {
                let u = Double(x) / Double(n - 1) * 2 - 1
                let v = Double(y) / Double(n - 1) * 2 - 1
                let d = (u * u + v * v).squareRoot()
                image[x, y] = Color(white: clamp(d * 1.1, 0, 1))
            }
        }
        dots = stipple(image, count: 380, in: canvasRectangle.inset(by: 16), iterations: 12)
    }

    override func draw() {
        background(Color(hex: 0xF5F2EA))
        noStroke()
        fill(Color(hex: 0x1A1B26))
        for d in dots { drawCircle(center: d, radius: 2.2) }
    }
}

/// A painted radial gradient rendered as one continuous line (stipple plus
/// TSP tour). Seeded and `time`-free, so it's deterministic.
private final class SingleLineScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private var line = Contour([], closed: false)

    override func setup() {
        seed(7)
        let n = 64
        let image = Image(width: n, height: n, color: .white)
        for y in 0 ..< n {
            for x in 0 ..< n {
                let u = Double(x) / Double(n - 1) * 2 - 1
                let v = Double(y) / Double(n - 1) * 2 - 1
                let d = (u * u + v * v).squareRoot()
                image[x, y] = Color(white: clamp(d * 1.1, 0, 1))
            }
        }
        line = singleLine(of: image, points: 320, in: canvasRectangle.inset(by: 16),
                          iterations: 12)
    }

    override func draw() {
        background(Color(hex: 0xF5F2EA))
        noFill()
        stroke(Color(hex: 0x1A1B26))
        strokeWeight(1.4)
        drawPolyline(line.points, closed: line.isClosed)
    }
}

/// The same painted radial gradient joined by the minimum spanning tree.
/// Seeded and `time`-free, so it's deterministic.
private final class SpanningTreeScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private var chains: [Contour] = []

    override func setup() {
        seed(7)
        let n = 64
        let image = Image(width: n, height: n, color: .white)
        for y in 0 ..< n {
            for x in 0 ..< n {
                let u = Double(x) / Double(n - 1) * 2 - 1
                let v = Double(y) / Double(n - 1) * 2 - 1
                let d = (u * u + v * v).squareRoot()
                image[x, y] = Color(white: clamp(d * 1.1, 0, 1))
            }
        }
        chains = spanningTree(of: image, points: 320, in: canvasRectangle.inset(by: 16),
                              iterations: 12)
    }

    override func draw() {
        background(Color(hex: 0xF5F2EA))
        noFill()
        stroke(Color(hex: 0x1A1B26))
        strokeWeight(1.4)
        for chain in chains { drawPolyline(chain.points) }
    }
}

/// A two-blob metaball field's level curves beside the tone lines of a
/// painted gradient with a dark disk. No rng and no `time`, so it's
/// deterministic.
private final class IsolineScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0xF5F2EA))
        noFill()
        stroke(Color(hex: 0x1A1B26))
        strokeWeight(1.2)

        // Left: the metaball sum of two blobs, traced at rising levels; the
        // outer levels merge across the neck, the tightest splits in two.
        let left = Rectangle(x: 8, y: 8, width: 112, height: 240)
        let a = Vector2(64, 92), b = Vector2(72, 168)
        let field = isolines(at: [0.9, 1.4, 2.2, 3.5], in: left, resolution: 96) { p in
            2200 / max(p.distanceSquared(to: a), 1) + 2200 / max(p.distanceSquared(to: b), 1)
        }
        for group in field {
            for curve in group { drawPolyline(curve.points, closed: curve.isClosed) }
        }

        // Right: tone lines of a diagonal gradient carrying a dark disk, so
        // open chains end on the frame and rings wrap the disk.
        let n = 48
        let image = Image(width: n, height: n, color: .white)
        for y in 0 ..< n {
            for x in 0 ..< n {
                var tone = (Double(x) + Double(y)) / Double(2 * (n - 1))
                let d = dist(Double(x), Double(y), Double(n) * 0.62, Double(n) * 0.4)
                if d < Double(n) * 0.22 { tone = 0.08 }
                image[x, y] = Color(white: tone)
            }
        }
        let right = Rectangle(x: 136, y: 8, width: 112, height: 240)
        let tones = isolines(of: image, at: [0.35, 0.55, 0.75], in: right, resolution: 96)
        for group in tones {
            for curve in group { drawPolyline(curve.points, closed: curve.isClosed) }
        }
    }
}

/// A dotted ring plus an offshore cluster, outlined by all three hulls.
/// Seeded and no `time`, so it's deterministic.
private final class ConcaveHullScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private var scatter: [Vector2] = []

    override func setup() {
        seed(7)
        let hub = Vector2(112, 138)
        for band in 0 ..< 3 {
            let radius = 56.0 + Double(band) * 15
            let count = Int(radius * .tau / 15)
            for i in 0 ..< count {
                let angle = Double(i) / Double(count) * .tau + random(-0.05, 0.05)
                let r = radius + random(-5, 5)
                scatter.append(hub + Vector2(cos(angle), sin(angle)) * r)
            }
        }
        let island = Vector2(210, 52)
        for _ in 0 ..< 16 {
            scatter.append(island + ring(innerRadius: 0, outerRadius: 22))
        }
    }

    override func draw() {
        background(Color(hex: 0x101318))
        noStroke()
        fill(Color(hex: 0x232E44))
        for islandShape in alphaShape(of: scatter, alpha: 24) {
            drawShape(islandShape)
        }
        noFill()
        stroke(Color(hex: 0x4A5468))
        strokeWeight(1)
        drawPolygon(convexHull(of: scatter))
        stroke(Color(hex: 0xE8B44A))
        strokeWeight(1.6)
        drawPolygon(concaveHull(of: scatter, concavity: 0.6))
        noStroke()
        fill(Color(hex: 0x8B97AB))
        drawCircles(scatter, radius: 1.6)
    }
}

/// A wobbly blob with an off-center hole, reduced to its skeleton with the
/// inscribed circles the axis carries. Seeded and no `time`, so it's
/// deterministic.
private final class MedialAxisScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private var blob = Shape(contours: [])
    private var skeleton = MedialAxis(branches: [])

    override func setup() {
        seed(9)
        let center = Vector2(126, 130)
        let outer = (0 ..< 40).map { i in
            let angle = Double(i) / 40 * .tau
            let r = 92 + signedNoise(Double(i) * 0.35) * 18
            return center + Vector2(cos(angle), sin(angle)) * r
        }
        let hole = (0 ..< 24).map { i in
            let angle = Double(i) / 24 * .tau
            let r = 26 + random(-2, 2)
            return center + Vector2(34, -10) + Vector2(cos(angle), sin(angle)) * r
        }
        blob = Shape(outer: outer, holes: [hole])
        skeleton = medialAxis(of: blob, spacing: 3, prune: 10)
    }

    override func draw() {
        background(Color(hex: 0xF5F2EA))
        noFill()
        stroke(Color(hex: 0x1A1B26).withAlpha(0.35))
        strokeWeight(1)
        drawShape(blob)
        stroke(Color(hex: 0x1A1B26))
        strokeWeight(1.6)
        for branch in skeleton.branches {
            drawPolyline(branch.points, closed: branch.isClosed)
        }
        strokeWeight(0.6)
        for branch in skeleton.branches {
            for (i, pair) in zip(branch.points, branch.radii).enumerated()
            where pair.1 > 5 && i % 5 == 0 {
                drawCircle(center: pair.0, radius: pair.1)
            }
        }
    }
}

/// A seeded scale-free web settled to a standstill by the force-directed
/// layout, drawn through `drawGraph`. Seeded and no `time`, so it's
/// deterministic.
private final class ForceGraphScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private var layout: ForceLayout?

    override func setup() {
        var rng = SplitMix64(seed: 11)
        var edges: [(Int, Int)] = [(0, 1), (1, 2), (2, 0)]
        var stubs = [0, 1, 1, 2, 2, 0]
        for i in 3 ..< 42 {
            let parent = stubs[Int(Double.random(in: 0 ..< 1, using: &rng) * Double(stubs.count))]
            edges.append((i, parent))
            stubs.append(i)
            stubs.append(parent)
            if Double.random(in: 0 ..< 1, using: &rng) < 0.3 {
                let second = stubs[Int(Double.random(in: 0 ..< 1, using: &rng) * Double(stubs.count))]
                if second != i, second != parent {
                    edges.append((i, second))
                    stubs.append(i)
                    stubs.append(second)
                }
            }
        }
        let settled = ForceLayout(count: 42, edges: edges,
                                  in: canvasRectangle.inset(by: 20), seed: 11)
        settled.idealDistance *= 1.5
        settled.settle()
        layout = settled
    }

    override func draw() {
        guard let layout else { return }
        background(Color(hex: 0xF5F2EA))
        stroke(Color(hex: 0x1A1B26).withAlpha(0.6))
        strokeWeight(0.9)
        fill(Color(hex: 0x1A1B26))
        drawGraph(layout, nodeRadius: 3)
    }
}

/// A lobed blob with an off-center hole carrying its straight skeleton and
/// a fixed ladder of mitered insets. Seeded and no `time`, so it's
/// deterministic.
private final class StraightSkeletonScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private var blob = Shape(contours: [])
    private var skeleton = StraightSkeleton(arcs: [], faces: [], maxInset: 0)

    override func setup() {
        seed(9)
        let center = Vector2(128, 126)
        let outer = (0 ..< 30).map { i in
            let u = Double(i) / 30
            let angle = u * .tau
            let r = 88 + sin(angle * 3) * 16 + signedNoise(5, loop: u, radius: 1.4) * 10
            return center + Vector2(cos(angle), sin(angle)) * r
        }
        let hole = (0 ..< 16).map { i in
            let angle = Double(i) / 16 * .tau
            let r = 20 + random(-2, 2)
            return center + Vector2(30, -14) + Vector2(cos(angle), sin(angle)) * r
        }
        blob = Shape(outer: outer, holes: [hole])
        skeleton = straightSkeleton(of: blob)
    }

    override func draw() {
        background(Color(hex: 0xF5F2EA))
        noFill()
        stroke(Color(hex: 0x1A1B26).withAlpha(0.55))
        strokeWeight(0.8)
        for step in 1 ..< 6 {
            drawShape(skeleton.inset(by: skeleton.maxInset * Double(step) / 6))
        }
        strokeWeight(0.6)
        stroke(Color(hex: 0x1A1B26).withAlpha(0.3))
        for arc in skeleton.arcs where arc.startDistance == 0 {
            drawLine(arc.start, arc.end)
        }
        strokeWeight(1.4)
        stroke(Color(hex: 0xB44A28))
        for arc in skeleton.arcs where arc.startDistance > 0 {
            drawLine(arc.start, arc.end)
        }
        stroke(Color(hex: 0x1A1B26))
        strokeWeight(1.4)
        drawShape(blob)
    }
}

/// A marbled paper from fixed operations (no rng): bull's-eye drops, a comb,
/// a tine pull, and a vortex. No `time`, so it's deterministic.
private final class MarblingScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private var bath = Marbling()

    override func setup() {
        bath = Marbling(spacing: 2)
        let eye = Vector2(118, 122)
        for ring in 0 ..< 8 {
            bath.drop(at: eye, radius: 100 - Double(ring) * 12,
                      color: ring.isMultiple(of: 2)
                          ? Color(hex: 0x1F2A44) : Color(hex: 0xEFE7D6))
        }
        bath.drop(at: Vector2(205, 60), radius: 26, color: Color(hex: 0xA43B2A))
        bath.drop(at: Vector2(60, 205), radius: 22, color: Color(hex: 0xC8912F))
        bath.comb(through: Vector2(0, 128), direction: .unitY,
                  spacing: 48, strength: 60, falloff: 12)
        bath.tine(through: Vector2(128, 0), direction: Vector2(0.2, 1),
                  strength: 40, falloff: 24)
        bath.swirl(at: Vector2(178, 178), strength: 140, falloff: 44)
    }

    override func draw() {
        background(Color(hex: 0xEFE7D6))
        noStroke()
        drawMarbling(bath)
    }
}

/// Two overlapping watercolor pools with interleaved layers, seeded through
/// a local generator in `setup()`. No `time`, so it's deterministic.
private final class WatercolorScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private var sheets: [(Shape, Color)] = []

    override func setup() {
        var rng = SplitMix64(seed: 11)
        let pools = [
            (Watercolor(around: Vector2(108, 112), radius: 62, using: &rng),
             Color(hex: 0x2B5D8A)),
            (Watercolor(around: Vector2(152, 148), radius: 54, using: &rng),
             Color(hex: 0xB0413E)),
        ]
        sheets = []
        for _ in 0 ..< 7 {
            for (pool, color) in pools {
                for _ in 0 ..< 2 {
                    sheets.append((pool.layerShape(using: &rng),
                                   color.withAlpha(0.07)))
                }
            }
        }
    }

    override func draw() {
        background(Color(hex: 0xF7F3E8))
        noStroke()
        for (shape, color) in sheets {
            fill(color)
            drawShape(shape)
        }
    }
}

/// A painted diagonal gradient with a bright disk, rebuilt as a glyph mosaic
/// in the bundled bitmap font. No rng and no `time`, so it's deterministic.
private final class GlyphMosaicScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.black)
        let n = 64
        let image = Image(width: n, height: n, color: .black)
        for y in 0 ..< n {
            for x in 0 ..< n {
                let u = Double(x) / Double(n - 1)
                let v = Double(y) / Double(n - 1)
                var tone = (u + (1 - v)) / 2 * 0.85
                let du = u - 0.35, dv = v - 0.4
                if (du * du + dv * dv).squareRoot() < 0.18 { tone = 0.95 }
                image[x, y] = Color(white: tone)
            }
        }
        textFont(BitmapFont.builtin)
        fill(.white)
        drawGlyphMosaic(image, columns: 20, in: canvasRectangle.inset(by: 8))
    }
}

/// A painted tonal study screened as vector halftone dots, the classic
/// reading beside the inverted one, both on a rotated screen. No rng and no
/// `time`, so it's deterministic.
private final class ColorVisionScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    private let chart = Palette([Color(hex: 0x1F77B4), Color(hex: 0xFF7F0E), Color(hex: 0x2CA02C),
                                 Color(hex: 0xD62728), Color(hex: 0x9467BD), Color(hex: 0x8C564B)])

    private let views: [ColorVision] = [.normal, .protanopia, .deuteranopia, .tritanopia]

    override func draw() {
        background(Color(white: 0.95))
        noStroke()

        // Top half: the CPU call, one column per kind, both palettes.
        for (column, vision) in views.enumerated() {
            let x = 8.0 + Double(column) * 62
            strip(chart, vision: vision, x: x, y: 8, width: 26, height: 110)
            strip(.colorblindSafe, vision: vision, x: x + 30, y: 8, width: 26, height: 110)
        }

        // Bottom half: the same strip through the GPU filter, drawn into a layer
        // per kind so one frame holds both paths.
        for (column, vision) in views.enumerated() {
            let x = 8.0 + Double(column) * 62
            let layer = renderTarget()
            withTarget(layer) {
                noStroke()
                strip(chart, vision: .normal, x: x, y: 132, width: 26, height: 110)
                strip(.colorblindSafe, vision: .normal, x: x + 30, y: 132, width: 26, height: 110)
            }
            drawImage(layer.filtered(.colorVision(vision)).image, 0, 0)
        }
    }

    private func strip(_ palette: Palette, vision: ColorVision, x: Double, y: Double,
                       width: Double, height: Double) {
        let size = height / Double(palette.count)
        for (i, color) in palette.colors.enumerated() {
            fill(color.simulated(vision))
            drawRect(x, y + Double(i) * size, width, size - 1)
        }
    }
}

private final class HalftoneScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.93))
        let n = 64
        let image = Image(width: n, height: n, color: .white)
        for y in 0 ..< n {
            for x in 0 ..< n {
                let u = Double(x) / Double(n - 1)
                let v = Double(y) / Double(n - 1)
                var tone = 0.15 + 0.75 * ((u + (1 - v)) / 2)
                let da = ((u - 0.32) * (u - 0.32) + (v - 0.34) * (v - 0.34)).squareRoot()
                if da < 0.2 { tone = 0.01 }   // solid ink: the corner-reaching cap
                let db = ((u - 0.72) * (u - 0.72) + (v - 0.72) * (v - 0.72)).squareRoot()
                if db < 0.16 { tone = 0.995 } // bare paper: the printable-dot cutoff
                image[x, y] = Color(white: tone)
            }
        }
        noStroke()
        let left = Rectangle(x: 6, y: 66, width: 118, height: 124)
        fill(Color(white: 0.12))
        drawHalftone(image, pitch: 9, angle: 0.35, in: left)

        let right = Rectangle(x: 132, y: 66, width: 118, height: 124)
        fill(Color(white: 0.1))
        drawRect(right.x, right.y, right.width, right.height)
        fill(Color(white: 0.95))
        drawHalftone(image, pitch: 9, angle: 0.35, in: right, inverted: true)
    }
}

/// A painted tonal study poured through the luminance melt at a fixed phase.
/// No rng and no `time`, so it's deterministic.
private final class LuminanceMeltScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.black)
        let n = 64
        let image = Image(width: n, height: n, color: .black)
        for y in 0 ..< n {
            for x in 0 ..< n {
                let u = Double(x) / Double(n - 1)
                let v = Double(y) / Double(n - 1)
                var tone = 0.15 + 0.55 * (1 - v) + 0.15 * u
                let d = ((u - 0.6) * (u - 0.6) + (v - 0.35) * (v - 0.35)).squareRoot()
                if d < 0.18 { tone = 0.97 }
                image[x, y] = Color(white: min(tone, 1))
            }
        }
        let layer = renderTarget()
        withTarget(layer) { drawImage(image, in: canvasRectangle) }
        drawImage(layer.filtered(.melt(phase: 3)).image, in: canvasRectangle)
    }
}

/// A painted noisy gradient with dark and bright guard bands, pixel-sorted on
/// both axes inside a midtone window, at 1:1 pixels. Seeded paint and no
/// `time`, so it's deterministic.
private final class PixelSortScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private var sorted: Image?

    override func setup() {
        seed(11)
        let n = 256
        let image = Image(width: n, height: n, color: .black)
        for y in 0 ..< n {
            for x in 0 ..< n {
                let u = Double(x) / Double(n - 1)
                let v = Double(y) / Double(n - 1)
                var tone = clamp(v * 0.9 + signedNoise(u * 6, v * 6) * 0.15, 0, 1)
                if v < 0.12 { tone = 0.04 }          // dark guard band
                if v > 0.9 { tone = 0.96 }           // bright guard band
                image[x, y] = Color(hue: 0.6 + tone * 0.25, saturation: 0.5,
                                    brightness: tone)
            }
        }
        sorted = image.pixelSorted(.vertical, threshold: 0.2 ... 0.8)
                      .pixelSorted(.horizontal, threshold: 0.2 ... 0.8)
    }

    override func draw() {
        background(.black)
        if let sorted { drawImage(sorted, in: canvasRectangle) }
    }
}

/// Twelve painted frames of a falling bar, read back through a left-to-right
/// slit-scan delay. No rng and no `time`, so it's deterministic.
private final class SlitScanScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private var warped: Image?

    override func setup() {
        let history = SlitScan(frames: 12)
        let n = 128
        for frame in 0 ..< 12 {
            let source = Image(width: n, height: n, color: .black)
            let barTop = Int(Double(frame) / 12 * Double(n - 20))
            for y in barTop ..< min(barTop + 20, n) {
                for x in 0 ..< n {
                    source[x, y] = Color(hue: Double(frame) / 12,
                                         saturation: 0.6, brightness: 0.9)
                }
            }
            history.push(source)
        }
        warped = history.image(delay: { uv in uv.x })
    }

    override func draw() {
        background(.black)
        if let warped { drawImage(warped, in: canvasRectangle) }
    }
}

/// A seeded Lévy flight polyline scaled to fit the canvas. Seeded and
/// `time`-free, so it's deterministic.
private final class LevyFlightScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0E1116))
        seed(4)
        let raw = levyFlight(from: Vector2(0, 0), steps: 400, minStep: 3, maxStep: 220, exponent: 1.8)
        var minX = raw[0].x, maxX = raw[0].x, minY = raw[0].y, maxY = raw[0].y
        for p in raw {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let spanX: Double = max(maxX - minX, 1e-9)
        let spanY: Double = max(maxY - minY, 1e-9)
        let s: Double = min(216 / spanX, 216 / spanY)
        let fitted = raw.map { Vector2(20 + ($0.x - minX) * s, 20 + ($0.y - minY) * s) }
        noFill()
        stroke(Color(hex: 0x9FC7E8))
        strokeWeight(1)
        drawPolyline(fitted)
    }
}

/// A seeded self-avoiding walk drawn as one stroke with hue along its length.
/// Seeded and `time`-free, so it's deterministic.
private final class SelfAvoidingWalkScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x14161D))
        seed(12)
        let path = selfAvoidingWalk(in: canvasRectangle.inset(by: 16), cellSize: 16)
        strokeCap(.round)
        strokeWeight(6)
        let ramp = Ramp([Color(hex: 0x2C7DA0), Color(hex: 0xE9C46A), Color(hex: 0xD1495B)])
        for i in 1 ..< path.count {
            stroke(ramp.color(at: Double(i) / Double(max(path.count - 1, 1))))
            drawLine(path[i - 1], path[i])
        }
    }
}

/// A crack-growth field advanced several hundred ticks in one frame, every
/// mark drawn: the faint crack points plus each tick's one-sided grain wash.
/// The helper is seeded and stepped in one call, so the geometry, the washes,
/// and the rng call order are all pinned. No `time`, so it is deterministic.
private final class CrackGrowthScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0xF7F3EA))
        noStroke()
        let inks = [Color(hex: 0x1F5673), Color(hex: 0xC26D3F),
                    Color(hex: 0x8A9B68), Color(hex: 0x71486E)]
        let field = CrackGrowth(width: 256, height: 256, cracks: 3,
                                seedAngles: 12, maxCracks: 24, seed: 9)
        for mark in field.step(500) {
            let ink = inks[mark.crack % inks.count]
            for grain in CrackGrowth.grains(from: mark.point, to: mark.washExtent,
                                            gain: mark.gain, count: 24) {
                fill(ink.withAlpha(grain.alpha))
                drawPoint(grain.position)
            }
            fill(Color.black.withAlpha(0.33))
            drawPoint(mark.point)
        }
    }
}

/// A painted crescent wound as string art in one frame: the greedy chord
/// choice pays its ink down as it goes, so the whole winding is one
/// deterministic pass. No rng and no `time`, so it is deterministic.
/// A seeded percolation grid just past the threshold: pins the fill, the
/// union-find labels, the spanning test, and the outline tracer.
private final class PercolationScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.05))
        var rng = SplitMix64(seed: 17)
        let grid = Percolation(columns: 40, rows: 40, probability: 0.62, using: &rng)
        let area = Rectangle(x: 8, y: 8, width: 240, height: 240)
        let spanning = grid.spanningClusterIndex

        noStroke()
        for k in 0 ..< grid.clusterCount where k != spanning {
            let t = min(Double(grid.clusterSizes[k]) / 150, 1)
            fill(Color.mix(Color(hex: 0x24506B), Color(hex: 0x88C7E8), t: t))
            for cell in grid.cellRects(of: k, in: area) { drawRect(cell) }
        }
        if let spanning {
            fill(Color(hex: 0xE8B44A))
            for cell in grid.cellRects(of: spanning, in: area) { drawRect(cell) }
            stroke(Color(hex: 0xF2E8DC))
            strokeWeight(1.5)
            noFill()
            for loop in grid.outlines(of: spanning, in: area) {
                drawPolygon(loop.points)
            }
        }
        noLoop()
    }
}

private final class StringArtScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0xF6F1E7))
        let art = StringArt(of: paint(), center: Vector2(128, 128), radius: 116,
                            pins: 100, chords: 400, ink: 0.12, resolution: 128)
        noFill()
        stroke(Color(hex: 0x20222B).withAlpha(0.4))
        strokeWeight(1)
        for chord in art.step(400) {
            drawLine(chord.from, chord.to)
        }
    }

    /// A small crescent on white: a disk with a second disk bitten out of it.
    private func paint() -> Image {
        let n = 96
        let image = Image(width: n, height: n, color: .white)
        for y in 0 ..< n {
            for x in 0 ..< n {
                let u = (Double(x) + 0.5) / Double(n) * 2 - 1
                let v = (Double(y) + 0.5) / Double(n) * 2 - 1
                let disk = dist(u, v, 0, 0)
                guard disk < 0.68 else { continue }
                let inDisk = 1 - smoothstep(0.62, 0.68, disk)
                let inBite = smoothstep(0.5, 0.6, dist(u, v, 0.3, -0.24))
                image[x, y] = Color(white: 0.85 - 0.7 * inDisk * inBite)
            }
        }
        return image
    }
}

/// One gradient reduced to three colors four ways, drawn 1:1 so a dithered pixel
/// is a canvas pixel. Top row: plain nearest-color quantization (bands) beside an
/// ordered Bayer dither. Bottom row: a blue-noise dither beside Floyd-Steinberg.
/// No rng and no `time`, so it is deterministic.
private final class DitherScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    private let palette = Palette(Color(hex: 0x14203A), Color(hex: 0xBF3100),
                                  Color(hex: 0xF7DFA5))
    private var panels: [Image] = []

    override func setup() {
        noStroke()
        let source = paint()
        panels = [source.dithered(.none, to: palette),
                  source.dithered(.ordered(size: 4), to: palette),
                  source.dithered(.blueNoise, to: palette),
                  source.dithered(.floydSteinberg, to: palette)]
    }

    override func draw() {
        background(.black)
        for (i, panel) in panels.enumerated() {
            drawImage(panel, in: Rectangle(x: Double(i % 2) * 128, y: Double(i / 2) * 128,
                                           width: 128, height: 128))
        }
    }

    private func paint() -> Image {
        let n = 128
        let image = Image(width: n, height: n)
        for y in 0..<n {
            for x in 0..<n {
                let u = Double(x) / Double(n - 1)
                let v = Double(y) / Double(n - 1)
                let t = clamp(1 - dist(u, v, 0.3, 0.75) * 1.3, 0, 1)
                image[x, y] = t < 0.5
                    ? Color.mix(palette[0], palette[1], t: t * 2)
                    : Color.mix(palette[1], palette[2], t: (t - 0.5) * 2)
            }
        }
        return image
    }
}

/// A two-ink artwork separated into spot-color printing masters, four panels
/// at 1:1: the artwork (top-left), its overprint preview screened through the
/// rotated round-dot halftone (top-right), and the two grayscale masters
/// below. Pins the separation search (coverages found under the linear-light
/// overprint model, judged in OKLab), the preview reconstruction from the
/// masters, the per-layer screen angles, and the minimum-dot highlight
/// cutoff. No rng and no `time`, so it is deterministic.
private final class PrintSeparationScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    private var panels: [Image] = []

    override func setup() {
        let source = paint()
        let separation = source.separated(into: [.fluorescentPink, .blue])
        panels = [source,
                  separation.halftoned(pitch: 5).preview(),
                  separation.layers[0].master,
                  separation.layers[1].master]
    }

    override func draw() {
        background(.black)
        for (i, panel) in panels.enumerated() {
            drawImage(panel, in: Rectangle(x: Double(i % 2) * 128, y: Double(i / 2) * 128,
                                           width: 128, height: 128))
        }
    }

    /// A pink wash meeting a blue disk: gradients exercise partial coverage,
    /// the overlap exercises the two-ink mix, and the corners stay bare paper.
    private func paint() -> Image {
        let n = 128
        let image = Image(width: n, height: n)
        let pink = Ink.fluorescentPink.color
        let blue = Ink.blue.color
        for y in 0..<n {
            for x in 0..<n {
                let u = Double(x) / Double(n - 1)
                let v = Double(y) / Double(n - 1)
                let wash = clamp(1.2 - (u + v), 0, 1)
                let disk = (1 - smoothstep(0.30, 0.34, dist(u, v, 0.62, 0.42))) * 0.9
                var c = Color.white
                c = Color(red: c.red * (1 - wash + wash * pink.red),
                          green: c.green * (1 - wash + wash * pink.green),
                          blue: c.blue * (1 - wash + wash * pink.blue))
                c = Color(red: c.red * (1 - disk + disk * blue.red),
                          green: c.green * (1 - disk + disk * blue.green),
                          blue: c.blue * (1 - disk + disk * blue.blue))
                image[x, y] = c
            }
        }
        return image
    }
}

/// A Truchet tiling with both built-in tiles — arc tiles in the top half,
/// diagonal tiles in the bottom — exercising both tile geometries and the
/// cross-cell connectivity (arcs meeting at shared edge midpoints, diagonals at
/// corners). Seeded and `time`-free, so it's deterministic.
/// Both Penrose variants side by side with their matching-rule arcs: pins the
/// two deflations, the half-tile merge, and the arc continuity constants.
private final class PenroseScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x14101E))
        noStroke()

        let left = Rectangle(x: 0, y: 0, width: 128, height: 256)
        let right = Rectangle(x: 128, y: 0, width: 128, height: 256)

        for (bounds, variant) in [(left, Penrose.Variant.kitesAndDarts),
                                  (right, .rhombs)] {
            let tiles = Penrose.tiles(variant, in: bounds, tileEdge: 26)
            noStroke()
            for tile in tiles {
                switch tile.kind {
                case .kite, .thick: fill(Color(hex: 0x342A58))
                case .dart, .thin: fill(Color(hex: 0x181129))
                }
                drawShape(tile.shape)
            }
            noFill()
            strokeWeight(1.5)
            for tile in tiles {
                for (i, arc) in tile.arcs.enumerated() {
                    stroke(i == 0 ? Color(hex: 0xF2A65A) : Color(hex: 0x2EC4B6))
                    drawPolyline(arc.points, closed: false)
                }
            }
        }
    }
}

/// A Wang tiling from the complete two-color set in the classic quadrant
/// rendering: pins the scanline fill and its rng order.
private final class WangTilesScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0E1116))
        seed(5)
        noStroke()
        if let tiling = wangTiling(WangTiling.completeSet(colors: 2),
                                   columns: 8, rows: 8) {
            drawWangTiling(tiling, colors: [Color(hex: 0x14213D), Color(hex: 0xFCA311)])
        }
    }
}

/// Hex-cell strapwork plus the girih-tile flower: pins the ray inference,
/// cross-tile continuity, and edge-to-edge girih tile placement.
private final class GirihScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x101418))
        noFill()
        strokeCap(.round)

        let expanded = Rectangle(center: Vector2(128, 128), width: 340, height: 340)
        let hexes = HexGrid(in: expanded, columns: 6, rows: 5).cells.map(\.corners)
        stroke(Color(hex: 0x2EC4B6).withAlpha(0.8))
        strokeWeight(1.5)
        drawGirih(over: hexes, angle: 60)

        let decagon = Girih.Tile.decagon.points(edge: 13, at: Vector2(128, 128))
        var flower = [decagon]
        for i in decagon.indices {
            let p = decagon[i], q = decagon[(i + 1) % decagon.count]
            flower.append(Girih.Tile.pentagon.points(onEdge: q, p))
        }
        fill(Color(hex: 0x101418))
        noStroke()
        for tile in flower { drawPolygon(tile) }
        noFill()
        stroke(Color(hex: 0xFCA311))
        strokeWeight(2)
        drawGirih(over: flower, angle: 54)
    }
}

/// A curved-edge spectre patch colored by metatile: pins the substitution
/// system, the bounds fit, and the chiral edge bumps.
private final class SpectreScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0F1214))
        strokeWeight(1)
        stroke(Color(hex: 0x0F1214))
        for tile in spectreTiling(tileEdge: 13, curve: 0.5) {
            if tile.isOdd {
                fill(Color(hex: 0xF6511D))
            } else {
                switch tile.metatile {
                case .gamma: fill(Color(hex: 0x35544F))
                case .delta, .theta, .lambda: fill(Color(hex: 0x1C2B2D))
                case .xi, .pi: fill(Color(hex: 0x24403D))
                case .sigma, .phi, .psi: fill(Color(hex: 0x2C4A45))
                }
            }
            drawShape(tile.shape)
        }
    }
}

/// A hitomezashi stitch design: the two-tone parity fill underneath, the dash
/// line-work over it, both faces of one seeded design so their agreement (a
/// tone boundary exactly under every stitch) is pinned as pixels.
private final class HitomezashiScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x101A33))
        seed(11)
        let design = hitomezashi(in: Rectangle(x: 16, y: 16, width: 224, height: 224),
                                 columns: 10, rows: 10)

        noStroke()
        for (cell, tone) in zip(design.grid.cells, design.parities) {
            fill(tone ? Color(hex: 0x2C4A7F) : Color(hex: 0x18264A))
            drawRect(cell.frame)
        }

        stroke(Color(hex: 0xF2E9DC))
        strokeWeight(3)
        strokeCap(.round)
        for dash in design.stitches {
            drawPolyline(dash.points, closed: false)
        }
    }
}

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

/// Four parametric L-systems in a 2x2, one per thing carrying numbers buys:
/// fractional lengths, a counter the turtle ignores, a width per branch, and
/// weighted rules. Seeded and `time`-free, so it's deterministic.
private final class ParametricLSystemScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0E1013))
        seed(11)
        noFill()
        strokeCap(.round)
        strokeJoin(.round)

        let tiles: [(ParametricLSystem, Int, Rectangle, UInt32)] = [
            (.triangleCurve, 5, Rectangle(x: 0, y: 0, width: 128, height: 128), 0x7EC8E3),
            (.compoundLeaf, 14, Rectangle(x: 128, y: 0, width: 128, height: 128), 0x77DD9B),
            (.randomBranch, 8, Rectangle(x: 0, y: 128, width: 128, height: 128), 0xD8E06E),
        ]
        strokeWeight(0.9)
        for (system, iterations, frame, hex) in tiles {
            stroke(Color(hex: hex))
            for c in lSystem(system, iterations: iterations, in: frame, padding: 8) {
                drawPolyline(c.points, closed: false)
            }
        }

        // The tapered tree carries a width at every point, so it draws as marks
        // and `strokeWeight` sets the trunk rather than the whole line.
        stroke(Color(hex: 0xE8A87C))
        strokeWeight(5)
        let frame = Rectangle(x: 128, y: 128, width: 128, height: 128)
        for mark in lSystemMarks(.taperedTree(), iterations: 9, in: frame, padding: 8) {
            drawMark(mark)
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

private final class MeanderScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    private let river = Meander.line(from: Vector2(-170, 150),
                                     to: Vector2(280, 115),
                                     seed: 7, width: 9, recordEvery: 20)

    override func draw() {
        river.step(2)
        background(Color(hex: 0xF2ECDD))
        noFill()
        strokeWeight(river.width * 0.7)
        for (index, scar) in river.scars.enumerated() {
            let recency = Double(index + 1) / Double(river.scars.count)
            stroke(Color(hex: 0xC26D3F).withAlpha(0.1 + 0.2 * recency))
            drawPolyline(scar)
        }
        stroke(Color(hex: 0x7FA8C9).withAlpha(0.8))
        strokeWeight(river.width * 0.8)
        for oxbow in river.oxbows {
            drawPolyline(oxbow.points)
        }
        stroke(Color(hex: 0x2C4A6E))
        strokeWeight(river.width)
        drawPolyline(river.centerline)
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

/// A texture synthesized from a small authored sample by the overlapping model.
/// Pins pattern extraction, the overlap rule, propagation, and the read-out in
/// one picture: every 3x3 square of the result is one the sample held. Drawn a
/// pixel at a time (`drawImage` would smooth it), seeded and `time`-free, so
/// it's deterministic.
private final class TextureSynthesisScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    private static let rows = [
        "................",
        "..######..####..",
        "..#....#..#..#..",
        "..#....####..#..",
        "..#..........#..",
        "..#..####....#..",
        "..####..#..###..",
        "........#..#....",
        "..#######..#....",
        "..#.....#..#....",
        "..#.....####....",
        "..#######.......",
        "................",
        "..####..######..",
        "..#..#..#....#..",
        "..#..####....#..",
    ]

    override func draw() {
        background(Color(hex: 0x0E1116))
        seed(4)

        let sample = Image(width: 16, height: 16)
        for (y, row) in Self.rows.enumerated() {
            for (x, ch) in row.enumerated() {
                sample[x, y] = Color(hex: ch == "#" ? 0x8FB8DE : 0x11151C)
            }
        }
        guard let texture = wfc(from: sample, width: 32, height: 32, patternSize: 3) else { return }

        let cell = 232.0 / 32
        noStroke()
        for y in 0 ..< texture.height {
            for x in 0 ..< texture.width {
                fill(texture[x, y])
                drawRect(corner: Vector2(12 + Double(x) * cell, 12 + Double(y) * cell),
                         width: cell, height: cell)
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

/// The classic-curve builders on one sheet, one per grid cell: Lissajous,
/// whole and rational roses, both trochoids, a squircle superellipse over a
/// pinched one, a 7-lobe supershape, a phyllotaxis scatter, and a spiky star
/// smoothed by Chaikin corner cutting over its raw outline. Pure closed
/// forms with no rng and no time, so the sheet is deterministic.
private final class ClassicCurvesScene: Sketch {
    override var canvasSize: CanvasSize { .square(384) }

    override func draw() {
        background(Color(hex: 0x101318))
        noFill()
        strokeWeight(1.5)

        let cells = Grid(in: bounds, columns: 4, rows: 2, padding: .all(14)).cells
        let radius = 0.42 * min(cells[0].frame.width, cells[0].frame.height)

        withState {
            translate(cells[0].center.x, cells[0].center.y)
            stroke(Color(hex: 0x2EC4B6))
            drawPolyline(lissajous(a: 3, b: 2, width: 2 * radius).points, closed: true)
        }
        withState {
            translate(cells[1].center.x, cells[1].center.y)
            stroke(Color(hex: 0xF2C14E))
            drawPolyline(rose(n: 5, radius: radius).points, closed: true)
            stroke(Color(hex: 0xE86A5B))
            drawPolyline(rose(n: 7, d: 3, radius: radius * 0.55).points, closed: true)
        }
        withState {
            translate(cells[2].center.x, cells[2].center.y)
            stroke(Color(hex: 0x8E7CF2))
            let s = radius / 4.4
            drawPolyline(hypotrochoid(ring: 5, wheel: 3, pen: 2.4).points.map { $0 * s },
                         closed: true)
        }
        withState {
            translate(cells[3].center.x, cells[3].center.y)
            stroke(Color(hex: 0x53D8A4))
            drawPolyline(superellipse(width: 2 * radius, n: 4).points, closed: true)
            stroke(Color(hex: 0x2EC4B6))
            drawPolyline(superellipse(width: 2 * radius, n: 0.7).points, closed: true)
        }
        withState {
            translate(cells[4].center.x, cells[4].center.y)
            stroke(Color(hex: 0xF6511D))
            let s = radius / 8.4
            drawPolyline(epitrochoid(ring: 5, wheel: 2, pen: 1.4).points.map { $0 * s },
                         closed: true)
        }
        withState {
            translate(cells[5].center.x, cells[5].center.y)
            noStroke()
            fill(Color(hex: 0xDDE3EC))
            drawCircles(phyllotaxis(count: 140, spacing: radius / 12).map {
                Circle(x: $0.x, y: $0.y, radius: 1.7)
            })
        }
        withState {
            translate(cells[7].center.x, cells[7].center.y)
            stroke(Color(hex: 0xE86A5B))
            drawPolyline(supershape(radius: radius, m: 7, n1: 0.3, n2: 1.2, n3: 1.2).points,
                         closed: true)
        }
        withState {
            translate(cells[6].center.x, cells[6].center.y)
            let star = Contour((0..<22).map { i in
                Vector2(angle: Double(i) / 22 * .tau,
                        length: i % 2 == 0 ? radius : radius * 0.45)
            }, closed: true)
            noFill()
            stroke(Color(white: 0.35))
            strokeWeight(0.8)
            drawPolyline(star.points, closed: true)
            stroke(Color(hex: 0x2EC4B6))
            strokeWeight(1.5)
            drawPolyline(star.smoothed(iterations: 3).points, closed: true)
        }
    }
}

/// An ant colony a fixed number of iterations into a tour, the pheromone web
/// under the best route so far. Seeded scatter, seeded search, no time, so
/// the picture is deterministic.
private final class AntColonyScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x14100C))
        var rng = SplitMix64(seed: 12)
        let cities = Ollin.poissonDisk(in: Rectangle(x: 24, y: 24, width: 208, height: 208),
                                       radius: 46, using: &rng)
        let colony = AntColony(cities: cities, elitism: 2, seed: 12)
        colony.step(8)

        strokeCap(.round)
        for trail in colony.trails {
            stroke(Color(red: 1.0, green: 0.72, blue: 0.35,
                         alpha: 0.05 + trail.strength * 0.5))
            strokeWeight(0.4 + trail.strength * 1.6)
            drawLine(trail.a, trail.b)
        }
        stroke(Color(hex: 0xF6EFE2))
        strokeWeight(1.4)
        noFill()
        drawPolyline(colony.bestTourPoints, closed: true)
        noStroke()
        fill(Color(hex: 0xE4572E))
        for city in colony.cities { drawCircle(city.x, city.y, 3) }
    }
}

/// A dielectric-breakdown discharge grown to a fixed size in one frame,
/// drawn with pipe-model widths under an additive halo. Seeded and stepped a
/// fixed count, so the figure is deterministic.
private final class LichtenbergScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0A0A12))
        let bolt = DielectricBreakdown(seeds: [Vector2(128, 128)], in: bounds,
                                       resolution: 84, eta: 1.9,
                                       maxSites: 500, seed: 3)
        bolt.step(500)

        let widths = bolt.thicknesses(tipWidth: 1.0, exponent: 2.0)
        strokeCap(.round)
        blendMode(.add)
        stroke(Color(red: 0.55, green: 0.42, blue: 1.0, alpha: 0.22))
        for (i, site) in bolt.sites.enumerated() {
            guard let parent = site.parent else { continue }
            strokeWeight(widths[i] * 2.4)
            drawLine(bolt.sites[parent].position, site.position)
        }
        blendMode(.normal)
        stroke(Color(hex: 0xF3EFFF))
        for (i, site) in bolt.sites.enumerated() {
            guard let parent = site.parent else { continue }
            strokeWeight(widths[i] * 0.7)
            drawLine(bolt.sites[parent].position, site.position)
        }
    }
}

/// A guilloche rosette: a coarse cam plus a fine ripple over twisted rings.
/// Pure closed form with no rng and no time, so one frame pins the braid.
private final class GuillocheScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0F2A24))
        noFill()
        stroke(Color(hex: 0xEFE6CF, alpha: 0.85))
        strokeWeight(0.8)
        withState {
            translate(128, 128)
            let rings = guilloche(rings: 22, innerRadius: 20, outerRadius: 112,
                                  rosettes: [Rosette(bumps: 8, amplitude: 6),
                                             Rosette(bumps: 40, amplitude: 1.2)])
            for ring in rings {
                drawPolyline(ring.points, closed: true)
            }
        }
    }
}

/// A fixed harmonograph trace: two damped pendulums per axis, near-unison
/// fundamentals plus faster overtones, baked once by contour() and drawn as
/// one open polyline. No rng and no time, so the weave is deterministic.
private final class HarmonographScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0xF4EFE4))
        let h = Harmonograph(
            x: [.init(amplitude: 96, frequency: 2.00, damping: 0.015),
                .init(amplitude: 34, frequency: 6.02, phase: .pi / 2, damping: 0.02)],
            y: [.init(amplitude: 96, frequency: 2.01, phase: .pi / 4, damping: 0.015),
                .init(amplitude: 34, frequency: 4.03, phase: .pi / 3, damping: 0.02)])
        noFill()
        stroke(Color(hex: 0x232B4A).withAlpha(0.75))
        strokeWeight(0.8)
        withState {
            translate(128, 128)
            drawPolyline(h.contour(duration: 80, samples: 12_000).points, closed: false)
        }
    }
}

/// A seeded flock of boids stepped to a fixed frame, drawn as heading-colored
/// triangles. Pins Reynolds' separation/alignment/cohesion steering and the
/// spatial-hash neighbor search. Seeded and stepped to a fixed frame.
private final class FlockingScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    private let flock = Boids(count: 180, in: Rectangle(x: 0, y: 0, width: 256, height: 256),
                              seed: 7, maxSpeed: 1.6, maxForce: 0.08,
                              perceptionRadius: 22, separationRadius: 11, margin: 24)

    override func draw() {
        flock.step()
        background(Color(hex: 0x0E1016))
        noStroke()
        let size = 4.0
        for i in 0 ..< flock.count {
            let p = flock.positions[i], a = flock.heading(i)
            fill(Color(hue: (a + .pi) / (2 * .pi), saturation: 0.55, brightness: 0.96))
            drawTriangle(Vector2(p.x + cos(a) * size, p.y + sin(a) * size),
                         Vector2(p.x + cos(a + 2.5) * size * 0.7, p.y + sin(a + 2.5) * size * 0.7),
                         Vector2(p.x + cos(a - 2.5) * size * 0.7, p.y + sin(a - 2.5) * size * 0.7))
        }
    }
}

/// Steering vehicles stepped to a fixed frame: followers riding a closed
/// wavy loop with separation, one seeded wanderer leaving a trail, and a
/// pursuer chasing the lead follower. Pins the individual steering behaviors.
/// Seeded and stepped to a fixed frame, no time, so it's deterministic.
private final class SteeringScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    // A fixed wavy loop (no noise, so the snapshot pins steering alone).
    private let path: [Vector2] = (0 ..< 96).map { i in
        let t = Double(i) / 96 * 2 * .pi
        let radius = 90 + 16 * sin(t * 3)
        return Vector2(128 + cos(t) * radius, 128 + sin(t) * radius)
    }
    private var followers: [Vehicle] = []
    private var wanderer = Vehicle(at: Vector2(128, 128), velocity: Vector2(1, 0),
                                   maxSpeed: 1.4, maxForce: 0.06, seed: 5)
    private var pursuer = Vehicle(at: Vector2(128, 90), maxSpeed: 1.5, maxForce: 0.05, seed: 9)
    private var trail: [Vector2] = []

    override func setup() {
        followers = (0 ..< 4).map { i in
            Vehicle(at: path[i * 24], velocity: Vector2(angle: Double(i), length: 1),
                    maxSpeed: 1.6, maxForce: 0.08, seed: UInt64(i))
        }
    }

    override func draw() {
        background(Color(hex: 0x0E1016))
        noFill(); stroke(Color(hex: 0x2A3040)); strokeWeight(8)
        drawPolygon(path)

        for creature in followers {
            creature.applyForce(creature.follow(path: path, radius: 5, lookAhead: 18, closed: true))
            creature.applyForce(creature.separate(from: followers, radius: 12))
            creature.step()
        }
        wanderer.applyForce(wanderer.wander(radius: 8, distance: 24))
        wanderer.applyForce(wanderer.contain(in: Rectangle(x: 64, y: 64, width: 128, height: 128), margin: 12) * 1.5)
        wanderer.step()
        trail.append(wanderer.position)
        if trail.count > 60 { trail.removeFirst() }
        pursuer.applyForce(pursuer.pursue(followers[0]))
        pursuer.step()

        if trail.count > 1 {
            stroke(Color(hex: 0x58B8D8).withAlpha(0.5)); strokeWeight(1.5)
            drawPolyline(trail)
        }
        noStroke()
        fill(Color(hex: 0xE8B44A))
        for creature in followers { drawVehicle(creature, size: 5) }
        fill(Color(hex: 0x58B8D8))
        drawVehicle(wanderer, size: 5)
        fill(Color(hex: 0xE8586B))
        drawVehicle(pursuer, size: 6)
    }
}

/// Inverse-kinematics chains solved against fixed targets in one frame:
/// FABRIK plain and stiffness-limited, CCD, the unreachable straight
/// stretch, and a dragged free-base rope. No rng, no stepping.
private final class IKChainScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0E1016))
        strokeCap(.round)

        func show(_ chain: IKChain, _ tint: Color) {
            noFill()
            stroke(tint)
            strokeWeight(3)
            drawPolyline(chain.joints)
            noStroke()
            fill(tint)
            drawCircle(center: chain.tip, radius: 3.5)
        }

        // Three arms from one root, one target: plain FABRIK, a stiff
        // FABRIK, and CCD, so the three poses differ visibly.
        let target = Vector2(180, 60)
        let plain = IKChain(from: Vector2(60, 230), segments: 10, length: 24)
        plain.reach(toward: target, iterations: 20, tolerance: 0.1)
        show(plain, Color(hex: 0x58B8D8))

        let stiff = IKChain(from: Vector2(60, 230), segments: 10, length: 24)
        stiff.maxBend = 0.25
        stiff.reach(toward: target, iterations: 120, tolerance: 0.1)
        show(stiff, Color(hex: 0x8FBFA0))

        let curl = IKChain(from: Vector2(60, 230), segments: 10, length: 24)
        curl.solver = .ccd
        curl.reach(toward: target, iterations: 20, tolerance: 0.1)
        show(curl, Color(hex: 0xE8586B))

        // Out of reach: stretches dead straight at the target.
        let stretch = IKChain(from: Vector2(20, 40), segments: 5, length: 14)
        stretch.reach(toward: Vector2(240, 20))
        show(stretch, Color(hex: 0xE8B44A))

        // A free-base rope dragged through two pins.
        let rope = IKChain(from: Vector2(230, 240), segments: 12, length: 12)
        rope.drag(to: Vector2(140, 180))
        rope.drag(to: Vector2(210, 130))
        show(rope, Color(hex: 0xB48EDE))

        noStroke()
        fill(.white)
        drawCircle(center: target, radius: 4)
    }
}

/// Three double pendulums a hair apart stepped to a fixed frame with
/// second-bob trails. Pins the equations of motion under the fixed-substep
/// integrator. No rng, fixed frame.
private final class DoublePendulumScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    private let pendulums = (0 ..< 3).map { i in
        DoublePendulum(length1: 60, length2: 48,
                       angle1: 2.2 + Double(i) * 0.02, angle2: 2.7)
    }
    private var trails: [[Vector2]] = [[], [], []]

    override func draw() {
        let pivot = Vector2(128, 100)
        for (i, pendulum) in pendulums.enumerated() {
            pendulum.step()
            trails[i].append(pivot + pendulum.bob2)
        }

        background(Color(hex: 0x0E1016))
        let tints = [Color(hex: 0x58B8D8), Color(hex: 0xE8B44A), Color(hex: 0xE8586B)]
        for (i, pendulum) in pendulums.enumerated() {
            noFill()
            stroke(tints[i].withAlpha(0.6))
            strokeWeight(1.5)
            if trails[i].count > 1 { drawPolyline(trails[i]) }
            stroke(tints[i])
            strokeWeight(2)
            drawLine(pivot, pivot + pendulum.bob1)
            drawLine(pivot + pendulum.bob1, pivot + pendulum.bob2)
            noStroke()
            fill(tints[i])
            drawCircle(center: pivot + pendulum.bob2, radius: 3)
        }
    }
}

/// A seeded orbital disk stepped through the quadtree force pass and the
/// leapfrog integrator, tinted by speed. Seeded, fixed frame.
private final class NBodyScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    private let system = NBody.disk(count: 220, center: Vector2(128, 128), radius: 92,
                                    centralMass: 60_000, seed: 6)

    override func draw() {
        system.step()
        background(Color(hex: 0x0E1016))
        noStroke()
        for body in system.bodies.dropFirst() {
            let heat = min(body.velocity.length / 40, 1)
            fill(Color(hue: 0.6 - heat * 0.45, saturation: 0.7, brightness: 0.95))
            drawCircle(center: body.position, radius: 1.6)
        }
        fill(.white)
        drawCircle(center: system.bodies[0].position, radius: 3)
    }
}

/// Space colonization grown to a fixed frame: a seeded blue-noise attractor
/// set, one bottom root, pipe-model stroke widths. Deterministic (the
/// algorithm has no rng; the attractors come from a seeded generator).
private final class SpaceColonizationScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    private let growth: SpaceColonization = {
        var rng = SplitMix64(seed: 3)
        let attractors = Ollin.poissonDisk(in: Rectangle(x: 20, y: 20, width: 216, height: 200),
                                           radius: 13, using: &rng)
        return SpaceColonization(attractors: attractors, roots: [Vector2(128, 244)],
                                 influenceRadius: 60, killRadius: 9, stepLength: 4.5)
    }()

    override func draw() {
        growth.step()
        background(Color(hex: 0x101410))
        strokeCap(.round)
        noStroke()
        fill(Color(hex: 0x3A4A3A))
        drawCircles(growth.attractors, radius: 1.5)
        let widths = growth.thicknesses(leafWidth: 0.8, exponent: 2.2)
        stroke(Color(hex: 0xBFE8C2))
        for (i, node) in growth.nodes.enumerated() {
            guard let parent = node.parent else { continue }
            strokeWeight(widths[i])
            drawLine(growth.nodes[parent].position, node.position)
        }
    }
}

/// A DLA cluster grown to a fixed frame from a center seed, tinted by
/// arrival order. Seeded walker, so it's deterministic.
private final class DLAScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    private let cluster = DiffusionLimitedAggregation(
        seeds: [Vector2(128, 128)], particleRadius: 2.2,
        bounds: Rectangle(x: 0, y: 0, width: 256, height: 256),
        maxParticles: 2400, seed: 5)

    override func draw() {
        cluster.step(10)
        background(Color(hex: 0x0E1016))
        noStroke()
        let count = Double(cluster.count)
        for (i, particle) in cluster.particles.enumerated() {
            fill(Color.mix(Color(hex: 0xF2EFE8), Color(hex: 0x5B8FB9), t: Double(i) / count))
            drawCircle(center: particle.position, radius: 2.2)
        }
    }
}

/// Stroke-as-shape geometry: an open curve stroked into a region with inset
/// bands, a closed square stroked into a band, and a convex hull stroked
/// thin. Pure CPU geometry rendered through the fill path; deterministic.
private final class StrokeShapeScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0xF2EDE3))

        // An open S-curve stroked round, with two inset bands inside.
        let wave = Contour((0 ... 24).map { i -> Vector2 in
            let t = Double(i) / 24
            return Vector2(24 + t * 208, 70 + sin(t * .pi * 2) * 26)
        }, closed: false)
        let ribbon = wave.stroked(width: 34, join: .round, cap: .round)
        noStroke()
        fill(Color(hex: 0x2E4057))
        drawShape(ribbon)
        noFill()
        stroke(Color(hex: 0xF2EDE3))
        strokeWeight(1.4)
        for inset in [-6.0, -12.0] {
            for contour in ribbon.offset(by: inset, join: .round).contours {
                drawPolygon(contour.points)
            }
        }

        // A closed square stroked into a band.
        let square = Contour([Vector2(30, 150), Vector2(110, 150),
                              Vector2(110, 226), Vector2(30, 226)], closed: true)
        noStroke()
        fill(Color(hex: 0xC8553D))
        drawShape(square.stroked(width: 12, join: .miter))

        // A convex hull around fixed points, stroked thin.
        let scatter = [Vector2(150, 160), Vector2(232, 172), Vector2(214, 232),
                       Vector2(166, 226), Vector2(140, 196), Vector2(188, 188),
                       Vector2(200, 150)]
        let hull = convexHull(of: scatter)
        fill(Color(hex: 0xE3B448))
        drawShape(Contour(hull, closed: true).stroked(width: 5, join: .round))
        fill(Color(hex: 0x33312E))
        drawCircles(scatter, radius: 3)
    }
}

/// An inline SVG document imported and drawn as authored beside its bare
/// geometry: a rounded rect, an even-odd ring built from arcs, a mirrored
/// polygon pair, a quadratic path, and an open stroked arc, plus the same
/// contours redrawn as outlines. Pure CPU parse; deterministic.
/// A Fourier epicycle chain over a deterministic two-frequency rosette: the
/// full-term reconstruction, a truncated 8-term prefix, and the chain drawn at
/// a fixed lap phase. No time, no randomness.
private final class EpicyclesScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x10131A))
        let outline = Contour((0 ..< 96).map { i -> Vector2 in
            let a = Double(i) / 96 * .tau
            let r = 82 + 26 * cos(a * 5)
            return Vector2(width / 2 + cos(a) * r, height / 2 + sin(a) * r * 0.8)
        }, closed: true)
        let epicycles = Epicycles(outline, samples: 128)

        noFill()
        strokeWeight(1.6)
        stroke(Color(hex: 0x9FD6E8))
        drawPolygon(epicycles.path(samples: 256).points)
        stroke(Color(hex: 0xE5B15C))
        drawPolygon(epicycles.path(samples: 256, terms: 8).points)
        strokeWeight(0.8)
        stroke(Color(hex: 0x6B7DA6))
        drawEpicycles(epicycles, at: 0.3, terms: 12)
    }
}

private final class ShapeMorphScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x10131A))

        // A prepared morph mid-blend: pairing, rotation, and the hole
        // growing out of the center.
        let c = Vector2(128, 104)
        let star = Shape((0 ..< 10).map { i in
            let a = Double(i) / 10 * .tau - .tau / 4
            return c + Vector2(angle: a, length: i.isMultiple(of: 2) ? 74 : 32)
        })
        let donut = Shape(outer: (0 ..< 48).map { c + Vector2(angle: Double($0) / 48 * .tau, length: 66) },
                          holes: [(0 ..< 32).map { c + Vector2(angle: Double($0) / 32 * .tau, length: 30) }])
        let morph = ShapeMorph(from: star, to: donut)
        fill(Color(hex: 0xE5B15C))
        stroke(Color(hex: 0xF4EAD6))
        strokeWeight(1.6)
        drawShape(morph.shape(at: 0.45))

        // One-off in-betweens: exact at the ends, blended between.
        let triangle = Shape([Vector2(-14, 10), Vector2(14, 10), Vector2(0, -14)])
        noFill()
        stroke(Color(hex: 0x9FD6E8))
        strokeWeight(1.2)
        for (i, t) in [0.0, 0.25, 0.5, 0.75, 1.0].enumerated() {
            let at = Vector2(34 + Double(i) * 47, 218)
            let circle = Shape((0 ..< 24).map { at + Vector2(angle: Double($0) / 24 * .tau, length: 15) })
            drawShape(triangle.mapPoints { $0 + at }.morphed(toward: circle, t))
        }

        // Open line-work morphs too (direction-aligned, stays open).
        let zigzag = Contour([Vector2(18, 22), Vector2(40, 44), Vector2(62, 22), Vector2(84, 44)],
                             closed: false)
        let wave = Contour((0 ..< 16).map { i in
            Vector2(18 + Double(i) / 15 * 66, 33 + 14 * sin(Double(i) / 15 * .pi))
        }, closed: false)
        stroke(Color(hex: 0x6BD69B))
        drawPolyline(Contour.lerp(zigzag, wave, 0.5).points)
    }
}

private final class SVGImportScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    private let source = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120">
      <rect x="6" y="6" width="108" height="108" rx="10" fill="#22283E"/>
      <path fill-rule="evenodd" fill="rgb(127, 209, 224)"
            d="M92 40 A24 24 0 1 1 44 40 A24 24 0 1 1 92 40 Z
               M80 40 A12 12 0 1 0 56 40 A12 12 0 1 0 80 40 Z"/>
      <g transform="translate(0 6)">
        <polygon points="30,86 56,66 56,86" fill="goldenrod"/>
        <g transform="translate(120 0) scale(-1 1)">
          <polygon points="30,86 56,66 56,86" fill="goldenrod"/>
        </g>
      </g>
      <path d="M36 100 Q60 82 84 100 Q60 92 36 100 Z" fill="#D8434E"/>
      <path d="M20 60 A48 48 0 0 1 60 16" fill="none" stroke="#F2EDE3"
            stroke-width="3" stroke-linecap="round"/>
    </svg>
    """

    override func draw() {
        background(Color(hex: 0x14161F))
        guard let art = SVG(data: Data(source.utf8)) else { return }

        // Left: the document as authored (fills, strokes, document order).
        drawSVG(art, in: Rectangle(x: 10, y: 66, width: 116, height: 124))

        // Right: the same file as bare contours, outlined.
        let fitted = art.fitted(in: Rectangle(x: 130, y: 66, width: 116, height: 124))
        noFill()
        stroke(Color(hex: 0xBFD3FF))
        strokeWeight(1.2)
        for contour in fitted.contours {
            if contour.isClosed {
                drawPolygon(contour.points)
            } else {
                drawPolyline(contour.points)
            }
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

/// A fluent `Visual` chain touching all five op families (source, coordinate
/// warp, color adjust, combine, modulate) plus a `.layer` read, so it also pins
/// the single-input routing and the params-as-uniforms codegen at a fixed frame.
private final class VisualChainScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        let rings = renderTarget()
        withTarget(rings) {
            background(.black)
            noFill()
            stroke(.white)
            strokeWeight(6)
            for r in stride(from: 20.0, through: 110, by: 30) {
                drawCircle(width / 2, height / 2, r)
            }
        }
        drawVisual(
            .oscillator(frequency: 18, speed: 1, colorShift: 0.3)
                .kaleidoscope(5)
                .displaced(by: .noise(scale: 3, speed: 0.2), amount: 0.08)
                .blended(with: .layer(rings).tinted(Color(hex: 0xFF8040)), .add, amount: 0.5)
                .saturation(1.2)
        )
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

// Raymarched fields lit by an environment: a polished-metal melt (the physically-based
// split-sum ambient, mirroring the HDRI) and a matte melt (the diffuse-irradiance
// ambient) beside mesh spheres in the same two materials, so field and mesh parity is
// pinned in one frame. Also pins `material(_:)` reaching the field batch at all (the
// per-batch finish). Environment-only lighting, fixed camera + rotation, no time.
private final class RaymarchedSDF3DEnvironmentScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0B0C12))
        toneMap(.aces)
        camera(.orbiting(target: Vector3(0, 0.1, 0), radius: 9.5,
                         azimuth: 0.4, elevation: 0.16, fieldOfView: .pi / 4.2, near: 2, far: 40))
        environment(.studio)

        withState {
            material(.polishedMetal)
            fill(Color(white: 0.95))
            let melt = SDF3D.torus(radius: 1.15, tube: 0.42)
                .smoothUnion(.sphere(radius: 0.62).at(x: 0, y: 0.5, z: 0), k: 0.55)
            drawSDF3D(melt.rotatedX(0.5 * .pi).at(x: -2.4, y: 0.4, z: 0))
        }
        withState {
            material(.matte)
            let melt = SDF3D.sphere(radius: 0.95).colored(Color(hex: 0x3ad6c5))
                .smoothUnion(.octahedron(radius: 1.05).at(x: 0.9, y: 0.85, z: 0)
                    .colored(Color(hex: 0xffb84d)), k: 0.6)
            drawSDF3D(melt.at(x: 2.2, y: 0.2, z: 0))
        }
        withState {
            translate(-0.1, -1.4, 1.6)
            material(.polishedMetal)
            fill(Color(white: 0.95))
            drawSphere(radius: 0.55)
        }
        withState {
            translate(1.0, -1.5, 1.9)
            material(.matte)
            fill(Color(hex: 0x3ad6c5))
            drawSphere(radius: 0.45)
        }
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
/// The 2D joint ops: a plus of two rects stairs-unioned, a chamfer-subtracted bite, and a
/// chamfer-intersected chip beside it. Pins the chamfer/stairs combine encodings (sel 7-12),
/// the crisp nearer-side color pick, and the stairs step count riding the OP node's extra.
private final class SDFCombinatorsJoineryScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x14161a))
        stroke(Color(white: 0.85))
        strokeWeight(1.5)
        let a = SDF.rect(width: 150, height: 64).colored(Color(hex: 0x46c2ff))
        let b = SDF.rect(width: 64, height: 150).at(x: 6, y: 0).colored(Color(hex: 0xffb454))
        let bite = SDF.circle(radius: 34).at(x: -70, y: -48)
        withState {
            translate(96, 92)
            drawSDF(a.stairsUnion(b, radius: 18, steps: 4).chamferSubtract(bite, radius: 8))
        }
        withState {
            translate(190, 196)
            drawSDF(SDF.rect(width: 90, height: 44).colored(Color(hex: 0x9adcf0))
                .chamferUnion(.rect(width: 44, height: 90).colored(Color(hex: 0xff6f61)),
                              radius: 14))
        }
    }
}

/// The 2D sculpt block: per-child mode/melt state (add/carve/blend switching mid-block),
/// including a nested domain block landing under the state at its close. Pins the
/// sculpt fold (each child combining under its captured state, the first as the base).
private final class SDFCombinatorsSculptScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x14161a))
        noStroke()
        translate(128, 128)
        sculpt {
            blend(22)
            fill(Color(hex: 0x46c2ff))
            drawCircle(0, 0, 62)
            withState { translate(52, -30); drawCircle(0, 0, 34) }   // melts on
            carve()
            withState { translate(-20, -34); drawCircle(0, 0, 26) }  // a soft dent
            blend(0)
            withState { translate(30, 34); drawRect(0, 0, 44, 44) }  // a hard notch
            add()
            fill(Color(hex: 0xffb454))
            mirrored(x: true) {                                       // lands as one piece
                withState { translate(74, 30); drawCircle(0, 0, 16) }
            }
        }
    }
}

/// The raymarched sculpt block: the same per-child mode/melt fold in 3D over captured
/// mesh primitives. Static at frame 0.
private final class RaymarchedSDF3DSculptScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x131018))
        camera(.orbiting(target: Vector3(0, 0.1, 0), radius: 5.6, azimuth: 0.5, elevation: 0.3,
                         fieldOfView: .pi / 4, near: 2, far: 12))
        directionalLight(.white, direction: Vector3(-0.5, 0.8, 0.4),
                         intensity: 1.15, softness: 0.3)
        ambientLight(Color(white: 0.18))
        material(.clay)
        sculpt {
            blend(0.3)
            fill(Color(hex: 0xd96f4e))
            drawSphere(radius: 1.0)
            withState { translate(0, -1.0, 0); drawCylinder(radius: 0.55, height: 0.5) }
            fill(Color(hex: 0xe8a06a))
            withState { translate(0, 0.95, 0); drawTorus(radius: 0.5, tube: 0.16) }
            carve()
            withState { translate(0, 1.1, 0); drawSphere(radius: 0.52) }
            blend(0.06)
            withState { translate(0.62, 1.05, 0); rotateZ(-0.5)
                        drawBox(width: 0.5, height: 0.3, depth: 0.34) }
            add()
            blend(0.05)
            fill(Color(hex: 0x8a5a44))
            withState { translate(0, 0.35, 1.05); rotateX(.pi / 2)
                        drawTorus(radius: 0.34, tube: 0.09) }
        }
    }
}

/// The 2D detailing ops: a columns-union plus, a pipe bead pair, and an engraved,
/// grooved, tongued bar. Pins the columns/pipe/engrave/groove/tongue encodings
/// (sels 13-19), the crisp color picks, and the second scalar riding the OP node's extra.
private final class SDFCombinatorsDetailingScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x14161a))
        stroke(Color(white: 0.85))
        strokeWeight(1.5)
        let a = SDF.rect(width: 120, height: 56).colored(Color(hex: 0x46c2ff))
        let b = SDF.rect(width: 56, height: 120).at(x: 4, y: 0).colored(Color(hex: 0xffb454))
        withState {
            translate(66, 62)
            drawSDF(a.columnsUnion(b, radius: 18, count: 4))
        }
        withState {
            translate(190, 58)
            drawSDF(a.pipe(b, radius: 9).scaled(0.62).at(x: 0, y: -28)
                .union(a.columnsIntersect(b, radius: 16, count: 3).scaled(0.62).at(x: 0, y: 34)))
        }
        withState {
            translate(64, 186)
            drawSDF(a.engrave(.circle(radius: 42).at(x: 4, y: 0), depth: 7)
                .tongue(.circle(radius: 58).at(x: 4, y: 0), height: 8, width: 6))
        }
        withState {
            translate(190, 186)
            drawSDF(a.columnsSubtract(b, radius: 16, count: 3)
                .groove(.circle(radius: 46).at(x: 4, y: 0), depth: 8, width: 6))
        }
    }
}

/// The raymarched detailing ops in one scene: a fluted columns-union joint, an
/// engraved + grooved sphere, a tongue-beaded box, and a pipe ring along a
/// sphere/plane crossing. Pins the 3D sels 13-19 and the unbounded-operand bounds
/// (a plane as the detailing surface keeps the field bounded).
private final class RaymarchedSDF3DDetailingScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x11141a))
        camera(.orbiting(target: Vector3(0.2, 0.1, 0), radius: 8.0, azimuth: 0.45, elevation: 0.3,
                         fieldOfView: .pi / 4, near: 2, far: 18))
        directionalLight(.white, direction: Vector3(-0.5, 0.8, 0.4),
                         intensity: 1.2, softness: 0.3)
        ambientLight(Color(white: 0.18))
        material(.glossy)

        let post = SDF3D.cylinder(radius: 0.4, height: 2.4).at(x: -2.6, y: 0.1, z: 0)
            .colored(Color(hex: 0x9adcf0))
        let bar = SDF3D.box(width: 2.0, height: 0.5, depth: 0.5).at(x: -1.9, y: 0.6, z: 0)
            .colored(Color(hex: 0xffb454))
        drawSDF3D(post.columnsUnion(bar, radius: 0.26, count: 4))

        let globe = SDF3D.sphere(radius: 0.9).colored(Color(hex: 0xff6f61))
            .engrave(.plane(normal: Vector3(0, 1, 0), offset: 0.1), depth: 0.05)
            .groove(.plane(normal: Vector3(0, 1, 0), offset: 0.6), depth: 0.06, width: 0.06)
        drawSDF3D(globe.at(x: -0.2, y: 0.1, z: 0))

        let beaded = SDF3D.box(width: 1.1, height: 1.1, depth: 1.1)
            .tongue(.sphere(radius: 0.78), height: 0.07, width: 0.055)
            .colored(Color(hex: 0x46c2ff))
        drawSDF3D(beaded.at(x: 1.8, y: 0.1, z: 0))

        let ring = SDF3D.sphere(radius: 0.7)
            .pipe(.plane(normal: Vector3(0, 1, 0), offset: 0), radius: 0.08)
            .colored(Color(hex: 0xb6ff5a))
        drawSDF3D(ring.rotatedZ(0.5).at(x: 3.3, y: 0.4, z: 0))
    }
}

/// The raymarched joint ops and hardware leaves in one field: a hex-prism head
/// chamfer-unioned to a shaft on a stairs-union base, plus a link, a capped-torus arc, a
/// free-point line stroke, and a pyramid. Pins the 3D sel 7-12 ops and leaf tags 10-14.
private final class RaymarchedSDF3DJoineryScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x101418))
        camera(.orbiting(target: Vector3(0, 0.2, 0), radius: 7.0, azimuth: 0.55, elevation: 0.35,
                         fieldOfView: .pi / 4, near: 2, far: 16))
        directionalLight(.white, direction: Vector3(-0.5, 0.8, 0.4),
                         intensity: 1.2, softness: 0.3)
        ambientLight(Color(white: 0.18))
        material(.glossy)

        let piece = SDF3D.hexPrism(radius: 0.5, height: 0.45).at(x: 0, y: 1.3, z: 0)
            .colored(Color(hex: 0xffb454))
            .chamferUnion(SDF3D.cylinder(radius: 0.26, height: 1.7).at(x: 0, y: 0.5, z: 0)
                .colored(Color(hex: 0x9adcf0)), radius: 0.12)
            .stairsUnion(SDF3D.box(width: 2.0, height: 0.6, depth: 2.0).at(x: 0, y: -0.7, z: 0)
                .colored(Color(hex: 0x5f6f86)), radius: 0.3, steps: 4)
            .chamferSubtract(SDF3D.sphere(radius: 0.5).at(x: 0.8, y: -0.3, z: 0.8), radius: 0.1)
        drawSDF3D(piece)

        let hardware = SDF3D.link(height: 0.3, radius: 0.28, tube: 0.085)
            .at(x: -2.0, y: 0.9, z: 0).colored(Color(hex: 0xd8dee6))
            .union(.cappedTorus(radius: 0.4, tube: 0.1, angle: 2.1)
                .at(x: -2.0, y: -0.35, z: 0).colored(Color(hex: 0xff6f61)))
            .union(.line(from: Vector3(1.7, -1.0, 0.6), to: Vector3(2.3, 0.6, -0.2), radius: 0.09)
                .colored(Color(hex: 0x8fa3bd)))
            .union(.pyramid(base: 0.7, height: 0.65).at(x: 2.35, y: 1.15, z: -0.35)
                .colored(Color(hex: 0xb6ff5a)))
        drawSDF3D(hardware)
    }
}

/// The raymarched sculpting distortions: a twisted box column, a bent bar, a sine-displaced
/// sphere, and a noise-roughened sphere. Pins the twist/bend XFORMs (sel 8/9) with their
/// Lipschitz rescale, and the displacement MODs (sel 2/3) with theirs.
private final class RaymarchedSDF3DDistortScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x12141a))
        camera(.orbiting(target: Vector3(0, 0.1, 0), radius: 8.5, azimuth: 0.35, elevation: 0.3,
                         fieldOfView: .pi / 4, near: 2, far: 18))
        directionalLight(.white, direction: Vector3(-0.5, 0.8, 0.4),
                         intensity: 1.15, softness: 0.3)
        ambientLight(Color(white: 0.17))
        material(.jade)

        drawSDF3D(SDF3D.box(width: 0.8, height: 2.4, depth: 0.8).twisted(1.2)
            .at(x: -2.9, y: 0.2, z: 0).colored(Color(hex: 0x46c2ff)))
        drawSDF3D(SDF3D.box(width: 2.4, height: 0.45, depth: 0.65).bent(0.55)
            .at(x: -0.9, y: 0.2, z: 0).colored(Color(hex: 0xffb454)))
        drawSDF3D(SDF3D.sphere(radius: 0.9).displaced(amplitude: 0.1, frequency: 6.5)
            .at(x: 1.1, y: 0.1, z: 0).colored(Color(hex: 0xff6f61)))
        drawSDF3D(SDF3D.sphere(radius: 0.9).roughened(amplitude: 0.15, frequency: 3.2)
            .at(x: 3.0, y: 0.1, z: 0).colored(Color(hex: 0x9aa7b8)))
    }
}

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

/// `strokeProfile` across the width-profile family, all at one `strokeWeight` so
/// only the profile differs: `.uniform` (the control, which must stay identical to
/// the unprofiled path), `.taper()`, `.ramp`, `.values`, and a `.nib` on an arc
/// that turns through a wide range of directions. The last row is a closed
/// triangle, whose profile wraps end to start, and a tapered stroke on a curve
/// whose corners are joins at varying width. Pins the per-vertex half-width
/// expansion (trapezoid segments, joins and caps at the local width) and the
/// area-conserving sub-pixel coverage that lets a taper vanish instead of trailing
/// a ghost line. Black on white, no rng and no time, so it is deterministic.
private final class BrushesScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.white)
        stroke(.black)
        strokeWeight(14)

        func wave(_ y: Double) -> [Vector2] {
            (0...40).map { i in
                let t = Double(i) / 40
                return Vector2(20 + t * 216, y + sin(t * .pi * 2) * 12)
            }
        }

        strokeBrush(.round)
        drawPolyline(wave(26))

        strokeBrush(.chisel())
        drawPolyline(wave(70))

        strokeBrush(.spray(seed: 5))
        drawPolyline(wave(114))

        strokeBrush(.scatter(seed: 9))
        drawPolyline(wave(158))

        // A brush and a width profile multiply.
        strokeBrush(Brush(.circle, spacing: 0.4, sizeJitter: 0.3, seed: 2))
        strokeProfile(.taper())
        drawPolyline(wave(202))
        noStrokeProfile()

        // A fixed angle, a closed path, and a shape tip.
        strokeWeight(10)
        strokeBrush(Brush(.square, spacing: 1.1, angle: .fixed(.pi / 4), seed: 4))
        drawPolyline([Vector2(30, 226), Vector2(120, 240), Vector2(210, 226)], closed: true)
        noStrokeBrush()
    }
}

private final class StrokeProfilesScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.white)
        stroke(.black); strokeWeight(20); strokeCap(.butt)

        let profiles: [StrokeProfile] = [
            .uniform,
            .taper(),
            .ramp(from: 0.05, to: 1),
            .values([0.2, 1, 0.35, 0.9, 0.1]),
        ]
        for (i, profile) in profiles.enumerated() {
            let cy = 26.0 + Double(i) * 32
            strokeProfile(profile)
            drawPolyline([Vector2(24, cy), Vector2(96, cy - 9),
                          Vector2(160, cy + 9), Vector2(232, cy)])
        }

        // A nib on a half-turn arc: the mark is fattest where the arc runs across
        // the nib and a hairline where it runs along it.
        strokeProfile(.nib(angle: .pi / 4))
        strokeWeight(24)
        drawPolyline((0...48).map { k in
            let a = .pi + Double(k) / 48 * .pi
            return Vector2(76 + cos(a) * 40, 190 + sin(a) * 40)
        })

        // A closed path (the profile wraps) and a taper over sharp joins.
        strokeWeight(16)
        strokeProfile(.taper(start: 1, end: 0))
        drawPolyline([Vector2(150, 168), Vector2(232, 186), Vector2(176, 230)], closed: true)
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

/// The relight height-map material pass (metal over a drawn hill scene), the
/// two-tone ordered dither, and the off-center swirl and ripple warps, all at
/// fixed parameters (no time/random). Pins the new fragments and dispatches, and
/// the `center` parameter plumbing on the radial warps.
private final class EffectsRelight: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.05))
        let scene = renderTarget()
        withTarget(scene) {
            background(Color(hex: 0x101826))
            noStroke()
            fill(.radial(center: Vector2(width * 0.35, height * 0.4), radius: width * 0.5,
                         Ramp([Color(white: 0.9), Color(white: 0.15)])))
            drawRect(0, 0, width, height)
            fill(Color(hex: 0xFF8A3C)); drawCircle(width * 0.68, height * 0.62, width * 0.16)
            fill(Color(hex: 0x54C2FF)); drawRect(width * 0.15, height * 0.15, width * 0.3, height * 0.22)
        }
        let tiles: [RenderTarget] = [
            scene.filtered(.relight(.metal, color: Color(hex: 0xD8A93F))),
            scene.filtered(.dither(dark: Color(hex: 0x1B1040), light: Color(hex: 0xFFE08A),
                                   pixelSize: 2)),
            scene.filtered(.swirl(angle: 2.4, radius: 0.5, center: Vector2(0.3, 0.35))),
            scene.filtered(.ripple(amplitude: 0.04, frequency: 9, center: Vector2(0.7, 0.6))),
        ]
        for (i, tile) in tiles.enumerated() {
            let x = Double(i % 2) * 128, y = Double(i / 2) * 128
            drawImage(tile.image, in: Rectangle(x: x, y: y, width: 128, height: 128))
        }
    }
}

/// The iridescence + glitter filters over a fixed two-shape scene, at fixed
/// `shift`/`phase` (no time), so the fbm thickness field, the thin-film per-channel
/// interference color, the hash-cell sparkle layers, and the alpha gating are all
/// pinned deterministically.
private final class EffectsGlitter: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.04))
        let sheen = renderTarget()
        withTarget(sheen) {
            noStroke(); fill(Color(white: 0.8))
            drawHeart(width * 0.27, height * 0.5, 120)
        }
        drawImage(sheen.filtered(.iridescence(amount: 0.85, scale: 2.2, bands: 2.4, shift: 0.4)).image, 0, 0)
        let sparkle = renderTarget()
        withTarget(sparkle) {
            noStroke(); fill(Color(hex: 0xC2185B))
            drawStar(width * 0.73, height * 0.5, 62, 31, points: 5)
        }
        drawImage(sparkle.filtered(.glitter(density: 60, amount: 1.2, saturation: 0.6, phase: 1.3)).image, 0, 0)
    }
}

/// The Mandelbrot set beside a Julia set at fixed framing and phase (no time, no
/// random): pins the escape-time generator's iteration, smooth coloring, cosine
/// palette fold, and interior fill in both modes.
private final class EscapeTimeScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.05))
        let w = 126, h = 252
        drawImage(generate(.mandelbrot(iterations: 120, phase: 0.2), width: w, height: h).image,
                  in: Rectangle(x: 1, y: 2, width: Double(w), height: Double(h)))
        drawImage(generate(.julia(iterations: 120, phase: 0.6), width: w, height: h).image,
                  in: Rectangle(x: 129, y: 2, width: Double(w), height: Double(h)))
    }
}

/// The four orbit traps at fixed framing and angles (no time, no random): pins
/// the minimum-distance tracking, each trap's distance formula, the trap
/// rotation, and the exp glow ramp.
private final class OrbitTrapScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.05))
        let w = 126, h = 126
        let tile: (Int, Int) -> Rectangle = { col, row in
            Rectangle(x: 1 + Double(col) * 128, y: 1 + Double(row) * 128,
                      width: Double(w), height: Double(h))
        }
        drawImage(generate(.orbitTrap(.cross(.zero), c: Vector2(-0.79, 0.15),
                                      zoom: 1.2, iterations: 120, angle: 0.35),
                           width: w, height: h).image, in: tile(0, 0))
        drawImage(generate(.orbitTrap(.point(.zero), iterations: 120, glow: 0.15),
                           width: w, height: h).image, in: tile(1, 0))
        drawImage(generate(.orbitTrap(.circle(center: .zero, radius: 0.5),
                                      c: Vector2(0.285, 0.01), zoom: 1.2,
                                      iterations: 120, glow: 0.02),
                           width: w, height: h).image, in: tile(0, 1))
        drawImage(generate(.orbitTrap(.square(center: .zero, radius: 0.35),
                                      c: Vector2(-0.4, 0.6), zoom: 1.2,
                                      iterations: 120, glow: 0.05, angle: 0.5),
                           width: w, height: h).image, in: tile(1, 1))
    }
}

/// The noise-toolkit generators at a fixed phase (no time/random): the warp
/// knob on `.noise` plus the cellular generator's three styles, each tile at
/// its own size.
private final class NoiseToolkitScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.05))
        let w = 126, h = 126
        let phase = 0.35 * Double.tau
        let tile: (Int, Int) -> Rectangle = { col, row in
            Rectangle(x: 1 + Double(col) * 128, y: 1 + Double(row) * 128,
                      width: Double(w), height: Double(h))
        }
        drawImage(generate(.noise(scale: 3, warp: 1), width: w, height: h).image,
                  in: tile(0, 0))
        drawImage(generate(.cellular(scale: 5, style: .cells, phase: phase),
                           width: w, height: h).image,
                  in: tile(1, 0))
        drawImage(generate(.cellular(scale: 5, jitter: 0.75, style: .borders,
                                     foreground: Color(hex: 0xF2C14E),
                                     background: Color(hex: 0x1B1F2A), phase: phase),
                           width: w, height: h).image,
                  in: tile(0, 1))
        drawImage(generate(.cellular(scale: 5, style: .mosaic,
                                     foreground: Color(hex: 0x55D6BE),
                                     background: Color(hex: 0x12161F), phase: phase),
                           width: w, height: h).image,
                  in: tile(1, 1))
    }
}

/// The Chladni generator's two styles at fixed modes and phases (no time, no
/// random): sand at the default and a higher mode, sand at a fractional
/// morphing mode, and the wave style mid-swing, each tile at its own size.
private final class ChladniScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.05))
        let w = 126, h = 126
        let tile: (Int, Int) -> Rectangle = { col, row in
            Rectangle(x: 1 + Double(col) * 128, y: 1 + Double(row) * 128,
                      width: Double(w), height: Double(h))
        }
        drawImage(generate(.chladni(), width: w, height: h).image,
                  in: tile(0, 0))
        drawImage(generate(.chladni(m: 9, n: 4, weight: 0.08, grain: 1,
                                    foreground: Color(hex: 0xF2C14E),
                                    background: Color(hex: 0x1B1F2A),
                                    phase: 0.8),
                           width: w, height: h).image,
                  in: tile(1, 0))
        drawImage(generate(.chladni(m: 6.5, n: 2.5, grain: 0.3,
                                    foreground: Color(hex: 0x55D6BE),
                                    background: Color(hex: 0x12161F)),
                           width: w, height: h).image,
                  in: tile(0, 1))
        drawImage(generate(.chladni(m: 7, n: 3, style: .wave,
                                    foreground: Color(hex: 0xE8DCC8),
                                    background: Color(hex: 0x2A2E3A),
                                    phase: 0.9),
                           width: w, height: h).image,
                  in: tile(1, 1))
    }
}

/// A ripples SimField rained on by seeded soft drops, evolved to the captured
/// frame and shaded into water with .relight. Seeded once in setup, so the
/// drop schedule (and therefore every frame) is deterministic.
private final class RipplesScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private var pool: SimField!

    override func setup() {
        seed(7)
        pool = simField(.ripples())
    }

    override func draw() {
        background(.black)
        withField(pool) {
            if frameCount % 18 == 1 {
                let x = random(40, width - 40), y = random(40, height - 40)
                let r = random(8, 18)
                fill(.radial(center: Vector2(x, y), radius: r,
                             [Color(white: 1, alpha: 0.7), Color(white: 1, alpha: 0)]))
                drawCircle(x, y, r)
            }
        }
        let water = pool.filtered(.relight(.liquid, angle: -.pi * 0.7, elevation: 0.7,
                                           height: 9, intensity: 1.15,
                                           color: Color(hex: 0x3D6E8F)))
        drawImage(water.image, 0, 0)
    }
}

/// A seeded diamond-square field, eroded (a light hydraulic pass then thermal
/// settling), meshed with a height-ramp texture, and framed by a fixed camera.
private final class TerrainScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0A0D12))
        let land = Heightfield.diamondSquare(size: 65, roughness: 0.55, seed: 7)
            .eroded(.hydraulic(drops: 6_000), seed: 7)
            .eroded(.thermal(talus: 0.03, iterations: 12))

        let ramp = Ramp([Color(hex: 0x2E4A33), Color(hex: 0x8A7E66), Color(hex: 0xEDEFF2)])
        var pixels = [UInt8]()
        for value in land.values {
            let c = ramp.color(at: min(max(value, 0), 1))
            pixels.append(contentsOf: [UInt8((c.red * 255).rounded()),
                                       UInt8((c.green * 255).rounded()),
                                       UInt8((c.blue * 255).rounded()), 255])
        }
        var mesh = land.mesh(width: 10, depth: 10, height: 2.2)
        if let texture = Image(width: land.columns, height: land.rows,
                               premultipliedRGBA: pixels) {
            mesh = mesh.textured(texture)
        }

        lightingPreset(.goldenHour)
        camera(Camera3D.orbiting(target: .zero, radius: 13, azimuth: 0.8,
                                 elevation: 0.55, fieldOfView: .pi / 4))
        drawMesh(mesh)
    }
}

/// Metaballs marched into a mesh at fixed positions: a merged pair on the
/// left, a lone ball on the right, and a negative ball biting into it. Fixed
/// camera, no time, no randomness.
private final class MetaballsScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0A0D12))

        var field = Metaballs()
        // Far enough apart that their spheres don't overlap, close enough that
        // the summed field still bridges them: the neck is the thing to pin.
        field.add(at: Vector3(-2.0, 0.35, 0.0), radius: 1.05)
        field.add(at: Vector3(0.1, -0.30, 0.35), radius: 0.85)
        field.add(at: Vector3(3.2, 0.50, -0.40), radius: 0.90)              // out of reach, stands alone
        field.add(at: Vector3(3.9, -0.10, 0.30), radius: 0.70, strength: -1) // bites into it

        fill(Color(hex: 0x7C8A9C))
        lightingPreset(.studio)
        camera(Camera3D.orbiting(target: Vector3(0.6, 0, 0), radius: 9.5,
                                 azimuth: 0.55, elevation: 0.35, fieldOfView: .pi / 4))
        drawMesh(field.mesh(resolution: 64))
    }
}

/// A cube and an extruded star smoothed as subdivision surfaces at fixed
/// levels and angles. Fixed camera, no time, no randomness.
private final class SubdivisionSurfaceScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0A0D12))
        lightingPreset(.studio)
        camera(Camera3D.orbiting(target: .zero, radius: 9.0,
                                 azimuth: 0.5, elevation: 0.33, fieldOfView: .pi / 4))

        let cube = Mesh.box(size: 1.6)
        let star = Mesh.extrude(Profile.star(points: 5, outerRadius: 1.0, innerRadius: 0.45),
                                depth: 0.6)
        // Back row: the cube at quad-rule levels 1 and 3, the cage ghosted
        // over the smoother one. Front row: the star through both schemes.
        withState {
            translate(-1.9, 1.15, 0)
            rotateY(0.6); rotateX(0.25)
            fill(Color(hex: 0x53D1FF))
            drawMesh(cube.subdivided(.catmullClark, levels: 1))
        }
        withState {
            translate(1.9, 1.15, 0)
            rotateY(0.6); rotateX(0.25)
            fill(Color(hex: 0x53D1FF))
            drawMesh(cube.subdivided(.catmullClark, levels: 3))
            wireframe()
            stroke(Color(hex: 0x53D1FF).withAlpha(0.35))
            strokeWeight(1.0)
            drawMesh(cube)
        }
        withState {
            translate(-1.9, -1.35, 0)
            rotateY(-0.4); rotateX(0.3)
            fill(Color(hex: 0xFFB13D))
            drawMesh(star.subdivided(.catmullClark, levels: 3))
        }
        withState {
            translate(1.9, -1.35, 0)
            rotateY(-0.4); rotateX(0.3)
            fill(Color(hex: 0xFF7AB0))
            drawMesh(star.subdivided(.loop, levels: 3))
        }
    }
}

/// Stacked ridgeline rows from the CPU ridged accumulator at a fixed loop
/// phase: seeded, occluding back to front, deterministic.
private final class RidgeLinesScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        seed(7)
        let paper = Color(hex: 0xF4EFE6), ink = Color(hex: 0x2A2E3A)
        background(paper)
        let rows = 12
        for r in 0 ..< rows {
            let depth = Double(r) / Double(rows - 1)
            let baseline = map(depth * depth, 0, 1, height * 0.30, height * 0.96)
            let amplitude = map(depth, 0, 1, height * 0.06, height * 0.20)
            var skyline: [Vector2] = []
            var x = 0.0
            while x <= width {
                let n = ridgedFbm(x * 0.013, Double(r) * 0.83, loop: 0.3, radius: 0.6)
                skyline.append(Vector2(x, baseline - n * amplitude))
                x += 4
            }
            skyline.append(Vector2(width, skyline.last!.y))
            var panel = skyline
            panel.append(Vector2(width, height))
            panel.append(Vector2(0, height))
            fill(Color.mix(paper, ink, t: 0.04 + depth * 0.10))
            noStroke()
            drawPolygon(panel)
            stroke(ink)
            strokeWeight(map(depth, 0, 1, 0.5, 1.4))
            noFill()
            drawPolyline(skyline)
        }
    }
}

/// The five pattern-field generators at fixed phases (no time/random), each filled
/// at its own tile size so the compositions are undistorted. Pins the five new
/// fragments and dispatches, the shared `ollin_pat_ramp` palette walk, and the
/// explicit-size `generate(_:width:height:)` form.
private final class PatternFieldsScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.05))
        let w = 84, h = 126
        let tiles: [RenderTarget] = [
            generate(.quasicrystal(phase: 2.0), width: w, height: h),
            generate(.moire(phase: 3.0), width: w, height: h),
            generate(.gyroid(phase: 1.2), width: w, height: h),
            generate(.phyllotaxis(count: 300, phase: 0.4), width: w, height: h),
            generate(.hexPulse(scale: 5, phase: 2.5), width: w, height: h),
            generate(.quasicrystal(symmetry: 5, contrast: 1, phase: 0), width: w, height: h),
        ]
        for (i, tile) in tiles.enumerated() {
            let x = Double(i % 3) * 85.5, y = Double(i / 3) * 128
            drawImage(tile.image, in: Rectangle(x: x, y: y, width: Double(w), height: Double(h)))
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

/// The modulated sibling of `EffectsSimField`: the same fixed dot-grid seed, with a
/// half-black, half-white modulation layer sliding feed/kill from the spot regime
/// (left) to the maze/coral regime (right; both pairs living regimes of this
/// implementation, read off the Guide's FeedKillMap figure). Pins the modulated step
/// variant end to end: the map layer resolved before the sim passes, the per-texel
/// feed/kill lerp, and one continuous field wearing two regimes without a seam.
private final class EffectsSimFieldModulated: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    var rd: SimField!
    var mask: RenderTarget!
    var seeded = false

    override func setup() {
        rd = simField(.reactionDiffusion(feed: 0.046, kill: 0.065,
                                         toFeed: 0.055, toKill: 0.062), scale: 0.5)
        mask = renderTarget()
        rd.modulation = mask
    }

    override func draw() {
        withTarget(mask) {                       // redrawn each frame: layers are per-frame
            background(.black)
            noStroke(); fill(.white)
            drawRect(width / 2, 0, width / 2, height)
        }
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

/// The three newer iterated maps in one frame: Gumowski-Mira across the whole
/// canvas, Ikeda and hopalong as small insets. Each carries its orbit across
/// frames with no settle (the Gumowski-Mira picture *is* the transient), so
/// the fixed capture frame pins the exact orbit prefix of all three rules.
private final class NewerMapsScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private let mira = ChaoticMap.gumowskiMira()
    private let ikeda = ChaoticMap.ikeda()
    private let hopalong = ChaoticMap.hopalong()
    private var points = [Vector2]()   // scratch, reused per map per frame

    private var miraCurrent: Vector2?
    private var ikedaCurrent: Vector2?
    private var hopalongCurrent: Vector2?

    override func setup() { noClear(); noStroke() }

    override func draw() {
        if frameCount == 1 { background(.black) }
        blendMode(.add)
        pointSize(1.0)

        accumulate(map: mira, current: &miraCurrent, perFrame: 20_000,
                   center: Vector2(128, 118), reach: 13,
                   color: Color(red: 1.0, green: 0.62, blue: 0.3, alpha: 0.07))
        accumulate(map: ikeda, current: &ikedaCurrent, perFrame: 8_000,
                   center: Vector2(52, 210), reach: 16,
                   color: Color(red: 0.42, green: 0.74, blue: 1.0, alpha: 0.07))
        accumulate(map: hopalong, current: &hopalongCurrent, perFrame: 8_000,
                   center: Vector2(204, 208), reach: 9,
                   color: Color(red: 0.55, green: 1.0, blue: 0.62, alpha: 0.07))
    }

    private func accumulate(map: ChaoticMap, current: inout Vector2?,
                            perFrame: Int, center: Vector2, reach: Double,
                            color: Color) {
        var point = current ?? map.start
        points.removeAll(keepingCapacity: true)
        points.reserveCapacity(perFrame)
        for _ in 0..<perFrame {
            point = map.next(point)
            points.append(Vector2(center.x + point.x * reach,
                                  center.y + point.y * reach))
        }
        current = point
        fill(color)
        drawPoints(points)
    }
}

/// One-dimensional maps three ways: the logistic diagram as a density image,
/// the Gauss mouse diagram as swept dots, and a cobweb over its curve and
/// diagonal. Everything is a pure function of the maps, so one frame pins it.
private final class BifurcationScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.white)

        // The logistic diagram, log-toned ink on white, drawn 1:1.
        let map = IteratedMap.logistic()
        if let plate = map.bifurcationImage(width: 150, height: 256,
                                            samplesPerColumn: 600, settle: 500) {
            drawImage(plate, 0, 0)
        }

        // The Gauss mouse as swept dots through the drawing sugar.
        noStroke()
        fill(Color(hex: 0x1F2033).withAlpha(0.35))
        pointSize(1)
        drawBifurcation(IteratedMap.gauss(),
                        in: Rectangle(x: 158, y: 6, width: 92, height: 112),
                        columns: 92, perColumn: 90, settle: 400)

        // A cobweb converging to the logistic 2-cycle at r = 3.4, over the
        // curve and the diagonal.
        let frame = Rectangle(x: 158, y: 152, width: 92, height: 92)
        func place(_ p: Vector2) -> Vector2 { frame.point(u: p.x, v: 1 - p.y) }
        noFill()
        strokeWeight(1)
        stroke(Color(hex: 0x9AA1B4))
        drawLine(place(Vector2(0, 0)), place(Vector2(1, 1)))
        stroke(Color(hex: 0x2E6E4E))
        drawPolyline(map.graph(at: 3.4).map(place), closed: false)
        stroke(Color(hex: 0xB0492C))
        drawPolyline(map.cobweb(at: 3.4, steps: 28, from: 0.08).map(place), closed: false)
    }
}

/// The mesh-gradient generator at a fixed phase (no time, no random): the
/// inverse-distance-weighted blob blend, the two-pass domain warp + swirl, the
/// sRGB-space palette blending, and the grain overlay are all deterministic
/// functions of the phase, so one frame pins them.
private final class MeshGradientPattern: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        let gradient = generate(.meshGradient(distortion: 0.8, swirl: 0.3,
                                              grain: 0.4, phase: 6))
        drawImage(gradient.image, 0, 0)
    }
}

/// The nine other design-pattern generators tiled 3×3 at fixed phases (no time,
/// no random), one tile per new dispatch arm + fragment.
private final class DesignPatternsSheet: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.black)
        let tiles: [RenderTarget] = [
            generate(.filaments(phase: 2)),
            generate(.smokeRing(colors: [.white, Color(hex: 0x6FD9FF)], phase: 2)),
            generate(.colorPanels(phase: 40)),
            generate(.spiral(distortion: 0.15, phase: 1)),
            generate(.waves(shape: 1.2, phase: 0.5)),
            generate(.dotOrbit(phase: 2)),
            generate(.grainGradient(shape: .ripple, phase: 2)),
            generate(.pulsingBorder(phase: 2)),
            generate(.godRays(phase: 2)),
        ]
        let g = grid(columns: 3, rows: 3)
        for (cell, tile) in zip(g.cells, tiles) {
            drawImage(tile.image, in: cell.frame)
        }
    }
}

/// The six design filters tiled 3×2 at fixed phases (no time, no random): the
/// three alpha-shape effects over a drawn heart, the three image effects over
/// a fixed mesh-gradient backdrop.
private final class DesignFiltersSheet: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.black)
        func heartLayer() -> RenderTarget {
            let layer = renderTarget()
            withTarget(layer) {
                noStroke(); fill(.white)
                drawHeart(width / 2, height / 2, width * 0.5)
            }
            return layer
        }
        let backdrop = generate(.meshGradient(phase: 2.4))
        let tiles: [RenderTarget] = [
            heartLayer().filtered(.liquidMetal(phase: 1)),
            heartLayer().filtered(.heatmap(phase: 4)),
            heartLayer().filtered(.gemSmoke(phase: 2)),
            backdrop.filtered(.flutedGlass(angle: 0.35)),
            backdrop.filtered(.water(phase: 2)),
            heartLayer().filtered(.paperTexture()),
        ]
        let g = grid(columns: 3, rows: 2)
        for (cell, tile) in zip(g.cells, tiles) {
            drawImage(tile.image, in: cell.frame)
        }
    }
}

/// One wedge of drawing folded by `symmetry(6, mirrored: true)` around an
/// off-axis pivot (translate + rotate first, so the fold matrices conjugate a
/// non-trivial CTM), touching every replicated 2D path: SDF instances (circle,
/// star, the bitmap-text pixels), the tessellated polygon fill, the fringe
/// outline and polyline, and a smooth-union SDF field (one group per fold,
/// sharing its node program). The center dot draws after `noSymmetry()`, so it
/// lands once. `time`-free, so it's deterministic.
private final class SymmetryScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x101418))
        translate(128, 132)
        rotate(0.15)                       // aim the mirror seam off-axis
        symmetry(6, mirrored: true)

        // SDF instances: a circle and a star along the arm.
        noStroke()
        fill(Color(hex: 0x2EC4B6))
        drawCircle(78, 16, 13)
        fill(Color(hex: 0xFFD166))
        drawStar(46, -20, 12, 5, points: 5)

        // A tessellated fill with its fringe outline.
        fill(Color(hex: 0xF6511D))
        stroke(.white)
        strokeWeight(1.5)
        drawPolygon([Vector2(20, 6), Vector2(58, 12), Vector2(40, 30)])

        // A stroked polyline (the fringe path alone).
        noFill()
        stroke(Color(hex: 0x9BF6FF))
        strokeWeight(2)
        drawPolyline([Vector2(24, -8), Vector2(56, -18), Vector2(92, -6)])

        // A composed SDF field: the merged blob replicates as one group per fold.
        noStroke()
        let blob = SDF.circle(radius: 9).colored(Color(hex: 0xB388EB))
            .smoothUnion(SDF.circle(radius: 7).at(x: 14, y: -6), k: 8)
            .at(x: 104, y: -12)
        drawSDF(blob)

        // Bitmap text rides the folds too (each pixel an SDF box).
        fill(.white)
        textFont(BitmapFont.builtin)
        textSize(10)
        drawText("ollin", 62, 34)

        // Off again: the center dot lands once.
        noSymmetry()
        fill(.white)
        drawCircle(0, 0, 7)
    }
}

/// Stencil clipping across the batch paths: a star-shaped `withClip` confining
/// tessellated stripes, SDF circles, and a fringe stroke; a nested circle clip
/// intersecting it; drawing after the pop crossing the old boundary unclipped;
/// and a rect-clipped bitmap-text run. `time`-free, so it's deterministic.
private final class ClipScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x101418))
        // A star-shaped region built as a plain vector Shape.
        var starPoints: [Vector2] = []
        for k in 0..<14 {
            let radius = k % 2 == 0 ? 78.0 : 40.0
            let a = Double(k) / 14 * 2 * .pi - .pi / 2
            starPoints.append(Vector2(96 + cos(a) * radius, 100 + sin(a) * radius))
        }
        withClip(Shape(starPoints)) {
            // Tessellated stripes exist only inside the star.
            noStroke()
            for i in 0..<16 {
                fill(i % 2 == 0 ? Color(hex: 0x2EC4B6) : Color(hex: 0x1B6B62))
                drawPolygon([Vector2(Double(i) * 16, 0), Vector2(Double(i) * 16 + 16, 0),
                             Vector2(Double(i) * 16 + 16, 256), Vector2(Double(i) * 16, 256)])
            }
            // An SDF circle and a fringe stroke cross the boundary and get cut.
            fill(Color(hex: 0xF6511D))
            drawCircle(96, 100, 34)
            stroke(.white)
            strokeWeight(3)
            drawLine(0, 60, 256, 150)
            // Nested clip: the purple fill shows only where circle intersects star.
            withClip(Circle(x: 140, y: 118, radius: 46)) {
                noStroke()
                fill(Color(hex: 0xB388EB))
                drawRect(0, 0, 256, 256)
            }
        }
        // After the pop: unclipped drawing crosses the old boundary untouched.
        noFill()
        stroke(Color(hex: 0x9BF6FF))
        strokeWeight(2)
        drawCircle(96, 100, 88)
        // A rect clip cutting a bitmap-text run (the glyph-atlas quad path).
        withClip(Rectangle(x: 128, y: 196, width: 84, height: 36)) {
            fill(Color(hex: 0xFFD166))
            textFont(BitmapFont.builtin)
            textSize(14)
            drawText("clipped text runs long", 96, 220)
        }
    }
}

/// One motif recorded into a `Batch` in `setup()` and replayed three ways in
/// `draw()`: in place (the identity replay), under a rotate+scale+translate stamp
/// (the flag-gated shader transform), and with a dynamic circle drawn between the
/// two replays (draw-order compositing around a `.retained` reference batch). The
/// motif spans the retainable paths: SDF instances (one with a gradient fill, so
/// the batch's own handle-relative gradient strip is exercised), a fringe-stroked
/// polyline, a concave tessellated fill, and a smooth-union SDF field.
/// A StrandField meadow patch grown in-draw, with a shadow-casting box, framed
/// so part of the patch is off-screen. No time and no rng, deterministic.
private final class StrandsScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x101218))
        camera(Camera3D(eye: Vector3(5, 2.4, 5), target: Vector3(1.5, 0.3, 0)))
        ambientLight(Color(white: 0.18))
        directionalLight(Color(white: 1), direction: Vector3(-0.5, -0.85, -0.35), intensity: 1)
        castShadows()
        withState {
            fill(Color(hue: 0.3, saturation: 0.25, brightness: 0.3))
            drawPlane(width: 30, depth: 30)
        }
        withState {
            translate(1.2, 0.75, -0.6)
            fill(Color(hue: 0.08, saturation: 0.4, brightness: 0.7))
            drawBox(width: 1.2, height: 1.5, depth: 1.2)
        }
        var meadow = StrandField(width: 16, depth: 16, count: 60_000)
        meadow.bladeHeight = 0.55
        meadow.swayAmount = 0.08
        drawStrands(meadow)
    }
}

/// A retained MeshField of three mesh kinds in a ring, GPU-culled, framed so
/// part of the ring is off-screen. No rng and no time, deterministic.
private final class MeshFieldScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private let field = MeshField()

    override func setup() {
        var boxes: [MeshInstance] = [], spheres: [MeshInstance] = [], cones: [MeshInstance] = []
        for i in 0 ..< 60 {
            let a = Double(i) / 60 * .tau
            let r = 2.0 + Double(i % 7) * 1.1
            let p = Vector3(cos(a) * r, 0.4, sin(a) * r)
            let tint = Color(red: 0.5 + 0.5 * cos(a), green: 0.7, blue: 1, alpha: 1)
            switch i % 3 {
            case 0: boxes.append(MeshInstance(position: p, rotation: Vector3(0, a, 0),
                                              scale: Vector3(1, 1 + Double(i % 4) * 0.4, 0.8),
                                              color: tint))
            case 1: spheres.append(MeshInstance(position: p, scale: 0.6, color: tint))
            default: cones.append(MeshInstance(position: p, rotation: Vector3(0, a, 0), color: tint))
            }
        }
        field.place(Mesh.box(width: 0.8, height: 0.8, depth: 0.8), at: boxes)
        field.place(Mesh.sphere(radius: 0.6), at: spheres)
        field.place(Mesh.cone(radius: 0.5, height: 1.1), at: cones)
    }

    override func draw() {
        background(Color(hex: 0x101218))
        camera(Camera3D(eye: Vector3(6, 3, 6), target: Vector3(2, 0.4, 0)))
        ambientLight(Color(white: 0.15))
        directionalLight(Color(white: 1), direction: Vector3(-0.5, -0.85, -0.35), intensity: 1)
        castShadows()
        withState {
            fill(Color(white: 0.8))
            drawPlane(width: 24, depth: 24)
        }
        specular(0.3)
        shininess(32)
        drawMeshField(field)
    }
}

/// A ring of pillars from one instanced mesh call: per-copy positions, y
/// rotations, non-uniform scales, and tints over a floor, one directional
/// caster, shadows on. No time and no rng, so it's deterministic.
private final class InstancedMeshScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x101218))
        camera(Camera3D(eye: Vector3(6, 6, 9), target: Vector3(0, 0.8, 0)))
        ambientLight(Color(white: 0.15))
        directionalLight(Color(white: 1), direction: Vector3(-0.5, -0.85, -0.35), intensity: 1)
        castShadows()

        withState {
            fill(Color(white: 0.8))
            drawPlane(width: 14, depth: 14)
        }

        specular(0.3)
        shininess(32)
        fill(Color(hex: 0xB8C4E8))

        let pillar = Mesh.box(width: 0.5, height: 1, depth: 0.5)
        var placements: [MeshInstance] = []
        for i in 0 ..< 40 {
            let a = Double(i) / 40 * .tau
            let r = 1.4 + Double(i % 5) * 0.55
            let h = 0.6 + Double((i * 7) % 11) * 0.22
            placements.append(MeshInstance(
                position: Vector3(cos(a) * r, h / 2, sin(a) * r),
                rotation: Vector3(0, a, 0),
                scale: Vector3(1, h, 0.7),
                color: Color(red: 0.6 + 0.4 * cos(a), green: 0.7, blue: 1, alpha: 1)))
        }
        drawMesh(pillar, instances: placements)
    }
}

private final class RetainedBatchScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    private var motif: Batch!

    override func setup() {
        motif = makeBatch {
            noStroke()
            fill(Gradient.linear(from: Vector2(-36, -60), to: Vector2(36, -20),
                                 [Color(hex: 0x4FC3F7), Color(hex: 0xE84C8B)]))
            drawRect(-36, -60, 72, 40)
            fill(Color(hex: 0xE8A23C))
            drawPolygon([Vector2(-40, 24), Vector2(0, -8), Vector2(40, 24),
                         Vector2(0, 10)])                 // concave: the triangle path
            stroke(Color(hex: 0xD6E2FF))
            strokeWeight(3)
            noFill()
            drawPolyline([Vector2(-40, 40), Vector2(-12, 30), Vector2(12, 46),
                          Vector2(40, 34)])               // the fringe path
            noStroke()
            fill(Color(hex: 0x66D48A))
            smoothUnion(k: 12) {                          // the SDF-combinator path
                drawCircle(-14, 66, 14)
                drawCircle(14, 66, 14)
            }
            fill(Color(hex: 0xF2F2F2))
            drawStar(0, -84, 16, 7, points: 5)            // a plain SDF instance
        }
    }

    override func draw() {
        background(Color(hex: 0x14141E))
        withState {
            translate(72, 84)
            drawBatch(motif)                              // identity replay
        }
        fill(Color(hex: 0xD84C4C))
        noStroke()
        drawCircle(104, 96, 18)                           // dynamic, over the first replay
        withState {
            translate(178, 160)
            rotate(0.5)
            scale(1.25)
            drawBatch(motif)                              // transformed stamp, over the circle
        }
    }
}

/// The hex and triangle grids on one sheet: a pointy-top hex grid tinted by
/// hex distance from its center cell, a flat-top grid tinted by column, and a
/// triangle grid whose up/down parity splits two palettes. No rng and no
/// `time`, so it's deterministic.
private final class TilingGridsScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x101318))
        noStroke()

        let hexes = HexGrid(in: Rectangle(x: 0, y: 0, width: 128, height: 128),
                            columns: 6, rows: 6, padding: 5, gutter: 2)
        let home = hexes.cell(column: 3, row: 3)
        for cell in hexes.cells {
            let rings = Double(hexes.distance(from: home, to: cell))
            fill(Color.mix(Color(hex: 0x7BE0C8), Color(hex: 0x15414B), t: min(1, rings / 5)))
            drawPolygon(cell.corners)
        }

        let flat = HexGrid(in: Rectangle(x: 128, y: 0, width: 128, height: 128),
                           columns: 6, rows: 6, orientation: .flat, padding: 5, gutter: 2)
        for cell in flat.cells {
            fill(Color.mix(Color(hex: 0xF9DC5C), Color(hex: 0xC5283D), t: Double(cell.column) / 5))
            drawPolygon(cell.corners)
        }

        let tris = TriangleGrid(in: Rectangle(x: 0, y: 128, width: 256, height: 128),
                                columns: 13, rows: 6, padding: 5, gutter: 2)
        for cell in tris.cells {
            let t = Double(cell.column) / Double(tris.columns - 1)
            fill(cell.pointsUp
                ? Color.mix(Color(hex: 0x113A4E), Color(hex: 0x3FB8AF), t: t)
                : Color.mix(Color(hex: 0x3A1330), Color(hex: 0xEE7752), t: t))
            drawPolygon(cell.vertices)
        }
    }
}

/// Recursive subdivision both ways: a binary aspect-aware split with seeded
/// accent fills beside a probabilistic quadtree tinted by depth. Seeded and
/// `time`-free, so it's deterministic.
private final class SubdivisionScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        seed(5)
        background(Color(hex: 0xF4EFE6))

        stroke(Color(hex: 0x14110F))
        strokeWeight(3)
        strokeJoin(.miter)
        let accents: [Color] = [Color(hex: 0xC5283D), Color(hex: 0xF9DC5C), Color(hex: 0x255C99)]
        for cell in subdivide(in: Rectangle(x: 8, y: 8, width: 116, height: 240),
                              minSize: 22, maxDepth: 6, chance: 0.8) {
            if random(0, 1) < 0.25 {
                fill(randomChoice(accents))
            } else {
                fill(Color(hex: 0xF4EFE6))
            }
            drawRect(cell.frame)
        }

        noStroke()
        for cell in subdivide(in: Rectangle(x: 132, y: 8, width: 116, height: 240),
                              minSize: 10, maxDepth: 5, chance: 0.75, style: .quad) {
            fill(Color.mix(Color(hex: 0x0E1116), Color(hex: 0x7BE0C8), t: Double(cell.depth) / 5))
            drawRect(cell.frame.inset(by: 1))
        }
    }
}

/// Three perfect mazes, one per carving algorithm, each with its longest path
/// traced through. Seeded and `time`-free, so the mazes are deterministic.
private final class MazeScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        seed(7)
        background(Color(hex: 0x101318))
        strokeCap(.round)
        noFill()

        let algorithms: [Maze.Algorithm] = [.backtracker, .kruskal, .wilson]
        let accents: [Color] = [Color(hex: 0xF6511D), Color(hex: 0xF9DC5C), Color(hex: 0x7BE0C8)]
        for (i, algorithm) in algorithms.enumerated() {
            let rect = Rectangle(x: 10, y: 10 + Double(i) * 82, width: 236, height: 72)
            let m = maze(columns: 19, rows: 6, algorithm: algorithm)
            stroke(Color(hex: 0xD8DEE9))
            strokeWeight(2)
            drawMaze(m, in: rect)
            stroke(accents[i])
            strokeWeight(3)
            drawPolyline(m.contour(of: m.longestPath(), in: rect).points, closed: false)
        }
    }
}

/// An Apollonian gasket tinted by generation order: the closed-form foam of
/// mutually tangent circles. No rng and no `time`, so it's deterministic.
private final class ApollonianScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0E1116))
        let rim = Circle(x: 128, y: 128, radius: 118)
        noFill()
        stroke(Color(hex: 0x2A3140))
        strokeWeight(2)
        drawCircle(rim)

        let foam = apollonianGasket(in: rim, minRadius: 1.6)
        noStroke()
        for (i, circle) in foam.enumerated() {
            fill(Color.mix(Color(hex: 0x1D5C63), Color(hex: 0xF9DC5C),
                           t: Double(i) / Double(foam.count)))
            drawCircle(circle)
        }
    }
}

/// Two 1D cellular automata drawn as stacked generations, side by side: elementary
/// rule 30 on the left, 3-color totalistic code 777 on the right. Both grow from a
/// single center seed. Pure CPU, no rng and no `time`, so it's deterministic.
private final class CellularAutomataScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0E1116))
        let columns = 41, generations = 41
        let inks = [Color(hex: 0xF2E9D8), Color(hex: 0xE89A3C), Color(hex: 0x5FA8A0)]
        let cell = 118.0 / Double(columns)
        let elementary = elementaryCA(rule: 30, width: columns, generations: generations)
            .map { $0.map { $0 ? 1 : 0 } }
        let totalistic = totalisticCA(code: 777, colors: 3, width: columns,
                                      generations: generations)
        noStroke()
        for (side, field) in [elementary, totalistic].enumerated() {
            let x0 = 8.0 + Double(side) * 124
            for r in 0 ..< generations {
                for c in 0 ..< columns where field[r][c] > 0 {
                    fill(inks[(field[r][c] - 1) % inks.count])
                    drawRect(x0 + Double(c) * cell, 66 + Double(r) * cell,
                             cell * 0.9, cell * 0.9)
                }
            }
        }
    }
}

/// Langton's ant stepped 14,000 moves on a wrapped 128-cell grid in the first frame:
/// the chaotic blob plus the emerged highway. Pure CPU, no rng, deterministic.
private final class TurmiteScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private let machine = Turmite(.langton, columns: 128, rows: 128)

    override func draw() {
        if machine.stepCount == 0 { machine.step(14000) }
        background(Color(hex: 0x100E14))
        let cell = width / 128
        noStroke()
        fill(Color(hex: 0xEAE3D4))
        for painted in machine.paintedCells {
            drawRect(Double(painted.column) * cell, Double(painted.row) * cell, cell, cell)
        }
        fill(Color(hex: 0xFF7B4D))
        for ant in machine.antPositions {
            drawCircle((Double(ant.column) + 0.5) * cell, (Double(ant.row) + 0.5) * cell, cell * 1.5)
        }
    }
}

/// A multi-scale Turing `SimField` left entirely alone: it starts from its own seeded
/// noise and organizes itself, so there is nothing to draw into it and no `withField`
/// block at all. Pins the dedicated pipeline and the read-registers-the-field path.
private final class MultiScaleTuringScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    var field: SimField!

    override func setup() { field = simField(.multiScaleTuring(seed: 4), scale: 0.5) }

    override func draw() {
        background(.black)
        drawImage(field.filtered(.relight(height: 0.35)).image, 0, 0)
    }
}

/// An Abelian sandpile `SimField` dropped as one heavy mountain on frame 1 (no
/// random, no time) and caught mid-collapse, recolored one color per grain count.
/// Deterministic: the pour is a fixed mark, the toppling a pure gather.
private final class SandpileScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    var pile: SimField!

    override func setup() { pile = simField(.sandpile(pour: 1024), scale: 1) }

    override func draw() {
        background(.black)
        withField(pile) {
            if frameCount == 1 {
                noStroke()
                fill(.white)
                drawCircle(width / 2, height / 2, 4)
            }
        }
        let counts = Ramp(stops: [(0.00, Color(hex: 0x10141F)),
                                  (0.25, Color(hex: 0x2C6E91)),
                                  (0.50, Color(hex: 0xE3A857)),
                                  (0.75, Color(hex: 0xF2E9DC)),
                                  (1.00, .white)])
        drawImage(pile.filtered(.gradientMap(counts)).image, 0, 0)
    }
}

/// The classic cyclic cellular automaton from its seeded random start, recoloured
/// by a closed hue wheel. Deterministic: the start is the seeded state fill, the
/// rule a pure gather.
private final class CyclicScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    var field: SimField!

    override func setup() { field = simField(.cyclic(seed: 4), scale: 0.5) }

    override func draw() {
        background(.black)
        let wheel = Ramp(stops: (0 ... 6).map {
            (position: Double($0) / 6,
             color: Color(hue: Double($0) / 6, saturation: 0.72, brightness: 0.95))
        })
        drawImage(field.filtered(.gradientMap(wheel)).image, 0, 0)
    }
}

/// A Greenberg-Hastings medium sparked by a fixed script (no random, no time): a
/// line and four dots on frame 1, half the plane wiped at frame 30 so the broken
/// front curls into a spiral pair.
private final class ExcitableScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    var field: SimField!

    override func setup() { field = simField(.excitable(states: 5), scale: 0.5) }

    override func draw() {
        background(.black)
        withField(field) {
            noStroke()
            if frameCount == 1 {
                fill(.white)
                drawRect(64, 140, 128, 3)
                for p in [(40.0, 40.0), (200.0, 60.0), (60.0, 210.0), (210.0, 200.0)] {
                    drawCircle(p.0, p.1, 3)
                }
            }
            if frameCount == 30 {
                fill(.black)
                drawRect(0, 0, 256, 132)
            }
        }
        drawImage(field.filtered(.gradientMap(.inferno)).image, 0, 0)
    }
}

/// Brian's Brain lit by a seeded sprinkle of single firing cells (a solid blob
/// dies at once, so the soup is the protocol), under the classic ramp.
private final class BriansBrainScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    var field: SimField!

    override func setup() {
        field = simField(.briansBrain(), scale: 0.5)
        randomSeed(7)
    }

    override func draw() {
        background(.black)
        withField(field) {
            noStroke()
            if frameCount == 1 {
                fill(.white)
                for _ in 0 ..< 1400 {
                    drawCircle(random(width), random(height), 1.1)
                }
            }
        }
        let glow = Ramp(stops: [(0.0, Color(hex: 0x05070C)),
                                (0.5, Color(hex: 0x3A6BD8)),
                                (1.0, .white)])
        drawImage(field.filtered(.gradientMap(glow)).image, 0, 0)
    }
}

/// A hodgepodge machine on the classic constants from its seeded random start,
/// recoloured with turbo. Deterministic: the start is the seeded state fill.
private final class HodgepodgeScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    var field: SimField!

    override func setup() { field = simField(.hodgepodge(seed: 4), scale: 0.5) }

    override func draw() {
        background(.black)
        drawImage(field.filtered(.gradientMap(.turbo)).image, 0, 0)
    }
}

/// A Lenia `SimField` seeded with a fixed grid of graded-alpha dots (no random/time),
/// run to frame 60 and recoloured. Pins the continuous-CA fragment: the normalized
/// ring-kernel convolution, the bell growth, and the dt integration and clip.
private final class LeniaScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    var life: SimField!
    var seeded = false

    override func setup() { life = simField(.lenia(), scale: 0.5) }

    override func draw() {
        withField(life) {
            if !seeded {
                noStroke()
                for i in 0 ..< 5 {
                    for j in 0 ..< 5 {
                        fill(Color(white: 1, alpha: 0.3 + 0.65 * Double((i * 3 + j * 5) % 7) / 6))
                        drawCircle((Double(i) + 0.5) * width / 5, (Double(j) + 0.5) * height / 5, 18)
                    }
                }
                seeded = true
            }
        }
        drawImage(life.filtered(.gradientMap(.magma)).image, 0, 0)
    }
}

/// A scripted watercolor painting on a fixed sheet of paper: wash, wet-in-wet
/// charge, dry, glaze. Fixed paper seed, fixed frames, no rng: deterministic.
private final class WatercolorSimScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    var paint: WatercolorField!

    override func setup() {
        paint = watercolor(.watercolor(pigments: [.frenchUltramarine, .quinacridoneRose, .hansaYellow],
                                       paperSeed: 7),
                           scale: 1)
    }

    override func draw() {
        withField(paint) {
            noStroke()
            switch frameCount {
            case 1:
                fill(paint.ink(0, load: 0.5))
                for i in 0 ... 8 {
                    let t = Double(i) / 8
                    drawCircle(48 + t * 160, 96 + sin(t * .tau) * 8, 34)
                }
            case 30:
                fill(paint.ink(1, load: 0.6, water: 0.6))
                for i in 0 ... 4 {
                    drawCircle(88 + Double(i) * 20, 100, 16)
                }
            case 60:
                paint.dry()
            case 62:
                fill(paint.ink(2, load: 0.4))
                for i in 0 ... 8 {
                    drawCircle(150, 30 + Double(i) * 25, 26)
                }
            default: break
            }
        }
        drawImage(paint.image, 0, 0)
    }
}

/// The three bundled IFS presets condensed by seeded chaos games, one per
/// panel. Seeded, no `time`, so it's deterministic.
private final class IFSScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x101318))
        noStroke()
        fill(Color(white: 0.92, alpha: 0.7))
        let systems: [(IFS, Bool)] = [(.barnsleyFern, true),
                                      (.sierpinskiTriangle, true),
                                      (.sierpinskiCarpet, false)]
        var rng = SplitMix64(seed: 6)
        for (index, entry) in systems.enumerated() {
            let frame = Rectangle(x: 6 + Double(index) * 82, y: 64,
                                  width: 76, height: 128)
            var cloud = entry.0.points(count: 9_000, using: &rng)
            if entry.1 { cloud = cloud.map { Vector2($0.x, -$0.y) } }
            drawPoints(fitted(cloud, in: frame), size: 1)
        }
    }
}

/// The tangent-ring inversion limit set over its drawn mirrors. Seeded, no
/// `time`, so it's deterministic.
private final class InversionFractalScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0D0F14))
        let center = Vector2(128, 128)
        let ringRadius = 88.0
        let radius = ringRadius * sin(.pi / 5)
        var mirrors: [Circle] = (0 ..< 5).map { i in
            let angle = Double(i) / 5 * 2 * .pi
            return Circle(center: Vector2(center.x + cos(angle) * ringRadius,
                                          center.y + sin(angle) * ringRadius),
                          radius: radius)
        }
        mirrors.append(Circle(center: center, radius: ringRadius - radius))
        noFill()
        stroke(Color(hex: 0x2A3242))
        drawCircles(mirrors)
        var rng = SplitMix64(seed: 4)
        fill(Color(hex: 0xE8C97D, alpha: 0.8))
        drawPoints(inversionLimitSet(of: mirrors, count: 9_000, using: &rng), size: 1)
    }
}

/// Two Kleinian limit-set curves, the gasket above the lace, each one
/// ordered closed polyline. No rng and no `time`, so it's deterministic.
private final class KleinianScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0B0D12))
        noFill()
        stroke(Color(white: 0.85))
        strokeWeight(1)
        let top = kleinianLimitSet(.gasket, epsilon: 0.012)
        drawPolyline(fitted(top.points, in: Rectangle(x: 16, y: 8, width: 224, height: 112)),
                     closed: true)
        let bottom = kleinianLimitSet(.lace, epsilon: 0.012)
        drawPolyline(fitted(bottom.points, in: Rectangle(x: 16, y: 136, width: 224, height: 112)),
                     closed: true)
    }
}

/// A Schottky circle orbit twice over: the kissing pair arrangement above,
/// the gasket-trace group's orbit below. No rng and no `time`, so it's
/// deterministic.
private final class SchottkyScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0B0D12))
        noFill()
        stroke(Color(white: 0.8, alpha: 0.55))
        strokeWeight(0.6)
        let top = Rectangle(x: 8, y: 8, width: 240, height: 116)
        for circle in schottkyCircles(pairing: schottkyCuspedPairs(in: top),
                                      minRadius: 0.5, maxDepth: 60) {
            drawCircle(circle)
        }
        let bottom = Rectangle(x: 8, y: 132, width: 240, height: 116)
        withClip(bottom) {
            for circle in schottkyCircles(ta: Vector2(2, 0), tb: Vector2(2, 0),
                                          in: bottom, minRadius: 0.5, maxDepth: 60) {
                drawCircle(circle)
            }
        }
    }
}

/// A seeded random flame at a fixed sample count, developed once. Seeded and
/// sample-fixed, so it's deterministic.
/// A seeded Buddhabrot plate at a fixed orbit count in the three-cap
/// false-color split: pins the orbit test, the seed region, the mirrored
/// deposit, the cap gating, and the percentile develop.
private final class BuddhabrotScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private var picture: Image?

    override func setup() {
        let plate = Buddhabrot(iterations: [600, 120, 30])
        let renderer = Buddhabrot.Renderer(plate, width: 128, height: 128, seed: 12)
        renderer.accumulate(samples: 250_000)
        picture = renderer.image()
    }

    override func draw() {
        background(.black)
        if let picture { drawImage(picture, in: canvasRectangle) }
        noLoop()
    }
}

private final class FractalFlameScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private var picture: Image?

    override func setup() {
        var rng = SplitMix64(seed: 12)
        let flame = FractalFlame.random(using: &rng)
        let renderer = FractalFlame.Renderer(flame, width: 128, height: 128, seed: 12)
        renderer.accumulate(samples: 700_000)
        picture = renderer.image()
    }

    override func draw() {
        background(.black)
        if let picture { drawImage(picture, in: canvasRectangle) }
    }
}

/// Two surfaces grown to a fixed step count: a sphere under even growth beside
/// one grown only in a band around its equator. Fixed camera, fixed seeds, no
/// time.
private final class SurfaceFromPointsScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    /// Golden-spiral sphere sample: deterministic, no randomness.
    private func spherePoints(_ count: Int, radius: Double) -> [Vector3] {
        let golden = Double.pi * (3 - 5.0.squareRoot())
        return (0 ..< count).map { i in
            let y = 1 - 2 * (Double(i) + 0.5) / Double(count)
            let ring = (1 - y * y).squareRoot()
            let angle = golden * Double(i)
            return Vector3(cos(angle) * ring, y, sin(angle) * ring) * radius
        }
    }

    override func draw() {
        background(Color(hex: 0x0A0D12))
        lightingPreset(.studio)
        camera(Camera3D.orbiting(target: .zero, radius: 9.5,
                                 azimuth: 0.55, elevation: 0.4, fieldOfView: .pi / 4))

        let sample = spherePoints(900, radius: 1.05)
        let closed = reconstructSurface(of: sample, resolution: 44, maxGap: .infinity)
        let opened = reconstructSurface(of: sample.filter { $0.y < 0.4 }, resolution: 44)

        let helix = (0 ..< 60).map { i -> Vector3 in
            let t = Double(i) / 59 * 2 * .tau
            return Vector3(cos(t) * 0.7, (Double(i) / 59 - 0.5) * 1.6, sin(t) * 0.7)
        }
        let skin = particleSurface(of: helix, radius: 0.24, blend: 2, resolution: 56)

        fill(Color(hex: 0xE2603A))
        withState {
            translate(-2.6, 0, 0)
            drawMesh(closed)
        }
        withState {
            drawMesh(opened)
        }
        withState {
            translate(2.6, 0, 0)
            drawMesh(skin)
        }
    }
}

private final class MeshGrowthScene: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0A0D12))
        lightingPreset(.studio)
        camera(Camera3D.orbiting(target: .zero, radius: 9.5,
                                 azimuth: 0.6, elevation: 0.42, fieldOfView: .pi / 4))

        let seedMesh = Mesh.icosphere(radius: 0.8, subdivisions: 2)

        let even = MeshGrowth(mesh: seedMesh, driver: .uniform, edgeLength: 0.13, seed: 5)
        even.maxVertices = 2400
        even.step(70)

        let banded = MeshGrowth(mesh: seedMesh,
                                driver: .field { position, _ in
                                    1 - smoothstep(0.08, 0.5, abs(position.y))
                                },
                                edgeLength: 0.13, seed: 5)
        banded.maxVertices = 2400
        banded.step(70)

        fill(Color(hex: 0xE2603A))
        withState {
            translate(-2.3, 0, 0)
            drawMesh(even.mesh)
        }
        withState {
            translate(2.3, 0, 0)
            drawMesh(banded.mesh)
        }
    }
}
