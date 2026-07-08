# Ollin architecture & internals

This document explains how Ollin's larger systems work *inside*: the rendering
pipeline, the effect graph, and the engineering rationale behind the choices
that are not obvious from the code. It is written for contributors (and the AI
agents that help them) who are about to change one of these systems and need to
know which invariants are load-bearing and why.

It is deliberately separate from the other docs:

- **[`CLAUDE.md`](CLAUDE.md)** is the always-loaded development guidance: the
  rules, the architecture decisions that constrain new work, the cross-cutting
  gotchas, and a one-line-per-feature capability index. It states *what* the
  invariants are; this file explains *why* they hold and *how* the machinery
  behind them works.
- **[`Docs/`](Docs/)** is the user-facing API reference (`Sketch`, `Drawing`,
  `Color`, ...). It documents how to *call* a feature, not how it is built.
- **[`ROADMAP.md`](ROADMAP.md)** and **[`DESIGN-NOTES.md`](DESIGN-NOTES.md)** are
  forward-looking only: what is planned and the design intent behind it.

So the split is: planned work in ROADMAP/DESIGN-NOTES, how to use a shipped
feature in Docs/, the rules and the index in CLAUDE.md, and the deep internals
of shipped systems here. When a system in CLAUDE.md's *Current state* needs more
than its terse invariant, the depth lives here and CLAUDE.md keeps a pointer.

This document is populated one system at a time, so it is intentionally
partial. The map below lists Ollin's major systems and where each one's
internals are documented today; CLAUDE.md's *Current state* section remains the
complete capability index regardless.

---

## Systems map

| System | Where its internals are documented |
| --- | --- |
| Renderer core (frame lifecycle, pipeline families, vertex-buffer ring, coverage models, linear-light present) | This doc, *The renderer at a glance*; the rules live in CLAUDE.md *Shaders & the Metal back end* / *Rendering performance* |
| Screen-space combine effects (SSAO, SSR, depth of field) | **This doc** |
| SDF combinators (2D VM + raymarched 3D) | **This doc** |
| Layered-effects substrate (render targets, filters, generators, compose, combine, feedback, sim fields / fluid) | **This doc**, *Layered-effects substrate* (the combine wiring under *Screen-space combine effects*) |
| 3D lighting (PBR / Cook-Torrance, IBL split-sum bake, procedural sky, PCSS + RT shadows, RT reflections) | **This doc**, *3D lighting and environments* (the reflection anti-aliasing chain under *Deferred ray-traced reflection AA*) |
| Text & glyphs (libtess2 fill, winding / overlap-clean gotchas, fringe stroke, SDF atlas) | Pending here; CLAUDE.md + `Docs/Drawing/Text.md` |
| Compute & GPU particles | Pending here; CLAUDE.md + `Docs/Shaders/Compute.md` |
| User-supplied shaders | **This doc**, *User-supplied shaders* |
| Camera rig (showcase orbit, view snaps, scene chrome) | **This doc**, *Camera rig: showcase orbit, view snaps, and scene chrome* |
| Satellites (audio, OSC, MIDI, Syphon, virtual camera, video, physics, vision, Record3D, phone) | `Docs/` per satellite + the cross-cutting satellite gotchas in CLAUDE.md |
| Live reload (OllinLive) | CLAUDE.md *Live reload* |

A *pending* row means the system's deep internals are not yet written up here:
its load-bearing invariants are in CLAUDE.md and its public API is in `Docs/`,
but the mechanism-and-why depth has not been migrated. Those rows are the
migration checklist (see *Status of this document* at the end).

---

## The renderer at a glance

Ollin's drawing model is *immediate-mode GPU*. There is no retained scene graph:
every frame, `Sketch.draw()` issues bare drawing calls that forward to a
`Drawer`, the `Drawer` records geometry, and once per frame `MetalRenderer` turns
that recording into GPU work. Understanding this flow makes every other section
easier, because each effect and each pipeline plugs into the same frame.

**The Drawer is a pure recorder.** It tessellates or encodes each primitive into
call-ordered `GeometryBatch`es, tagging each with its kind (triangles, SDF,
fringe stroke, image, glyph, mesh, point cloud, SDF group) and its render target.
It never talks to the GPU. That is what lets one recording drive the live window,
the headless `image(of:)` export, and the off-screen effect layers without
change, and it is why draw order is preserved: batches composite front-to-back in
the order the sketch drew them, so SDF shapes, tessellated fills, and 3D meshes
interleave correctly. Collapsing the call-ordered batches into unordered per-kind
passes would break occlusion.

**MetalRenderer resolves a small render graph.** At `render()`/`image(of:)` time
it runs, in order: any off-screen render-target passes (each target's tagged
batches into its own MSAA-resolve pass), the filter and combine ops that read
those layers, the main geometry pass, then the post-process and present pass. A
2D sketch with no targets takes a fast path that is byte-identical to a single
direct pass.

**Geometry rides several pipelines, cached by descriptor.** The pipeline families
are a tessellated-triangle path (libtess2 fills under 8x/4x MSAA), an instanced
analytic-SDF path (one quad per shape, fill/stroke/AA computed in the fragment), a
fringe-stroke path (the high-quality stroke renderer: CPU edge-expansion plus a
1px anti-aliasing fringe), a textured-quad image path, a glyph-atlas path, the 3D
mesh path, and the SDF-combinator and raymarch paths. They are built through a
cache keyed on a descriptor (shader, blend mode, sample count, pixel format), so a
new variant is a cache lookup rather than more constructor code. The CPU-to-GPU
structs these pipelines share are defined once in
`Sources/Ollin/Renderer/OllinShaderTypes.h`.

**Uploads go through a triple-buffered, semaphore-gated vertex-buffer ring.**
Writing a buffer the GPU is still reading for an in-flight frame tears the
geometry on screen, so the ring (`maxFramesInFlight` slots, a frame-boundary
semaphore) hands each frame its own buffer. This is load-bearing: do not collapse
it back to one shared buffer.

**Compositing is linear-light, with a single present pass.** Geometry composites
into a linear `rgba16Float` intermediate, so the hardware blends and resolves MSAA
physically; a final present pass tone-maps and dithers that float frame down to
the sRGB drawable, which is the one place 8-bit quantization happens. Shaders
linearize their sRGB color inputs, the clear color is linearized too, and
stroke/disk coverage is remapped to perceptual alpha so thin dark marks stay dark.

The rules and invariants behind all of this (the exact coverage models, the
shared-header discipline, the shader-segment concatenation order, the
precompiled-metallib path) live in CLAUDE.md under *Shaders & the Metal back end*
and *Rendering performance*. This section orients you; those sections hold the
invariants you must not break.

---

## Layered-effects substrate

The layered-effects system (`Sources/Ollin/Effects/`) lets a sketch draw into
off-screen layers, filter them on the GPU, and composite them back with blend
modes, following the OPENRNDR `RenderTarget`/`Filter`/`compose` model. The
public surface is in `Docs/Drawing/Effects.md`; this section explains the
machinery behind it: how the deferred graph resolves, how filters, generators,
and the persistent feedback/simulation layers run, and the invariants that were
each bought with a real bug.

### The deferred render graph

The `Drawer` stays a pure recorder. `withTarget(_:)` redirects drawing by
tagging each recorded `GeometryBatch` with its `target: RenderTarget?` (forcing
a fresh batch at each boundary), and the drawer records the frame's
`renderTargets`, `filterOps`, and `frameFilters` lists. `MetalRenderer` resolves
that graph at `render()`/`image(of:)` time, in order: each geometry target's
tagged batches render into their own MSAA-resolve pass; the filter and combine
ops run (MPS or fragment passes) into pooled textures; the main pass runs and
samples the results (`target.image` composites through the textured-quad path,
`Image(renderTarget:)`); and `postProcess` filters run on the resolved frame
before present. The no-targets path is gated on those three lists being empty
and is byte-identical to a direct render.

Everything stays GPU-resident: layers are render-pass attachments and filter
inputs are sampler binds, never a CPU round-trip (the layer-as-uniform upload
that makes naive layer systems unusably slow). Layers are premultiplied linear,
so blur and bloom composite physically and tone-map plus dither still happen
exactly once, at present. A layer's `scale` renders it at fraction resolution
for fill-rate-bound effects, and layer textures are pooled per frame-ring slot.

**The layer blocks scope the drawing state.** `withTarget`, `withFeedback`, and
`withField` push and pop the drawing state around their block (the documented
`withState`-like scoping), so a `blendMode` or style set inside a layer block
never leaks to the canvas. Leaking was a real bug; the fix changed no
snapshots, and `Feedback.filtered(_:)` mirrors `SimField.filtered(_:)` (both
forward to their write layer).

**Every `GeometryBatch` begin must snapshot all the `*Start` offsets.** A
batch's vertex count for each kind is `next.<kind>Start - this.<kind>Start`, so
a batch creator that omits one offset silently zeroes the count of a *preceding*
batch of that kind. The image/glyph/particle/depthScene begins once omitted
`meshStart`, which was harmless until a 3D mesh in a render target was followed
by `drawImage`/`drawCaption` (the `SceneDefocus` case); all begins now snapshot
every offset.

### Filters and generators

`Filter` is a ~55-entry catalog in six families (blur/glow, color/tone,
stylize/optical, retro, uv-warp distortion, and the design filters; the full
per-filter list lives in `Docs/Drawing/Effects.md`). Every filter is a
fullscreen-triangle fragment pass on the `.effect` pipeline, reusing
`ollin_present_vertex` plus an `ollin_fx_*` fragment, reading and writing
premultiplied linear. Most are single-sample; a handful (`bilateral`,
`motionBlur`, `radialBlur`, `oilPaint`, `median`, the halftones) gather several
taps; only `.gaussianBlur` and bloom's internal blur use MPS
(`MPSImageGaussianBlur`). `.bloom` is bright-pass, blur, add-back.
`.gradientMap` binds a baked 256-step LUT (`rgba32Float`) as a second texture.

