# Guide plan

The working document for writing [the Ollin Guide](README.md). Readers should read [README.md](README.md) instead; this file is for whoever is writing the next chapter.

How to use it: pick the next chapter from the status table, read its brief below, then follow the session workflow in [AUTHORING.md](AUTHORING.md). When a chapter ships, update its status here, mark the coverage-matrix rows it satisfies, and check whether any parking-lot item it hosts has shipped in the framework meanwhile.

## Status

| Chapter | File | Status |
|---|---|---|
| 1. Hello, Ollin | `01-HelloOllin.md` | done |
| 2. Color that works | `02-Color.md` | done |
| 3. Motion and time | `03-MotionAndTime.md` | done |
| 4. Randomness | `04-Randomness.md` | done |
| 5. Noise | `05-Noise.md` | done |
| 6. Grids and repetition | `06-GridsAndRepetition.md` | done |
| 7. Words and pictures | `07-WordsAndPictures.md` | done |
| 8. Vectors, gently | `08-Vectors.md` | done |
| 9. Forces and physics | `09-ForcesAndPhysics.md` | done |
| 10. Flocks and swarms | `10-FlocksAndSwarms.md` | done |
| 11. Growing things | `11-GrowingThings.md` | done |
| 12. Fields and flow | `12-FieldsAndFlow.md` | done |
| 13. Shapes as material | `13-ShapesAsMaterial.md` | done |
| 14. Layers and effects | `14-LayersAndEffects.md` | done |
| 15. Your first shader | `15-YourFirstShader.md` | done |
| 16. Simulations | `16-Simulations.md` | done |
| 17. 3D, gently | `17-3DGently.md` | done |
| 18. Sculpting with fields | `18-SculptingWithFields.md` | done |
| 19. Depth and the iPhone as a sensor | `19-DepthAndThePhone.md` | done |
| 20. Sound and control | `20-SoundAndControl.md` | done |
| 21. Seeing | `21-Seeing.md` | done |
| 22. Sharing and performing | `22-SharingAndPerforming.md` | done |
| A. Just enough Swift | `A-JustEnoughSwift.md` | done |
| B. Just enough math, visually | `B-JustEnoughMath.md` | done |
| C. Coming from p5.js and Processing | `C-ComingFromP5.md` | done |
| D. The complete toolbox | `D-CompleteToolbox.md` | done |

Statuses: `not started` → `figures` (figure sketches built and rendered) → `drafted` (prose written) → `done` (humanized, audited, committed). Appendices B and D keep growing with the chapters: a session that adds a chapter also adds its math ideas to B (an entry with a picture) and gives its new capabilities rows in D and in the coverage matrix.

Also tracked here so they aren't forgotten:

- The figure runner stays a local gate rather than a CI job, and the reason is the runner rather than the cost. Scarce CI minutes were the original reason and no longer decide it, since a full run went from twenty minutes to about three. What decides it now is that a CI runner cannot do this job honestly. Two figures (`21-Seeing/MotionBrush` and `21-Seeing/FlowArrows`) measure optical flow through the same Vision request `build.yml` already skips, because the virtualized runner fails it, and rendered pixels are GPU-specific anyway, so a CI render could only report that a figure compiled and ran, never that it still looks right. Reopen this if those figures are ever reworked, or if the runner grows a compile-only mode, which would catch the real rot (an API rename breaking a figure) without needing a GPU at all.
- The full run of 213 figures takes about three minutes cold and under a second when nothing changed, so run the whole suite rather than reaching for `--only`. It used to take twenty, which was long enough that a session could talk itself into skipping the gate; the cache and the worker shards that fixed it are described in *Figures* in [AUTHORING.md](AUTHORING.md).
- The two figures that genuinely cannot reproduce (`16-Simulations/ArtificialLife` and `16-Simulations/FluidAndBlobs`, whose GPU sims are atomic-race-ordered and chaotic) carry `// figure: unstable`, so the runner verifies them without rewriting their images. There is no `git restore` step any more; a clean `git status` after a run is now the expected result, and churn under `Guide/Images` means something real changed.
- A website (Guide + Docs + gallery) is a later project; keep all markdown portable (plain relative links, standard tables, no HTML beyond the sanctioned `<img width>` figure embed in AUTHORING.md).
- Translations are out of scope for now.

## Chapter briefs

Each brief lists what the chapter teaches, what it assumes, the piece it builds toward, and where to draw from. Figure lists are starting points, not contracts; the writing session decides the final set. Every chapter ends with two short sections: "Where this comes from" (technique credits, matching `ATTRIBUTION.md`) and "Go deeper" (links into `Docs/`).

### Part I: Seeing something move

**1. Hello, Ollin.**
Teaches: what a sketch is; `setup`/`draw`; the canvas and its top-left coordinate system; `background`, `fill`, `stroke`; `drawCircle`/`drawRect`/`drawLine`; motion by default (`time` in an expression moves); the working loop for the whole guide: `swift run OllinLive`, edit, save, watch; `@Param` knobs in the inspector; running any repo example.
Assumes: can program a little, in any language. First Swift callouts: a `class ... : Sketch` is a recipe; `var`/`let`; calling functions with labels.
Payoff: a small animated composition (drifting circles over a colored ground) the reader tunes live with knobs.
Figures: the coordinate-system diagram; a first-shapes contact sheet; the finished piece at a fixed frame.
Draws from: `Docs/Core/Sketch.md`, `Docs/Core/Canvas.md`, `Docs/Drawing/Drawing.md`, `Docs/Helpers/Input.md`, `Docs/Helpers/Parameters.md`; `Examples/Basic/`.

**2. Color that works.**
Teaches: `Color` and the named set; RGB vs HSB and when each is natural; opacity; palettes and `Ramp`s; mixing that looks right (OKLab by intuition: "mix in a space that matches your eye", one diagram, no math); `Colormap`s; gradient paint on shapes.
Assumes: Ch 1.
Payoff: a generative color-field poster from one palette, re-rolled live.
Figures: RGB-vs-HSB wheel diagram; a mixing comparison strip (naive vs perceptual); palette/ramp swatch sheets; the poster.
Draws from: `Docs/Drawing/Color.md`; `Examples/Color/`.

