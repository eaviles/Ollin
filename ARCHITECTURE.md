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
| Renderer core (frame lifecycle, pipeline families, vertex-buffer ring) | This doc, *The renderer at a glance*; the rules live in CLAUDE.md *Shaders & the Metal back end* / *Rendering performance* |
| The 2D drawing paths (SDF primitives + coverage models, fringe strokes, libtess2 fills, linear-light present) | **This doc**, *The 2D drawing paths* |
| Live reload, `@Param`, stats, and the live-coding hosts | **This doc**, *Live reload and the live-coding hosts*; the rules stay in CLAUDE.md *Live reload* |
| Screen-space combine effects (SSAO, SSR, depth of field) | **This doc** |
| SDF combinators (2D VM + raymarched 3D) | **This doc** |
| Layered-effects substrate (render targets, filters, generators, compose, combine, feedback, sim fields / fluid) | **This doc**, *Layered-effects substrate* (the combine wiring under *Screen-space combine effects*) |
| 3D lighting (PBR / Cook-Torrance, IBL split-sum bake, procedural sky, PCSS + RT shadows, RT reflections) | **This doc**, *3D lighting and environments* (the reflection anti-aliasing chain under *Deferred ray-traced reflection AA*) |
| Geometry & generator catalog (Grid, booleans/offsets, SVG import, epicycles, curves, morphing, sampling/stippling, walks, tiling, packing, growth, WFC, CA/turmites, fields/boids/steering, attractors, IK/pendulum/N-body) | **This doc**, *The geometry and generator catalog* |
| Color pipelines (palette import/extraction, image dithering, print separations) | **This doc**, *Color: palettes, dithering, and print separations* |
| Text & glyphs (libtess2 fill, winding / overlap-clean gotchas, fringe stroke, SDF atlas) | Pending here; CLAUDE.md + `Docs/Drawing/Text.md` |
| Compute & GPU particles | Pending here; CLAUDE.md + `Docs/Shaders/Compute.md` |
| User-supplied shaders | **This doc**, *User-supplied shaders* |
| Camera rig (showcase orbit, view snaps, scene chrome) | **This doc**, *Camera rig: showcase orbit, view snaps, and scene chrome* |
| Satellites (audio, OSC, MIDI, Syphon, virtual camera, video, physics, vision, Record3D, phone) | `Docs/` per satellite + the cross-cutting satellite gotchas in CLAUDE.md |

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

## The 2D drawing paths

How a 2D mark becomes pixels: the instanced analytic-SDF path for the closed
primitives, the fringe-expander path for strokes, libtess2 plus MSAA for
arbitrary fills, all composited in linear light. The regression-preventing
rules are in CLAUDE.md *Rendering performance*; this section is the mechanism
and the history behind them.

### The instanced SDF path

Each analytic primitive (point markers, circle, ellipse, rect, oriented box,
circular arc, triangle, general 3-point triangle, regular polygon, star,
rhombus, vesica, oriented vesica, moon, cross, ring, trapezoid, parallelogram,
egg, heart, cut disk, uneven capsule, horseshoe, parabola, rounded X, blobby
cross, tunnel, stairs, cool S) is one instanced quad: an `SDFInstance` on the
`.sdf` pipeline, evaluated by `ollin_sdf_fragment`, which switches on the
shape tag and runs a shared fill + stroke + anti-aliasing tail. Per-shape CPU
cost is a single struct write (the `Myriad` example draws 8,100 circles at
roughly an 1,100 fps CPU ceiling). `SDFInstance` is a *tagged union*: a
`shape` tag plus generic `size`/`param0`/`param1`/`param2`/`extra` slots, and
each instance carries its own CTM (`float3x3`) so the fragment evaluates the
SDF in local space and the anti-aliasing stays ~1px under any transform
(`fwidth`); the covering quad spans `size` plus half the stroke plus a small
margin. The per-shape encodings (which param slot carries what, and which
`sd*` function each calls: the point's round/square/diamond/cross/x markers,
`drawNgon`/`drawStar` sharing one `sdStar`, the egg/heart/tunnel/stairs
Y-flips, the three-point triangle and quadratic Bezier reading their free
points from `param0`/`param1`/`param2`) live in `SDFShape` plus
`ShaderShapes.metal`; the distance functions are iq's 2D catalog, written from
the technique. (The circle approach was studied from a peer framework's MIT
shader and written independently; credited in `ATTRIBUTION.md`.)

`drawLine` and `drawBezier` originally rendered here as SDF capsule/Bezier
instances and have since moved to the fringe stroke path below; their shader
cases are retained but unemitted. Arbitrary `drawPolygon`/`drawPolyline` and
elliptical or full-turn arcs stay on the triangle path by nature (`drawArc`
runtime-branches: `rx == ry` and sweep less than a full turn goes SDF, else it
tessellates). What tessellates there is the *fill*: a tessellated arc's outline
is a path like any other, so it strokes through the fringe expander, which is
what gives it joins and caps and keeps translucent ink to one coat. The three
modes hand it the same shapes the vector recorder writes (open as a polyline,
chord as a closed loop, pie as that loop through the center), so a rendered arc
and an exported one trace the same outline.

One rule is not safely discoverable from the code, so it is recorded: the four
roundable shapes (rhombus/vesica/moon/cross) take a footprint-preserving
`cornerRadius`, and vesica/moon must `opRound` off a *full-footprint* SDF.
Insetting the vesica's waist toward zero sends its derived circle radius and
offset to ~1e7, and the shader's `sqrt(r^2 - d^2)` loses all precision (a real
glitch, fixed by the full-footprint form).

**Hollow/band mode** generalizes the ring's `opOnion` to every region shape:
`hollow(_:)`/`solid()` set a per-instance `bandWidth`, and `regionFill` onions
the shape's SDF (`abs(d) - bandWidth/2`) before coverage, so the fill paints a
constant-width band hugging the outline and an active stroke borders *both*
edges (the framed-ring look a stroke alone cannot make). The band straddles
the edge, so the covering quad grows by `bandWidth/2`. The `bandWidth` field
fit the struct's then-tail-padding, so it forced no widening. Region shapes
opt in via `SDFShape.honorsHollow`; points, lines, and the ring (already a
band) opt out, and the round-dot point opts out by hand since it shares the
`.ellipse` tag (a solid disk's area-conserving coverage is bypassed for
`regionFill` only when banding).

**Stroke alignment** (`strokeAlign(_:)`: `.center`/`.inside`/`.outside`) rides
the same coverage tail: the coverage functions take a `strokeBias`
(`0` / `-hw` / `+hw`) that shifts the stroke band off the edge
(`abs(d - strokeBias) < hw`) while the fill still stops at `d = 0`, so the
inset/outset is an exact SDF offset and `.center` (bias 0) is byte-identical
to before. The 3-state align rides in **bits 8-9 of the `shape` tag** (the tag
is < 256, so the vertex shader masks `shape & 0xFF` before the switch), which
costs the instance no room; `.outside` grows the covering quad by another half
stroke. Hollow forces the bias to 0 (a band already has two edges);
lines/points/open-arc never compute a stroke band, so they stay centered.

### Coverage models

Coverage is split by whether a shape tiles, and the split is load-bearing:

- **Inside-biased** (`regionCoverage`): `box`, `pie`, `chord`, `triangle`,
  star/n-gon, and the non-round point markers get full coverage to the
  geometric edge with the AA halo only outside, so abutting fills (tiled
  grids, gradient bands, the rotated wedges tiling a cell in `LifeQuilt`)
  leave no seam. Moving them onto a centered ramp brings the seams back.
- **Area-conserving** (`diskCoverage` and the capsule case): the disk
  (ellipse/circle/round point) and capsule/line use a centered AA ramp, but
  any mark smaller than ~half a pixel keeps a ~1px footprint while its alpha
  scales by the true/clamped **area** (disk) or **width** (line). Sizes run
  0...n: tiny dots, small circles, and thin lines fade by area instead of
  popping in, snapping to a 1px floor, or flickering as they move. Safe
  because disks and lines never tile edge-to-edge, so they need no inside
  bias.
- **Ink-conserving stroke bands** (`strokeBandCoverage`, shared by the region
  and disk outline paths): a band thinner than ~1px holds a ~1px footprint
  with alpha scaled by the width ratio (the capsule's trick), so an outline
  thinner than a pixel fades to nothing instead of plateauing at a fixed
  hairline. The old smoothstep band floored at ~half coverage as `hw -> 0`, so
  a 0.4px and a 0.05px outline read alike. A band at or above ~1px reduces to
  the plain smoothstep edge it always was (byte-identical, snapshot-safe).

These area-conserving paths and every stroke band then run their coverage
through `perceptualCoverage` (see *Linear-light compositing* below).

### Adding an SDF shape

The tagged union has a fixed *scalar budget*: `size` (2) + `param0` (2) +
`param1` (2) + `param2` (2) + `extra` (1) on top of the per-instance
CTM/center/colors/stroke. Any shape that is a canonical form parameterized by
a size plus a ratio or two drops in as four touch-points (an `SDFShape` case,
a `Drawer.draw*` builder, an `sd*` function, a fragment `case`) with **no
renderer or pipeline change**; position/rotation/scale come free from the
CTM. One constraint: `size` is *not* a free slot. The vertex shader uses it as
the covering quad's AABB half-extent, so it carries the bounding extent and
cannot double as a geometry point. The two shapes that need three free points
beside size-as-AABB (the general 3-point triangle and the quadratic Bezier
stroke) forced the one widening so far: `param2` took the stride from 128 to
144, and the 8 bytes of tail padding that left have since been claimed by the
gradient-paint row fields. **The struct is full at 144: the next field is a
real widening.** Two things stay off this path by nature: arbitrary
polygon/polyline (variable vertex count; they stay on the triangle path), and
SDF *operators* (smooth-min, union/subtract, domain repetition), which combine
fields and live on the SDF-combinator path. The distance functions come from
iq's 2D catalog (implemented from the technique, credited in
`ATTRIBUTION.md`); hg_sdf is the source for the operator track.

### The fringe stroke path