A few filter internals are worth pinning. `.relight` (the height-map material
pass, with matte/metal/glass/sand/liquid finishes) derives its normal from a
Sobel gradient that must be uv-normalized, or high-resolution relief flattens.
The radial warps take a `center:` in layer fractions and are byte-identical at
the 0.5 default. Among the design filters, `.flutedGlass`/`.water`/
`.paperTexture` transform the layer while `.liquidMetal`/`.heatmap`/`.gemSmoke`
read its alpha shape (draw a shape, filter it): liquid metal and gem smoke
consume a true interior-inflation field solved per frame as coarse-to-fine
Jacobi fragment passes (`poissonInteriorField`), chosen because it is both
smooth and boundary-exact where a blur leaks across concavities and a distance
transform creases at the medial axis; heatmap preps a Gaussian halo
(`blurredAlphaFields`, matching its blur-based reference).

Two conventions keep the color math honest: the distortion warps only move
texels (premultiplied values pass through untouched), while the color/stylize
filters un-premultiply, run the straight-color op, and re-premultiply. The
per-pass uniform is a packed `[SIMD4<Float>]` (`constant float4 *params`,
widened from a single `float4`) so one filter can carry several params and
colors. New filter built-ins are written from the published technique and
credited in `ATTRIBUTION.md`'s Techniques list, never in `.swift` comments.

`Generator` (`generate(_:)`) is the input-less sibling: a procedural pattern
filled into a `RenderTarget` by a no-input fragment pass (a `.generator`
`RenderTarget.Origin`), resolved ahead of the geometry and filter passes. The
catalog is the four basics (`.checkers`/`.gridLines`/`.bars`/`.noise`,
`ollin_gen_*`), the design-pattern set (`.meshGradient`/`.filaments`/
`.smokeRing`/`.colorPanels`/`.spiral`/`.waves`/`.dotOrbit`/`.grainGradient`/
`.pulsingBorder`/`.godRays`, in `ShaderPatterns.metal`), the pattern fields
(`.quasicrystal`/`.moire`/`.gyroid`/`.phyllotaxis`/`.hexPulse`, closed-form
animated fields sharing `ollin_pat_ramp`), and the escape-time fractals
(`.mandelbrot`/`.julia`, smooth iteration count through a cosine palette fold).
`generate(_:width:height:)` fills an explicit-size layer, so patterns compose
per-layer instead of being squashed into full-canvas fills (the Shader and
Visual `generate` forms have the same explicit-size overloads). One nuance: a
fine 1px pattern averages away when its layer is drawn smaller, which is why
the `dither` generator takes a `pixelSize`.

Three design-pattern invariants hold across that set. Animation is an explicit
`phase` parameter (feed `time`), so exports and snapshots are deterministic
with no hidden clock. Palettes ride as trailing float4 rows after the scalar
rows of the packed params buffer. And the fragments blend palettes and
composite internally in sRGB (`ollin_pat_stop`/`ollin_pat_out`), converting to
premultiplied linear only on output: designer palettes mixed in linear read as
washed-out pastel (a real bug), and the mesh gradient's inverse-distance
weighting especially depends on this.

### Feedback (previous-frame) layers

`feedback(scale:)` returns a *persistent* `Feedback` layer: made once in
`setup()` and held, unlike the per-frame `RenderTarget`, because its identity is
what carries state across frames. `withFeedback(_:) { prev in ... }` redirects
drawing into it and hands in last frame's result as `prev` (the
`withTarget(Feedback)` form reads `feedback.previous` by name instead), and
`feedback.image` composites this frame's result.

Under the hood it is a two-texture ping-pong kept in a persistent map keyed by
the layer's identity (`MetalRenderer.feedbackSlots`, separate from the per-frame
texture pools): the renderer draws into the back texture while the block reads
the front, then flips after the frame. It relies on Metal's automatic GPU-to-GPU
hazard tracking (feedback is inherently serial, so no extra semaphore), and
slots are pruned by a weak owner reference on live reload. The
`RenderTarget.Origin.feedback(Feedback)` case routes the write layer to the
ping-pong storage.

**Headless warmup gotcha:** `image(of:frame:)` must render *every* warmup frame
when `drawer.usesFeedback`, exactly like accumulation, not just `stepCompute`,
or the ping-pong never evolves; the built-up state is what a single-frame export
and the `effects-feedback` snapshot depend on. `usesFeedback` counts feedback
layers, sim fields, and SSR ops alike.

### Simulation fields

`simField(_:scale:)` returns a persistent `SimField` (`Effects/SimField.swift`)
that runs a built-in `Sim` on its state each frame: the stateful sibling of the
stateless `Filter`. `Sim` is a `Sendable` value catalog like `Filter`:
`.reactionDiffusion(feed:kill:)` (Gray-Scott), `.gameOfLife` (Conway), and
`.fluid(...)`. A sketch draws into the field to seed or force it
(`withField(_:_:)`, scoped like `withTarget`): the renderer renders the drawn
marks into a transient seed texture, runs `ollin_sim_inject` to composite the
seeds onto the front state, then steps the sim's `ollin_sim_*` fragment N
sub-steps per frame (reaction-diffusion 14, Game of Life 1), ping-ponging pooled
scratch into the back buffer (`runSimulation` in `MetalRenderer`).

Sim fields reuse the feedback path: the `RenderTarget.Origin.simField(SimField)`
case routes to the same persistent ping-pong storage (`FeedbackSlot`, whose
owner is `AnyObject`), and `feedbackSlot(for:restState:)` clears a fresh pair to
the sim's *rest state* (reaction-diffusion rests at A=1, B=0; Game of Life
dead), not to transparent. The field itself is raw state, not a picture:
`SimField.image` shows it, and `SimField.filtered(_:)` recolors it through the
`Filter` catalog (the substrate payoff: reaction-diffusion output fed through
`gradientMap`).

`.fluid(...)` is the multi-field sim (a real-time incompressible flow carrying
dye), so it runs a dedicated `runFluid` pipeline (~30 passes/frame) instead of
the single-state step path: a velocity+dye splat (the mark's color becomes dye;
`withField`'s `force:` becomes velocity, converted by dividing by `dt`), curl
plus vorticity confinement, a divergence-free projection via a Jacobi pressure
solve (default 20 iterations) and gradient subtract, then semi-Lagrangian
advection of velocity then dye (Stam stable fluids / GPU Gems / the splat
recipe, written from the technique and credited in `ATTRIBUTION.md`; boundaries
are the clamp-to-edge sampler, and `dt` is a fixed constant for determinism).
Its persistent state is *two* ping-pong pairs (velocity and dye) in a separate
`MetalRenderer.fluidSlots` map keyed by the `SimField`'s identity;
pressure/divergence/curl are per-frame pooled scratch, and
`acquireFilterTexture` hands out a distinct texture per call so the ~8 scratch
passes never alias. Keeping `fluidSlots` beside `FeedbackSlot` keeps the
single-field path byte-identical (verified: no `effects-simfield` or
`effects-feedback` re-record). The brush model is one global `force` per field
per frame; `SimField.image` is the dye, recolorable and bloomable like any
layer.

### Compose DSL, combine ops, and `aside`

`compose { layer { ... }.post(_:).blend(_:).scale(_:) ... }` is the declarative
surface over the substrate: it makes a `renderTarget` per `layer`, draws into it
via `withTarget`, chains the `.post` filters, and composites bottom-to-top in
declared order under each layer's `.blend`. It is pure sugar (a user can
hand-write the same `renderTarget`/`withTarget`/`filtered`/`drawImage`);
`ComposeLayer` is the public value type and `@ComposeBuilder` the result
builder, so `if`/`for` build layers. One load-bearing detail: `layer(_:)`'s draw
closure is `@escaping @_implicitSelfCapture` (it runs synchronously inside
`compose` but is stored in the builder), so bare draw calls inside a `layer { }`
need no `self.`; without the attribute the p5-style feel breaks. Verified: the
attribute propagates across module boundaries to example and test targets.

`Combine` (`Effects/Combine.swift`) is the two-input sibling of `Filter`:
`base.combined(with: aux, op)` reads two layers, covering what one-input filters
cannot. It is a `Sendable` value descriptor like `Filter`, but it cannot hold
the reference-type `RenderTarget`, so the aux rides alongside it and the op
records a `RenderTarget.Origin.combine(base:aux:op:)` case resolved in the same
`filterOps` list as filters; record order guarantees both inputs fill first (the
wiring is detailed under *Shared substrate* in the next section). Six ops:
`.mask` multiplies base by aux luminance/alpha with optional invert
(premultiplied luma, so coverage is honored); `.displace` offsets the base UV by
the aux's RG recentered to within `amount`; `.mix` is a premultiplied
cross-dissolve; `.defocus`, `.ambientOcclusion`, and `.screenSpaceReflections`
are the screen-space effects detailed in the next section. The two inputs may
differ in `scale` (each is sampled by normalized uv).

`aside { }` is the combine's `compose` sugar: it builds the same value as
`layer { }` (its `.blend` unused; an aside never composites), and
`.masked(by:)` / `.displaced(by:amount:)` / `.mixed(with:amount:)` /
`.defocused(by:)` feed it to a layer. A layer's processing is an ordered
`[Step]` (filter or combine) so posts and combines interleave, resolved by one
recursive `resolveComposeLayer`; that is what lets an aside carry its own
`.post` chain (a blurred mask edge, for example).

Substrate credits (recorded in `ATTRIBUTION.md`, never in `.swift`):
AsyncGraphics (architecture and the cross-dissolve/key/displace shape), ofxFX
and orx-fx/OPENRNDR (the catalog, the compose model, the `aside` idea), and
Apple MPS (first-party, in use).

---

## Screen-space combine effects

Ambient occlusion, screen-space reflections, and depth of field are all
**two-input (or three-input) combine ops** in the layered-effects graph
(`Sources/Ollin/Effects/Combine.swift`). They read a rendered color layer plus a
depth layer (and, for AO and SSR, a surface-normal layer), and they run as a
short chain of fullscreen fragment passes on the `.effect` pipeline. They share
one substrate, so understanding that substrate first makes each effect simple.

### Shared substrate: the G-buffer, depth, and the combine path

A combine op records a `RenderTarget.Origin.combine(base:aux:op:)` node, resolved
in the same `filterOps` list as ordinary filters. Record order guarantees both
inputs exist before the op runs (they must already have been drawn to be
referenced). The op binds `[base, aux]` (and `normals` for AO and SSR) and runs
its passes into pooled textures before the main pass samples the result.

