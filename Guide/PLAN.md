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
| 11. Growing things | `11-GrowingThings.md` | not started |
| 12. Fields and flow | `12-FieldsAndFlow.md` | not started |
| 13. Shapes as material | `13-ShapesAsMaterial.md` | not started |
| 14. Layers and effects | `14-LayersAndEffects.md` | not started |
| 15. Your first shader | `15-YourFirstShader.md` | not started |
| 16. Simulations | `16-Simulations.md` | not started |
| 17. 3D, gently | `17-3DGently.md` | not started |
| 18. Sculpting with fields | `18-SculptingWithFields.md` | not started |
| 19. Depth and the iPhone as a sensor | `19-DepthAndThePhone.md` | not started |
| 20. Sound and control | `20-SoundAndControl.md` | not started |
| 21. Seeing | `21-Seeing.md` | not started |
| 22. Sharing and performing | `22-SharingAndPerforming.md` | not started |
| A. Just enough Swift | `A-JustEnoughSwift.md` | not started |
| B. Just enough math, visually | `B-JustEnoughMath.md` | not started |
| C. Coming from p5.js and Processing | `C-ComingFromP5.md` | not started |
| D. The complete toolbox | `D-TheCompleteToolbox.md` | not started |

Statuses: `not started` → `figures` (figure sketches built and rendered) → `drafted` (prose written) → `done` (humanized, audited, committed). Appendices B and D grow with the chapters (each chapter session adds its math ideas to B's list and flips its features in the coverage matrix), so they stay `not started` until a dedicated session assembles them near the end.

Also tracked here so they aren't forgotten:

- CI wiring for the figure runner is deliberately deferred (CI minutes are scarce); `Scripts/guide-figures.sh` run locally per session is the gate for now. Revisit when several chapters exist.
- A website (Guide + Docs + gallery) is a later project; keep all markdown portable (plain relative links, standard tables, no HTML beyond the sanctioned `<img width>` figure embed in AUTHORING.md).
- Translations are out of scope for now.

## Chapter briefs

Each brief lists what the chapter teaches, what it assumes, the piece it builds toward, and where to draw from. Figure lists are starting points, not contracts; the writing session decides the final set. Every chapter ends with two short sections: "Where this comes from" (technique credits, matching `ATTRIBUTION.md`) and "Go deeper" (links into `Docs/`).

### Part I: Seeing something move

**1. Hello, Ollin.**
Teaches: what a sketch is; `setup`/`draw`; the canvas and its top-left coordinate system; `background`, `fill`, `stroke`; `drawCircle`/`drawRect`/`drawLine`; motion by default (`time` in an expression moves); the working loop for the whole guide: `swift run OllinLive`, edit, save, watch; `@Param` knobs in the inspector; running any repo example.
Assumes: can program a little, in any language. First Swift callouts: a `class ... : Sketch` is a recipe; `var`/`let`; calling functions with labels.
Payoff: a small animated composition (drifting circles over a colored ground) the reader tunes live with knobs.
Figures: the coordinate-system diagram; a first-shapes contact sheet; the payoff at a fixed frame.
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
Figures: uniform-vs-Gaussian scatter diagram; a seed contact sheet (same sketch, nine seeds); the payoff.
Draws from: `Docs/Generators/Random.md`; `Examples/Randomness/`, `Examples/Recreations/`.

**5. Noise.**
Teaches: noise as "random that remembers"; 1D noise driving a value over time; 2D noise as terrain/texture; the third dimension as drift; `signedNoise`; layering two noise scales by hand for detail; noise vs random side by side.
Assumes: Ch 4.
Payoff: a drifting organic field piece.
Figures: random-vs-noise line comparison; a 2D noise field visualized; a zoom/scale diagram; the payoff.
Draws from: `Docs/Generators/Noise.md`; `Examples/Randomness/NoiseField` and friends.

**6. Grids and repetition.**
Teaches: the `Grid` helper (points, cells, one loop instead of two); margins with `Insets`; transforms (`translate`/`rotate`/`scale`) and `withState`; symmetry by repetition; Truchet tiles and why identical parts join into larger figures.
Assumes: Ch 1 to 5 (noise/random vary the repetition).
Payoff: an endlessly varied tiling piece.
Figures: grid anatomy diagram (padding, gutter, cell vs point); a transform-stack diagram; Truchet connectivity diagram; the payoff.
Draws from: `Docs/Drawing/Geometry.md` (Grid), `Docs/Drawing/Truchet.md`; `Examples/Patterns/`.

**7. Words and pictures.**
Teaches: `drawText` and the three font kinds at a glance; text as geometry (`textToShapes`) and warping it; `loadImage`/`drawImage`; reading pixels (`Image[x, y]`) to drive drawing; `tint`.
Assumes: Ch 1 to 6.
Payoff: a typographic poster or an image-driven pointillist piece.
Figures: font-kinds contact sheet; a text-warp step sequence; an image-sampling diagram (photo → grid of marks); the payoff.
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
Figures: steering-move diagram; wander/arrive diagrams; one diagram per boid rule; rule-combination sequence; a growth time-lapse strip; the payoff.
Draws from: `Docs/Generators/Steering.md`, `Docs/Generators/Boids.md`, `Docs/Generators/DifferentialGrowth.md`; `Examples/Motion/Steering`, `Examples/Patterns/Flocking`, `Examples/Patterns/DifferentialGrowth`.

**11. Growing things.**
Teaches: recursion by drawing (a fractal tree written by hand first); rewriting rules (L-systems) and the turtle, grown iteration by iteration; branching with the stack; stochastic rules; space colonization (growth that claims space: veins and trees from attraction points, the pipe model for weight); diffusion-limited aggregation (growth by chance: frost from frozen walkers); Wave Function Collapse as "every neighbor must agree", watched as it solves.
Assumes: Ch 4 (seeds), Ch 6 (grids, for WFC), Ch 10 (stateful steppers).
Payoff: a procedural garden.
Figures: branch-stack diagram; L-system expansion table + drawing per iteration; a space-colonization growth sequence; a DLA cluster; WFC solve sequence; the garden.
Draws from: `Docs/Generators/LSystem.md`, `Docs/Generators/SpaceColonization.md`, `Docs/Generators/DiffusionLimitedAggregation.md`, `Docs/Generators/WaveFunctionCollapse.md`; `Examples/Patterns/LSystem`, `Examples/Patterns/Venation`, `Examples/Patterns/Dendrite`, `Examples/Patterns/WaveFunctionCollapse`.

**12. Fields and flow.**
Teaches: a field as "an answer at every point" (the mental model that later pays off in shaders and SDFs); visualizing a field with arrows; `FlowField` from noise; tracing streamlines; evenly-spaced streamlines; advecting particles; strange attractors as found motion.
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
Teaches: state that lives on the GPU; Game of Life (rules → life); reaction-diffusion (two chemicals, endless pattern) with the feed/kill map explored by knobs; fluid; seeding and forcing a sim by drawing into it; recoloring sim state through filters; GPU particles at a million (the sandpainting look, with accumulation from Ch 14).
Assumes: Ch 14 (Ch 15 helps but isn't required; kernels are presented as recipes).
Payoff: a reaction-diffusion organism piece, seeded by the reader's drawing.
Figures: GoL rules diagram; feed/kill parameter map; sim-seeding sequence; particle-count scaling strip; the organism.
Draws from: `Docs/Shaders/Compute.md`, `Docs/Drawing/Effects.md` (sim fields); `Examples/Simulation/`, `Examples/Compute/`.

### Part IV: The third dimension

**17. 3D, gently.**
Teaches: the camera as an orbiting eye (`cameraShowcase`, drag to look); depth; solid primitives; the 3D transform stack; lights and materials by playing (presets, then individual lights); matcap as "shading from a picture"; loading a mesh; casting shadows; the scene-inspection views.
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

**A. Just enough Swift.** The guide's Swift, gathered: values and types, functions and labels, classes vs structs, closures, optionals as encountered, property wrappers as used by `@Param`/`@Eased`. Builds on `Docs/Swift.md` rather than duplicating it: the appendix is the pedagogical pass, the primer stays the quick reference. Written after several chapters exist so it matches what the guide actually uses.

**B. Just enough math, visually.** One page per idea, each with an Ollin-rendered picture: coordinates, angles and radians, sine/cosine as a circle, vectors, interpolation and the shaping functions, distance, randomness distributions, fields, matrices as "move/turn/scale" (no algebra). Every chapter that introduces a math idea adds its entry here in the same session (the running list lives at the top of the appendix file as comments until assembled).

**C. Coming from p5.js and Processing.** The translation table (`circle()` → `drawCircle`, `createCanvas` → `canvasSize`, `push`/`pop` → `withState { }`, `random` seeds, `noise`, classes, the loop), what's the same, what's idiomatically different, and the habits worth dropping. This is also the roadmap's migration-guide item; writing this appendix completes it.

**D. The complete toolbox.** The 100%-coverage surface, generated from the matrix below: every capability, one plain-words line, where the Guide teaches it (if it does), and its Docs page. Doubles as the guide's index of the framework.

## Feature-coverage matrix

The guarantee that the Guide gives awareness of everything Ollin ships. One row per capability (keyed by Docs page, plus rows for capabilities without their own page). Depth: **taught** (a chapter section explains it), **shown** (appears in a worked example with a sentence or two), **pointed** (named with a one-liner and a Docs link, at minimum in Appendix D). Rules: no row may be unassigned; every Docs page must be reachable from at least one chapter's "Go deeper" list; when a new feature ships in the framework, it gets a row here (see the ship checklist note in `CLAUDE.md`).

| Capability (Docs page) | Guide home | Depth |
|---|---|---|
| `Core/Sketch.md` (lifecycle, time, loop) | Ch 1 | taught |
| `Core/Canvas.md` (canvasSize, windowMode) | Ch 1 | taught |
| `Swift.md` (language primer) | Ch 1 callouts, Appendix A | taught |
| `Drawing/Drawing.md` (shapes, state, transforms) | Ch 1, Ch 6 | taught |
| `Drawing/Color.md` (Color, OKLab, palettes, colormaps) | Ch 2 | taught |
| Gradient paint (`Drawing/Color.md`) | Ch 2 | taught |
| `Helpers/Math.md` (map, lerp, dist; the shaping scalars clamp/fract/step/smoothstep) | Ch 3, Appendix B | taught |
| `Helpers/Animation.md` (easing, @Eased, @Smoothed, Timeline; loopProgress/pingPong) | Ch 3 | taught |
| `Helpers/Input.md` (mouse, keyboard) | Ch 1 | taught |
| `Helpers/Parameters.md` (@Param) | Ch 1; bindings in Ch 20 | taught (typed family: sliders/stepper/color well taught in Ch 1's payoff, the rest named + pointed; groups/icons pointed) |
| `Generators/Random.md` | Ch 4 | taught |
| `Generators/Noise.md` (noise, signedNoise, loop:, fbm, curlNoise) | Ch 5; curl in Ch 12/16 | taught |
| `Drawing/Geometry.md`: `Grid`, `Insets` | Ch 6 | taught |
| `Drawing/Truchet.md` | Ch 6 | taught |
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
| `Generators/Packing.md` (circles) | Ch 13 | taught |
| `Generators/ShapePacking.md` | Ch 13 | shown |
| Hatching (`Output/Export.md`) | Ch 13 | taught |
| `Drawing/Effects.md` (targets, filters, compose, combine) | Ch 14 | taught |
| Blend modes (`Drawing/Drawing.md`) | Ch 14 | taught |
| Feedback (`Drawing/Effects.md`) | Ch 14 | taught |
| `Drawing/Accumulation.md` (noClear) | Ch 14; used in Ch 16 | taught |
| `Drawing/HDR.md` (toneMap) | Ch 14 | taught |
| Design patterns + design filters (`Drawing/Effects.md`) | Ch 14 | shown |
| Depth-of-field `.defocus`, SSAO, SSR (`Drawing/Effects.md`) | Ch 17 | pointed |
| `Shaders/Shaders.md` (user shaders) | Ch 15 | taught |
| `Shaders/Visuals.md` (Visual chains) | Ch 15 | taught |
| `Shaders/ShaderLibrary.md` (helper reference) | Ch 15 | pointed |
| `Shaders/Compute.md` (kernels, Particles, Simulation) | Ch 16 | taught |
| Sim fields: Game of Life, Gray-Scott, fluid (`Drawing/Effects.md`) | Ch 16 | taught |
| `3D/3D.md` (camera, primitives, meshes, lights, materials) | Ch 17 | taught |
| `3D/Camera.md` (cameraControl, moves, showcase, views) | Ch 17 | taught |
| `3D/Combining.md` (what stacks with what) | Ch 17/18 | pointed |
| Matcap (`3D/3D.md`) | Ch 17 | shown |
| PBR materials + IBL environments + procedural sky (`3D/3D.md`) | Ch 18 | shown |
| Shadows: 2D map, PCSS, ray-traced point (`3D/3D.md`) | Ch 17 | shown |
| Ray-traced reflections (`3D/3D.md`) | Ch 18 | pointed |
| Wireframe, textured meshes, mesh loading (`3D/3D.md`) | Ch 17 | shown |
| Point clouds (`3D/3D.md`) | Ch 19 | taught |
| `Drawing/Combinators.md` (SDF 2D + SDF3D raymarching) | Ch 18 | taught |
| `3D/DepthCompositing.md` | Ch 19 | shown |
| `3D/RGBD.md` | Ch 19 | taught |
| `3D/Record3D.md` | Ch 19 | taught |
| `3D/Phone.md` (capture app streams, world fusion) | Ch 19 | taught |
| `Helpers/Audio.md` (analysis, beats, sources) | Ch 20 | taught |
| `Integration/MIDI.md` | Ch 20 | taught |
| `Integration/OSC.md` | Ch 20 | taught |
| `Vision/Vision.md` (16 trackers, ModelTracker) | Ch 21 | taught/pointed by tracker |
| `Video/Video.md` (playback as texture) | Ch 21 | taught |
| `Integration/Syphon.md` | Ch 22 | taught |
| `Integration/VirtualCamera.md` | Ch 22 | shown |
| `Output/Export.md` (PNG, sequence, video, GIF, SVG) | Ch 3 (GIF), Ch 13 (SVG), Ch 22 (all) | taught |
| `Tools/LiveCoding.md` (OllinLiveCoding) | Ch 22; OllinLive workflow in Ch 1 | taught |
| Examples gallery (`swift run OllinExamples`) | Ch 1 | shown |
| Extension seam (`Sketch.extend`, `SketchExtension`) | Appendix D | pointed |
| Headless capture (`OllinApp.image(of:)`) | Ch 22; used by the Guide's own figure runner | shown |

## Roadmap parking lot

Where each open `ROADMAP.md` item will live in the Guide once it ships in the framework. Guide prose is written only for shipped features; this table reserves the seat. When writing a chapter, check whether any of its parked items shipped since this table was made.

| Roadmap item | Future Guide home |
|---|---|
| Normalized u,v coordinates | Ch 1 |
| PDF export | Ch 22 |
| Palette file import | Ch 2 |
| Stroke as shape | Ch 13 |
| Single-file sketches | Ch 1 (would simplify the setup story; revisit Ch 1 when it ships) |
| Retained geometry buffers | internal; Appendix D note at most |
| More SDF shapes | Ch 18 / Appendix D |
| More model examples (ModelTracker) | Ch 21 |
| SVG import | Ch 13 |
| Clipping as drawing state | Ch 6 or 14 |
| Perfect-loop export (`--export-loop`) | Ch 3 |
| Reproducibility metadata in exports | Ch 4 + Ch 22 |
| Kaleidoscope symmetry | Ch 6 |
| Small filter-catalog additions | Ch 14 |
| Shape morphing | Ch 3 or 13 |
| SDF sculpting (richer combinators) | Ch 18 |
| Generative-geometry refinements | Ch 11 |
| Technique catalog: fractals | Ch 11 (may grow into its own chapter) |
| Technique catalog: GPU-scale agents, ALife, Lenia | Ch 16 |
| Technique catalog: growth/morphogenesis (Turing patterns, sandpile, growth on meshes) | Ch 16/17 |
| Technique catalog: waves, terrain | Ch 16/17 |
| Technique catalog: IK, pendulums, n-body | Ch 9 |
| Technique catalog: classic curves, space-filling | Ch 3/6/13 |
| Technique catalog: tiling/layout families | Ch 6 |
| Technique catalog: meshing (marching cubes, metaballs) | Ch 17 |
| Technique catalog: computational geometry | Ch 13 |
| Technique catalog: image-as-input family | Ch 7 |
| Technique catalog: painterly marks | Ch 13 |
| Technique catalog: noise toolkit | Ch 5 |
| Technique catalog: pattern fields | Ch 15 |
| Expressive brushes and strokes | Ch 13 |
| Project generator | Ch 1 |
| Variation galleries / seed exploration | Ch 4 + Ch 22 |
| iPhone sensor array (scene mesh, drift correction) | Ch 19 |
| 3D: loadScene, live camera environment, 3D rigid bodies | Ch 17 (bodies also Ch 9) |
| Photorealistic 3D tier | Ch 17/18, likely a new chapter when substantial |
| Sound synthesis, spatial audio, algorithmic composition | Ch 20, likely splitting into its own chapter |
| Tempo sync | Ch 20 |
| Live rigs (serial/BLE, DMX/LED, NDI) | Ch 22, or a future installations chapter |
| New input sources | Ch 20/21 |
| New output surfaces (haptics, screensaver, USDZ, fabrication, riso separations, performance capture) | Ch 22 |
| Rendering/color frontier (P3/HDR out, GPU-driven, path tracing) | Ch 14/22 |
| Authoring/editor tooling | Ch 22 |
| Collaboration and multi-device | future chapter beside Ch 22 |
| Installation mode | future installations chapter |
| Learning (user guide, migration guide, tutorials) | this Guide itself; migration guide = Appendix C |
| Extension ecosystem (ollinx-*) | a future "Extending Ollin" appendix |
| Profiling and GPU debugging | Appendix D note, future appendix |
| Accessibility and inclusive text | Ch 2 (palettes), Ch 22 |
| Swift Playgrounds / iOS, visionOS, AR | a future part or appendix, when the platforms land |
