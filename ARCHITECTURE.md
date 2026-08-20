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
feature in Docs/, the cross-cutting rules in CLAUDE.md, the capability inventory
in [`CAPABILITIES.md`](CAPABILITIES.md), and the deep internals of shipped
systems here. When a capability needs more than its terse invariant there, the
depth lives here and `CAPABILITIES.md` keeps a pointer.

This document is populated one system at a time, so it is intentionally
partial. The map below lists Ollin's major systems and where each one's
internals are documented today; `CAPABILITIES.md` remains the complete
capability index regardless.

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
on its own perpendicular runs past that crossing and into its neighbor, so both
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

Where the crossing falls outside either neighboring segment the ribbon would
turn inside out, so the ends stay square there (NanoVG's inner-bevel case, the
`dmr2 * limit * limit >= 1` test against the shorter neighbor). A corner that
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
rasterization, which is what the export supersample (`--render-scale`, see
`Docs/Output/Export.md`) exists to spend time on and what makes it worth
little on the paths that carry their own coverage.

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
  index into a color channel, is what separated this from the amount question
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
carried in the state, so color-by-scale (McCabe's colored plates) is not
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
neighbors and keeps the remainder, so in quarters the whole update is
`q' = fract(q) + Σ floor(q_n) / 4`. Dhar's 1990 abelian-property result is what
licenses any parallel schedule, single or k-fold, since topplings commute and
the settled pile is the same in any order. The k-fold form matters and was
found empirically (the first render used one toppling per pass): where every
cell holds fewer than eight grains, the regime a critical pile lives in, the
two are *identical*, but at a heavy source single toppling pools, because a
saturated blob's interior is net zero (lose four, receive one from each of
four toppling neighbors) and only its perimeter drains; a measured 800-frame
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
- **The boundary is open, never wrapped or clamped.** A neighbor position off
  the field contributes nothing, and a toppling cell always loses four, so
  grains crossing the edge are simply gone. That dissipation is what lets a fed
  pile keep settling (on a torus sand only accumulates until every cell topples
  forever), and the guard must reject the position *before* sampling, or the
  clamping sampler reads the edge texel back as its own neighbor: a reflecting
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

### The watercolor wash (`Sim.watercolor` / `WatercolorField`)

The third dedicated multi-pass sim beside the fluid and Turing, and the largest:
the classic three-layer wash model (shallow water flowing above the paper,
pigment settling onto it, moisture creeping through it; see `ATTRIBUTION.md`
for the source paper and the division of credit). `runWatercolor` drives it
over a `WatercolorSlot` of ten persistent textures: three ping-pong pairs
(`flow` = velocity/pressure/wet mask, `pig` = suspended pigment + paper
saturation, `dep` = settled pigment), the generated `paper` height field, the
dried-glaze stack (`driedR`/`driedT`, Kubelka-Munk reflectance and
transmittance), and the `display` texture the field's `image` serves (also the
repeat-encode answer: a second encode of the same sketch frame reads it back
instead of re-stepping).

**The grid and its packing.** One texel carries a staggered (MAC) cell: `u` on
its right face, `v` on its top face, pressure and the wet mask at the center.
Every flow or pigment tap goes through a bounds-rejecting helper that reads
off-canvas as dry, motionless paper; the clamp sampler would reflect the edge
texel back as its own neighbor, and the rejection is also what pins velocities
at the canvas edge for free. A face bordering a dry cell is pinned to zero in
every pass that writes velocities, which is the paper's boundary condition
(water never leaves the mask) applied at write time rather than as a separate
pass.

**Two sign decisions are load-bearing.** The velocity update applies the
viscous term as `A + μB` (B is the five-point Laplacian): the model's
continuous equations carry `+μ∇²u` and its own design conditions demand damped
flow, while the printed pseudocode's sign reads inverted, and anti-diffusion
detonates the wash within seconds. The divergence relaxation likewise runs in
the divergence-*reducing* direction (`δ = −ξ·div`), in gather form: a face
carries its own cell's correction minus its right/top neighbor's, and the
per-cell corrections also accumulate into pressure, so water added anywhere
pushes water everywhere.

**Time stepping.** The paper's adaptive Euler step (Δt chosen so no velocity
crosses a texel) becomes four fixed substeps of dt = 1/4 with velocities
clamped to ±1, the ripples precedent. That pairing is what lets the pigment
advection be a pure nine-tap gather with no conservation rescale: each face
moves at most a quarter of a cell per substep, so the four outflows can never
exceed the cell's own pigment, concentrations stay non-negative, and both
sides of a face compute the same transfer from the same snapshot. The
settle/lift exchange with the deposit layer is split into two passes
(`transfer_dep`, `transfer_pig`) that read one snapshot and derive identical
per-pigment deltas, so the pair conserves pigment exactly; the capillary
absorption folds into the pigment half (wet paper drinks toward its
height-scaled capacity, damp paper left behind dries slowly).

**Backruns and the two lifecycle verbs.** The capillary layer is the paper's:
moisture diffuses from wetter to drier paper *that is already damp* (a
receiver below the dampness threshold takes nothing, so blooms stop at dry
paper), and paper saturated past a threshold joins the wet mask. Two
calibration facts matter. `dry()` bakes the wash into the glaze stack
(compositing the wet layer onto `driedR`/`driedT` as *fresh* textures swapped
into the slot, never rewritten in place under an in-flight frame) and must cap
the remaining saturation *below* the mask-expansion threshold, or the fully
saturated sheet re-wets its whole old footprint on the next step and `dry()`
never sticks. And a baked wash has nothing left to push, which is why the
paper's backrun needs its own staging verb: `blot()` lifts the standing water
but leaves the pigment parked and the sheet damp (the paper authors this state
as initial conditions), and a *held* clean-water touch then floods back
through the damp paint, pushing it into the pale bloom with the dark branching
rim. A single tap only nudges, because one frame's pressure equalizes through
the relaxation almost immediately; the held brush is a sustained pressure
source, and interactively that is exactly how a wet brush behaves.

**Rendering.** The optical passes run in display-space sRGB, the space the
pigment coefficients are specified in (and the space the source work's own
arithmetic ran in), converting to linear only at the output write; the CPU
reference (`KubelkaMunk` in `WatercolorSim.swift`, which also powers the
`overWhite:`/`overBlack:` inversion and the tests) and `ollin_wash_km_layer`
are the same closed forms and must stay in step. A layer's coefficients blend
across the palette in proportion to each pigment's share of the total
thickness (`x_k = g_k + d_k`); the wet layer composites over the dried stack,
and the whole stack over the sheet's own reflectance. The pipeline is
deterministic end to end (the paper generates from a seeded fragment; every
pass is a fixed function of state), so unlike the atomic-scatter compute sims
it carries a pixel snapshot (`watercolor-sim`), with `WatercolorSimTests`
pinning what a mean diff averages away: the darkened edge, the dry-brush gaps
(the inject's height gate applies to *both* halves, or dry-brush gaps hold
flat unsimulated pigment), the freeze after `dry()`, the backrun-vs-off
counterfactual, and byte-exact replay.

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
example a hand-drawn depth map) samples paired depth neighbors a few texels out,
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
`viewProjection` to its prior uv), neighborhood-clamps the sampled history to the
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
for Beginners), reprojection temporal accumulation with neighborhood variance
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
  neighborhood max consumes it, while a real in-focus subject is thick enough to
  keep its near-zero size.