Two opt-in attachments make 3D-aware effects possible without taxing 2D sketches:

- **Depth.** A render target that a 3D scene is drawn into carries a
  `depth32Float` MSAA attachment that resolves (`.min`) to a sampleable buffer.
  `target.depth` exposes it as a gray layer (0 near, 1 far) via an
  `ollin_fx_depth_normalize` pass that linearizes clip-space depth over the
  camera's near/far. It is sRGB-encoded so the perceptual decode the effects use
  reads it back exactly. The attachment is gated by `RenderTarget.needsDepth`
  (set from `drawMesh`/`drawPointCloud`/`drawDepthScene`), so a pure-2D target
  carries no depth and is byte-identical to before. The opt-in is two-tier: the
  attachment only when 3D is recorded, the resolve-and-normalize pass only when
  `.depth` is actually read; particles in a target still skip it.
- **Normals.** A dedicated single-purpose mesh pass (`encodeMeshNormals` plus
  `ollin_mesh_normal_vertex`/`_fragment`) writes raw view-space normals into a
  mesh-normal G-buffer. It is a separate pass rather than a second attachment on
  the shared geometry pass, which would force every 2D pipeline to be
  MRT-compatible. It is gated by `RenderTarget.needsNormals`, set in
  `Drawer.recordCombine` when an `.ambientOcclusion` or
  `.screenSpaceReflections` op reads a 3D `base`. So a 2D sketch, or a 3D scene
  that runs neither effect, is byte-identical and pays nothing.

The camera parameters the effects need to reconstruct view-space position
(near, far, FOV, and the unified perspective/ortho/intrinsic form) are stamped
on the depth layer at normalize time as `RenderTarget.depthReconstruction` and
read back through the combine's `aux` target. This is the one piece of non-texture
wiring through the `filterOps` loop, which otherwise only sees textures.

The normal G-buffer began as a single-sample pass and went through two fixes
worth knowing before you touch it, because both are easy to reintroduce:

1. **It must be MSAA-resolved.** As the lone single-sample buffer next to an
   8x-resolved scene depth, a silhouette pixel toggled between the mesh normal
   and the cleared background as the camera moved sub-pixel, which made the AO
   shimmer along edges. Resolving it as MSAA turns that binary snap into a smooth
   sub-pixel slide. (The SSAO accept threshold is correspondingly `> 0.001`, not
   `> 0.5`, so any coverage uses the resolved normal instead of the
   depth-reconstruction fallback.)
2. **The resolve must be depth-aware, not a hardware box-average.** At a
   mesh-versus-background edge a plain resolve is correct: the background samples
   are cleared zero, so the average is the front normal scaled by coverage. But
   at an *internal* silhouette (a near surface's edge against a farther one) a
   box-average blends front and back normals into a tilted one that varies along
   the edge, which tilts the AO hemisphere into a faint dashed occlusion line.
   `ollin_mesh_normal_resolve` averages only the front surface's samples (the
   nearest covered depth, then the samples within half the covered depth span),
   so the stored normal matches the `.min`-resolved scene depth. It stores
   coverage-scaled values (the box-average convention, so it stays identical at
   mesh-versus-background edges; SSAO renormalizes the direction on read).

**No view-space Y-flip.** The stored normal is in the same view space as
`ollin_ssao_viewpos`, whose `-ndcY` already lands the frame y-up. A flip is *not*
needed and would be wrong. This is counter-intuitive enough that a plausible
"the normal needs a Y negate" claim has been made and is incorrect; verify by
rendering the G-buffer (ground and tops read cyan, +y up and +z toward camera)
and checking that AO lands on contact creases, not on box tops.

### Ambient occlusion (`.ambientOcclusion`)

`ollin_fx_ssao` reads the aux as depth, reconstructs view-space position, takes
the surface normal from the G-buffer (or reconstructs it from depth when no
meshes are present), then samples a hemisphere kernel oriented to that normal and
counts a sample as occluding when the visible surface there sits in front of it
(within `radius`, via a depth-discontinuity range-check that rejects across
silhouettes). A second pass, `ollin_fx_ssao_blur`, multiplies the base by a
gently blurred AO. As a post-effect it darkens the final image, not just an
ambient term.

Four choices are load-bearing, each of which fixed a specific worse artifact and
should not be undone while chasing flicker:

- **A dense low-discrepancy Fibonacci hemisphere kernel with no per-pixel
  rotation.** Textbook SSAO rotates a sparse/random kernel per pixel to break the
  coherent-silhouette banding it would otherwise paint onto flat faces (the
  "projected squares" look), then blurs the resulting noise away. But that
  screen-space noise crawls and flickers in crevices as the camera turns. A dense
  near-isotropic Fibonacci kernel avoids the banding with no rotation at all, so
  the estimate is geometry-locked: it moves with the surface rather than crawling
  in screen space. Measured at roughly 2x less flat-face noise than the rotated
  form, and flicker-free.
- **A continuous (branchless) Duff basis** for orienting the kernel to the
  normal. A hard axis branch (such as `abs(N.x) < 0.9`) makes the whole AO term
  pop as a face crosses the branch boundary; the continuous basis removes that.
- **The depth-aware MSAA normal resolve** described above.
- **A 7x7 Gaussian depth-aware blur** in pass 2. It is a smooth, not a denoise:
  depth-weighted so it does not bleed AO across silhouettes, and wide enough to
  feather the thin continuous contact line the depth-aware resolve leaves at an
  internal silhouette so it reads as a soft contact rather than a drawn line.

The depth-reconstruction fallback (used when the target holds no meshes, for
example a hand-drawn depth map) samples paired depth neighbours a few texels out,
not one: a 1-texel stencil is comparable to the 16-bit depth layer's
quantization step, so its reconstructed normal stair-steps and bands the flat
faces (the "dirty faces" bug).

Techniques: hemisphere SSAO (Crytek, john-chapman, LearnOpenGL), normal-from-depth
(Wicked Engine), the Fibonacci kernel, and the continuous basis (Duff). Credited
in `ATTRIBUTION.md`'s Techniques list; written from the technique, not ported.

Remaining work: any residual sub-pixel edge shimmer (8x MSAA is not infinite;
temporal accumulation is the lever), and routing a raymarched SDF field's
analytic 4-tap normal into the G-buffer (marginal for a smooth field, where
depth reconstruction already works; it would only help fields with sharp
subtract/intersect creases).

### Screen-space reflections (`.screenSpaceReflections`)

SSR reflects the rendered scene off its own surfaces, reading exactly the three
inputs (`base`, `aux` depth, `normals`) that SSAO already wires, so it needs no
new render-graph plumbing and is byte-identical when unused. It runs four passes:
trace, spatial resolve, temporal accumulation, composite.

**Trace** (`ollin_fx_ssr`) rebuilds view-space position and normal, reflects the
eye ray, and traces the reflection ray in screen space. The single most important
invariant here is the **McGuire-Mara adaptive stride**: cover the whole ray in at
most `steps` coarse steps (with a binary refinement that pins the crossing inside
the resulting coarser stride). This makes both the screen parameterization honest
and the reach resolution-independent. A hit is accepted on a **depth-interval
crossing**: the ray's depth interval across a step brackets the surface depth,
widened behind by `thickness`, with back-face rejection (`dot(R, sceneNormal) <
0`). A crossing test, not a near-the-ray distance and not a single-point depth
compare, is what rejects a ray that merely grazes a silhouette beside an object:
such a ray never crosses that object's depth.

The march **starts half a stride out** rather than on the receiver's own depth:
an interval anchored exactly on it flips between hit and miss with any depth
gradient across a pixel (self-hit speckle). Half a stride is the bias that gives
the first interval the same start-to-width ratio as every later one, so its
self-hit geometry matches the rest of the march while a hit landing within the
first stride (a reflection right at the contact between an object and its
mirror image) still registers. The earlier form skipped the whole first stride
instead, which detached every reflection about a pixel from its object. The
step count is also **floored at 4**, because a ray whose whole screen span is a
pixel or two (one heading nearly along the view axis) would otherwise be
covered by a single coarse interval and could effectively never hit: a dead
zone that punched pixel holes in view-aligned reflections.

This pass was the source of a long, costly debugging loop, and the failures form
a clear lesson. An earlier hand-rolled version stepped a fixed world-space
distance and forward-projected each step, which samples unevenly under
perspective and aliases into a diagonal moire. Patching it produced, in turn, a
budget-capped screen-space stride (which streaked long rays vertically) and a
"cylinder" artifact (a sphere's floor reflection rendered as a constant-width
band instead of a foreshortened ellipse). Two resolution-dependent sampling bugs
hid behind the cylinder, both rooted in stepping a fixed *pixel* count: the depth
fraction over-read to the ray's far end when the budget capped the step count,
and a fixed pixel budget truncated any reflection spanning more pixels than the
budget, cutting its far end flat. The McGuire-Mara adaptive stride fixes both at
once.