Every stroked path (`drawLine`, `drawBezier`, `drawPolyline`, the
`drawPolygon` outline, `drawShape` contours) renders through the
AGG/NanoVG-style fringe expander (`appendFringeStroke`, written from the
technique; no SDF, no MSAA/SSAA). The path is edge-expanded CPU-side into
per-segment butt quads plus a ~1px screen-space anti-aliasing fringe
(`fw = 1/ctmScale`; coverage ramps 1 to 0 across it, GPU-interpolated so the
edge stays smooth at *any* angle at native resolution, fixing the staircase
the SDF capsule's single-sample `fwidth` left on shallow diagonals). It rides
its own `.fringe` `GeometryKind`/pipeline (`ollin_fringe_vertex`/`_fragment`)
but **reuses the triangle vertex buffer**: the coverage rides in an `aa` field
tucked into `OllinVertex`'s existing float2-to-float4 alignment padding
(stride stays 32, the triangle path byte-identical), with the stroke's rgb
plus paint alpha in `color`. The fragment remaps **only the coverage** through
`perceptualCoverage` and keeps the **paint alpha linear** (translucent strokes
composite at their true opacity; keeping the two channels separate is *why*
the `aa` field was needed). Solid, translucent, and gradient paint all take
this path; gradient samples per path vertex like the tessellated path
(`vertexPaint`: along-path reads arc length, long segments split first so the
baked LUT tracks).

The fringe **straddles** the true edge, so perceived width equals
`strokeWidth`; geometry stayed within snapshot tolerance of the old
SDF/tessellated output, so no snapshot re-record was needed. Joins and caps
are honored via per-join outer-gap fillers (`strokeJoin` `.miter`, beveling
past the limit, `.bevel`, `.round`; `strokeCap` `.butt`/`.round`/`.square` on
open ends), so `drawLine` (single segment, cap-only; now default **butt**, not
the old always-round capsule) and `drawBezier` (flattened, then cap plus
joins) honor them too. `appendStrokedPath` (the old tessellated join-filler
path) is retained for text glyph stroking only.

**Fills stay on libtess2 plus 8x MSAA, byte-identical.** The empirical call
(native-resolution A/B): MSAA fill edges are already smooth, and a fill fringe
would reintroduce abutting-fill seams (Voronoi, LifeQuilt) or fatten shapes,
so the fringe is strokes-only.

**A cross-section carries a point on the centerline, and that is load-bearing.**
The five points are outer edge, core, center, core, outer edge, so a segment's
ribbon is four quad bands rather than three. Coverage does not change across the
two core bands, so the split draws nothing new; what it removes is a T-junction.
Every join fans out from the path vertex itself (`center` in `appendFringeStroke`,
shared by the miter, bevel, and round builders), and with no cross-section point
at offset 0 that apex landed in the *middle* of the core band's end edge. The two
edges are collinear in exact arithmetic, but the rasterizer snaps each endpoint to
its sub-pixel grid independently, and the hairline that opens between them
swallowed the occasional MSAA sample. The symptom was isolated pixels of 6/8
coverage buried inside solid ink, never runs, appearing and vanishing as the
stroke weight moved by half a point.

Worth recording, because it sent the first investigation down a blind alley: the
artifact reads as *46% coverage* if you measure the pixel in sRGB, which is
impossible for the sub-pixel gap the geometry allows, and the contradiction
looked like evidence against a seam. Compositing is linear-light, so the same
pixel is 75% coverage, exactly two samples of eight. **Measure coverage in linear
light before reasoning about how wide a gap must be.** Diagnosis came from the
positions rather than the values: every hole sat on the radial line through an
integer path vertex, outside the turn, between 0 and `coreHalf` of it, which is
precisely the span the join's apex edge shares with the ribbon.

**Consecutive segments end on their shared inner crossing, and that is what
makes translucent ink lay down one coat.** On the inside of a turn the two
segments' edges genuinely cross, at the inner miter point. A segment that ends
on its own perpendicular runs past that crossing and into its neighbour, so both
quads cover the wedge between the two perpendiculars. Opaque ink hides it. Ink
that is not opaque composites the wedge twice: a 40pt stroke at alpha 0.25 read
224 along the arm and 197 in a hard-edged diamond at a right-angle corner, which
is 0.75 against 0.75 squared in the linear light everything composites in, a
clean second coat. Spread over a dense curve the same defect became a graded band
down the inside of the turn (mean 224.6 falling to 221.5, single pixels as low as
197) and, on a spiral, a comb of dark radial spokes, one per join.

So both ribbons end on the crossing point. `innerMiter[v]` holds the direction to
expand along on the inner side, scaled so that `pts[v] + innerMiter[v] * off`
sits exactly `off` from *both* centerlines, which is what keeps the coverage ramp
correct (coverage is a function of distance from the centerline, and a miter
point preserves that distance to both segments by construction). The two ribbons
then share that edge exactly: no overlap, and no gap. This is NanoVG's
`nvg__chooseBevel` model, written from the technique.

Three things make it safe to leave everything else alone. The **outer** side is
untouched, still ending on the segment's own perpendicular, so the join filler
and the centerline seam above are unaffected. The covered **region is
unchanged** for an opaque stroke: the union of two overlapping strips is already
bounded by the two inner edges meeting at the crossing, so moving the internal
seam onto that crossing draws the same shape, which is why the whole snapshot
suite passed unrecorded. And **collinear vertices are skipped**, so a straight
polyline is byte-identical.

Where the crossing falls outside either neighbouring segment the ribbon would
turn inside out, so the ends stay square there (NanoVG's inner-bevel case, the
`dmr2 * limit * limit >= 1` test against the shorter neighbour). A corner that
sharp folds over itself whatever we do, and an overlap is a kinder failure than a
crack. Near-hairpins bail the same way rather than take NanoVG's clamped miter,
which would pull the two ribbons short of each other and open a white seam.

`appendStrokedPath`, the tessellated path retained for outline-glyph stroking,
shares the rule through `Drawer.innerCrossings`, but pays for it differently.
Its segments are plain quads with no point on the centerline, so once the inner
end bends away to the crossing, the end edge no longer passes through the path
vertex, and a join filler fanning from that vertex lands mid-edge. That is the
same T-junction the centerline point fixes above, and it showed immediately: a
comb of *pale* ticks on the outside of every curve, the exact mirror of the dark
comb being removed. Splitting each segment in two at the centerline fixes it and
costs two triangles per segment. Moving the filler's apex onto the crossing fixes
it and costs nothing, because the gap is bounded by the two end edges, both of
which now run to that point, and it is still star-shaped about it. The two are
pixel-identical; the apex move ships. The fringe path cannot do the same, since
its fan has to meet the centerline point its cross-section already carries.

Cost is nothing measurable: the triangle count does not change at all, only
vertex positions, and the pre-pass is a few flops per vertex (`Patterns/Streamlines`,
M2 release, 1080², three interleaved runs: 5.516 against 5.521 ms/frame, inside
the noise of either variant). Vector export was never affected, since a profiled
stroke's outline is one nonzero-wound `Shape` and a uniform one is a native
`stroke-width`; the raster path now agrees with both.

Splitting the core is worth two extra triangles per segment (six to eight, about
21% more fringe vertices). Paid for by building each cross-section as a fixed
`Cross` value instead of the two arrays `offsets(_:).map` used to allocate per
call, four allocations per segment on a path that runs over every stroke in a
frame: a stroke-only sketch measures ~10% *faster* than before the seam was
closed (`Patterns/Streamlines`, M2 release, 1080²: 6.18 to 5.55 ms/frame).
`FringeStrokeTests` pins the seam behaviorally across joins, weights, and
curvatures, since the defect is a few pixels in a million and any whole-frame
mean difference averages it away.

### Fills and the triangulator

The vector `Shape`/`Contour` type (concave polygons, holes) fills via vendored
libtess2 (the GLU tessellator lineage), wrapped in `Shape.triangulatedFill()`
(`ShapeTriangulator.swift`, `import CLibtess2`) and drawn by `drawShape` on
the triangle path. The fill rule is a per-`Shape` `winding: FillWinding`
(`.evenOdd` default, where nested contours become holes and direction does not
matter, or `.nonZero`), mapped to `TESS_WINDING_ODD`/`TESS_WINDING_NONZERO`.
Convex shapes (circle, rect, ellipse, convex `drawPolygon`) keep the direct
fan/strip math; routing them through the triangulator is a pure loss.

Font glyphs are this path's hardest customer, and their two gotchas are
detailed in CLAUDE.md's *Text* bullet (glyph shapes must be `.nonZero`;
San Francisco's overlapping sub-contours need a Clipper2 union clean at a
reference scale of 1024 followed by Ramer-Douglas-Peucker simplification,
cached per glyph and size). The mechanism notes worth keeping here: the union
only merges cleanly when curves are finely flattened, and flatten density
tracks the render size (`CurveSampling`), which is why the clean must run at
the large reference scale and then rescale; and the reference-scale flatten
leaves contours ~40x denser than the render needs, which per-frame stroke
tessellation then pays for (a real 12-fps regression), hence the simplify
step. `Shape.mapPoints(_:)` preserves `winding`; rebuilding a glyph via
`Shape(contours:)` silently resets it to even-odd (that re-breaks the `e`).
The niche `glyphRun` text-on-path/per-glyph path still flattens raw, a known
follow-up.

Curved outlines (quadratic/cubic Bezier plus Catmull-Rom `curve`) sample to
points via the public `Path` builder (`Path.swift`:
`move`/`line`/`curve`/`quadCurve`/`cubicCurve`/`close`, plus `Contour` and
`Shape(curveThrough:)`), surfaced as the closure sugar `drawShape { p in ... }`
and the top-level `drawCurve(_:closed:)`. They feed the same triangulated fill
and stroked path, so a curve never touches the SDF/renderer side; the
`Contour`/`Shape` data stays polygonal and the `Path` just flattens curves
into it.

### Linear-light compositing and perceptual coverage

Geometry composites into a linear `rgba16Float` intermediate (`linearFormat`;
the sRGB `.bgra8Unorm_srgb` `ollinColorPixelFormat` is the drawable/present
format, not the geometry target), so the hardware blends and resolves MSAA in
linear space: anti-aliased edges and translucent stacks composite physically,
without the too-dark fringes of a gamma-space blend, and the float precision
keeps many overlapping translucent layers from banding as an 8-bit
intermediate would.

Three pieces keep tones from shifting, each a real bug when missed:

1. Shaders **linearize** their sRGB `Color` inputs before compositing and
   output linear into the float target; the *present pass* re-encodes to sRGB.
2. The **background/clear color is also linearized** (`Color.srgbToLinear` in
   `mtlClearColor`) so the clear value lands in the float target as linear,
   matching shaded geometry. Miss this and the background washes out lighter,
   because the clear bypasses the shader.
3. Image textures load `.SRGB: true` so each sample decodes to linear,
   matching the linearized solid colors beside them.

A triangular-PDF **dither** (a pure function of pixel position, so renders
stay reproducible) is applied in `finalizeColor`, which runs **in the present
pass** (the single 8-bit quantization point, after tone-mapping the resolved
float frame), breaking the banding smooth gradients otherwise show. The image
fragment skips the dither: its source pixels are premultiplied, and it outputs
premultiplied linear straight into the float target.

**The one deliberate carve-out from pure linear light: stroke and disk/dot AA
*coverage* is remapped to perceptual alpha** (`perceptualCoverage`,
`1 - srgbToLinear(1 - c)`) before compositing. Linear blending makes a
partially-covered dark mark read lighter than its coverage (a 50%-covered
black pixel lands at sRGB ~0.74), so a thin diagonal line's
correctly-conserved ink splits across the pixel staircase and reads faint and
"beaded" (the bug that made the Molnar *Interruptions* field look chopped
after the linear-light switch). The remap lands each covered pixel at the
gamma-space darkness its coverage implies, so a 1px stroke is evenly dark at
any angle and a sub-pixel mark still fades 0...n. It touches **only partial
coverage** (`perceptualCoverage(1) = 1`, `(0) = 0`) and never a shape's own
fill/stroke *alpha*, so solid interiors and translucent/overlap blending stay
linear-light. It applies to the capsule/`drawBezier` strokes, `diskCoverage`
(fill and outline), and `regionCoverage`'s stroke band, but **not** the region
*fill* ramp, which stays plain linear so abutting fills tile seamlessly.

Paired with this, the capsule/Bezier AA footprint uses the **L2 gradient
length**, not `fwidth`: a unit-gradient distance field's L1 norm overshoots by
sqrt(2) at 45 degrees, which had been fading diagonal 1px lines as if
sub-pixel. Verified near-optimal for the raster path: 4x SSAA barely beats it;
a 1px diagonal's residual softness is fundamental to native-resolution
rasterization (see `DESIGN-NOTES.md` on the supersampled render scale).

### Retained batches (`Batch` / `makeBatch` / `drawBatch`)

The per-frame model re-records and re-uploads every mark each frame; a
`Batch` (`Sources/Ollin/Drawing/Batch.swift`) is the escape for *static, heavy*
content: the recording happens once and the replay costs one reference batch.
Measured on an M2 at 1080^2, release: 150k circles cost ~13.5 ms/frame CPU
(~74 fps ceiling) on the per-frame path and ~0.003 ms/frame replayed, with the
frame's own arrays staying empty.