- **Scatter** is the min over the immediate neighborhood. Where the band instead
  lands in the *fully defocused* range it flings the color beneath it across the
  entire blur radius, and because the whole rim shares one depth it cuts off at
  one radius too: a perfectly in-focus object came out ringed by a faint,
  hard-edged, concentrically ridged halo of its own color (7 to 10% of the
  object's brightness against a dark backdrop, out to `maxBlur`). A rim texel
  always has a low-blur neighbor on the object side, so the min erases it, while
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

- **Both fields seed with the center texel.** Seeding the near field with black
  instead (the obvious "nothing here yet" value) leaves its running average
  converging *from* black, weighted `1/(taps+1)` per reaching tap, so a partly
  covered foreground composites that bias over the background. A uniformly white
  layer with a near disc in its depth map came back with a ~12% dark ring.
- **Alpha rides the gather with the color.** The layers are premultiplied, so
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
single-pass gather cannot do. The far side resolves first (the sharp center
blended toward its own bokeh by how defocused it is), then the foreground field
composites *over* that by its coverage, so a defocused foreground spreads over
and hides an in-focus subject behind it instead of leaving a sharp crescent, and
an in-focus subject otherwise stays crisp and correctly occludes what is behind
it. Folding the two into one `mix(center, mix(bg, fg, a), max(dof, a))` applies
the coverage twice and leaves a half-covered sharp subject a quarter more of its
sharp self than it should have.

Two rules make the foreground's own silhouette soften on **both** sides of itself,
which is the half that is easy to get wrong (it blurred outward and stayed razor
sharp inward, stepping 40% of the way to the background in a single pixel):

- **A pixel under a near blur lets the background field gather from anywhere
  inside that blur** (`nearReveal`). Otherwise nothing sits behind the foreground
  for it to become transparent against, since the in-focus scene around it never
  "reaches". What a foreground truly hides cannot be recovered from one image;
  standing its neighborhood in for it is the usual approximation and reads right.
- **Foreground coverage is an area fraction of that near blur, not of the whole
  gather disc.** The spiral is equal-area per tap, so taps inside radius `r` number
  `total * (r/maxBlur)^2`; normalizing by the disc instead (with a constant fudge
  to make up the difference) pins the alpha at 1 well inside the silhouette, which
  is exactly what kept the inner edge hard. Normalized properly the alpha passes
  through the silhouette mid-ramp and falls off over the foreground's own blur
  radius either side.

An expanding golden-angle spiral (`radius += radScale/radius`, with `radScale`
proportional to `maxBlur` squared) packs rings denser toward the rim so the bokeh
edge is smooth without jitter.

**The shape of the opening is a parameter of that gather, not a second path.** An
out-of-focus point of light is a picture of the opening its light came through, so
`blades` / `irisAngle` / `catsEye` enter at exactly one place: the reach test. The
circular test asks whether a tap's own blur spans its distance. The general test
asks the same question in units of how far the opening reaches *that way*
(`ollin_dof_aperture`), so the distance is divided by that reach and the ~1px soft
edge is divided by it too, which is what keeps the edge about a pixel wide on screen
whether the opening runs near or far in that direction. A round opening reaches
exactly 1 everywhere, so it is byte-identical: the whole snapshot suite and all 49
Guide probe figures passed unrecorded.

Two decisions inside that helper are worth keeping:

- **A polygon is taken at the *area* of the round opening it replaces**, not at its
  radius: `R = sqrt(pi / (n sin(pi/n) cos(pi/n)))`, from `n R^2 sin(2 pi / n) / 2 =
  pi`. So changing the blade count changes the shape of a highlight and not how
  large it reads, which is the behavior a blade *slider* wants. The cost is that the
  corners now poke past `maxBlur`, so the gather's rim goes out to `maxBlur * R` and
  the tap spacing widens with it (the tap count stays at the budget). The
  foreground-coverage normalization moves to that same rim, or a near field would
  read its area against the wrong disc.
- **Cat's eye is the aperture intersected with two discs pushed apart** by `pinch`
  along the line to the middle of the frame, `pinch` growing with the pixel's
  distance from that middle and capped at 0.9 so an opening never closes entirely.
  This is the geometry of optical vignetting: what an off-axis image point sees of
  the aperture is what the barrel's own openings leave of it, front and rear, which
  is why the shape is a symmetric lemon rather than a disc with one flat side.
  Solving `|t u -/+ pinch f| <= 1` for the larger root gives the reach in closed
  form, `sqrt(pinch^2 c^2 + 1 - pinch^2) - pinch |c|` with `c` the cosine between
  the tap direction and the line to the middle, so it costs one dot product and one
  square root per tap. The reach is `1 - pinch` along that line and
  `sqrt(1 - pinch^2)` across it, and since the second is always the larger the lemon
  lies the long way around the frame, as a real one does. It changes *shape* only;
  the gather normalizes by its accumulated weight, so nothing darkens (`.vignette`
  is the filter for that).

**`blades` defaults to the camera, not to round.** `DepthReconstruction` already
carries the camera geometry stamped on a 3D target's depth layer for the ambient
occlusion and reflection combines, so it carries `apertureBlades` too, and
`.defocus` falls back to it. That is what makes one line, `camera.apertureBlades =
6`, shape the live blur, every lens-flare ghost, and the path-traced export's own
highlights together. A hand-drawn depth ramp carries no camera and stays round
unless the call names a count itself.

**The round path pays nothing, and that took one branch.** Folding the general form
into the loop unconditionally cost **19.6 ms against 14.7 ms** at 192 taps (M2,
1080x1080, old and new alternated back to back), which is a 33% tax on every sketch
that never asked for an iris: a divide, two multiplies and a call per tap add up over
192 of them. The shaping now sits behind a `shaped` test hoisted out of the loop, read
off the *settings* (`blades >= 3 || catsEye > 0`) rather than off the per-pixel pinch,
so it is one answer for the whole pass and the round branch runs exactly the
instructions it ran before: **14.4 ms against 14.7 ms**, parity within the noise. An
opening that *is* shaped costs about a third more GPU time (15.1 ms to 20.1 ms at the
`Effects/Bokeh` example's settings, 66 fps to 50 fps), which is the right shape for an
opt-in.

**The envelope is the tap budget, and it is worth stating plainly.** The spiral is
equal-area per tap, so the spacing between taps is `sqrt(pi / budget)` of the rim:
about 13% at `.default` (192 taps) and 8% at `.detail` (512). A source smaller than
that spacing is hit or missed rather than resolved, and comes out wearing the
spiral instead of a clean edge. Meanwhile a regular polygon's corners stick out by
`1 - cos(pi/n)` of the rim: 50% for a triangle, 19% for a pentagon, 13.4% for a
hexagon. So at `.default` a hexagon's corners sit exactly at the sampling limit,
which is why a low blade count reads and a high one does not, and why the Guide
figure uses five blades at `.detail`. The scalloped rim and the faint dark core an
HDR point source shows are the **pre-existing** gather's (the center hole starts at
`radScale`), verified by rendering the same scene at `blades: 0`; the aperture
neither causes nor cures them.

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
directly instead: a near spread invents no color, a sharp subject rejects the
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
(`fieldScreenCoverage`: each world AABB's eight corners through the camera, and
per box the smaller of the corners' clipped NDC bounding rect and their convex
hull's area, summed; a plane or a corner at/behind the camera counts as full
coverage) and traces at `min(1, fraction / √coverage)`: the marched-pixel
count never exceeds `fraction² × canvas`, the cost the fraction already implies
at full coverage, while a small field gets traced dense. At or above scale 1 the
pre-pass is skipped entirely (the inline march is crisper *and* cheaper).
The estimate's honesty is load-bearing, because every ounce of conservatism
holds the internal resolution down: the flatteners grow a combine's AABB by
each op's *provable* outward reach (a polynomial smooth op's surface bulges at
most k/4 past its operands, padded to k/2 for bound-type child SDFs; chamfer
and stairs seams stay within k/2; columns, pipe, and tongue genuinely reach k;
the subtract, intersect, and morph families cannot leave the hard op's region
at all, and morph's k is a blend fraction, not a length). The blanket
k-per-nested-op grow this replaced compounded on a three-op metaball into a box
whose projection read near-screen-filling four radii out, so the adaptive scale
never rose and the dollied-out blob stayed at the reduced resolution: the
zoom-out blur back again, from the estimate rather than the formula. The hull
term earns its keep on the oblique views an orbit camera spends most of its
time in, where a corner-on box's NDC bounding rect over-covers its hexagonal
silhouette by about 2×.
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

## Instanced meshes and mesh fields

The user-facing surface is `Docs/3D/Instancing.md`; this section is the
machinery behind `drawMesh(_:instances:)` and the retained, GPU-culled
`MeshField`, and the two findings that shaped them.

### The two tiers

The per-frame instanced path (`.meshInstanced`) is the animation tier: the base
mesh expands once per call into its own ring array (LOCAL space, the model
matrix deliberately NOT baked, which is the whole saving over the per-mesh
path's per-copy re-bake), and an 80-byte `OllinMeshInstance` per copy (model
matrix + tint) rides a second ring. Rebuilding the placement list every frame
is the intended idiom, so nothing here is retained. The `MeshField`
(`.meshField`) is the world tier: everything uploads once into the field's own
per-device buffers (the `Batch.GPUResources` model), and the per-frame work
moves to the GPU entirely.

Both vertex shaders derive the normal transform from the model's linear part as
the adjugate (three column cross products), normalized after. That choice is
load-bearing for the compute-written forms: a kernel fills only model + color,
and non-uniform scale still lights correctly with no inverse-transpose to
precompute. The A/B against the CPU path's true inverse-transpose held under
mean 0.5/255 with non-uniform scales in the fixture.

### The field's frame

`encodeMeshFieldCulling` runs at drive level (after `encodeCompute`, before any
render pass, same command buffer, so hazard tracking orders everything): one
blit zeroes the per-entry visible counts, then per field a cull kernel (one
thread per copy) tests the entry's local bounding sphere through the copy's
matrix and the draw-time field matrix against six Gribb-Hartmann planes, and
appends survivors into the entry's own region of a compacted-index buffer
(atomic per-entry counters; regions tile the copy list, so entries never
collide). An encode kernel (one thread per entry) then writes one
`MTLDrawPrimitivesIndirectArguments` per entry:

```
draws[e] = { vertexCount:   entry.vertexCount,
             instanceCount: visible[e],
             vertexStart:   entry.vertexStart,     // into the shared vertex buffer
             baseInstance:  entry.compactOffset }  // into the shared compacted buffer
```

`baseInstance` is the trick that keeps the draw arm stateless: `[[instance_id]]`
starts at `baseInstance`, so the field vertex reads
`instances[compacted[iid]]` and every entry's draw uses identical whole-buffer
bindings; the arm binds four things once and issues one indirect draw per
entry. CPU cost is per KIND of mesh, never per copy.

### Why indirect draws and not an indirect command buffer

The design started as a classic ICB (compute-encoded `render_command`s,
`inheritPipelineState`, one `executeCommandsInBuffer`), and the mechanism
worked in isolation. It died on a fact worth keeping: on a ray-tracing device
the lit mesh fragment carries the RT intersector, and Metal refuses that
fragment in any ICB-capable pipeline ("Fragment shader cannot be used with
indirect command buffers"). The choices were a hand-synced RT-free fragment
twin (fields would stop receiving ray-traced effects) or GPU-written indirect
draw arguments, which carry the identical payload with no fragment restriction.
Indirect draws won: full shading everywhere, one code path, and the CPU still
never sees a copy. Any future ICB use belongs on RT-free shaders (a depth-only
pass is the natural fit). A second lesson from the same debugging session: a
failed `try? pipeline(key)` skips a batch silently, which made the field
invisible while its culling A/B "passed" on two empty images; every new
pipeline key now gets an explicit build test.

### Culling the shadow pass, exactly

Camera-frustum culling alone recovered only 1.5x on the 240k-copy benchmark,
because the shadow pass still drew every copy. The fix is a second cull of the
same shapes against the LIGHT's frustum (the 2D map's own view-projection),
which is exact by construction: anything it drops, the map's rasterizer would
have clipped anyway, so casters behind the camera still shadow the view and the
picture cannot change. The cube (point) pass stays uncculled: it looks in six
directions at once. With both culls the benchmark lands at 18.5 ms vs 50.8 ms
unculled (2.7x), CPU ~0. One gotcha cost real time: within a single compute
encoder, a later dispatch inherits earlier `setBuffer` bindings, and the
shadow-cull dispatch read the just-bound draw-arguments buffer as instance
matrices until the instance buffer was explicitly rebound. The
culled-vs-unculled A/B surfaced it as a single 37-pixel shadow sliver.

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
intensities in the tens. Rect and disk panels cast shadows from their real
extent (the caster search reaches them after the punctual kinds; see
*Shadows* below), where a tube never casts (radial emission has no facing
axis to shadow from). The RT-reflection hit shade evaluates the **exact LTC
diffuse** per area light (`ollin_ltc_diffuse`, the identity-transform
integrals kept in step with `ollin_ltc_light`'s dispatch), so a panel-lit
surface reads the same in a mirror as head-on: only the disk's
horizon-clipped-sphere factor reads a table, so the single amp texture rides
the trace (threaded through `ollin_pbr_ibl_ambient` to the inline path, and
bound at texture 9 of the deferred trace pass, whose lighting also resolves
`ltcEnabled`, or the panel would go dark only in its deferred reflection).
Specular at a hit stays the traced second bounce, matching the punctual
lights' Lambert-only hit treatment. Pinned by the RT-gated `area-reflections`
snapshot and the panel-on/off `AreaReflectionRenderProbes` differential. The
head-on view (V ≈ N) takes a deterministic fallback tangent instead of
normalizing a zero vector (the reference leaves this case unguarded; the
head-on LUT row is fitted isotropic, so any tangent is exact).

### Light shaping (IES profiles and cookies)

A point or spot light can carry an `IESProfile` (a fixture's measured angular
intensity, parsed from the industry's LM-63 photometric files) and a spot a
`LightCookie` (a projected image). Both are per-light data that end up as
layers of two `texture2d_array`s bound at fragment textures 10/11 on every
lit carrier, sampled inside `meshLitColor`'s punctual branch and the
`ollin_rt_direct` hit shade.

**The parser treats the file as a number stream, not lines.** LM-63 nominally
caps lines at 132 characters, but real exports break that freely (Lagarde's
survey found 4,000-character candela lines), so `IESProfile` finds the
`TILT=` line, tokenizes every whitespace/comma-separated number after it, and
counts: a skipped `TILT=INCLUDE` block, the 10 + 3 header fields, the two
angle lists, then one candela block per horizontal angle with the vertical
angle varying fastest. Lateral symmetry rides the *last* horizontal angle
(0 = axially symmetric, 90 = quadrant, 180 = bilateral, 360 = full wrap, plus
the rare 90-first/270-last plane), expanded at sample time by folding the
query azimuth into the stored wedge. Only Type C photometry parses (the
architectural convention; A/B are automotive/floodlight aiming conventions
Ashdown reports never meeting in practice), values normalize to peak 1 (the
light's `intensity` stays the brightness knob, unitless like the rest of the
punctual model), and every failure path returns `nil` with a one-line stderr
reason, including header counts, which go through a guarded `Double`→`Int`
conversion because a malformed exponent would otherwise trap the process.

**The bake resamples the wedge onto a uniform sphere.** The CPU sampler
interpolates the non-uniform measured angles piecewise-linearly; `bakedTable`
evaluates it at texel centers into a 256×64 (θ 0…π across, φ 0…2π down)
`r16Float` layer. The shader then needs no knowledge of symmetry or angle
lists: u clamps, v wraps (the sampler's `t_address::repeat` carries
`atan2`'s signed azimuth straight through). Directions outside a file's
measured vertical range are dark *by design*: a downlight file ending at
90° sends nothing above the fixture's horizon, which is why the example's
wallwasher tilts its whole axis at the wall the way a real one aims, rather
than expecting azimuthal data to reach up.

**`LightCookie` is a value, not an `Image` reference.** `Light` is
`Equatable, Sendable`; `Image` is neither, so the cookie resamples the
image's premultiplied pixels bilinearly into its own fixed 512² buffer at
init (with a precomputed content hash for cheap equality and caching) and
carries no reference back. That one decision keeps `Light` a plain value,
makes the GPU upload a byte copy into an array layer, and pins the "build it
once in `setup()`" usage shape. A GPU-backed image has no CPU pixels and
fails to wrap (snapshot it first).

**Frame plumbing follows the LTC pattern exactly.** `makeLighting` dedupes
the frame's profiles and cookies into `Drawer.usedIESProfiles` /
`usedLightCookies` (rebuilt on every call, so the several per-frame
`makeLighting` invocations agree) and packs each light's layer indices plus
its roll into the new `OllinLight.shaping` float4 (-1 = none; a
zero-initialized struct would silently point at layer 0). The renderer bakes
the arrays keyed by content-hash lists (an unchanged frame rebinds the same
textures; a changed one gets a *fresh* allocation, never replaced in place,
since in-flight command buffers retain the old) and raises `iesEnabled` /
`cookieEnabled` at the same three sites `ltcEnabled` is resolved (the main
encode, `resolveFieldLighting`, and `encodeReflectionPass`, the last because
the deferred trace builds its own lighting and would otherwise lose the
pattern only in reflections). The stand-in for an empty slot is a dedicated
1×1 `texture2d_array`; the 2D gradient-strip stand-in the other slots use
is type-invalid where the shader declares an array.

**Sampling applies to the light's local copy.** `ollin_apply_light_shaping`
multiplies the profile's scalar and the cookie's rgb into the loop-local
`L.color`/`L.specular`, so every shading model below (standard, toon, Gooch,
PBR), the SSS wrap, and the `incoming` sheen accumulation pick the shaping up
with no per-model edits, and `ollin_rt_direct` reuses the same helper so
reflections can't drift. The tangent frame (`ollin_light_frame`) uses the
shadow code's up-reference convention but winds `right = axis × ref`, the
**projector convention**, under which a cookie reads un-mirrored as seen from
the light looking along its beam; the first cut wound it `cross(ref, axis)`
and the probe caught the mirrored image. The cookie maps the outer cone's
footprint to the texture square (`tan` of the half-angle recovered from the
packed `cosOuter`), so its edges land exactly at the cone edge and the edge
clamp is invisible: every point outside the [0,1]² square is also outside
the cone the `smoothstep` already zeroed. One `roll` spins profile azimuth
and cookie together, like turning a fixture in its yoke.

Pinned by `IESProfileTests` (parse, symmetry folds, candela ordering, bake,
packing) and `LightShapingRenderProbes` (the ring profile darkening the axis
while lighting its ring, the half-black cookie's orientation, and a
half-turn roll swapping it); the `light-shaping` snapshot covers the whole
path with inline-authored fixtures. All bundled `.ies` files are authored
for Ollin; manufacturer files are freely *distributed* but not clearly
*licensed*, so none ship.

### Atmosphere (fog and volumetric light)

`fog(_:density:heightFalloff:)` and `volumetricLight(_:anisotropy:)` are per-frame
drawer state packed into three `OllinLighting` tail fields (`fogColor` with the
gate in `.w`, `fogParams`, `fogParams2`), so the constants reach every lit carrier
plus the deferred reflection trace with no new plumbing; the gate at 0 leaves every
branch untaken (whole suite byte-identical, verified). The packing sits *ahead of*
`makeLighting`'s `.off` early return on purpose: fog is a property of the air, so a
`noLights()` scene still fogs (only the shaft march needs the lights).

**The compositing model respects call order with no stored scene depth.** Every 3D
shading fragment fogs *itself* over its own eye-to-surface path (the exact
closed-form height-fog transmittance from Quilez, with series limits at zero
falloff and horizontal rays so nothing pops at the horizon), applied after the full
shading tail so reflections and IBL ambient dim too. The empty air is a fullscreen
draw in the skybox slot (`PipelineKey.fogAir`, the same always-pass/no-write
recipe, encoded right after the skybox): it marches to each pixel's own far-plane
distance and outputs premultiplied `(ambient + in-scatter, 1 − T)`, so the
backdrop shows through by exactly the transmittance, meshes depth-composite over
it, and 2D drawn later is untouched. Splats and particles alpha-composite over the
beam-painted backdrop, which is why beams read through a point cloud that itself
takes no fog term. The RT reflection hit shade applies the analytic leg to the
surface-to-hit path inside the *shared* trace (`ollin_rt_reflection_trace`), so
the inline and deferred paths can't disagree; an environment miss keeps the sky
clear (documented envelope).

**The march (`ollin_fog_inscatter`) is the Tóth-Umenhoffer single-scattering
integral, and three of its pieces are load-bearing, each a real observed failure
first.** (1) *Per-spot ray∩cone span bounding*: strata spread over the whole ray
straddle a beam a fraction of a stratum wide, and the beam dissolves into a woven
noise lattice (or, un-jittered, vanishes outright); bounding the sub-march to the
analytic cone crossing puts every stratum where the beam is. Only the transverse
case is bounded (a ray running within the cone angle of the axis takes the full
range under a quadratic near-field warp `t = tEnd·u²`), and the mirror-nappe
interval is rejected by an axis-side test. (2) *The light-leg extinction*: without
`exp(−τ(light→sample))` a ray riding inside a cone accumulates without limit and
the frame washes out; with it the integral is bounded by ~σs/σt. Beams-only mode
(no `fog`) substitutes a 0.05 reference density for both the scattering
coefficient and that leg, so beams still form and still bound while the view path
keeps zero dimming. A directional light takes the leg only under height falloff
(the slant path from the sky then has a finite closed form: the crepuscular
dimming); uniform fog has no finite sky path, so it is skipped there. (3)
*Per-step jitter decorrelation*: one shared per-pixel offset moves all strata
together, and that coherent error reprints the jitter pattern as a lattice across
the beam, so each step re-reads the gradient noise at a per-step pixel shift. The
jitter stays a pure function of (pixel, step): exports and snapshots reproduce
with no temporal history and no warmup.

Per step, a spot evaluates its cone falloff and the shared
`ollin_apply_light_shaping` (IES profile + cookie on the light's local copy), so
a gobo's panes read as bars of bright air with the same projector-convention
mapping the surfaces use; visibility is one un-filtered `sample_compare` tap
(`ollin_fog_shadow_tap`, constant bias only: an air sample has no normal and is
never its own occluder; outside the caster's box counts as lit). Directional and
spot participate; point and area kinds sit out (no distance falloff means an
omnidirectional glow has no shape to march), and only the 2D-map caster carves
shafts, the same one-caster rule as surfaces.

**Budgets and encode sites.** The step budget rides `fogParams2.x`, resolved by
the renderer (`resolveVolumetricSteps`: 16/32/64 by tier through
`effectiveQuality`, absolute 8…128) at *both* lighting-resolution sites: the main
`encode` and `resolveFieldLighting`, so the half-res field tier marches like the
full-res pass. The air cap rides `fogParams2.y` (the camera far plane, packed by
the drawer). A frame with no batches at all early-outs of `encode` before the air
draw, so beams need at least one mesh in frame (documented). Measured M2 1080²
export tier: the two-spot example costs ~6 ms/frame over its no-volumetrics
sibling; the analytic-fog-only path is arithmetic in the fragment tail
(`fog` snapshot unchanged in cost). Verification: `VolumetricStateTests` (packing,
resets, clamps), `FogRenderProbes` / `VolumetricLightRenderProbes` (distance and
height ordering, the air wash, unlit fog, cone confinement, the carved shaft via
on/off differencing, beams-only leaving off-beam surfaces alone), and the `fog` +
`volumetric-light` snapshots.

**Aerial perspective** (`aerialPerspective(density:haziness:heightFalloff:sun:)`)
is the fog integral split by wavelength: the classic real-time outdoor-scattering
model (Hoffman-Preetham, credited in `ATTRIBUTION.md`), riding the same slots
under **mode 2 on the fog gate** (`fogColor.w` = 0 off / 1 fog / 2 aerial, so
every existing `> 0` gate stays armed and the carriers pick the model with one
compare against 1.5). The shared `ollin_fog_optical_depth` computes one scalar τ
(the green channel's; height falloff included), and `ollin_aerial_split`
exponentiates it per channel through the Rayleigh RGB ratios normalized to green
(`OLLIN_AERIAL_RAYLEIGH` = 0.428/1.0/2.442, the measured sea-level coefficients'
1/λ⁴ ratios, mirrored by hand from `Drawer.aerialRayleighRatios`) mixed with a
gray aerosol fraction (`haziness`), then forms the in-scatter's closed form
`(βR·Φ_R(θ) + βM·Φ_HG(θ))/β_ext · E_sun` per channel, with Φ_R the molecular
phase `0.75(1+cos²θ)` and Φ_HG the shipped `ollin_hg_phase` at g = 0.76 - so the
final composite is `rgb·T₃ + L_in·(1−T₃) + marched beams`, the same shape as
fog's. **The codegen rule from the GI work applies:** `ollin_apply_fog` stays
verbatim and aerial is a *twin function beside it* (`ollin_apply_aerial`), the
call sites branching, because a grown fragment re-contracts under fast math -
verified by recording all 182 snapshot references with the feature in the tree
against a clean-HEAD worktree record: **pixel-identical across the board**. Two
appended `OllinLighting` tail fields carry the rest (`aerialSun` = world sun +
g, `aerialLight` = sun radiance + haziness); the sun resolves at pack time
(explicit → the `.sky` environment's sun through its rotation - the skybox
samples at R_y(rotation)·ray, so content sits at R_y(−rotation) in the world,
sign confirmed against the drawn sun disc → the first directional light negated
→ a default 35° elevation), and its radiance is white dimmed by the molecular
slant-path extinction (airmass ≈ 1/sin e), so a horizon sun feeds the veil
sunset color with no extra knob. A nil `density` derives as 0.35 / the
eye-to-target distance (the contact-shadow default's rule). **The air veil steps
aside behind a skybox** (the renderer flags `fogParams2.z` when the skybox drew;
the air fragment then adds only the marched beams): the sky already is this
scattering integral carried to infinity, so painting the scene-scale veil over
it would double-count - with no backdrop the air paints the implied horizon
glow, its three-channel transmittance necessarily flattened to a mean alpha
(exact over the usual flat clear). Long paths *saturate* toward the sky tone by
design (the closed form's equilibrium); the veil on a mid-distance silhouette
runs blue because blue accumulates fastest at small τ, while the saturated limit
tends toward the phase-mixed sun color - both ends verified against the Hosek
horizon (silhouettes melt into the sky with no seam). Verification:
`AerialStateTests` (mode packing, clamps, the framing-derived density, the
three-way sun resolution with the rotation formula pinned, last-call-wins,
per-frame reset, the warm low-sun radiance, the ratio constants) and
`AerialRenderProbes` (off restores byte-identity, the blue-leaning veil,
distance ordering, sunward brightening, haziness graying, height falloff, the
sky-pixel byte-hold behind a skybox, the bare-air glow, beams riding the aerial
density, determinism - the sky-skip, flat-ratio, and flipped-lobe sabotages each
verified red), plus the `aerial-perspective` snapshot.

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

**Volumetric clouds** (`Environment.clouds(_:)`, the `Clouds` value) bake into
this same generation, which is the design's whole payoff: the backdrop, the
IBL chain, and every reflection see one weather, an overcast dims the scene's
light by construction, exports are deterministic (the cloudscape is a pure
function of the dials, no temporal history), and a still sky costs nothing per
frame while a drifting one rides the shipped animated-sky re-bake. The plain
`ollin_ibl_sky_gen` stays **verbatim** (the fast-math codegen rule) and a
cloudy sky selects the `ollin_ibl_sky_gen_clouds` twin, which reproduces the
clear sky and then marches a spherical shell (1.5-4 km over an earth-radius
floor, so the horizon compresses formations the way a real sky does; 64
IGN-jittered steps, span capped at 24 km, 5 cheap taps toward the sun per lit
sample). The density chain is the published recipe: a procedural weather field
(the reference hand-draws its map, so the stand-in **thresholds a billow fbm
into blobs with hard cores and real gaps**, the window sliding down as coverage
rises - the soft field read as thin veil everywhere, a real first-render
defect), the rounded-base/tapered-top height pair, a **tiling** 128-cube
billow-carved base volume and 32-cube eroding detail volume (periodic
gradient-lattice + cellular kernels, `ollin_cloud_noise_*`, dispatched once per
process and held - a fixed lattice, so every machine bakes identical fields),
and the transmittance shaping trio (attenuation clamp, forward lobe + sun-halo
against a soft back lobe, depth-driven edge darkening). Three tunings were
measured, not guessed: the view extinction's mean free path at ~140 m (550 m
read as vapor), the clear-sky ambient inside the march thinning with coverage
(without it an overcast barely dimmed the floor the probes measure), and the
IGN jitter keyed on the fragment's **own pixel position** (a hardcoded texel
scale left pairs of texels sharing offsets when the cloudy bake doubled to
2048×1024, printing stripe combs across the deck). The bake-cache key widened
from `Environment.Source` to `IBLKey` (source + clouds, clouds nil for non-sky
sources so a stray value can't fragment an HDRI's slot), and the skybox's auto
soft-focus turns off for a *cloudy sky specifically* (its bake is the content's
own resolution; the gate checks the source is really `.sky`, a rule the
HDRI-ignores-clouds probe caught as a live defect when it keyed on the clouds
value alone). Verification: `CloudStateTests` + `CloudRenderProbes` (coverage
claims more sky by a measured blue-lead-ratio classifier, overcast dims the
floor, phase moves the weather, an HDRI ignores clouds byte-identically, two
bakes match byte-identically - the cache-key sabotage verified red), plus the
`sky-clouds` snapshot.

### Shadows

`castShadows()` routes by light type: directional/spot render a 2D shadow map;
a point light is ray-traced on an RT GPU (inline `intersection_query` behind
the `OLLIN_RT_SHADOWS` compile gate) with a mid-point cube fallback elsewhere;
a rect/disk area panel is ray-traced on an RT GPU with a 2D-map fallback (below);
`shadowQuality(_:)` maps hardware-relative ray counts through `RenderQuality`.

**A frame casts from a list of lights, not one.** `Drawer.makeLighting` resolves
up to `OLLIN_MAX_SHADOW_CASTERS` (4) casters into `OllinLighting.shadowCasters`,
each an `OllinShadowCaster` (stride 112) carrying its own view-projection,
texel size, penumbra radius, linearization constants, sample budget, and kind.
Three decisions make the change cheap to reason about:

- **Slot 0 is the primary caster**, chosen by exactly the priority the single
  caster used (directional → spot → point → rect/disk), and the single-caster
  fields on `OllinLighting` mirror it field for field. Everything written
  against those fields therefore reads what it always read: fog and volumetric
  shafts, subsurface transmittance, contact shadows, the marched-field cast,
  caustics, GI, the traced export, and the raymarch carrier all still follow
  one caster. A one-caster frame packs exactly what it packed before the list
  existed, which is why the whole snapshot suite passed unrecorded.
- **A 2D caster's map layer is its slot index.** The shadow map became a
  `depth2d_array` sized to the frame's caster count (a fresh texture when it
  must grow, never a resize in place), one depth-only pass per caster into its
  own `depthAttachment.slice`. Because slot 0 owns layer 0 whether or not it is
  a 2D caster, every helper that reads the primary caster names layer 0 as a
  constant, and a cube or traced primary simply leaves that layer cleared.
- **A point light casts only as the primary.** There is one cube texture and
  one acceleration structure, and both belong to slot 0, so the packing never
  puts a point light in an extra slot: every extra caster is a 2D one. Lifting
  that needs a `depthcube_array` for the cubes and a per-caster trace against
  the shared structure, which is in `DESIGN-NOTES.md`.

#### The rasterized cube, and why it was wrong for so long

The mid-point cube is what a GPU without render-stage ray tracing renders for a
point caster, and it is the one 3D path an Apple-silicon machine never takes.
Nothing exercised it: the snapshot named `point-shadows` renders *traced* here,
so it pinned the traced picture and said nothing about the fallback. It was
wrong in three separate ways at once, and each one is now a probe in
`CubeShadowTests` that was watched fail with its fix removed.

**Forcing the path.** `MetalRenderer.rayTracingAvailable(on:)` answers false when
`OLLIN_NO_RAY_TRACING=1` is in the environment, and both places that decide the
render path read it: the renderer's own `rayTracedShadows`, and the shader
compile that sets `OLLIN_RT_SHADOWS`. So the fallback can be rendered, measured,
and tested on the machine the framework is developed on. `CubeShadowTests` runs
under it, and also runs unasked on a GPU that genuinely cannot trace.

**Every face was stored upside down.** The six face view matrices use the
standard cube-face basis, which is written for an API whose framebuffer origin
is the *bottom* left. Metal's is the top left, while a cube face is addressed
from the top left in both, so rendering those views unchanged flips each face
vertically. A receiver then samples the mirror of the direction it meant: a box
over a floor threw its shadow behind itself, and the floor's own occlusion came
from the wrong place, which rippled it. Working the render's `u` and `v` out
against the cube-lookup table shows `u` already agreeing on all six faces and
`v` inverted on all six, so the fix is one row: negate the projection's y. The
pass culls nothing, so the winding it also flips is free.

**The far plane was fitted to the camera, not to the light.** The packing had
only `Drawer`, so it sized the cube from the camera's framing radius, which says
nothing about how far the light reaches. A caster further from the light than
the camera is was clipped straight out of the cube: it lit up and threw nothing.
The fit belongs in the renderer, because only the renderer knows it is rendering
a cube at all, and a traced frame must not pay for the scan: `pointCasterFar`
takes the frame's mesh-vertex AABB, measures the farthest corner from the light,
adds 2% (so the farthest surface still stores under the "nothing here"
sentinel), and the value travels to the fragment as `MetalRenderer.pointShadowFar`,
which `finalizeShadowCasters` writes into slot 0 beside the facts it already
carries back. A traced frame renders no cube, leaves it nil, and keeps every
packed field exactly as it was. Instanced and field casters are not in the scan
(their copies are a matrix each, and a field's live in a GPU buffer), so a frame
holding them keeps the old camera-derived value as a floor.

**The bias was measured in the wrong place, and then was the wrong shape.** A
cube texel covers `2·d/N` world units at distance `d` from the light, and the
packed `texelWorld` is that figure taken once, where the camera looks. Used
whole, it under-biases every surface further out. Worse, a surface the light
*grazes* crosses many texels' worth of distance inside one texel, and the 20-tap
PCF reaches three texels out, so the slack has to cover the distance crossed
over that whole spread: it grows as `tan` of the incidence angle, without bound
as the light nears the surface plane. So the fragment now works its own texel out
from its own distance (`OLLIN_POINT_SHADOW_RESOLUTION` moved into the shared
header for it, retiring the two Swift copies), and scales the *depth* bias by
that tangent, capped at 12. Only the depth bias is scaled: moving the sample is
what notches a box's bottom corners, and a surface square on to the light has a
tangent of zero and the bias it always had. Past the far plane a receiver reads
**lit**, which is the envelope the 2D casters already state for a receiver
outside their fitted frustum.

Measured against the traced render of the same scene, the fixed cube path sits
at a mean 0.34 to 0.40 per channel, where the old one put the shadow on the
wrong side and combed the floor. On this machine the whole path is inert, so all
of it is snapshot- and figure-neutral.

The lit mesh loop resolves a light's caster slot by scanning the list, and
`cs == 0` gates the primary-only terms (`rtShadow`, `fieldShadow`, and the
marched-field multiplier). A marched field is in no map, so a field carrier
takes the primary caster alone. Facts the renderer settles after
`makeLighting` (the flip to the traced path, the ray or tap counts, whether a
map was produced at all) are carried back into slot 0 by
`finalizeShadowCasters`, which also budgets taps for the extra casters and
drops them when no map was rendered.

**Per-light opt-out, and why the presets use it.** `Light.castsShadow`
(default true, with a `castsShadow:` argument on every factory and bare call
and a chainable `castingShadow(_:)`) is how a light declines. Every curated
`LightingPreset` sets it false on its fill and rim lights. That is not
housekeeping: a fill exists to open the shadow side, so a shadow of its own
works against the rig, and without the flag every preset would suddenly cast
two or three shadows and pay a depth pass for each. It is also the measured
answer, since it is what returns the Guide's 26 three-dimensional figures to
their committed pixels.

**Area (rect/disk) casters shadow from the panel's real extent.** The caster
search reaches them after the punctual kinds (directional → spot → point →
rect/disk), so every existing scene keeps its caster. On an RT device each lit
pixel traces visibility rays to deterministic points spread over the panel's
actual surface (`shadowFactorRayTracedArea`: the golden-angle Vogel disk laid
in a disk's own plane; antithetic ±p pairs of the R2 low-discrepancy lattice
over a rect, so any sample budget stays mean-centered on the panel), which
also reproduces a strip's anisotropic penumbra. Elsewhere the panel renders a
spot-style perspective map from its center, aimed at the camera target (a
panel lights its whole front hemisphere, so unlike a spot there is no cone to
aim by; the same framing proxy as the directional box) with the frustum fit to
the scene sphere, and the PCSS penumbra radius is the panel's half-extent in
map texels (a disk's radius; a rect's geometric-mean half-extent, so a thin
strip doesn't blur like a square of its long side), capped at 40 texels where
the fixed tap budget would spread into dither. `shadowSoftness` stays the one
dial across every caster: for an area caster it scales the *physical* extent
(0 → the hard legacy 3×3 / all rays at the center, 0.5 default → the true
size, 1 → twice), packed CPU-side into `shadowDepthA` for the map path and
swapped into `shadowDepthB` when the renderer flips the caster to the traced
path (`shadowKind` 2), since the map path needs that slot for the perspective
linearization term. The shadow dims the LTC integrals inside the area branch
of `meshLitColor` (both `diffI`/`specI`, so every shading model and the SSS
back term dim consistently); a no-caster frame multiplies by exactly 1.0 and
stays byte-identical. Tubes never cast: radial emission has no facing axis to
render a map from, and the caster search skips them. The traced path is
pinned by the RT-gated `area-shadows` snapshot; the map path (unreachable on
an RT machine) by the path-agnostic `AreaShadowRenderProbes`, which compare
castShadows()-on/off renders so the per-pixel difference isolates the shadow.

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

### Glass: transmission and refraction

The transmissive material rides the PBR finish (shading model 3), not a new
model: `transmission` / `ior` / `thickness` / `attenuation` ride the
`OllinMaterial` tail, every new branch gates on `transmission > 0`, and the
normal-incidence Fresnel moved from a hard-coded `0.04` to a CPU-packed
`mat.f0` that packs the *exact literal* `0.04` at the default IOR 1.5 (the
computed `((0.5)/(2.5))^2` rounds to a different float; `MaterialTests` pins
it), so every pre-glass frame is bit-identical. The moving parts:

- **The transmitted lobe replaces the diffuse one** (the glTF
  `KHR_materials_transmission` form): in `ollin_pbr_ibl_ambient` the diffuse
  part becomes `mix(kD·diffuse, Ft·(1−E)·base, transmission·(1−metallic))`
  where `E = F0·brdf.x + brdf.y` is the specular lobe's share of the energy,
  and `meshLitColor`'s punctual + LTC diffuse scale by the same `diffKeep`
  factor. `diffKeep` engages **only when `iblEnabled` is up**: with no
  environment there is nothing to transmit, so transmission is inert and the
  material shades as the plain dielectric (pinned byte-equal by
  `GlassRenderProbes.withoutAnEnvironmentGlassIsAPlainDielectric`).
- **The base path is environment refraction** (`ollin_env_refraction`, all
  GPUs): refract at entry; a solid (`thickness > 0`) marches the analytic
  interior span `thickness · −(N·R)` and refracts back out through a
  curvature-blended exit normal (`normalize((N·R)·rr − n·0.5)`, the published
  rasterizer approximation of the unseen far interface), a thin wall exits
  parallel to the view ray; the sample reuses the GGX-prefiltered mips at the
  material's roughness with the blur fading as IOR → 1 (`mix(rough, 0,
  saturate(3/ior − 2))`); Beer-Lambert absorption is `pow(attColor, span /
  attDistance)` with the attenuation color floored at 1e-4 per channel on the
  CPU (a zero channel would hit `pow(0, 0)` NaNs under fast math).
- **The RT upgrade rides the same `rayTracedReflections()` opt-in**, one
  switch upgrading mirrors and glass together. `ollin_rt_refraction` traces the
  *refracted* entry ray through the same accel: a solid's interior leg
  finding a **back face** found its real exit (refract out there and trace on;
  the traced interior span feeds Beer-Lambert exactly), a **front face** inside
  is an embedded object seen through one interface (shade it where it is); a
  thin wall continues the straight view ray, hopping through its own shell's
  back faces (bounded at 4 hops). Total internal reflection at an exit carries
  straight on (a bounded fudge; a real internal bounce recurses without
  bound). Hits shade through `ollin_rt_hit_radiance`, the hit shade *extracted
  from* `ollin_rt_reflection_trace` so mirror and glass shading cannot drift.
- **A body the accel structure doesn't hold supplies its own far interface.**
  `buildShadowAccel` admits solid `.mesh3D` batches only, so a raymarched field
  owns no triangle the interior leg could hit: the walk would take whatever
  stands *behind* the field for its exit and absorb over that entire run. Green
  glass on a 0.95-radius sphere read G137 as a field against G189 as the mesh,
  and slid to G59 when the slab behind it moved twice as far away, which is how
  the mechanism was isolated (the mesh never budged, and turning absorption off
  made the two byte-equal, so absorption was the only term involved). The fix
  keeps the exit where the geometry is known: the raymarch fragment refracts the
  same entry leg, sphere-traces the *inside* of its own field until the surface
  comes back (`ollin_sdf3d_interior_exit`, stepping by `-d` since the field reads
  negative in there), and hands the exit point plus its inward-facing normal down
  through `ollin_pbr_ibl_ambient` into `ollin_rt_refraction`. Three properties
  make it safe: the supplied exit stands in **only while it is nearer than any
  traced hit**, so a mesh embedded in a glass field still shows through the entry
  interface; the mesh path passes a zero `bodyExit` and takes the traced branch
  **byte-identically**; and only a transmissive solid under a live trace pays for
  the extra march. The environment path never had the defect, its span being
  analytic on both shapes.
- **The interior march starts *on* the surface, and both naive readings of that
  are wrong.** The first draft crawled (the sphere-trace step *is* the interior
  distance, which is ~0 at the entry) and tested nearness to decide it was out
  (the distance is within an epsilon of zero from either side). What actually
  decides the test there is the sub-epsilon residual the outward march happens to
  leave behind, and that residual **bands radially**, since the outward march's own
  step sequence does. The body came out printed in fine concentric rings, each ring
  a radius where the residual tipped the first test the other way and the march
  returned nothing. So the march now carries a **floor under every step**, which is
  what keeps it moving, and counts the exit **only once the ray has really been
  inside**; it returns a distance rather than a failure, because the caller's
  fallback is the very mistake the march exists to prevent, and a budget that runs
  out answers with what it marched, bounded by the body's own extent. **The rings
  were invisible to a patch mean** (the centre patch matched the mesh to 0.6/255
  through them) and only a per-pixel comparison sees them, which is why the probe
  compares the two bodies pixel by pixel over a **disc that stops a few pixels
  short of the rim** rather than a square: a square's corners reach the
  silhouette, where the outermost pixels legitimately differ (the AA models
  disagree, multisampled against analytic, and the field's single inline
  reflection ray meets the rim-compressed mirror image a mesh's supersampled
  deferred layer averages; the rim's own shading agreement is pinned separately
  by `aFieldRimShadesLikeAMeshRim`, see *Deferred ray-traced reflection AA*).
  `GlassRenderProbes.aGlassFieldAbsorbsLikeAGlassMesh` pins the
  agreement, the independence from what stands behind, and the absence of banding
  (verified red against the unfixed walk *and* against the ringing march).
- **Documented v1 envelope:** the refraction trace is inline (single-ray) even
  when reflections run deferred; refracted content is usually minified, so
  aliasing stays acceptable where a mirror's would not (revisit if glass
  shimmer shows up in motion). A traced hit does not re-enter transmission, so
  glass seen in a mirror or through other glass reads as an opaque shiny body,
  and glass still casts an opaque shadow (a transmission-aware shadow term is
  a follow-up). Roughness on the traced path blends toward the env-refraction
  sample by the reflection wrapper's constants (a single ray cannot frost).

### Clearcoat and sheen

The two layered lobes on the physically-based finish (`Material.clearcoat` /
`Material.sheen`), pure shading additions in `meshLitColor` + `ollin_pbr_ibl_ambient`
with no new pipeline. Both branch on their packed fields, so a material carrying
neither shades byte-identically (verified against the whole snapshot suite).

- **Clear coat** is a second Cook-Torrance lobe: GGX at the coat's own perceptual
  roughness, the cheap Kelemen visibility `1/(4·LoH²)`, Schlick Fresnel at a fixed
  0.04 (an IOR-1.5 lacquer film). The base's direct + ambient terms scale by
  `1 − Fc` (the energy the film reflects away), and the base's F0 re-derives for a
  coat-to-surface interface, `((1 − 5√f0)/(5 − √f0))²` blended by the coat
  intensity. **That remap sends the default dielectric 0.04 to exactly 0** (an
  IOR-1.5 base under an IOR-1.5 film has no interface), which is physically right
  and practically surprising: a fully-coated rough dielectric *loses* its broad
  base specular and gains a narrow film highlight, so its disc-mean brightness
  goes *down*. The render probes compare **peak** brightness for exactly this
  reason (the first mean-based drafts failed on correct physics).
- **Sheen** is the inverted-alpha sine distribution ("Charlie") with the cloth
  visibility denominator, no Fresnel, tinted directly by the sheen color (strength
  premultiplied into the packed rgb; roughness in w). Layering follows the
  directional-albedo scaling: the base scales by `1 − max(tint)·E(NoV, roughness)`
  and the lobe itself rides E in the ambient, which is what keeps a strong white
  sheen from adding energy out of nowhere.
- **The sheen LUT** carries E: there is no closed form, so it bakes by numerical
  integration (uniform hemisphere, 1024 samples) into a 64² `r16Float` texture,
  `ollin_ibl_sheen_lut` in the IBL bake family. It is environment-independent but
  needed under plain lights too, so it triggers off the frame's *materials* rather
  than the environment bake: `ensureSheenLUT` sits beside the three `resolveIBL`
  call sites and scans the drawer's batches for a nonzero packed sheen color. It
  binds at **fragment texture 12 on every `meshLitColor` carrier** (solid /
  textured / raymarch / half-res), stand-in strip otherwise, the LTC/IES/cookie
  discipline.
- **Area lights:** the coat runs a second LTC fetch + integral at the coat
  roughness (its norm + average-Fresnel split evaluated at F0 0.04), gated so a
  coatless material pays nothing; the sheen lobe is too broad for the GGX-fitted
  tables, so it takes `E · diffI`: the directional albedo times the panel's
  exact cosine integral, honest because a near-Lambertian lobe's response to a
  panel *is* its albedo times the cosine-weighted solid angle.
- **Ray-traced reflections:** the coat's ambient gather reuses the frame's traced
  radiance (same mirror direction; the coat is usually the smoother lobe, so the
  traced scene beats a second prefiltered sample; no second trace is cast). Sheen
  keeps the prefiltered environment sample under RT (a wide lobe's honest
  integral). The RT *hit* shade carries neither lobe (per-vertex data has no
  room for them), so a coated or sheened surface seen in a mirror shades as its
  base material there, the glass-in-glass envelope's sibling.

### Subsurface scattering (the separable diffusion)

`Material.scattering` / `scatteringRadius` / `scatteringColor` (presets `.skin(radius:)`
/ `.marble(radius:)`) is real subsurface scattering as a screen-space diffusion,
written from the published separable-subsurface-scattering technique (credited in
`ATTRIBUTION.md`): the exact 2D diffusion kernel is well approximated by two 1D
convolutions, so the whole effect is two fullscreen passes over the linear
pre-tonemap frame, inserted between the geometry resolve and the whole-frame
`postProcess` filters in every render path (live, headless/export, and the GPU
benchmark; the accumulation surface and the texture hand-off keep their existing
no-deferred-pass envelope). The stage is content-gated: a frame with no scattering
material returns the resolved texture untouched and encodes nothing.

- **The kernel is built on the CPU** (`MetalRenderer.scatterKernel`, nonisolated,
  cached by quantized profile): 25 taps whose offsets are importance-distributed
  (sign-kept o² over ±3 profile units), each weighted by the trapezoidal span it
  covers times the diffusion profile there. The profile is the published
  sum-of-Gaussians fit of measured skin reflectance, one channel's curve reused
  for all three and stretched per channel by `scatteringColor` (which is what
  makes one curve serve skin, marble, or a green jade); the fit's narrowest term
  is direct bounce, accounted by `scattering`, so it's dropped. Weights normalize
  to unit sum per channel, then the un-scattered share folds back into the center
  tap: energy-conserving at any strength, and *exactly* the identity at strength
  0. Pure function of (falloff, strength) → deterministic exports and a cache
  that never invalidates. Up to 8 distinct profiles ride one frame's params rows
  (extras reuse the last, noted once).
- **The mask pass** is a dedicated mesh re-encode (the `encodeMeshNormals` /
  reflection-G-buffer pattern: never a second attachment on the shared geometry
  pass), single-sample, writing (projected step in uv units of the height axis,
  mark, view-space depth, profile index) with its **own depth**, so every solid
  mesh rasterizes and an occluder in front of a scattering surface suppresses it.
  Its pipeline (`isScatterMask`) has **blending off**, load-bearing: the alpha
  channel carries the profile *index*, which `.normal` blending would multiply
  into the color channels (a profile-0 surface would write rgb × 0). Matcaps
  occlude but never scatter (they bypass lighting and material entirely);
  wireframes and the grid chrome are skipped, matching the sibling passes.
- **The blur** (`ollin_sss_blur`, one fragment, two encodes with the direction in
  the params) early-outs on unmarked pixels, so within a scattering frame every
  non-scattering pixel is **bit-exact** (a linear sample at an exact texel center
  is the texel; pinned by the probes, not a tolerance). The step is the mask's
  projected radius over 3 (the kernel offsets span ±3), the horizontal pass
  divided by the aspect; ortho projections skip the depth division (detected by
  `projection[3][3] == 1`, exact for ortho).
- **The depth-gap guard is measured against the scattering radius, not a
  screen-space constant.** The reference implementation's guard
  (`300 · dtpw · width · Δd`) is *proportional* to the radius, tuned for a radius
  around 1% of the object: at any larger radius it saturates on the surface's own
  curvature and silently turns the whole blur off (the first probe render showed
  a max channel diff of 5/255, a real bug). Ollin's guard un-projects the mask's
  step back to a world-space radius (`2 · step · wFactor / P11`) and cuts a tap
  fully at four radii of depth gap, which is exactly the reference's behavior *at
  its own scale* made scale-invariant. Background taps read the cleared depth 0,
  a hard gap by construction, so background never bleeds into a surface; the blur
  writes only marked pixels, so the glow never leaks past the silhouette either.
- **`OllinMaterial` grew 192 → 224** (`scatter` float4: falloff ratios raw, not
  linearized, since they're relative widths, floored 0.001 against the kernel's
  per-channel divide; radius in w; plus `scatterStrength` and explicit tail
  pads). The lit mesh fragments read the fields only inside the transmittance
  branch below (gated on `scatterStrength > 0`, so every existing shading path
  is untouched); the batch's `finish` is how the mask pass and the
  kernel collection see them, and the existing material-change batch break means
  no new break rule.
- **The transmittance term** (the translucency half: light through a thin backlit
  body, written from the published shadow-map translucency technique, credited in
  `ATTRIBUTION.md`) lives in `meshLitColor`'s punctual loop, not the blur: only
  the shadow-casting light transmits, because its depth is the one thickness
  gauge the frame has. Thickness per caster kind: a **2D map** (directional/spot)
  projects the receiver shrunk two map texels along its normal (the silhouette
  fix, made scale-invariant the way the shadow biases are) and **gathers the
  transmittance over the diffusion's own entry footprint** (`transmitGather2D`;
  the light-space gathering of the translucent-shadow-maps work, credited in
  `ATTRIBUTION.md`): a fixed 13-tap equal-area spiral spread laterally in
  *profile units* (one unit = a third of the scattering radius, taps out to 2.4),
  each tap's occluder depth read through the manual bilinear whose corners
  linearize *before* blending (`transmitOccluderDistance`; the plain sampler is
  nearest, and a nearest tap terraces a steep thickness gradient into texel
  bands; blending perspective depths first bends the ramp; depths convert to
  world via `OllinLighting.shadowLinearize`, the caster projection's
  [2][2]/[3][2] packed by `makeLighting`, of which the PCSS ratio needs only
  [2][2] and an absolute distance both), and the same five Gaussians as the slab
  profile summed over each tap's 3D through-body path (depth² + lateral², both
  per-channel falloff-stretched), **normalized per Gaussian so a
  constant-thickness slab reduces exactly to the slab form** (which is why the
  flat-slab probes and snapshots did not move). The gather exists because a
  single-tap read **re-exposes the caster mesh's own tessellation** at grazing
  light angles: the smooth interpolated normal hides the facets in every N·L
  term, but a depth *difference* through the steep transmit exponential does
  not, and near the light-space silhouette the facet-truth error is amplified to
  a visible fraction of the scattering radius (the 2026-08-11 audit's
  "transmittance stripes", first misattributed to shadow-texel quantization
  until a 3x-tessellated twin erased the bands while the texel math said 0.6
  px/texel). Two details are load-bearing: the footprint is sized by the
  **scattering radius in world units, never in map texels** (a texel-sized
  filter cannot span a facet), and the spiral **rotates per point by a
  world-anchored hash** at a fraction of the footprint scale (13 taps quadrature
  a depth field with facet steps in it, and a fixed spiral leaves that error
  spatially structured, a blocky moire against the tessellation; the rotation
  turns it into fine surface-glued noise the screen-space diffusion blur
  absorbs, and world-anchoring keeps it still under a static camera and
  identical between two renders of one frame). Measured on the distilled audit
  scene (row-mean detrended residual over the terminator band): 1.36 mean / 3.8
  peak striped, 0.44 / 1.6 gathered, a 96x48-tessellated reference at 0.15-0.33
  either way, pinned red-first by `grazingLightLeavesTheTerminatorSmooth`. What
  remains after the gather is the polyhedron's *own* translucency at the
  profile's genuine lateral resolution: the narrow Gaussians (the thin-body
  transport) have footprints a fraction of the scattering radius and cannot
  smooth entry structure wider than themselves, so a coarsely faceted body under
  a tight radius keeps soft facet shading, and the answer there is tessellation
  (the fine-tessellated twin is the reference, not a wider filter). A
  **cube** caster subtracts its stored linear distance; a **ray-traced point**
  caster traces one closest-hit ray from just inside the surface
  (`meshRTThickness`, computed by the solid/textured fragments under the same
  material gate so a non-scattering surface never pays it); both keep the single
  read (the audit measured the 2D path; the same gather ports if either shows
  the exposure). The profile `ollin_sss_transmit` is the **closed-form
  slab integral of the same Gaussian sum the diffusion kernel tabulates**
  (integrating each normalized 2D Gaussian over the plane at depth s leaves
  w·e^(−s²/2v)), kept in sync with `scatterKernel` by hand, with world thickness
  entering in the kernel's own units (×3/radius, the ±3-unit span). The
  irradiance is the paper's reversed-normal wrap `max(0.3 + dot(−N, L), 0)`, so
  lit faces take nothing (no double count with the diffuse) and the handoff
  crosses the terminator smoothly. Three placements are load-bearing: the term
  reads the **pre-shadow attenuation** (a backlit surface stands in its own
  body's shadow, and dimming by that factor would erase exactly the light being
  transported) while still riding the cone gate and the shaped/tinted light
  copy; it lands **before the screen-space blur**, which diffuses it together
  with the reflectance (the published treatment); and it multiplies by
  `scatterStrength`, the PBR metallic kill, and `diffKeep`, so every gate that
  makes the blur inert makes the term inert too (no caster, strength 0, a field
  carrier's own `fieldShadow`, an area-panel caster: each path byte-identical,
  probe- and suite-pinned). One practical note: the transmitted rim on a deep
  body is a tight bright feature, so an overdriven radius prints the blur's tap
  comb around it exactly as it does around a tight highlight; at documented
  radii it cannot show (measured on the slab probe: ripple period matched the
  kernel's outer-tap spacing, and an honest radius flattened it to the dither
  floor).
- **Envelope:** solid and textured meshes on the main canvas. A mesh drawn into a
  render target and a raymarched SDF field each degrade to their plain shading
  with a one-time note (the RT-reflections main-canvas precedent); 2D content
  drawn *over* a scattering surface in the same frame sits on marked pixels and
  is blurred with them (the reference approach shares this; a scattering frame
  is a 3D scene in practice). Specular on a scattering surface is blurred with
  the diffuse: the reference *demo* actually renders speculars to a separate
  target and re-adds them after the blur, and that separation is the known
  upgrade here. Its visible form: a radius several times the documented
  guidance, on a polished surface with a tight grazing highlight (a huge HDR
  near-delta), prints the kernel's 25 discrete taps as a faint replica comb
  around the highlight. At documented radii the tap gaps stay near a pixel and
  it cannot show (probed live at 1.6K; the first example draft overdrove its
  radii 3 to 5x and combed).

---

## Normal mapping (the surface-map tier's foundation)

The first slice of the advanced-materials arc: a tangent-space normal map on the
textured-mesh path, plus the tangent machinery every later surface map (parallax
occlusion, detail maps) rides.

**The pipeline is a twin, not a branch.** `ollin_mesh_nm_vertex` /
`ollin_mesh_nm_fragment` mirror the textured pair verbatim with the perturbation
added, selected by a `normalMapped` variant on the mesh `PipelineKey`. The shipped
textured functions are untouched, so unmapped textured frames are byte-identical
*by construction* rather than by a verified gate (the fast-math codegen rule:
growing a shipped function's control flow re-contracts its expressions and moves
ulps; a twin can't). The cost is ~40 duplicated fragment lines, taken knowingly.

**The vertex tangent rides the spare 8 bytes.** `OllinMeshVertex` had 8 bytes of
tail padding reserved since the 3D work; the tangent packs into it as four
Float16s (`OllinHalf4`: `half4` under `__METAL_VERSION__`, `simd_ushort4` of bit
patterns on the CPU side), so the stride stays 64 and every existing path is
layout-identical. Direction xyz + handedness w, world-space (the model's linear
part baked in at `drawMesh`, like a surface direction, not the normal's
inverse-transpose), renormalized in the fragment after interpolation.

**Tangents are MikkTSpace, vendored, with the glTF sign.** `External/CMikkTSpace`
(zlib-style notice) is the reference generator the glTF spec names and normal-map
bakers target; matching its exact basis is the point, which is why it's bundled
rather than reimplemented. `Mesh.generatingTangents()` runs it over the indexed
mesh through corner callbacks and folds the per-corner results back per vertex by
exact bit equality (MikkTSpace welds internally, so grouped corners return
bit-identical values); a genuine disagreement at a shared vertex (a mirrored-UV
seam) splits it, retargeting the indices, deterministically (face-order
processing, encounter-order appends).

**The handedness sign was measured, not assumed, and it's the arc's one real
finding.** MikkTSpace's raw `fSign` makes `fSign · cross(N, T)` point along
**+∂p/∂v** (down the map image) on every surface (measured on a hand-built quad
and the sphere generator's front, both `b·∂p/∂v ≈ +1`). The glTF spec's normal
maps are explicitly green-up (+Y), which needs the shader bitangent pointing
image-*up*, so the ecosystem stores `w = −fSign` in files (the flip the
mikktspace-wasm / glTF-transform docs warn about). Ollin stores the negation too,
so authored glTF `TANGENT`s pass through unchanged and generated tangents land in
the same convention. Verified three ways: the Khronos `NormalTangentTest` +
`NormalTangentMirrorTest` render with every mirrored-handedness tile matching the
real-geometry reference column; a green-up dome map on a plain generated quad
reads as raised domes; and `MeshTangentTests` pins the green-direction contract
as a render probe. Two dead ends worth remembering: a "missing terminator" chased
for an hour was perspective parallax between spheres at ±x (byte-identical when
re-rendered at matched positions), and a winding-vs-normals-inconsistent
hand-built test quad flips `fSign` and will gaslight any convention probe built
on it.

**The map is data, not color.** `Image.linearTexture(for:)` is the raw-bytes twin
of the color texture cache (`.SRGB: false`, or a plain `.rgba8Unorm` upload for
authored pixels): decoding a normal map's bytes as sRGB color bends every stored
direction (127 would decode to 0.187 and tilt the whole surface by −0.6 along
t+b). Separate cache slot, so one `Image` can serve both reads.

**Gates.** `MeshMaterial.normalScale` doubles as the off switch and the per-batch
gate: the drawer sets the finish uniform's `normalScale` (a claimed
`OllinMaterial` tail pad) only after verifying aligned uvs *and* tangents, encode
keys the twin pipeline off it, and 0 routes down the plain textured pipeline
byte-identically (probe-pinned). A map attached without its basis degrades
honestly: geometric normals plus a one-time note. Shading uses the bent normal
everywhere (all shading models, punctual + area lights, IBL, GI); the ray/offset
machinery (field shadows, traced shadows, transmittance thickness) keeps the
geometric normal, a map being surface detail, not surface position. Skinned
meshes pose tangents with the blended joint matrix's linear part, so relief
stays put on a bent limb.

---

## The PBR map set (surface maps)

The second slice of the advanced-materials arc: metallic-roughness, occlusion,
and emissive maps on `MeshMaterial`, sampled per pixel on the mesh path. One
pipeline serves the whole set (`ollin_mesh_maps_fragment`, sharing
`ollin_mesh_nm_vertex`), with the normal-map bend folded in behind its own
`normalScale` gate, so map combinations don't multiply pipelines.

**Per-pixel metallic/roughness forced the tail question, and the answer is the
biggest hand-synced twin in the codebase.** `meshLitColor` (~470 lines) and
`ollin_pbr_ibl_ambient` (~140) read `mat.metallic`/`mat.roughness` from the
per-batch constant buffer at a dozen sites spread through the LTC area
lights, the punctual Cook-Torrance branch, the transmission diffKeep, and the
IBL split-sum; a per-pixel value cannot ride a `constant` reference, and growing
the shipped functions with override parameters is the fast-math re-contract
gamble the codegen rule exists to forbid. So `meshLitColorMapped` and
`ollin_pbr_ibl_ambient_mapped` are *mechanical substitution copies*: the body
verbatim, every `mat.metallic` read replaced by `pxMetal`, every
`clamp((float)mat.roughness, …)` by `clamp(pxRough, …)`, and the flat ambient
terms scaled by `pxAO`. The sync rule is stated at both definitions (edit the
original, re-copy, re-substitute) and the copies were made by scripted
extraction + diff review, not retyping. The cost is real and was taken
knowingly: the alternative (parameterizing the shipped tail) risks ulp movement
across every 3D frame ever rendered, and the aerial/GI precedents both paid the
twin price for the same reason.

**Composition semantics are glTF's.** The sampled channels *multiply* factors:
`px = finish(material(_:)) × MeshMaterial.metallic/roughness × map`, with the
drawer folding the mesh material's own factors into the batch finish only when
the map is bound (`mrGate`), so a loaded file's `metallicFactor × texture`
intent survives under the sketch's `material(.physicallyBased(metallic: 1,
roughness: 1))` and lower finish values stay an artistic scale on top.
Occlusion is indirect-only (`1 + strength·(ao − 1)` on the flat ambient inside
the twin tail, and on the IBL ambient / GI bounce / flat-IBL adds at the
fragment level; direct light untouched, the spec's rule, probe-pinned by the
direct-light byte-equality counterfactual). Emissive is `factor × sRGB map`,
added after all lighting and before the atmosphere, so fog veils emission like
any other surface radiance; a constant factor with no map routes down the same
pipeline against a white stand-in, which is also how a black emissive factor
with an emissive texture correctly emits nothing (the glTF default). The gates
ride the finish uniform like `normalScale` (`mrGate`, `occlusionStrength`, and
an `emissive` float4 claiming the last two tail pads plus one appended row),
zero on every other batch, so unmapped frames keep their exact codegen by
construction.

**Sampling color spaces split by meaning.** Metallic-roughness and occlusion
are data (`Image.linearTexture(for:)`, the raw-bytes cache slot the normal map
introduced); emissive is color (`texture(for:)`, sRGB-decoded). All four map
slots are always bound on the maps pipeline (real texture or the white
stand-in), the gates keeping unbound slots unsampled and validation happy.

**USD reads the set through connections, with a repack fallback.** A preview
surface's `metallic`/`roughness`/`occlusion` inputs resolve to `UsdUVTexture`
taps (image + the tapped output channel + the texture's own scale/bias). Taps
already in the standard ORM layout (one image, roughness at g, metallic at b)
reuse the image directly (the `USDAssetStore` now caches decoded images by
authored path precisely so two taps at one file compare `===`), and anything
else repacks channel-by-channel into that layout at load (untapped channels
white, the multiply identity, so an authored constant factor still carries).
Factors round-trip through the taps' per-channel `scale`, occlusion strength
through scale s / bias 1 − s on its channel (exactly `1 + s·(ao − 1)`), and the
normal map's strength through its decode: scale (2s, 2s, 2, 1) / bias (−s, −s,
−1, 0) is the exact spelling of `s·(2c − 1)` on x/y, so `normalScale` survives
a round trip losslessly and the plain (2, 2, 2, 1) decode reads back as 1. USD
normal maps also fold in here (there is no authored-tangent attribute in USD),
generating the MikkTSpace basis after the skinning pass with glTF's
vertex-split guard: a generation that would split a mirrored-UV seam is
accepted only on nodes with nothing (skin/morph/part arrays) aligned to the
vertex order. The writer mirrors every one of these encodings, the reader's
stated inverse, and `usdchecker --arkit` accepts a package carrying the full
set (test-pinned).

**Envelope.** The maps live on the primary surface: a reflection hit still
shades from the per-vertex metalness/roughness the `OllinMeshVertex` w slots
carry (constant per batch), and emission isn't seen in mirrors, the same
per-hit envelope every surface map has. Matcap and wireframe ignore the set
(one bakes its lighting, the other draws edges).

---

## Height maps: parallax occlusion and displacement

The third slice of the advanced-materials arc: a height map on `MeshMaterial`
(`heightTexture`/`heightScale`), read two ways from one datum (**white is the
authored surface, darker carves in below it**), so the shading fake and the
real geometry agree about where the relief lives.

**Parallax occlusion rides the maps fragment, not a new twin.** The march
lives in `ollin_parallax_uv` and a `mat.parallax`-gated branch at the top of
`ollin_mesh_maps_fragment`; that fragment is slice-2 code, exempt from the
verbatim rule (its own header says it may branch freely), so no third copy of
the shading tail was needed. The shifted uv feeds *every* map sample below it
(base color, normal, metallic-roughness, occlusion, emissive), which is the
whole point: the maps move together the way a carved surface's would. The
drawer routes a height-mapped mesh to the surface-mapped pipeline
(`usesSurfaceMaps` gained `parallax > 0`), verifies uvs + tangents like the
normal map (degrading honestly without them), and packs `finish.parallax`
only then, so the gate doubles as the encode and shader switch and mapless
frames keep their codegen. Verified empirically after the growth: the full
snapshot suite holds unrecorded and a guide-figures run has zero churn, so
the branch didn't move ulps on gate-off frames. Texture slot 21, sampled as
data (`linearTexture`), white stand-in otherwise.

**The march is the published two-phase intersection.** A linear search steps
the eye ray down through the normalized relief volume (8…32 layers by view
angle, more at grazing where each step crosses more texels), then one secant
step treats the field between the last two samples as a straight line and
lands the crossing. Height samples inside the loop use explicit `level(0)`:
the loop's exit varies per pixel, where implicit derivatives are undefined
(the data texture carries no mips anyway). A white entry sample returns the
uv untouched (the exact null, probe-pinned byte-identical on the same
pipeline), and the `1/e.z` stretch is floored at 0.1 so grazing rays smear
boundedly (the technique's silhouette envelope, documented rather than
hidden).

**The uv step's signs are the tangent-frame fact from slice 1, derived rather
than assumed.** With the eye projected onto the frame as
`e = (V·T, V·B, V·N)`, one unit of relief depth shifts the sample by
`scale/e.z · (−e.x, +e.y)`: `u` *against* the eye (a recess shows its far
side), and `v` with the **opposite** sign because the stored-handedness
bitangent `w·cross(N, T)` points up the map image while `v` grows down it,
the same green-up convention the normal map measured. The direction probe
pins both axes against a flat control (a recessed dot must shift toward the
camera on screen), and a sign-flip sabotage fails each axis independently.

**Parallax is shading only, and the tests state it.** Depth, silhouettes,
shadow rays, transmittance thickness, and reflections all keep the flat
surface; `parallaxNeverMovesTheSilhouette` pins the coverage mask equal
against the flat control, which is also the teaching contrast with
displacement.

**Displacement is the weld-aware CPU sibling.** `Mesh.displaced(by:scale:)`
samples the same image at the uvs (clamp-to-edge bilinear over the red
channel, mirroring the GPU sampler) and moves vertices along averaged
normals by `(h − 1) · scale`, white pinned at the authored surface, the
shared datum. It works per *welded position group* (the `MeshWelding` seam):
one averaged normal and one averaged height per group, so the flat-shaded
generators' coincident corners move as one and a uv seam cannot tear the
mesh open (the sabotage that samples per-vertex instead fails the seam
test). Smooth normals recompute over the welded displaced surface and
republish per original vertex; a carried tangent basis regenerates
(MikkTSpace) for the new shape.

**USD carries the map; glTF cannot.** glTF core and the ratified
`KHR_materials_*` extensions have no height-map slot, so the map is
Ollin-authored API on that side. The USD writer feeds the preview surface's
`displacement` input from a `UsdUVTexture` tap authored as scale `s` / bias
`−s`, the exact spelling of `s·(h − 1)`, so a renderer that really
displaces carves the same relief, and the reader recovers
`heightScale` from the tap's channel scale (a lossless round trip,
validator-checked with `usdchecker --arkit`; a constant, unconnected
`displacement` is a uniform offset with no relief in it and stays unread).
The reader also generates tangents for a displacement-connected material,
the normal-map rule.

---

## Triplanar projection

The fourth slice of the advanced-materials arc: texture for meshes that have
no uvs at all (a marched isosurface or metaball skin, a grown or reconstructed
shell, a subdivision result). The base texture is projected flat along each of
the three world axes and the three reads blend by how squarely the surface
faces each axis; `MeshMaterial.triplanarScale` is the tile's world size, and
`Mesh.triplanarTextured(_:normal:scale:)` is the whole attach (no uvs, no
tangents, none generated).

**It rides the surface-mapped fragment, not a new twin.** The projection lives
in `ollin_triplanar_surface` and a `mat.triplanar`-gated branch at the top of
`ollin_mesh_maps_fragment`; that fragment is slice-2 code, exempt from the
verbatim rule, and the exemption was re-verified empirically after this growth
(the full snapshot suite holds unrecorded and a guide-figures run has zero
churn). The gate packs as tiles per world unit (`1 / triplanarScale`) into the
`OllinMaterial` tail pad the parallax slice left, so the struct's stride is
unchanged and every gate-off batch keeps its exact codegen. The drawer routes
a triplanar mesh to the surface-mapped pipeline unconditionally (no uv or
tangent verification, the point of the feature), forces the uv-mapped gates
off, and refuses the rest of the map set with a one-time note: v1 projects
the base color and the normal map only, and parallax is the technique-level
cut (its march walks one uv space; a triplanar surface has three). The
fragment samples through its own repeat-addressing constexpr sampler, since
the mesh sampler clamps.

**The sampling space is world space, decided rather than inherited.** The
drawer bakes the model matrix into vertex positions CPU-side, so the fragment
only has post-transform `worldPos`; carrying a pre-transform position would
mean widening the 64-byte mesh vertex or a per-batch inverse matrix, and the
world anchor is also the technique's classic behavior (abutting meshes
continue one another's pattern, which the example's box cairn teaches). The
envelope is stated everywhere it matters: a mesh animated through the
transform stack slides through the standing pattern, and
`theProjectionIsAnchoredToTheWorldNotTheMesh` pins it as a test. A `space:`
parameter can widen the API later without breaking it.

**The per-axis frames are derived in Ollin's own conventions, not
transliterated.** Each axis's uv is chosen so the picture reads upright and
unmirrored from either side of the surface: v runs *down* the image (the
top-left texture origin, so both wall projections take `-y` and the top one
takes `+z`), and u flips with the sign of the normal's axis component (the
back of a wall would otherwise mirror). Each frame is right-handed
(right x up = facing), which is what lets the normal map keep its ordinary
green-up decode. The blend weights are the normal's components to the fourth
power, renormalized: a fixed sharpening, so a glancing projection (whose
texture smears into streaks) hands over quickly. The normal map combines per
plane by expressing the geometric normal in the plane's own frame, adding the
map's tangent-plane push onto it, and multiplying the height components (the
whiteout combine), then carrying the result back to world space; a flat map
hands back exactly the geometric normal on every plane, so the bend vanishes
where the map does. One sign here was a probe-caught lesson: the u flip keys
on the *normal's* side, not the viewer's, so the back of a single-sided quad
(interpolated normal still facing away) legitimately mirrors, and the
unmirror test had to author a genuinely back-facing wall, the closed-mesh
case the flip exists for.

**Neither glTF nor USD has a triplanar slot** (checked core + ratified
extensions on one side, the preview-surface schema on the other; it's a
rendering technique, not a material property), so the projection is
Ollin-authored API only, and the spatial exporter's recorder notes that the
projected maps stayed behind and strips them, exporting the surface in its
plain color. `TriplanarTests` pins the feature against counterfactuals (the
no-uv mesh wears the picture, both wall orientations and the top frame read
upright and unmirrored, the 45-degree seam *mixes* the two projections
instead of hard-picking one, the projected normal map pushes lighting along
the frame axes with no tangent basis anywhere, the world anchor, the off
switch, determinism), with the sign flips, the hard-pick, the top-frame v,
and the green direction each sabotage-verified red.

---

## Detail maps

The advanced-materials arc's fifth slice, and the smallest by construction:
a finer second texture pair (`MeshMaterial.detailTexture` /
`detailNormalTexture`, attached by `Mesh.detailMapped(_:normal:scale:strength:)`)
tiled `detailScale` times across the base uv and applied in the surface-mapped
fragment behind its own gates, using the branch-freely exemption the parallax
and triplanar slices established (the shipped textured/nm fragments stay
verbatim; growing `ollin_mesh_maps_fragment` held the whole snapshot suite
unrecorded again).

**The color map is data with 128 gray the neutral.** The sample multiplies the
base as `mix(1, d·2, strength)`; sampled through `linearTexture` (no sRGB
decode), byte 128 reads 0.502 and the multiplier sits within half an 8-bit
step of the identity, so an author's mid-gray from any paint app is the
neutral. Reading it as color would put the neutral at sRGB ~188, which nobody
would guess. (A flat-128 map is therefore *near*-identity, within the
dither's step; the exact byte-identity switch is `strength: 0`, which the
drawer treats as "never raise the gates," routing down the plain textured
pipeline.)

**The normal blends by Reoriented Normal Mapping** (Barré-Brisebois/Hill),
so the fine grain follows the surface the base normal map describes instead
of overwriting it: with the detail flat, the algebra collapses to exactly the
base normal (the identity the overwrite blend fails, and the probe pins).
The detail branch *recomputes* the bent normal from scratch (one redundant
base-map sample, paid only when detail is on) rather than restructuring the
shipped base-normal resolve above it, keeping that code textually untouched.
Strength scales the detail's tangent-space xy before renormalizing, the
standard fade.

**Packing:** `detailScale`/`detailStrength` claimed the two free tail pads
and `detailGates` (color-bound / normal-bound flags) appended one row,
growing `OllinMaterial` 256 → 272 (offsets 248/252/256; the drawer packs
them only for a verified uv-mapped mesh, never with triplanar, so the union
gate is just `detailScale > 0` in `usesSurfaceMaps`). Textures 22 (detail
color) and 23 (detail normal) joined the mesh path, both data reads, white
stand-ins bound when a gate is down. The maps carry no mips, like the whole
mesh texture path, so a very high tile count shimmers under minification:
the documented envelope, with the example keeping its default in the range
the framing shows. Neither glTF nor USD has a detail slot; the spatial
exporter notes-and-strips (the triplanar treatment). `DetailMapTests` pins
tiling-at-scale, the 128 neutral, the RNM identity and composition, and the
strength-0 byte-identity, with the tiling and reorientation
sabotage-verified red.

---

## Projected decals

A picture stamped through an oriented box onto whatever lit mesh surfaces
sit inside it: `Decal` (the LightCookie construction: one 512-square
premultiplied resample at wrap time, content hash, plus the source aspect so
a placement can default its height) and the per-frame `decal(_:at:...)`
placement, capped at `OLLIN_MAX_DECALS` (8) with repeated placements of one
image sharing a texture layer. The CPU builds each box's world→unit-box
transform once (`Drawer.placeDecal`: the light-cookie projector frame with
its measured `right = axis × ref` order, three rows over the box size), so a
fragment pays one row-dot per axis, an inside test, a facing fade, and one
array sample per decal.

**The routing is the design's crux, and it keeps byte-identity by
construction.** The decal loop lives only in the surface-mapped fragment
(the branch-freely one); a frame with placed decals routes *every* lit mesh
batch through that pipeline at encode time (`meshSurfaceMapped ||=
placedDecals present`; wireframe, matcap, and the grid keep their own), so a
plain solid or textured mesh receives a stamp with its map gates all zero,
and a frame with no decals keeps its exact prior routing, no shipped
fragment grown at all. The trade, stated in the docs: a frame *with* decals
shades its plain meshes through the maps fragment (equivalent shading,
different codegen), which is the feature's own envelope, not a regression
surface. Solid meshes ride the nm vertex safely because `OllinMeshVertex()`
zero-fills, so unwritten uv/tangent fields are deterministic.

**In the fragment,** box space is `[-0.5, 0.5]³` with +y the image's top
(the cookie orientation rule; v = 0.5 − p.y), the composite is premultiplied
with one scale on both halves (`base·(1 − s.a·k) + s.rgb·k`, k = opacity ×
fades) so a fade can't fringe the sticker's edge, and two fades guard the
box's own geometry: a facing fade (`smoothstep(0.05, 0.35, N·−axis)`) that
melts the stamp off surfaces edge-on to the projection instead of smearing
it down them, and a depth-end fade over the last tenth of the box so a
receiver near the far planes never hard-clips. The decal list rides its own
small uniform (`OllinDecals`, fragment buffer 2, count-gated) beside a
content-hash-cached `rgba8Unorm_srgb` texture array at texture 24 (the
cookie array's twin, `shapingStandIn()` when empty). Decals modify albedo
only, before the per-pixel surface resolve, so the stamp takes the surface's
finish and every shading model downstream is untouched; reflections show the
undecaled base (the surface-map envelope), and fields/particles/point clouds
sit outside by design. `DecalTests` pins placement against the renderer's
own projection (a drawn marker at the same world position), the depth bound,
the edge-on fade, call-order compositing, the solid-mesh routing, and
transparency, with the translation sign, the depth clip (both guards at
once), the facing fade, and the loop order each sabotage-verified red.

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
keep the inline single-ray trace**: a render target's lighting never sets the
deferred flag, and the main encode hands the `.sdfGroup3D` batches their own copy
of the frame's lighting with `rtReflectionDeferred` cleared. That clearing is
load-bearing, and it was a defect before it was a rule. A field's pixels are not
in the deferred layer (its G-buffer re-encodes mesh batches only), so the
raymarch fragment passes a zero `deferredReflection` stand-in; while the full-res
inline field path still bound the shared lighting with the flag set, the
ambient's deferred branch composited `0 + prefiltered · (1 − 0)` and the traced
reflection silently no-opped for every field in a deferred frame. Nothing
crashed, and no snapshot moved, because no snapshot scene combines a field with
`rayTracedReflections()`. The visible symptom was the silhouette: at grazing
incidence the reflection is most of the picture, and the raw environment there
outshines the traced scene, so a field wore a 3-4px blown-white rim band plus one
dark pixel (the reflection sweeping a dark environment region just past the
body), while the mesh beside it, compositing the traced slab, descended smoothly.
The isolation is worth recording. A patch mean and the snapshot tolerance both
average the band away (it was found by eye); per-pixel scanlines showed it, and
the decisive instrument was a diagnostic return inside `ollin_pbr_ibl_ambient`
itself (NoV, prefiltered luminance, and `brdf.y` written out as RGB), which
showed the mesh and field paths agreeing on every shading input except the
prefiltered radiance, an order of magnitude apart at matched NoV. A 4096²
render settled that the band was not an unaveraged sub-pixel highlight (it kept
its angular width under supersampling), and a no-tracing render settled that it
was not field-specific (the mesh rim blows out identically without tracing:
that band is the honest picture of a hot environment at grazing Fresnel under
the clamp tone map, on either geometry). `GlassRenderProbes.aFieldRimShadesLikeAMeshRim`
pins the fixed rim with an edge-aligned scanline comparison, verified red
against the flag leak. The residual envelope: the rim compresses the mirror
image, so the field's single inline ray can read one bright pixel where the
mesh's supersampled layer averages (noted in `Docs/3D/Combining.md`). Measured against
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

A rough first hit **fades its traced bounce back into that lobe** by
`smoothstep(0.12, 0.55, rough)`, the same rule the inline wrapper applies to the
primary surface. One ray carries no lobe width, so without the fade a matte
floor seen in a mirror, or through glass, showed a crisp reflection of its
surroundings that a direct view of the same floor never shows (the first
sighting was the glass example's `roughness: 0.8` floor mirroring the striped
wall behind it). The miss branch already *is* that lobe, so it needs no blend,
and a hit below the ramp is untouched: the near-mirror snapshots
(`rt-reflections-3d`, `area-reflections`) did not move.

---

## Global illumination (the probe field)

`globalIllumination()` is dynamic diffuse GI in the probe-field form (the DDGI
papers; Techniques list): a grid of irradiance probes over the scene (a fixed
512-probe budget spread per axis by the fitted volume's aspect, see below),
re-traced every frame against the same acceleration structure the
shadows and reflections share, and sampled by every lit carrier as the diffuse
ambient. The pipeline is four fragment passes in `encodeGIPass`
(`MetalRenderer+Targets.swift`), all in `ShaderGI.metal` (a new segment after
ShaderCombine: it reuses Shader3D's RT surface fetch and ShaderEffects'
`PresentOut`), compiled only under `OLLIN_RT_SHADOWS`:

1. **Trace** (`ollin_gi_trace`): one texel per (ray, probe) into a transient
   surfel texture. The texture's first `OLLIN_GI_FIXED_RAYS` (32) columns are
   the **fixed statistics fan**: spherical-Fibonacci directions with *no*
   rotation and no shading (distance and facing only), traced solely for the
   relocation pass. The remaining columns are the radiance fan: a
   spherical-Fibonacci fan under a per-update random rotation (Shoemake
   quaternion from the hashed seed, so an update is a pure function of its
   seed). A radiance hit shades as direct light (Lambert over the punctual
   kinds, the exact LTC diffuse for panels, light shaping applied) *times one
   visibility ray to the casting light* (without that shadow ray, bounce
   light walks through the very wall whose shadow the primary shading draws),
   plus the *previous* update's probe field at the hit (each update deepens
   the bounce by one). A miss samples the environment's radiance times the
   IBL exposure (sky light with occlusion, for free); a backface hit stores
   zero radiance and a **negated, 80%-shortened** distance (the sign is the
   relocation pass's flag, the shortening the leak guard).
2. **Blend irradiance** (`ollin_gi_blend_irradiance`): per octahedral texel,
   the cosine-weighted mean of the radiance fan (`Σ wL / Σ w`, which is
   E/π, the IBL irradiance cube's own convention, so the sample drops into
   `diffuse = irradiance * base` unchanged; the fixed columns are skipped,
   since directions that never rotate would bias the estimate), encoded
   `pow(x, 1/5)` (the 2021 paper's perceptual gamma) and hysteresis-blended
   into the previous atlas. **Live only**, the reference's asymmetric
   temporal-response pair, and the asymmetry is the point: a *darkening* past
   0.25 cuts the hysteresis by 0.75 (a switched-off light must not ghost),
   while a *brightening* whose luminance jumps past 0.10 is rate-limited to a
   quarter step per update. With a sun disc in the fan, one update catches it
   on a couple of rays and the next on none, so a bright spike is estimator
   variance to be absorbed, not news to be trusted; before the rate limit, a
   sky-lit scene's whole field visibly pulsed (a real live-window defect,
   measured at ~25/255 swings on a lit sphere). Headless skips the pair
   entirely: its iterations converge a progressive mean, and either heuristic
   would bias the estimator it is converging.
3. **Blend depth** (`ollin_gi_blend_depth`): mean distance + mean squared
   distance under a power-50 cosine lobe, at 16×16 per probe against the
   irradiance's 8×8, over the radiance columns (same skip).
4. **Relocate** (`ollin_gi_relocate`): per-probe statistics off the surfel
   texture's **fixed columns only**. Every decision below sits on a
   threshold, and a threshold fed the rotating radiance fan flickers: a probe
   hovering near one oscillated between positions every update, and every
   surface its cage touched visibly pulsed (the second real live-window
   defect; freezing relocation was the diagnostic that isolated it). With
   the fixed fan each step is a pure function of (geometry, previous
   offsets), so the walk settles. The branches are the reference's three: a
   probe seeing >25% backfaces steps out through its closest backface; a
   surface-pressed one (closest frontface under 0.3× min spacing) backs away
   along its farthest frontface unless the two oppose; a comfortable one
   drifts back toward its grid anchor by the clearance it can spare, so an
   offset never outlives the geometry that earned it. Proposals commit only
   inside the 0.45-of-spacing ellipsoid (a proposal outside is refused whole,
   never clamped onto the shell); offsets live in a probeCount×1 ping-ponged
   texture the trace and samplers both read.

Sampling (`ollin_gi_sample`, Shader3D, textures 13/14/15 on every lit carrier)
is the papers' four-term weight: trilinear cage × soft backface wrap ×
Chebyshev variance visibility from a self-shadow-biased point
(`(0.2·n + 0.8·ω_o) · 0.75·minSpacing · 0.3`, precomputed into
`giCounts.w`), small weights perceptually crushed; decode is `pow 2.5` per
probe with the blended result squared (interpolation stays in roughly
perceptual space). Where it lands: under an environment the probe sample
*replaces* the irradiance-cube diffuse inside `ollin_pbr_ibl_ambient` and the
flat env ambient (the probes integrate the same environment, occlusion
included); with no environment it adds a GI ambient the scene never had.
Specular is untouched (GI is diffuse; mirrors are the RT reflections' job).

**The volume is auto-fitted and held, and the grid's shape follows it.** The
mesh batches' vertex AABB (folded over the same batch walk the accel build
uses, target-drawn meshes included, so the volume covers exactly what the
probe rays can hit and a scene drawn entirely inside a render target still
gets a field), padded 15% per side, defines the volume. The per-axis probe
counts derive from that volume at fit time (`giAxisCounts`): a binary search
for the smallest near-isotropic spacing whose counts, each clamped to 2…16,
multiply to at most the 512 budget, so a cube resolves to the original 8×8×8
while a flat tabletop spends the same budget as 16×2×16 instead of stacking
unused vertical rows. Counts are held with the volume (probes must not move
for hysteresis to mean anything), the atlases allocate once at the 512-probe
capacity so a refit never reallocates, and the sampler/blend shaders were
grid-shape-generic from the start (`giCounts.xyz` drives all index math).
Live, the volume *holds* until the raw bounds escape it or shrink well inside,
and a refit restarts the field. Headless/export ignores the held state
entirely: the volume refits from the frame's own bounds and
`resolveGIIterations()` whole trace+blend+relocate iterations (8/12/16 by
tier) run from scratch with a progressive-mean hysteresis (`i/(i+1)`) and
seed = the iteration index, so a frame is a pure function of itself:
byte-stable snapshots (`gi-3d`), flicker-free video, and the frame-grab
re-render can't double-step the live accumulation (`statefulEncodeIsRepeat`
guards the live path like the other stateful passes; `beginStatefulEncode`
runs the frame-scoped reset ahead of the GI pass, which now precedes the
effect-target encode so layers sample the same update). Rays per probe
resolve per GPU like the shadow rays (hardware RT 64/96/192, software
32/64/96), through the sketch's `globalIlluminationQuality(_:)` tier (a
persistent `RenderQuality` setting, `.default` following the automatic
live/export split; the headless iteration count rides the same tier). The
grid deliberately does *not* ride the tier: more rays refine the same
estimator, but a tier-driven grid would move the probes themselves, and
`.default`'s automatic export lift would then light an export differently
from the live window.

Three bugs from the first render session, each now a pinned rule:

- **Never `mix` toward an unread history.** The first update ran hysteresis 0
  against the uninitialized previous atlas, and `mix(fresh, old, 0)` is
  `fresh + 0·(old − fresh)`: NaN wherever the garbage was NaN. The whole
  field poisoned in two channels (the pool read green); the blends now never
  read `previous` without history.
- **Cap the visibility moments at cage scale.** Distances stored raw to the
  volume's far cap let far geometry dominate a texel's variance so completely
  that near-surface statistics collapsed into a hard step at the mean,
  printing a dark blob under every probe near a wall. The reference's rule
  (clamp stored distance to 1.5× spacing: the Chebyshev test only ever asks
  about a probe's own cage) is load-bearing, not an optimization.
- **Relocation is not optional.** A room built from wall slabs parks whole
  probe rows *inside* the slabs (the smoke test's ceiling row sat at y 4.04
  in a 4.0–4.2 slab), and an embedded probe's backface statistics darken a
  blotch of every surface its cage touches. The 2021 optimizer walks them
  out in a few updates; diagnosing it was a textbook counterfactual chain
  (Chebyshev off → *brighter dots* at probes, trilinear-only → smooth but
  dark → the weights were fine and the probes were wrong).

**Camera-anchored cascades give a vast scene a near field.** The fitted volume
spends its 512 probes over the whole scene, so a terrain leaves ~50-unit gaps
between probes and the bounce near the camera smears. Past a coarseness
threshold (fitted spacing above half the eye-to-target distance, calibrated so
a room with the camera inside stays single-volume with a comfortable margin),
`giCascadeLadder` derives up to `OLLIN_GI_MAX_CAMERA_CASCADES` (3) extra
volumes that halve the scene spacing down toward a quarter of the working
distance, each an isotropic-spacing window of at most 8x8x8 probes centered on
the eye: axes whose span already covers the scene's slab pin there instead (a
terrain's cascades never scroll vertically), and per-axis counts clamp to the
slab, so a flat scene's cascades spend a fraction of their 512-probe slots.
The atlases stack one 512-probe slot per cascade (the same widths, so
`ollin_gi_atlas_uv` and the carriers' three texture bindings are untouched;
probe index = slot · 512 + local), allocated at the ladder's capacity: a
capacity change only ever rides a refit, and the single-volume allocation is
exactly the shipped one, so a room-scale scene keeps byte-identical sampling
UVs. Live, a cascade scrolls in whole probe planes as the camera moves (the
infinite-scrolling-volume model, studied via NVIDIA's public RTXGI SDK: a
truncation dead zone of one plane, physical texel = (grid + phase) mod counts,
so a stationary world lattice point keeps its texel), and a small pass over
the offsets ping-pong invalidates exactly the scrolled-in planes by zeroing
the offset and its w validity; the blends read that per-probe validity and
blend an invalidated probe like a refit's (fresh at full weight, the
reference's clear-then-zero-hysteresis semantics in one step), so the field's
interior never re-converges. The ladder itself holds live until the working
scale drifts past half/double its derivation value AND the fresh derivation
differs structurally; headless refits ladder and volumes from the frame's own
camera and bounds every frame (no scroll machinery at all), so an export stays
a pure function of the frame, and the quality tier still never touches the
grid. Sampling walks the table finest-first: the finest covering cascade wins,
fading over its outermost cell into the next coarser (the ladder is nested by
construction, so the blend partner always covers the band), with the scene
volume the fallback that covers every shaded point; the interior of the finest
window costs one 8-probe cage like before, the band two. Two codegen rules
came out of the byte-identity work: `ollin_gi_sample` and `ollin_gi_trace`
stay verbatim as the single-volume fast paths with cascaded twins beside them
(`ollin_gi_sample_volume`/`_cascaded`, `ollin_gi_trace_cascaded`, selected per
frame by whether cascades exist), because fast-math re-contracts a function's
unchanged float expressions when its control flow grows, and even the ulp
shifts a dithered byte; and the trace bisect that found it (whole-file revert,
then per-function) is cheaper than reasoning about which expressions fuse.
Verified: the room and mirror byte-identity scenes render pixel-exact against
their pre-cascade references, a full snapshot re-record matches a clean-HEAD
re-record on all 180 reference files byte-for-byte, and the vast-scene
counterfactual (the test seam forcing the single volume on the same frame)
moves the near structure's bounce by up to 149/255 where the fine cascades
resolve the floor's light. The live scroll behavior was measured by the
screencapture frame-diff protocol (2026-08-11): a 160-unit sunlit gallery
(three-rung ladder, spacings 6.9/3.5/1.7) under a camera advancing in 6-unit
steps with 2.6 s holds between them, 150 captures binned by an on-canvas hold
marker, an env-guarded debug print confirming every step scrolled all three
rungs (45 scroll events; a repeat-position control hold scrolled nothing).
Within-hold consecutive diffs: steady-state floor 0.05-0.09/255 mean (p99 =
1), the no-scroll control hold identical to it, post-scroll first pairs
0.1-0.6/255 typical with one worst case of 1.8/255 (p99 28), every hold back
at the floor within one to two seconds and never re-elevated. The worst
transient localizes to a single near-camera bounce-lit face (the amplified
diff shows one box side, no probe-plane-shaped band, no scene-wide term):
that face swung ~8/255 (~6%) over the first third of a second after a scroll
and crept back at the rate-limited pace, which is the asymmetric
temporal-response pair behaving as designed, a one-shot settle rather than an
oscillation. Continuous slow drift (1.5 u/s, the finest rung scrolling a
plane every ~1.2 s) shows no fade seams or banding in the stills.

**Mirror interiors and render targets gather too.** The traced hit shade
(`ollin_rt_hit_radiance`, shared by the reflection and refraction walks) swaps
its irradiance-cube diffuse for a probe-field sample at the *hit* when the
field is active, pre-divided by the IBL exposure because the whole traced
radiance is scaled by it on composite (the `ollin_pbr_ibl_ambient` rule), so a
surface seen in a mirror or through glass carries the same bounce as its
direct view; the atlases ride into the deferred trace pass (textures 13/14/15
in `encodeReflectionPass`, whose lighting packs the field like the LTC/shaping
mirroring) and thread through `ollin_pbr_ibl_ambient` into the inline trace.
This is distinct from the recorded flat-pastel-blobs dead end above, which was
about substituting irradiance for the *specular* second bounce; the traced
specular stays traced. Render targets take the resolved field through
`encodeEffectTargets(gi:)` (the GI pass now encodes ahead of the effect
layers, so a layer samples the same update the main pass does).

Behavioral net: `GlobalIlluminationTests` (bounce-fills-the-unlit-ceiling,
red-wall dye vs a repainted twin, no leak into a sealed box vs a light moved
inside, intensity scaling, on-then-off byte-equality, two-render
byte-determinism, the mirror-interior and render-target counterfactuals, the
quality knob's export-tier bytes, the exact per-axis-count derivation, and the
cascade tier: the vast-scene near-field counterfactual against the test seam's
forced single volume, the room-stays-single byte-equality, cascaded two-render
determinism, and the exact ladder/scroll-math derivations), all RT-gated
except the CPU unit tests, the toggle/mirror/target/knob/cascade claims each
verified red by sabotage. The two live stabilizers (the fixed relocation
fan and the temporal-response pair) deliberately carry no test of their own:
both defects exist only in the live hysteresis loop, which every deterministic
probe restarts from scratch, so the verification is the live A/B measurement
(window captures diffed frame-to-frame: sphere pulsing mean ~4.4 → ~0.5,
worst-band over-8/255 fraction 53% → under 1%), the same honesty rule the
artificial-life sims follow. The remaining envelope: GPU point clouds and
particles don't gather (they barely have surfaces to), documented in
`Docs/3D/3D.md#global-illumination`.

---

## The path-traced export

`--path-traced` renders the still/sequence/video exports' 3D content with an offline unidirectional path tracer (`Renderer/ShaderPathTrace.metal`, driven by `MetalRenderer+PathTrace.swift`), while everything around the solid meshes keeps the raster pipeline. The mechanism, and the decisions that took debugging to reach:

**Scheduling: the trace owns its command buffers and completes first.** `encodePathTracePass` runs at the top of the headless one-frame render, before any of the frame's own encoding: a setup buffer (environment bake through the cached `resolveIBL`, shaping tables, the acceleration-structure build), then one compute dispatch per sample chunk, each committed and waited. Three reasons over "encode it into the frame's buffer": a minutes-long single command buffer risks the GPU watchdog and can report no progress; the chunk boundary is where the still export's rewriting `path tracing N/M samples` line comes from; and the shared per-frame rings the build fills (`meshGeoOffsetBuffers`, the accel object itself) are re-filled afterwards by the frame's own shadow pass, which is only safe because the trace has already finished. Chunks adapt toward roughly a second of GPU work each (`cb.gpuEndTime - cb.gpuStartTime`).

**The scene handoff generalizes the caustics pattern.** `buildShadowAccel(pathTraceMats: true)` breaks its coalesced geometry runs wherever the batch finish changes (a bytewise compare; the finishes are packed from the same inputs, so bytewise is exact) and uploads one full `OllinMaterial` per geometry, parallel to the base-vertex offsets. A hit therefore resolves position, interpolated normal and vertex color, the baked per-vertex metal/rough, and the whole finish (emissive, `f0`, shading model). Matcap batches are excluded from the traced scene entirely and keep rastering: a matcap is the unlit emissive-look finish, and the glowing prop a sketch draws exactly over an area light would otherwise swallow every next-event visibility ray to that light (the AreaLights example found this on the first render: the whole panel's light went missing).

**The composite is one premultiplied draw with a depth write.** The kernel accumulates radiance sum and hit count into an `rgba32Float` texture (fixed per-pixel order across dispatches, so the export is byte-deterministic) plus a pinhole primary depth. In the geometry pass, the first solid mesh batch draws a fullscreen composite instead (later solid batches skip): source-over premultiplied, so silhouette edges carry fractional coverage and blend over the backdrop and any 2D drawn before, and the fragment writes the traced depth, so wireframe, the grid, matcaps, point clouds, strands, raymarched fields, and instanced meshes still raster over or behind it correctly. A primary miss contributes nothing; the skybox or clear color behind the composite is what shows.

**Radiance conventions are raster parity, not a private physical system.** Punctual lights keep the raster's units (intensity-premultiplied color, no distance falloff, un-normalized Lambert for the legacy finishes, the microfacet terms for the physically-based one); area lights are physical with `color` as radiance, and a tube emits by its silhouette ribbon (length × diameter; the full lateral surface overshoots by ~π, measured against the raster's LTC look); the environment samples the same equirect at the same normalization-times-intensity the skybox and IBL use; with no environment the flat ambient becomes the miss field, which makes an ambient-only scene an exact furnace (`PathTraceTests` pins the mean within 3/255; note `Color(white: 0.5)` is sRGB, so the field is its linearized 0.214).

**Variance came down in three distinct steps, each a published technique, each fixing a different mechanism.** First, environment importance sampling with the power heuristic (two-level luminance CDFs over a 512×256 latitude-weighted grid, cached per equirect texture; one shared lobe-pdf function feeds both sides of the heuristic, or the estimator biases): this fixed the missing light, not the sparkle. Second, filtered importance sampling: lobe-side environment reads pick the mip whose texel footprint matches the sampled probability's solid angle, and the environment strategy reads the level its tables were built from, so one lamp texel far brighter than its table cell cannot spike. Third (the one that actually killed the single-pixel glitter), path-space regularization: next-event evaluation at an *indirectly seen* vertex floors the surface roughness at 0.25, because a near-mirror NEE term carries the microfacet distribution's full peak with no probability division, and one bounce-sample that happens to align with a light spikes by tens of thousands (no sample count cures a bounded-mean, unbounded-tail estimator). The continuation lobe stays exact, so mirror-in-mirror imagery is unaffected; only a light's glint seen *in* a mirror softens, which the raster reflections (Lambert-only at hits) never showed at all. The depth-isolation experiment that found it: depth 1 was clean, depth 2 sparkled with both environment terms disabled, so the only unbounded term left was light NEE at bounce vertices.

**The grain filter is a separate pass over what the trace wrote down about the surface.** The estimator's own variance work above is where the noise *comes from*; this is what is done with the noise that is left. While it traces, the kernel fills two guide layers at the *first* hit only: the surface's base color after its maps plus the running square of each sample's luminance, and the shading normal plus the primary distance. They are written only while `pt.meshLights.w` is up (the `denoise` flag, which is off unless asked for), and are a one-pixel stand-in otherwise, so the ordinary render allocates nothing extra and writes nothing extra. `encodePathTraceDenoise` then runs four kernels in one waited command buffer: `prepare` turns the sums into per-pixel means, divides the radiance by the surface color (demodulation, so nothing painted on a surface is ever blurred, only the light on it) and computes the unbiased sample variance of the mean, `/(N-1)`, which is why a single-sample render skips the pass outright; `ollin_pt_denoise_atrous` runs five times over a ping-pong pair, doubling its tap spacing each time so a 32-pixel reach costs 25 reads per pass, weighing every tap by normal agreement (power 128), *relative* distance (0.02 of the center's own distance, opened by the tap spacing), and luminance difference divided by the measured variance (3x3-blurred first, since a single pixel's estimate of its own spread is itself noisy); `finish` multiplies the surface color back and writes into `accum` **in accum's own units** (radiance times the coverage count), which is why the composite fragment needed no change at all. Variance rides the alpha channel through the chain and is filtered with squared weights. Three things worth keeping: the guide albedo is forced to 1 on a mostly-transmissive hit (what shows through glass is not its tint, so dividing by that tint would smear the view behind it); the settings were swept rather than copied, and wider luminance blending (4 -> 8 -> 16) buys about 1.5% RMSE while costing about 30% of the kept high-frequency detail, so the published sigma of 4 over five passes stands; and every integrator probe in `PathTraceTests`, plus the `path-traced-3d` snapshot, names `denoise: false` explicitly rather than leaning on the default, because they measure the sampling and not the filter.

**The lens is eight lines in the ray generator.** `Camera3D.aperture`/`focusDistance` sample a disk over an orthonormal basis around the view axis and re-aim at the shared focus point; the composite's depth stays the pinhole center-ray depth so the raster kinds composite stably. The camera frame comes from the same `makeUniforms3D` the raster uses (unjittered), so perspective, orthographic, and intrinsic projections all frame identically.

**Glass is a stochastic mix, and the estimator weight collapses to one Smith term.** A physically-based hit with `transmission > 0` routes that fraction of paths (a weight-free stochastic mix, so partial transmission shades correctly) to a microfacet dielectric: sample a micro-normal from the same visible-normal distribution the opaque lobe uses, price it with the exact unpolarized dielectric Fresnel at the relative index (entering 1/ior, leaving ior), reflect with probability F, otherwise refract about the micro-normal (`refract` returning zero is total internal reflection, which reflects). A thin pane (`thickness` 0) never bends: both faces cancel, so the ray passes straight and only the reflection lobe uses the micro-normal. A solid tracks a `medium` state: the crossing in multiplies the surface tint and arms `attenuation`, every interior segment pays `attenuationColor^(d/attenuationDistance)`, and the crossing out disarms it (tint on entry only, or a slab tints twice). The property that makes visible-normal sampling with stochastic Fresnel selection worth the ceremony: the sampled estimator's weight reduces to the outgoing Smith G1 alone (the distribution, the Fresnel, and both Jacobians cancel), so polished glass carries weight 1.0 exactly, which is why a clear solid sphere in the ambient furnace renders the field to within the test's 4/255 and any future energy bug in the branch moves that mean.

**The MIS bookkeeping travels as one flag.** A glass vertex runs no next-event pass (it is specular-dominated; a light NEE through a near-delta lobe is exactly the glitter the regularization exists to prevent), so it sets `prevNEE = false`. Every "did another strategy already have a chance at this light" weight keys off that flag: a ray that leaves the scene after a glass vertex takes the environment at *full* weight (the power-heuristic share would silently halve everything seen through a window), and an emissive mesh found through glass adds its full glow. Opaque vertices set the flag and leave their continuation pdf in `prevPdf`, and the emission-side weight at a BSDF-found emissive hit is computable at the hit alone because of the CDF property below.

**Transparent shadows are a closest-hit walk, gated to cost nothing without glass.** Next-event visibility (`ollin_pt_transmittance`) walks the shadow segment hit by hit: an opaque surface kills it, a transmissive one multiplies the tint (albedo times transmission per thin sheet or solid entry, Beer over interior spans) and steps past, bounded at eight crossings. It is a straight line on purpose: a shadow ray cannot refract, so the bent, focused version of this light is exactly the live `caustics()` feature's territory. It also skips the per-interface Fresnel (the standard shadow-ray approximation; the few-percent error reads as slightly bright glass shadows, never as a seam). A scene-level flag (`meshLights.z`, set when any traced geometry transmits) keeps glass-free frames on the original cheap any-hit ray.

**Textures reach hits as bindless resource IDs, sharpened by a ray cone.** The accel build's run-coalescing also breaks on surface-map identity (gate-aware: a slot's texture only counts while its finish gate is up, so two batches differing only in an undrawn map still coalesce), and a parallel buffer of `MTLResourceID`s, five per geometry (`OllinPTTexEntry`: base color, normal, metallic-roughness, occlusion, emissive; the 1x1 white stand-in in an unbound slot, so the base sample is the identity and needs no gate, and the gated slots are simply never read unbound), is read in MSL as a five-texture argument-buffer struct, with `useResources` marking the real textures resident. Base and emissive bind the color (sRGB) texture, the value-encoding maps the raw data view, the raster encode's own split. The hit's uv interpolates from the same flat vertex buffer the fetch already reads. The mip is the ray-cone estimate: the CPU unprojects the center pixel and its neighbor once to get the footprint at the eye plus the spread per unit of travel (projection-agnostic, so orthographic cameras get a constant footprint and perspective ones a growing one), and the kernel divides the cone's width at the accumulated path distance by the triangle's own texel density (texture-space area over world-space area, per-map resolution folded in per slot), the standard texture-LOD scheme for rays, which have no screen-space derivatives.

**The surface maps compose at a hit exactly as the raster surface-mapped fragment composes them, with three consistency rules the estimator needs.** `ollin_pt_apply_maps` runs once per opaque hit: the base color multiplies the baked vertex tint; the normal map bends through the barycentric-interpolated vertex-tangent frame (bitangent rebuilt as sign · cross(N, T), the bend computed on the raw interpolated frame and flipped to the viewed side after, so a back face shows the same relief mirrored); the metallic-roughness channels multiply the *finish-table* factors rather than the baked vertex w slots, because the vertex slots carry only the drawing-state finish while the finish table carries the drawing-state × mesh-material product the raster's per-pixel resolve multiplies; a triplanar geometry projects base color and normal map through the raster's own `ollin_triplanar_surface` (its lod-less reads land on level 0, which is also where the raster reads its mipless image textures). The consistency rules: (1) the hit keeps a geometric normal (`OllinPTHit.Ng`, the pre-bend ray-facing normal) for every epsilon offset and a below-horizon break on the sampled continuation, the raster's own "a map is surface detail, not surface position" split, and since `Ng == N` on unmapped surfaces those scenes are untouched; (2) the occlusion ramp (1 + strength·(ao − 1)) dims the *environment share only*, applied to the environment NEE term at the vertex and, through a carried `aoPrev`, to the lobe-side environment/ambient pickup when the ray it produced misses: both halves of that MIS pairing scale by the same factor, which is what keeps the combined estimator consistent, while direct-light NEE, emissive hits, and surface-to-surface bounce light stay undimmed (the trace already occludes those with real geometry, and dimming one MIS half without its partner would bias the pair); (3) an emissive map modulates the radiance a mesh-light sample or a BSDF-found emissive hit carries, but the triangle *selection*, its area pdf, and the reverse MIS weight all stay priced on the bare factor: the CDF ran on factor luminance, an sRGB map's texels never exceed 1, so the factor pdf's support covers the glow and the estimator stays unbiased with no per-triangle map integral.

**The emissive-triangle CDF makes the reverse pdf free.** The CPU lays out every glowing geometry's triangles with a running power CDF (emissive luminance times area, two-sided to match the constant term a direct hit adds). Because a triangle's selection probability is proportional to luminance times area and the point within it is uniform, the pdf over the light's *area* at any sampled point is just luminance over total power, independent of which triangle, so a BSDF-found hit on an emissive surface can price the light strategy's pdf from its own material and hit distance, with no per-triangle lookup structure. The forward side samples the CDF by binary search, prices the point by the area-to-solid-angle conversion, runs visibility through the transparent walk, and folds in through the same power heuristic the environment pair uses.

## Temporal anti-aliasing

`temporalAntialiasing()` is the frame-wide form of the accumulation the
deferred-reflection pass already did: jitter the 3D projection by a sub-pixel
offset each frame and integrate the resolved frames, so edges refine past the
fixed MSAA sample positions and the screen-space/traced effects' residual
shimmer is absorbed with them. Written from the published treatments (the
jittered-supersampling resolve with neighborhood rectification, moment-based
history clipping, and the luminance-compressed blend; Techniques list in
ATTRIBUTION.md). Per-frame state like `rayTracedReflections()`, main canvas
only, any Metal GPU.

**The jitter is one NDC translate premultiplied onto the projection**
(`MetalRenderer.jittered(_:by:)`: clip.xy += jitter · clip.w), which is exact
for perspective, orthographic, *and* intrinsic projections where the classic
add-to-`[2][0]` trick is perspective-only, and touches neither z nor w, so
depth values, `depth(at:)`, and every depth test are unchanged. The offsets
are the low-discrepancy (2,3) radical-inverse sequence
(`taaJitterOffsets`, built from the public `halton`), the live path cycling
the first 8 by frame count, the export supersample taking the first N in
order. One `taaJitter` parameter threads it through every main-canvas 3D
pass so nothing misaligns: `encode`'s `makeUniforms3D`, the reflection
G-buffer, the scatter mask, and both half-res field pre-passes; render
targets always pass zero (a target has no accumulation to resolve a jitter
with), and `encodeMeshNormals` stays unjittered with them.

**Live** (`applyTemporalAA`, between the subsurface diffusion and the frame
filters): the main pass gains a `.min` depth resolve (memoryless MSAA depth
resolves from tile memory; a TAA-off frame attaches none), and the resolve
shader (`ollin_fx_taa_resolve`) reprojects the history by camera motion with
closest-depth 3×3 dilation, resamples it with a 9-tap Catmull-Rom (bilinear
alone re-blurs the accumulation every frame), rectifies it against the
current 3×3's moments in luminance-compressed YCoCg, and blends it as an
adaptive EMA into an `SSRHistorySlot` twin (`taaHistory`), guarded by
`statefulEncodeIsRepeat` like the other stateful passes. A frame's current
sample is first reconstructed at the *unjittered* pixel center (a 3×3
Gaussian, the published Blackman-Harris fit e^−2.29r², weighted by each
tap's distance from that center), which re-centers the shifted render and
keeps the nonzero-mean jitter sequence from wobbling the whole image.

**Headless/export** never touches the history (the deferred-reflection
precedent): `image(of:)` renders the geometry N times under the fixed
sequence (4/8/16 by tier via `resolveTAASamples`; export's automatic tier is
`.detail`, so 16) and averages them in linear light through
`ollin_fx_weighted_sum` ping-pong passes, the pre-passes (shadows, GI,
effect layers, sims, the deferred reflection) running once outside the loop.
A single export is anti-aliased with no warmup, a video can't flicker, two
renders are byte-identical, and the live frame-grab re-render can't
double-step the on-screen accumulation. The benchmark path takes the live
shape (cost parity).

Three live defects were found and fixed by frame-diff measurement (the
static-trellis scene in an OllinLive window, screencapture bursts diffed
frame-to-frame, statistics at the scale of the question), and each is now a
pinned rule:

- **Remove the jitter from the reprojection entirely.** The first cut
  reconstructed through the current *jittered* inverse view-projection,
  reasoning the unjitter "falls out of the matrix math". It does not: a
  static camera then reprojects the history at uv − j every frame, the
  history is Catmull-Rom-resampled at a different sub-pixel offset per frame,
  and its content random-walks with variance Var(jitter)/(1 − feedback²),
  which read as px-scale oscillation on every hairline edge (trellis
  frame-to-frame p99 14–33/255). Both reprojection matrices are unjittered
  (the published remove-the-jitter velocity rule); the jittered depth makes
  the reconstruction at most half a pixel off, which only perturbs the
  velocity under camera motion, never the still case. The same fix went into
  `ollin_rt_reflect_temporal`, whose G-buffer `u3` now carries the frame's
  jitter under TAA.
- **The rectification box must widen when the pixel is still.** At a fixed
  γ = 1 the μ ± σ box is rebuilt from each jittered frame, so the box itself
  oscillates with the jitter phase and drags a perfectly converged hairline
  edge back and forth (the clamp-sawtooth failure the survey literature
  documents). The clip's γ is velocity-adaptive (2.5 at rest easing to 0.75
  by 15 px/frame of motion): a still pixel's reprojection is exact, so its
  history deserves the wide box; a fast mover gets the tight one.
- **Key the adaptive feedback to the clamp, not the sample.** Feedback keyed
  to the luminance difference between the history and the *instantaneous
  jittered sample* permanently distrusts exactly the pixels that need the
  longest memory (a hairline edge's sample disagrees with its own converged
  mean every frame by construction). It keys instead on how far the clip
  just moved the history (untouched → 0.97, dragged a full σ → 0.88), so a
  converged edge holds still and a real change still refreshes fast.

The verification record (the artificial-life honesty rule: the live loop
restarts under every deterministic probe, so these numbers *are* the test):
TAA-off control diffs exactly 0.0000 mean / 0 max frame-to-frame; converged
TAA-on canvas mean 0.06–0.19/255 (p99 2–7), the pathological hairline-rod
crop mean 0.17–0.49 (p99 3–11, over-8/255 fraction 0.4–1.7%, down from
0.74–2.2 mean and 8–33 p99 before the three fixes), flat regions exactly 0,
and a moving camera shows no ghost trails while a 2D overlay stays within
1/255. The deterministic net is `TAATests`: the kernel-discrimination probe
(the export average must match its own analytic construction, built by
box-reducing an 8× reference at each declared offset, and match it *better*
than the plain box kernel, which pins offsets, signs, sequence, and weights
at once; margins set so even a full sign flip, whose point-reflected set has
a similar kernel, reads red), flat-interior energy conservation (a wrong 1/N
is 4 quantization steps), on-then-off byte-equality, two-render export
determinism, the 2D no-op gate, and the exact-pixel-shift/depth-untouched
jitter unit test; the discrimination and conservation claims verified red by
sabotage. A deliberate measurement note: a *box-filtered* ground truth is
not the export average's limit (its kernel is the pixel box convolved with
the jitter set, slightly wider than the pixel), and judging AA against a
gamma-space downsample is the classic linear-light trap; the test's
reference is built in linear light with the matching kernel.

**The mover-velocity buffer (`withMotion`)** gives world-space movers exact
history. Camera motion already reprojects per pixel from depth, but a mesh
that moves on its own (a spun `rotate`, a physics body, an animated scene)
leaves no record of where it was, so its pixels reprojected to stale content
and only the rectification clamp stood between them and ghosting, at the
price of the moving edges' refinement. The wrinkle is immediate mode: a
sketch re-records geometry every frame with baked world-space vertices and no
persistent identity, so there is no model matrix to diff. `withMotion { }`
supplies the identity: the block's call site plus its occurrence index among
same-site calls this frame plus the draw index within the block (the
`SSRSlotKey` rule; a frame-wide ordinal cross-wires histories the moment an
earlier block goes conditional), or an explicit name via `withMotion("…")`.
The drawer remembers each keyed draw's model matrix across frames
(`moverHistory`, pruned when a key skips a frame so a two-frame-old placement
is never read as one frame of motion) and, from a mover's second frame on,
records its vertex range with `previousOfCurrent = prevModel ·
inverse(curModel)`: the transform that takes this frame's baked world
positions back to last frame's placement.

The buffer itself is designed once for its three consumers (TAA now, MetalFX
temporal upscaling and motion blur ahead): **rg16Float at render resolution,
value = previous − current in pixels, y-down, both view·projections
unjittered**, which is the MetalFX motion-texture contract verbatim (scale 1,
and the convention Karis/Playdead compute; jitter does *not* cancel in the
difference, the same remove-the-jitter rule as the reprojection), and the
pixel units McGuire's motion-blur tile pyramid wants. Population is **sparse,
movers-only, with the depth-reprojection fallback for everything else** (the
UE-lineage pattern, vs the full-screen camera-baseline pass Playdead/Unity
write): every pixel no mover wrote keeps the shipped, live-measured camera
path *verbatim* (`ollin_fx_taa_resolve`'s fallback block is untouched), and a
frame with no declared movers encodes nothing at all, so the off path is
byte-identical by construction. The full-screen camera-baseline fill is the
recorded MetalFX prerequisite (that consumer sees only the texture and can't
run our depth fallback). The pass (`encodeVelocityPass`, right before the
resolve so both read the same previous view·projection off the history slot)
is single-sample with its own depth, two phases in one encoder: everything
that is *not* a mover draws depth-only first (nil fragment, color writes
masked off; wireframes skip, the normal-G-buffer rule), so a hidden mover
loses the depth test instead of writing velocity through its occluder; then
each mover range draws with its `previousOfCurrent`, the fragment
differencing the two interpolated clip positions after the divide
(perspective-exact). Unwritten texels keep a sentinel clear
(`OLLIN_VELOCITY_NONE`; a NaN from a degenerate mover transform compares
false and reads as unwritten too). The resolve samples the buffer at its
existing 3×3 closest-depth neighbor (the closest-fetch dilation rule, so a
mover's AA halo follows the mover), and a written texel replaces the matrix
reprojection with `prevUV = uv + v · texel`. A stationary mover under a
moving camera writes the camera's own motion (the total-motion contract,
probe-pinned), so written-vs-fallback never disagree about what motion *is*.

Verification: the registry, the pass, and the resolve's velocity branch are
pure functions of their inputs, so unlike the accumulation loop they carry a
deterministic net (`VelocityBufferTests`, 13): the call-site/occurrence/named
identity rules, skip-a-frame pruning, wireframe and render-target gates, and
render probes reading the texture back over a 1:1 orthographic scene (the
exact pixel delta with the exact sign, sentinel elsewhere, written-zero vs
sentinel, the camera term riding a still mover, the occluder holding a hidden
mover back), plus a crafted-texture probe of the resolve branch itself
(velocity toward the history's white half vs its black half vs the sentinel's
identity fallback). The velocity-sign, occluder-drop, and resolve-sign
sabotages each read red exactly where expected. The live *payoff* (a mover's
edges keeping their accumulated refinement mid-flight) has no deterministic
probe, so it was measured by the same screencapture protocol as the three
live defects above (2026-08-11): a static-camera probe scene ran the example's
orbiting thin bar with `withMotion` on and off (an env-var branch, two
launches of one binary), 30 window captures each, and per-frame edge metrics
over the bar. The median high-pass residual of the column-coverage profile
(spatial aliasing) read 0.006 with exact motion vs 0.048 without, 3-10x apart
at every matched bar length (0.007 vs 0.024 at the longest, ~0.005 vs ~0.065
at the shortest usable), and the centerline's second-difference RMS 0.16 vs
0.54; a static control rod in the same frames read identically in both runs
(0.006-0.008), and neither mode showed any ghost trail (the fallback's cost
is refinement, never a smear: the clamp holds). The crops match the numbers:
the exact-motion bar mid-flight reads like the converged static rod, the
fallback bar is visibly sawtoothed along both silhouettes.

Envelope: render targets and the accumulation surface keep plain MSAA; 2D
overlays over a *moving* 3D scene ride the scene's reprojection (measured
within 1/255 in the static and moving checks). `withMotion` covers solid /
textured / matcap meshes on the main canvas; a skinned or otherwise
vertex-deforming mesh is approximated by its node's rigid motion (exact
per-vertex history needs a previous-position stream, the engines' skinned
answer), wireframes, point clouds, GPU particles, and raymarched fields write
no velocity (and fields don't occlude the velocity pass), and a mover hidden
by one of those non-mesh occluders can still write velocity there, where the
clamp absorbs it as before.

---

## Motion blur

`motionBlur(shutter:)` is the velocity buffer's second customer: the published
plausible-motion-blur reconstruction filter (the TileMax/NeighborMax
dominant-velocity pyramid plus a classified per-pixel gather; Techniques list
in ATTRIBUTION.md), run as four fullscreen effect passes over the resolved
linear frame, after the temporal-AA resolve and before the frame filters, so
the blur reads settled edges and a bloom or grade reads the streaks. Per-frame
state like TAA, the same envelope (main canvas, active 3D camera, any Metal
GPU), and a photographic dial: `shutter` is the fraction of a frame interval
the virtual shutter stays open, 0.5 the film-standard 180-degree look, the
half of which enters the math because the published spread is the
*half*-velocity (a streak centers on the instant rather than trailing it).

**The chain.** Pass 1 (`ollin_mb_fill`) builds the full-screen velocity field
the paper assumes: where the mover pass wrote a texel that per-object motion
wins, everywhere else the pixel's world position (reconstructed from the
`.min`-resolved depth through the unjittered inverse view-projection)
reprojects through last frame's view-projection, which is the temporal
resolve's own fallback math per-pixel. The result is scaled by the
half-shutter and magnitude-clamped to the published `[0.5px, k]` (a whisper of
motion rounds up to half a pixel so the gather's center weight stays bounded;
nothing streaks past the tile radius the pyramid assumes), and the pixel's
camera-space depth rides the same texel's z. This fill is, incidentally, the
full-screen motion texture MetalFX's scaler needs, minus the shutter scale and
clamp: the camera-baseline-fill prerequisite exists once this runs. Passes 2
and 3 reduce that field to each k-pixel tile's largest velocity, then each
tile's 3x3-neighborhood largest, so every pixel knows about any mover whose
streak can reach it (velocities are clamped to k, one tile, so 3x3 suffices).
Pass 4 gathers S taps along the neighborhood's dominant velocity and weighs
each by the paper's three continuous cases: a blurry tap in *front* of the
pixel streaks over it (its cone says whether its spread reaches this far), a
tap *behind* a blurry pixel estimates the background the streak uncovers, and
two taps blurring together share a cylinder weight. All classification is
continuous (soft depth compare over an extent, cones and cylinders over
distances), so there is no sorting and no tap ordering; the center pixel opens
the sum at the inverse of its own velocity magnitude, which is what keeps a
sharp pixel heavy and a fast one light. k is resolution-relative
(`height/36`, clamped 16...64, reproducing the published 20 px at 720 tall)
and S resolves 9/15/27 from the frame-wide automatic quality (the TAA
no-per-knob rule, so export's automatic `.detail` lifts it).

**Where the cross-frame state lives is the design decision.** The previous
camera is kept on the *Drawer* (`previousCamera3D`, saved in `beginFrame`
before the per-frame reset), not on a renderer history slot, because
`beginFrame` runs once per `draw()` on every path: live, the same-frame
repeat, and the headless export drive, which already calls `performDraw()`
for every warmup frame, all read the same value with no new machinery. That
is what makes the export deterministic for free (exported frame k reads frame
k-1's camera and movers exactly like the live window) and what makes repeats
correct: by the time a repeat re-encodes, the TAA slot's stored matrix has
already advanced to *this* frame's, so the blur re-encodes the mover pass
itself through the shared `encodeMoverVelocity` core against the drawer's
matrix (the identical value the slot held when the first encode ran). The TAA
entry point (`encodeVelocityPass`) keeps its exact gates and its slot matrix,
so the shipped TAA path is untouched down to the byte; when both features run
on a live frame the blur simply reuses the TAA pass's texture, and the two
sources cannot disagree because the matrices are equal by construction.

**Byte-identity is layered.** Off, nothing runs (the guards return the
resolved frame). On but still, the chain skips on the CPU: the previous and
current view-projections compare float-equal and no mover range was recorded,
so a static scene with the blur on renders byte-identically to one without
it. On with a still *mover*, the mover pass writes zero motion, every
neighborhood's dominant velocity sits under the half-pixel floor, and the
reconstruction's early-out copies each pixel through by nearest-sample read,
which is value-exact. Frame 0 has no previous camera and returns unblurred by
definition. The backdrop rule is deliberate: a pixel at depth exactly 1 (2D
drawing, the clear color, the environment skybox) writes zero velocity, the
temporal resolve's own background treatment, so captions and overlays never
smear under a camera move; the cost is that the sky does not streak under a
pan, the documented envelope. The soft-depth extent is 1% of the eye-to-target
distance (the `sceneScale` proxy the sparkle cells and RT bias already ride),
not a fixed world constant: the published 1mm-10cm figures assume meter-scale
scenes, and a tuned screen-space constant hiding a scale assumption is the
subsurface-scattering lesson repeated.

Degenerate-input guards in the shaders are epsilon-shaped rather than
branched: a zero-velocity tap's cone divides by a floored magnitude (else
0/0), the cylinder's smoothstep edges are held apart (edge0 == edge1 divides
by zero at the boundary), and a tap that rounds onto the center pixel
contributes benignly instead of NaN-ing the sum. The gather jitter is
`hash12` of the pixel position, the dither's position-pure rule, so two
renders of one frame are byte-identical and video exports cannot shimmer.

Verification (`MotionBlurTests`, 12, over 1:1 orthographic scenes so
expectations are exact pixels): streak-direction twins (a horizontal mover
streaks along x and not y, the vertical twin the reverse), the tile-pyramid
reach (a background pixel in the tile *next to* a small fast mover, whose own
tile max is zero, still gathers the streak), camera-only blur with no
`withMotion` in sight, shutter scaling at a pixel only the wide spread
reaches, the still-frame / still-mover / frame-0 / 2D byte-identity gates,
backdrop stillness under a pan, and two-render determinism. The neighbor-max
skip, velocity-axis swap, and mover-texture drop sabotages each read red
exactly where expected (the mover drop failing the mover streak while the
camera streak stays green). The snapshot `motion-blur` pins the whole chain at
frame 2 on any Metal GPU.

---

## Temporal upscaling

`temporalUpscaling(_ quality:)` is the velocity buffer's third customer and the
jitter machinery's second: the live window renders the whole frame at a reduced
size and Apple's MetalFX temporal scaler (`MTLFXTemporalScaler`) reconstructs
the full-size canvas from the sub-pixel-jittered history. The tier maps to a
render fraction (`.performance` half size per axis, `.default` two-thirds,
`.detail` three-quarters, clamped to the device-reported scale range), so
per-pixel cost falls by the square while the scaler's own accumulation keeps
edges temporally anti-aliased. Per-frame state like `temporalAntialiasing()`,
main canvas + active 3D camera only, and gated on
`MTLFXTemporalScalerDescriptor.supportsDevice` (elsewhere a one-time note and a
normal full-resolution frame).

**The integration point is the resolve chain, not a post-process.** In the live
`render()`, every geometry-side pass sizes to the render (input) size: the MSAA
target and resolve, the depth buffer and its forced `.min` resolve, the clip
stencil, the reflection G-buffer, GI, contact shadows, the half-res field
pre-passes, the subsurface diffusion, and the mover-velocity pass. The scaler
then replaces `applyTemporalAA` (the scaler *is* the jittered accumulation;
feeding it Ollin's already-averaged output would integrate twice), bridging to
the drawable's full size, and everything downstream (motion blur, the frame
filters, the present) runs at the output size unchanged. The logical canvas
(`viewport`) never changes, and the geometry encode sets no explicit
`MTLViewport`, so shrinking the attachments is the whole resolution change: no
coordinate math anywhere is touched, and with the feature off the two sizes are
equal and the frame is byte-identical by construction.

**The scaler's inputs are the contracts already shipped.** The motion texture
is a full-screen fill (`ollin_fx_velocity_fill`): the `ollin_mb_fill` recipe
with the shutter scale and magnitude clamp removed, compositing the mover
pass's texture over depth-reprojected camera motion as *raw* previous-minus-
current pixels, y-down, both view-projections unjittered, which is the scaler's
documented convention at `motionVectorScale = 1` (the velocity buffer was
designed to it). The jitter offsets handed to the scaler are the pixel shifts
the jittered projection applied to the content (x right, y down, the table's
own units: "the offset to sample to return to the reference frame"); the
sequence is the shared Halton table extended from 16 to 32 entries, cycling
`min(32, ceil(8·s²))` phases for scale s (a scaler reconstructing s× the pixels
per axis needs ~8·s² distinct sub-pixel positions), while TAA keeps cycling its
first 8 and the export supersample its first ≤16, so both are untouched
(`theJitterTableKeepsItsShippedPrefix` pins the prefix). Depth is the same
`.min` resolve TAA reads (0 near, 1 far, `isDepthReversed` false), color the
linear pre-tonemap resolve with auto-exposure metering the HDR range.

**Cross-feature seams, each explicit:** while the scaler runs, `taaHistory` is
dropped (a later TAA-only frame must not reproject through a stale matrix);
motion blur runs at the output size reading the render-resolution depth and
mover texture by normalized coordinates, with the mover's pixel values rescaled
by the size ratio through a `moverScale` parameter whose (1, 1) default
multiplies exactly (the plain path stays byte-identical); a same-frame repeat
returns the slot's existing output without re-encoding, because the scaler's
internal history must advance exactly once per frame (the `taaHistory` rule);
and scaler creation failing flips the support flag so the note prints once
instead of retrying every frame. **Headless never touches the scaler**: a
sketch asking for upscaling exports as the full-resolution temporal-AA
supersample (`headlessTemporalAAActive`), pinned byte-identical to asking for
`temporalAntialiasing()`. The export is the deterministic full-quality
equivalent of the live preview, and the GPU benchmark keeps measuring the
full-resolution cost.

Verification splits along the honesty rule: the deterministic pieces
(`UpscalingTests`, 9) pin the gating, the tier mapping, the jitter-table
prefix, the fill's three behaviors over crafted textures
(`debugUpscaleFillReadback`: raw mover passthrough with no shutter scale,
exact camera reprojection, depth-1 backdrop zero), and the headless
equivalence; the fill and gate sabotages each read red. The live scaler is a
stateful platform object, so its verification is measurement (2026-08-11, the
TAA frame-diff protocol: a static RT-reflection scene in OllinLive, window
captures diffed over the canvas crop): converged frame-to-frame mean
0.08-0.11/255 (max ~30), inside the shipped TAA-on stillness band, i.e. no
jitter-sign shimmer, and *stiller* than the same scene un-upscaled (max ~120),
because the scaler absorbs the deferred reflection's residual sparkle the way
TAA does; hot-toggling off, then `.detail`, then `.performance` through a
reload swaps slots cleanly; and the FPS A/B on that scene read 28.6-30.6 fps
at full resolution vs 57.7-60.2 (vsync-capped) at `.performance`.

---

## The canvas sample pass (`CanvasSampler`)

The seam behind LED mapping (and anything else that turns rendered pixels into
a few hundred output values a frame): a `package`-access `CanvasSampler` in
`Sources/Ollin/Renderer/CanvasSampler.swift` that samples N points from the
rendered display texture with one small compute dispatch and reads back an
N-entry byte buffer. It rides the rendered-*texture* extension hook
(`wantsRenderedTexture` / `frameRendered(_:texture:)`, the frame-sharing seam),
so the off-screen re-render is only paid while a consumer is registered, and a
headless export (which never fires the hook) costs nothing. The design point is
the readback size: the whole-frame `CGImage` grab moves megabytes per frame
where a map of a few hundred LEDs needs a few hundred bytes, so the CPU never
touches the frame, only the sampled results.

Mechanics, and the decisions inside them:

- **Self-contained kernel, compiled from an inline source string** on first use
  (`makeLibrary(source:)` on the texture's device), deliberately *outside* the
  shader segment concatenation: it shares no helpers or types with the drawing
  shaders, and passing plain `float4` / `uchar4` buffers on both sides leaves no
  shared struct layout to drift (the one-header rule exists for structs spelled
  twice; here nothing is spelled twice).
- **Per-point box radius.** Each point is `(x, y, radius, 0)`; the kernel
  averages the `(2r+1)²` texel patch with clamped taps, so off-canvas points
  read the nearest edge texel and every LED can carry the patch it stands for.
  Radius is clamped to 256 so a wild value can't stall the GPU.
- **Linear-light averaging, display bytes out.** Reads on the sRGB texture
  decode to linear, the mean runs on linear values, and the result re-encodes
  through the sRGB curve to bytes, so a half-black half-white patch reads as
  the gray that *looks* halfway (the compositing rule), and a radius-0 sample
  round-trips the stored byte exactly (`CanvasSamplerTests` pins both, with
  the sRGB-space average as the counterfactual). Alpha averages and quantizes
  straight; it carries no gamma.
- **Synchronous by design.** The pass runs on its own queue and waits for
  completion before returning, for the same reason frame-sharing does: the
  renderer re-renders into the handed-out texture in place next frame on its
  own queue, and Metal's hazard tracking doesn't span queues. The wait is a
  few hundred threads deep and lands on the render loop that was already
  paused for the off-screen re-render.
- **Buffers persist; points re-upload only on change.** The point list is
  uploaded when assigned (a static map costs one upload total), and the output
  buffer is reused across frames.

The first consumer is `OllinDMX`'s `LEDMap` (`package` access reaches it
because the satellites live in the same package), which owns the mapping
question: where strips/matrices/loose points sit, each LED's default radius
(half its spacing or cell, banded 1...32), the whole-LED universe packing, and
the fixture-path color conversion. A future serial/laser tier can reach the
same seam; promoting it to public API is cheap if a sketch-facing use appears.

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

## Scene import (`loadScene` / `drawScene`)

Structure-preserving import beside the merged `loadMesh`: `Scene(contentsOf:)`
(sugar `loadScene`) reads a glTF/GLB file's default scene as a tree of
`SceneNode` values (name, authored local transform kept verbatim as a matrix,
an optional `Mesh` in node-local space with that node's primitives merged) plus
the authored cameras (core glTF) and punctual lights (the `KHR_lights_punctual`
extension), each resolved through its node's world transform into ordinary
`Camera3D`/`Light` values. Every other format `loadMesh` reads degrades
honestly to a single-node scene with no cameras or lights. User-facing API:
`Docs/3D/Scenes.md`.

**The loader split.** `MeshLoaderGLTF.swift` factored its file/buffer plumbing
into an internal `GLTFDocument` (GLB chunk split, buffer resolution, the
accessor readers, image bytes, material resolution) shared by both consumers.
`Mesh.loadGLTF` kept its own instance-walk-and-merge loop *untouched* (it bakes
world transforms into positions as it appends, and computes smoothed normals
after baking, so rebuilding it over per-node local meshes would not be
byte-identical); the scene path adds `GLTFDocument.localMesh(at:)`, the same
merge rules with no world baking. `MeshLoaderTests` pin that `loadMesh` output
is unchanged.

**Drawing.** `Drawer.drawScene` is a walk: save `modelMatrix`, post-multiply
the node's local transform, `drawMesh` the node's mesh (via the deform branch
below when the node skins or morphs), recurse, restore. Reusing `drawMesh`
wholesale is the point: materials, lights, shadows, reflections, wireframe,
batch/export/combine gating all apply with zero new rules, and
`SceneLoaderTests.drawSceneMatchesManualTransforms` pins that a drawn scene is
byte-identical to the equivalent manual transform-stack calls.

**Per-material submeshes.** A multi-material mesh (glTF primitives with
distinct materials; a USD mesh partitioned by `materialBind` `GeomSubset`
children) keeps its node's `mesh` *whole*, one merged vertex order, and adds
internal `SceneMeshPart`s on the node: per-material triangle lists indexing
that same mesh, plus the material each wears. The one-vertex-order design is
what keeps deformation untouched: morph deltas and skin weights stay aligned
with the merged positions, posing happens once, and the draw then emits one
ordinary `drawMesh` per part, a struct copy of the posed mesh with the part's
`indices` and `material` swapped in (the vertex arrays share storage through
copy-on-write, so nothing is duplicated). Loaders build parts only when the
split is real: the glTF merge records each primitive's index span and groups
spans by material index in first-appearance order, emitting parts for two or
more distinct looks (each material resolves once, shared with the merged
mesh's own pick); the USD build maps authored faces to part slots (first
subset claims a contested face, out-of-range face indices are ignored,
unclaimed faces form a remainder wearing the mesh's own binding, and a subset
family other than `materialBind` never partitions) and collects each face's
fan triangles into its slot during the one triangulation walk, in both the
indexed and the expanded forms. A single-material node carries no parts and
draws on the untouched path, byte-identical, which the unchanged snapshot
corpus pins; `partsVertexCount` guards a mesh swapped under the node back to
the whole-mesh draw (the skin-alignment treatment), pinned by render probe
beside the parts-vs-manual byte-equality probe in `SceneLoaderTests`.

**Resolution choices, and why:**

- **Cameras.** Eye = the node's world translation; the view direction is the
  world -z column (the glTF aiming convention); the world +y column keeps
  authored roll. `Camera3D` needs a *target*, so the eye looks at the scene
  bounds' center projected onto the view axis (an orbit-friendly pivot), one
  unit ahead when the scene is empty or behind the camera. Orthographic `ymag`
  is a half-height, so Ollin's `height` is `2 * ymag`.
- **Light intensities normalize per kind, brightest = 1.** glTF stores
  physical units (lux for directional, candela for point/spot) that only mean
  something under distance falloff, which Ollin's punctual lights don't model;
  raw candela values would blow out any scene. Per-kind (not global)
  normalization keeps the authored balance within a kind without letting the
  incomparable units fight each other. Colors arrive linear and re-encode to
  sRGB, the base-color-factor treatment.
- **Cameras and lights ride their nodes.** The loaders never resolve a pose:
  they attach internal node-local specs (`SceneLightSpec`, everything but the
  pose: kind, color, per-kind-normalized intensity, cone and area extents,
  emitting down local -z; `SceneCameraSpec`, projection + clip range), and
  `scene.cameras`/`scene.lights` are computed properties that walk the tree's
  *current* transforms on every read (`Scene.visitWorlds`, pre-order,
  matching the old collection order), so a carrier moved by hand or by an
  applied animation carries its camera or light. One shared
  `SceneLightSpec.resolve(world:)` serves both formats (position from column
  3, direction from -z, a rect's extents scaled by the axis lengths, a tube's
  endpoints transformed whole), so glTF and USD cannot drift; the camera
  getter re-derives the scene-center target from the *posed* bounds, which is
  render-safe because moving a look-at target along the view ray leaves the
  view matrix unchanged. Intensity normalization (per kind, brightest = 1)
  happens once at load over the specs (`normalizeLightSpecs`), so reads do no
  cross-light work and later node edits can't re-scale the mix. Assigning
  either array stores a fixed override (`fixedCameras`/`fixedLights`, and a
  get-modify-set tweak of one element is an assignment): the hand-set,
  world-space values win from then on and stop following the nodes, the
  documented trade that keeps "tweak a light after loading" working. USD
  composes prim worlds in double during the walk, but specs resolve through
  the Float node tree; the drift is sub-ulp for authored transforms and the
  whole snapshot suite passed unchanged.
- **Value semantics with an in-place subscript.** `scene.node(_:)` returns a
  copy (nodes are values); `scene["name"]` get/set finds the first depth-first
  match and writes back through the tree, so
  `scene["part"]?.rotate(dt, axis: .unitY)` composes *inside* the authored
  transform and spins the node about its own pivot. The authored matrix is
  never decomposed, so nothing is lost to a TRS round-trip.
- **`Scene` takes the bare public name** (the `Image`/`Environment`
  precedent), which is why the hosts' `var body` spell `some SwiftUI.Scene`.
- Malformed input follows the parser posture: `init?` never traps, a cycle in
  a corrupt node graph is skipped by a visited set, unnamed nodes get `""`.

**Animation (`SceneAnimation` / `scene.apply(_:at:)`).** The file's `animations`
array parses into `SceneAnimation` values (`3D/SceneAnimation.swift`): channels
group into per-node `Track`s (sorted by node index, the determinism rule), each
holding up to three `Sampler`s (translation/rotation/scale) and an optional
morph-weights sampler (below). A sampler stores
keyframe times plus `SIMD4<Float>` values, three per keyframe for cubic
splines (in-tangent, value, out-tangent, the file's element order), and samples
by the spec's formulas: STEP holds the earlier key, LINEAR lerps (rotations
take the spec's shortest-arc slerp, the arc angle from the dot's absolute
value with its sign folded into the second endpoint, degrading to normalized
lerp near parallel), CUBICSPLINE is the Hermite blend with tangents scaled by
the segment duration, quaternion results normalized. Outside the keyframe
range the nearest key's *value* element holds (the spec's clamp), which is
what makes one-shots end in their final pose. Rotation outputs may be
normalized integers (the spec allows four quantized encodings); the reader
decodes them by the spec's int-to-float equations.

Applying is where the "never decompose" rule earns its keep in reverse: a
sampled pose can't be written into a bare matrix without knowing the
un-animated components, so each `SceneNode` built from a TRS-authored glTF
node carries its authored components (`trs`, set from the file's own fields,
never derived from the matrix) plus its file node index (`sourceIndex`, the
identity tracks target). `apply` swaps sampled components into that base and
recomposes T·R·S; a matrix-authored node has `trs == nil` and stays untouched
(the spec forbids animating one). The `position` setter keeps `trs.t` in sync,
so a hand-set position survives a rotation-only track; a hand `rotate` on an
animated node is overwritten by the next `apply`, standard animation-system
semantics. Applying is absolute (a pure function of the animation and time),
so per-frame application converges and export determinism follows from the
sketch clock. `SceneAnimationTests` pin the sampler math against hand-computed
values (the Hermite 2.25 case, the 45-degree slerp midpoint, the quantized
decode) and the apply semantics; the `animated-scene` snapshot pins the whole
pipeline over the bundled orrery at a fixed sample time.

**Skinning and morph targets (the deforming tier).** The posing math lives in
`3D/SceneSkinning.swift`; the loader half extends `GLTFDocument.localMeshData`
(what `localMesh` now wraps) to merge, aligned with the merged vertex order,
the per-vertex `JOINTS_0`/`WEIGHTS_0` attributes (u8/u16 joints; float or
normalized-int weights via the existing `readVec4` decode; kept all-or-nothing
across primitives, the UV rule) and the morph targets' per-vertex POSITION /
NORMAL displacements (kept only when every primitive declares the same target
count, which the format requires). Deform data rides the `SceneNode`, not the
public `Mesh`: `skinIndex` + `vertexJoints`/`vertexWeights` + `morphTargets`
internal, `weights` public (the hand-drivable blend-shape surface; a weights
animation channel writes the same property). Skins parse into internal
`SceneSkin` values (joint *file node indices* plus inverse bind matrices, read
by the new `readMat4`). Morph displacements are where sparse accessors and
zero-filled no-buffer-view accessors matter (exporters store only the moved
vertices), so `readVec3` grew both, shared by every VEC3 read.

Posing happens at `drawScene` time with no new user API. A scene with skins
first resolves every file-indexed node's *scene-root* transform in one walk
(`nodeWorldTransforms`; a skinless scene skips it, and the unskinned walk is
structurally unchanged, so `drawSceneMatchesManualTransforms` still pins
byte-identity). Per node, `morphedMesh()` blends displacements at the current
`weights` (nil when there's nothing to do, so plain nodes take the untouched
path), then a skinned node poses through `skinnedMesh(_:skin:worlds:)`: joint
matrix `j` = root-relative world of joint node `j` × its inverse bind matrix,
each vertex blending up to four of them by weight (renormalized over the
influences actually used; a malformed joint index drops out; a zero-weight
vertex keeps bind pose), normals through the blended inverse-transposes. The
result lands in scene-root space because the format's rule is that a skinned
mesh's *own node chain is ignored* (placement comes entirely from the joints),
so the posed mesh draws under the model matrix of the `drawScene` *call*, not
the walk's composed one; a misaligned skin falls back to the undeformed draw
with a one-time note, never a mis-draw. Morphs apply before skinning (the
spec's order). The weights animation channel stores `k` scalars per keyframe
(`k` = the mesh's target count), and for CUBICSPLINE each keyframe groups all
in-tangents, then all values, then all out-tangents; `WeightsSampler` mirrors
the vector sampler's clamp/segment logic over that flat layout.
`SceneSkinningTests` pin the parse (u8 joints, inverse binds, sparse deltas),
the posed blend against hand-computed positions, default-weight precedence
(node over mesh), the cubic weights layout, byte-determinism, and, by render
probe, the ignored-node-transform rule; the `skinned-scene` snapshot pins the
whole pipeline over the bundled tidepool at a fixed sample time.

**The USD leg (`SceneLoaderUSD.swift`).** `Scene(contentsOf:)` routes the USD
family (`.usdz`/`.usdc`/`.usda`/`.usd`) through Ollin's own parser end to
end: one `USDStage` parse builds the node tree in authored order with
per-prim identity, rebuilds each mesh from its authored data, and resolves
preview-surface materials (package textures included), cameras, UsdLux
lights, the baked transform animation, and the UsdSkel deforming tier. The
walk's mechanism and schema rules live in § *The USD parser core* below
(under *The native scene walk*); what belongs to this section is that the
result is an ordinary `Scene`: `drawScene`, the subscript, `apply(_:at:)`,
and the skinning pose path apply unchanged, cameras resolve through the same
shared pose tail as glTF
(`Scene.resolveCamera(projection:near:far:world:sceneCenter:)`: -z view
axis, up column, bounds-center target), and `Mesh.loadUSD` (the merged
`loadMesh` leg) is the same walk with node transforms baked into the
vertices, the glTF merged-loader treatment. `SceneLoaderTests` pin the walk
over inline `.usda` fixtures; the `usd-scene` snapshot pins the whole
pipeline over the bundled court.

The bundled demo assets (`Examples/3D/Geometry/LoadedScene/scene.gltf`, the
animated `Examples/3D/Geometry/AnimatedScene/scene.gltf`, the deforming
`Examples/3D/Geometry/SkinnedScene/scene.gltf`, and the USD trio
`Examples/3D/Geometry/USDScene/stage.usda` / `USDAnimatedScene/stage.usda` /
`USDSkinnedScene/stage.usda`) are generated by
`Scripts/make-sample-scene.swift` / `make-animated-scene.swift` /
`make-skinned-scene.swift` / `make-usd-scene.swift` /
`make-usd-animated-scene.swift` / `make-usd-skinned-scene.swift` (the
`make-textured-cube.swift` precedent): geometry, cameras, lights, keyframes,
skins, and morph targets all authored in-repo, so the assets carry no
third-party license. The USD scripts author their designed display colors as
*linear* literals (the preview-surface convention), so the spec-correct
color read renders them exactly as designed.

---

## The USD parser core (OllinUSD)

USD is Ollin's native scene format, read by Ollin's own parser rather than
the platform importer (which drops lights, animation, and skinning,
alphabetizes children, and reads colors as display values). The parser core
in `Sources/Ollin/3D/USD/` is the substrate of that arc, now complete: it
opens all three containers and yields one raw prim/attribute tree,
`USDStage` (layer metadata plus `USDPrim`s carrying metadata,
`USDAttribute`s with defaults / time samples / connections,
`USDRelationship`s, and children, all in authored order). It is
**internal**: the consumer stages described below (the scene walk and its
light / animation / skinning legs) turn this tree into the public `Scene`,
and no raw type leaks. The supported envelope, verified against real
exports, is flattened single-layer files and self-contained packages,
variants at their defaults, no cross-file composition. Everything is
clean-room from the OpenUSD source's *structure* (credited in
`ATTRIBUTION.md`, never translated); the study notes live in the format
facts below.

The raw tree keeps the file's own shape rather than applying USD semantics:
tuples (vectors, quaternions, matrices) are component lists in file order,
tuple arrays are flat component arrays with an arity (`point3f[]` →
`.floatTupleArray(3, …)`), scalar widths widen (half/float → `double`, every
int width → `int`/`uint`) but float-typed *arrays* keep `Float` so bulk
geometry preserves exact bits for cross-checking, and a type the parser
doesn't decode records `.unsupported(typeName)` and moves on. One
consequence worth knowing: an *untyped* metadata value keeps the literal's
shape, so the same field can arrive `.stringArray` from text and
`.tokenArray` from crate; consumers normalize, the raw tier doesn't.

- **`USDTextParser`** (`.usda`) is a recursive-descent byte scanner,
  deliberately a *superset* of the grammar (newlines are free where the spec
  requires them; `;` and newline both separate statements). Values coerce by
  the declared attribute type; nested tuples flatten (a `matrix4d`'s rows).
  It parses all three comment forms, the full escape table (`\x` hex, octal,
  unknown-escape-drops-backslash), triple-quoted strings and `@@@…@@@` asset
  literals, `attr.timeSamples = { t: v, … }` blocks, `.connect` targets, and
  list-edit qualifiers. Out-of-envelope constructs are consumed
  string-aware and recorded `.unsupported`, never a throw: variantSet
  blocks, references/payload/inherits/specializes/subLayers, relocates,
  splines, array edits.
- **`USDCrateReader`** (`.usdc`, versions 0.8-0.10; the three versions share
  one structural layout, 0.9/0.10 only add value types) reads the bootstrap
  (`PXR-USDC` magic, version bytes, TOC offset), the TOC's six sections
  (TOKENS/STRINGS/FIELDS/FIELDSETS/PATHS/SPECS), and value data addressed by
  64-bit ValueReps (bits 63/62/61 = array/inlined/compressed, bits 48-55 the
  type, low 48 the payload: an inline value or an absolute offset).
  Structural sections are LZ4-wrapped (`USDLZ4`: a chunk-count byte, then
  raw LZ4 blocks Apple Compression decodes as `COMPRESSION_LZ4_RAW`) and
  mostly integer-coded (`USDIntegerCoding`: a running sum of deltas, each
  the shared common value or an explicit int picked by a 2-bit code stream;
  the 64-bit variant's widths are int16/int32/int64, one step *wider* than
  the 32-bit variant's). The PATHS section is a pre-order traversal
  (`jumps` of -2/-1/0/+n for leaf/child-only/sibling-only/both; a negative
  element-token index marks a property path), decoded iteratively with an
  explicit stack so deep scenes can't overflow. Authored order comes from
  traversal order, overridden by the `primChildren` / `properties` token
  vectors when present. Format traps pinned by the study and honored in
  code: an inlined AssetPath scalar carries a *token* index while its array
  elements carry *string* indexes; Vec2h is the one vector that inlines
  with raw half bits (the others inline as signed per-component int8s,
  matrices as int8 diagonals); TimeSamples is doubly indirected (a forward
  offset to the times rep, then a forward offset to the per-sample rep
  list); compressed float arrays are either all-integers (`'i'`) or a
  lookup table plus indexes (`'t'`); an array rep with payload 0 is the
  empty array; a sub-16-element "compressed" array stores raw.
- **`USDZipArchive`** (`.usdz`) parses the zip central directory itself
  (stored entries per the usdz spec, deflate tolerated, ZIP64 out of
  scope); the package's default layer is the first entry with a usd
  extension in archive order. `USDStage.load` sniffs content, never the
  file extension.

Verification is all local (`USDParserTests`), leaning on the fact that
**Model I/O exports both `.usda` and `.usdc` (crate 0.8)**: the same asset
is exported both ways and the two independent parser paths must agree
(structure exactly, floats to text precision), and both must agree with what
Model I/O reads back (vertex counts, transforms). System vectors cover crate
0.9 (the CoreUSDEdit shaderball) and 0.8 packages (the PencilKit pen usdz
files); a reparse is pinned byte-deterministic through a canonical dump. One
oracle lesson encoded in the tests: for a file Model I/O didn't author, its
`MDLMesh.vertexCount` is the *expanded* per-face-corner count (equal to our
`faceVertexIndices` count), not the authored `points` count, which stays
internally consistent (max index + 1 == point count). The shaderball also
demonstrates the arc's premise: Model I/O alphabetizes the children our
reader returns in authored order.

### The xformOp evaluator and UsdLux lights (stage 2)

The first consumer of the raw tree is the transform evaluator
(`USDXform.swift`, internal): `USDPrim.localXform()` composes a prim's
authored xformOps per `xformOpOrder` into one column-vector matrix, and
`USDStage.visitPrims` walks the tree handing every prim its world transform
(skipping abstract `class` prims). The conventions it encodes, each verified
against the reference implementation's structure and pinned by
`USDXformTests`:

- **`xformOpOrder` lists ops outermost first** (`["translate", "rotateXYZ"]`
  rotates, then translates), which with column-vector matrices means
  composing the listed ops left to right. Ops authored on the prim but
  absent from the order don't apply; no order means the identity.
- **USD matrices are row-vector** (translation in the fourth row), so a
  `matrix4d`'s four rows load directly as simd columns; the convention
  transpose falls out of the flat read.
- **Rotation angles are degrees**, and a three-axis rotate's value is always
  (x, y, z) angles; the op name (`rotateXYZ` … `rotateZYX`) only picks the
  application order, name order first.
- The **`!invert!` prefix** inverts its op (the `translate:pivot` /
  `!invert!translate:pivot` idiom is the pivot mechanism), and
  **`!resetXformStack!`** discards both the inherited stack and any ops
  listed before it. Single-axis forms (`translateX`, `scaleY`, `rotateZ` …)
  and arbitrary `xformOp:<type>:<suffix>` names are handled; a dangling
  op token is skipped, never fatal.
- **`orient` quaternions are (real, i, j, k)** in the raw tree. That is the
  text authoring order, and a crate amendment keeps the containers agreeing:
  crate files store quats as the raw in-memory struct, *imaginary first*
  (i, j, k, w), the one tuple shape where the two containers genuinely
  diverged, so the crate reader reorders scalar and array quats to
  real-first at decode (no local tool authors a crate `orient`, so this leg
  is spec-derived; the composition itself is pinned in text form).

The cross-oracle for the whole stack: Model I/O composes the example
stage's camera ops itself, and `USDXformTests` pins our matrix against its
`MDLObject.transform.matrix` element for element.

The evaluator's first customer was **UsdLux lights** (stage 2 of the arc):
light prims don't survive the platform importer at all, so
`SceneLoaderUSDLights.swift` reads them from the raw tree into ordinary
`Light` values on `Scene.lights` (today as node-riding `SceneLightSpec`s the
scene walk attaches where it builds each light prim's node, so visibility
and purpose gate them and the pose resolves through the tree's current
transforms on every read; the whole-stage `resolveUSDLights(_:)` form reads
every light prim directly). The mapping is complete over Ollin's light
kinds:

| UsdLux prim | Ollin light |
| --- | --- |
| `SphereLight` | `.point` |
| `SphereLight` + `shaping:cone:angle` | `.spot` (half-angle in degrees × 2 → `coneAngle`; `shaping:cone:softness` → `penumbra`) |
| `DistantLight` | `.directional` |
| `RectLight` (`width` × `height`) | `.rect` (extents scale with the prim's transform; local y is the `up` hint) |
| `DiskLight` (`radius`) | `.disk` |
| `CylinderLight` (`length`, `radius`) | `.tube` (the length runs along local x) |

Every kind emits along its prim's local -z (the camera convention, same as
glTF). Attributes read the `inputs:` prefix with bare pre-21.02 fallbacks;
schema defaults apply (intensity 1, except DistantLight's sunlight-scale
50000; disk/sphere/cylinder radius 0.5; rect 1 × 1; cylinder length 1).
The glTF punctual treatment carries over: colors re-encode linear → sRGB,
and each kind normalizes intensity × 2^exposure to its brightest = 1
(photometric units mean nothing without distance falloff). The usdz leg is
covered by a test-built stored zip (64-byte aligned via the extra-field
padding scheme the reference writer uses), which both our reader and Model
I/O accept; `SceneLoaderTests` pins the full rig, and the example stage's
authored rig (one light of every mapped kind, `make-usd-scene.swift`) rides
the `usd-scene` snapshot.

### Transform animation (stage 3)

The second consumer of the raw tree is transform animation
(`SceneLoaderUSDAnimation.swift`): the xformOp `timeSamples` no platform
importer carries become ordinary `SceneAnimation` tracks, so the shipped
`apply(_:at:)` plays a USD file on the sketch clock with no new user API. A
flattened layer has no named clips, so a stage with any sampled xformOp
yields exactly one (unnamed) animation for its whole timeline;
`scene.animations.first` is the way in.

The design choice, made over mapping plain translate/orient/scale ops
one-to-one onto track kinds: **bake**. For each animated prim, the composed
local matrix is evaluated at the union of the prim's authored sample times
and decomposed into translation/rotation/scale keys (mirrored basis folded
into a negative x scale; consecutive quaternion keys kept on one hemisphere
so the sampler's shortest arc is the baked arc). Baking reuses the stage-2
evaluator wholesale (`localXform(at:)` samples each op's attribute at a time
code instead of reading `authoredValue`), which is what lets *every* authored
op form play through the existing three track kinds: pivot pairs
(`translate:pivot` + `!invert!`, whose baked translation keys orbit),
single-axis ops, mixed orders, whole-matrix ops. The one envelope edge: an op
stack whose composition genuinely shears (matrix ops interleaved with
non-uniform scales) keeps only its TRS part. Each animated prim's rest pose
(the decomposed stack at rest) installs as the node's TRS base, the field
`apply` requires; since every baked track carries all three samplers, the
base never actually shows through.

Per-attribute sampling (`USDAttribute.sampled(at:)`) encodes a spec fact
worth pinning: **interpolation is a runtime stage setting, never authored in
a file** (`UsdStage::SetInterpolationType`; linear is the default every
consumer sees), so baked tracks are LINEAR. Under linear interpolation the
lerp-capable types blend componentwise, quaternion types slerp (the
reference's rule for `GfQuat*`), and everything else holds, which is the
held/STEP semantic exactly where it can occur. Time codes convert to seconds
through the layer's `timeCodesPerSecond` (falling back to `framesPerSecond`,
then the spec default 24), offset by `startTimeCode`, so a Maya-style
frame-101 opening still starts at zero.

**Tracks bind by per-prim identity**: the bake returns entries keyed by each
animated prim's absolute path (`USDBakedTrack`), and the scene walk maps
them onto the `sourceIndex` it assigned that prim's node, installing the
rest pose by the same identity, so a name duplicated across branches
animates exactly the prim that authored the samples. (The interim era, when
the platform importer still built the node tree, bound these tracks by first
depth-first name match through a `Track.nodeName` channel; the native walk
retired that channel entirely, and `apply` matches `sourceIndex` alone.)

Verification closed the stage-3 vector gap: macOS ships `/usr/bin/usdcat`,
a *reference crate writer*, so `USDAnimationTests` converts a hand-authored
animated usda to a real crate 0.8 file at test time (tool-gated, like the
system-asset vectors) and pins the two containers baking identical tracks,
which exercises the crate TimeSamples decode (the doubly-indirected layout,
previously spec-only) against reference output. The bundled kinetic mobile
(`make-usd-animated-scene.swift`, one part per authored form: rotateXYZ
spin, nested counter-spin, translate bob, quaternion orient tumble, the
pivot-idiom pendulum, scale breathing) rides the `usd-animated-scene`
snapshot at a fixed sample time, and a Metal-gated probe renders frames one
authored lap apart byte-identical (the loop-wrap guarantee the example's
`loopDuration` promises).

### UsdSkel skinning and blend shapes (stage 4)

The third consumer of the raw tree is the UsdSkel tier
(`SceneLoaderUSDSkinning.swift`): skeletons, skin bindings, and blend
shapes resolve into the deforming node data `drawScene` already poses
(`SceneSkinning.swift`), so a rigged USD file bends and blends with no new
user API and no new pose math.

A probe settled the architecture before any code. The platform importer
does surface UsdSkel API (an `MDLSkeleton` object with correct joint paths
and bind matrices, a packed joint animation, a morph-deformer component),
but two findings disqualify it as the data path. First, the joint vertex
attributes it reports are wrong: an elementSize-1 binding authored as
`[0, 0, 0, 0, 1, 1, 1, 1]` with unit weights came back as scrambled
four-wide garbage (`[1, 0, 0, 1]` weights and the like). Second, its
vertex layout for a deforming mesh is unstable ground: it keeps the
authored points for a skinned mesh but expands per face corner for an
unskinned one, and Ollin's own normal generation
(`addNormals(creaseThreshold:)` in `readMDLMesh`) then splits vertices
freely (8 authored points became 36), so per-point data (joint weights and
blend-shape offsets, all authored against the points array) has nothing
stable to land on.

So a deforming mesh is **rebuilt from the raw tree** on its authored
points, kept indexed: faces fan-triangulated in authored winding (reversed
under a `leftHanded` orientation), authored vertex-interpolated normals
honored (anything else smooths across faces, the `loadMesh` treatment),
vertex-interpolated `primvars:st` carried with v flipped to the top-left
convention, and the bound preview surface's diffuse color. This rebuild,
taken in stage 4 for deforming meshes only, became the seed of the general
mesh read: the native walk (stage 5 below) runs the same builder for every
Mesh prim, with the deforming form as its keep-indexed case.

**Joints synthesize into ordinary `SceneNode`s.** Each Skeleton prim
becomes a container node at the prim's evaluator world transform, holding
one node per joint nested by the joint paths' own hierarchy (parent = the
longest strict prefix present in the list), each node's TRS base its local
rest transform: authored `restTransforms`, or derived from the world-space
binds (`inv(bind[parent]) · bind[joint]`, the root against the skeleton
world) when a file authors none. Containers append *after* the tree nodes,
their joint identities numbered past every prim index (the walk hands the
skinning pass its next free index), so the one `sourceIndex` scheme covers
prims and joints without collision: SkelAnimation joint tracks bind by that
identity, and a joint poses by hand like any node
(`scene["elbow"]?.rotate(...)`).

The skinning math then falls out of the shipped pose path with no new
code: a joint's scene-root world is skelWorld · jointSkelSpace, and each
binding's inverse-bind entry is authored as
`inv(bindTransform) · geomBindTransform`, so the shipped
`worlds[joint] · inverseBind · point` is exactly the UsdSkel skinning
equation (bind transforms are world-space at bind; the geometry bind
transform maps the mesh's authored points to world at bind), and the
skinned node's own chain stays ignored, the rule glTF already established.
The skel primvars expand per point: `elementSize` influences each
(`constant` interpolation is the rigid binding, one shared element riding
every point), the `skel:joints` remap reordering mesh-local indices into
skeleton order when authored, influences past the pose path's four dropped
heaviest-first (the blend renormalizes over what's used).

SkelAnimation channels need no bake, because the schema is already
TRS-shaped (`translations`/`rotations`/`scales`, each an array over the
animation's own joint list per sample), so each joint's samplers slice
directly out of the channels: LINEAR per the interpolation rule stage 3
pinned, quats real-first from both containers per the parser rule, a
static (default-only) channel becoming a single held key. Blend shapes
pair `skel:blendShapes` names with `skel:blendShapeTargets` prims by
position; offsets land dense or through the sparse `pointIndices` form
(zeros elsewhere), `normalOffsets` riding when they pair one-to-one. The
weights channel gathers the animation's `blendShapes` token order into the
mesh's own target order by name (an unnamed shape holds 0) and binds by
the mesh node's identity, joining the joint tracks and the stage-3 xform
tracks in the stage's one merged animation. The animation source resolves
like the spec binds it:
the `skel:animationSource` relationship on the skeleton or inherited down
the prim hierarchy, which is also what lets a blend-shape-only mesh with
no skeleton at all play its weights (the bundled lotus).

Verification: `USDSkinningTests` pins hand-derived skinned positions
through the full `Scene(contentsOf:)` → `apply` → pose path (a two-joint
arm bending 90°, the two-influence midpoint, the rigid binding, whose
expected position also pins morph-before-skin ordering, and the remap
reproducing the unremapped pose); the usdcat-converted crate must resolve
identically to the text authoring (matrix4d[] binds, primvar metadata, the
sparse shape, every channel); and the platform importer's one trustworthy
skeleton output serves as a second oracle: our inverse binds must invert
to its `jointBindTransforms`. The bundled pond
(`make-usd-skinned-scene.swift`: a sea serpent on a five-joint chain with
two blended influences per point and a geometry bind transform; a lotus
breathing on a dense-with-normals bloom and a sparse tip curl) rides the
`usd-skinned-scene` snapshot at a fixed sample time, with the same
Metal-gated loop-wrap probe the mobile has.

### The native scene walk (stage 5)

The final stage moved structure, meshes, cameras, and materials off the
platform importer, so the whole USD `loadScene` path (and `loadMesh`'s USD
leg) now runs on the raw tree alone: `Scene.loadUSDScene` opens the file
once (`USDStage.open`, which for a package also keeps the archive and the
default layer's entry name), walks the prims depth-first in authored order,
and hands the light / animation / skinning legs everything they need. What
the swap fixed outright: children keep their authored order (the platform
importer alphabetizes; the system shaderball's `core, base, sss_bars` group
is the pin, at the parser level and the loaded-`Scene` level), preview
surface colors read spec-correctly (authored values are linear; they
re-encode to sRGB, the treatment every loader's colors get), textures
resolve (a `UsdUVTexture` connected to the diffuse input reads its file
through the package entries or the layer's folder, `USDAssetStore`, with a
sole-file-name fallback for exporters that flatten directory layouts), and
every track kind binds by real per-prim identity.

**Identity.** Each prim that becomes a node gets a `sourceIndex` assigned
depth-first in authored order; the walk returns the path → index map, the
animation bake's path-keyed entries and the skinning attach resolve through
it, and synthesized joints number from the walk's next free index, so one
scheme covers prims and joints. Prims that never become nodes: Material,
Shader, NodeGraph, Skeleton (the skinning pass synthesizes the real joint
subtree), SkelAnimation, BlendShape, GeomSubset, and abstract `class` prims;
everything else, Scope and light and camera prims included, keeps its place
as a (possibly bare) named node.

**The general mesh read.** `buildUSDMesh` generalizes the stage-4 rebuild to
every Mesh prim through one primvar model (`USDPrimvarSpec`): an authored
attribute resolves its interpolation (authored metadata; `varying` reads as
`vertex`; unauthored infers from the element count against the declared
default) and its optional `:indices` indirection (a blocked `None` indices
attribute reads as unauthored), and a mis-sized set drops whole rather than
mis-mapping. A mesh whose normals and texture coordinates are per-point (or
absent) stays **indexed on the authored points**; faceVarying or per-face
(`uniform`) data can't ride shared vertices, so the general form **expands
one vertex per face corner** and lands each corner's values exactly, with
missing normals smoothed (which over expanded corners is the honest
flat-facet look). A deforming mesh must stay indexed, the layout its skel
primvars and blend-shape offsets are authored against, so there a
faceVarying set drops instead (`keepIndexed`). `primvars:normals` wins over
`normals` when both are authored, the schema's precedence.

**Schema semantics honored, and the deliberate stances.** `visibility =
"invisible"` prunes rendering for its subtree, and a `guide`/`proxy`
`purpose` does the same (both inherit down; nodes stay in the tree, meshes
and lights skip, cameras skip only under invisibility). `upAxis` and
`metersPerUnit` are *not* applied: a scene arrives in its author's own units
and orientation, the `loadMesh` contract, and a probe confirmed the platform
importer ignored both too, so nothing regressed. A subdivision-surface mesh
draws its control cage (`mesh.subdivided(_:)` is the explicit refinement
path). A `!resetXformStack!` prim bakes the discard into its local matrix
(`parent⁻¹ · composed`) so the tree's composed world stays exact. Raw-value
normalization (the text-vs-crate `.token`/`.string` shapes, tuple arrays,
scalar widths) lives in one set of internal `usd*` accessors on `USDValue`
in `SceneLoaderUSD.swift`; consumers read through them, never re-switch.

**The merged form.** `Mesh.loadUSD` walks the same scene with node
transforms baked into positions and normals (normal matrix per node), first
authored material wins, UVs all-or-nothing, which fixed a real defect: the
platform merge read node-local vertex data with no transforms, so a
multi-part file's parts piled at the origin. Model I/O remains only for
STL/PLY/ABC (`loadViaModelIO`).

Verification kept the three-way oracle: the platform importer still reads
these files, so node worlds cross-check against its composition
(`USDXformTests`), inverse binds against its skeleton read
(`USDSkinningTests`), and camera projections land on the same numbers its
`MDLCamera` derivation produced; usdcat still converts the authored text
vectors to crate at test time; and the fixture scripts author their designed
display colors as linear literals, so the spec-correct read renders the
committed assets exactly as designed and the whole snapshot suite passed the
swap unrecorded.

---

## The 3D physics bridge

The 3D rigid-body world (`World3D` / `Body3D` / `Joint3D` in `OllinPhysics`)
is backed by vendored Jolt Physics (`External/CJolt`, MIT), reached through an
Ollin-authored C bridge rather than Swift C++ interop: `include/cjolt.h` is a
flat-POD `extern "C"` surface (opaque world/constraint pointers, a `uint32`
body handle, tagged-union shape and constraint descriptors carrying plain
float arrays), and `src/cjolt.cpp` is the only compilation unit in the repo
that includes a Jolt header. That containment is what makes Jolt's
define-consistency requirement (every unit including its headers must agree on
all `JPH_*` configuration macros, or structs silently change layout) hold by
construction: the macros live in one target, and Swift only ever imports the C
module. The vendored tree is the upstream `Jolt/` subtree verbatim; the GPU
compute backends, HLSL shaders, and debug renderer are on disk (so their
gated `#include`s resolve) but excluded from the SwiftPM build, since their
`JPH_USE_*` / `JPH_DEBUG_RENDERER` gates stay off.

Inside the bridge, each `CJoltWorld` owns the whole solver stack: a 16 MB temp
allocator, a `JobSystemThreadPool` (threads clamped to 1…8 from the core
count; Jolt's simulation is deterministic across thread counts, which the
test suite pins by stepping two identical worlds to byte-equal poses), the
three broad-phase/object-layer filter implementations, and the
`PhysicsSystem`. The layer scheme is the canonical two-layer setup
(NON_MOVING statics that only pair with MOVING) plus a GHOST layer that pairs
with nothing, reserved for any future collision-less helper body. Library
globals (allocator, RTTI factory, type registry) initialize once per process
behind `std::call_once`; there is no global *world* pool, which is why the 3D
tests run parallel where Box2D's need `@Suite(.serialized)`.

Two hard-won rules live here. First, **marshaling**: the C API's `float[3]` /
`float[4]` parameters map to Swift homogeneous tuples, and the one legal way
to hand a tuple's storage across is `withUnsafe(Mutable)Bytes(of:)` over the
whole tuple (the `CJoltInterop.swift` helpers). The original code took
`withUnsafeMutablePointer(to: &out.0)`, which is only valid for that single
element; the compiler materialized a temporary for it, the C side's writes to
elements 1 and 2 landed in dead stack memory, and positions read back with x
correct while y and z stayed 0, while the simulation itself ran perfectly (the
pendulum's x swung on schedule). The diagnostic that cracked it was printing
poses over time rather than staring at final asserts.

Second, **the grab is Jolt's own reference drag model, reproduced exactly**
(`Samples/SamplesApp.cpp` in the upstream tree): the anchor is a *static*
body that is created but never *added* to the world (nothing can collide with
it, it lives in no broad-phase), it is *teleported* to each new target with
`SetPositionAndRotation` so its velocity is always zero, and the dragged body
hangs on a `DistanceConstraint` with coincident points and a soft limit
spring (frequency 2 Hz, damping 1). Both deviations tried first were real
bugs: a rigid `PointConstraint` on a hand-driven anchor rings undamped, and a
*kinematic* anchor driven by `MoveKinematic` arrives carrying velocity that
the constraint solver dutifully matches, pumping the body into a widening
orbit (measured at ±40 units/s around the target). A zero-velocity anchor
plus a critically-damped spring can only ever bleed energy. The Swift-side
sugar (`grabBody(at:in:)` / `dragGrab(_:to:)`) adds the camera ray
(perspective and orthographic branches over the public `Camera3D` fields) and
remembers the picked point's depth along the view axis, so dragging moves the
body in the screen-parallel plane through the grab point.

Stepping clamps `dt` to `maxTimestep` (1/30 s) and runs
`⌈dt·60⌉` collision passes, so a hitch slows the world rather than
detonating a stack. Snapshot policy follows the artificial-life precedent: the
solver is deterministic *per binary* (pinned behaviorally), but a toolchain
rebuild may move ulps and a toppling stack amplifies them, so 3D physics
scenes are pinned by `RigidBody3DTests`' behavioral asserts (settling
heights, joint arm lengths, grab convergence, byte-equal replays) and not by
pixel references.

**Joint motors, limits, and springs** (stage 2 of the arc) surface the hinge
and slider constraints' powered side through four bridge calls that mutate a
live constraint: `cjolt_constraint_set_motor` (state + target + servo spring +
effort cap in one call), `_set_friction`, `_set_limit_spring`, and
`_current` (the angle/offset readback). Each switches on
`Constraint::GetSubType()` and no-ops on every other kind, so the Swift side
never needs a downcast or a kind check to stay safe. The design follows the
solver's own model rather than inventing one: a *velocity* motor is
`SetMotorState(Velocity)` + a target rate capped by the motor's torque/force
limits, and a *position* motor is `SetMotorState(Position)` + a target driven
by the `MotorSettings` spring (frequency in Hz, damping as a ratio, the
upstream defaults 2/1 kept as `drive(to:)`'s defaults), which is what
`Joint3D.drive(at:)` / `drive(to:)` map onto one-to-one. Three facts here are
load-bearing. Hinge limits must be authored min ∈ [-π, 0], max ∈ [0, π]
*relative to the connect pose* (the constraint defines angle 0 as the relative
orientation at creation because the bridge sets both bodies' constraint frames
identically in world space); `connect` clamps the user's range to that window
rather than letting the solver assert. `set_motor` ends by activating both
constraint bodies (`ActivateBody` skips statics internally): a settled body
sleeps, a sleeping pair never feels a motor change, and a door whose closer
engages after the scene has gone quiet would otherwise hang open forever with
no error anywhere. And the friction knob (`SetMaxFrictionTorque` /
`SetMaxFrictionForce`) applies only while the motor is *off*, per the solver's
contract, which is exactly what lets one number serve as both the stiff-hinge
drag and the coast-down brake after `stopMotor()`. Units cross the bridge the
same way everything else does: angles and rad/s pass through untouched, slider
targets/offsets convert by `unitsPerMeter`, and the effort caps stay in the
solver's N·m / N (documented, defaulted to unlimited via a non-finite
sentinel the bridge maps to ±FLT_MAX). `JointMotor3DTests` pins each knob
behaviorally, always against its counterfactual twin (a capped motor against
an unlimited one, a limited pendulum against a free one, soft limits against
hard), the same discipline as the rest of the suite.

**Compound bodies and world-geometry colliders** (stage 3) widen the shape
catalog without touching the API's shape: `CJoltShapeDesc` grew a recursive
child array (`CJoltShapeChild`, a desc pointer plus a local pose), a
height-field leg (samples plus offset/scale), and the tapered forms, and
`makeShape` recurses through `StaticCompoundShapeSettings::AddShape` (whose
`Create` collapses a single posed child to a rotated/translated shape and a
single unposed child to the child itself, which is why an offset single shape
costs nothing extra). Marshaling moved from the fixed two-deep
`withUnsafeBufferPointer` nesting to a `ShapeDescArena` (plain allocations
owned by an object held across the create call with `withExtendedLifetime`),
because a compound makes the number of pinned buffers data-dependent, which
static scope nesting cannot express. Two facts here are load-bearing. First,
`mAllowDynamicOrKinematic` must be `false` for any shape whose
`MustBeStatic()` is true (mesh, height field, a compound containing either):
allowing the switch makes body creation compute mass properties, which those
shapes cannot provide, and the library *traps*; this was a latent stage-1 bug
(nothing had ever actually created a `.mesh`-collider body) that the stage-3
tests exposed. The static pin now asks the created shape rather than
pattern-matching the descriptor type, `cjolt_body_set_motion` refuses the
switch for the same shapes, and the Swift side notes once when a dynamic body
gets pinned. Second, the height-field mapping: the solver wants an n×n sample
grid with n a multiple of its block size (a power of two stores best) and
defines the surface as `offset + scale · (x, h[z·n+x], z)`, so `Collider3D`
resamples the `Heightfield` bilinearly onto the smallest power of two
covering the source grid's cells (4…1024 per side; a 257-sample
diamond-square field lands on its natural 256) and derives offset/scale to
reproduce `mesh(width:depth:height:)`'s centered sizing exactly, storing 16
bits per sample so the collider tracks the drawn mesh to well under a visible
error. Per-part densities ride each child's own desc (the body's relative
density multiplies the part's). Scene colliders are a walk over the
package-visible `Scene.visitWorlds`: each mesh node's composed world
transform is baked into its triangles (general matrices, scale and shear
included, which a body pose could not carry) and added as one static mesh
body at identity, followed by an `OptimizeBroadPhase`. `Collider3DTests`
pins the tier: compound mass sums and balance against a counterfactual twin,
offset and rotated part poses, tapered-shape masses against their analytic
neighbors (a cone weighs a third of its cylinder), the flat and non-square
height-field mappings, the off-the-edge void, the scene-collider transform
composition, and a byte-identical compound-on-terrain replay.

**Contact events and sensors** (stage 4) surface the solver's collision
callbacks without letting a callback anywhere near Swift. Jolt's
`ContactListener` fires on the job system's worker threads *during* `Update`,
several at once, with every body locked, so the bridge's `ContactRecorder`
(owned by `CJoltWorld`, declared *before* the `PhysicsSystem` that holds a
pointer to it, so it outlives every step that could still be writing) buffers
flat-POD `CJoltContactEvent`s under a `std::mutex`, and
`cjolt_world_drain_contacts` empties that buffer on the main thread after
`cjolt_world_step` returns. This is the C cousin of the render-thread-closure
rule: the listener only ever reads what it is handed.

Three decisions inside the recorder are load-bearing. First, **the buffer
speaks in body pairs, not sub-shapes**: a compound's parts and a mesh's
triangles each report their own contact, so the listener reference-counts each
pair (keyed on the two `BodyID`s packed into a `uint64`) and emits one `began`
as the count leaves zero and one `ended` as it returns, which is the
granularity a sketch asks about; without it a crate landing on terrain would
report a landing per triangle. Second, **the drain sorts before it copies**
(by pair, then phase): worker threads record in whatever order they finish, so
an unsorted list would replay differently run to run and break the catalog's
determinism rule (the Swift-side `touching` lists are sorted arrays rather
than `Set`s for the same reason). Third, **`speed` is computed in
`OnContactAdded`, where the velocities are still pre-solve**: the manifold
normal moves body 2 out of collision, so it points from body 1 toward body 2,
and the solver's own measure of a pair's relative velocity is `v2 - v1` along
that normal, negative while they approach, which makes the closing speed
`(v1 - v2) · n` clamped at zero. `OnContactRemoved` receives only a
`SubShapeIDPair` and may not touch the bodies at all (one may already have
been destroyed), which is why an `ended` event carries no point or normal, and
why an event naming a body Swift can no longer resolve is dropped after its
bookkeeping is applied rather than handed over half-resolved.

**Soft bodies come in through a second listener**, and its shape is nothing
like the first. `SoftBodyContactListener::OnSoftBodyContactAdded` is called once
per soft body per collision pass, carrying a `SoftBodyManifold` of that body's
*whole* contact set, and there is no removal callback at all. So began and ended
are derived rather than reported: the same `ContactRecorder` (registered as both
listeners, so a sketch reads one list) accumulates the set as it arrives and
`finishSoftStep` diffs it against the previous step's once `Update` has
returned. Three details are load-bearing. The event's point and normal come
from the *first* particle to report a pair, which keeps the choice deterministic
(the particle array is in a fixed order); the pair is stored low id first and
the normal turned around when the soft body is the second of the two, so the
"normal runs from `a` toward `b`" rule holds either way. `speed` reads
`inSoftBody.GetLinearVelocity()` **during the callback**, which is the velocity
the body arrived with, because the update averages the new particle velocities
into it only afterwards, and reading the *other* body's would be a documented
race. And a sleeping soft body's touches are **held rather than ended**: the
solver stops asking it, which is not the same as it having let go. (That is a
deliberate difference from the rigid rule, where the solver genuinely reports
the removal; it is also what tells the buoyancy pass below that a sunk sheet is
lying on something rather than stalled in mid water.)

Sensors ride `BodyCreationSettings::mIsSensor` plus a fourth object layer
(`SENSOR`) that pairs only with `MOVING`, so a trigger volume never spends a
step colliding against static scenery or another sensor. The DX decision here
came from the library's own note: a *static* sensor only detects **active**
bodies, and Jolt drops the contact the moment a body falls asleep, so a
pressure plate would report empty the instant its load settled. A sensor is
therefore created **kinematic and activated** whatever `kind` was asked for
(`Body::UpdateSleepState` exempts sensors from sleeping outright), which is
what makes `sensor.touching` answer the standing occupancy question that
`Body3D.touching` on ordinary solids cannot: a settled pile sleeps and stops
reporting, pinned deliberately by `aSleepingPileStopsReportingItsTouches`
against its sensor counterfactual. Ray casts take a `NonSensorBodyFilter` so
the cursor looks through a trigger to the solid scene, and `Body3D.kind`
refuses to change a sensor's motion (with a `noteOnce`) rather than silently
turning it solid. The `ground` slab became a registered-but-unlisted `Body3D`
(`world.groundBody`, in `bodyByID` so a contact can name it, out of `bodies`
so no drawing loop has to skip a 1000-unit box). `Contact3DTests` pins the
tier behaviorally, each against its twin: a sensor passes a ball through to
exactly the height an empty scene would while a solid one catches it, a
compound's simultaneous foot contacts report one event where two loose boxes
report two, impact speed tracks √(2gh) across drop heights, the list survives
being read twice and empties on a quiet step, a removed body leaves no stale
touches, and two identical worlds log identical event sequences.

### Characters

`Character3D` wraps Jolt's `CharacterVirtual`, which is a different kind of
object from everything above it: not a body the solver integrates, but a shape
the library sweeps through the world by hand on demand. It is not in the broad
phase, nothing collides with it by default, and the `PhysicsSystem` does not
know it exists. That shape drives every structural decision in the tier.

It needs its own bridge object and its own update call. `CJoltCharacter` holds
the `Ref<CharacterVirtual>` plus the two distances the combined update takes
(`stepHeight`, `stickToFloor`): those are *arguments* to `ExtendedUpdate`
rather than state on the character, so the wrapper is where they live.
`World3D.step(dt:)` advances every character **before** `cjolt_world_step`,
which is the order the library's own sample runs in: the character sweeps
against the world as it currently stands, then the solver integrates the
bodies. `ExtendedUpdate` is the update to call rather than `Update`, because
it is the one that also walks stairs and sticks to the floor; both distances
run along the character's own up axis, which must match the world's y-up.

Two geometry decisions make the API pleasant. The capsule is built
bottom-at-origin (a `RotatedTranslatedShape` lifting a `CapsuleShape` by
`halfHeight + radius`), so `position` is the character's **feet**: a figure
modeled standing at the origin stands on the ground in the world, and
`withCharacter` is a plain translate. And `mSupportingVolume` is
`Plane(up, -radius)`, so only contacts against the lower cap can hold the
character up; without it a hand brushing a wall counts as ground. `isOnGround`
reads `GetGroundState()` rather than testing a normal, because the library
already distinguishes *supported by ground you may walk on* from *supported by
a slope you may not* from *touching something that cannot hold you*.

**The velocity composition is the library's recipe, and it lives in Swift.**
`Character3D.advance(dt:)` reproduces the sample's `HandleInput`: on the
ground the character inherits `GetGroundVelocity()` rather than keeping its own
fall speed (which is what makes a moving platform carry it, and is the only
moment a jump may be added), in the air it keeps just its vertical velocity so
gravity accumulates, gravity is added, and the walking velocity is added last
and always. Ollin takes the no-inertia, air-control-on branch: the sketch owns
input feel, and Ollin already has easing and springs for anyone who wants
smoothing. Keeping the composition on the Swift side leaves the C bridge a
thin mechanical wrapper and the policy visible where Ollin's DX decisions live.

**`velocity` is intent; `actualVelocity` is outcome.** The library never
writes the achieved velocity back into `mLinearVelocity`, so a character pinned
against a wall still reads a full walking pace. The sample derives an
"effective velocity" from the position delta across the update, and
`Character3D` does the same, publishing it as `actualVelocity`. The pair is
worth having rather than tidying away: `velocity` is the right thing to read
for what the character is attempting, and `actualVelocity` is the only correct
input to a walk cycle, which otherwise skates on the spot against a wall.

**Every character always carries an inner rigid body.** `CharacterVirtual`
supports an optional `mInnerBodyShape`, and Ollin makes it mandatory rather
than a flag: it is what gives the character presence among the ordinary
bodies, so ray picking finds it, the stage-4 `ContactRecorder` reports it,
sensors see it walk in, and a fast body cannot pass through it in one step. It
is created kinematic in `Layers::MOVING` at 0.9× scale so it never collides
before the swept shape does, and the library filters it out of the character's
own queries. On the Swift side it surfaces as `character.body`, registered in
`bodyByID` (so a `Contact3D` can name it) but deliberately kept out of
`world.bodies`, the `groundBody` precedent: a drawing loop over the bodies
should not render a capsule where the sketch draws its own figure. Characters
also register in the world's `CharacterVsCharacterCollisionSimple`, since
otherwise they would pass through each other.

Three envelope facts, each measured rather than assumed. `stepHeight` is the
distance the stair walk probes upward, not a hard ceiling: the capsule's
rounded foot rides an edge slightly before the probe runs, so a ledge roughly a
quarter taller than the setting may still be climbed (0.4 climbs 0.5, stops at
0.6). That is inherent to the algorithm, so it is documented rather than
compensated for, and the tests use a clear margin. Whether `pushStrength`
actually shifts something is a contest with ground friction, not just mass: a
4 kg crate slides under the default 100 N while a 43 kg one does not, because
friction alone asks for more. And a slope *just* past `maxSlope` reads
`.onSteepSlope` while a near-vertical face reads `.notSupported`, because at
that angle nothing supports the capsule at all.

`Character3DTests` pins the tier behaviorally, each knob against a
counterfactual twin that isolates it: the same 40° ramp is climbed or refused
by `maxSlope` alone, the same 0.3 ledge is a step or a wall by `stepHeight`
alone, the same crate scatters or blocks by `pushStrength` alone. Around those
sit the standing/falling/steep readbacks, jump-only-from-the-ground, a platform
carrying the character exactly as far as it travels, a sensor reporting the
walk-through, teleporting re-reading the ground, and identical replays.

### Vehicles

`Vehicle3D` wraps Jolt's `VehicleConstraint` plus its `WheeledVehicleController`
(or the `MotorcycleController` subclass). The shape of the tier follows from
one fact: **a vehicle is a constraint on a body, not a body.** The chassis is
an ordinary `Body3D` created through the same path as everything else, so it
collides, takes impulses, reports contacts, is ray-pickable, and lives in
`world.bodies`; the constraint on top owns the wheels, the suspension springs,
and the drivetrain. Creating one therefore does three registrations, and
missing the third is the classic mistake (upstream's own header warns about
it): `AddConstraint`, then `AddStepListener`, because the wheels are collided
and driven inside `PhysicsStepListener::OnStep` and a vehicle without that
listener keeps its shape and simply never moves. Teardown reverses both, and
`World3D.remove(_:)` destroys the constraint *before* the chassis body, since a
constraint may not outlive a body it holds.

Two fields were added to `CJoltBodyDesc` for the chassis and are used only
there so far: an explicit `mass` (`EOverrideMassProperties::CalculateInertia`,
so a 1500 kg car is 1500 kg whatever its box's volume) and a `centerOfMass`
offset, applied by wrapping the finished shape in an
`OffsetCenterOfMassShape`. The wrapper is load-bearing for drivability (weight
at roof height levers a car over in the first corner) and free for drawing,
because Jolt's `GetPosition()`/`GetWorldTransform()` report the *shape origin*
rather than the center of mass, so `withBody` is unaffected. `addVehicle`
defaults the offset to the mean height of the wheel mounts, which reproduces
the reference sample's hand-picked value for a normal layout.

**Axles are derived from geometry, not from list order.** The public surface is
per-wheel (`steers`, `driven`), but Jolt wants differentials and anti-roll bars
addressed as left/right index pairs. `Vehicle3D.axles(of:)` sorts wheels by
`(z, x, index)` (deterministic, the catalog rule), clusters them where their
`z` agree within a quarter of the wheelbase, and pairs within a cluster; a lone
wheel becomes a single-wheel axle with the other index `-1`, which is how a
two-wheeler's front and back come out right where pairing by list order would
have made one nonsense "axle" out of them. An axle with any driven wheel gets a
differential (engine torque split evenly across driven axles), and every full
pair gets an anti-roll bar. **At least one axle must be driven**: with zero
differentials the controller's own debug assert on the torque split fires (the
ratios sum to 0 rather than 1), so with nothing marked the rear axle takes it.

**Gearing is solved from a speed rather than exposed as ratios.** The gearbox
keeps the library's default gear ratios, and the differential ratio is derived
in the bridge (where those ratios live) from `topSpeed`: top gear at the
engine's max RPM must turn a driven wheel of the measured radius that fast.
That turns an opaque number into one a sketch understands, and it stays live,
since `GetDifferentials()` is writable between steps. Ollin does **not** adopt
the sample's `SetTireMaxImpulseCallback` 10× longitudinal hack, which exists
only to preserve the feel of settings tuned against an old bug; the library's
physically-correct Coulomb limit is used, and the defaults (500 N·m against a
30 units/s top speed) were picked by measuring a torque sweep, not by copying
the sample's numbers. That sweep is also what settled `suspensionTravel`'s
0.3 default: at 1.5 Hz a 1500 kg car sags ~0.11 m, so 0.2 sat too close to the
bump stops.

**Everything on a wheel is live, `driven` included.** `applyWheelDesc` writes a
whole `CJoltWheelDesc` onto a wheel's settings, and the same function serves
the initial build and a retune through `cjolt_vehicle_set_wheel_settings`,
which `const_cast`s the wheel's settings handle. That is safe here and nowhere
else: the bridge news one settings object per wheel and shares it with nothing,
and the solver re-reads every field on each step. The friction curves are
rebuilt from a default-constructed tire before `grip` scales them, so repeated
pushes cannot compound. `driven` is the gearbox rather than the wheel, so it
goes through `cjolt_vehicle_set_drive`, which rebuilds the differentials (or a
tracked machine's two sprockets) and re-solves the gearing against the new
driven radius, so the vehicle keeps the `topSpeed` it was given. That is why
`CJoltVehicle` remembers that speed. **The rebuild waits for the step rather
than happening on the assignment**, and that is load-bearing rather than an
optimization: which wheels drive is set a list at a time, and each wheel's flag
is only half an answer while the loop is still running. Rebuilding eagerly
means the drivetrain's report-back (an axle the engine turns drives *both* its
wheels) lands in the middle of the sketch's loop and undoes the assignments
still to come, so `for wheel in car.wheels { wheel.driven = wheel.position.z > 0 }`
ends with all four driven. Deferring to `advance()` makes the whole list one
edit, resolved once.

Three smaller decisions. The wheels' collision tester gets a body filter that
rejects both the chassis and any sensor, because overriding the filter replaces
the default one that hides the vehicle from itself, and a detector volume is a
region to drive through rather than a surface to ride on. All three testers
(ray, sphere, cylinder) are built up front and switched by reference, so
`wheelContact` costs nothing. And the wheel pose comes back as a position plus
a quaternion posing a **+y-aligned cylinder** (`GetWheelWorldTransform(i,
Vec3::sAxisY(), Vec3::sAxisX())`), which is the axis convention `drawCylinder`
already uses, so `withWheel` is a translate and a rotate with no fixups.

**The tracked sibling is a third controller, and the wheel type goes with it.**
`tracked: true` builds a `TrackedVehicleControllerSettings` instead, whose
`ConstructWheel` asserts on the wheel settings type, so the bridge news
`WheelSettingsTV` rather than `WheelSettingsWV` for every wheel. That split is
the reason `applyWheelDesc` became a shared base over two overloads: the
suspension, the position, and the radius are the same on both, while a rolling
wheel takes steering, brakes, and friction *curves* read against slip, and a
road wheel takes a flat pair of coefficients (4.0 longitudinal, 2.0 lateral by
default, which is why a band keeps pulling while it slides where a tire's curve
falls away past its peak). `cjolt_vehicle_get_wheel` guards its `WheelWV` cast
on the kind for the same reason; a `WheelTV` has no slip to report.

Three decisions shape the tier, all of them on the Ollin side. **The bands come
from geometry, like axles do:** the driver's right is `-x`, so the left band
takes the wheels at positive `x`, and a machine whose wheels all sit on one side
is refused rather than half-built (the controller looks each wheel's track up by
an index it fills in from the two lists, and a wheel no track claims keeps the
`-1` it was born with). The axle list is still computed and still passed, but
for a tracked machine it is read only for the anti-roll bars, which live on the
constraint rather than on the controller. **Steering is mapped in the bridge**,
because the library takes a rotation-rate multiplier per band rather than an
angle: `steering` runs the inside band at `1 - 2·|steering|`, so half lock stops
it and full lock reverses it. Neither ratio may be exactly zero (the controller
divides by them, and asserts), so a stopped band is spelled as a very slow one.
**Track inertia is derived, not exposed.** `VehicleTrackSettings::mInertia` is
the band's moment at the sprocket, and the library's default is one number for
one reference machine; Ollin forms it as `share · mass · radius²` with the share
at 0.08, which is a run of track plus its road wheels swung at the sprocket's
radius. It was measured across a range of sizes rather than guessed, and the
range from 0.02 to 0.15 turned out to be within a few percent on straight-line
distance and turn rate, which is why it stays a constant instead of becoming a
knob. The same derivation covers the brake: a band's `mMaxBrakeTorque` is the
sum of its wheels' `brakeTorque`, so the shipped per-wheel knob keeps meaning
something and a tracked machine needs no new one.

The motorcycle sibling is the same call with `balances: true`. Getting it to
work took one thing the car does not need: `casterAngle`, which rakes both
`mSuspensionDirection` and `mSteeringAxis` back on the front wheel. Without
it the balance controller cannot hold a line and the machine goes over within a
second; with 30° of rake it rides, and leans into a corner. Note that a
two-wheeler running dead straight stays up even with the controller *off*,
because nothing perturbs it, so the counterfactual test starts it leaned over.

`Vehicle3DTests` pins the tier behaviorally, each knob against a counterfactual
twin. The sharpest is the drive-routing one: two identical cars with slick
front tires, differing only in which axle is driven, travel 2× apart, which
pins where the torque goes rather than merely that there is some. Around it sit
the suspension sag (soft vs stiff), braking distance vs coasting, the hand
brake locking only the wheels that have one, reverse braking through a stop,
the top-speed gearing ceiling, wheels-in-the-air, the axle grouping as a pure
CPU test, a leaned two-wheeler righting itself where the unbalanced twin falls,
and identical replays. `TrackedVehicle3DTests` does the same for the tracked
machine, its own sharpest being the pivot: full lock turns it through more than
a full circle without leaving its own length, where the twin given the same
throttle and no steering covers ground and barely changes heading. Around it
sit the band split, one sprocket per band, the bands running opposite ways in a
pivot and the inside one stopping at half lock, steering needing throttle at
all, a road wheel neither steering nor slipping, the brake and the hand brake
pulling the same one, slick bands climbing less of the same bank, and the live
`driven` rebuild pinned through the wheeled routing test (a car switched to
front drive after it was built goes nowhere on slick front tires where its
rear-driven twin keeps its legs).

### Ragdolls

A `Ragdoll3D` (`Sources/OllinPhysics/Ragdoll3D.swift`, the fitting in
`RagdollFit.swift`) turns a skinned `Scene` into a tree of rigid bodies and
writes the simulated pose back onto the skin. It is built on the library's own
`RagdollSettings` / `Ragdoll` pair rather than on loose bodies and constraints,
which buys three things the loose form would have to reinvent: `Stabilize()`
(the Havok mass-ratio and inertia treatment, without which a light hand on a
heavy arm makes the solver fight itself), `CalculateConstraintPriorities()` (the
root solved before the leaves), and `DisableParentChildCollisions()` (the group
filter that stops a thigh from fighting the pelvis it sits inside).

**The layout decision everything else follows from: a limb's body stands at its
joint, not in the middle of its bone.** The shape is pushed out along the bone
inside the body instead, through the same `RotatedTranslatedShape` the character
capsule uses. That makes the body's world transform *identical* to the joint's
world transform, so reading the pose back is an assignment with nothing to
undo (the write-back test pins node positions equal to body positions to 1e-5),
and the local rotation a motor is aimed at is exactly the skeleton's own local
rotation. The alternative (bodies centered on the bones, as the library's own
sample authors them by hand) would need a per-joint offset carried through every
read and write.

**The skeleton seam lives in the core**, since satellites never depend on each
other: `Scene.skeleton()` flattens the first skin's joints (name, file identity,
parent within the skin, current world transform, inverse bind matrix),
`Scene.skinnedVertices()` hands over the mesh in bind space with its joint
weights, and `Scene.setJointWorlds(_:)` is the write-back, all `package` in
`Sources/Ollin/3D/SceneSkeleton.swift`. `setJointWorlds` walks top-down so a
joint it writes is what its children are placed against, preserves whatever
scale a node carries (a rigid pose has none, and dividing it out would shrink
the mesh), and re-syncs a node's TRS animation base to the posed transform so a
rotation-only track applied next frame does not drag the node back to its
authored translation. Joints it is not given keep their local transform and ride
their parent, which is what makes a partial ragdoll (one that skips the fingers)
carry the rest of the figure rigidly.

**Shapes are fitted to the mesh, not derived from bone lengths.** Each vertex is
assigned to the limb whose weight over it is largest (summed over the joints
that limb absorbed), transformed into that joint's frame by its inverse bind
matrix, and a capsule is fitted: the axis is the dominant eigenvector of the
covariance (power iteration seeded from the largest-variance world axis, so the
start can never sit at right angles to the answer), the radius the 85th
percentile of the perpendicular distances, and the ends the 2nd and 98th
percentiles along the axis. Percentiles rather than extremes, because one stray
vertex should not decide how thick an arm is; the axis is flipped to point away
from the parent joint so the twist convention is consistent. A limb with too
little mesh falls back to the bone to its children, and one with neither to a
small ball. The measured result on the bundled figure: a torso radius of 0.157
against a forearm's 0.051, from bones of similar length. Mass is split by fitted
volume and then rebalanced by `Stabilize()`, which preserves each chain's total,
so the figure weighs what the call asked for.

**Powered figures.** `drive(toward:)` reads the target scene's joint worlds,
converts each to the child's rotation relative to its ragdoll parent, and hands
the whole array to `cjolt_ragdoll_drive_to_pose`, which sets both motors of
every swing-twist to `Position` and calls `SetTargetOrientationBS`. The spring
(frequency, damping) and the torque cap are re-applied on every call, so
`strength` is live. The root has no constraint, so a powered figure holds its
*shape* and still falls as a whole; pinning the root limb kinematic is the
puppet-on-a-hook answer, and `ragdoll.kind = .kinematic` routes `drive(toward:)`
to `MoveKinematic` instead, giving the figure arrival velocities so it shoves
what it walks through.

**Bodies in, but not in `bodies`.** Each limb is wrapped in an ordinary `Body3D`
and registered in `world.bodyByID` (so contacts, sensors, and ray picking name
it) while staying out of `world.bodies`, the `groundBody` / `character.body`
precedent: a sketch draws the figure's mesh, not the capsules. Making that
useful needed one fix elsewhere: `body(under:in:)` looked its hit up in
`world.bodies`, so it could never find a limb; it now looks up `bodyByID`, which
also makes a character's stand-in and the ground slab pickable.

`Ragdoll3DTests` pins the tier behaviorally (no pixel snapshots, the physics
policy). The headline counterfactual is the same figure dropped twice, once
driven toward its rest pose and once limp: the shape error (per-limb offset from
the built pose, measured in the root's own frame so falling over does not count
as deforming) is 0.48 limp against 0.034 powered. Around it sit the fit
proportions, mass split, placement, the named-joint subset and what the skipped
joints do, the exact write-back, `pose(from:)` as a reset, a weaker motor
sagging further, the kinematic figure shoving a crate out of its way, a
cone-limited joint stopping where a `.ball` keeps going, a tighter cone holding
a figure straighter, per-joint retuning, limbs naming the floor they land on,
parent-child pairs never reporting a touch while two figures do, and identical
replays.

### Soft bodies

A `SoftBody3D` (`Sources/OllinPhysics/SoftBody3D.swift`) is the one member of
the tier whose state is not a pose. The solver's soft body is position-based
dynamics over a set of particles with springs between them; the bridge
(`cjolt_soft_body_*`) builds one `SoftBodySharedSettings` per body from a mesh,
lets the library derive stretch, shear, and fold constraints from the faces, and
hands the result to `CreateAndAddSoftBody`. It is a real body in the world (it
collides with the rigid bodies and a ray cast reports its id), so it needs no
step listener or hand update the way a character and a vehicle do.

**Welding is a precondition, not a nicety.** Ollin's generators emit flat-shaded
meshes whose triangles share no vertex index, and a soft body built from one has
no connectivity at all: it would fall apart into loose triangles on the first
step. `addSoftBody` runs the mesh through the core's `package` `Mesh.welded()`
seam (`Sources/Ollin/3D/MeshWeld.swift`, a thin public-to-the-package face over
the existing internal `WeldedMesh`, the same seam `MeshReactionDiffusion` needs
for the same reason), simulates on the merged particles, and republishes through
the `remap` so `positions` and `mesh` still line up with the source mesh index
for index. That is what keeps uvs, colors, and the material intact.

**Normals follow the source mesh, not the winding.** The read-back derives
normals from the simulated positions, and the obvious cross-product order is
right only if the mesh winds the way you assume. Ollin's own catalog does not
agree with itself here (the same trap the subdivision surfaces hit), so a
`Mesh.plane` came back lit from underneath. The fix is a one-time area-weighted
vote at build time: derive the normals for the *rest* shape, dot them against
the mesh's authored normals, and remember a flip if the sum is negative.

**Two knobs, both made scale-free, both by measurement.** The library's own
numbers are physical and therefore useless as a 0…1 dial:

- *Compliance* (the inverse stiffness of a spring, in m/N) has to be compared
  against the load, so one fixed value visibly softens a heavy cloth and does
  nothing at all to a light one. The knob is normalized by the body's own
  hanging weight: `scale = meanEdge * sqrt(particleCount) / (mass * gravity)` is
  the compliance at which one loaded edge stretches by its own length, and
  `stiffness` maps onto a fraction of it. Measured: mean edge stretch runs
  1.0005 at `stiffness: 1` to 1.22 at `0.05`, and a 0.2 kg cloth and a 20 kg one
  agree to four decimals (`stiffnessMeansTheSameAtAnyWeight` pins that).
- A *fold* constraint measures an angle where a stretch constraint measures a
  length, so its compliance carries two fewer powers of length. `bend` therefore
  divides the same scale by the mean edge squared. Without that correction the
  whole 0.2…1.0 range of the knob was already rigid, which the first probe found
  by sweeping.

`pressure` is the third: the solver's number is `n R T`, and working the force
through `ApplyPressure` gives an outward acceleration of `pressure * area /
(mass * volume)`. Expressing the knob as that acceleration *in gravities* makes
`pressure: 1` mean "just holds its own weight up" at any size, and the rest
shape's area and volume are measured once at build time to convert. It is
refused on an open surface with a one-time note, the closed test being that
every edge belongs to exactly two faces.

**A soft body is a thing in the world**, which took three seams. Its touches
reach `world.contacts` through the soft contact listener described above, and
the same widening that made that possible (a contact naming
`any Colliding3D` rather than two `Body3D`s) let the query surface stop looking
through one. Buoyancy is its own loop (see *Water and buoyancy*). The shared
protocol is deliberately tiny (`group`, `isAwake`, `wake()`, `userData`, all of
which already existed on both types) because the *difference* between the two
kinds is the honest part: a cast to `Body3D` is what a sketch writes before
applying an impulse, and it fails for exactly the reason it should.

**What the tier does not do**, all of it the library's own envelope rather than
a shortcut: soft bodies collide with rigid bodies but not with each other or
themselves; impulses and constraints do not apply to one (hence `applyForce` for
wind, and a grip that *pins a particle* rather than adding a joint); and there
is no tearing, because a tear has to split a shared vertex and rebuild the
constraint set, which cannot be done to a body mid-simulation.

#### Why there is no tetrahedral solid

The solver has a sixth constraint family the bridge does not build: a **volume
constraint** over a tetrahedron, held at the volume it started with, which is
how a body resists being squashed through its *interior* rather than only at its
skin. Its cost is that nothing in the library builds one. `CreateConstraints`
derives edges and bends from *faces*, so the tetrahedra are the caller's to
supply, and the only tetrahedral body upstream ships is `sCreateCube`, whose
lattice *is* its surface. Any other shape has to be meshed, and the tractable
form of that is a lattice: fill the bounds with a grid, keep the cells a parity
test puts inside the surface, split each into six tetrahedra, and tie the skin
to the result.

Both models were built and measured against each other before the question was
answered, because the answer decides whether a whole meshing pass and two more
knobs earn their place. The shipped one wins or ties everywhere that matters, on
a 5 kg ball of radius 0.5 against a lattice six cells across:

| | `pressure: 20` | interior lattice + tetrahedra |
|---|---|---|
| a 25 kg weight on it | 99.2% of its height, 100.0% of its volume | 100.4%, 100.0% |
| a finger driven 0.4 in, then withdrawn | no dent left, 100.0% of its volume | no dent left, 100.0% |
| pressed to 45% of its height, released | **100% of its height, 100% of its volume** | 111%, 103% |
| the same on a cube | **99%, 97%** | 115%, 60% |
| holding an authored cube's volume at rest | 122 to 127% at `bend: 0`, 100.6 to 103.5% at `bend: 1` | 100.0% |
| particles | 162 | 243 |

Three readings settle it. The **load case is a tie**, so the tetrahedra are not
buying the thing they exist for at any load a sketch would apply. **Recovery
from a hard squash goes to pressure**, which is the case a jelly demo actually
is. And the one place the lattice plainly wins, holding an authored shape with
corners, is won by its interior **springs** rather than its tetrahedra: the same
lattice with the tetrahedra removed holds the same 100.0%, and `bend` closes
most of that gap on a pressurised body anyway, which is guidance worth having on
its own and is on the soft-body page.

The recovery gap is structural rather than tunable, and it is one line of the
vendored source: `ApplyVolumeConstraints` forms its residual as
`abs(signed volume) - restVolume`, so a tetrahedron that has been turned inside
out reads as *satisfied* and nothing pushes it back. A hard squash is exactly
what inverts one. A gas law has no such failure mode, since `nRT/V` grows
without bound as the enclosed volume shrinks, which is why the pressurised ball
comes back round every time.

Two things would reopen it: a vertex-follows-tetrahedron binding in the solver
(so a real surface could ride a lattice instead of hanging off springs, which is
what a proper embedded solid does and what Jolt's skinned constraints, which
bind to a *skeleton*, cannot express), or a signed volume constraint that can
drive an inverted tetrahedron back out.

Found while probing this, and fixed rather than worked around: a soft body built
from `Mesh.cylinder` detonated inside half a second, because the generator wound
both cap fans into the solid while its wall wound out of it, leaving the surface
with no consistent inside. `Mesh.pyramid`, `Mesh.roundedBox`, `Mesh.extrude`,
and `Mesh.cone` carried versions of the same defect, and `parametricSurface`
derived its normals as `du × dv` while winding its quads the other way, which
shaded the superellipsoid, the supershape, the Möbius band, and the Klein bottle
from the side the light is not on. Nothing culls back faces and every mesh
carries its own normals, so none of it showed in a snapshot; `MeshTests`
now pins consistent outward winding and normal/winding agreement across the
catalog.

`SoftBody3DTests` pins it behaviorally against counterfactual twins: a pinned
sheet hangs where a free one lands on the floor, a stiffer cloth stretches less
under the same load, a fold-resisting sheet held at its middle stays a plate
where a limp one falls around the pin, a pressurized ball keeps a height and
volume a limp one loses and shoves a crate further, pressure on a sheet changes
nothing at all, a cloth drapes over a sphere rather than through it, a wind
holds a banner out, and identical runs replay identically.

### Cloth a skeleton carries

The solver has a second way to hold a particle, beside pinning it: a *skinned
constraint* ties it to a set of joints and caps how far it may travel from where
they put it. That is what turns a hanging sheet into a cape. Ollin exposes it as
four parameters on the same `addSoftBody` call (`skinnedTo:` a scene,
`carriedBy:` a closure naming a joint per vertex, `sway:` a leash, `backStop:` a
clearance) plus `SoftBody3D.follow(_:)` and `snap(to:)`.

**The bind pose is whatever the figure is standing in when the cloth is built,
which is what makes it need no authored weights.** The solver's `InvBind` takes
a particle's rest position into a joint's own space; Ollin forms it as
`jointWorld_bind⁻¹ · placement`, where `placement` is where the rest shape was
put. Every later pose then reads as the motion since. This has a second payoff
that is not obvious: **the bind pose does not have to be remembered to be
recovered**, since `placement · invBind⁻¹` is that joint's bind transform back
exactly. That is what lets a surface restored from a snapshot, with no scene in
sight, open standing in the pose it was hung in rather than collapsed on its own
origin.

Scale is handled by dividing *only the translation* of every joint matrix by
`unitsPerMeter`. For an affine `[R|t]` that is exactly the conjugation
`S⁻¹ [R|t] S`, so a bind and a later pose converted the same way compose in
meters precisely as they did in world units.

**A particle held exactly on the skin is made kinematic, and that is the link
between the two halves of the slice.** The library treats `maxDistance == 0` as
"kinematic" for the skin constraint's own purposes, but leaves the particle's
inverse mass alone, so the springs still drag it about. The bridge zeroes the
inverse mass instead, which does three things at once: the particle really does
hold still, `CalculateClosestKinematic` can see it, and therefore the long-range
attachments (`maxStretch:`, the LRA constraints of Kim/Chentanez/Mueller-Fischer,
which Ollin drives at `GeodesicDistance` so a cloth that has to reach round a
corner is not over-constrained) work from anchors the *skin* holds rather than
only from ones pinned to the world. Measured: a 6 kg cape hangs 8 cm long on its
springs alone and exactly at its rest length with `maxStretch: 1`.

**`sway` and `backStop` are raw lengths, and that is a deliberate departure from
the stage-8 rule.** Stiffness, bend, and pressure all needed a derived
normalization because compliance is m/N and means different things on different
bodies. A distance does not: probed across the range, a sway of 0.02 held every
particle within 0.0202 of its skinned position, 0.05 within 0.0504, 0.1 within
0.1009, and a back stop of 0.02/0.1/0.4 held the cloth 0.0200/0.1000/0.4005 past
the skin. The rule is about *compliance*, not about every physical number the
library takes.

**`follow(_:)` records; `World3D.step` applies.** `SkinVertices` interpolates
from the previous skin pose to the current one across the step's iterations, so
it must be called exactly once per step; recording the pose and handing it over
beside the character and vehicle passes is what guarantees that, and it keeps the
"call it before `step`" contract meaningful. `snap(to:)` is the other half and
applies at once, since a teleport should be readable before the next step.

**A pose that changed is what wakes the body, and it had to be.** The skin
constraints are solved *during* the update, so a cape that has hung still long
enough to settle and fall asleep stops answering the figure entirely: stand
still until it settles, walk away, and it is left behind (the probe caught this
outright, with a fully hard-skinned cape reading 1.39 units adrift). Comparing
this frame's flattened pose against the last applied one costs a few hundred
float comparisons and wakes the body only when the figure has actually moved,
which is also what still lets a cape on a still figure sleep.

Build order inside `cjolt_soft_body_create` is load-bearing: the skinned
constraints and their inverse-mass zeroing go in *before* `CreateConstraints`
(which is where the LRA constraints are derived, and it can only see kinematic
particles that already are), and `CalculateSkinnedConstraintNormals` runs before
`Optimize`. Both are no-ops for a body nothing carries, so every existing soft
body is untouched.

The snapshot writes the skin down rather than naming a scene for it: the
closures that decided which joint carries what, and how long each leash is, are
a sketch's and cannot be carried, exactly as the pinned list already could not
be. That is one `simd_float4x4` per joint plus six numbers per carried particle
(measured 4.7 KB for a 169-particle cape), and it needs no new `PhysicsAsset`
case, because the mesh is already named. `SkinnedCloth3DTests` pins the tier
against counterfactual twins: a cape goes where its figure goes where an
unskinned twin stays put, a settled one still answers a figure that walks away,
each leash holds to within 5%, cutting the skin loose multiplies the reach
five-fold, the back stop holds the cloth off the figure a free one sinks into,
a snapshot round trip is exact to 1e-6 and still follows a figure it has never
seen, and identical runs replay identically.

### Ropes, and the frame a rod carries

A `Rope3D` (`Sources/OllinPhysics/Rope3D.swift`) is a `SoftBody3D` whose
particles are held by **Cosserat rods** rather than springs. The solver has
seven soft-body constraint families and the bridge built four; this is the
fifth, and it is the one that carries an *orientation*: a rod holds a rotation
of its own, integrated beside the particle positions, so geometry attached to it
turns as the rope bends and twists. A chain of springs cannot express that,
because a frame guessed from neighboring points has no roll.

**A rope is the first body with no surface at all**, which is why the slice
starts in the bridge. `cjolt_soft_body_create` refused a description with no
faces, on the reasonable ground that a triangle is the smallest simulable
surface; with rods it is not the smallest simulable *thing*. The guard now asks
for faces only when there are no rods. Everything downstream of that turns out
to cope: `CreateConstraints` derives its long-range attachments by walking every
vertex rather than every face, and `CalculateClosestKinematic` walks rods beside
edges, so `maxStretch:` works on a rope with no faces exactly as it does on
cloth (measured 1.80 uncapped against 1.00 capped on the same hanging rope) as
long as the rods go in *before* `CreateConstraints`, the same ordering rule the
skin already needed.

**Two things the solver does to the rod list have to be undone on the way out,
and both are the bridge's to know.** `Optimize()` reorders the rods so it can
solve them in parallel, and `CalculateRodProperties()` reverses any rod pointing
against its neighbor, so that neighboring rods agree on which way is forward.
The handle therefore records, per rod the caller handed over, where it ended up
and whether it was turned around; the read-back walks that map and multiplies a
reversed rod's rotation by a half turn about its own x axis, which sends its +z
back the way the caller asked for and leaves a right-handed frame. So `segments`
speaks in the caller's own order and direction, and the `RopeSegment.rotation` a
sketch reads is the same convention `withSegment(_:)` applies (local +y along
the rope, matching the axis Ollin's cylinders and capsules stand on; local +x
carries the twist).

**The bend knob needed its own scale, and the scale had to be measured.** The
stretch constraint is a distance constraint with an orientation term bolted on,
so the shipped cloth normalization (`meanEdge * sqrt(particleCount) /
(mass * gravity)`) transfers to it unchanged and is exact across weight. The
bend-and-twist constraint is not: it holds a *rotation*, a pure number, against
a generalized mass in units of inverse kilograms, so there is no length in it to
compare against and no derivation to do. Hanging a rope out sideways and asking
what compliance leaves the tip drooping by a third of the rope's own length, at
several lengths and particle counts, gives

    compliance  ∝  meanRod² / (length³ · mass · gravity)

with a measured constant that puts "drooping about a third" in the middle of the
knob. Before the correction the knob's meaning ran away with length: `bend: 0.1`
left a half-unit rope nearly rigid (drop/span 0.13) and a six-unit one limp
(0.92). After it, `bend: 0.5` lands at 0.26 to 0.33 across twelve-fold in length,
double in particle count, and a hundred-fold in mass. The one case that stays
out of that band is a long rope divided finely (forty particles over six units),
which is not the normalization failing but PBD's own propagation limit, the same
thing the raft's folding deck runs into: stiffness travels one rod per solver
pass, so `iterations` is the lever, and raising it from 5 to 20 takes that rope
from 0.40 to 0.027.

Both sweeps were **non-monotone at 900 steps and monotone at 3000**, which is
the stage-8 lesson again: a cantilever that has not stopped swinging measures
its swing, not its stiffness.

**Putting a rope back needed the rod frames, and they turned out to be
writable.** `SoftBodyMotionProperties` exposes `GetRodRotation` and no setter,
and `mRodStates` is private, so a restored rope opened every rod in the frame
its *rest* polyline gives while its particles stood in the shape it had reached.
The stretch constraint then hauls each rod round to the direction it is actually
in and drags the particles with it: exact at the moment of restore and 0.36
units out one step later, oscillating for hundreds of frames. The way in is that
`RodStretchShear::mBishop` is read exactly once at runtime, by
`SoftBodyMotionProperties::Initialize`, to seed each rod's state, and everything
else it feeds (`mLength`, `mOmega0`, the rest shape the rope springs back
toward) is computed by `CalculateRodProperties` *before* that. So writing the
saved orientations over `mBishop` after that call and before `Optimize` stands
the rope's rods back up without touching the shape it wants to return to.
Measured on a settled rope: 0.0014 units of drift after one step against 0.361
without, which is what `aRestoredRopeDoesNotSpring` pins as a counterfactual
twin. It also means a rope needs **no `assetName`** to be saved, unlike a
surface: its whole rest shape is a handful of points, so it carries itself.

**The envelope is mostly the tier's, with one piece of its own.** No
self-collision, so a coil passes through its own turns. And `SoftBodyShape` is
built entirely from a body's faces, so a rope is invisible to `raycast`,
`sweep`, and `bodiesOverlapping` (pinned deliberately by
`aRopeIsInvisibleToQueries`) while still colliding perfectly well *with* the
rigid world, because that runs off the particles' own `vertexRadius` spheres
inside the soft body's update rather than off the shape. `grabSoftBody(at:in:)`
would have gone with the queries, so it falls back to the nearest particle
within a few thicknesses of the line of sight, which is what the cursor plainly
means on a rope anyway. Branching is out: a rope is one strand, and a plant with
several stems is several ropes.

#### Why there is no hair tier

Jolt v5.6.0 vendors a whole `Jolt/Physics/Hair/` module beside the soft-body
solver, with 49 shader files behind it. It simulates a groom of hair strands as
Cosserat rods, which is the same maths `Rope3D` already rides, plus a velocity
and density grid that lets strands push on each other, plus an interpolation step
that draws ten render strands around every simulated one. It is not exposed, and
the reason is a fit problem before it is a cost problem.

**It cannot be blown.** `Hair` takes no force of any kind: the whole external
input is the head's transform, the scalp's joint matrices, and the velocities of
the shapes it collides with, and the string `wind` does not occur anywhere in the
49 shaders (upstream's own missing-features list in `Hair.h` names wind forces
first). Hair moves because the head moved, and by nothing else. Every cloth and
rope thing Ollin ships is built the other way round: the Drape, Cape, and Rigging
examples all gust, through `applyForce`. A strand tier that cannot be blown is
not the tier this framework wants.

**It only collides with `ConvexHullShape`.** Every other shape sub-type is
skipped without a word (`Hair.cpp`, the `GetSubType() == EShapeSubType::ConvexHull`
tests). Ollin's figures are meshes and capsules: a ragdoll limb is a capsule and
so is a character, so hair would pass straight through everything the framework
actually builds.

**Its input is an authored groom, not a generated one.** `HairSettings` wants
simulation strands, render strands, a scalp mesh, that scalp's inverse bind pose
and skin weights, and per-frame joint matrices, and nothing in Jolt reads a groom
from a file. In Ollin the sketch is what makes the geometry, and once a sketch is
placing strands the whole scalp-and-bind-pose apparatus is overhead:
`addRope(through:)` already takes a polyline.

**And it is a secondary-motion system, by design.** Measured on 200 strands run
for 10 s at the shipped defaults: gravity moves the tip of a 175 mm strand by
2.15 mm, against 0.02 mm with the gravity factor zeroed. Long-range attachments
and the global-pose pull hold the hair in the groom it was authored in, which is
right for a game character whose hair should stay styled and is the opposite of
what a sketch asks for.

The measurement that made the decision cheap is that the rod family **already
exposed** carries more strands than the hair module does. Nothing requires a
soft body's rods to form one chain, so one body can hold a whole groom. On an M2
in release, 8 particles per strand, every root held and every body awake:

| strands (particles) | one soft body of rod chains | `Rope3D`, one body each | Jolt `Hair`, its own CPU backend |
|---|---|---|---|
| 1,000 (8,000) | **0.94 ms** | 1.30 ms at 800 | 5.93 ms |
| 4,000 (32,000) | **3.10 ms** | 8.58 ms | 20.28 ms |
| 10,000 (80,000) | **6.90 ms** | past the body budget | 25.74 ms at 4,000 simulated |
| 20,000 (160,000) | **12.45 ms** | past the body budget | past the frame |
| 40,000 (320,000) | 26.02 ms | past the body budget | past the frame |

So the shipped solver holds **20,000 fully simulated strands inside a 60 fps
frame** where the hair module holds about 2,500, and it does it with no new build
machinery at all. The honest caveat is that those hair figures are its **CPU**
compute backend, whose `Dispatch` is a serial loop over every thread and which
upstream describes as being for debugging rather than for speed, so a Metal
backend would be much faster than the table shows. That is exactly the work being
declined: the Metal backend loads a precompiled `Jolt.metallib`, so the 49
HLSL-dialect shaders would have to be cross-compiled to Metal and packaged by a
SwiftPM build step, the backend is Objective-C++ and would have to be admitted
into a target whose whole point is that `cjolt.cpp` is the only code that ever
includes a Jolt header, and the simulation's output is a Jolt-owned compute
buffer that Ollin's renderer would need a new path to draw, since the readback
the header offers is labeled slow and for debugging. All of that pays for a
system that still could not be blown by wind.

`Rope3D`'s own knobs already reach hair scale, which is what makes the
alternative real rather than theoretical: swept from rope scale down, a
cantilever of 8 points at 25 mm spacing droops 0.26 of its span at `bend: 0.5`
and 0.79 at `bend: 0.05`. Below about 10 mm of spacing the bend knob loses its
authority (0.149 against 0.165 across its whole range), which is the floor.

What would reopen it: upstream growing **external forces** and **collision
against more than convex hulls**, and dropping the "currently still in
development" note the header carries, since those two are what make it fit at
all. If hair is wanted before then, the way in is a multi-strand `Rope3D` rather
than this module: one body, many rod chains, drawn with a few interpolated
strands around each simulated one, which is the trick that earns the hair module
most of its strand count and is pure sketch code. The cost to watch there is
build rather than step time, since `CreateConstraints` plus `Optimize` take 3.2 s
at 20,000 strands and 12.5 s at 40,000, which makes strand count a setup-shaped
artwork parameter like `maxVertices`.

### Water and buoyancy

Buoyancy is unlike everything above it in the bridge: the solver does not work
it out. It is an impulse the *caller* applies to each body, each step, before
the step that integrates it, so the whole tier is a loop Ollin owns rather than
a thing configured on the solver. `World3D.step` runs it after the characters
and vehicles have had their turn and immediately before `cjolt_world_step`,
which is where the library's own samples put it.

**Density in, factor out.** The library takes a dimensionless `inBuoyancy`
(the ratio of the fluid's density to the body's) rather than a fluid density,
on the grounds that a plain number is easier to configure. That is the wrong
trade for Ollin, because a body already carries a `density` and the collider
already maps relative density 1 onto 1000 kg/m³, which is water. So the bridge
takes a real density and forms the ratio itself:
`buoyancy = scale · density · totalVolume / mass`. The `totalVolume` is
deliberately the one `GetSubmergedVolume` just returned rather than the shape's
own reported volume, so the ratio is formed against exactly the volume the
submerged fraction was measured against and the waterline lands where the
displaced volume says. That is what makes the headline behavior derived rather
than tuned: a body of density *d* settles with fraction *d* of itself under,
pinned to within 0.08 across the range (the margin is what sleeping costs,
since the solver freezes the body wherever its last small oscillation had
reached rather than at the exact equilibrium).

**Waves are a per-body tangent plane.** The impulse takes a surface *point and
normal* per call, not a world-wide plane, so a swell is expressible: each body
is handed the plane tangent to the surface under its own center of mass. This
is the library's own boat sample's approach, not an invention, and it carries
the honest envelope that a body much larger than the wavelength it rides is
approximated. The surface function lives in Swift (`Water.surface(at:phase:)`,
three crossed sines whose gradient is analytic rather than sampled either
side), which is what lets `waterMesh` and `waterHeight` read the very same
surface the bodies ride: one source of truth, pinned by a test that every mesh
vertex sits at `waterHeight` for its own x and z.

**The query.** `cjolt_world_bodies_in_box` is a broad-phase `CollideAABox` over
the water volume, filtered to dynamic rigid non-sensor bodies and sorted by
handle. The filter is load-bearing three times over: a kinematic body (a
sensor, a character's stand-in) has motion properties an impulse would nudge
off its driven path, a static one has none at all, and the library's buoyancy
is not implemented for soft bodies and asserts on one. Sorting is the
stage-4 rule again, so the per-body pass replays in one order.

**Sleeping is the interesting part, and the wake rule has two modes because
one is wrong.** A floating body settles and sleeps, and that is correct: it
holds its waterline exactly (measured: zero movement over thirty further
seconds) and costs nothing. It stops being right the moment the surface moves,
and the two ways that happens want different answers. A swell wakes only what
its surface passes through, tested against the body's own bounds, so a stone
sunk to the bottom (whose submerged volume no wave shape can change) sleeps on
instead of being stirred awake every step. A *changed setting* has to wake
everything afloat wherever it is, because the equilibrium itself moved. The
first draft had only the swell rule, and a probe caught it: raising the level
from 0 to 3 left a sleeping crate frozen at the old waterline, three units
under the new surface and outside its own bounds, so it never woke.
`CJoltBuoyancyWake` names the three cases rather than passing a bool.

**A soft body is floated by hand, particle by particle.** The library's own
`ApplyBuoyancyImpulse` asserts `IsRigidBody()`, and rightly: it works through one
inverse mass, one inertia tensor, and a submerged volume, and a bag of particles
has none of them (`SoftBodyShape::GetSubmergedVolume` returns a submerged volume
of exactly zero: it is a stub). So `cjolt_soft_body_apply_buoyancy` adds the
impulse to each particle's velocity itself, and three decisions make it work.

*What it takes is a ratio, not a density.* The lift a particle gets is
`(ρ_fluid / ρ_body) · g` upward, which needs neither the particle's mass nor its
share of a volume the surface may not even enclose, so the bridge takes that
dimensionless number and Swift forms it, since only Swift knows what a sheet
weighs per unit of displacement. Hence `SoftBody3D.density`: derived from mass
over enclosed volume when the surface is closed (the rigid tier's
derived-not-tuned rule), and `1` for an open sheet, which has no volume to
derive one from.

*Every particle gets its own surface height.* Where a rigid body is handed one
tangent plane sampled under its center, the call takes an array of per-particle
heights above the surface, computed in Swift from the same `Water.height(at:)`
the drawn mesh uses. This was not a refinement, it was the fix for a real
defect: with one plane, a 4-unit raft on a 9-unit swell reads its far edges
against a wave that is not under them, so every crest gave the edges extra lift
and the deck **curled into a bowl** over about ten seconds. Sampling per
particle made the same deck flat, and it is cheap (three sines per particle, on
a body whose positions the frame reads anyway).

*A particle's push ramps in over a band* about one particle spacing wide, rather
than switching on at the surface. A flat sheet's particles all cross the
waterline at the same instant, so a hard test leaves it with no waterline to
hold and it chatters; with the band, the deck settles where the mean submerged
fraction balances its weight.

Sleeping needed one more rule than the rigid path. A cloth's area for its weight
is enormous, so drag holds a *sinking* sheet below Jolt's own sleep threshold
(`mPointVelocitySleepThreshold`, compared against a squared speed, so an
effective 0.17 m/s) and it would stop dead in mid water and read as though it
floated. The test that fixes it is not a measurement but a fact about the two
densities: **a body heavier than the fluid has no depth at which the fluid could
hold it**, so if it is asleep, submerged, and touching nothing, it has stalled
rather than settled, and it is woken. "Touching nothing" is exactly why a
sleeping soft body keeps its touch list: a sheet lying on the sea bed has its
weight carried and is left alone. An earlier draft compared the *measured* lift
against 1 and failed, because a floating raft's balance sits a few percent under
a full gravity (measured 0.92: the band means it settles slightly high, and the
solver freezes it there).

`Buoyancy3DTests` (25) pins the tier against counterfactual twins: a cork
floats where a stone sinks and where the same cork with no water just falls,
the waterline tracks density across the range, denser water floats the same
body higher, drag settles a body that otherwise still bobs after a minute, a
sleeping floater holds its level, a tide reaches it, a swell carries what
floats and lets the bottom sleep, a current drifts a raft, `buoyancy`
multiplies both ways, sensors and soft bodies are left alone, the drawn surface
is the ridden one, and identical runs replay identically.

### World queries

Ray casts, shape sweeps, and overlap tests (`Sources/OllinPhysics/Query3D.swift`
over four `cjolt_world_*` bridge calls) are the one part of the tier that is not
simulation at all: they run against the world as it stands, between steps, and
change nothing. The public surface is `raycast` / `raycastAll`, `sweep` /
`sweepAll`, `bodiesOverlapping`, and `bodiesContaining`, all returning the
shared `Hit3D` (body, point, outward normal, distance along the query) the way
`Contact3D` is the shared answer for what the solver noticed *during* a step.

Three decisions carry the design.

**The filter is a struct, not a parameter list.** `CJoltQueryFilter` (ignore
list, `includeSensors`, `includeSoftBodies`) travels by pointer into every query
call, so the next way to narrow one, collision layers and groups, is a field
there rather than another argument added to four functions and their Swift
wrappers. Its body-level half is `QueryBodyFilter`, which replaced the old
`NonSensorBodyFilter` the mouse pick used; the broad-phase and object-layer
halves are the same "filter as a moving body would" pair the pick has always
used, so statics stay visible and the ghost layer (grab anchors) never is.

**What a query is blind to was chosen, not inherited.** A sensor is a region to
be inside rather than a surface to hit, so it is transparent unless asked for,
which is the rule mouse picking already followed. Soft bodies started
transparent for a different reason (no single rigid pose meant no `Body3D` to
hand back), and that reason **went away** with the soft-contact work: once a
touch could name `any Colliding3D`, so could a hit, and a hanging sheet blocking
a sightline is plainly the right answer. So `Hit3D.body` is
`any Colliding3D` and every query sees cloth (`ignoring:` and collision groups
are how to look through one). Every public call site of `hit.body` was an
identity comparison, so the widening cost one cast, in the one place that
applies an impulse to what it found. Bodies the world keeps out of `bodies` (the
ground slab, a character's stand-in, a ragdoll's limbs) *are* visible too,
because hits resolve through `bodyByID` rather than by searching that array,
which is what makes a ground probe and a line-of-sight check on a walking figure
work at all.

**The mouse pick is the same call.** It used to be a separate internal ray
(`World3D.pick`) that differed only by seeing soft bodies; once the public
queries saw them too it had nothing left to be, so it went away and
`body(under:in:)` and `grabSoftBody(at:in:)` both call `raycast` and cast the
hit to the kind they can use. A cloth hanging in front of a crate therefore
answers for the cloth, which is what the cursor is on.

The rest is mechanical, with two details worth knowing. A ray's surface normal
can only come from the body itself (the sub-shape id names the face, and a
mesh's faces each have their own), so it needs a `BodyLockRead`; a sweep's
normal is the negated penetration axis, which needs no lock. And the count-out
convention is that the bridge returns how many hits it *found*, not how many it
wrote, so the Swift side sizes a stack buffer of 16, and grows exactly once when
a scene held more.

Sweeping or overlapping with a `mesh` or `heightfield` collider is refused with a
one-time note (`Shape::MustBeStatic()` asked of the created shape, the stage-3
rule): those describe scenery, and the narrow phase cannot carry one as a probe.
`Query3DTests` (24) pins the surface against counterfactual twins: the nearest
body versus the same scene with it removed, line of sight with and without the
wall, a swept sphere stopping exactly its radius short of where the ray reached,
a gap a ray threads and a sphere does not, a probe that fits turned edge-on and
not flat, a compound reported once however many parts are inside, sensors and
soft bodies invisible until asked for or never, distances in world units under
a changed `unitsPerMeter`, and identical worlds answering identically.

### Collision groups

"These two never touch" is a named `CollisionGroup` on each thing plus a
symmetric table on the world (`Sources/OllinPhysics/CollisionGroup.swift`,
`ignoreCollisions(between:and:)` / `allowCollisions` / `collides(_:with:)`).
The name is `ExpressibleByStringLiteral`, so a group costs one word at the site
where a body is made and the rule is one sentence somewhere else.

**The group rides in the object layer, and that choice is the whole design.**
Jolt offers two filtering mechanisms and only one of them reaches everywhere a
pair can meet. A per-body `CollisionGroup`/`GroupFilterTable` is consulted in
the *narrow phase only*: it would never have reached a query, a character's own
sweep, or a wheel's collision tester, it hardcodes "same sub-group never
collides" (so two crates in one category could not have stacked), and it only
filters within one `GroupID`, which is the slot the ragdoll tier already owns
for keeping one figure's limbs from fighting each other. The **object layer**,
by contrast, is what the library consults when finding collision pairs (so the
contact listener never hears a filtered touch), in `DefaultObjectLayerFilter`
for every query, in the filters `CharacterVirtual::ExtendedUpdate` takes, in the
`ObjectLayer` a `VehicleCollisionTester` is constructed against, and in
`SoftBodyCreationSettings::mObjectLayer`. So the layer carries both halves:

```
layer = (group << 2) | kind        kind in {NON_MOVING 0, MOVING 1, GHOST 2, SENSOR 3}
```

Group 0 leaves every layer numerically identical to the four fixed kinds it had
before, so **a world that never names a group is byte-identical**; the whole
existing physics suite passed unchanged. `ObjectLayerPairFilterImpl` answers the
fixed kind rules against `layerKind` and then consults a `GroupTable` (64
`uint64` rows, symmetric, diagonal meaningful), written from the main thread
between steps and only read while one runs. The two mechanisms stay orthogonal:
a ragdoll takes an Ollin group *and* keeps its own per-figure `CollisionGroup`,
so two figures in one group still collide.

Four places needed the split honored by hand, each of which would otherwise have
filtered a pair in one place and not another:

- **Character against character.** Characters are not in the broad phase; they
  meet through `CharacterVsCharacterCollisionSimple`, which the layer never
  reaches. `GroupedCharacterCollision` wraps it and refills a scratch list per
  call with only the characters the caller's group can touch, then delegates to
  the library's own loop rather than reimplementing it. The group travels as the
  `CharacterVirtual`'s user data (the bridge owns that slot) so the filter can
  answer for a bare character pointer without searching for its wrapper.
- **Wheel collision testers** take their `ObjectLayer` at construction, so
  changing a live vehicle's group rebuilds all three and re-selects the active
  one (`CJoltVehicle` remembers `contactIndex` and `wheelWidth` for exactly
  this). `Body3D.group`'s setter routes through `World3D.bodyChangedGroup` so
  setting the group on a *chassis body* rebuilds them too, rather than leaving
  the wheels probing the old layer.
- **Buoyancy's sweep** asked for `SpecifiedObjectLayerFilter(Layers::MOVING)`,
  an exact layer match that was correct while there was one moving layer and
  silently stops floating a grouped body once there are many. It became a
  kind-based `MovingKindLayerFilter`. This was a real trap, caught by writing
  the "a grouped body still floats" twin before trusting the encoding.
- **Motion changes rewrite the layer**, so `cjolt_body_set_motion` and
  `cjolt_ragdoll_set_motion` re-derive it from the *current* layer's group: a
  body let go from static keeps the group it was in.

Queries narrow through a `group` field on `CJoltQueryFilter` rather than a new
parameter on the four C calls (the stage-10 rule paying off); `QueryFilters`
builds its layer filters from `layerFor(filter->group, MOVING)`, so `as:` sees
what a moving body of that group would see and the default group answers exactly
as before. A world holds 64 groups; naming more keeps the extras in `.default`
(never aliasing an in-use group, which would filter the wrong things) with a
one-time note, and `world.collisionGroups` lists the names so a typo, which is a
*new* group silently doing nothing, is findable. `CollisionFilter3DTests` (22)
pins each answer against its counterfactual twin, the sharpest being the four
that exist only to catch a half-applied filter: the contact listener, the
sensor, the second character, and the wheel testers.

**Per-body motion knobs** are three fields the body descriptor and the solver
already carried, surfaced as `Body3D.freedom` / `.gravityScale` / `.checksPath`
plus matching `addBody` parameters. Two of them are pass-throughs
(`SetGravityFactor`, `SetMotionQuality`, both null-guarded upstream so they are
safe on a body that is currently static). `freedom` is not, and the reason is
worth keeping: the library stores a restricted degree of freedom *inside the
body's mass properties* (a locked axis is one given infinite mass or inertia),
so `MotionProperties::SetMassProperties(dofs, properties)` is the only way in
and the whole mass set has to be re-derived from the shape and scaled back to
the body's mass. That mass cannot be read back from the body, because a body
whose translation is already locked reports an inverse mass of zero, so
`cjolt_body_set_freedom` takes it as an argument: Swift passes the explicit
mass a body was created with (the vehicle-chassis path) and otherwise zero,
which the bridge reads as "the shape's own". The same asymmetry made
`cjolt_body_get_mass` answer `0` for a pinned body, reading as weightless when
the truth is the opposite, so it now falls back to the shape's mass properties
and `Body3D.mass` prefers an overridden mass over that fallback. `Freedom3D` is
an `OptionSet` whose raw bits *are* `EAllowedDOFs`', so the bridge casts; two
sanity rules live in `allowedDOFs()`: a zeroed descriptor field means
unrestricted (which is what keeps every existing `CJoltBodyDesc()` byte-identical,
including the ground slab's), and a mask with no freedom at all, which the
library documents as invalid and would divide by a zero mass, reads as
unrestricted rather than trapping. Setting freedom activates the body, since
whatever was holding it still may not any more.

Continuous collision detection needed a decision rather than a translation. The
solver's own gate (`PhysicsSystem`, `mLinearCastThreshold` × the shape's inner
radius) means a `LinearCast` body that is moving slowly costs nothing beyond one
comparison, which is what makes an opt-in flag the right shape: turning it on
for a slow body is measurably free (`checkingThePathChangesNothingWhileTheBodyIsSlow`
pins the two runs byte-identical), so there is no reason to guess on the sketch's
behalf, and guessing would change results for every fast body in every existing
sketch. What a probe also settled is where tunnelling actually starts: speculative
contacts catch far more than the naive "moved further than the wall is thick"
estimate, so a 0.05-radius pellet against a 0.04-thick wall passes through at 40
units/s and bounces at 20, which is why the example's shot has to cross *thin*
plates to make the point. `Character3D` and `Vehicle3D` need nothing turned on:
a `CharacterVirtual` shape-casts its own path each update, and a vehicle's wheels
find the road by ray, leaving the chassis as the only part with an ordinary
body's tunnelling story. `Motion3DTests` (16) pins the tier against counterfactual
twins, the sharpest being a contact that throws a free body five units and cannot
move its flat twin at all.

Folded in here: the floor slab's collision group is remembered on the world
(`World3D.groundGroup`, recorded by `bodyChangedGroup`) rather than on the slab,
because `rebuildGround` builds a fresh descriptor whenever `ground` or
`unitsPerMeter` moves and the group would otherwise be silently lost.

### Tracks, ropes, freedoms, and joint-to-joint links

Five more constraint kinds, split by what each one links. Three connect two
bodies and ride `JointKind3D` (`.path`, `.pulley`, `.allowing`); two connect two
*joints* and ride a second enum, `JointLink3D` (`.gear`, `.rackAndPinion`),
through a `connect(_ a: Joint3D, _ b: Joint3D, _:)` overload. The split follows
what the solver actually constrains: a gear ties the rotation two hinges allow,
so naming the hinges gives the bodies, the axes, and the drift-correction
constraints in one go, where naming bodies would give none of them.

`.path` is `PathConstraint` over a `PathConstraintPathHermite`. Three pieces are
load-bearing. **The spline frame is built in Swift** (`PathSpline` in
`JointPath.swift`): tangents are cardinal (half the span between neighbors,
one-sided at an open path's ends) and normals are carried along the curve by
**parallel transport**, because re-deriving "world up minus its along-track
part" per point flips when the track goes vertical and the rider flips with it;
the holonomy a closed loop comes back with is a stated envelope, not a defect.
**Points arrive in world space and the bridge takes them into body 1's own
space** with the settings' path transform left at identity, which is exactly
what makes path space equal body-1 *body* space (the center-of-mass offset in
`mPathToBody1` cancels against the body's own COM transform), so a track hung
off a moving body rides it. The rider joins at `GetClosestPoint` of where it
already is. **Progress is normalized in the bridge**, since a Hermite path's
fraction runs to its segment count and only the bridge knows that: `drive(to:)`
scales a 0…1 target up and `cjolt_constraint_current` scales the reading back
down, so `Joint3D.progress` means the same thing on any track. The four
`PathAlignment` cases map onto `EPathRotationConstraintType`.

`.pulley` is the one place a vendored-library defect had to be handled rather
than patched. `IndependentAxisConstraintPart::CalculateConstraintProperties`
guards on `IsStatic()` where every other constraint part guards on `IsDynamic()`,
so a **kinematic** end reaches `MultiplyWorldSpaceInverseInertiaByVector`, which
asserts on non-dynamic bodies (and in a release build would read a kinematic
body's inertia and shove it off its driven path). The bridge refuses that pair
and `World3D.connect` notes once; the vendored source stays pristine. The rope's
default range is `min 0, max -1`, which is the library's "measure the current
length" sentinel on the max only, and is exactly rope behavior: resists being
pulled longer, gives when let slack. `taut:` sets both to -1.

`.allowing` is `SixDOFConstraint` with `ESwingType::Pyramid` (the swing type
that takes limits which are not symmetric) and the world's own axes as the
constraint frame, so a freedom names the same direction here that it names on a
body. `Freedom3D`'s six bits are already in `EAxis` order, so the per-axis loop
is `MakeFixedAxis` / `MakeFreeAxis` / `SetLimitedAxis` off one mask plus the two
shared ranges.

The links resolve **which end of each joint actually moves** in the bridge
(`resolveLinkEnd`): the body that is not static, or the second body when both
can move, matching the order every `connect` call is written in. A hinge hands
back `GetLocalSpaceHingeAxis1/2`; a slider has no public accessor, so its axis
is column 0 of `GetConstraintToBody{1,2}Matrix()`, and both are already in the
body's center-of-mass space, which is why the settings use
`EConstraintSpace::LocalToBodyCOM`. Both links call `SetConstraints` with the
two source joints so the solver can measure and correct its own drift. Two
knobs are converted on Ollin's side: `travelPerTurn` becomes the library's
radians-per-meter (`2π / travel`), and a **gear ratio is forced positive** with
a note, because a negative one leaves the position correction pulling against
the velocity rule until the pair detonates (probe-confirmed), and a real gear
ratio is a tooth count with no sign anyway. A link records all four bodies it
reaches (`Joint3D.alsoTouches`) and its two source joints (`links(_:)`), so
removing any body or either joint takes it with them, which matters because the
gear holds raw `Body` pointers.

The swing-twist motor gap closed at the same time. `cjolt_constraint_set_motor`
now handles `SwingTwist` and `Path` beside Hinge and Slider. A scalar target on
a joint that bends in every direction can only mean the roll about its own axis,
so it runs the **twist motor only** (`SetSwingMotorState(Off)`, a pure-twist
target orientation): the solver reads the twist error from constraint-space x
alone, so the swing half of the target is unused and the bone keeps swinging
free (measured: twist lands within 0.001 of the target with swing at 0.000).
Pointing it somewhere is `cjolt_constraint_set_orientation_motor`, which takes a
world direction back through body 1's rotation and `GetConstraintToBody1()` into
constraint space, turns x onto it with `Quat::sFromTo`, and composes the twist;
`SetTargetOrientationCS` clamps that to the joint's own limits, so aiming past
the cone leans as far as it may. `cjolt_constraint_twist` reads the roll back
(`2·atan2(q.x, q.w)` of the twist half).

`JointKind3DTests` (24) pins the family against counterfactual twins, the
sharpest being a body on a track and a loose one thrown the same way (the railed
one holds its circle to 0.05 while its twin falls twenty units). Example
`3D/Physics/Contraption`.

### Saving a world

`World3D.snapshot()` captures the whole world as a `PhysicsSnapshot`, and
`restore(_:)` builds it back; `save(to:)` / `load(contentsOf:)` are the file
pair over them. The format is **Ollin's own**, not the solver's
`PhysicsScene`, and the reason is `Body3D.collider`: a snapshot has to hand back
the *Ollin* description of each body, because that is what a sketch draws from
and what `addBody`'s knobs are expressed in, and a restored Jolt shape cannot
be turned back into a `Collider3D` case (a compound or a hull has forgotten it
ever was one). Once the colliders have to be written down anyway, the solver's
serialization buys nothing and costs a second representation to keep in step.

The consequence is the design's best property: **restoring replays the ordinary
`addBody` and `connect` calls**, so a restored world is one a sketch could have
built by hand and cannot be in a state a built one cannot reach. What it costs
is a small binary encoder (`SnapshotWriter` / `SnapshotReader` in
`PhysicsSnapshot.swift`): a header, then a payload holding the world settings,
the group table, the bodies, the joints, and the joint-to-joint links, every
number a `Float64`. `PhysicsSnapshot` wraps the `Data` rather than the
decoded model, which makes it `Sendable` and `Equatable` for free (a `Collider3D`
is neither) and leaves exactly one representation, so a snapshot that went
through a file and one that did not are the same value.

The payload is **packed with LZFSE** (the system codec, so nothing is vendored
and the bytes are the same on every machine), and the header carries a flag, the
unpacked length, and an FNV-1a checksum beside the magic, version, and counts.
Two measurements settled that. On a scenery-heavy world (a 129² heightfield
collider, a 16,641-vertex terrain mesh, a 5,000-vertex knot, sixty boxes) the
file goes 1912 KB to 966 KB, and on the case the feature exists for, a settled
heap of sixty primitives, 10.7 KB to 1.2 KB. A world is arrays of `Double`s
whose exponent bytes repeat, which is exactly what a general compressor eats.
The second measurement is the one that **rejected narrowing mesh positions to
`Float32`**: it saves less (1912 KB to 1210 KB, or 575 KB packed as well), it is
lossy for the `Mesh` a sketch reads back out of `body.collider`, and where it
would help most it is dominated outright by naming the geometry instead of
holding it. Compression is conditional on being smaller, which the codec reports
by refusing a destination the source's size, so an incompressible payload simply
rides uncompressed and the flag says so.

The checksum is not decoration. **LZFSE's decoder returns the full requested
length from a truncated stream** rather than reporting the truncation (measured:
15 bytes of a 46-byte stream decoded to all 825 bytes, none of them right), so
the old "the reader runs out of bytes" defense silently became "rubbish parses
into some world" the moment the payload was packed. The checksum makes *refused
rather than half-read* true by construction, and it also catches a
corrupted-but-complete file, which the unpacked format never could.
`aDamagedSnapshotIsRefusedRatherThanHalfRead` pins it against its undamaged twin.

Four things are load-bearing:

- **A joint's zero is the pose its bodies were in when it was made**, and that
  is not where they are now. `connect` reads both bodies' current poses to build
  the constraint frames, so a hinge saved half open and re-connected where it
  stands would call *open* zero, and its limits would run a whole swing further.
  So `Joint3D` records `connectPoseA` / `connectPoseB` at creation, and restore
  stands the two bodies back there, makes the joint, and then puts them where
  the snapshot found them. Constraint frames are fixed at creation, so the
  result is exact for every kind at once (a weld's relative pose, a
  length-less rod's span, a track's attachment point) rather than per-kind
  arithmetic. Pinned by `aHingeKeepsItsZeroAcrossASnapshot` against the naive
  twin, which reads 0.
- **The desc grew three fields whose zero is the old behavior**, the encoding
  rule from stages 11 and 12: `CJoltBodyDesc.linearVelocity` /
  `angularVelocity` / `startAsleep`. Velocity through
  `BodyCreationSettings` rather than a post-create setter, because
  `BodyInterface::SetLinearVelocity` activates a body it moves; `startAsleep`
  adds `EActivation::DontActivate` to what was already the static case, which
  is what "asleep" is. A settled pile therefore comes back *settled*: measured
  0/12 awake after a restore against 12/12 for the same poses handed to
  `addBody`, and zero movement over the next sixty steps.
- **A vehicle's chassis is an ordinary body in `world.bodies`**, so capturing
  it with the loose ones would save a crate that restores without its wheels.
  It is written in the vehicle section instead, while still taking a body index
  after the loose ones so a joint saved against it (a trailer on a hitch) still
  names it.
- **The group table survives `removeAll()` in the solver but not in Swift.**
  Restore rebuilds `groupNames` in the saved order (which *is* the solver's
  indexing, so a body's saved index still names its group) and then sets every
  pair among the union of the old and new counts back to what the snapshot
  says, rather than trusting whatever the previous world left behind.

Two bridge getters came with it (`cjolt_body_get_friction` /
`_get_restitution`, surfaced as live `Body3D.friction` / `.restitution`), since
the two knobs `addBody` took had until now been write-only.

The round trip is exact end to end, which is stronger than the docs promise: a
restored pile's worst pose error is 0, a re-capture is byte-identical to the
first, and a ballistic body stepped on from a restore lands at the same
position as one never interrupted. The envelope is the solver's in-flight
bookkeeping (contact caches, island assignments), which is not carried, so a
scene captured mid-collision may drift where a settled one cannot. That is also
the whole point of the feature: determinism is per binary, so a heap made by
simulating is a different heap wherever the floating point rounds differently
(measured: releasing one stone 1e-7 higher moves a stone in the settled heap
0.45 units), where a saved one has nothing left to compute.
`PhysicsSnapshotTests` (23) pins it; example `3D/Physics/Cairn`.

#### The tiers above a loose body

Characters, vehicles, and ragdolls are in the file too, and the reason they can
be is the taxonomy: **sorting the tiers by what is actually heavy in each**
turns "what may a snapshot reference" into a much narrower question. A
character is a capsule and a handful of numbers. A vehicle is colliders plus a
wheel list plus live drivetrain state. A ragdoll *splits*: what the solver holds
(a fitted shape per limb, the joint tree, the limits) is derived data that fits
by value, while the skinned `Scene` it was fitted from is the sketch's own
asset, already loaded and already handed back for `scene.apply(ragdoll)`. None
of the three needs to name anything outside the file, so all three are written
by value and only a soft body's source mesh is left.

That split is what shaped `Ragdoll3D`: its initializer was divided into a
`convenience init` that works a `Scene` down to a `RagdollPlan` and a designated
one that builds the solver objects **from the plan**, so a restored figure is
built by the same code a fitted one is, and `RagdollPlan` grew each limb's
`name` and `sourceIndex` (which a plan previously read back off the skeleton it
no longer has). The per-joint limits are held on the figure as
`jointLimits`, since the solver takes them and never hands them back.

Three findings came out of building it, each measured rather than reasoned:

- **A vehicle must carry its drivetrain, not just its chassis.** Restoring pose
  and velocity alone leaves the engine idling and the wheels stationary, so a
  machine at speed has to spin both up again: measured, a car under full
  throttle fell **6.4 units** behind over two seconds. Carrying engine RPM,
  gear, clutch, and each wheel's angular velocity and rolled angle brings that
  to 1.5. What is left is the solver's own in-flight bookkeeping, and the fair
  comparison says so: a *rigid* stack captured mid-collapse and restored
  diverges **2.13** units over the same 120 steps, worse than the vehicle, while
  a parked machine and a coasting one come back at 0 and 0.07. Wheel suspension
  length is deliberately not carried (there is no setter, and `PreCollide`
  re-measures it against the ground), which shows only as the wheels' contact
  cache being rebuilt on the first step.
- **Never write a pose as a position then a rotation.** The solver holds a body
  by its **center of mass**, so `SetPosition` computes it against the
  orientation the body still has; a following `SetRotation` then leaves the body
  origin a fraction out. It is invisible for a box or a sphere (center of mass
  at the origin) and real for a **ragdoll limb**, whose shape is pushed out
  along the bone by a `RotatedTranslatedShape`: three of sixteen limbs came back
  up to 4.8e-07 off. The new `cjolt_body_set_pose` (over
  `SetPositionAndRotation`) fixed all three.
- **The bytes settle after one restore rather than on the first capture, and
  that is the solver's doing.** Integrating a body lets its quaternion drift a
  hair off unit length; anything handed back to the solver is normalized on the
  way in, since it requires a unit quaternion. So capturing a *stepped* world
  twice around a restore differs in a few last bits, and every capture after
  that is identical (verified to five rounds). Reproducing the normalization in
  Swift was tried and reverted: it fixed fifteen limbs of sixteen, which is a
  half-measure dressed up as a guarantee. `aWorldOfEveryTierRoundTripsToTheSameBytes`
  states the property that is actually true.

`SnapshotTierTests` (13) pins the tier against counterfactual twins; example
`3D/Physics/Yard`.

#### Naming geometry rather than holding it

The one thing genuinely too heavy to write down every time is bulk geometry: a
`.mesh` or `.heightfield` collider, and a soft body's whole source mesh. The
shape that fits the house rules is **a name the sketch chooses plus a resolver
at restore** (`Body3D.assetName` / `SoftBody3D.assetName`, a serializable
sibling of `userData`; `restore(_:resolving:)` and `load(contentsOf:resolving:)`
over a `PhysicsAssetResolver`), which keeps the sketch the source of truth about
where its assets live, the way `resource:in:` refuses to default its bundle.
`PhysicsAsset` is deliberately just the two kinds worth naming. Naming stays
**opt-in**, because a self-contained file is what makes a settled arrangement
committable, and that is the right default. Measured: a world with a 65²
terrain, a 5,000-vertex mesh, and twenty crates is **105 KB held, 1.1 KB
named**.

Naming is also what lets **soft bodies into the snapshot at all**, which closes
the last tier: a soft body is nothing *but* its mesh, so an unnamed one is left
out with a note while a named one saves the numbers it was built with plus every
particle's position and velocity and the pinned set. That needed
`cjolt_soft_body_get_velocities` and `cjolt_soft_body_set_state` (the write goes
through the body's center-of-mass transform, mirroring the existing read, and
sets `mPreviousPosition` alongside `mPosition` so the first step does not read a
step's worth of phantom motion). Measured round trip: 289 particles back at
1.19e-07.

Three decisions are load-bearing:

- **A name is per body, at the top level only.** A mesh nested inside a compound
  is still written whole, because the name belongs to the body rather than to
  one of its parts, and a compound of meshes pins the body anyway.
- **An unresolved name costs one body, not the restore.** It is skipped with a
  note and the joints that named it are dropped with it, which meant the
  restored-body list has to keep **nils in the gaps** so the saved indices still
  line up (`restored(_:in:)` reads that list rather than searching `bodies`).
- **The fingerprint hashes the geometry; counts and bounds were not enough.**
  The first draft stored counts plus a bounding box, which is *blind* to the
  case that matters most: `Heightfield.diamondSquare` normalizes to 0…1, so two
  terrains grown from different seeds have identical counts and identical bounds
  and are not remotely the same ground (a probe caught it). FNV-1a over the
  samples costs the same walk and answers the question. A mismatch notes and
  restores anyway, since the saved poses are the best answer available.

One bug worth remembering came out of it: the reader's `count()` helper bounds a
length against the bytes remaining, which is right for an array *in* the stream
and wrong for a fingerprint's piece count, which counts geometry that is
deliberately **not** there. Reading a 4,225-sample terrain's count that way threw
on a 1 KB payload and the whole restore was refused. A bounds-checked reader
belongs only where the number really is a length.

`SnapshotAssetTests` (10) pins it; the `3D/Physics/Yard` example names its
heightfield floor and its cloth banner.

### Reading UsdPhysics

`World3D.addBodies(from: Scene)` picks up rigid-body, collider, and joint
annotations authored elsewhere. It is the interchange leg, and the direction is
the whole argument: **reading is lossy and that is fine** (a file's notion of a
body is a description, and what it omits has a sensible default), where writing
would not be, which is why the snapshot stays Ollin's own format.

The split follows the lights/cameras precedent: the core reads the annotations
into `package` value types (`ScenePhysics` / `ScenePhysicsBody` /
`ScenePhysicsShape` / `ScenePhysicsJoint`, in `3D/SceneLoaderUSDPhysics.swift`,
attached to the loaded `Scene`), and `OllinPhysics/UsdPhysics.swift` turns those
into ordinary `addBody` / `connect` calls. So the satellite never sees the USD
parser, and a restored or snapshotted imported world is one a sketch could have
built.

**Every attribute name was verified against `pxr/usd/usdPhysics/schema.usda`
rather than recalled**, which the continuation prompt specifically warned about,
and the schema's shape drove four decisions:

- **A collider's shape is the prim's own geometry.** There is no shape
  attribute: `PhysicsCollisionAPI` on a `Cube` means a box. So the reader maps
  gprim types, and the sizes are the gprim's own (`Cube.size` default **2**, not
  three extents; `Capsule` default radius 0.5 / height 1, the height being the
  span between cap centers, which is already Ollin's meaning).
- **USD stands a Capsule, Cylinder, and Cone on z** (`axis`, default `"Z"`)
  where Ollin's stand on y, so the difference is baked into the shape's own turn
  inside its body. A rod authored the default way arrives lying down, and
  `aCapsuleAuthoredOnZComesInLyingDown` pins it against a y-axis twin.
- **A rigid body owns its whole subtree**, so several collider prims under one
  body fuse into one `.compound`, which is exactly what the schema means and
  what makes a hammer one body.
- **A joint naming one body holds it to the world.** The bridge already
  supported that (`resolveBody` returns `Body::sFixedToWorld` for
  `CJOLT_BODY_INVALID`, which the header had documented all along), so the fix
  was a Swift seam rather than C: the new public **`connect(_:toWorld:)`**, with
  the two-body `connect` and it both forwarding to one optional-second-body
  form. A first draft added a `cjolt_body_create_anchor` before reading far
  enough to find the existing support; checking the header beat writing the
  code.

The bug worth remembering: **a collider prim that *is* its body has an identity
local transform**, so taking the shape's scale from the collider-inside-body
transform loses the prim's own scale entirely, which is the common case. Scale
must come from the collider's **world** transform always, with the
body-relative transform supplying only position and rotation (and that
measured against the body's rotation and place rather than any scale it
carries, since the scale is already in the sizes). It rendered as a scene of
unscaled cubes: caught by looking at it, not by a test.

`UsdPhysicsTests` (14) pins the tier; example `3D/Physics/Imported` with a
hand-authored `yard.usda`.

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

Crack growth (`Geometry/CrackGrowth.swift`): straight cracks over an
angle-raster grid. A cell within 5° of the crack's angle reads as its own
line. Any other angle stops the crack, which restarts perpendicular at a
random claimed cell and recruits one more, up to `maxCracks`. Restarts
draw from a kept list of claimed cells. A bounded random probe went
dormant on a sparse grid, a real bug the tests caught. `step()` returns
per-tick `Mark`s (point, one-sided wash span, gain); `CrackGrowth.grains`
lays the sin-eased wash. The wash-side test was verified red by flipping
the sign. Example `Patterns/Cracks`; snapshot `crack-growth`;
`CrackGrowthTests` (8, CPU-only).

Meander (`Geometry/Meander.swift`): kinematic river migration, a stateful
`final class` you hold and `step()`. Per step: curvature by central
differences; each point's drift blends the local curvature (weight -1) with
a normalized, exponentially decaying average of upstream curvature (weight
2.5, e-folding over `memoryLength`), applied perpendicular to the line and
clamped to 0.9 x `spacing`; pinch pairs closer than `cutoffDistance` across
the land (skipping nearby indices along it) excise the loop into an
`Oxbow`; the centerline resamples through an interpolating Catmull-Rom at
even `spacing`. Two findings are load-bearing. The resample must be a
curvature-preserving spline: routing it through the straight-segment
`Contour.resampled(spacing:)` shaves curvature every step and visibly damps
the growth. And the seed perturbation must be long-wave: a white-noise
jitter of the start line carries almost no energy at the amplified
wavelengths (about ten channel widths) while its curvature spikes trip the
per-step clamp, and the measured sinuosity stalled at 1.19 by step 1600;
three tapered sine components in the 6-16 width band reach 1.84 by step
800, with the first natural cutoff before step 1600. Oxbows shrink toward
their centroid and are deleted under half a width; `scars` records the
centerline every `recordEvery` steps, trimmed to `maxScars` in one pass.
The migration itself is deterministic; all rng is in the seeded start
waves. Example `Patterns/Meander` (starts 700 units off-canvas, so the
canvas windows the middle of a longer river and the downstream translation
keeps feeding it); snapshot `meander`; `MeanderTests` (9, CPU-only).

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

`Geometry/OverlappingWFC.swift` is the overlapping model, which learns its
constraints from an example `Image` instead of declared tiles. Colors are
indexed first-met in scan order; patches are cut at every position (the
sample read as wrapping) or only where a whole patch fits, augmented by the
dihedral variants `WFCSymmetry` keeps, and counted by content into weights.
Six pieces are load-bearing, and each is a way the algorithm goes wrong
rather than merely slow:

- **Propagation runs over the four unit offsets only**, not the `(2N-1)²`
  offsets the 2016 formulation used. It is sound because in a complete
  assignment the intervening cell holds *some* pattern and the two overlaps
  chain by transitivity, so the long-range arcs are redundant. This is the
  20x that made the model practical.
- **The support counters are the propagator, not a recompute.**
  `compatible[cell][pattern][d]` counts the patterns still standing in the
  neighbor *opposite* `d` that would allow `pattern` here, so it initializes
  to `propagatorCount[opposite[d]][p]`. Using `d` there compiles, runs, and
  is quietly wrong. A counter reaching zero means nothing over there can sit
  beside that pattern, which is what bans it in O(1). `ban` zeroes all four
  of a pattern's counters so later decrements go negative and it can never
  be banned twice.
- **Entropy is Shannon over the weights**, `log(S) - Σw·log w / S`, updated
  incrementally in `ban`. A plain count of survivors treats a cell holding
  two equally likely patterns the same as one holding two at 1000:1, which
  is nearly decided. The scan's sentinel is `.infinity`, never a magic
  constant a large pattern set could exceed.
- **A bounded output's last `N-1` columns and rows are outside the solve
  entirely**: never observed, and never propagated into. A ban spreading
  into one would empty a cell nobody asked about and read as a
  contradiction. The read-out then recovers those pixels from the last cell
  that covers them (the `dx`/`dy` offset in `render`), which is why the
  output needs `2N-2` pixels a side.
- **Patterns with no legal neighbor in a direction that exists are banned
  before anything is settled.** Propagation can never eliminate one (nothing
  ever withdraws support from it), so it survives to be chosen and the
  output is quietly illegal rather than contradictory. These appear when the
  sample is read as bounded, where its edge patches may have nothing that
  can follow them.
- **Determinism** follows the catalog rule: patterns are appended in scan
  order and the content dictionary is lookup-only, the noise that breaks
  entropy ties is drawn in a fixed cell order, and the weighted pick walks
  the survivors in index order.

Deliberate cuts: no seeding constraints (the reference's `ground` names a
pattern by index, which is an artifact of extraction order and silently
means something else when the sample or symmetry changes) and no
backtracking (a contradiction restarts the whole solve, `attempts` times,
as upstream does). Caps at 256 colors and 1024 patterns refuse a photograph
rather than grinding on it. Sugar `wfc(from:...)` + `wfc(_ model:...)`;
example `Patterns/TextureSynthesis`; snapshot `texture-synthesis`;
`OverlappingWFCTests` pins extraction against hand-derived counts, the
rotation closure, local legality in all three output modes, and
determinism.

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
instead of 5%), the pair is oriented dark-to-light so neighboring tones
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

## Wide gamut and HDR output (`colorOutput`)

The mechanism is small: `ColorOutput` picks the drawable's pixel format and the
present pass's encoding, and the renderer carries both for its lifetime.
`.standard` keeps the 8-bit sRGB drawable and the shipped
`ollin_present_fragment`; `.wide` and `.extended` present into `rgba16Float`
through `ollin_present_wide_fragment`, a twin kept beside the original rather
than a branch inside it, because that fragment's exact codegen is what every
dithered 8-bit frame reproduces and growing it re-contracts under fast math.

The whole difference between `.wide` and `.extended` at the pixel level is one
uniform: the ceiling the twin clamps to. `.wide` stops at 1.0, `.extended`
starts unbounded (so an off-screen render keeps the highlights an exported HDR
video is for) and a live host pulls it down to the display's reported headroom
every frame, since the system grants and withdraws that as brightness and
surrounding content change.

### Naming a color outside sRGB needed no shader change

`Color(displayP3:green:blue:)` converts to linear sRGB and re-encodes, which
puts some components outside 0…1. That value has to survive the ordinary vertex
path, where the fragment applies the shipped `srgbToLinear`. It does, exactly:
below the curve's knee that function is the straight line `c/12.92`, and the CPU
`linearToSrgb` is its exact inverse there, so the pipeline's decode of a
negative component is precisely the encode's inverse. Extending the shader's
transfer function to the mirrored form was the obvious alternative and would
have re-contracted every 2D fragment for no gain.

### The float drawable is not slower (measured)

The expectation going in was that `.wide` would cost bandwidth: eight bytes per
pixel against four. Measured, it is **cheaper**, because the standard present
fragment pays more arithmetic than the wider one saves in bytes. `finalizeColor`
runs `linearToSrgb`, two hash calls for the dither, and `srgbToLinear` per
pixel; the wide twin runs a 3x3 matrix and a clamp.

M2, release, a near-empty frame so the present pass dominates, ten paired runs
(the two settings measured back to back so thermal drift cancels within a pair,
the rule that a single A/B run can otherwise invert):

| canvas | `.standard` | `.wide` | difference |
| --- | --- | --- | --- |
| 540² | 0.17 ms | 0.12 ms | 0.05 ms cheaper |
| 1080² | 0.44 ms | 0.23 ms | 0.21 ms cheaper, ±0.01 over ten pairs |
| 2160² | 0.88 ms | 0.83 ms | noisy, break-even to slightly cheaper |

`.extended` measures identically to `.wide` (same shader, same format). The
saving shrinks at 2160² as bandwidth starts to matter against the fixed
per-pixel arithmetic.

What this does *not* measure: the harness renders off-screen, so the window
compositor's own cost for a float layer, and for an EDR layer in particular, is
outside it. The render cost is settled; the system cost is not.

The measurement is why the case against `.wide` as a future default is about
what leaves the window (a P3 file read by a consumer that ignores the tag reads
oversaturated; Syphon and the virtual camera feed such consumers) and about
re-recording every reference and figure, rather than about speed.

### A still keeps its highlights in a gain map

PNG stops at white, so `--export frame.png` throws away the one thing
`.extended` exists for. `--export frame.heic` writes HEIC instead, with an
ISO 21496-1 gain map beside the picture (`Export/GainMapExport.swift`). The
picture is the frame clamped at white, which is what the PNG already carries.
The map records, per pixel and per channel, the ratio between the two. Each
decision below was settled by measuring, and each one has an obvious wrong
answer.

**The map is computed here, not by the imaging framework.** Core Image will
derive one from an SDR/HDR pair (`kCIImageRepresentationHDRImage`), but its
ceiling comes from the frame's statistics rather than its peak. Measured on a
synthetic frame peaking at 4x white, varying only how much of it is bright:

| highlight area | peak read back |
| --- | --- |
| 0.1% | 0.99x |
| 1% | 1.75x |
| 5% | 3.63x |
| 25% and up | 4.00x |

A sketch's highlights are small by nature (a lamp core, a spark, a specular
hit), so that behavior deletes them. Declaring `CIImage.contentHeadroom` does
not help, though the header says it drives the calculation: the value is live
(the tone-map filter reads it) and the writer ignores it. Supplying a
ready-made map through `kCIImageRepresentationHDRGainMapImage` writes the
legacy Apple auxiliary type rather than the ISO one. So the map, its metadata,
and the file are built with ImageIO directly.

**The map carries a gain per channel.** Clamping happens per channel, so a
bright color clamps unevenly. An amber core of (4.0, 2.2, 0.72) becomes
(1, 1, 0.72), which needs three different multipliers to undo. Measured with
one channel for all three: green came back 81% high, blue 300% high. With
three channels: every channel within 0.6%.

**The base is written losslessly.** `kCGImageDestinationLossyCompressionQuality`
is 1.0, so a still export stays as faithful as the PNG it replaces. The
reconstruction error is then the 8-bit base's own quantization, about 0.6% at
mid gray and under 2% at the peak.

The metadata is the `HDRToneMap` namespace ImageIO reads back: `Version`,
`BaseHeadroom`, `AlternateHeadroom`, `BaseColorIsWorkingColor`, and one
`ChannelMetadata` entry per channel carrying `GainMapMin`, `GainMapMax`,
`Gamma`, `BaseOffset`, and `AlternateOffset`. Reconstruction is
`(base + offset) * 2^(e * GainMapMax) - offset`, where `e` is the stored byte
over 255. ImageIO re-encodes the three-channel map as 4:2:0 (`'420f'`), so the
*differences between* channels are stored at half resolution; the overall gain
is not.

A frame whose peak is at or below white carries no map at all, and
`OllinApp.StillExport.keepsHighlights` reports which happened.
`GainMapExportTests` pins the peak, the color, the base, the ISO type, and the
declared ceiling; the per-channel map and the true-peak ceiling were both
verified red by sabotage.

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

### The loose file on a wall (`OllinRun`)

`swift run OllinRun <file>` uses the same loader for the opposite purpose. It
compiles the file once and hands the sketch to `OllinApp.run`, the standalone
path a packaged `@main` sketch takes. That path is the only one that reads a
sketch's declared `Installation`, so it is how a loose file goes on a wall.
`Scripts/ollin` routes there when the arguments carry `--installation` or
`--calibrate`, and the live host prints that command rather than saying only
that the flag does nothing. There is no watcher here, by design: a wall
runs the code it was started with.

Two details are load-bearing, and both fall out of the unique `-module-name`
above. First, the checkpoint file is named from
`String(describing: type(of: sketch))`, which drops the module. So
`OllinRuntimeSketch_<token>.Piece` files as `Piece.json`, and a relaunch finds
yesterday's run rather than starting the piece over every morning.
`OllinRun --selftest` compiles one file twice and compares the two names,
printing both qualified ones so the check cannot pass for the wrong reason.
Second, the compile happens before `OllinApp.run` rather than inside it. `run`
is where a piece asking for `restarts` becomes its own supervisor. A file that
does not compile therefore fails once here, with swiftc's own message, instead
of failing in every child until the watch gives up.

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

## Live recording (the real-time recorder)

`SessionRecorder` (`Sources/Ollin/Export/SessionRecorder.swift`) records a live
run as it happens, where the offline exporters re-render on a fixed clock. It
is a `SketchExtension`: while a take runs it arms `wantsRenderedFrame` and
receives each frame as a `CGImage` from the runner's frame-grab hook. That is
the CPU-readback path on purpose. The GPU-texture hook is cheaper but its
off-screen render skips shadows, effect targets, and the whole 3D pass list,
so a recording through it would silently degrade exactly the sketches worth
recording. The CGImage path is the same full off-screen re-render the export
uses, pixel-identical to `--export-video`, at the cost the frame-grab design
already accepted (an async readback stays the later optimization).

Everything that touches the `AVAssetWriter` lives in a queue-confined
`RecorderWriter` on one serial queue: the frame appends, the audio drain
timer, and the finish. Both writer inputs run `expectsMediaDataInRealTime`,
and the session's timeline is the host clock: a video frame's presentation
time is the wall time it rendered at, so a slow frame simply lasts longer in
the file. A frame the encoder cannot take is dropped and counted, never
awaited; real time does not block on a codec.

Sound has no master bus to tap. Every sound object owns a private engine, so
the recorder discovers the sketch's sources by Mirror walk (the
`ExportAudioSource` trick) through the core `CaptureAudioSource` seam, and
each source gets an `AudioCaptureSink` lane. A node allows one tap per bus
and the analyzer already owns it, so capture rides the same tap through a
`CaptureTapRelay` slot added to `installAnalyzerTap`'s fan-out. A lane places
each buffer on the master timeline by its host-time stamp with a running
counter smoothing the jitter: the counter wins while the stamp disagrees by
under 50 ms, the stamp wins past that, and the hole a device drop leaves is
filled with silence rather than closed up. Closing it up is the classic
drift bug: the audio track comes out shorter than the video and the two part
ways a few seconds per headphone switch. The writer queue mixes all lanes
every 100 ms, 150 ms behind the clock (late buffers still land), applies the
offline mixer's `tanh` knee, and appends interleaved float stereo; the AAC
track is declared whenever the mode carries sound at all, so an instrument
that first plays mid-take lands mid-file, in sync, after plain silence.

Two lifecycle rules carry the live hosts. A recording survives a hot swap
because `SketchRunner.reload(to:)` moves `sketch.sessionRecorder` to the new
instance and re-extends it; the recorder's `setup` hook then rescans that
instance's instruments, which is how the sound keeps flowing after an
evaluation replaced every `Synth`. Hosts must address the *current* sketch
through `SketchSession.currentSketch` (the runner's), because
`SketchSession.sketch` deliberately stays the first mount and a recorder
wired to a stale instance films nothing. And a take must end as a playable
file however the process ends: `stop` finishes asynchronously, app
termination and the recorder's own SIGINT/SIGTERM dispatch sources go
through `stopAndWait()`, and a canvas-size change (the one thing a movie
cannot absorb) finishes the file cleanly and says so.

---

## Record and replay (the take transport)

`Take` (`Sources/Ollin/Core/Take.swift`) writes a run down as data: the `variation` seed, one clock sample per frame exactly as the display drove it (jitter included), every input event, and every `@Param` change, the last two stamped with the frame they precede. Playing the same file into a fresh instance walks it through the same frames, and the pixel test pins that to the byte. Where the real-time recorder above keeps a run's *pixels*, a take keeps the *performance*, so it is small (roughly 90 bytes a frame as JSON, about 20 MB an hour) and it can re-render through any export path afterwards, path tracer included.

The design lives on two choke points rather than a parallel driver. Every driver Ollin has, the live window, each offline export loop, the benchmark, funnels its clock through `Sketch.advance`; the player overrides the caller's values there, after applying the frame's recorded events and knob changes, and the recorder writes down whichever clock is about to apply. And every input enters `Sketch` through a small set of internal handlers (`setMouse`, `handleMouseButton`, `handleKey`, `handleScroll`, and friends); each one logs to the recorder and then refuses the call while a player is attached, and the player re-ingests recorded events through the same private halves, which is what makes the hooks (`mousePressed()` et al.) fire again on replay. Because both seams sit below every host, `--replay` composes with the whole export flag surface through nothing but the one `make()` wrapper in `handleCommandLine`.

This is deliberately *not* a `SketchExtension`. The seam's hooks see the frame boundary but never the input events between frames, and they run after `advance` has already applied the clock, too late to override it. The recorder and player are two small internal collaborators on `Sketch` (`takeRecorder` / `takePlayer`, at most one attached), wired by the runner or by `Take.install(on:)`.

The stamp contract is the one non-obvious invariant. An event stamped `k` arrived after frame `k` drew; it applies at the advance whose pre-increment `frameCount` is `k`, and `frames[k]` is that advance's clock. Recording and playback must agree on the pre-increment stamp, or every replay shears its input by one frame. `Take.install(on:)` must run before `setup()` (seed first, then the starting knob values, then the player), because `setup()` builds from both; `--seed` beside `--replay` re-seeds deliberately *after* install, which replays the same gestures onto a different variation.

Recording starts at the run's own frame 0 (the runner attaches the recorder in its first-frame block, ahead of `setup()`, or `beginTake` restarts in place), because a take that begins mid-state could never reproduce. The file autosaves on a doubling cadence capped at a minute of frames: a growing take re-encodes whole, so a fixed short cadence would cost more the longer the run gets, and the write is a value-copy handed to a utility queue so the frame loop never pays it. A live-reload swap or a seed restart ends the take (writing it out) rather than corrupting it.

Scrubbing backward is re-simulation: rewind to frame 0 (reseed, restore the starting knobs, `setup()` again) and step forward to the target. The intermediate frames go through `stepReplayFrame`, which mirrors the headless drive in `renderImage(of:)`: an accumulating or feedback frame must actually render off-screen for its persistent surface to evolve, anything else only needs its compute stepped. Generic state snapshots are not possible (only the sketch knows its state), so the honest cost of a deep backward scrub is the frames in between; determinism is what makes the landing exact.

## Spatial video (the stereo pair and its file)

`--export-spatial` writes stereo MV-HEVC, the format Apple's platforms play with
real depth. Two things carry the weight: how the pair is made, and what the file
has to say about itself before the system will call it spatial.

**One draw, two renders.** The pair comes out of a single `performDraw()`, with
`Drawer.aimStereoEye(_:previous:)` swapping the camera between the two
`renderer.image(of:)` calls (`renderStereoFrames` in
`Sources/Ollin/Export/SpatialVideoExport.swift`). Drawing twice was the obvious
alternative and is wrong: it would roll the sketch's randomness twice and step
every simulation twice, and the artificial-life tier documents itself as not
reproducible frame for frame even at one seed, so the two eyes would get
genuinely different worlds. Rendering twice is already a supported shape: the
renderer's `statefulEncodeIsRepeat` stamp (keyed on drawer identity plus frame
count) exists for the live frame grab, so the second eye advances no feedback
slot, no sim, and no GI history. Two consequences fall out and are documented
rather than fixed: anything the sketch flattened during `draw()` (a `project()`,
a `depth(at:)` placement, a billboard) keeps the center camera's answer in both
eyes and therefore lands on the screen plane, and an accumulating sketch has one
persistent surface, so both eyes are handed the same picture with a note. The
`previous:` half of the seam is not decoration: motion blur measures against the
last frame's camera, and left against right would read the eye separation itself
as the whole world lurching sideways every frame.

**The lean is one matrix entry, for two different reasons.** `stereoEye` steps
the eye and its target sideways along the camera's own right axis (parallel axes,
the film rig; toeing in tilts the two frames against each other and leaves
vertical misalignment at the corners). The convergence correction then lands
entirely in `[2][0]`, the term mixing view z into clip x, and that one entry is
right for all three projections by two separate routes that happen to meet. For a
perspective or intrinsic frustum, clip w *is* the view distance, so premultiplying
a constant shift of the flattened image collapses into `[2][0]`, which is exactly
the asymmetric frustum a parallel rig is defined by (the same identity
`MetalRenderer.jittered` uses for TAA). An orthographic camera has no such w, and
sliding it sideways moves the whole picture with no parallax at all, so what it
needs is a shear proportional to depth; working the convergence condition through
gives the same entry the same value. `stereoLateral` defaults to 0, so an
ordinary camera's projection is untouched by construction.

**The derivation is a stated criterion, not a constant.** Unset, the eyes sit 1%
of the frame width apart measured at the convergence plane. For a camera with a
vanishing point that is *also* the classic comfort rule, because the two work out
to the same number: far-field separation equals `p00 · e / convergence`, and
`e = frameWidth/100` at that distance makes it 1% of the frame, under the figure
a viewer's own eyes span. The frame width is read off the built projection's
`[0][0]` rather than off the field of view, so an intrinsic lens and an angled one
are measured the same way and an intrinsic camera's letterboxing is already in
the number. Orthographic reuses the expression with the distance factor dropped,
since its frame is the same width wherever you measure it.

**The file's five load-bearing numbers.** MV-HEVC alone gives a two-layer video
that plays in stereo; the system calls it *spatial* only with
`HasLeftStereoEyeView`, `HasRightStereoEyeView`, `HorizontalFieldOfView`
(millidegrees), `StereoCameraBaseline` (micrometres), and
`HorizontalDisparityAdjustment` all present. Drop any one and
`AVAssetPlaybackAssistant` reports `.stereoMultiviewVideo` but not
`.spatialVideo`, which is why the near-neighbor options are not the test. The
disparity adjustment is 0 because convergence is already in the pictures: the
eyes were aimed when the frame was drawn rather than left parallel for a player
to slide together. The layer/view keys are written as all three of
`MVHEVCVideoLayerIDs`, `MVHEVCViewIDs`, and `MVHEVCLeftAndRightViewIDs`; naming
the middle one without the last is the one combination that *hangs* the encoder
rather than refusing. Buffers come from the receiver's own pool and must be
IOSurface-backed. The write path uses the macOS 26 `TaggedPixelBufferGroupReceiver`
with its synchronous `appendImmediately`, not the adaptor whose
`appendTaggedBuffers` is already deprecated at the deployment floor. Settings are
built at frame 0 rather than up front, because the field of view and the eye
spacing are only known once the sketch has set its camera in `draw()`, and a
writer takes its settings before it starts (the same deferral the ordinary video
export makes for the seed in its recipe).

**The video input must be `expectsMediaDataInRealTime = true`**, which the
ordinary video export does not need and which is not about the data arriving in
real time. A file-paced input is interleaved in chunks of about a second, and a
multi-layer input under that pacing stops accepting frames at the end of the
first chunk and never becomes ready again: measured at exactly frame 36 of a
30 fps export, with `AVAssetWriter.status` still `.writing`, `error` nil,
`isReadyForMoreMediaData` false forever and `appendImmediately` returning false
forever. A realtime input is exempt from the pacing. This is the same escape,
for the same class of reason, that the soundtrack input already takes in the
ordinary video export, and it costs only a less tidily interleaved file, which
for one video track is nothing. A sound-carrying spatial export is therefore two
realtime inputs and interleaves without either gating the other (verified: a
6 second clip and a 3 second sound-carrying one, both complete and both read as
spatial).

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

**Seeding from an authored camera (the `from:` forms).** `cameraControl(from:)`
/ `cameraMove(_:from:)` / `cameraShowcase(_:from:)` seed the rig from any
`Camera3D` (a loaded scene's authored camera being the point), via the internal
`Camera3D.orbitPose` decomposition: `target` is the pivot, the eye offset
splits into radius / azimuth (`atan2(x, z)`, inverting `Camera3D.orbiting`
exactly, round-trip-pinned) / elevation (`asin(y/r)`), and the projection maps
to a field of view. An orthographic camera converts its frame height to the
equivalent fov at the target distance (`2 * atan(h / 2r)`) and seeds
`isOrthographic` through a `seed(orthographic:)` parameter that lands only
when the seed takes, so the shot shows the authored extent, the axis widget's
projection toggle still owns the flag afterward, and flipping projections
holds the scale (the existing `makeCamera` convention). `near`/`far` default
to the camera's own clip range, read every frame rather than seeded. What
doesn't carry, by design: the rig is y-up, so authored roll drops, and a
straight-down camera clamps just off the pole. The overloads call `seed`
first, then forward to the plain forms (whose own `seed` is then a no-op),
so every downstream behavior (anchor capture, idle return, view snaps) sees
the authored framing as the opening shot.

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

### Trackpad pressure delivery

`Sketch.pressure` / `pressureIsAvailable` are the platform surface (documented
in `Docs/Drawing/Marks.md`); how the values actually arrive was rebuilt once
the first hand test on a Force Touch trackpad showed a stroke that never varied
(the feature had shipped verified by CPU tests only, and two masked defects hid
each other). The working delivery, each piece load-bearing:

- **Delivery is a view-owned local event monitor, not the `pressureChange`
  responder override.** Inside the SwiftUI hosts, `.pressure` events reach the
  app but the hosting layer consumes them before responder dispatch: verified
  by hand with an app-level monitor (every event visible, 239/239) against the
  view override (zero delivered). `OllinMTKView` installs
  `NSEvent.addLocalMonitorForEvents(matching: .pressure)` in
  `viewDidMoveToWindow`, guarded to its own window and an active canvas press,
  and uninstalls in `viewWillMove(toWindow: nil)` (a nonisolated `deinit`
  cannot touch main-actor state). The responder override stays for plain
  AppKit embeddings, where dispatch works and the monitor's double report of
  the same value is harmless.
- **`mouseDown` re-claims the stream with `pressureConfiguration?.set()`.**
  The hosting layer's gesture recognizers install their own deep-click
  configuration, which takes precedence over the view's `.primaryGeneric`
  property for the press (observed effective behavior 5, deep click, where the
  whole normal force range reads about 0). `set()` during `mouseDown` is the
  documented way to re-claim the active stream; after it the events arrive as
  behavior 2, one stage, smooth 0...1, and no force click fires mid-stroke.
- **Never read `associatedEventsMask` on a `.pressure` event.** The access
  raises, and AppKit's event dispatch swallows the raise, silently abandoning
  the rest of the handler: the report dies with no crash and no log line
  (pinned by step-tracing: 118 monitor-fed calls entered the reporter, every
  one vanished at the mask read). A pressure event is its own capability proof,
  so that path reports `canVary: true` unconditionally; the mask is read only
  on mouse events, where it separates a pressure-capable device from a plain
  mouse.
- **Mouse events from a pressure-capable device seed zero, and drag events go
  quiet once the stream is live.** Their `pressure` field is the legacy
  constant 1; the true curve arrives only on the pressure stream and starts
  near zero. Without the seed a stroke opens on a one-frame full-force blip;
  without the drag gate (`pressureStreamLive`, reset each `mouseDown`) the
  value flaps between the true press and 1.0 on alternating events. A plain
  mouse keeps its honest flat 1 while a button is down.
- A feel note for anyone testing by hand: the generic curve saturates at
  moderate force, so the analog range lives in the light-touch zone. A firm
  press reads 1.0 throughout, which is easy to misread as "pressure is stuck".

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
*pending* there accrues depth that would otherwise swell `CAPABILITIES.md` (or
that a contributor needs and that currently survives only as the memory of past
work), it moves here under the same convention. `CAPABILITIES.md` keeps the
terse invariant and a pointer; the mechanism, rationale, and measurements live
here; `CAPABILITIES.md` remains the authoritative capability index. The
migration is deliberately incremental: a system earns a writeup here when its
`CAPABILITIES.md` bullet is carrying mechanism it should not, or when someone is
about to work in that area, not as a one-time backfill.