The lesson, which generalizes to any change in this area: a *resolution-dependent*
artifact points at the sampling/parameterization, not at the hit test. Render the
same frame at several output resolutions side by side to localize it, and
reproduce the actual conditions where it appears (the truncation was invisible in
every export and only showed at the live window's larger screen resolution). And
when a published technique has a canonical reference, implement that reference
completely rather than substituting a simpler-looking variant and patching back
toward it. The shipped trace is the canonical screen-space ray from LYGIA's
`lighting/ssr` and the McGuire-Mara port, studied from the references rather than
hand-rolled.

**Spatial resolve** (`ollin_fx_ssr_resolve`) is a 3x3 conservative-smoothing
despeckle plus a variance-aware gloss blur whose kernel is **dense
(contiguous-texel), never strided**. This is load-bearing: a strided kernel steps
over the fine grazing-contact streaks and never smooths them.

**Temporal** (`ollin_fx_ssr_temporal`) reprojects last frame's reflection by
camera motion (reconstruct the receiver's view-space point, lift it to world via
the scene camera's `inverseView`, project through the previous frame's
`viewProjection` to its prior uv), neighbourhood-clamps the sampled history to the
current reflection's 3x3 AABB to reject ghosting, then EMA-blends at
`resolveSSRAlpha`. History is an `SSRHistorySlot` ping-pong keyed by the SSR op's
**call site** (`#fileID:#line`, captured by the `.screenSpaceReflections`
factory) plus an occurrence index for same-site ops, not by an owner identity: a
sketch makes its `renderTarget()` fresh each frame (unlike a persistent
`Feedback`/`SimField`), so there is no stable object to key on. It is not a
frame-wide ordinal either: an ordinal shifts when an earlier SSR op is recorded
only conditionally, briefly handing a later op the wrong history. Only same-site
ops (one call in a loop) can still shift among themselves, the structural-identity
limit. `usesFeedback` counts an SSR combine so the headless/export warmup
converges.

**Composite** upsamples. The march, blur, and temporal passes run at
`resolveSSRScale` (half-res on `.performance`, full-res otherwise and always on
export, so snapshots hold). `quality` maps to `resolveSSRSteps`, which is a
*precision* knob (more coarse steps for a tighter crossing), not a reach cap;
reach is resolution-independent regardless.

The v1 model is a post-process over color, depth, and normal, so every surface
reflects, modulated by Fresnel and angle, with no per-material reflectivity
channel (a mask as a third input is a deferred follow-up). Documented limits,
which are inherent to screen-space tracing rather than bugs: off-screen or hidden
geometry cannot reflect (`edgeFade` hides the frame-edge cutoff); a reflection
beyond `maxDistance` fades at its tail; raymarched SDF fields and point clouds
fall back to depth-reconstructed normals because only meshes feed the G-buffer;
and the contact-seam streaks of a near-mirror reflecting a curved object's
grazing silhouette are SSR's inherent limit, which ray-traced reflections answer.

Techniques: linear screen-space tracing (McGuire-Mara, Sugu Lee, 3D Game Shaders
for Beginners), reprojection temporal accumulation with neighbourhood variance
clamping (Karis, Pedersen-Playdead), and a stochastic-SSR spatial resolve
(Frostbite, AMD FidelityFX SSSR). Credited in the README; written from the
technique.

### Depth of field (the `.defocus` gather)

`.defocus` is a single-pass circle-of-confusion bokeh gather with near/far field
separation (the architecture from the Catlike Coding DoF tutorial; the per-field
gather is Gustafsson's running-average form, Tuxedo Labs, studied via LYGIA's
`sample/dof`, whose Prosperity license is why it was reimplemented, not ported).
The aux is read perceptually as a depth map (`linearToSrgb(luma)`, matching the
depth-feed read so the gray a sketch draws is the depth).

Each tap is sorted by whether it is nearer than focus (foreground) or not, into
two accumulators, each a Gustafsson running average:
`acc += mix(acc/tot, sample, reach); tot += 1`, where `reach` tests whether a
tap's own blur spans its distance. A non-reaching tap adds the current average
rather than zero, so every tap counts. This both kills grain (no variance from a
varying effective sample count, so no per-pixel jitter is needed) and blends
overlapping bokeh.

**Near/far separation is the load-bearing idea**, and it is the thing a plain
single-pass gather cannot do. The foreground field carries a coverage that
composites it *over* the background field, so a defocused foreground spreads over
and hides an in-focus subject behind it instead of leaving a sharp crescent. The
sharp center is then blended toward the bokeh by `max(centerDefocus,
foregroundCoverage)`, so an in-focus subject stays crisp and correctly occludes
blurred things behind it with a sharp edge, unless a foreground blur covers it.

Two supports complete it. An expanding golden-angle spiral
(`radius += radScale/radius`, with `radScale` proportional to `maxBlur` squared)
packs rings denser toward the rim so the bokeh edge is smooth without jitter. And
a **seam dilation** (center blur size taken as the max over a small neighbourhood)
consumes the thin in-focus ring a hard depth edge leaves where its anti-aliased
boundary crosses the focal plane (the dotted-circle artifact). The seam was the
most stubborn artifact in this effect, and the lesson is general: an artifact that
survives every change to subsystem X is not in X. The seam survived every gather
rewrite because it lived in the CoC/depth, not in the gather; a debug
visualization of the in-focus map (returning `1 - centerCoC/maxBlur`) made it
visible directly.

This works on smooth/continuous depth (a gradient or a depth feed) and on
hard-edged discrete per-object depths with overlapping objects. `quality` is a
`RenderQuality` tier that the renderer resolves to a per-GPU bokeh tap budget
(`resolveDofTaps`); the tap budget, not the blur radius, is what `quality`
controls, so `.detail` is creamier and `.performance` is faster, while `maxBlur`
is the blur amount.

The tap budget was tuned with data from `Scripts/benchmark.sh dof`
(`DofBenchmarkTests` sweeps tap counts via the internal `dofTapsOverride` hook
and the effects-aware `benchmarkGPUMilliseconds`): on an M2 at 1080x1080,
`.default` (128 taps) measures 9.9 ms and holds 60 fps with headroom, and
`.detail` (256 taps) measures 19 ms (30 fps, for creamier blur). The shader's
`OLLIN_DOF_TAPS` constant is the fallback default when no budget is passed. The
`Effects/Defocus` example racks focus through orbs at discrete per-object depths
(a moderate count, so dense occlusion stays readable), and its snapshot pins the
overlapping hard-depth case.

---

## SDF combinators

The combinators compose signed-distance *fields* so that shapes **merge** instead
of stack. This is the field-combining axis that the per-instance SDF primitive
path (one shape per quad) structurally cannot express. There are two parallel
implementations: a 2D path (`Sources/Ollin/Drawing/SDF.swift` plus
`Renderer/ShaderCombinator.metal`) and a raymarched 3D sibling
(`Sources/Ollin/Drawing/SDF3D.swift` plus `Renderer/ShaderRaymarch.metal`). The
user-facing API is documented in `Docs/Drawing/Combinators.md`; this section is
how they work.

### The SDF VM (2D)

The typed `SDF` value type (leaf shapes plus combine, modify, and transform ops)
flattens on the CPU to a flat `SDFNode` program. This is a new render path beside
the per-instance `SDFInstance` path: its own `SDFGroupInstance` struct, a node
buffer, a `GeometryKind.sdfGroup`, and a `.sdfGroup` pipeline. It cannot ride the
per-instance path because `SDFInstance` is full at 144 bytes.

`ollin_sdfgroup_fragment` walks the program per pixel with two fixed-depth stacks
(cap 16): a **value** stack of (distance, color) for the combine and modify ops,
and a **point** stack for the transform and domain scopes (an XFORM node pushes
and transforms the point; the matching RESTORE_P pops it, and for a scale scope
multiplies the child distance back). Smooth ops use iq's polynomial smooth
minimum, whose blend factor also lerps the two operands' colors, giving the "melt
two colors" look; hard ops pick by min/max.

Several invariants are load-bearing:

- **Leaves carry no transform.** All positioning (a shape's intrinsic anchor,
  `.at`, `.rotated`, `.scaled`, domain repeat and mirror) is expressed as XFORM
  nodes, so method-chain order is exact: `a.at(p).repeated()` tiles the moved
  shape, while `a.repeated().at(p)` shifts the tiling.
- **The leaf distance is `ollin_sdf_distance`**, the per-shape region-SDF decode
  factored out of `ollin_sdf_fragment`'s switch. The two are kept in sync **by
  hand**: a new region shape goes in both, and the per-instance fragment switch is
  left untouched so single-shape snapshots stay byte-identical.
- **Polar/radial repeat is the shared sel-5 XFORM** in both `ollin_sdf_xform`
  (2D, folding around the origin) and `ollin_sdf3d_xform` (3D, folding around an
  axis). It is the single-evaluation kind of fold: wedge-symmetric content is
  exact, and asymmetric content shows a seam.
- A field past the stack or node caps (depth 16, roughly 256 nodes) is logged and
  skipped, never mis-drawn. Only closed region shapes are supported; lines, open
  arcs, and Beziers have no interior and are skipped with a one-time log.

A scoped block form (`smoothUnion(k:) { drawCircle...; drawRect... }`, and the
hard ops, mirror, and repeat variants) is sugar: bare region draws inside the
block are captured at `Drawer.appendSDF` as leaves instead of drawn, and the
block reaches every fillable region shape. The buffers thread through all nine
`encode` call sites (live, accumulation, export, effect-targets), so combinators
work on every path.

The stateful `sculpt { }` block (built for the live-coding loop) layers a
mutable combine state over that capture: its `add()` / `carve()` / `blend(_:)`
verbs change the per-child mode and melt mid-block. The CombineFrame snapshots
the state per captured child, a nested block lands under the state at its
close, the verbs address the innermost *sculpt* frame through nested blocks,
and each sculpt frame keeps its own state.

2D anti-aliasing reuses the single-shape coverage tail; the covering quad is the
whole-tree conservative AABB the flattener computes. 2D gradient paint is
supported (a solid color or a linear/radial gradient on `fill`/`stroke`, sampled
in field space at the fragment's `in.field`, so one ramp paints the whole merged
region or outline). Along-path paint has no single path on a merged field and
falls back to solid; a solid-leaf field is byte-identical to the per-shape path.

Per-axis sizing exists in both 2D and 3D: `stretched(x:y:[z:])` is iq's
`opElongate`, a point-domain warp that stays an *exact* SDF and is the preferred
per-axis tool; `scaled(x:y:[z:])` is a true non-uniform scale and is only a
conservative bound (it rescales the child distance by the minimum scale component
for a safe Lipschitz march, so blends distort under strong anisotropy).

### Raymarched 3D (`SDF3D` / `drawSDF3D`)

The 3D sibling composes 3D fields (sphere, box, rounded box, torus, capsule,
cylinder, cone, octahedron, ellipsoid, plane, plus the same ops) that merge the
same way, sphere-traced as one surface through the active camera and
depth-composited with the rasterized meshes. It is a parallel path beside the 2D
one: its own `SDFNode3D` and `SDF3DGroupInstance` structs, a
`GeometryKind.sdfGroup3D`, a `.raymarch` pipeline, and the `ShaderRaymarch.metal`
segment.

The most important implementation fact is that **the march runs in world space**.
Each step maps the world point into the field's local frame via its
`inverseModel`, so the 4-tap gradient normal and the written `[[depth(any)]]`
depth come out world-space with no normal matrix, and the depth (the world hit
point through the same view-projection the meshes use) lets meshes z-test and
interpenetrate the field. Each field draws as one fullscreen triangle bounded by
its world AABB, so a ray that misses bails in constant time. Shading reuses
`meshLitColor` unchanged, which is why the snapshot-pinned mesh shading never
moves when a field is added.

The infinite plane (`SDF3D.plane(normal:offset:)`) is the one unbounded leaf: it
has no finite AABB, so the flattener marks the whole field `unbounded` (propagated
through combine), and the fragment marches the near..far span instead of an AABB
slab. It is value-type-only (it has no mesh primitive). The leaves are iq's
3D distance functions, and `ollin_sdf3d_eval`'s switch must stay in sync with
`SDF3DShape`. The sculpting tier added five more (`line` between two free points,
`hexPrism`, `pyramid`, `cappedTorus`, `link`, tags 10 through 14); `line` is the
one leaf not centered at the origin, so the flattener bounds it from its two
endpoints plus the radius rather than a symmetric half-extent, and `pyramid`
wraps iq's fixed-half-unit-base form in a uniform scale (exact) with a re-center.

Two sculpting op families ride the same node kinds. The **joint and detailing
ops** (the chamfer/stairs/columns union/subtract/intersect trios, OP selectors
7 through 15, plus `engrave`/`groove`/`tongue`/`pipe`, selectors 16 through 19,
from hg_sdf under its MIT option) live in both `ollin_sdf_combine` and
`ollin_sdf3d_combine` (the 2D and 3D switches share the encoding; the op's
second scalar, the stairs step count, column count, or groove/tongue width,
rides the OP node's spare `extra`, and the staircase helper uses a GLSL-style
floored modulo, `ollin_emod`, because Metal's `fmod` truncates and would break
the pattern for negative operands). Their color is a crisp pick rather than a
melt (the nearer operand for the joint trios and `pipe`, the body for
`engrave`/`groove`/`tongue`), which is what makes a joint read as fitted parts. Columns keeps the reference's own
band guard; the detailing ops are value-type-only (the morph precedent), while
columns gets block forms too. They all assume the two surfaces cross frankly
(near right angles): near-parallel faces within the joint radius echo the
pattern past the seam, the technique's documented envelope, so the docs steer
usage there rather than the code trying to guard it (an extra band guard on the
chamfer/stairs trios was tried and traded the echo for a visible field
discontinuity).

The **distortions** are twist and bend (XFORM selectors 8/9, iq's `opTwist` /
`opCheapBend` as point-space scopes) and sine/noise surface displacement (MOD
selectors 2/3, iq's `opDisplace`; the MOD case reads the live query point, and
the noise flavor reuses the shader library's 3D `valueNoise`). All four produce
distance *bounds*, not exact fields, so the flattener attaches a conservative
Lipschitz rescale that keeps the sphere trace from overshooting: twist/bend
compute `1/(1 + rate·reach)` from the child's just-flattened bounds and ride it
on the scope's RESTORE_P distance scale (the same slot a non-uniform scale
uses), while displacement bakes `1/(1 + amplitude·frequency·C)` into the MOD
node's `geo0.x` (C is the displacement's own slope bound: √3 for the sine
product, ~2 for value noise). Strong settings therefore march slower instead of
holing the surface.