**Recording is an array swap, not a parallel recorder.** `Drawer.makeBatch`
swaps the per-frame geometry arrays, the batch list, and the gradient-row table
for fresh ones, runs the body through the ordinary funnels, moves the results
into the handle, and swaps back. That buys every 2D path (SDF instances,
triangles, fringe, images, atlas glyphs, SDF-combinator groups, point clouds)
with zero funnel changes, and it makes the captured `GeometryBatch` runs
self-consistent: the encode derives a run's count from the *next* run's start,
so recorded runs must index the handle's own arrays, never the frame's.
Swapping the gradient-row table makes the baked row indices inside recorded
`SDFInstance`s **handle-relative**: at encode the replay binds the batch's own
strip texture (`MetalRenderer.makeGradientStrip`, the shared builder behind
the frame's cached strip), so a recorded gradient can never point into
whatever rows the *current* frame happens to have. The body runs inside
`pushState`/`popState` from an identity CTM, with the target/clip stacks
swapped out, so a recording is style-scoped and context-neutral; `drawBatch`
supplies the draw-time context (target, clip level, 2D depth) on the reference
batch. Content that interlocks with per-frame passes (meshes and 3D fields,
which would silently drop out of shadow/reflection passes; particles; layer
blocks; clipping; `background`) is gated at its funnel with a one-time note,
because dropping a batch *after* recording would corrupt the next-run count
derivation.

**Replay is a reference batch plus a flag-gated uniform transform.** `drawBatch`
appends one `.retained` `GeometryBatch` carrying the handle and the CTM (nil
when identity). The encode loop hands it to `encodeRetained`, a contained
sibling of the main per-kind arms that binds the handle's persistent
`MTLBuffer`s (made once per device from the immutable arrays, so the
triple-buffer ring rule doesn't apply: nothing ever rewrites them) at each
inner run's offset. The draw-time CTM rides new `Uniforms` fields
(`batchTransformed` + `batchTransform`) that every 2D vertex shader applies
*to its output position only*, behind a flag test that stays 0 outside a
replay, so the ordinary paths' arithmetic is untouched (the whole snapshot
suite stayed byte-identical) and an untransformed replay renders byte-identical
to the recording (pinned by `BatchRenderTests`). Transforming the output alone
is what keeps SDF analytic AA exact under any replay rotation/scale: the
shape-local interpolants never change, and `fwidth` re-derives the on-screen
footprint. Point-cloud runs ignore the 2D transform and project through
whatever camera is active at replay. On exit the loop's uniforms binding is
restored so following batches are undisturbed.

**Vector export records commands instead.** Vector mode replaces GPU emission
per funnel, so a batch can't carry both representations without running the
body twice (which would double-consume the rng). Instead
`OllinApp.isVectorExporting` spans the *whole* `recordVectorFrame` drive
(setup and warmup included, unlike the per-frame `svgRecorder` install), and
under it `makeBatch` runs the body against a private recorder, storing
`SVGCommand`s in the handle; `drawBatch` splices them into the active recorder
with the draw-time CTM left-composed per command. Each export path builds a
fresh sketch (`handleCommandLine`'s one `make()` wrapper), so a handle never
needs both representations in one life.

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
`.reactionDiffusion(feed:kill:)` (Gray-Scott), `.gameOfLife` (Conway),
`.lenia(...)`, `.ripples(...)`, `.sandpile(...)`, `.multiScaleTuring(...)`, and
`.fluid(...)`. A sketch draws into the field to seed or force it
(`withField(_:_:)`, scoped like `withTarget`): the renderer renders the drawn
marks into a transient seed texture, runs `ollin_sim_inject` to composite the
seeds onto the front state, then steps the sim's `ollin_sim_*` fragment N
sub-steps per frame (reaction-diffusion 14, Game of Life 1), ping-ponging pooled
scratch into the back buffer (`runSimulation` in `MetalRenderer`). The inject
pass binds the sim's parameter rows after the texel row, same as the step, for
the injects that read one (the sandpile's pour); the pre-existing injects never
look past the texel row, so the binding change was byte-identical for them.

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

#### Multi-scale Turing (`.multiScaleTuring`)

McCabe's rule (written from the Bridges 2010 paper, credited in
`ATTRIBUTION.md`): one substance in `0...1`, and at each scale an *activator*
average over a small disc against an *inhibitor* average over a larger one. The
scale whose two averages differ least wins that pixel and nudges it toward the
greater of the two; the field is then renormalized to fill its range again,
which is what stops the nudges accumulating into a runaway. Like `.fluid` it
needs more than one pass, so it runs its own `runMultiScaleTuring` pipeline, but
unlike the fluid its storage is a single ping-pong pair, so it shares
`FeedbackSlot` and inherits the flip, the prune, and the
`statefulEncodeIsRepeat` arm unchanged.

The passes: inject the drawn seeds; build a blur pyramid down to 1×1; per scale,
measure `|activator − inhibitor|` at full size and run it down the same halving
chain to the rung its `variationRadius` names; step; reduce the stepped field to
its minimum and maximum through a 4×4 chain; normalize into the back buffer.
Precomputing the variations means the step recomputes only the *winner's* two
averages, which is what keeps a symmetric field affordable (one scale's fold per
pixel rather than every scale's).

Four things about the GPU realization are load-bearing, and each was a real
defect first, found by bisecting a single scale against the paper's figures
rather than by reading the output as a whole:

- **The field starts as seeded noise, not a constant.** A uniform field has every
  average equal at every scale, so no scale ever fires: it is a fixed point, and
  a constant rest state leaves the sketch black forever with no hint why. This is
  why `feedbackSlot` grew a `fill:` override beside `restState`.
- **The pyramid is Gaussian (Burt-Adelson binomial), not a 2×2 box mean.** A
  square kernel has square preferred directions, and the labyrinth came out
  rectilinear, all right angles. The separable `(1,3,3,1)/8` about the block
  center is four bilinear taps at ±0.75 source texels with equal weight, the same
  cost as the box, and repeated down the rungs it converges on a true Gaussian.
- **A radius gathers a nine-tap disc two rungs *finer* than the radius match,
  never a single tap at the matching rung.** This is the subtle one. The matching
  rung has the right blur *width* but holds only one sample per feature, so the
  reconstruction between samples has nothing to go on and the pattern locks to
  the lattice. No amount of kernel smoothing fixes it, because the information is
  not there; the pyramid has to be oversampled relative to the blur. Two rungs
  finer puts the lattice at a quarter of the blur width, and the ring rebuilds
  the disc isotropically (each tap is itself a smooth Gaussian about a quarter of
  the radius, so the taps overlap rather than reading as a ring of blobs).
  `MultiScaleTuringTests.patternIsIsotropicRatherThanLockedToTheLattice` measures
  the gradient-energy-weighted mean of `cos(4θ)`: the defect scores 0.63, the
  shipped gather 0.11, and the counterfactual was run to confirm the test fails
  on the defect rather than merely passing on the fix.
- **Variation is averaged over a per-scale `variationRadius`, not read at a
  point.** Read at a point, a fine scale's disagreement passes through zero along
  every contour of its own structure, and since *least* disagreement wins it
  claims a dense web of pixels across the whole field and buries the coarse
  scales. (Softology's write-up notes single-point variation gives "the sharpest
  most detailed images", which is the same observation from the other side.)
  Measuring the winner distribution directly, by temporarily routing the winning
  index into a colour channel, is what separated this from the amount question
  below: the coarsest scale was already winning 68% of pixels in contiguous
  regions, so selection was never the problem.

Two *parameter* facts are equally load-bearing, because renormalization couples
the scales to each other: the rungs want **equal amounts** (whichever pushes
hardest sets the field's range, and the rest are squeezed toward mid gray, so an
uneven ladder gives one scale's pattern with the others as a faint wash), and the
ladder **starts at radius 2** (a rung at radius 1 works on single texels, and
pixel-scale features read as speckle rather than detail).

Two constants are paired across the language boundary: `TuringScale.maxScales`
(6) with `OLLIN_TURING_MAX_SCALES`, and `MetalRenderer.turingPyramidLevels` (12)
with `OLLIN_TURING_LEVELS`, which sizes the `array<texture2d<float>, N>` binding;
a shallower pyramid repeats its top rung to fill it and `levelCount` keeps the
shader off the padding. Deliberate v1 cut: the winning-scale index is *not*
carried in the state, so colour-by-scale (McCabe's coloured plates) is not
available; it would mean spending a channel that both the display and the extent
reduce read as gray.

This sim is also what surfaced `Drawer.ensureFieldSteps`. A sim only evolves
while its layer is one of the frame's render targets, which `withField` is what
normally arranges. That is right for a sim you seed by drawing, but a
self-organizing one needs nothing drawn into it, and the natural sketch (make it
in `setup`, `drawImage` it in `draw`) would sit frozen. So `SimField.image` and
`.filtered(_:)` register the field too; the layer's transparent clear is what
makes that safe, since an unseeded frame renders a seed that composites nothing.
Existing sketches register via `withField` first, so target order is unchanged
and the whole snapshot suite passed unrecorded.

#### Abelian sandpile (`.sandpile`)

The Bak-Tang-Wiesenfeld toppling automaton (1987, the model that named
self-organized criticality; credited in `ATTRIBUTION.md`), and the counterpoint
to the Turing pipeline above: it is exactly the cheap, generic single-texture
sim the step path was built for (one gather fragment, no dedicated pipeline).
Each pass every cell holding at least four grains topples, *as many times as it
can at once*: for every four grains it holds it sends one to each of its four
neighbours and keeps the remainder, so in quarters the whole update is
`q' = fract(q) + Σ floor(q_n) / 4`. Dhar's 1990 abelian-property result is what
licenses any parallel schedule, single or k-fold, since topplings commute and
the settled pile is the same in any order. The k-fold form matters and was
found empirically (the first render used one toppling per pass): where every
cell holds fewer than eight grains, the regime a critical pile lives in, the
two are *identical*, but at a heavy source single toppling pools, because a
saturated blob's interior is net zero (lose four, receive one from each of
four toppling neighbours) and only its perimeter drains; a measured 800-frame
run settled just 13% of what was poured, with the rest stacked at the source.
The k-fold form drains a hot source exponentially instead, which is what makes
the classic drop-a-mountain-and-let-it-collapse figure renderable in seconds.
`SandpileTests` turns the abelian theorem into the verification: the GPU's
parallel sweeps interleaved with pouring must match a sequential CPU
stabilization *cell for cell*, which pins the threshold, the gather, the
inject rounding, and (in the edge-block variant, verified red against its
counterfactual) the open boundary.

The GPU realization has four more load-bearing choices:

- **Grains are stored in quarters** (one grain = 0.25) so a stable cell reads
  0, ¼, ½, ¾ directly (`gradientMap`-ready, one flat level per count) while the
  arithmetic stays exact: quarter steps in a half-float texel are exact to 2048
  grains, far above what the clamped pour (≤ 1024/frame) can pool.
- **Reads come from `.r` only.** The state is written to all three channels for
  a readable gray image, but the step and inject read the one channel: a
  luminance dot product is off by an ulp, and the step's `floor`/`fract` at the
  toppling threshold are exact operations an ulp would break.
- **The boundary is open, never wrapped or clamped.** A neighbour position off
  the field contributes nothing, and a toppling cell always loses four, so
  grains crossing the edge are simply gone. That dissipation is what lets a fed
  pile keep settling (on a torus sand only accumulates until every cell topples
  forever), and the guard must reject the position *before* sampling, or the
  clamping sampler reads the edge texel back as its own neighbour: a reflecting
  wall, the counterfactual `grainsFallOffTheOpenBoundary` was verified against.
- **The inject rounds to whole grains.** A mark pours
  `rint(luma × pour) / 4` onto the state (additive, like the ripples inject:
  replacing would erase the pile), so a soft anti-aliased fringe pours whole
  grains or none and the count never leaves the integer lattice; the rounding
  also absorbs the ulp in a white mark's luminance. Nothing erases; easing off
  the pour is the only way to stop.

`topplings` is `subSteps`, a factory knob rather than a constant because an
avalanche front moves one texel per pass, which makes it the pacing dial: watch
single waves at 1, hurry a collapse at 128. The two pour protocols look very
different and both are honest physics: the *classic relaxed figure* comes from
dropping one heavy mark on one frame and letting the field settle (the
`Sandpile` example and the Guide figure both do this), while a *held* heavy
mark keeps a molten super-critical core for as long as the torrent runs,
because each frame's pour re-fills the interior faster than the rim sheds; the
display shows it honestly as the top of the ramp, not a defect to guard
against.

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

It runs as **two passes**. A pre-pass (`ollin_fx_dof_prepass`) reduces the depth
map to three per-pixel numbers, `(scatter, depth, receive)`, and the gather then
reads those instead of the depth, so a tap costs one texture sample and no math.
Moving the seam dilation into that pass as well took its 8 taps out of the
per-pixel loop; the whole change measures **~35% faster** at 192 taps (M2,
1080x1080, three runs each back to back: 22.0 ms before, 14.2 ms after).

The two sizes are deliberately different, and each answers the *same* problem from
one side. A depth map's silhouettes are anti-aliased, so every outline carries a
sub-pixel band of in-between depth:

- **Receive** is the max over a small ring (the seam dilation). Where that band
  sweeps through `focus` it leaves a ~1px in-focus ring tracing each defocused
  mark, which reads as a thin dotted circle; taking a pixel's own blur as the
  neighbourhood max consumes it, while a real in-focus subject is thick enough to
  keep its near-zero size.
- **Scatter** is the min over the immediate neighbourhood. Where the band instead
  lands in the *fully defocused* range it flings the colour beneath it across the
  entire blur radius, and because the whole rim shares one depth it cuts off at
  one radius too: a perfectly in-focus object came out ringed by a faint,
  hard-edged, concentrically ridged halo of its own colour (7 to 10% of the
  object's brightness against a dark backdrop, out to `maxBlur`). A rim texel
  always has a low-blur neighbour on the object side, so the min erases it, while
  a genuinely defocused region keeps its size. The radius is 2px, not 1, so the
  erased band is wider than the gather's bilinear footprint, which would otherwise
  average half the rim's size straight back in.

Each tap is sorted by whether it is nearer than focus (foreground) or not, into
two accumulators, each a Gustafsson running average:
`acc += mix(acc/tot, sample, reach); tot += 1`, where `reach` tests whether a
tap's own blur spans its distance. A non-reaching tap adds the current average
rather than zero, so every tap counts. This both kills grain (no variance from a
varying effective sample count, so no per-pixel jitter is needed) and blends
overlapping bokeh. Three details of the accumulation are load-bearing:

- **Both fields seed with the centre texel.** Seeding the near field with black
  instead (the obvious "nothing here yet" value) leaves its running average
  converging *from* black, weighted `1/(taps+1)` per reaching tap, so a partly
  covered foreground composites that bias over the background. A uniformly white
  layer with a near disc in its depth map came back with a ~12% dark ring.
- **Alpha rides the gather with the colour.** The layers are premultiplied, so
  blurring rgb past a sharp alpha stops the result being premultiplied at all: a
  shape on a transparent layer kept a razor silhouette however much blur was
  asked for. An opaque layer is unaffected either way.
- **A tap behind this pixel is occlusion-clamped** to twice this pixel's own blur
  (Gustafsson's clamp). Without it a heavily defocused backdrop pours over a
  barely defocused midground for the full `maxBlur`, whatever the midground's own
  blur: a square with a 4.8px circle of confusion lost 30px of its edge to a 48px
  backdrop. Two comparably defocused regions are each within 2x the other, so
  overlapping bokeh still merges instead of hard-cutting along a silhouette.

**Near/far separation is the load-bearing idea**, and it is the thing a plain
single-pass gather cannot do. The far side resolves first (the sharp centre
blended toward its own bokeh by how defocused it is), then the foreground field
composites *over* that by its coverage, so a defocused foreground spreads over
and hides an in-focus subject behind it instead of leaving a sharp crescent, and
an in-focus subject otherwise stays crisp and correctly occludes what is behind
it. Folding the two into one `mix(centre, mix(bg, fg, a), max(dof, a))` applies
the coverage twice and leaves a half-covered sharp subject a quarter more of its
sharp self than it should have.

Two rules make the foreground's own silhouette soften on **both** sides of itself,
which is the half that is easy to get wrong (it blurred outward and stayed razor
sharp inward, stepping 40% of the way to the background in a single pixel):

- **A pixel under a near blur lets the background field gather from anywhere
  inside that blur** (`nearReveal`). Otherwise nothing sits behind the foreground
  for it to become transparent against, since the in-focus scene around it never
  "reaches". What a foreground truly hides cannot be recovered from one image;
  standing its neighbourhood in for it is the usual approximation and reads right.
- **Foreground coverage is an area fraction of that near blur, not of the whole
  gather disc.** The spiral is equal-area per tap, so taps inside radius `r` number
  `total * (r/maxBlur)^2`; normalising by the disc instead (with a constant fudge
  to make up the difference) pins the alpha at 1 well inside the silhouette, which
  is exactly what kept the inner edge hard. Normalised properly the alpha passes
  through the silhouette mid-ramp and falls off over the foreground's own blur
  radius either side.

An expanding golden-angle spiral (`radius += radScale/radius`, with `radScale`
proportional to `maxBlur` squared) packs rings denser toward the rim so the bokeh
edge is smooth without jitter.

The seam was the most stubborn artifact in this effect, and the lesson is general:
an artifact that survives every change to subsystem X is not in X. The seam
survived every gather rewrite because it lived in the CoC/depth, not in the
gather; a debug visualization of the in-focus map (returning
`1 - centerCoC/maxBlur`) made it visible directly. Returning the pre-pass channels
raw out of the gather is the same move and worth reaching for early.

This works on smooth/continuous depth (a gradient or a depth feed) and on
hard-edged discrete per-object depths with overlapping objects. `quality` is a
`RenderQuality` tier that the renderer resolves to a per-GPU bokeh tap budget
(`resolveDofTaps`); the tap budget, not the blur radius, is what `quality`
controls, so `.detail` is creamier and `.performance` is faster, while `maxBlur`
is the blur amount.

The tap budget was tuned with data from `Scripts/benchmark.sh dof`
(`DofBenchmarkTests` sweeps tap counts via the internal `dofTapsOverride` hook and
the effects-aware `benchmarkGPUMilliseconds`). Take the numbers back to back on a
cool machine: single runs drift by 50% under thermal load, which is enough to
invert an A/B. On an M2 at 1080x1080 the `.default` tier (192 taps) measures
~14 ms and holds 60 fps. The shader's `OLLIN_DOF_TAPS` constant is the fallback
default when no budget is passed. The `Effects/Defocus` example racks focus
through orbs at discrete per-object depths (a moderate count, so dense occlusion
stays readable), and its snapshot pins the overlapping hard-depth case.

The pixel snapshots passed within tolerance across every one of the fixes above,
because a mean-per-channel comparison averages away defects that live in a band
around each silhouette, which is where all of them live. `DefocusTests` pins them
directly instead: a near spread invents no colour, a sharp subject rejects the
backdrop, a lightly defocused midground keeps its edge, a foreground silhouette
softens on both sides, transparency blurs its coverage, and `maxBlur` 0 is a
pass-through. Reach for a behavioral probe here, not a whole-frame diff.

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

**The tier is a GPU sampling budget only; geometry dials never join it.** Every
`RenderQuality` consumer changes how the *same* image is sampled (shadow rays,
bokeh taps, AO samples, SSR steps, the raymarch's internal resolution), which is
exactly what licenses the export auto-upgrade and the byte-identical
default-tier snapshots. The CPU geometry features' cost dials
(`MeshGrowth.maxVertices`, `subdivided(_:levels:)`, isosurface / `Metaballs`
`resolution`, an erosion's droplet count, `medialAxis(of:spacing:prune:)`'s
sampling step) look similar
but are kept out on purpose, for three structural reasons. First, geometry is
data the sketch reads back: vertex counts drive loops, positions seed per-point
decisions, results feed physics and coloring, so a tier that moved one of these
dials would change the *piece* (and how much of the seeded RNG stream the
downstream code consumes), not the fidelity of its rendering, and the
seed-plus-params reproduction promise (`ExportMetadata`) would break. Second,
the tiers resolve per-GPU by design, and a hardware-relative form is
unacceptable for geometry: the same seed must produce the same artwork on every
machine. Third, there is no shared axis: a vertex ceiling, a refinement count, a
grid density, and a droplet count each mean something the artist should choose
in domain terms, and a tier-to-value mapping picked by the framework would
itself be an artistic decision. Even the dials that converge toward an ideal (an
isosurface's `resolution`, subdivision `levels`, `medialAxis` spacing) fail the
first two tests. The framework's taxonomy already covers these: seeds are
identity, knobs are tuning, and a geometry dial is a knob, served by `@Param`
and `--export-sweep` rather than by a tier.

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

### Area lights (linearly transformed cosines)

`rectLight` / `diskLight` / `tubeLight` (`Light.rect/.disk/.tube`, GPU kinds
3-5) shade a glowing surface analytically: a linearly transformed cosine (a 3×3
transform of the clamped-cosine distribution) approximates the GGX lobe per
(perceptual roughness, view angle) and still integrates in closed form over the
light's shape (Heitz/Dupuy/Hill/Neubelt's technique; per-shape citations in
`ATTRIBUTION.md`). The fitted inverse transforms and their (norm, average
Fresnel, clipped-sphere form factor) terms ship as two 64×64 float32 tables
bundled from the authors' BSD-3 reference release
(`Sources/Ollin/Resources/LTC/`, provenance + conversion recipe in the notice
beside them; the `ltc.js` export carries more precision than the repo's
half-float `.dds`). `ensureLTCTables()` loads them once into `rgba32Float`
textures bound at fragment textures 8/9 on every `meshLitColor` carrier (the
solid and textured mesh fragments, the raymarch fragment, and the half-res
field tier), with a never-sampled stand-in when absent and
`OllinLighting.ltcEnabled` gating the read, so a frame with no area light is
byte-identical and a corrupt bundle degrades to a one-time stderr note instead
of garbage shading.

Per shape, in the shader (`Shader3D.metal`, the `ollin_ltc_*` block):

- **Rect** uses the paper's *exact* path: transform the four corners into the
  view-aligned shading frame and clamped-cosine space, clip the polygon to the
  horizon (the 16-configuration table), and sum the analytic edge integrals
  (the rational theta/sin-theta fit replacing `acos`). The corner winding is
  chosen so the integral is positive on the side the light faces, which is why
  `packLight`'s frame must stay right-handed (`tangent × bitangent = facing`);
  `twoSided` folds the back side in as `abs(sum)`. The clipless
  vector-form-factor variant (cheaper, approximate near the horizon) was
  deliberately not used: the exact clip is the reference demo's default and the
  per-pixel branch cost is fine at eight lights.
- **Disk** transforms the disk's bounding quad, where it becomes an arbitrary
  ellipse: an eigendecomposition finds the principal axes, a cubic solve (the
  numerically robust split form of the trigonometric method) its horizon
  clipping, and the tabulated horizon-clipped sphere (table 2's `w` channel)
  maps the resulting form factor to the final integral. **The sqrt arguments
  clamp at zero**: they are provably non-negative in exact math (the
  discriminant of an all-real spectrum, Cauchy-Schwarz on the moment matrix,
  the root signs of a visible ellipse), but where a receiving surface grazes
  the disk's plane the float versions dip a few ulps under zero and every NaN
  reads as black speckle scattered over the grazing region (a real bug, found
  by a median-outlier sweep over the first example render and bisected to the
  disk path; the clamps cleared 1086 outlier pixels to the 73-pixel geometric
  baseline with no other change).
- **Tube** runs the analytic line integral (horizon-clamping the segment,
  then the position/tangent antiderivative pair) in clamped-cosine space,
  scaled by the transform's width factor, times the tube radius. The width
  factor needs the transform's inverse-transpose, taken from the columns'
  cross products (the normal-matrix identity), so the sparse matrix never
  needs a general inverse. No end caps, matching the reference default. Two
  guards the reference lacks: the perpendicular-foot distance floors at 1e-4
  (a surface point on the extended axis divides by zero) and a vanishing
  endpoint cross product skips the width factor (the segment seen edge-on).

Diffuse always evaluates with the identity transform (an untransformed clamped
cosine is exact Lambert), so only the specular half reads table 1. In
`meshLitColor`'s loop the area branch `continue`s past the whole punctual path:
the PBR model blends table 2's norm and Fresnel channels by F0; the standard
model maps `shininess` onto the equivalent GGX width (`alpha = sqrt(2/(s+2))`,
so perceptual roughness is its fourth root) and scales the norm channel by
`mat.specular` (inert at zero, the finish rule); toon quantizes the soft
diffuse into its cel bands (the highlight stays smooth; a soft light has no
hard cel edge); Gooch takes highlight only, keying its tone axis off the
panel's direction. The subsurface finish's back term re-evaluates the diffuse
integral with the normal flipped, so the translucent bleed carries the panel's
real falloff. `intensity × color` is the emitting surface's radiance (the
LTC-native convention: a full surrounding hemisphere of radiance 1 returns the
albedo exactly), which is why area lights fall off physically while the
punctual kinds keep their no-attenuation model, and why a thin tube runs at
intensities in the tens. Area lights never cast shadows (the caster search
covers the punctual kinds; the area-extent caster is the roadmap's *Light
shaping* item), and the RT-reflection hit shade approximates them as centroid
emitters with an area/(π·d² + area) falloff rather than binding the LUTs in a
secondary bounce. The head-on view (V ≈ N) takes a deterministic fallback
tangent instead of normalizing a zero vector (the reference leaves this case
unguarded; the head-on LUT row is fitted isotropic, so any tangent is exact).

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

## The geometry and generator catalog

The CPU-side geometry types and generative-technique recipes live in
`Sources/Ollin/Geometry/`. CLAUDE.md's *Geometry & color* bullet is the
capability index and keeps the terse regression-preventing invariants; this
section carries the mechanism and the history behind them. Two contracts span
the whole catalog. First, determinism: every builder is a pure function of its
inputs and seed (or a stateful class that steps reproducibly), so figures,
export recipes, and snapshot tests reproduce. The recurring rule behind it:
Swift `Set`/`Dictionary` iteration order is randomized per process, so no rng
decision or position-mutating pass may walk one directly; use sorted candidate
lists and fixed iteration orders (WFC is the canonical case, and mazes, space
colonization, boids, and the physics disk-collision resolver follow it).
Second, fit-by-points: a figure whose stroke should stay constant-width is
fitted by scaling its *points*, never `scale()`, because the CTM scales the
stroke width too (found as the trochoid fat-blob snapshot bug; applies to
Lévy flights and anything else fitted to the canvas).

### Grid

`Grid` (`Geometry/Grid.swift`) is a regular `columns × rows` grid over a
`Rectangle`, the typed replacement for margin-then-nested-loop boilerplate.
The row-major `points` (`Grid.Point`) and `cells` (`Grid.Cell`) elements
carry their indices, so indexed cases (checkerboard, hue-by-position) are a
single loop; killing the double `for` was the point of the type.
`Grid.Distribution` is `.center` (a dot per cell, the default) or `.spanning`
(an edge-to-edge lattice, ignores `gutter`); `cells` always tile and a cell's
`.center` is always its true center; `padding` is the outer margin, `gutter`
the gap between cells, both over the typed `Insets` (per-edge,
literal-expressible: `padding: 20` equals `.all(20)`). The element type
churned during design (a `Cell`-wrapping `Collection` whose `center` shifted
meaning read wrong, then flat arrays, then the rich indexed elements without
the shape-shifting) and is settled. Most 2D grid examples adopt it;
warped/proportional/polar layouts stay hand-rolled. Example `Patterns/Grid`.

### Shape booleans, offsets, and stroke-as-shape (Clipper2)

`Shape.union` / `intersection` / `subtracting` / `symmetricDifference` and
`offset(by:join:)` run over vendored Clipper2 (BSL-1.0, `External/CClipper2`).
They operate on the filled region; each side is normalized under its own
`winding` first. Offset output must be run through Clipper2's `SimplifyPaths`
before returning; without it, cascaded insets balloon vertex counts
geometrically. `Contour.stroked(width:join:cap:)` / `Shape.stroked(...)`
convert a stroke to a filled `Shape` via the shim's `cc2_stroke` (Clipper2
`InflatePaths` at half-width): open contours take `StrokeCap` end types,
closed ones become bands, and self-crossings union clean under non-zero
winding. Unlike `cc2_offset`, the input is *not* normalized first;
normalization would erase open paths, which are the whole point of stroking.
Open and closed groups stroke in two shim calls, then union. Example
`Shapes/InkRibbon`; snapshot `stroke-shape`; `StrokeShapeTests`.
`convexHull(of:)` is the monotone chain: corners in boundary order, collinear
edge points dropped, duplicates deduped (`ConvexHullTests`; example
`Shapes/RubberBand`). Both in `Docs/Drawing/Geometry.md`.

### SVG import

`Geometry/SVGImport.swift` reads `<path>` with the full grammar (packed
numbers, glued arc flags, S/T reflection; elliptical arcs become cubics of at
most 90° via the SVG F.6.5 center conversion), the basic shapes, `<g>` +
`transform` lists, presentation and inline styles, and both fill rules, into
per-element `Shape`s carrying fill/stroke/width/join/cap in document order
(`SVG.Element`; `id` maps to `name`, looked up via `element(named:)`).
Control points transform *before* flattening: flattening is affine-invariant,
so transforming first keeps sampling density matched to the final size (arcs
convert to cubics first for the same reason). The SVG initial fill is black
and the initial winding `.nonZero`, unlike Ollin's `.evenOdd` shape default;
the mismatch is per spec, so the two defaults stay different. An unresolvable
`url(#…)` paint falls back to mid-gray rather than dropping the element; open
contours never fill; unsupported containers (defs, clipPath, mask, symbol,
pattern, marker, style, text) skip their whole subtree via a depth counter.
Example `Shapes/SVGImport` (an original hand-authored rocket badge, drawn as
authored and mined as resampled dots); snapshot `svg-import`;
`SVGImportTests` covers the grammar edge cases including the post-`Z`
malformed-input stop.

### Fourier epicycles

`Epicycles` + `drawEpicycles(_:at:terms:)` (`Geometry/Epicycles.swift`): a
plain O(n²) DFT, built once at setup time, over a closed contour's even
arc-length resamples, into amplitude-sorted spinning-circle `Term`s (signed
integer `frequency`; k > n/2 folds negative). Read via `point(at:)` /
`joints(at:)` / `path(samples:terms:)`. The sort's tie-break (slower
|frequency| first, then positive) keeps symmetric inputs deterministic.
`terms:` is always a largest-first *prefix* of the one built chain, so a
detail knob needs no rebuild. `point(at:)` is periodic, so negative phases
wrap and a fixed-length trail across the lap seam is a one-liner. With all
terms the reconstruction is exact at sample phases; `EpicyclesTests` pins
that plus the circle/ellipse closed forms. No rng anywhere. Example
`Motion/Epicycles` (traces an original whale SVG, declares `loopDuration`);
snapshot `epicycles`.

### Classic curves and the harmonograph

`Geometry/ClassicCurves.swift` + `Geometry/Harmonograph.swift`, all rng-free
and deterministic. `phyllotaxis(count:spacing:angle:)` is Vogel's model
(default `Double.goldenAngle`; index = seed age).
`lissajous(a:b:phase:width:height:)` reduces shared frequency factors and
samples one exact period into a closed `Contour`. `rose(n:d:radius:)` reduces
n/d and samples exactly the parity-dependent closure span (πd when n·d is
odd, 2πd otherwise) so no arc retraces doubled.
`hypotrochoid`/`epitrochoid(ring:wheel:pen:)` take integer gear radii so
closure is guaranteed, sampling exactly `wheel/gcd(ring, wheel)` laps with
auto sample counts scaling by the laps; figure symmetry is `ring/gcd` lobes,
and the examples spin one lobe or petal per loop for seamless laps.
`Harmonograph` sums per-axis damped `Pendulum`s,
`amplitude·sin(frequency·τ·t + phase)·e^(−damping·t)`, frequency in turns per
unit time; `point(at:)` reads live, `contour(duration:samples:)` bakes; the
default duration `settleTime` is the 1%-decay time of the *slowest* pendulum,
capped at 240 when undamped. Chaikin `smoothed(iterations:)` on
`Contour`/`Shape` is the quarter-point corner cut; open contours keep exact
endpoints; each pass doubles the point count, iterations capped at 10.
Examples `Patterns/Spirograph` / `Patterns/Roses` (both declare
`loopDuration`), `Motion/Lissajous` (the classic table over `Grid`),
`Motion/Harmonograph` (pendulums rolled from the seeded `random`, one figure
per `variation`), `Shapes/CornerCutting`; `Patterns/Phyllotaxis` rides the
helper. Snapshots `classic-curves` + `harmonograph`; `ClassicCurveTests`
(astroid/cardioid closed forms, petal counts, exact open-pass Chaikin).

### Shape morphing

`ShapeMorph` (`Geometry/ShapeMorph.swift`) builds correspondence once and
reads `shape(at:)`; `Shape`/`Contour: Tweenable` lets `Timeline` sequence
geometry (those conveniences rebuild correspondence per read);
`morphed(toward:_:spacing:)` is the sugar. Contours pair closed with closed
and open with open (largest by area/length first, then nearest centroid);
both sides densify by segment *insertion* so corners survive; spacing derives
per outline (1/128 of its own length, capped near 4096 points); closed rings
then take the min-travel cyclic rotation and open runs a direction flip. An
orientation mismatch reverses *all* target contours: a global flip preserves
both fill rules, per-pair flips do not. Spacing per outline, not per pair,
was a real fixed bug (a shared spacing bunches the equalizer's insertions and
warps the blend). Unmatched contours lerp to their own centroid (uniform
scale-away, so holes grow in and out without popping). `shape(at:)` returns
the originals verbatim at 0 and 1; the winding rule switches at t = 0.5; no
rng anywhere (`ShapeMorphTests`). Example `Motion/Morphing` (star to blob to
donut cycle, declares `loopDuration`); snapshot `shape-morph`.

### Scattering, sampling, and stippling

Voronoi & Delaunay (`Tessellation.swift`): Bowyer-Watson with a
Sutherland-Hodgman clip to `bounds` for seamless cells, plus `relaxed()`
Lloyd; sugar `voronoi` / `delaunay` / `drawVoronoi` / `drawDelaunay` /
`lloyd`. Blue noise (`Geometry/PoissonDisk.swift`): Bridson's algorithm,
`poissonDisk(in:radius:candidates:maxCount:)`, as a public generic free
function over any `RandomNumberGenerator` (`SplitMix64` is public) plus
seeded `Sketch` sugar; the even-but-organic scatter and the seed set the
tessellators and packing consume. Example `Patterns/BlueNoise`; snapshot
`blue-noise`.

Low-discrepancy sampling (`Geometry/Sampling.swift`): `halton(_:base:)` (the
radical inverse) plus `haltonPoints(count:in:bases:startIndex:)` /
`sobolPoints(count:in:startIndex:)` give even coverage as an ordered stream:
any prefix is itself even, and growing the count never moves a placed point,
the draft-then-refine property neither `random` nor `poissonDisk` has. They
are pure functions of the index (no rng, no seed, never touching the sketch's
`rng`); `startIndex` defaults to 1 because index 0 of both sequences is the
corner point; Halton bases must stay coprime (default (2, 3)); Sobol is
Gray-code stepped with dim-2 direction numbers from the degree-1 recurrence
`m_k = 2m_{k−1} ⊕ m_{k−1}`. `SamplingTests` pins the canonical first points
of both. Example `Patterns/LowDiscrepancy`; snapshot `low-discrepancy`.

Stippling (`Geometry/Stipple.swift`) is Secord's weighted Voronoi:
`stipple(_ image:count:in:iterations:)` plus a density-closure form. Density
rasterizes once to a working grid (~256 px per dot, capped); seeding is
rejection-sampled; weighted-Lloyd passes then assign every ink-bearing pixel
to its exact nearest dot over a site-bucket grid. The expanding-ring nearest
search may stop before ring r only once the best find is at most
(r−1)·bucketSide; the r·bucketSide bound shipped first and was a real bug,
locking dots onto the bucket lattice (rectilinear runs at bucket scale).
Image density is (1 − linear `luminance`) · alpha, so transparency carries no
ink (the same rule the dither pass uses); zero ink anywhere returns an empty
array, never a uniform scatter. Deterministic given (input, count, seed);
setup-time work, hold the points. Example `Patterns/Stippling` (paints its
sphere in `setup()`, no asset); snapshot `stipple`; `StippleTests`.

### Spanning-tree line art and isolines

`spanningTree(through:)` (`Geometry/SpanningTree.swift`) is the branching
sibling of the `singleLine` tour: the exact Euclidean minimum spanning tree,
built by Kruskal over the unique edges of the `Delaunay` triangulation
(which always contains the EMST), ties broken by (distance², index) so the
build is deterministic. Degenerate inputs take two fallbacks: fully
collinear points have no triangulation, so the tree is the lexicographic
chain (exactly the MST along a line); exactly-coincident duplicates never
enter the triangulation, so leftover components join by nearest-vertex
passes. The output is the minimal trail decomposition, one open `Contour`
per pair of odd-degree vertices: a walk may start only at a vertex whose
*unconsumed* degree is odd (each walk flips its two endpoints odd-to-even
and no vertex ever flips back, so an index-order sweep is minimal;
starting at *originally*-odd vertices strands edges into extra chains, a
real first-build bug caught by `decompositionIsMinimal`). The image sugar
`spanningTree(of:points:in:iterations:cutoff:)` mirrors
`singleLine(of:...)` over the same stipple + cutoff pipeline. Example
`Images/SpanningTree`; snapshot `spanning-tree`; `SpanningTreeTests`
(brute-force Prim match, minimality, degenerate inputs).

`isolines(at:in:resolution:field:)` (`Geometry/Isolines.swift`) is marching
squares over an on-demand sampling grid (`resolution` cells across the
longer side, square-ish cells). The case table emits *oriented* segments
(inside on a fixed side), so stitching walks directionally: forward along
to→from key matches until the chain closes or runs out, then backward from
the start, which is what lets a contour that exits the bounds come back as
an open `Contour` ending on the edge. Saddle cells (codes 5/10) are settled
by the cell-average rule. Two invariants: a contour passing exactly through
a grid corner (corner value exactly zero) makes its cell emit a null
segment, dropped before stitching (the real bug was two-point litter beside
an intact ring, seen with a radius-100 circle whose lattice hits are exact);
and the endpoint maps are only ever indexed, never iterated, so the walk
order is the segment order and the trace is deterministic. The levels form
samples the grid once and traces per level; the image form reduces pixels
to linear-luminance-on-white (transparency reads as paper), samples
bilinearly, and takes its levels in sRGB tone (converted once), matching
the stipple/`cutoff` convention. Examples `Patterns/ContourMap` (looping
fbm terrain, index contours); snapshot `isolines` (metaball merge/split +
image tone lines); `IsolineTests`.

### Hulls and the medial axis

`Geometry/ConcaveHull.swift` holds the two tighter scatter outlines, both
carved from the shared Bowyer-Watson `Delaunay`. `concaveHull(of:concavity:)`
is the characteristic shape (chi-shape) of Duckham, Kulik, Worboys, and
Galton: the starting boundary is the triangulation's outer edge, and border
triangles erode longest-boundary-edge-first through a max-heap, each pop
allowed only while the edge exceeds a length threshold and the triangle's
opposite vertex is not already on the boundary. That single stop rule is
what keeps the polygon simple and every input point inside, and it makes
each edge a one-shot decision (boundary vertices never leave the boundary,
so a blocked edge stays blocked). The public knob inverts the JTS-style
edge-length ratio into `concavity` 0...1, interpolating the threshold
between the triangulation's longest and shortest edge, so it reads
scale-free.

One repair proved load-bearing: the shared `Delaunay` builds against a
finite super-triangle (20x the input span), and a nearly collinear hull
triple has a circumcircle that reaches that scale, so the sliver triangle
can drop out of the mesh and leave the boundary with a shallow notch (a
real case: a point 0.35 units inside a hull edge on a 400-unit scatter,
found the day the suite pinned "concavity 0 equals `convexHull`"). Rather
than touch the substrate (whose exact output existing snapshots pin),
`capHullNotches` compares the mesh boundary against `convexHull(of:)`,
walks each notch path, and caps it with a fan of sliver triangles before
erosion starts. Zero concavity then reproduces the convex hull exactly,
and a cap erodes away like any border triangle the moment the knob turns,
so higher concavities are untouched. `HullTests` keeps the seed-7 scatter
that first exposed the notch as the regression.

`alphaShape(of:alpha:)` is Edelsbrunner's alpha complex in its standard
form: keep the triangles whose circumradius is at most `alpha`, orient
them counterclockwise, and link the edges owned by exactly one kept
triangle into loops (at a pinch vertex the walk takes the clockwise-most
departure relative to the reversed arrival, which keeps each loop on its
own face). Union-find over shared edges groups kept triangles into
islands; each island's loops sort largest-area-first, so a `Shape` comes
back outer contour first with its holes after.

`Geometry/MedialAxis.swift` approximates Blum's medial axis as the Voronoi
subcomplex of a boundary sampling (Brandt-Algazi): every contour resamples
at `spacing`, the samples triangulate, and the Voronoi edge between two
adjacent triangles survives when its dual Delaunay edge joins samples that
are not neighbors along their ring and both circumcenters pass the new
winding-honoring `Shape.contains(_:)` (tested against the resampled
domain, so the test and the triangulation agree). Each skeleton vertex is
a circumcenter whose circumradius is exactly its clearance, which is what
makes the carried radii honest inscribed-disk radii. The graph decomposes
into branches between degree-not-2 vertices plus leftover pure rings (a
hole's skeleton), and `prune` trims terminal twigs shorter than the knob.
Pruning collects each round's twigs against the round-start graph and only
then removes them together: the first cut removes a twig, drops its
junction to degree 2, and a same-round sibling walk would run straight
past the vanished junction down the trunk (a real bug, caught by the
rectangle's roof-ridge test). A twig that is its own component never
prunes, so small regions keep their skeletons.

All three functions canonicalize their output by geometry rather than
construction order, because the substrate's triangle *order* is
process-varying (the Bowyer-Watson refan iterates a Dictionary) even
though the triangle *set* is stable: hull loops rotate to their
lexicographically smallest vertex, alpha islands sort by their outer
points, and skeleton branches orient and sort by their endpoints. Examples
`Shapes/Hulls` (the three-outline scatter) and `Shapes/MedialAxis`
(letterform skeletons with rolling inscribed disks); snapshots
`concave-hull` / `medial-axis`; `HullTests` / `MedialAxisTests`.

### The straight skeleton

`Geometry/StraightSkeleton.swift` computes the mitered-offset sibling of
the medial axis exactly (no boundary sampling): the shrinking-wavefront
simulation over circular lists of active wavefront vertices (one per ring,
holes included), an event heap ordered by inset distance, and one supporting
line per boundary edge that never changes while its wavefront segment
slides along it. Naive event-at-a-time processing is famously wrong on
real inputs, where right angles and symmetry land several events on one
point at one time, so the queue drains in *levels*: every event within
tolerance of the lowest distance loads at once, the level clusters events
that share a meeting point or a parent vertex, and each cluster processes
as one generalized event over *chains* (runs of consecutive collapsing
edges, split vertices, and the opposite edges splits land on, sorted by
angle around the meeting point; one new wavefront vertex is born into each
gap between consecutive chains). A split's opposite edge resolves against
the live wavefront at processing time (projecting the meeting point onto
the edge picks the right segment when earlier splits already divided it),
splits cut one LAV in two, cross-LAV splits merge a hole's wavefront into
the outer one, and a chain of collapsing edges inside a multi-split
retires all its vertices like a lone edge event would (the mixed-chain
case the studied reference leaves unhandled). Events computed during a
level that land back on it are stale echoes and are purged, which is also
why a LAV down to two vertices closes as a *bridge* (the ridge arc between
where its pair stopped) rather than through an event: the pair's mutual
event always lands on the current level.

Two hardening rules earned their place. First, degenerate multi-splits can
leave a *ghost corner*: two wavefront vertices at one point flanking a
zero-length front, whose mutual event lands on the current level forever
(purged each time), starving the LAV; a level-end pass fuses each such
pair into the single vertex it should have been (a real bug, caught by a
nine-lobed 400-vertex blob whose partition came back 8% short, pinned by
`facesPartitionSpikyBlobs`). Second, output assembly does not use the
reference implementations' face-queue pointer surgery at all: every event
creates one shared *node* (point + distance), each wavefront vertex
records its origin and death node, and a face reassembles at the end from
its edge plus the origin-to-death arcs of every vertex that carried one of
the edge's endpoint roles, stitched by node identity. Node sharing is what
makes arcs dedupe exactly across neighboring faces, and it gives the whole
system its test net: the faces must partition the shape, so their areas
sum to its area (held to 1e-7 relative by the fuzz tests).

`inset(by:)` leans on faces being roof planes: within a face, inset
distance is an affine function (distance to the edge's line), so the inset
at `d` is a straight chord through each face crossing level `d`, paired
even-odd along the edge direction. A chord endpoint lies on a face-boundary
arc shared with a neighbor face, and because inset distance restricted to
that shared segment is the same affine function from both sides, chords
stitch into rings by *arc identity* (canonical node-pair keys), no epsilon
matching. Rings start at their lexicographically smallest chord, outer
rings come out positive, holes negative, and `distance <= 0` returns the
normalized input rings. Determinism holds the house rule throughout: the
SLAV is an array in creation order, sets are membership-only, level lists
sort by (distance, point, sequence), and chain sorting tie-breaks by edge
id. Example `Shapes/StraightSkeleton` (the island contour ladder);
snapshot `straight-skeleton`; `StraightSkeletonTests` (closed-form squares,
ridges, spokes, hand-mitered L and plus insets, the notch pinch, hole
merges, the symmetric square ring whose wavefronts annihilate along whole
segments, and the partition fuzz).

### Painterly marks: marbling and watercolor

`Geometry/Marbling.swift` is mathematical paper marbling in Jaffer's
closed-form model (the Lu-Jaffer-Jin-Zhao-Mao formulation): a `Marbling`
bath is an ordered stack of `MarbledInk`s (a fillable `Shape` plus a
color; a value type, so a copied bath forks its history), and every
operation is one exact point transform run over every outline. `drop`
displaces each point at distance `d` from the center to `√(d² + r²)`
(the area-preserving displacement; the `d → 0` limit lands on the new
rim, direction picked deterministically) and then appends the new disk,
polygonized at the bath's `spacing`. The stylus family shares one falloff
law, displacement `strength · 2^(−d/falloff)` parallel to the tool's
motion: the straight tine takes `d` from the line, the comb from the
nearest tooth (`offset − round(offset/teeth)·teeth`), and the two
rotational tools (circular tine, `swirl`) convert the same decayed length
into an arc about the center, which is why both preserve each point's
radius exactly. The exponential form is Jaffer's `z·uᵈ` with the base
reparameterized so `falloff` reads as a half-distance in canvas units.

Refinement is what keeps stretched outlines smooth, and its direction
matters: segments subdivide at **pre-transform** midpoints while the
*transformed* span exceeds `spacing` (depth-capped, with a source-length
floor so a drop centered on an outline can't recurse forever), so every
inserted point lies exactly on the transformed curve; refining after the
fact could never recover a fold. Since the transforms are homeomorphisms
the outlines never self-cross, `add(_:color:)` floats arbitrary
shapes (holes intact, so glyph counters survive), and the whole bath is
rng-free and deterministic. Cost note: points accumulate per operation,
so a bath is setup-shaped work redrawn from the held value.

`Geometry/Watercolor.swift` is the generative-watercolor recipe (the
Hobbs formulation): recursive midpoint subdivision where each edge splits
at its midpoint, the midpoint jumps by an isotropic Gaussian scaled by
that edge's own variance, children inherit `0.4...0.8` of it, and the
starting edges draw jittered (`0.2...1.8`) shares of the base variance,
which is what gives one blob crisp stretches beside blooming ones. The
`Watercolor` value is the *base*: an irregular polygon pushed through the
shared rounds once, held immutable, with every `layer` deforming a copy a
few rounds further so all layers agree at the core and differ at the
fringe. Two decisions proved load-bearing: layers must fill through
`layerShape` / the `drawShape` route with **non-zero winding**, because
the deformed outline self-crosses and even-odd cuts white pinholes while
a triangle-fan `drawPolygon` fill shatters the concave outline into
radial spokes (both real first-render bugs); and the `detail` floor
(edges below it stop subdividing) bounds a layer's point count no matter
the round count, which took the first full-sheet render from ~40 s to
seconds with no visible change (sub-pixel splits are invisible). The
Gaussian is a stateless Box-Muller over the generic rng so the draw count
per call is fixed and a seed reproduces exactly. The `drawWatercolor`
sugar dilutes the current solid fill color to the per-layer opacity and
stacks layers via the sketch's own rng; painting is deliberately
setup-shaped (every layer is a full concave fill).

Examples `Patterns/Marbling` (bull's-eyes, nonpareil combs, a vortex;
click drops, drag pulls a stylus) and `Shapes/Watercolor` (three
interleaved pigment pools glazing where they overlap, a clipped speckle
for granulating texture, `noLoop`); snapshots `marbling` / `watercolor`;
`MarblingTests` (exact-displacement, falloff, radius-preservation, and
refinement-bound checks) / `WatercolorTests`. Docs
`Docs/Generators/Marbling.md` / `Watercolor.md`; technique credits in
`ATTRIBUTION.md` (Jaffer / Lu et al.; Hobbs).

### Random walks

`Geometry/Walks.swift`. `randomWalk(from:steps:stepLength:)` is isotropic.
`levyFlight(from:steps:minStep:maxStep:exponent:)` draws truncated power-law
step lengths via inverse CDF, with the log-uniform special case at μ = 1;
`minStep` must be > 0 because the power law diverges at zero.
`selfAvoidingWalk(in:cellSize:from:maxLength:)` is a lattice DFS with
backtracking: visited-forever marks make the search finite and the path
self-avoiding, and the best path reconstructs through parent links, valid
precisely because a visited cell's parent never changes; the lattice centers
in bounds like the tiling grids. All return `[Vector2]`, seeded and
deterministic (`WalkTests`); fit a flight by scaling its points (the
catalog-wide rule above). Examples `Patterns/LevyFlight` +
`Patterns/SelfAvoidingWalk` (both declare `loopDuration`); snapshots
`levy-flight` + `self-avoiding-walk`.

### Truchet, tiling, and layout

Truchet (`Geometry/Truchet.swift`): one tile per `Grid` cell at a
seed-chosen orientation, open `[Contour]` line-work; `Truchet.Tile` is
`.arcs` (after Smith) or `.diagonals` (the maze look). Arcs are centered on
cell *corners* through the two adjacent edge midpoints, so abutting cells
join regardless of flip; they go elliptical for non-square cells. Example
`Patterns/Truchet`; snapshot `truchet`.

`HexGrid`/`TriangleGrid` are `Grid` siblings whose blocks keep true aspect:
sized to the tighter fit and centered in the padded bounds, so more columns
means smaller cells, never stretch. Hex cells carry offset `column`/`row`
*and* axial `q`/`r` (odd-r/odd-q storage, math in axial:
`distance`/`neighbors`/`ring`); `cell(at:)` picks exactly via cube rounding
(round all three cube coordinates, recompute the worst offender; rounding
the axial pair independently drifts off-lattice near cell edges). Hex
`gutter` insets the corner radius by g/√3; triangle gutter shrinks vertices
toward the incenter; triangle parity: up iff `column + row` is even,
neighbors left/right/across. `Subdivision.cells`/`subdivide` split `.binary`
(cut across the longer side, fraction clamped so both halves keep `minSize`)
or `.quad`; the root always splits when it can, `chance` applies from depth
1; leaves carry `depth`. `Maze` has three carvers (`.backtracker`,
`.kruskal`, `.wilson`), all perfect mazes (n−1 passages, pinned by
`TilingTests`). Wilson's loop-erasure is implemented as the
last-exit-direction map: overwriting a revisited cell's exit *is* the
erasure, and the path replays from the walk start. `walls(in:)` merges
collinear segments into single runs (plotter-clean); `longestPath()` is the
double-BFS tree diameter. Determinism: fixed iteration orders and candidate
arrays only, no Set/Dictionary walks. `apollonianGasket` applies the
Descartes circle theorem with every child as the quadratic's *other root*
given its parent triple (Vieta), so the whole recursion is linear: no
complex square root, no tangency-validation epsilon; seeds are the closed
form (2√3−3)·R; BFS order doubles as generation age for tinting. Examples
`Patterns/HexGrid` / `TriangleGrid` / `Subdivision` / `Maze` / `Apollonian`;
snapshots `tiling-grids` / `subdivision` / `maze` / `apollonian`;
`TilingTests`.

### Aperiodic tilings

Penrose (`Geometry/Penrose.swift`): both tilings live as Robinson
half-triangles (a `Half` is an acute/obtuse flag plus apex, axis, and free
corners), deflated from a ten-half wheel at the chosen center and merged
into whole tiles at the end: P2 halves pair across the apex-to-axis leg,
P3 halves across the axis-to-free base, matched through a quantized edge
key. Halves on the wheel's outer rim have no partner and are dropped, which
is why the wheel over-covers the bounds by a few tile widths. The P3
subdivision is the standard published one; the P2 rules were derived from
the merge structure, and the derivation's load-bearing part is not the
split points (golden sections of the legs) but each child's *ordering*:
which corner is the axis corner decides how the next generation subdivides,
a wrong choice only shows up as T-junctions one level later, and the
crack-free test is what pins all six assignments.

The arcs are corner-centered circles whose radius is a fraction of the two
adjacent edges (equal in length at every chosen corner). P2's fractions
fall straight out of the continuity constraints (kite nose 1/phi^2, kite
144-corner 1/phi, dart both 1/phi^2). P3 hides a real subtlety: a rhomb's
outline is only canonical up to its 2-fold rotation, and under any
C2-symmetric arc placement the thick-thin meeting classes demand f = t and
f = 1 - t at once, so midpoint crossings are the *only* solution family.
The classic golden decoration needs each rhomb oriented beyond C2, and the
merge already holds the datum: the two halves are mirror twins, so exactly
one is positively wound, and leading the outline with that half's apex
orients every rhomb intrinsically. A brute-force continuity solve over
golden candidates (run at development time on a deflated patch) then
yields a small family of exact solutions; the shipped constants are thick
arcs at the apex pair at 1/phi^2 and thin arcs at the side pair at
(1/phi^2, 1/phi), and the continuity test re-verifies them on every run.

Wang tiles (`Geometry/WangTiles.swift`): the stochastic scanline of Cohen,
Shade, Hiller, and Deussen. Each cell picks weight-proportionally among the
tiles matching its west neighbor's right edge and north neighbor's bottom
edge; `WangTiling.completeSet(colors:)` is the full colors^4 product set,
which always has a candidate, while hand-built sets that dead-end get fresh
attempts and then return nil (the WFC-style contract).

Girih (`Geometry/Girih.swift`): Kaplan's inference algorithm from the
polygons-in-contact paper. Two rays leave each edge midpoint at the contact
angle, leaning into the polygon (interior side from the signed area);
every crossing pair is costed by the summed origin-to-crossing distances
(collinear facing pairs by their origin distance), sorted with a
(cost, i, j) tie-break, and taken greedily, each ray used once; unmatched
rays drop, which is the paper's behavior on awkward shapes. The five girih
tiles are turtle walks over exterior-angle tables with unit steps, and
`points(onEdge:_:)` re-runs the walk along a caller's segment, which is
the exact composition primitive: the decagon-and-ten-pentagons flower in
the example is each pentagon laid on a reversed decagon edge.

Spectre (`Geometry/Spectre.swift`): the substitution system of the chiral
aperiodic monotile paper. Tile(1,1) is a 14-step turtle on the 30-degree
grid (the direction table in `edgeDirections`; quad anchors at vertices
3, 5, 7, 11). Nine metatiles substitute through eight slot transforms per
generation, built by chaining anchor matches through the rotation schedule
(60, 0, 60, 60, 0, 60, -120) and then mirroring the entire generation:
layout handedness alternates per level, every leaf path picks up exactly
one mirror per level, so all tiles at a given depth share one handedness
(the cyclic turn-sequence test pins it). Gamma is the mystic, carrying a
second spectre translated to vertex 8 and rotated +30 degrees, surfaced as
`isOdd`. The child tables and slot data are the paper's, cross-checked
against the authors' reference app; the implementation (value types, the
level walk, exactness tests) is Ollin's own. Sizing grows levels until the
patch covers the bounds in tile units, then scales, recenters, and clips
per-tile. The curved outline replaces every edge with the same flattened
cubic bump, alternating sides edge to edge; 14 being even keeps the
alternation cyclically consistent, and abutting tiles nest because odd
edges always meet even edges in a spectre tiling, which is exactly the
paper's chirality-forcing edge modification.

`AperiodicTilingTests` covers all four: the crack-free scan (every edge
shared at most twice, no corner strictly inside another edge), P2/P3 edge
ratios and kind presence, the thick:thin ratio near phi, arc-endpoint
pairing across interior edges, Wang constraint satisfaction and seed
determinism, girih motif completeness and n-fold symmetry on regular
polygons plus cross-tile joining, and the spectre's unit edges, congruent
single-handedness, odd-tile sparsity, and determinism. Examples
`Patterns/Penrose` / `WangTiles` / `Girih` / `Spectre`; snapshots
`penrose` / `wang-tiles` / `girih` / `spectre`;
`Docs/Drawing/AperiodicTilings.md`.

### Packing

`Geometry/Packing.swift`. `packCircles(in:count:minRadius:maxRadius:padding:)`
is grow-to-touch greedy gap-filling, big-first. `packCircles(around:)` grows
each point's circle to half its nearest-neighbor distance, a closed form
with no iteration or rng. `relaxCircles(_:iterations:)` parts a coincident
pair on a fixed axis to stay reproducible. All seeded and deterministic,
output `[Circle]`. Shape packing is geometry-aware: it fits against each
shape's actual outline, not bounding circles, so small shapes nestle into
notches and concave gaps (built to fix the visible space around triangles
and stars). The engine is the stateful `ContinuousPacking` class:
grid-accelerated incremental `step()` with even-odd ray-cast rejection and
grow-to-nearest-outline, broad-phased by a bounding-circle prune over a
spatial hash; an empty shape bag packs plain circles on a fast path.
`packShapes(_:in:count:…)` runs it to completion; `packShapes(_:around:…)`
scatters one shape per point. An unbounded `maxRadius` clamps the grid cell
*and* the search reach to the region size, else the reach is infinite. The
example rides `noClear()` accumulation and draws only newly added shapes,
keeping per-frame cost flat as the field fills. `PackingTests`; examples
`Patterns/CirclePacking` + `Patterns/ShapePacking`; snapshots
`circle-packing` + `shape-packing`.

### Growth systems

L-systems (`Geometry/LSystem.swift`): axiom + rules (or stochastic
`choices`) rewrite to a string a turtle walks into open `[Contour]`
line-work; 13 presets verified against Wikipedia and Paul Bourke; seeded
`Sketch` sugar fits the form to the canvas and drives `&rng` so stochastic
presets vary by `seed`. A 2M-symbol expansion cap stops expansion and keeps
the last string under it. The turtle flushes one `Contour` per unbroken run,
so a branch shares its branch point with the trunk and no segment draws
twice. Example `Patterns/LSystem`; snapshot `l-system`.

Differential growth (`Geometry/DifferentialGrowth.swift`): a stateful
`final class` you hold and `step()`; attraction/alignment/repulsion over a
uniform spatial hash, long edges split at midpoints, `jitter` breaks a
symmetric ring so it buckles; `ring(...)` / `line(...)` seed factories.
CPU-only and deterministic given the seed (bucket lookups and summation are
order-stable), so it grows over frames yet a fixed-`frame` snapshot
reproduces. Example `Patterns/DifferentialGrowth`; snapshot
`differential-growth` (`frame: 130`).

Space colonization (`Geometry/SpaceColonization.swift`): branching growth
toward attraction points; each attractor pulls its single closest node
within `influenceRadius`; attractors within `killRadius` are consumed (keep
`killRadius` > `stepLength`). No rng: deterministic given input, with
Dictionary iteration sorted by node index, oscillation guards, and a stall
counter so unreachable attractors terminate (`isFinished`). Pipe-model
`thicknesses(leafWidth:exponent:)`; pairs with `poissonDisk`. Example
`Patterns/Venation`; snapshot `space-colonization` (`frame: 140`).

Diffusion-limited aggregation
(`Geometry/DiffusionLimitedAggregation.swift`): off-lattice seeded walkers
freeze at first touch; long strides while far, kill-radius respawn,
`stickiness` < 1 packs denser, optional `bounds` cage. Particles are
parent-linked and arrival order equals index, so tint-by-age is free.
Example `Patterns/Dendrite`; snapshot `dla` (`frame: 110`). `GrowthTests`
pins both growth systems.

### Wave Function Collapse

`Geometry/WaveFunctionCollapse.swift` is the simple-tiled model (Gumin):
`WFCTile` edge sockets + weights, min-entropy observe, weight-biased
collapse, propagate, restart-on-contradiction. Every rng decision runs over
a sorted candidate list with a fixed cell-iteration order (the catalog-wide
determinism rule originated here); anything else makes the seeded solve
irreproducible and the snapshot flaky. Sugar `wfc(...)` +
`drawWFC(_:in:padding:gutter:tile:)`; draw from `tiles[i].sockets` so one
draw block covers a tile and all its rotations. Example
`Patterns/WaveFunctionCollapse`; snapshot `wave-function-collapse`.

### Cellular automata and turmites

`Geometry/CellularAutomata.swift` + `Geometry/Turmite.swift`.
`elementaryCA(rule:width:generations:from:wrap:)` covers the 256 rule-byte
automata; `totalisticCA(code:colors:width:generations:from:wrap:)` is the
base-k digit table over the neighborhood sum; both are pure functions
returning stacked generation rows, with `startDensity` Sketch sugar rolling
the start row on the seeded `random`. The Sketch facade mirrors the full
free-function signatures because any bare-named Sketch member blocks
unqualified global calls inside sketches (the shadowing rule). `Turmite` is
the stateful walker class (the `DifferentialGrowth` shape): `[state][color]`
`Rule(write:turn:state:)` tables over a wrapped grid, turn quarters from the
published 1/2/4/8 codes, multi-ant in array order, no rng anywhere; the
`Preset` catalog (`.langton`/`.spiral`/`.highway`/`.chaos`/`.frame`/
`.fibonacci`) decodes the published turmite catalog and conforms to
`ParamOption` for free menu knobs. `CellularAutomataTests` pins rule
30/90/110 known rows, the totalistic 777 opening, wrap semantics, and
Langton's flip-parity plus the exact 104-step highway period. Examples
`Patterns/ElementaryCA` + `Patterns/Turmites`; snapshots
`cellular-automata` + `turmites`. `Docs/Generators/CellularAutomata.md`.

### Flow fields, boids, and steering

`FlowField` (`Geometry/FlowField.swift`) is a value type around an
`angle: (Vector2) -> Double` closure. `streamline(from:)` traces both
directions through a seed; `streamlines(from:separation:)` traces evenly
spaced non-crossing lines (Jobard-Lefer): a batch commits its own points to
the occupancy grid only *after* tracing, so a line never blocks itself.
`advected(_:)` steps points along the field. The seeded sugar
`flowField(scale:turns:z:)` / `curlField(scale:z:)` captures the sketch's
seeded noise, so the field is transient: trace streamlines once and hold
those, don't store the field (it retains `self`); `z` is the noise slice.
Example `Patterns/Streamlines` (distinct from the older `Motion/FlowField`
field-arrow viz); snapshot `streamlines`.

`Boids` (`Geometry/Boids.swift`) is Reynolds' separation/alignment/cohesion
over spatial-hash neighbors, with edge avoidance within `margin` (no wrap,
so no toroidal-seam artifact) and an optional `field: FlowField?` join. The
grid buckets fill in boid-index order and the 3×3 cell scan is fixed-order,
so force sums are order-stable and a seeded flock at a fixed frame
reproduces. `drawBoids(_:size:)` sugar. Example `Patterns/Flocking`;
snapshot `flocking` (`frame: 120`). `Vehicle` (`Geometry/Steering.swift`)
is the single-creature side: composable forces (`seek`/`flee`/`arrive`/
`pursue`/`evade`/`wander`/`follow(field)`/`follow(path:)`/`separate`/
`contain`) over the public `steer(toward:)`; behaviors return forces you
weight and sum, `step()` integrates. Only `wander` rolls the rng, and it
rolls a *unit* then scales by jitter (the zero-width-range gotcha). Path
following seeks a point further along the arc length; `closed:` wraps
through the seam (`SteeringTests`). `drawVehicle(_:size:)` sugar. Example
`Motion/Steering`; snapshot `steering` (`frame: 150`).

### Force-directed graph layout

`ForceLayout` (`Geometry/ForceLayout.swift`) is the Fruchterman-Reingold
spring embedder, faithful to the 1991 pseudocode: repulsion `k²/d` between
all node pairs (accumulated once per pair, equal-and-opposite, in fixed
index order), attraction `d²/k` along edges (per-edge `weight` multiplies
the pull), each node's move capped at `temperature` and clamped to
`bounds`, the temperature cooling *linearly* to zero over `coolingSteps`
from `initialTemperature` (a tenth of the frame's larger side, the paper's
figure). `k` (`idealDistance`) defaults to `√(area/n)`. Two honest facts
worth keeping straight. First, `k` is a scale constant, not a promised edge
length: for a ring of n nodes the radial components of the crowd's
repulsion sum to exactly `(n−1)k²/2R` regardless of angle, giving the
equilibrium `R⁴ = (n−1)k³/16sin³(π/n)`, spacing well under `k`; the
measured settle sits on that equilibrium (6× longer cooling moves the mean
edge ~1.5%), so a fuller frame comes from raising `k` (FR's own `C`
multiplier), not from more iterations. Second, the freeze is real: at
`temperature` 0 `step()` early-returns, so a settled layout is free to
leave in `draw()`, and `reheat(_:)` (restore a fraction of
`initialTemperature`) is the one way anything moves again; it's the idiom
for growth (`addNode`/`connect`, then a small reheat) and for dragging
(pin the grabbed node, write its position, keep `reheat(0.15)` topped up
so neighbors follow). `gravity` (default 0, byte-identical off) is a
phantom edge from every node to the bounds center scaled by its value,
quadratic in distance, so small values (~0.01) center disconnected
components and big ones crush the web. Coincident nodes part along an
index-derived direction (deterministic tie-break). Everything is arrays in
index order: seeded `SplitMix64` placement, no Set/Dictionary walks, so a
run replays exactly (`sameSeedReplaysExactly`). Example
`Patterns/ForceGraph` (scale-free growth by degree-weighted stub picks,
drag-to-pull); snapshot `force-graph`; `ForceLayoutTests`.

### Strange attractors and chaotic maps

`Geometry/Attractors.swift`. `StrangeAttractor` integrates the 3D systems
(lorenz, rossler, aizawa, thomas, halvorsen, dadras, chen, fourWing) under
RK4; `ChaoticMap` iterates the 2D maps (clifford, deJong, henon). Both
carry a user-suppliable `@Sendable` closure and emit orbits via
`orbit(count:settle:)`; 3D rides `PointCloud` through the camera, 2D plots
as additive density. RK4 lives in `Math/Integration.swift` behind the
internal `Integrable` protocol, promoted from file-private when the double
pendulum became its second caller. Examples `3D/StrangeAttractor` +
`Patterns/CliffordAttractor`; snapshots `strange-attractor-3d` +
`clifford-attractor`.

`Geometry/Bifurcation.swift` adds the family's 1D member, `IteratedMap`:
where `ChaoticMap` is a fixed rule, this is a parameterized *family*
`x' = f(x, r)` (the closure takes `(x, r)`), because the bifurcation
diagram is a sweep over `r`. Factories logistic / sine / tent /
gauss(alpha:) carry an analytic `derivative` plus the canonical sweep
window (`parameterRange`) and vertical axis (`valueRange`); readings are
`orbit(at:)`, `graph(at:)` (the hump), `cobweb(at:steps:)` (the
graphical-iteration staircase, `2·steps + 1` points from `(x₀, floor)`),
`bifurcation(over:columns:perColumn:settle:)` as `(r, x)` points (the
plotter-friendly form `drawBifurcation` maps into a rect), and
`bifurcationImage` (per-column orbit binned into pixel rows, tone =
`log1p(count)` normalized by one global peak factor, the fractal-flame
one-log-factor rule, ink on white). `lyapunovExponent(at:)` averages
`ln |f′|` along the orbit, using the analytic derivative when present and
a central difference otherwise, flooring `|f′|` at 1e-12 so a superstable
visit doesn't emit −∞; `BifurcationTests` pins it to the exact known
values (`ln r` for the tent map termwise, `ln 2` for logistic r = 4 via
the tent conjugacy) and pins the cascade itself (fixed point below 3, the
2-cycle's closed form at 3.2, period 4 at 3.5, period 3 inside the
1 + √8 window). Two numerical decisions are load-bearing: sweeps sample
**column centers**, never the range endpoints, because some families are
degenerate exactly there (the μ = 2 tent orbit collapses to 0 in binary
floating point, one doubled bit per step, ~50 steps and it's gone); and
the factory `start` values avoid the critical point 0.5, whose logistic
orbit dies in two steps at exactly r = 4 (0.5 → 1 → 0). The gauss family
genuinely holds two coexisting attractors over part of its window, so its
diagram depends on `start`; that's the map, not a bug. Everything is
rng-free and pure, so the diagram is render-once `setup()` work and the
example holds it in a retained `Batch`. Example `Patterns/Bifurcation`;
snapshot `bifurcation`; `BifurcationTests`.

### IK chains, the double pendulum, and N-body

`Geometry/IKChain.swift` / `DoublePendulum.swift` / `NBody.swift`: three
stepped CPU motion systems, deterministic throughout (no rng; `NBody`
factories seeded). `IKChain` warm-starts per call. `reach(toward:)` is
fixed-base: `.fabrik` (default; even, smooth) or `.ccd` (the whippy
tip-heavy alternative, with `maxTurn` damping). `drag(to:)` is the
free-base single tip-to-base pass (the classic tentacle); `moveBase(to:)`
re-roots. `maxBend` is enforced per joint *inside* both FABRIK passes:
clamp against the pass-side neighbor, then re-place at exact segment
length; post-clamping would break the rigid lengths. An out-of-reach target
stretches the chain straight before the iterate loop. Keep the stall exit:
constraints can make in-range targets unattainable, and `reach` returns
false rather than spinning.

`DoublePendulum` is the standard point-mass Lagrangian EOM over the shared
RK4; `step(dt:)` splits into fixed substeps of at most 1/480 s, so default
stepping is a pure function of the start (energy drift pinned by
`DoublePendulumTests`); passing live `deltaTime` trades reproducibility for
wall-clock pacing. `bob1`/`bob2` are pivot-relative, y-down.

`NBody` is a Barnes-Hut quadtree (index-order insertion, incremental
mass/COM, s/d < θ opening) with Plummer softening and KDK leapfrog;
accelerations cache across steps and recompute on a body-count change.
Coincident bodies chain at the depth cap, else subdivision recurses
forever. The force walk runs on unsafe buffers on purpose (~2× debug frame
rate, measured). θ = 0 must stay the exact all-pairs sum, and vanilla
monopole BH at θ = 0.7 runs a few percent of field scale; `NBodyTests` pins
brute-force equality at θ = 0 plus the roughly quadratic error shrink as θ
tightens, so don't "tighten" that bound. Seeded factories: `disk` (circular
orbits from enclosed mass; `velocity:` drift stages collisions) and
`cluster`. Examples `Motion/InverseKinematics` / `DoublePendulum` /
`NBody`; snapshots `ik-chain` / `double-pendulum` / `n-body`;
`IKChainTests` / `DoublePendulumTests` / `NBodyTests`.
`Docs/Simulation/Motion.md`.

---

## Color: palettes, dithering, and print separations

`Color` itself (the CSS Color 4 named set, `Color(hex:)`, HSB with wrapping
hue, the gamut-mapped OKLab family written from Ottosson,
`Color.mix(_:_:t:in:)` over `ColorSpace`, blackbody `Color(kelvin:)`,
`Ramp` / `Palette` / `CosinePalette` / `Colormap`) is enumerated in
`Docs/Drawing/Color.md`. This section records the mechanism in the color
*pipelines* under `Sources/Ollin/Color/`: palette import and extraction,
image dithering, and print separations. All are CPU-side, setup-time, and
deterministic, so they are snapshot- and recipe-safe.

### Palette import

`Color/PaletteImport.swift`: `loadPalette` / `loadPalettes` (plus
`Palette(contentsOf:)` / `palettes(data:format:)` / `resource:in:`) over the
`PaletteFormat` set: hex-per-line, CSV, TSV, JSON (array-of-arrays, flat
array, or `{"colors":[…]}`), and ASE (Adobe Swatch Exchange, written from
the community spec; swatch groups become palettes in document order, loose
colors flush in place; RGB/Gray/CMYK/LAB, the last via CIELAB on D50, where
LAB lightness arrives 0…1, not 0…100). The three text formats share one
parser (they differ only in separator), so `.auto` decides palette-per-line
by the *file's* shape: every line yielding exactly one color means one
palette, not a stack of one-color palettes. An explicit format must override
that sniff; the parameter is `palettePerLine: Bool?` with nil meaning
"decide", and a plain `Bool` here was a real bug. A line parsing to zero
colors is skipped (CSV headers fall away), and no comment syntax is
promised: `#deface` is a color. Every loader returns `[]`/`nil` on malformed
bytes, never traps (bounds-checked `ByteReader`; the ASE block length is
authoritative, so an unknown block can't desync the stream). Ship the
loader, not the data (the `.fnt` rule): bundled palette *data* stays
license-gated. Example `Color/PaletteFile`; `PaletteImportTests`.

### Palette extraction

`Color/PaletteExtract.swift`: `Palette(extractedFrom:count:seed:)` /
`extractPalette(from:)` run weighted k-means++ then Lloyd over OKLab (sRGB
distance splits greens and merges blues). Input is grid-sampled to at most
16k pixels; identical pixels merge and are sorted before clustering
(Dictionary order is per-process; determinism is a promise); emptied
clusters reseed to the worst-explained sample. Output is most-used first, so
`p[0]` is the dominant color. Fewer distinct colors than `count` returns
only what's there; a texture-backed `Image` has no CPU pixels and yields an
empty palette (`snapshot()` first); setup-time work, not per-frame. Example
`Color/PaletteFromImage`; `PaletteExtractTests`.

### Image dithering

`Color/Dither.swift`: the `Dither` enum + `Image.dithered(_:to:)` /
`(_:levels:)`. Eight error-diffusion kernels (Floyd-Steinberg,
Jarvis-Judice-Ninke, Stucki, Atkinson, Burkes, the three Sierras), ordered
Bayer (`.ordered(size:)`, powers of two 2…16, recurrence-built), and
`.blueNoise` (a 64² void-and-cluster tile after Ulichney, generated once
from a fixed seed and cached: ~15 ms release, ~2 s debug; generated, not
bundled, so no asset and no license). CPU-only by nature: error diffusion is
serial and can never be a fragment shader. The GPU `Filter.dither` /
`.ditherDuo` remain the cheap real-time *layer* effect, a different tool.

The load-bearing rule is three color spaces, one per family, and mixing them
up *is* the bug. Tone always accumulates in linear light (diffusing in sRGB
brightens gradients). `.none` picks the OKLab-nearest color: it carries no
error, so it is free to be perceptual, and the bands land evenly. Error
diffusion must pick the *linear*-nearest: choosing in a space it doesn't
accumulate in leaves a consistently-signed residual that draws a thin false
contour of the wrong color along the tone where the two rules disagree. That
contour is 1-2 px wide, so it hides from tile-averaged error statistics;
don't try to pin it that way. `DitherTests` pins the rule on a 1×1 image,
where no neighbor exists and the choice rule is directly observable.

Threshold maps (Bayer and blue noise) run the Yliluoma pair search: every
palette pair (and each color alone) is scored by the OKLab distance of the
mix it can actually reach, plus a variance-weighted noisiness penalty
(`0.005 · f(1−f) · pairDist²`; Yliluoma's flat 0.1 suits dense game palettes
but bands a sparse one: on plain black+white it hands the whole top of the
ramp to solid white). The fraction along the winning pair is taken in linear
light (deciding by OKLab distance instead puts a 25% gray at ~46% white
instead of 5%), the pair is oriented dark-to-light so neighbouring tones
share pattern phase, and plans are memoized per distinct color. The shipped
v1 anchored the search on the single nearest color, a real bug: gray on a
black/white/red palette dithered *pink*.

Details that earned their place: a fully transparent pixel diffuses no
residual (its black isn't light; it darkened cutout edges). Input walks the
premultiplied bytes through a 256-entry linear LUT (bit-identical to the
subscript path, ~2× release). Bayer thresholds are centered
(`(m+0.5)/n² − 0.5`) and added *before* quantizing, never compared against
raw (the naive `v > m/n²` form biases the image lighter). Serpentine
(default on) mirrors the kernel's `dx`. Void-and-cluster's phase-3 role
inversion collapses into phase 2: on the torus zeros-energy = G −
ones-energy, so the tightest cluster of zeros *is* the largest void (one
loop, provably). Alpha passes through; a texture-backed `Image` returns
unchanged (`snapshot()` first); an empty palette returns self. Example
`Color/Dithering`; snapshot `dither`; `DitherTests`.

### Print separations

`Color/Ink.swift` + `Color/PrintSeparation.swift` +
`Export/SeparationExport.swift`. `Image.separated(into:paper:)` splits a
frame into per-ink grayscale masters (byte = ink fraction, black = full ink)
under the translucent-spot-ink overprint model: each ink is a transmittance
filter (its color in linear light), coverage mixes in linear light, layers
multiply. The per-distinct-color coverage search (lattice seed, then
coordinate descent, memoized like the dither planner) is judged in OKLab:
the dither pass's two-space rule again. `preview()` reconstructs the
overprint *from the masters*, so screened masters preview their actual dots.
`dithered(_:)` reuses the `Dither` kernels over the coverage plane (coverage
*is* the linear quantity, no sRGB detour); `halftoned(pitch:angles:)` runs
rotated round-dot screens with an area-exact covered-area threshold (darkest
ink at 45°). Both drop coverage past the 2% minimum dot: the sub-1% residue
8-bit rounding leaves in "white" otherwise screens into stray specks (a real
fixed bug). `Ink` carries the 78-ink standard riso catalog (stencil.wiki
values, credited in `ATTRIBUTION.md`; the workflow references
p5.riso/Spectrolite are inspiration-only, since p5.riso's license is not
MIT-compatible). The sketch declares `printInks`, not `inks` (that name
collided with an example's own property). `--export-separations` writes one
PNG per ink plus `-preview.png`, each with registration targets and a label
in a white band *around* the untouched artwork, drawn in full ink on every
layer so the crosses stack into register; recipes carry the ink list
(`ExportMetadata.inks`). GPU-backed image yields an empty separation; the
model limits by physics (inks only darken; no white ink on dark stock).
Example `Color/PrintSeparation` (the canvas *is* the poster; a `@Param` view
knob flips artwork/masters/preview so exports separate the artwork, not a
demo layout); snapshot `print-separation`; `PrintSeparationTests`.
`Docs/Output/PrintSeparations.md`.

---

## Live reload and the live-coding hosts

`swift run OllinLive <path/to/Sketch.swift>` opens a window, watches the file,
and on save recompiles just that sketch into a `.dylib` and hot-swaps it into
the running loop; the window never closes. The rules live in CLAUDE.md's
*Live reload* section; this is the machinery.

### The host and the swappable dylib

OllinLive is a SwiftUI `App`: its `WindowGroup` hosts a `SketchView`, which
hands back the `SketchRunner` through its `onRunner` callback; the file
watcher then drives `SketchRunner.reload(to:)`. `SketchRunner.sketch` is a
`var`, and the loop already calls `sketch.performDraw()` through the instance,
so swapping the var means the next frame runs new code. The reusable loader
(`SketchLoader`) lives in the `OllinRuntime` library target, shared with the
gallery and kept out of the shipping `Ollin` framework.

The sketch dylib compiles with `-I` pointing at the dirs that hold
`Ollin.swiftmodule` and the C targets' module maps (to type-check
`import Ollin`) and `-undefined dynamic_lookup` with *no* `-lOllin`; the host
links `-Xlinker -export_dynamic`, so the dylib's Ollin symbols resolve against
the host at `dlopen`. Those `-I` dirs are **discovered, not assumed**
(`SketchLoader.moduleSearchPaths`): the classic SwiftPM build puts them next
to the executable (`<bin>/Modules`, `<bin>/<C>.build`), but the Xcode/Swift
build system puts `Ollin.swiftmodule` directly in `<bin>` and the C maps under
`.build/index-build/<triple>/debug`, so a `<bin>/Modules`-only assumption
fails with "no such module 'Ollin'" (it did; the `--selftest` harness
exercises exactly this). A third source sits outside the build tree: a
vendored C target with a checked-in module map
(`External/<T>/include/module.modulemap`, e.g. CBox2D, CSyphon) never lands
under a `*.build` dir, so the loader also collects those `include/` dirs from
the package root; without them a loose sketch cannot `import OllinPhysics`
(its swiftmodule needs the clang module even though the import is
`internal import`).

There is one copy of `Sketch`, so the loaded object casts as `Ollin.Sketch`.
**A `.dynamic` Ollin product does not fix this**: SwiftPM still links the
target statically into the executable, giving two copies and a failed cast
(verified the hard way). Each load uses a unique `-module-name` so repeated
reloads of the same class do not collide in the objc runtime. The loader
regexes the `class ...: Sketch` name and compiles a sibling
`@_cdecl("ollin_make_sketch")` factory file alongside the user's source, so
the user file is untouched and its `@main` is harmless under `-emit-library`.

### Watching, threading, and reload state

Editors save atomically (temp file plus rename), which breaks fd-based
watches, so `FileWatcher` watches *directories* with
`kFSEventStreamCreateFlagUseCFTypes | ...FileEvents` (the UseCFTypes flag is
required or the path-array cast crashes), debounced ~150ms, dispatching by
extension: `.swift` recompiles and swaps; `.metal` routes to the shader
reload (a user-resource `.metal` invalidates just the user-shader caches, a
framework segment rebuilds the whole library; the dispatch tells them apart by
path); image assets re-run `setup()`.

Recompiles run off the main thread (the window keeps drawing the old sketch);
the swap is marshaled to the main queue. A compile error is printed and the
running sketch is left alone, so a typo never closes the window; likewise
`MetalRenderer.reloadLibrary` builds the new pipelines before committing, so a
bad shader edit cannot blank the renderer. `reload(to:keepClock:)`
re-instantiates and re-runs `setup()`; by default it resets
`time`/`frameCount`, and `--keep-clock` carries them forward (offsets
`startTime` so `time` continues, copies `frameCount`) so an animation's phase
does not jump. `Sketch.onReload()` fires once after the post-reload setup,
never on first launch. `SketchRunner.reload(to:)` honors the *new* sketch's
declared `canvasSize` for non-`.resizable` modes, so an edited resolution
takes effect on the swap.

### `@Param` knobs and the inspector

The generic `@Param` wrapper/registry in the core (`Param.swift`) drives the
shared inspector (`Inspector.swift`) in all three hosts through the
type-erased `AnyParam`/`ParamControl` surface (typed get/set closures per
control kind), so hosts never touch `Param<Value>` directly. The control
follows the property's type: `Double` slider (optional `step:` snaps every
write; `style: .field` drops the track), `Int` stepper, `Bool` toggle, a
`ParamOption` enum menu (keyed on case *names* for persistence; the
CaseIterable mode enums conform out of the box), `Color` well, `Vector2`
paired x/y fields (`style: .pad` adds a drag pad mapped top-left = both lower
bounds, the canvas origin), `Vector3` and `Rectangle` and `Insets` field
lines, `ClosedRange<Double>` a two-thumb slider (a min dragged past the max
pushes it along; the grabbed thumb is held for the whole gesture), `String` a
text field, `style: .segmented` on the option kinds, and the `ParamChoices`
named-catalog menu (which needs `Equatable` to find the current selection;
that is why `Easing`, a closure wrapper, and the parameterized `Material`
finishes stay out, while `LightingPreset` conforms). `ParamValue` is public,
so a user type can conform by mapping onto an existing control kind. `icon:` /
`group:` put an SF Symbol on the row and split the list into titled group
cards (declaration order; ungrouped first).

Numeric value boxes scrub (drag to change, Option fine, Shift coarse, click to
type). Two SwiftUI gotchas were real bugs: any Text sharing a scrub pill's
HStack must be `.fixedSize()`, or the paired-pill (Vector2) row compresses it
to zero width and it silently vanishes; and `.segmented`'s ViewThatFits needs
the label `.fixedSize()`-pinned (an un-pinned truncatable label never wraps)
plus `maxWidth` with `alignment: .leading` on the wrapped block (ViewThatFits
centers a narrower child). Knob values persist across reloads as `ParamStored`
payloads (`SketchSession.recordParam`/`syncParams`; a property that changed
*type* in the edit drops its stale value so the new default wins). Headless
gates: `OllinLive --paramtest` plus `ParamTests`.

### Frame stats and the host chrome

The runner fills one shared `FrameStats` (`@Observable`: fps, CPU frame time,
vertex/SDF draw counts, clock, canvas size) a few times a second via the
built-in `StatsExtension` on the extend seam. Three surfaces read it: the
OllinLive sidebar inspector, the gallery's right-sidebar inspector, and (for a
standalone `swift run`) a detached frosted `NSPanel` (`StatsPanel.swift`;
View > Show Inspector, cmd-/ via `OllinHUDCommands`, bound to
`@AppStorage(OllinHUD.showStatsKey)`). A host with its own inspector sidebar
opts the panel off (`SketchView(showsInspectorPanel: false)`) and omits
`OllinHUDCommands`, so its cmd-/ toggles the sidebar instead. Stats are debug
chrome, SwiftUI siblings of the Metal view, so they never land in exports.

Two gotchas the build proved: the CPU-ms must time `performDraw()` *alone*
(timing across `renderer.render()` includes the triple-buffer semaphore wait,
pinning the number to ~1/fps and telling you nothing); and an on-canvas
element's corner inset must be `.padding` *before* the canvas-filling
`.frame`, or the padded box overflows and clips. `SketchView` is a SwiftUI
`View` that `ZStack`s host chrome (the axis widget, the keyboard-focus hint)
over a private `MetalCanvas`, the `NSViewRepresentable` MTKView that remains
the AppKit/UIKit portability seam.

### The shared session engine (`SketchSession`)

`OllinRuntime.SketchSession` holds the compile/reload orchestration both
OllinLive and OllinLiveCoding wrap (supersede-cancel compile scheduling,
`syncParams` re-applied *before* the swap so knobs never snap, and the
two-channel Swift-versus-shader error model where neither clears the other);
`LiveSession` and `PerformanceSession` are thin wrappers. Orchestration
changes go in `SketchSession`, never re-forked per host. Buffer compiles
(`SketchLoader.Input.source`) write the editor text into the per-compile work
dir *under the sketch's own file name*, so diagnostics carry exact buffer
lines and the same file name (`CompileDiagnostic.parse` matches by `fileName`,
never by path, which is the temp copy), while the factory shim's
`Bundle.module` keeps pointing at the sketch's real folder so co-located
assets resolve. The rest of the live-coding host's invariants (stage overlays,
editor rules, recovery scoping, the headless gates) are enumerated in
CLAUDE.md's *Live coding* block.

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