**3. Motion and time.**
Teaches: `time`, `deltaTime`, frame-rate independence; shaping functions as curves you can see: `map`, lerp, `step`, `smoothstep`, easing curves, each drawn as its curve next to the motion it produces (this is the chapter that must pass the smoothstep test; see AUTHORING.md); sine and cosine as "a point going around a circle", nothing more; phase; `Timeline` keyframes; `@Eased`/`@Smoothed`.
Assumes: Ch 1 (Ch 2 for nicer figures).
Payoff: a perfectly looping kinetic piece exported as a GIF (the guide's first export).
Figures: one curve-plus-motion pair per shaping function; the circle-to-sine diagram; the loop as GIF.
Draws from: `Docs/Helpers/Math.md`, `Docs/Helpers/Animation.md`; `Examples/Motion/`.

**4. Randomness.**
Teaches: `random` ranges and choices; seeds and why determinism matters (the same piece twice); `randomGaussian` vs uniform, shown as scatter; random walks; picking from palettes/arrays.
Assumes: Ch 1 to 3.
Payoff: a Molnár-inspired ordered-grid-with-disorder piece (connects to `Examples/Recreations/`).
Figures: uniform-vs-Gaussian scatter diagram; a seed contact sheet (same sketch, nine seeds); the finished piece.
Draws from: `Docs/Generators/Random.md`; `Examples/Randomness/`, `Examples/Recreations/`.

**5. Noise.**
Teaches: noise as "random that remembers"; 1D noise driving a value over time; 2D noise as terrain/texture; the third dimension as drift; `signedNoise`; layering two noise scales by hand for detail; noise vs random side by side.
Assumes: Ch 4.
Payoff: a drifting organic field piece.
Figures: random-vs-noise line comparison; a 2D noise field visualized; a zoom/scale diagram; the finished piece.
Draws from: `Docs/Generators/Noise.md`; `Examples/Randomness/NoiseField` and friends.

**6. Grids and repetition.**
Teaches: the `Grid` helper (points, cells, one loop instead of two); margins with `Insets`; transforms (`translate`/`rotate`/`scale`) and `withState`; symmetry by repetition; Truchet tiles and why identical parts join into larger figures.
Assumes: Ch 1 to 5 (noise/random vary the repetition).
Payoff: an endlessly varied tiling piece.
Figures: grid anatomy diagram (padding, gutter, cell vs point); a transform-stack diagram; Truchet connectivity diagram; the finished piece.
Draws from: `Docs/Drawing/Geometry.md` (Grid), `Docs/Drawing/Truchet.md`; `Examples/Patterns/`.

**7. Words and pictures.**
Teaches: `drawText` and the three font kinds at a glance; text as geometry (`textToShapes`) and warping it; `loadImage`/`drawImage`; reading pixels (`Image[x, y]`) to drive drawing; `tint`; then the picture-as-input family that grows out of pixel reading: glyph mosaic and halftone (a mark per cell), stippling joined into a single-line tour or a spanning tree (line work for a plotter), and pixel sorting.
Assumes: Ch 1 to 6.
Payoff: a typographic poster or an image-driven pointillist piece.
Figures: font-kinds contact sheet; a text-warp step sequence; an image-sampling diagram (photo → grid of marks); the finished piece.
Draws from: `Docs/Drawing/Text.md`, `Docs/Drawing/Images.md`; `Examples/Text/`, `Examples/Images/`.

### Part II: Systems that come alive

**8. Vectors, gently.**
Teaches: `Vector2` as an arrow you can draw; add/subtract/scale shown geometrically; magnitude and normalize; position, velocity, acceleration as three arrows on one body; steering toward a target; wrapping/bouncing at edges.
Assumes: Ch 1 to 6. This is Appendix B's biggest client; every operation gets a picture.
Payoff: a swarm that chases the mouse.
Figures: arrow-arithmetic diagrams (add, scale, normalize); the position/velocity/acceleration trio; the swarm.
Draws from: `Docs/Drawing/Geometry.md`, `Docs/Helpers/Math.md`; `Examples/Motion/`.

**9. Forces and physics.**
Teaches: force → acceleration by intuition; hand-rolled gravity/drag on the Ch 8 mover; then the `World`: Verlet particles and springs (soft), bodies/colliders/joints (rigid); `grab` for mouse interaction; when to hand-roll vs simulate.
Assumes: Ch 8.
Payoff: an interactive physics toy (a hanging chain or tumbling stack the mouse can grab).
Figures: force-accumulation diagram; spring-rest-length diagram; soft-vs-rigid contact sheet; the toy.
Draws from: `Docs/Simulation/Physics.md`; `Examples/Physics/`.

**10. Flocks and swarms.**
(Retitled from "Agents", 2026-07-06: the field's classic word for these rule-following creatures now reads as AI assistants, and this guide will outlive the collision. The chapter still teaches the term: open with a one-sentence disambiguation, crediting Craig Reynolds' 1986 *autonomous agents*, coined decades before "agent" meant software wielding a chatbot, then speak in flock/boid/creature language. Never use "agent" bare in headings or the TOC.)
Teaches: one creature that steers (the steering move: desired velocity minus velocity, capped; seek, arrive, wander, pursue via `Vehicle`); local rules → global behavior; the three boid rules, each visualized alone before combining; perception radius; `Boids`; differential growth as "a line that wants space"; stateful systems you step (holding a class across frames).
Assumes: Ch 8 (Ch 9 helps).
Payoff: a living flock piece, colored by heading.
Figures: steering-move diagram; wander/arrive diagrams; one diagram per boid rule; rule-combination sequence; a growth time-lapse strip; the finished piece.
Draws from: `Docs/Generators/Steering.md`, `Docs/Generators/Boids.md`, `Docs/Generators/DifferentialGrowth.md`; `Examples/Motion/Steering`, `Examples/Patterns/Flocking`, `Examples/Patterns/DifferentialGrowth`.

**11. Growing things.**
Teaches: recursion by drawing (a fractal tree written by hand first); rewriting rules (L-systems) and the turtle, grown iteration by iteration; branching with the stack; stochastic rules; space colonization (growth that claims space: veins and trees from attraction points, the pipe model for weight); diffusion-limited aggregation (growth by chance: frost from frozen walkers); Wave Function Collapse as "every neighbor must agree", watched as it solves; the chance games (the chaos game deriving the same fern a second way, then fractal flames, circle-inversion limit sets, and Kleinian limit curves).
Assumes: Ch 4 (seeds), Ch 6 (grids, for WFC), Ch 10 (stateful steppers).
Payoff: a procedural garden.
Figures: branch-stack diagram; L-system expansion table + drawing per iteration; a space-colonization growth sequence; a DLA cluster; WFC solve sequence; the garden.
Draws from: `Docs/Generators/LSystem.md`, `Docs/Generators/SpaceColonization.md`, `Docs/Generators/DiffusionLimitedAggregation.md`, `Docs/Generators/WaveFunctionCollapse.md`; `Examples/Patterns/LSystem`, `Examples/Patterns/Venation`, `Examples/Patterns/Dendrite`, `Examples/Patterns/WaveFunctionCollapse`.

**12. Fields and flow.**
Teaches: a field as "an answer at every point" (the mental model shaders and SDFs later reuse); visualizing a field with arrows; `FlowField` from noise; level curves of a scalar field (`isolines`, marching squares, the stacked-levels contour map, the image form); tracing streamlines; evenly-spaced streamlines; advecting particles; strange attractors as found motion.
Assumes: Ch 5 (noise), Ch 8 (vectors).
Payoff: a flow-field print (the Fidenza look, credited as such).
Figures: field-of-arrows diagram; streamline tracing step diagram; even-spacing comparison; attractor plates; the print.
Draws from: `Docs/Generators/FlowField.md`, `Docs/Drawing/Attractors.md`; `Examples/Patterns/Streamlines`, `Examples/3D/StrangeAttractor`.

**13. Shapes as material.**
Teaches: `Path` and `Shape` (curves, contours, holes); booleans (union/subtract/intersect) as vocabulary; offsetting; Voronoi and Delaunay from scattered points; blue-noise scatter; circle and shape packing; hatching fills for pen plotters; SVG export.
Assumes: Ch 4 to 6, Ch 8.
Payoff: a plotter-ready composition (exported SVG shown beside the raster render).
Figures: boolean-ops diagram; Voronoi/Delaunay duals; packing time-lapse; hatching close-up; the composition.
Draws from: `Docs/Drawing/Geometry.md`, `Docs/Drawing/Voronoi.md`, `Docs/Generators/BlueNoise.md`, `Docs/Generators/Packing.md`, `Docs/Generators/ShapePacking.md`, `Docs/Output/Export.md` (SVG); `Examples/Shapes/`, `Examples/Patterns/`.

### Part III: Pixels and light

**14. Layers and effects.**
Teaches: drawing into a layer (`renderTarget`/`withTarget`); filtering a layer (blur, bloom, the catalog at a glance); compositing with blend modes; `compose { }`; feedback (trails, tunnels); accumulation (`noClear`) and long-exposure looks; HDR and `toneMap` (why bright light needs rolling off).
Assumes: Part I; Ch 12's field mental model helps.
Payoff: an earlier piece reworked with layers, glow, and feedback.
Figures: layer-graph diagram; filter-family contact sheet; blend-mode grid; a feedback step sequence; before/after of the rework.
Draws from: `Docs/Drawing/Effects.md`, `Docs/Drawing/Accumulation.md`, `Docs/Drawing/HDR.md`; `Examples/Effects/`.

**15. Your first shader.**
Teaches: the per-pixel mental model (the Ch 12 field, evaluated by the GPU at every pixel); uv space; writing `shade(uv, info)`; color as a return value; params; the shaping functions from Ch 3 reappearing per-pixel (smoothstep as an edge, this time already familiar); the shader library at a glance; `Visual` chains for combining without writing code.
Assumes: Ch 3 (shaping), Ch 12 (fields), Ch 14 (layers).
Payoff: a live animated shader visual.
Figures: the pixel-grid mental-model diagram; uv-space diagram; smoothstep-as-edge pair; chain-graph diagram; the visual.
Draws from: `Docs/Shaders/Shaders.md`, `Docs/Shaders/Visuals.md`, `Docs/Shaders/ShaderLibrary.md`; `Examples/Shaders/`.

**16. Simulations.**
Teaches: state that lives on the GPU; Game of Life (rules → life); reaction-diffusion (two chemicals, endless pattern) with the feed/kill map explored by knobs; fluid; the ripple pool (marks add height, and why a drop must be soft and brief); Chladni figures as the wave you solve rather than simulate; seeding and forcing a sim by drawing into it; recoloring sim state through filters; GPU particles at a million (the sandpainting look, with accumulation from Ch 14).
Assumes: Ch 14 (Ch 15 helps but isn't required; kernels are presented as recipes).
Payoff: a reaction-diffusion organism piece, seeded by the reader's drawing.
Figures: GoL rules diagram; feed/kill parameter map; sim-seeding sequence; particle-count scaling strip; the organism.
Draws from: `Docs/Shaders/Compute.md`, `Docs/Drawing/Effects.md` (sim fields); `Examples/Simulation/`, `Examples/Compute/`.

### Part IV: The third dimension

**17. 3D, gently.**
Teaches: the camera as an orbiting eye (`cameraShowcase`, drag to look); depth; solid primitives; the 3D transform stack; lights and materials by playing (presets, then individual lights); matcap as "shading from a picture"; loading a mesh; growing a landscape (`Heightfield`, diamond-square, hydraulic and thermal erosion, the three read-outs); casting shadows; the scene-inspection views.
Assumes: Part I; Ch 8 (vectors; `Vector3` is introduced as "the same, plus z").
Payoff: a rotating sculptural scene the viewer can orbit.
Figures: camera-orbit diagram; primitive catalog sheet; lighting-preset contact sheet; material sweep; the scene.
Draws from: `Docs/3D/3D.md`, `Docs/3D/Camera.md`, `Docs/3D/Combining.md`; `Examples/3D/`.

**18. Sculpting with fields.**
Teaches: signed distance as "how far, and which side" (one diagram); the 2D combinators (`SDF`, smooth union as melting) built on Ch 12's field model; then the same idea raymarched in 3D (`SDF3D`, `drawSDF3D`); domain tricks (mirror, repeat) as space folding; a light touch of environments/PBR for the finish (pointers to Docs for depth).
Assumes: Ch 12, Ch 17 (Ch 15 helps).
Payoff: a melted-glass sculpture, orbitable.
Figures: signed-distance diagram; smooth-min melt strip; a march-the-ray diagram; domain-repetition diagram; the sculpture.
Draws from: `Docs/Drawing/Combinators.md`; `Examples/Shapes/Combinators*`, `Examples/3D/Raymarching/`.

**19. Depth and the iPhone as a sensor.**
Teaches: point clouds; what an RGBD frame is (color + depth + intrinsics, one diagram); playing a recorded `.r3d` clip as a cloud; the live USB stream; the Ollin Capture app streams (body, face, world depth, segmentation); world fusion (sweeping a room into one cloud); depth compositing (2D drawing inside a 3D scene).
Assumes: Ch 17. Requires hardware for the live half; the recorded-clip path works for every reader and leads the chapter.
Payoff: a room-scan artwork (or a recorded-clip artwork without the hardware).
Figures: RGBD anatomy diagram; unprojection diagram; a fusion sweep sequence; the artwork.
Draws from: `Docs/3D/RGBD.md`, `Docs/3D/Record3D.md`, `Docs/3D/Phone.md`, `Docs/3D/DepthCompositing.md`; `Examples/3D/` (Depth/Phone groups).

### Part V: Out into the world

**20. Sound and control.**
Teaches: hearing (`amplitude`, `spectrum`, bands, beats) and drawing what you hear; the microphone vs a file; MIDI knobs and pads; OSC from a phone/tablet; binding any of them to `@Param` so one sketch is playable from anywhere.
Assumes: Part I (Ch 14 makes richer visuals).
Payoff: an audio-reactive visual played with a MIDI controller (or the keyboard/mouse fallback).
Figures: spectrum-anatomy diagram; beat-detection timeline; a binding-flow diagram (controller → param → visual); the visual.
Draws from: `Docs/Helpers/Audio.md`, `Docs/Integration/MIDI.md`, `Docs/Integration/OSC.md`, `Docs/Helpers/Parameters.md`; `Examples/Audio/`, `Examples/Integration/`.

**21. Seeing.**
Teaches: the webcam as a live image; the tracker model (attach, read typed results in `draw`); a tour in three depths: hands/face/body (taught), contours and optical flow (shown), the wider catalog (pointed); coordinate mapping done right; video files as material, including analyzing them.
Assumes: Part I; Ch 7 (images), Ch 8 (vectors).
Payoff: an interactive mirror piece (the reader's motion paints).
Figures: tracker-flow diagram; landmark-map figures; a flow-field-from-motion figure; the mirror.
Draws from: `Docs/Vision/Vision.md`, `Docs/Video/Video.md`; `Examples/Vision/`, `Examples/Video/`.

**22. Sharing and performing.**
Teaches: exporting stills, sequences, video, GIF; SVG for plotters (closing Ch 13's loop); publishing to other apps (Syphon) and as a system camera; the live-coding host (`OllinLiveCoding`): evaluate-on-command, code over visuals, performing a set; reproducibility as a sharing feature (seeds, params).
Assumes: everything before it, lightly.
Payoff: a short performed piece, live-coded, recorded, and shared.
Figures: export-formats map; a Syphon-into-another-app screenshot; the performance host annotated; frames from the performance.
Draws from: `Docs/Output/Export.md`, `Docs/Integration/Syphon.md`, `Docs/Integration/VirtualCamera.md`, `Docs/Tools/LiveCoding.md`; `Examples/Export/`, `Examples/Live/`.

### Appendices

**A. Just enough Swift.** The guide's Swift, gathered: values and types, functions and labels, classes vs structs, closures, optionals as encountered, property wrappers as used by `@Param`/`@Eased`. Builds on `Docs/Swift.md` rather than duplicating it: the appendix is the pedagogical pass, the primer stays the quick reference. Written after several chapters exist so it matches what the guide actually uses. Decided 2026-07-08, the three Swift docs get one reader each: A is the narrative pass for the Guide's audience (an engineer from any language, no p5 assumed), `Docs/Swift.md` becomes the pure language quick-reference, and Appendix C owns the p5/Processing angle (see C's brief for the `Docs/Swift.md` refocus that goes with it).

**B. Just enough math, visually.** One page per idea, each with an Ollin-rendered picture: coordinates, angles and radians, sine/cosine as a circle, vectors, interpolation and the shaping functions, distance, randomness distributions, fields, matrices as "move/turn/scale" (no algebra). Every chapter that introduces a math idea adds its entry here in the same session, as a picture-plus-plain-words page in the matching theme group.

**C. Coming from p5.js and Processing.** The translation table (`circle()` → `drawCircle`, `createCanvas` → `canvasSize`, `push`/`pop` → `withState { }`, `random` seeds, `noise`, classes, the loop), what's the same, what's idiomatically different, and the habits worth dropping. This is also the roadmap's migration-guide item; writing this appendix completes it. Decided 2026-07-08: C owns the p5/Processing framing outright, and the session that writes it also refocuses `Docs/Swift.md` into the pure language quick-reference (today it's titled "Swift for p5.js newcomers", which is C's job): move the p5 comparisons here, keep the language mechanics there, cross-link both ways.

**D. The complete toolbox.** The 100%-coverage surface, generated from the matrix below: every capability, one plain-words line, where the Guide teaches it (if it does), and its Docs page. Doubles as the guide's index of the framework.

## Feature-coverage matrix

The guarantee that the Guide gives awareness of everything Ollin ships. One row per capability (keyed by Docs page, plus rows for capabilities without their own page). Depth, from most to least:

- **taught**: a chapter section explains it, with a figure. This is the goal for every row.
- **shown**: it appears in a worked example with a sentence or two, so a reader can find it and run it. This is the floor for anything that has shipped.
- **pointed**: named with a one-liner and a Docs link, at minimum in Appendix D. **Not a resting place.** A `pointed` row is a promise to teach, and it is only legal while the Guide debt ledger below names the chapter it is owed to.

`Scripts/guide-coverage.sh` enforces the rules: no row unassigned, no row `pointed` without a debt entry, every Docs page has a row, every Docs page reachable from a numbered chapter's "Go deeper" list, and every Docs page present in Appendix D. Run it before committing anything that ships a user-facing capability; it is step 5 of the ship checklist in `CLAUDE.md`.

Why the script exists rather than a habit: a row marked `pointed` used to satisfy the checklist completely, so a feature could ship, get its one-line table entry, and never be taught. Seven slices landed that way over two days at the end of July 2026 while every audit stayed green, because the matrix said each row was accounted for. Counting rows was never the check; the check is that the depth column is honest.

| Capability (Docs page) | Guide home | Depth |
|---|---|---|
| `Core/Sketch.md` (lifecycle, time, loop) | Ch 1 | taught (`setup()`/`draw()` and the clock; `noLoop()` and `@main` pointed) |
| `Core/Canvas.md` (canvasSize, windowMode) | Ch 1 | taught ("The canvas is not the window" with a diagram: the two are independent, `width` reports the canvas either way, exports ignore the window, the preset families including paper sizes and `.dpi()`, and the three `windowMode` cases) |
| `Swift.md` (language primer) | Ch 1 callouts, Appendix A | taught |
| `Drawing/Drawing.md` (shapes, state, transforms) | Ch 1, Ch 6 | taught |
| Variable-width strokes (`strokeProfile`/`noStrokeProfile`, `StrokeProfile`, in `Drawing/Drawing.md`) | Ch 13 | taught ("A mark, not a line" with a three-panel figure: the profile as a multiplier on `strokeWeight`, taper/ramp/values along the path against the direction-driven nib, sampling density, why the analytic shapes ignore it, and the filled-outline vector export) |
| Stroke dynamics (`StrokeMark`/`drawMark`, `StrokeDynamics`/`StrokeResponse`/`StrokeInput`, `pressure`/`pressureIsAvailable`; `Drawing/Marks.md`) | Ch 13 | taught ("A mark you are still making" after the profile section, with a three-panel figure over one paced curve: why a fraction along the path cannot exist mid-stroke, the ten-line paint loop, width and opacity as separate named axes, the pressure fallback read in `mousePressed()`, and profiles composing with dynamics) |
| Brushes (`strokeBrush`/`noStrokeBrush`, `Brush`; `Drawing/Marks.md#brushes`) | Ch 13 | taught ("A mark made of many marks" after the dynamics section, with a three-panel figure over one S-curve: separate stamps reading as a solid mark, spacing measured in stamp sizes rather than pixels, the jitter/angle/scatter/count knobs as fractions of the stamp, non-circular tips, composing with a profile, and stamps exporting as real shapes) |
| Kaleidoscope symmetry (`symmetry`/`noSymmetry`, in `Drawing/Drawing.md`) | Ch 6 | taught ("The fold, done for you" after the hand-rolled rotate loop, with a three-panel figure: symmetry as drawing state, why the mirrored form is the one worth having, and folding around the current origin) |
| Clipping (`withClip`, in `Drawing/Drawing.md`) | Ch 6 | taught ("Drawing inside a shape" with a three-panel figure: the same stripes confined three ways, all three region types, and nesting as intersection) |
| `Drawing/Color.md` (Color, OKLab, palettes, colormaps) | Ch 2 | taught |
| Gradient paint (`Drawing/Color.md`) | Ch 2 | taught |
| Palette file import (`loadPalette`/`loadPalettes`, hex/CSV/TSV/JSON/ASE; `Drawing/Color.md`) | Ch 2 | taught |
| Palette extraction from an image (`Palette(extractedFrom:)`; `Drawing/Color.md`) | Ch 2 | taught |
| Image dithering (`Image.dithered`: error diffusion, ordered Bayer, blue noise; `Drawing/Color.md`) | Ch 2 | taught (a three-panel figure over one gradient: why snapping bands, the two families and how each decides, `.none` as the teaching control, `levels:` posterizing, and the do-it-in-setup rule) |
| Retained batches (`Batch`, `makeBatch`/`drawBatch`; `Drawing/Batches.md`) | Ch 13 | taught (after the plate's setup/draw split: what is still costing you per frame, `makeBatch`/`drawBatch`, the measured 150k-circle numbers, transforms at replay, and the refuse-at-the-funnel list) |
| `Helpers/Math.md` (map, lerp, dist; the shaping scalars clamp/fract/step/smoothstep) | Ch 3, Appendix B | taught |
| `Helpers/Animation.md` (easing, @Eased, @Smoothed, Timeline; loopProgress/pingPong) | Ch 3 | taught |
| `Helpers/Input.md` (mouse, keyboard) | Ch 1 | taught |
| `Helpers/Parameters.md` (@Param) | Ch 1; bindings in Ch 20 | taught (typed family: sliders/stepper/color well taught in Ch 1's finished piece, the rest named + pointed; groups/icons pointed) |
| `Generators/Random.md` | Ch 4 | taught |
| `Generators/Noise.md` (noise, signedNoise, loop:, fbm, curlNoise) | Ch 5; curl in Ch 12/16 | taught |
| Noise toolkit (simplexNoise, worley, ridgedFbm/turbulence, warpedFbm; the `.cellular` generator + `.noise` warp knob; `Generators/Noise.md`) | Ch 5 (shader-lib mirror named in Ch 15) | taught (the family toured with two figures in Ch 5; feature:/jitter: and warp: explained; GPU legs pointed to the Cellular/DomainWarp examples) |
| `Drawing/Geometry.md`: `Grid`, `Insets` | Ch 6 | taught |
| `Drawing/Truchet.md` | Ch 6 | taught |
| `Drawing/Tiling.md` (HexGrid/TriangleGrid, subdivide, Maze, apollonianGasket) | Ch 6 | taught ("Grids that aren't square" with a four-panel figure: the other two regular tilings and why hexes keep their proportions, hex ring distance, recursion versus tabulation for layout, what makes a maze perfect and the algorithm as a texture knob, plus the gasket) |
| `Drawing/Text.md` (three font kinds, textToShapes, atlas) | Ch 7 | taught (drawText/textSize/textAlign, the three kinds, perGlyph, textToShapes warp, atlas mode; on-path/box/metrics/variable axes named + pointed) |
| `Drawing/Images.md` (Image, pixels, tint) | Ch 7 | taught (loadImage/drawImage/tint, blank-image authoring, the pixel subscript both ways; resource loading named) |
| `Drawing/Geometry.md`: `Vector2`/`Vector3`, `Rectangle`, `Circle` | Ch 8, Ch 17 | taught (Vector2 arrows, +/−/scale, length/normalized/limited/distance/angle, with(x:y:) taught in Ch 8; dot/cross/lerp/rotated/projected pointed; Vector3 waits for Ch 17) |
| `Simulation/Physics.md` (Verlet + rigid World) | Ch 9 | taught (forces by hand + accumulate/divide-by-mass; World/step, particle collisions, bounds/bounce/drag, springs/rest length/stiffness, pin/place, Body/colliders/friction/density/restitution, .static, the revolute joint, grab; push/strain/soft blobs/other joints named + pointed) |
| `Generators/Boids.md` | Ch 10 | taught |
| `Generators/Steering.md` | Ch 10 | taught |
| `Generators/DifferentialGrowth.md` | Ch 10 | taught |
| `Generators/SpaceColonization.md` | Ch 11 | taught |
| `Generators/DiffusionLimitedAggregation.md` | Ch 11 | taught |
| `Generators/LSystem.md` | Ch 11 | taught |
| `Generators/WaveFunctionCollapse.md` | Ch 11 | taught |
| `Generators/FlowField.md` (streamlines, advection) | Ch 12 | taught |
| `Drawing/Attractors.md` (strange attractors, chaotic maps) | Ch 12 | taught |
| `Drawing/Geometry.md`: `Path`, `Shape`, booleans, offset | Ch 13 | taught |
| `Drawing/Voronoi.md` (+ Delaunay, Lloyd) | Ch 13 | taught |
| `Generators/BlueNoise.md` | Ch 13 | taught |
| `Generators/LowDiscrepancy.md` (`haltonPoints`, `sobolPoints`) | Ch 13 | taught (beside blue noise, with a growth figure: not random at all, the incremental property blue noise lacks, why it never touches the sketch rng, and the scalar `halton`) |
| `Generators/Stippling.md` (`stipple`, weighted-Voronoi) | Ch 7 | taught ("A picture as one line" explains the settling method in plain words before the Voronoi structure is named in Ch 13, plus `count` and the `cutoff` rounding) |
| `Generators/SingleLine.md` (`singleLine`, the TSP tour) | Ch 7 | taught (the tour beside the tree in a three-panel figure, both the `through:` and `of:points:` forms) |
| `Generators/SpanningTree.md` (`spanningTree`, the MST rendering) | Ch 7 | taught (same figure and section; the minimal-chain decomposition explained as pen lifts) |
| `Generators/Isolines.md` (`isolines`, marching-squares level curves) | Ch 12 | taught ("Where the field equals something" with a three-panel figure: scalar versus direction fields, marching squares explained by the sixteen corner patterns, `resolution`, why the stacked-levels form costs almost nothing extra, open versus closed contours, and the image form) |
| `Generators/Hulls.md` (`concaveHull` / `alphaShape`) | Ch 13 | taught ("What shape are these points?" with a three-panel figure over one scatter: convex vs concave vs alpha, the `concavity` and `alpha` ranges that read well, and which to reach for by what happens next) |
| `Generators/MedialAxis.md` (`medialAxis`, skeletons with radii) | Ch 13 | taught ("The skeleton inside" with a two-panel figure: branches and the inscribed disks, `spacing`/`prune` explained, `isClosed` rings, and what the radii are good for) |
| `Generators/Marbling.md` (`Marbling`, closed-form paper marbling) | Ch 13 | taught ("Ink on water" with a four-panel figure: the bull's-eye of drops, the area-preserving push, the shared falloff law, all four raking tools, `add`, and the concentric-swirl no-op) |
| `Generators/Watercolor.md` (`Watercolor` / `drawWatercolor`, layered deformation) | Ch 13 | taught ("Pigment from a polygon" with a three-panel figure: the starting polygon, one 4% layer, forty stacked; layers-vs-opacity, `variance`, the paint-once rule, and interleaving two pigments) |
| `Generators/Chladni.md` (`chladni` field + `.chladni` generator, mode-by-pitch audio join) | Ch 16 | taught ("Standing waves" with a six-mode figure: the closed form and plate coordinates, sand settling at the zero crossing, the m == n degeneracy, fractional modes for morphing, both generator styles, and the Ch 20 audio join pointed) |
| `Generators/Isosurface.md` (`isosurface`, `Metaballs`, marching cubes) | Ch 18 | taught ("The other way out" after the sphere-tracing section, with a two-panel figure of one coarse metaball chain shaded and wireframed: a field becoming an ordinary `Mesh` rather than pixels, `radius` as the size a ball reads at alone, why summed fields make blobs fuse and neck, the `level` and negative-`strength` knobs, why a coarse mesh still reads smooth (normals from the field, not the facets), the above-the-level solidity convention that makes a distance function need a minus sign, and the pay-by-the-pixel versus pay-by-the-volume choice) |
| `Generators/Terrain.md` (`Heightfield`, diamond-square, hydraulic + thermal erosion, terrain meshes) | Ch 17 | taught ("A landscape you grow" with a three-stage erosion figure and a lit mesh: the closure and diamond-square builders, `roughness`, why rain is what makes noise read as land, thermal talus settling, the three read-outs, and the erode-in-setup rule) |
| `.ripples` wave-equation Sim (`Drawing/Effects.md`) | Ch 16 | taught ("A pool you can drop things into" with a figure: marks add height rather than set it, the soft-dab and brief-drop rules and why, `damping`, and the raw state as a debug view to shade with `.relight`) |
| `Drawing/GlyphMosaic.md` (`drawGlyphMosaic`, measured glyph ramps) | Ch 7 | taught ("A picture as marks" with a two-panel figure: measured ink per font, the curated sets, `glyphScale` gutters, the data form, and the inverted-polarity trap it shares with halftone) |
| `Drawing/PixelSorting.md` (`Image.pixelSorted`) | Ch 7 | taught ("Sorting the pixels" with a before/after figure: the threshold as the whole technique, the keys, and the needs-texture and reversed-on-a-gradient caveats) |
| `Drawing/Halftone.md` (`drawHalftone`, area-exact dot screens) | Ch 7 | taught (same section and figure: `pitch`/`angle`, area-exact coverage, real circles for the plotter, and continuous tone versus the mosaic's steps) |
| `.melt` design filter (`Drawing/Effects.md`, the luminance melt) | Ch 14 | taught (a before/after figure beside the design filters, the shared displacement vector that makes it read as dyed rather than smeared, the brightness mix-back, the dial-back knobs, and the never-perfectly-loops caveat) |
| `Video/SlitScan.md` (`SlitScan` frame history) | Ch 21 | taught ("The past as material" with a synthetic-clip figure: the rolling history, the delay closure and what 0 and 1 mean, alternative delay maps and the image form, the memory cost, and the `Ollin.SlitScan` shadowing note) |
| `Generators/Walks.md` (`randomWalk`, `levyFlight`, `selfAvoidingWalk`) | Ch 4 | taught ("Three walks, three rules" after the hand-rolled walk, with a same-seed three-panel figure: why an even-stepped walk pools, the power-law step lengths and the foraging connection, the `minStep` divergence, and getting stuck as the point of the self-avoiding one) |
| `Generators/Packing.md` (circles) | Ch 13 | taught |
| `Generators/ShapePacking.md` | Ch 13 | taught ("Packing shapes, not circles" with a two-panel figure of one packing: why a spiky outline is the interesting case, the bounding circles drawn overlapping as proof the fit used outlines, what `padding`/`rotation`/`scale` change in character, and `ContinuousPacking` held open against `noClear()`) |
| Hatching (`Output/Export.md`) | Ch 13 | taught |
| Perfect-loop export (`--export-loop`, `loopDuration`; `Output/Export.md`) | Ch 3 | taught |
| `Drawing/Epicycles.md` (Fourier epicycles) | Ch 13 | taught ("Circles all the way down" with a rising-term figure: the largest-first prefix, exactness at full terms, under-terming as a smooth simplifier, and the construction versus the path) |
| `Drawing/Curves.md` (classic curves: phyllotaxis, lissajous, rose, hypotrochoid/epitrochoid, `Harmonograph`, Chaikin `smoothed`) | Ch 13 | taught ("Curves you can write down" with a six-panel figure: the golden angle and why it can't line up, the frequency ratio, petal parity, whole-number gears, damped pendulums, corner cutting, and the fit-by-points rule) |
| `Drawing/Morphing.md` (shape morphing: `ShapeMorph`, `Tweenable` geometry) | Ch 13 | taught ("One shape becoming another" with a five-step figure: build-once-read-cheap, exact originals at the ends, unmatched contours growing from their own centre, and timing living outside the read) |
| `Drawing/SVG.md` (SVG import: `loadSVG`, `drawSVG`) | Ch 13 | taught |
| `Drawing/Effects.md` (targets, filters, compose, combine) | Ch 14 | taught (targets/filters/generators/compose/feedback taught; combine + aside pointed) |
| Blend modes (`Drawing/Drawing.md`) | Ch 14 | taught |
| Feedback (`Drawing/Effects.md`) | Ch 14 | taught |
| `Drawing/Accumulation.md` (noClear) | Ch 14; used in Ch 16 | taught |
| `Drawing/HDR.md` (toneMap) | Ch 14 | taught |
| Design patterns + design filters (`Drawing/Effects.md`) | Ch 14 | taught ("The design family" with a six-tile two-row figure: the generator set and the phase-is-a-number rule that keeps exports reproducible, then the filters split into the alpha-shape readers (draw a shape, then filter it) and the picture transformers, plus the tuned-for-full-canvas caveat and the `edges` knob) |
| Relight, two-tone dither, warp centers (`Drawing/Effects.md`) | Ch 14 | taught ("Filters that read the layer as something else" with a three-panel figure: brightness as height and the five finishes, brightness as tone with `pixelSize` grain, and `center:` in 0…1 layer coordinates as the knob that makes a warp a composition) |
| Pattern fields (`Drawing/Effects.md`) | Ch 15 | taught ("The pattern fields" with a six-field catalog plus a hand-rolled gyroid beside the built-in: closed form as the defining property and its three consequences, all six named, reading a 3D field at a moving slice, and the sRGB palette convention) |
| Escape-time fractals (`Drawing/Effects.md`) | Ch 16 | taught (escape time as the step count that becomes the color, the marked-c figure showing a Julia set as a portrait of one Mandelbrot point and why edge points are richest, smooth banding with `cycles`/`phase`, and the zoom-needs-iterations trap) |
| `Generators/Fractals.md` (`IFS`, `FractalFlame`, inversion and Kleinian limit sets, Schottky circle orbits) | Ch 11 | taught ("The same fern, played as a game" derives the chaos game from the chapter's own L-system fern with a condensing figure and explains why contraction forces the attractor; "Three more games worth knowing" covers flames, inversion, and Kleinian with a three-panel figure, plus `fitted` and the Contour return; "Circles that pair off" builds the Schottky lace from four paired circles with a three-panel nesting figure, explains why a touching pair keeps the picture full where a separated one empties it, and bridges to the trace recipe with a four-member family figure around the gasket) |
| Depth-of-field `.defocus`, SSAO, SSR (`Drawing/Effects.md`) | Ch 17 | taught ("What the depth buffer is for" with a three-panel figure: depth as an ordinary layer, occlusion as what stops objects floating, focus/range read against near/far, SSR's cannot-see-the-back limit, and quality tiers resolving on export) |
| `Shaders/Shaders.md` (user shaders) | Ch 15 | taught |
| `Shaders/Visuals.md` (Visual chains) | Ch 15 | taught |
| `Shaders/ShaderLibrary.md` (helper reference) | Ch 15 | taught (the named families, plus what splicing means: one source compiled into framework shaders, user shaders, and compute kernels, so a field behaves identically wherever you move it, and the `using:` opt-out) |
| `Shaders/Compute.md` (kernels, Particles, Simulation) | Ch 16 | taught |
| Sim fields: Game of Life, Gray-Scott, fluid (`Drawing/Effects.md`) | Ch 16 | taught |
| Artificial life: `ParticleLife`, `PPS`, `Physarum`, `SpatialHash` (`Simulation/ArtificialLife.md`) | Ch 16 | taught ("Crowds that organize themselves" with a three-panel figure: the neighbor-search problem `SpatialHash` solves, all three systems with their rules and calls, and the no-frame-exact-reproducibility caveat) |
| Fluids & soft bodies: `ParticleFluid`, `SoftBodies` (`Simulation/Fluids.md`) | Ch 16 | taught ("Liquids and jellies" with a two-panel figure: SPH density-to-pressure explained, `stiffness`/`nearStiffness`/`gravity`, shape matching and `squish`, and grabbing with `pull`) |
| Cellular automata: Lenia sim, `elementaryCA`/`totalisticCA`, `Turmite` (`Generators/CellularAutomata.md`) | Ch 16 | taught ("More ways to be an automaton": elementary rules as a numbered rule byte with rules 30/90/110, `totalisticCA` named, `Turmite`/Langton's ant held and stepped, and Lenia with its knobs and the dense-seed rule; two figures) |
| Articulated & chaotic motion: `IKChain`, `DoublePendulum`, `NBody` (`Simulation/Motion.md`) | Ch 9 | taught (all three toured in "Three ready-made motion systems" with a three-panel figure: `reach`/`drag` and the solver/`maxBend` knobs, the pendulum's determinism-plus-sensitivity, and n-body's `theta`/`softening` and the seeded factories) |
| Damped spring: `DampedSpring`, `@Sprung` (`Helpers/Animation.md`) | Ch 3 | taught (duration/bounce, the moving-target case that separates it from `@Eased`, and `kick`; `velocity` and `Vector2` springs pointed) |
| `3D/3D.md` (camera, primitives, meshes, lights, materials) | Ch 17 | taught |
| `3D/Camera.md` (cameraControl, moves, showcase, views) | Ch 17 | taught |
| `3D/Combining.md` (what stacks with what) | Ch 17/18 | taught (the concept in Ch 17's bearings section: several kinds of 3D thing reach the screen by different routes, so finishes apply unevenly, with the table pointed for lookup) |
| Matcap (`3D/3D.md`) | Ch 17 | taught ("Shading from a picture": sampling by facing direction, why baked lighting is both the appeal and the limit, when a material is the better choice, the 26 built-ins by family, `Matcap.shaded`, and the `fill` tint) |
| PBR materials + IBL environments + procedural sky (`3D/3D.md`) | Ch 18 | taught ("The finish" in two parts with a roughness run and a two-image environment pair: metal versus dielectric and roughness, why a mirror with nothing to reflect goes dark (so PBR and environments are one topic), the bundled eight versus the downloading twelve, `.sky` as the zero-asset option, and `lightingOnly`/`backgroundBlur`) |
| Shadows: 2D map, PCSS, ray-traced point (`3D/3D.md`) | Ch 17 | taught ("Shadows, and what they tell you" with a rising-height figure: shadows as the only cue for height, contact hardening and `shadowSoftness`, the four practical notes (a receiver is needed, opt-in and per-frame, one caster chosen for you, nothing to aim), the three caster routes as an explanation of cost, and `shadowQuality` for graininess) |
| Ray-traced reflections (`3D/3D.md`) | Ch 18 | taught ("Mirrors that see off screen": traced rays versus searching the finished picture, integration into the environment rather than post-process, the three conditions, no-op where unavailable so the call can stay in, and the settle-then-clean behavior) |
| Wireframe, textured meshes, mesh loading (`3D/3D.md`) | Ch 17 | taught (loading with the `normalized(scale:)` habit, then a three-panel figure for the other two dressings: `wireframe()` as both an inspection tool and a look (and why it does not light), `textured(_:)` with the pole pinch a checker reveals, and all three as stack state in one frame) |
| Point clouds (`3D/3D.md`) | Ch 19 | taught |
| `Drawing/Combinators.md` (SDF 2D + SDF3D raymarching) | Ch 18 | taught |
| `3D/DepthCompositing.md` | Ch 19 | taught ("Flat drawing that knows where it is" with a three-pillar figure: `depth(at:)` sets depth alone, `project` returns nil behind the camera, `withBillboard` does both and moves the origin, why a 2D mark keeps its canvas size, and `depth(_:)` for a feed) |
| `3D/RGBD.md` | Ch 19 | taught |
| `3D/Record3D.md` | Ch 19 | taught |
| `3D/Phone.md` (capture app streams, world fusion) | Ch 19 | taught |
| `Helpers/Audio.md` (analysis, beats, sources) | Ch 20 | taught |
| `Integration/MIDI.md` | Ch 20 | taught |
| Tempo sync (`TempoClock` over MIDI clock; `Integration/MIDI.md`) | Ch 20 | taught (a musical-time diagram: 24 ticks per beat is the whole protocol, why counting means the grid can't drift, every reader with a worked position, `progress(over:)`, and the arm-on-next-tick and free-running-master behaviors) |
| `Integration/OSC.md` | Ch 20 | taught |
| `Vision/Vision.md` (16 trackers, ModelTracker) | Ch 21 | taught (all sixteen: hands/face/2D body/contours/optical flow, the segmenters, the 3D body read in its three spaces, then four sections for the rest with three figures built from synthetic scenes, so no figure needs a camera, a person, or downloaded weights: the card read by the rectangle detector and the OCR, the fitted trajectory carried past its last sighting onto where the ball really went, and the saliency map beside the classifier's confidence floor; `ModelTracker`'s four output surfaces are taught, with its weights left to the reader since Ollin ships none) |
| `Video/Video.md` (playback as texture) | Ch 21 | taught |
| `Integration/Syphon.md` | Ch 22 | taught |
| `Integration/VirtualCamera.md` | Ch 22 | taught ("The sketch as a webcam": why the browser needs a camera and Syphon cannot cross that line, the system extension and its one-time approval, the test card, the fixed 1280x720 letterbox and 30 fps, and suspecting the viewer first when the picture looks mirrored or cropped) |
| `Output/Export.md` (PNG, sequence, video, GIF, SVG, PDF) | Ch 3 (GIF), Ch 13 (SVG), Ch 22 (all) | taught |
| Reproducibility metadata in exports (`Output/Export.md`) | Ch 22 | taught (what the recipe holds, where it lives and why that slot exists, reading it back with `exiftool`, the recover-a-past-render scenario, and the GIF and missing-code limits) |
| Print separations (`Image.separated` into spot inks, screening, `--export-separations`; `Output/PrintSeparations.md`) | Ch 22 | taught ("Printing one ink at a time" with a masters-plus-overprint figure: what a master is, why translucent inks make more colors than drums, `printInks` and the in-code form, the perceptual nearest-mix search, and the minimum-dot and rosette notes) |
| Variations & seed exploration (`Core/Variations.md`): `variation`, the Variation card, `--export-grid`, `--seed` | Ch 4 | taught |
| Normalized coordinates `uv(u, v)` (`Core/Canvas.md`) | Ch 1 | taught ("Placing things without pixels" with a six-panel figure of one layout in three canvas shapes, placed by pixels and by fractions; `uv` corners and `scale` for sizes, plus honest guidance on when plain pixels are fine) |
| `Tools/LiveCoding.md` (OllinLiveCoding) | Ch 22; OllinLive workflow in Ch 1 | taught |
| Single-file sketches (the `ollin` command, hashbang files; `Tools/SingleFile.md`) | Ch 1 | taught ("A shorter way to run things": `install`/`new`/run, what it means that a sketch is one file, export flags on a loose file, and the hashbang form) |
| Examples gallery (`swift run OllinExamples`) | Ch 1 | taught ("The gallery" with a layout diagram: the three panes, the filter field, hiding the knobs, why arrow keys move the list rather than reaching the sketch, and that every entry is an ordinary sketch file to open and copy) |
| Extension seam (`Sketch.extend`, `SketchExtension`) | Ch 22 | taught ("Adding behavior without touching the sketch": why cross-cutting behavior does not belong in `draw()`, the built-in stats extension as the example, and the opt-in frame readback) |
| Headless capture (`OllinApp.image(of:)`) | Ch 22; used by the Guide's own figure runner | taught ("Rendering from code": the flags are a wrapper around one call, what it does step by step, the batch cases it unlocks, a figure that renders another sketch four times to demonstrate itself, and the Guide's own figure runner as the worked example) |

## Guide debt

Capabilities that shipped in the framework without a Guide section yet. An entry here is the only legal way for a matrix row to sit at `pointed`, and it is a commitment, not a filing cabinet: it names the chapter that owes the section and the date the capability shipped, so the wait is visible and countable.

Add an entry only when a session genuinely cannot teach the feature it just shipped, and say so in the commit message. Then the *next* session touching that chapter clears it. `Scripts/guide-coverage.sh` prints every entry on every run, and fails the build for a `pointed` row that has no entry.

No entries. The one that stood here, Schottky circle orbits owed to Chapter 11, was cleared on 2026-08-01.

| Capability (Docs page) | Owed to | Since |
|---|---|---|

## Roadmap parking lot

Where each open `ROADMAP.md` item will live in the Guide once it ships in the framework. Guide prose is written only for shipped features; this table reserves the seat. When writing a chapter, check whether any of its parked items shipped since this table was made.

| Roadmap item | Future Guide home |
|---|---|
| More SDF shapes | Ch 18 / Appendix D |
| More model examples (ModelTracker) | Ch 21 |
| Generative-geometry refinements | Ch 11 |
| Technique catalog: GPU-scale steering agents | Ch 16 |
| Technique catalog: growth/morphogenesis (Turing patterns, sandpile, growth on meshes) | Ch 16/17 |
| Technique catalog: tiling/layout families | Ch 6 |
| Technique catalog: meshing (point-cloud reconstruction, subdivision surfaces) | Ch 17 |
| Project generator | Ch 1 |
| iPhone sensor array (scene mesh, drift correction) | Ch 19 |
| 3D: loadScene, live camera environment, 3D rigid bodies | Ch 17 (bodies also Ch 9) |
| Photorealistic 3D tier | Ch 17/18, likely a new chapter when substantial |
| Sound synthesis, spatial audio, algorithmic composition | Ch 20, likely splitting into its own chapter |
| Tempo sync: Ableton Link | Ch 20 |
| Live rigs (serial/BLE, DMX/LED, NDI) | Ch 22, or a future installations chapter |
| New input sources | Ch 20/21 |
| New output surfaces (haptics, screensaver, USDZ, fabrication, performance capture) | Ch 22 |
| Rendering/color frontier (P3/HDR out, GPU-driven, path tracing) | Ch 14/22 |
| Authoring/editor tooling | Ch 22 |
| Collaboration and multi-device | future chapter beside Ch 22 |
| Installation mode | future installations chapter |
| Learning (user guide, migration guide, tutorials) | this Guide itself; migration guide = Appendix C |
| Extension ecosystem (ollinx-*) | a future "Extending Ollin" appendix |
| Profiling and GPU debugging | Appendix D note, future appendix |
| Accessibility and inclusive text | Ch 2 (palettes), Ch 22 |
| Swift Playgrounds / iOS, visionOS, AR | a future part or appendix, when the platforms land |