The same scoped block form reaches 3D: inside a block with a camera, the
SDF-able mesh builders (`drawSphere`, `drawBox`, and so on) route through
`Drawer.drawMeshPrimitive`, which captures an `SDF3D` leaf instead of
tessellating, positioned by the relative model matrix decomposed to translate,
rotate, and uniform scale (the only similarity an SDF respects). A non-primitive
`Mesh` inside a block is ignored with a one-time log.

Silhouette anti-aliasing is analytic: the fullscreen pass gets no MSAA at the
hit/miss edge, so the primary march tracks how close the ray came to the surface
relative to the pixel's own cone, and composites a grazing near-miss by that
coverage over what is behind it. 3D gradient paint is screen-space: a gradient
`fill` paints the whole merged surface by each hit's projected screen position.

Materials and environment light reach fields with mesh parity. The material
rides per batch: `ensureSDF3DBatch` records the active `material(_:)` as the
batch's `finish` and breaks the batch when it changes, exactly like
`ensureSolidMeshBatch` (the generic `ensureBatch` records no finish, so fields
routed through it shaded with the default material no matter what the sketch
set, which is why the split-out exists). On top of `meshLitColor`, the raymarch
fragment then adds the same image-based ambient the mesh fragments add: the
split-sum `ollin_pbr_ibl_ambient` for a physically-based finish (including the
traced-reflection swap when `rtReflections` is set, for which it binds the same
caster acceleration structure, flat mesh buffer, and per-geometry offsets the
mesh path binds), and `ollin_ibl_flat_ambient` (diffuse irradiance) for the
standard and toon finishes, Gooch excepted. All of it is gated on
`lighting.iblEnabled`, so a frame with no environment is byte-identical. The
half-res pre-pass mirrors the whole arrangement: `resolveFieldLighting` carries
the same IBL setup (and `rtReflections` flag) the main encode builds, and
`encodeRaymarchHalfRes` binds the same IBL textures and trace inputs, so a field
lights identically at any resolution tier.

### Field shadows

Shadows are gated on `castShadows()`, so a field without it is byte-identical.
The matrix of field-to-mesh and mesh-to-field shadowing is complete across light
types, and every path is byte-identical when off (a no-caster scene samples a
dummy all-lit map or skips the trace, so the factor stays 1):

- **Field self-shadows.** The raymarch fragment marches a penumbra ray toward the
  caster light (`ollin_sdf3d_softshadow`, iq's standard `min(k*h/t)` form) and
  feeds it to `meshLitColor` via a `fieldShadow` param. Use iq's standard form,
  not the previous-step-refinement variant: the refinement divides by zero on a
  receding ray and false-shadows lit faces.
- **Field casts onto meshes (directional/spot).** The field also renders into the
  2D shadow map, so rasterized meshes receive its shadow.
- **Field receives mesh shadows.** The raymarch fragment samples the 2D map, the
  point-light cube, or the ray-traced mesh acceleration structure at its hit, so a
  mesh's shadow lands on a field surface as it would on another mesh.
- **Field casts under a point/RT light.** A point caster has no 2D map to render
  into, so the lit mesh fragments march the field(s) inline toward the light and
  fold the result into the mesh's own point-shadow.

### Performance and the quality dial

A field is a fullscreen sphere-tracer whose cost is **bound to pixel count, not
step count** (a benchmark sweep is roughly flat across 32 to 256 steps). So the
`raymarchQuality(_:)` / `raymarchResolution(_:)` dial scales the field's internal
*resolution* (full on `.detail`, half on `.default`, quarter on `.performance`,
or a custom fraction), via a reduced-res pre-pass that the main pass composites
(bilinear color, point-sampled depth so the silhouette stays crisp).

The resolved fraction is a **marched-pixel budget at full coverage, not a fixed
downscale**. Because the AABB clip bails missed rays in O(1), the tracer's real
cost tracks the pixels the fields *cover*, and a fixed fraction had it exactly
backwards: a dollied-out field (small on screen, cheap to march) got the fewest
real pixels and dissolved into upsampled blur (the zoom-out-blur bug). So
`encodeRaymarchHalfRes` estimates the fields' projected screen coverage
(`fieldScreenCoverage`: each world AABB's eight corners through the camera, the
clipped NDC areas summed; a plane or a corner at/behind the camera counts as
full coverage) and traces at `min(1, fraction / √coverage)`: the marched-pixel
count never exceeds `fraction² × canvas`, the cost the fraction already implies
at full coverage, while a small field gets traced dense. At or above scale 1 the
pre-pass is skipped entirely (the inline march is crisper *and* cheaper).
Deterministic (pure function of camera + AABBs, no temporal state), so it holds
on export too. Two supporting pieces: the pre-pass targets are **grow-only** and
the pass renders into a **viewport subrect** (a continuous dolly drifts the scale
every frame; reallocating per frame would thrash), with the upsample mapping UVs
into the subrect and clamping half a texel inside it so bilinear never reads the
cleared texels past it; and the pre-pass's analytic silhouette AA sizes its pixel
cone by the **internal** resolution (`Uniforms3D.raymarchScale`), where sizing it
to the full-res pixel under-blurred the low-res image and the upsample magnified
the aliasing into a staircase. The inline path binds scale 1, which is
bit-identical to the pre-fix expression, so full-res renders and snapshots are
unchanged.

Field shadows are the expensive case, because the point-light cast is
per-receiver-pixel: a screen-filling floor under a field can take roughly half a
frame. Two levers trim it: a conservative AABB early-out in the inline field
march (inflated by the soft-shadow penumbra reach, so a grazing near-miss still
marches and the result is byte-identical), and a half-res field-shadow pass
(`encodeFieldShadowHalfRes`) wired to the same `resolveRaymarchScale` dial.

**The automatic tier scales the live preview only.** With no explicit setting,
export resolves to `.detail` (scale 1.0) and marches and shadows full-res, so
default-tier snapshots stay byte-identical and exported art is never downscaled;
an explicit `raymarchResolution` fraction (or explicit tier) is honored on export
too, coverage-adaptively. The dial rides the shared `RenderQuality` model, where
`.default` doubles as automatic: live `.default`, export `.detail`, overridable
by the `--render-quality` flag. All four quality knobs (shadows, defocus, ambient
occlusion, and raymarch resolution) target frame-rate bands.

---

## 3D lighting and environments

The user-facing surface is in `Docs/3D/3D.md`; this section is the machinery
behind the physically-based finish, the image-based lighting (IBL) bake and its
caches, the procedural sky, and the shadow paths. The ray-traced reflection's
anti-aliasing chain has its own section (*Deferred ray-traced reflection AA*).

### The physically-based finish

`Material.physicallyBased` (and the `.metal(roughness:)` / `.dielectric(roughness:)`
sugar plus the brushed/polished/plastic built-ins) is an energy-conserving
Cook-Torrance microfacet BRDF: GGX distribution, height-correlated Smith
visibility, Schlick Fresnel (the glTF 2.0 / Filament forms, reimplemented from
the math), evaluated over the same analytic lights as every other material. The
surface color stays `fill` (a metal tints its reflection by that color and has
no diffuse). Structurally it is `shadingModel 3`: one new `case` in
`meshLitColor`'s switch plus two `OllinMaterial` fields (`metallic`/`roughness`)
that every other model ignores, so all non-PBR materials render byte-identical.

### The IBL bake

`environment(_:)` lights the PBR materials from a surrounding HDRI via the
split-sum approximation (Karis). The renderer bakes once per resolved source
(cached; `MetalRenderer+IBL`, the `ShaderIBL.metal` segment): equirect to cube,
a diffuse irradiance cube, a GGX-prefiltered specular mip-cube, and a one-time
BRDF LUT, all fullscreen passes into cube faces that run before the geometry
pass at the render/image/benchmark sites. The prefilter is a 1024-sample GGX
importance bake; 256 samples left swirl/mottle artifacts on rough metals around
concentrated bright lights.

**Load-bearing gotcha: mip the equirect *before* the equirect-to-cube pass.** A
high-resolution equirect into a 256-square cube face is a large minification,
so the cube sample needs valid mips; without them it reads empty and the IBL
goes black (a real bug, fixed).

The EXR decode runs through ImageIO, which does not decode dwab compression, so
the bundled set is PIZ half-float. Inf/NaN sun texels are clamped on load, and
a sin-weighted average luminance is computed then for **per-environment
auto-exposure**: the bundled set ranges roughly 800x in raw brightness, so each
environment is scaled to a common target and any HDRI "just works".

At shade time the mesh fragment adds the split-sum ambient
(`ollin_pbr_ibl_ambient`, fragment textures 4/5/6) on top of `meshLitColor`'s
direct lighting when `OllinLighting.iblEnabled`; the non-PBR materials take the
diffuse irradiance as their ambient (`ollin_ibl_flat_ambient`; Gooch keeps its
own tone ramp), so one environment lights every material. All of it is gated,
so a frame with no environment is byte-identical. The raymarched fields add the
same two branches (see *SDF combinators*).

The environment also draws as a **skybox** backdrop by default
(`ollin_ibl_skybox_*`, a view-ray equirect sample before the geometry with
depth disabled, matching the reflections); `.lightingOnly()` opts out. The
backdrop is bicubic-reconstructed (a 4-tap Catmull-Rom, so the magnified
low-resolution slice is not a blocky bilinear grid) with a resolution-aware
`backgroundBlur` (`nil` = automatic: a gentle soft-focus at 1K easing to sharp
at 4K; overridable 0...1).

### Environments, downloads, and caches

An `Environment` built-in is one of 8 CC0 HDRIs bundled at 1K (instant,
offline, CI-safe) or one of 12 download-on-demand sources fetched from Poly
Haven on first use; a user source is `.hdri(path:)`, `.hdri(downloadURL:)`, or
the procedural `.sky`. `highRes(.twoK/.fourK/.eightK)` upgrades a built-in's
*backdrop* to a sharper version; the lighting never needs more than 1K.

The download cache is `EnvironmentCache`
(`~/Library/Caches/Ollin/Environments/`, overridable via
`OLLIN_ENVIRONMENT_CACHE`, with an injectable `fetch` so the unit test mocks
it; no network in CI). A `.remote(url:fallbackResource:)` source resolves in
the renderer: cached goes straight to bake; export **blocks** on the download
so exported art is always full-resolution; live kicks it off and shows the
bundled-1K placeholder (or the neutral sky) until it lands. The fetch prints
throttled byte/percent progress and then a decoding note to the terminal, via a
classic `URLSessionDownloadTask` on a delegate session, because the async
`download(from:delegate:)` convenience does not deliver the `didWriteData`
progress callback; the decode note strips the `<hash>-` cache prefix via
`EnvironmentCache.displayName`. `Scripts/clear-caches.sh` wipes the environment
and compiled-model caches by default, with targeted flags (`--environments` /
`--compiled-models` / `--models` / `--build`, `--all`, `--dry-run`).

**The processed equirect is cached as a blob.** A 4K PIZ decode is the
multi-second cost (the bake itself is cheap GPU passes), so the decoded float
pixels are written beside the download as a raw-float16 blob
(`EnvironmentCache.equirectBlobFile`, `<hash>.equirectf16`); a relaunch skips
the decode entirely (a 4K blob is ~64MB, smaller than the 92MB float32 source,
loaded by memcpy, round-tripping pixel-identical). The bundled 1K set stays on
its compact EXR, which decodes in a blink and needs no blob.

**The decode/blob-read runs off the render thread**: `equirectBytes` in a
`Task.detached`, handed back through an `OSAllocatedUnfairLock` into
`equirectReady` (`loadEquirectBytes`/`processEquirect` are `nonisolated`, since
`MetalRenderer` is `@MainActor`), with the bundled placeholder shown until it
lands, so the live window never blocks. The export path loads synchronously
(`blocking`) so exported art is full-resolution and the snapshot stays
byte-identical.

The in-memory bake cache is LRU-bounded (~512 MB of baked maps; the frame's own
entry never evicts; an evicted source re-bakes from its blob in a blink), and
orphaned decoded pixels (`equirectReady` entries whose environment moved on
before they baked) are pruned after a few resolves, so a gallery cycling many
HDRIs stays bounded (`IBLCacheTests`).

### The procedural sky

`.sky(turbidity:sunElevation:groundAlbedo:)` is a zero-asset Hosek-Wilkie
daylight dome. The RGB coefficient dataset and config code are vendored at
`External/CHosekWilkie` (3-clause BSD, trimmed to the RGB path);
`ollin_hosek_rgb_configs` cooks the per-channel config CPU-side,
`ollin_ibl_sky_gen` evaluates the per-texel radiance into the equirect, and the
same cube/irradiance/prefilter/skybox bake runs on it. A neutral `.sky()` is
also the default placeholder while a non-bundled HDRI downloads, so the scene
is lit by a sky instead of unlit (unless an explicit bundled `placeholder:` was
given).

Two performance decisions are load-bearing. The sky equirect is generated on
the frame's own command buffer with **no CPU read-back**: auto-exposure's
average luminance is integrated analytically from the coefficients
(`skyAverageLuminance`) instead of read back from the texture (the read-back
path was the 3-fps bug). And an animated sky re-bakes every frame at a
**reduced sample budget** (the `params.z` budget in
`ollin_ibl_irradiance`/`_prefilter`: a coarser hemisphere step plus 32 GGX
samples for `fastSky`; 0 selects the default fine bake, so the HDRI path stays
byte-identical), which keeps a moving sun smooth with no quantization stepping.
`rotated(_:)` spins the sun for free: it is a shade-time uniform, never a
re-bake.

### Shadows

`castShadows()` routes by light type: directional/spot render a 2D shadow map;
a point light is ray-traced on an RT GPU (inline `intersection_query` behind
the `OLLIN_RT_SHADOWS` compile gate) with a mid-point cube fallback elsewhere;
`shadowQuality(_:)` maps hardware-relative ray counts through `RenderQuality`.

**PCSS (soft shadows).** `shadowSoftness(_:)` (0 hard, 0.5 default
contact-hardening, 1 very soft) runs the directional/spot 2D map through
Percentage-Closer Soft Shadows: blocker search, penumbra estimate, then a
variable-kernel Vogel-disk PCF (`shadowFactorPCSS`; the Fernando/NVIDIA
technique, studied from openFrameworks' shadow shader), sharp at contact and
blurring with distance. It is gated on `shadowDepthA > 0`, so `shadowSoftness(0)`
routes to the legacy hard 3x3 tap and is byte-identical.

**The penumbra ratio must be formed in light-linear depth.** A directional
ortho map uses the plain separation `(n_r - n_b)`; a spot perspective map
linearizes via `(n_r - n_b)/(n_r + A)` where `A` is the projection's `[2][2]`
term (carried as `shadowDepthB`; the `[3][2]` term cancels), and the negative
`A` also flags the spot path. `OllinLighting` did not grow for any of this: the
spare kind-0 fields `shadowDepthA`/`shadowDepthB`/`shadowSamples` carry the
light size (in texels), the linearization term, and the tap budget, and the
blocker search reuses the already-bound nearest `shadowCubeSamp` for raw depth
reads (no new sampler or pipeline).

One knob unifies every caster: the same softness drives the RT point caster's
area radius (`dist * 0.06 * softness`; the 0.5 default reproduces the old
`dist * 0.03`, so the `point-shadows` snapshot is byte-identical). The 2D tap
budget rides `RenderQuality` via `resolveShadowTaps2D` (performance 24 /
default 40 / detail 72, GPU-independent fixed counts since these are cheap
texture taps, not RT rays; export resolves `.detail`). Shadows are
soft-by-default, and the penumbra change measured sub-tolerance (~0.2 mean
against the 2.0 snapshot threshold, a localized shadow-edge change), so
`mesh-shadows`/`spot-shadows`/`rt-reflections-3d` stayed within tolerance and
were not re-recorded (the SSAO silhouette-AA precedent).

### Ray-traced reflections: integration and plumbing

The trace itself, the two-bounce hit shading, and the anti-aliasing chain are
in *Deferred ray-traced reflection AA* below. The integration facts live here:

- **It integrates into the IBL specular, not a post-process.**
  `ollin_rt_reflection` (in Shader3D, inside `#if OLLIN_RT_SHADOWS` beside
  `traceShadowRay`) traces one closest-hit ray (`R = reflect(-V, n)`, origin
  `worldPos + n * rtReflectionBias`) against the mesh acceleration structure
  and replaces `ollin_pbr_ibl_ambient`'s `prefiltered` environment sample with
  the hit's radiance (a miss returns the environment sample, so a ray that
  leaves the scene shows the sky), compositing through the same Fresnel/BRDF
  weighting. The primary surface's roughness then blends the sharp mirror
  toward the prefiltered environment (one ray cannot blur).
- **Per-hit material data is baked per vertex.** Metalness and roughness ride
  the spare `OllinMeshVertex` w slots (`normal.w` metallic, `position.w`
  roughness for a PBR lit mesh), inert for the primary render since the lit
  vertex shaders read only xyz.
- **It reuses the shadow-caster accel.** `buildShadowAccel` also returns a
  per-geometry base-vertex offsets buffer (`meshGeoOffsetBuffer`, the coalesced
  `runStart`s) so a hit's `(geometryId, primitiveId)` plus barycentric
  coordinates fetch its triangle from the flat non-indexed `OllinMeshVertex`
  list (accel + offsets + flat mesh buffer bind to the mesh fragment at buffers
  3/7/6, RT-gated). `encodeShadowPass` was decoupled so the accel builds when
  shadows *or* reflections are active (a directional/spot caster builds the 2D
  map and the reflect accel; a no-caster reflections-only scene builds just the
  accel); `ShadowMaps.reflectAccel`/`reflectGeoOffsets` carry it, and
  `OllinLighting.rtReflections` (set by the renderer when present) gates the
  shader, so everything is byte-identical when off.
- Every solid mesh is reflectable (the accel covers all of them;
  `castShadows()` is not required). Reflections need an environment (the
  integration point and miss fallback) and an RT GPU (`rayTracedShadows`), are
  off-by-default, and no-op on a non-RT GPU (the environment reflection
  remains). The `rtReflectionBias` self-hit epsilon is sized from the scene
  scale in `makeLighting`.
- **v1 limits:** two bounces (the third order terminates at the environment);
  full resolution (a half-res `RenderQuality` tier, deeper bounces, a dedicated
  all-mesh accel, and the glossy-cone denoise are the follow-ups). The
  per-hit-material gap is closed for the PBR finish via the baked vertex slots;
  the non-PBR stylized finishes still shade as plain diffuse in a reflection.

---

## Deferred ray-traced reflection AA

The ray-traced reflection is one closest-hit ray per reflective pixel, which makes
a *reflected* silhouette (a pillar's mirror image meeting a polished floor, the
"reflection horizon") a 1px-hard edge no spatial filter can soften: the edge lives
inside the traced image, past where MSAA can reach. The fix is stochastic
supersampling of the reflection layer, restructured from an inline per-fragment
trace into a small deferred chain (`encodeReflectionPass`, main canvas only):

1. **Reflection G-buffer.** Re-encode the main canvas's solid mesh batches
   (the mesh-normal pass's dedicated-re-encode pattern; wireframes and the grid
   chrome skipped, matching the accel) into a single-sample MRT pair (world
   normal + coverage, and the per-vertex metalness/roughness the baked
   `OllinMeshVertex` w slots carry) plus its own `depth32Float`. Single-sample
   on purpose: the layer is supersampled by jitter, not by MSAA, so it costs a
   fraction of the SSAO normal pass's readable-MSAA memory.
2. **Trace** (`ollin_rt_reflect_trace`, RT-gated in ShaderCombine so it can call
   the Shader3D helpers; segment order): per pixel, reconstruct the surface
   point through `inverseViewProjection` at a **sub-pixel-jittered** NDC (the
   pixel's own full-precision depth), reflect the eye ray off it, and trace via
   `ollin_rt_reflection_trace`, the hit-shading half shared with the inline
   `ollin_rt_reflection` (a thin wrapper over it), so the two paths cannot
   drift. Output is premultiplied by hit (miss = 0), so the average's alpha
   carries fractional scene-vs-environment coverage. The jitter is an R2
   sequence phase-rotated per pixel (`hash12`), a pure function of
   (pixel, index), so exports reproduce bit-exactly. **No roughness-cone spread**:
   glossiness stays with the mesh fragment's roughness blend toward the
   prefiltered environment (the inline path's rule). A stochastic cone at 1–16
   rays reads as sparkle on brushed metals; integrating one properly needs a
   spatial resolve/denoise stage first (a follow-up).
3. **Temporal resolve, live** (`ollin_rt_reflect_temporal`): the SSR temporal's
   scheme (reproject through the previous frame's view·projection, clamp the
   history to the current 3×3 neighborhood, blend as an EMA on
   `resolveSSRAlpha`-style tiers), but reconstructing the world point from the
   G-buffer's own full-precision depth rather than the normalized depth layer.
   The history is one `SSRHistorySlot` (`rtReflectHistory`), guarded by
   `statefulEncodeIsRepeat` so the live frame-grab can't double-step it,
   reallocated on a size change. A static camera reprojects to identity and the
   single jittered ray converges to the supersampled reflection in about a
   dozen frames; under motion the clamp bounds stale history and it degrades
   toward the single-ray look (the SSR temporal's accepted behavior; full
   view-dependent reflection reprojection needs a depth history and was
   declined as impractical, per the published technique's own author).
4. **Headless/export supersample.** `image(of:)` runs the same chain with
   `supersample: true`: N deterministic jittered rays averaged **within the one
   frame** (perf 4 / default 8 / detail 16; export resolves `.detail`), no
   history slot touched. A single exported frame is anti-aliased with no warmup,
   a video export cannot flicker, and the live recording's off-screen re-render
   (which routes through `image(of:)`) never advances the on-screen
   accumulation, which is also why reflections need no `usesFeedback` warmup.

The lit mesh fragments sample the finished layer by screen position
(`position.xy · rtReflectionScale / texSize`, the fieldShadowScale rule, fragment
texture 7) when `rtReflectionDeferred` is set, compositing `hit.rgb + prefiltered
· (1 − hit.a)` through the same Fresnel/BRDF weighting, identical math to the
inline form when coverage is 0 or 1. **Render targets and the raymarched fields
keep the inline single-ray trace** (their lighting never sets the deferred flag);
the deferred chain covers the canvas render, live and headless. Measured against
a 2× supersampled ground truth, the deferred export lands ~32% closer (contact-
region RMSE) than the single-ray form, with the remaining delta shared with
everything else 2× supersampling touches.

The hit shade itself is **two-bounce**: the first hit's specular traces a second
closest-hit ray and shades that surface (env-terminated at the third order,
`ollin_rt_fetch_surface` + `ollin_rt_direct` shared by both bounces) rather than
sampling the environment blindly. The second trace is load-bearing where two
reflectors meet (the mirror floor at a polished pillar's base): an unoccluded
environment sample at the first hit pipes the HDRI's bright lower hemisphere
straight through the floor, and the grazing-compressed reflected silhouette
concentrates the leak into a razor-thin bright streak along the base that no
anti-aliasing can remove, because it is consistently-shaded content, not an
edge (the debug that proved it painted occluded-secondary hits red and lit up
exactly the streak). Shading the actual second surface dims the corner by the
product of the two surfaces' own reflectances, as a real mirror corner does.
Both bounces sample the environment through `ollin_rt_env_lobe`, which widens
the prefilter mip by grazing incidence (effective roughness
`rough / max(NoV, rough)`; a microfacet lobe stretches by ~1/NoV), so
grazing-lit reflected content spreads its energy the way the surface's own
distribution does. Two dead ends worth recording: an irradiance-probe fallback
for occluded secondaries reads as flat pastel blobs on curved reflections (the
irradiance cube integrates the same bright HDRI floor that leaked), and lobe
widening alone dims the streak but cannot remove it (the leak is radiometric,
not a filtering problem).

---

## User-supplied shaders

A sketch writes its own fragment shader and runs it through the effect graph.
The contract is Ollin-native, not raw Metal: the user defines
`float4 shade(float2 uv, ShaderInfo info)` (uv 0...1 top-left, returning
straight sRGB), and Ollin generates the surrounding fragment plus a fullscreen
`ollin_user_vertex`. The public surface is `Docs/Shaders/Shaders.md` and the
per-function `Docs/Shaders/ShaderLibrary.md`; this section is the wiring.

**Routing reuses the effect-graph enums.** `Shader` is a `.shader(Shader)` case
on `Generator`, `Filter`, and `Combine.Kind`, so input count *is* the variant:
`generate(.shader(s))` (0 inputs), `layer.filtered(.shader(s))` (1 input, read
via `sample(info, uv)`), `a.combined(with: b, .shader(s))` (2 inputs, adding
`sampleAux(info, uv)`). All three resolve through the existing
`encodeGenerator`/`applyFilter`/`applyCombine` with no new render-graph
plumbing. The input layer(s) ride *inside* the wrapper's `ShaderInfo` as
`texture2d<float>` plus `sampler` members (valid MSL, passed by value to
`shade`), read back as straight sRGB (`ollin_layer_sample` un-premultiplies and
applies `linearToSrgb`) so the user works in one color space.

**Compile model.** Each shader composes its own source (the `OllinShaderLib`
segment, the variant wrapper, the user source) and compiles as its own
`device.makeLibrary(source:)`, cached by `fnv1a(composed)` through `MTLLibrary`
to `MTLRenderPipelineState` (the `userShader*` caches), so it compiles once,
not per frame. A *failed* compile is cached too (`userShaderErrors`) so a
broken shader does not retry every frame; all three caches clear on a
framework-shader reload. `ShaderInfo` is built per frame from
`frameComputeUniforms` (snapshotted from `drawer.computeUniforms` at the top of
`encodeEffectTargets`, so the filter/combine call sites need no `drawer`). The
bound uniform struct `OllinShaderUniforms` is scalars-only (no array) so Swift
fills it with the plain memberwise init; user params (up to 32 floats, read via
the `param(info, i)` macro) ride a separate `float4` buffer at index 0.

**Friendly errors are the headline.** `Shader.init` captures its call site
(`#filePath`/`#line` default args) and the wrapper emits
`#line <startLine> "<file>"` before the user source, so Metal reports
diagnostics at the real, IDE-clickable location: the sketch's own `.swift` for
an inline string (a multiline literal's content starts at `line + 1`; a
no-newline string sits on the call line, so a one-content-line literal reads
one off, an accepted quirk that `ShaderErrorTests` pins), or the `.metal` file
itself for a resource (line 1). `cleanShaderDiagnostics` strips the
`Compilation failed:` header, rebases `program_source:` lines to the same
`file:line` as a fallback, and drops compiler-internal `note:` lines pointing
at `/System/` framework headers (a line naming the user's file is always
kept). The call-site location rides the composed-source hash, so identical
shaders at two call sites cache separately (fine; same-site rebuilds like
`Visual`'s still hit). The error surfaces two ways: stderr (once per source
hash, for a plain `swift run`) and a pull-model channel to the host: the
renderer holds `currentUserShaderError` (reset each frame, set on failure),
`SketchRunner` reads it after `render()` on the main thread and forwards via
`onUserShaderError` (deduped), and `LiveSession` maps it to its `shaderError`
feeding the existing `CompileErrorState` overlay. The channel is deliberately
separate from the Swift compile-error channel so a shader error and a Swift
error never clear each other (`reloadShaders`' framework-shader gap is closed
the same way).

**`OllinShaderLib` is one source of truth, used three ways.** The helper
segment (color/hash/noise/sdf/domain plus `palette`/OKLab, including the
once-compute-only `curlNoise`/`discSample`/3D `valueNoise`/one-out hashes,
folded into its hash/noise sections) is built on by the framework's own
segments, spliced into every user shader, and spliced whole into every compute
kernel by `composeComputeSource` (the separate compute prelude is gone: one
helper set, `hashNM` names, everywhere). `using: [.noise, .sdf]` keeps only the
marked sections (`// OLLIN_LIB_BEGIN/END <module>`, with the noise-needs-hash
dependency resolved); it is a compile-time lever only (the GPU dead-code
eliminates unused helpers anyway), default `.all`. The 2D `sd*` distance
catalog (`sdEllipse`/`sdRoundBox`/`sdSegment`/`sdStar`/`sdHeart`/`sdBezier`/...
plus the `dot2`/`ndot` helpers) lives in the lib's `sdf` section, moved
verbatim out of `ShaderShapes` (the block was self-contained, so the framework
library still resolves it and all snapshots stayed byte-identical);
`ollin_sdf_distance` and the fragment switch in `ShaderShapes` still call
them, so framework shapes and user shaders share one copy.

**Hot-reload covers both forms in OllinLive.** An inline-string shader reloads
with the sketch (a `.swift` edit). A `.metal` *resource* shader reloads on its
own: `Shader(resource:in:)` reads lazily (it stores the bundle-resolved path,
not the content; `Bundle.module` resolves to the sketch dir under OllinLive
too), the renderer reads and caches the file, and a watched-`.metal` change
routes through `LiveSession.handle` to `SketchRunner.invalidateUserShaders()`
(clears the source/library/pipeline caches; forces one frame if `noLoop`), so
the next frame re-reads and recompiles with no swiftc pass (verified
end-to-end: edit reloads, a break shows the line-accurate overlay error, a fix
recovers). A framework-segment `.metal` (under the repo's `Renderer` dir) still
routes to the full library reload; the dispatch tells them apart by path.

---

## Camera rig: showcase orbit, view snaps, and scene chrome

`cameraShowcase(_:)` (the default the 3D examples use) is an auto-orbit the viewer can
take over, easing back to the opening shot when left alone. It adds no new camera
math: it is a small state machine in `CameraRig` (`Sources/Ollin/3D/CameraRig.swift`)
that orchestrates the two halves that already exist: the cinematic-move driver
(`updateMove`/`startMove`/`apply`) and the damped interactive controller
(`updateControl`).

**Three phases.** `updateInteractiveMove(move:input:dt:viewportHeight:idleTimeout:returnDuration:)`
runs one of:

- `driving`: calls `updateMove` verbatim (the move plays). A drag, dolly, or pan
  this frame switches to `manual` and resets the idle clock. The interaction check
  runs *before* the branch, so the input that starts the takeover (a single scroll
  tick included) lands the same frame.
- `manual`: calls `updateControl`. Each input frame zeroes the idle clock; each
  idle frame accumulates it. At `idleTimeout` (10s default) it begins the return.
- `returning`: eases the displayed pose from where the viewer left it toward the
  *opening* orbit, then hands back to `driving`.

**Reset to the original shot, not resume-in-place.** The opening framing (target,
radius, elevation, azimuth) is captured once in `seed()` as the `anchor*` fields,
separate from the live pose the controller mutates. When the return begins,
`beginReturn` snapshots the viewer's pose (`returnFrom*`), restarts the move at the
anchor framing (`startMove` with the pose temporarily set to the anchor, so the
move's base is the opening shot), then restores the displayed pose to the viewer's
so the blend starts there with no jump. `advanceReturn` advances the move (a *live*
orbit at the opening framing) and blends `returnFrom → movePose` by a Hermite
`easeInOut(returnClock/returnDuration)` (4s default). Hermite is flat at both ends,
so the orbit's angular velocity ramps from rest to full, the "progressive" return.
Azimuth blends along the shortest arc (`lerpAngle`) so a viewer who spun several
turns returns the short way instead of unwinding every turn. At `t=1` the blend
equals `movePose`, and `driving`'s next `updateMove` reads the same base/clock, so
the handoff is seamless; a fresh interaction during the return cancels straight back
to `manual`.

**Byte-identical when uninteracted (load-bearing).** With no input the machine never
leaves `driving` and runs the unchanged `updateMove`, so the headless/export and
snapshot paths are pixel-identical to a plain cinematic move, and `cameraMove` /
`camera` themselves are untouched, so every existing 3D snapshot is unaffected
(`cameraShowcase` is a *new* opt-in call, not a behavior change to the old ones). The
state machine is exercised by CPU units in `CameraRigTests` (interrupt, idle return
to the anchor framing, seam continuity, mid-return cancel), since a snapshot cannot
drive synthetic input events.

`activeCamera` (on `Sketch`) returns the resolved `Camera3D` for the frame, so a
sketch that places geometry relative to the camera (e.g. `DepthCompositing` seats
its pins at the camera `eye`) keeps working when the interactive rig owns the pose.

### The controller model and input surface

`cameraControl()` is the canonical orbit-control model, reimplemented from the
references (studied, not ported): spherical azimuth/elevation with a
`2 * pi * delta / height` rotate, a multiplicative `pow(0.97)` dolly, a
`2 * radius * tan(fov/2) / height` pan, all `deltaTime`-corrected for
frame-rate independence, with exponential damping toward an input-driven goal
plus a capped release-momentum flick. Both halves seed the framing on the first
call only and compose over the current pose (`CameraRig.lastMode` re-syncs the
controller's goal after a move), so "frame by hand, then drift" is one call
after another, and the rig clamps elevation off the poles.

The rig is a plain `let` on `Sketch` advanced explicitly, *not*
`FrameAdvancing`: the Mirror-collection cache behind `FrameAdvancing` only sees
stored properties that exist before the first frame, which the rig sidesteps.
The input surface feeding it is platform-neutral and plumbed once through
`OllinMTKView` (so it reaches standalone, gallery, and OllinLive):
`scrollDeltaY` is the per-frame scroll total, **double-buffered** in
`advance()` so a wheel event landing between frames is never lost; `modifiers`
is a `ModifierKeys` option set mapped from `NSEvent.ModifierFlags` behind the
AppKit seam (like `KeyCode`); plus `rightMouseIsPressed` and the `mouseWheel()`
hook.

### Scene inspection views (`cameraView` / `resetCamera`)

`cameraView(_:)` snaps the rig to canonical angles: `.reset` restores the
opening framing (target, radius, and angle); the six axis views swing only the
orbit angle, keeping the current target and radius; `.isometric` (`.corner` is
the deprecated alias) is true isometric, `asin(1/sqrt(3))` up at 45 degrees
around. Snaps glide by default (`animated: false` cuts), and on completion hand
the pose back to the active driver via `CameraRig.driver` (control resyncs its
goal, a move re-bases, showcase holds then idle-returns), so motion resumes
from the snapped pose with no jump. `applyViewSnap` early-returns when no snap
is active and the `.driver` set is inert, so the path is byte-identical when
unused (`camera-move` was not re-recorded). The viewer-facing surface is the
host Camera menu (`OllinCameraCommands`, cmd-0 through cmd-7) in all three
hosts, reaching the running sketch through the `OllinActiveSketch` weak holder
to `SketchRunner.requestCameraView` (applied next frame) to `cameraView`; a 2D
or hand-set-`camera()` sketch ignores it. Snap math and hand-back are pinned by
`CameraRigTests`.

### Scene chrome: the axis widget and the ground grid

`cameraAxis()` and `groundGrid()` are live-only host chrome, like the FPS
overlay: never exported, a no-op in 2D, read live each frame or toggled from
the Camera menu. The axis widget (`AxisWidget`) is a SwiftUI sibling reading
the per-frame `CameraOrientationState` the runner publishes: click an axis to
snap via `requestCameraView`, plus reset, isometric, and an
ortho/perspective toggle driving `CameraRig.isOrthographic`. The ground grid is
a `.grid` `PipelineKey` pass drawn straight from `SketchView.draw`,
depth-tested but not depth-writing, *outside* the deferred render graph.

**The grid LOD invariant (load-bearing).** The infinite-grid LOD (the Golus
technique, reimplemented) divides the once-computed base world-uv derivative by
each decade-spaced scale; never take `dfdx()` of a pre-scaled uv. The pre-scaled
uv (`cellA`) jumps a decade across adjacent pixels at a LOD boundary, and the
derivative spike shatters the lines into a crawling dotted band (a real fixed
bug). "Major" (every-10th) lines are distinguished *by width in the one line
color*, not by a brighter color and not by a separate per-class fade, so every
scale fades by the same rule (its line thinning below a pixel,
`covA + max(covB, covC)`) and the levels converge and fall off together toward
the horizon under a single uniform radial fade. The old form (a brighter,
separately-faded major) made the levels vanish at staggered depths and read as
stacked planes at different heights; do not reintroduce it.

---

## Status of this document

The sections above are the current contents.
The *Systems map* near the top is the migration checklist: when a system marked
*pending* there accrues depth that would otherwise swell CLAUDE.md (or that a
contributor needs and that currently survives only as the memory of past work),
it moves here under the same convention. CLAUDE.md keeps the terse invariant and
a pointer; the mechanism, rationale, and measurements live here; CLAUDE.md's
*Current state* remains the authoritative capability index. The migration is
deliberately incremental: a system earns a writeup here when its CLAUDE.md bullet
is carrying mechanism it should not, or when someone is about to work in that
area, not as a one-time backfill.
