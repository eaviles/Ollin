# Ollin roadmap

Ollin is a creative-coding framework for Swift and Metal on Apple platforms, aiming for p5.js ergonomics on an OPENRNDR-grade core. This file is the running list of what's planned and what's being explored. If you'd like to help, it's a good place to start.

For how the framework works and the conventions behind it, see the guides in [`Docs/`](Docs/). For working code, browse [`Examples/`](Examples/).

## How to contribute

A few things worth knowing before you pick something up:

- Building and running needs macOS 26+ and a Metal-capable GPU. There's no way around the Swift toolchain and Metal, so changes are verified on a Mac.
- New drawing features are built on the typed core first (the `Drawer` and the value types), then given the bare p5-style call as sugar. Anything the bare API can do, the core should be able to do too, with more control.
- A feature isn't considered done until it has an example. Examples live in [`Examples/`](Examples/), one idea per sketch, and they're compile-tested in CI so they don't rot. Writing the example is also how the API gets a sanity check: if it's awkward to write, the API probably needs work.
- The items under [Up next](#up-next) are the most self-contained, so they tend to make the best first contributions.
- A rough priority sits under sections where it helps: **Near-term** marks well-scoped, good next pickups; **Later** marks bigger items that lean on earlier work. Untagged sections are substantial and wanted, just not the very next thing. Genuinely speculative ideas live under [Further out / exploratory](#further-out--exploratory); the platform-gated legs under [On the horizon](#on-the-horizon).

If you're coming from p5.js or JavaScript, [`Docs/Swift.md`](Docs/Swift.md) covers just enough Swift to get productive.

## Up next

Near-term, fairly self-contained pieces, each small and well-scoped.

- **Normalized `u, v` coordinates.** A 0…1 coordinate space across the canvas alongside points, so a sketch can place things without referring to `width`/`height`.
- **PDF export beside SVG.** The vector serializer already records every draw call as geometry; Core Graphics can write the same geometry to PDF for print.
- **Palette file import.** Load a `Palette` from a file — plain hex-per-line text first, Adobe `.ase` swatches as the stretch — so anyone can pull palettes they've collected (a COLOURlovers favorite, a Lospec export, design-tool swatches) into a sketch locally. This is the "ship the loader, not the data" rule the bitmap-font `.fnt` loader set: bundled palette *data* stays license-gated (ColorBrewer-style, verifiably permissive only), while the loader makes any palette a file away. The loading surface mirrors the font and image loaders (`path`/`data`/`resource:in:`, with the same caller-bundle gotcha).
- **Stroke as shape.** Offsetting an *open* path turns a stroked polyline into a closed outline region — a thick stroke that exports as a filled SVG region, hatches for the plotter, or feeds the shape booleans. The offsetting engine already does this for closed regions; the work is the open-path surface (end caps, and where the API lives).
- **Single-file sketches.** A zero-ceremony way to run one `.swift` file as a sketch, in the spirit of `swift-sh`, so dashing off an idea doesn't require setting up a package.
- **Retained geometry buffers.** Every frame currently re-uploads everything; keeping static geometry (a large point cloud, a fixed background) in a persistent buffer would drop its per-frame cost to zero.
- **More SDF shapes, when a good fit appears.** Any canonical form parameterized by a size and a ratio or two drops into the instanced-SDF path as four small touch-points (a shape tag, a builder, a distance function, and a fragment case).
- **More model examples over `ModelTracker`.** The custom-model tracker runs anything converted to Core ML; a well-known model can make a strong example, with the weights always fetched by `Scripts/fetch-models.sh` rather than committed. Candidates, licenses, and the surfaces involved are in the [design notes](DESIGN-NOTES.md#model-examples-and-modeltracker-surfaces-not-started).
- **Unify the shader preludes.** GPU compute kernels and fragment shaders each get a helper set spliced in for free, but they're two different sets that overlap and disagree on names (the same hash is `hash21` for a kernel and `hash12` for a shader). Fold them into one shared library with consistent names, so a helper learned in one works the same in the other. See the [design notes](DESIGN-NOTES.md#unify-the-shader-preludes-not-started).
- **Shader errors at the source file.** A user shader's compile error reports a line relative to the shader string (`Shader:8`), not the `.swift` or `.metal` file it lives in, so it's hard to locate in a big sketch and an IDE can't jump to it. Capture the source location at construction (`#filePath`/`#line`) and emit it in the spliced `#line` directive, so errors read as a clickable `file:line`. See the [design notes](DESIGN-NOTES.md#shader-errors-at-the-source-file-not-started).

## Shader composition and live-coding

Two linked directions. First, a composable API for chaining and mixing shader-driven visuals fluently (in the spirit of Hydra's `osc().rotate().modulate(noise())`). Second, a separate **live-coding performance app** (working title `OllinLiveCoding`) built on top of the framework, a host app in the same tier as `OllinLive` and `OllinExamples`: you write and evaluate sketch code live with the code shown to the audience (the Hydra model, where the writing is the show). Its target is live-coding **the Ollin sketch in Swift**, not only shader expressions, built on the shipped dylib hot-reload engine. Both are distinct from `OllinLive`, which is file-watch dev hot-reload, not a performance tool. A third strand is **broadening the 3D SDF combinators**: the sphere-traced field merging (`drawSDF3D`) growing toward the full ShaderPark "sculpting" experience. See the [design notes](DESIGN-NOTES.md#shader-composition-and-live-coding-not-started).

## Generative geometry

**Near-term.** A tier of classic generative-art building blocks that emit vector geometry (points, `Contour`s, `Shape`s) feeding the existing draw, shape-boolean, hatching, and SVG paths rather than the renderer: **circle and shape packing** (grow-to-touch and front relaxation), **L-systems** (grammar-driven recursive structure), **differential growth** (organic line and curve accretion), **blue-noise and Poisson-disk sampling** (even-but-organic point distributions), **Wave Function Collapse** (constraint-solved tile layouts), and **Truchet tiling** (rotated tile sets that read as flowing pattern). They share the plotter-friendly, geometry-first shape the shape booleans set, all driven by the existing seedable `random`/`noise` so a run is reproducible, and each ships with an example, and several are the natural implementation behind a [recreation](DESIGN-NOTES.md#examples-folder-maintained-ongoing) of the artist who pioneered them. See the [design notes](DESIGN-NOTES.md#generative-geometry-not-started).

## Technique and algorithm helpers

**Near-term.** A standing, growing catalog of classic creative-coding techniques and algorithms as first-class helpers, the way the SDF shapes, the effect `Filter`s, and the [generative-geometry](#generative-geometry) builders are catalogs that keep growing. Each one lands wherever it fits the existing core (a geometry emitter beside the shape builders, a GPU `Generator` or shader for an escape-time or field technique, a simulation beside the compute and `SimField` paths), ships with an example, runs off the seedable `random`/`noise` so a result reproduces, and is implemented from the published technique (credited in the README's Techniques list). Many map onto the *Nature of Code* canon (vectors, forces, particles, autonomous agents, cellular automata, fractals, evolution), so the catalog doubles as a familiar on-ramp from that world, and the geometry-emitting recipes are flagged plotter-friendly for the pen-plotter path. The families worth working through, none considered yet:

- **Strange attractors and chaotic maps.** Lorenz, Rössler, Aizawa, Clifford, Peter de Jong, and friends: iterate the map or integrate the system and plot the orbit, in 2D and 3D, as a point cloud, a density field, or a traced polyline. The logistic and Hénon maps and the bifurcation diagram sit here too.
- **Fractals.** Escape-time sets (Mandelbrot, Julia) as a GPU `Generator`; iterated function systems and fractal flames; diffusion-limited aggregation (dendritic growth).
- **Agents, steering, and flow fields.** Steering behaviors (seek, flee, arrive, wander, path-following, flow-following) and flocking (Reynolds, the *Nature of Code* canon), and first-class **flow fields** (build a field from noise or a function, trace streamlines, advect particles and strokes through it, the Fidenza look). Plus physarum slime-mold agents, a general cellular-automata helper (Wolfram and totalistic rules beyond the shipped Game of Life), and **genetic / evolutionary** form-finding, all on the compute path the particle and `SimField` systems already use.
- **Particle-interaction and artificial life.** Simple per-particle rules that produce lifelike emergence on the GPU: **Particle Life** (a few particle types with an attraction/repulsion matrix, Ventrella's *Clusters*), **Primordial Particle Systems**, **GPU soft-bodies** (particles joined by spring bonds), and **SPH** particle fluids, all sharing a **GPU spatial-hash neighbor search** as the enabler. Pushed toward self-replication, mutation, and selection, this is the open-ended-evolution territory the ALIEN environment (chrxh/alien) explores, studied as *techniques* and reimplemented in Metal compute (inspiration, not a port, credited in the README's Influences).
- **Classic curves and distributions.** Phyllotaxis (the golden-angle spiral), Lissajous and rose curves, spirograph (hypotrochoids and epicycloids), and the space-filling curves (Hilbert, Peano, Gosper, dragon) that are a gift for the plotter. Low-discrepancy sampling (Halton, Sobol) and weighted-Voronoi stippling for even, organic point sets, and Chaikin corner-cutting to smooth a polyline into a flowing curve.
- **Tiling and layout.** Hexagonal and triangular grids (extending the shipped `Grid`), recursive subdivision (quadtree / BSP, the Mondrian look), the Apollonian gasket, and aperiodic tilings (Penrose, Wang, Islamic / girih star patterns), beside the Wave Function Collapse and Truchet builders in [generative geometry](#generative-geometry).
- **Meshing and surfaces.** Marching cubes (turn a scalar field, metaballs, or a point cloud into a mesh), metaballs and implicit surfaces, and subdivision-surface smoothing (Catmull-Clark / Loop); these route to [3D mode](#3d-mode).
- **Image as input.** Turn a source image into generative output: pixel sorting, image-to-stipple and image-to-single-line (TSP) renderings, k-means palette extraction, and the dithering family (Floyd-Steinberg, ordered / Bayer, blue-noise), over the pixel access the `Image` type already exposes.
- **Noise toolkit.** Round out the shipped value and curl noise: domain warping (the iq marble and cloud basis), Worley / cellular noise, simplex / OpenSimplex, and ridged / turbulence fbm.
- **Plotter line art.** TSP and minimum-spanning-tree single-line renderings of an image, and contour extraction via marching squares (already used internally for SDF outlines, worth surfacing).

See the [design notes](DESIGN-NOTES.md#technique-and-algorithm-helpers-not-started).

## Project generator

An openFrameworks-style generator that scaffolds a ready-to-run sketch folder from a few questions (which capabilities, which canvas size), instead of hand-copying boilerplate. Beyond a blank scaffold, it could also emit a sketch *from an existing artifact*: a 3D scene file (glTF/USD) as placed `drawMesh`/`camera`/light calls, or a Shadertoy URL/GLSL shader translated into an Ollin sketch plus shader code. See the [design notes](DESIGN-NOTES.md#project-generator--sketch-scaffolding-not-started).

## Variation galleries and seed exploration

**Near-term.** Ollin sketches are already reproducible (`seed()` makes a run deterministic) and tunable (`@Param`); the missing piece is *exploring the seed space* the way Art Blocks-style generators do. Navigate a sketch's variations (step through seeds, jump to one, randomize) and export a contact sheet of many seeds as a single image (the fixed-timestep frame driver behind `OllinApp.image(of:)` already renders any frame off-screen). Distinct from the [project generator](#project-generator), which scaffolds a *new* sketch; this explores the variation space of an existing one. See the [design notes](DESIGN-NOTES.md#variation-galleries-and-seed-exploration-not-started).

## iPhone as a sensor array

A Mac has no depth camera, inertial sensors, or spare Neural Engine for live perception; a tethered iPhone has all three. The idea: let the phone act as a sensor and on-device ML co-processor for a sketch that still renders on the Mac, capturing and perceiving (LiDAR point clouds, face and body tracking, segmentation, device motion, and more) and streaming typed results the sketch reads in `draw()`. Both a recorded RGBD clip and a tethered phone's live USB RGBD stream already reconstruct on the Mac as point clouds (see [`Docs/3D/Record3D.md`](Docs/3D/Record3D.md)), the kind of world-facing depth feed an Intel RealSense once gave openFrameworks, and a sweep of the phone's depth frames fuses by camera pose into one world cloud (see [`Docs/3D/Phone.md`](Docs/3D/Phone.md)). The work ahead grows that stream into the rest of the phone's senses — scene mesh, richer face and body data — over Ollin's own iPhone capture app, and drift-corrects a long sweep so its fused cloud stays registered. The wire protocol, the sensor catalog, and the build order are in the [design notes](DESIGN-NOTES.md#iphone-as-a-sensor-array-partly-shipped).

## 3D mode

2D stays the default, and 3D keeps building out on top of the shipped camera, depth buffer, transform stack, solid primitives, meshes loaded from file (with their own base-color material and texture), textured meshes, the directional/point/spot light & material model, curated lighting presets, the stylized material library (iridescent, velvet, jade, toon, gooch, …), the physically-based metallic-roughness material, image-based lighting from bundled, downloaded, or loaded HDRI environments (with a skybox backdrop), matcap materials (view-normal sphere-texture shading), and directional, spot, and point cast shadows:

- **Scene import (`loadScene` beside `loadMesh`).** A loaded model collapses to one merged `Mesh` today, which is right when a sketch just wants the geometry to place itself. The complement preserves a file's *structure*: glTF and USD are scene formats (a node hierarchy with per-node transforms, plus cameras and lights), so `loadScene` would return a `Scene` of named nodes a sketch draws in place (`scene.draw()`), reaches individually to animate (`scene.node("lamp")`), and opens on the camera and lights the scene was authored with, handing back the same `Camera3D` and `Light` types the rest of 3D mode uses. It makes "compose a draft scene in a design tool, then bring it into a sketch" a first-class workflow, aligning with the glTF 2.0 standard every tool exports (Spline, Blender, three.js). A one-way *scene-to-source* variant (emitting an editable sketch instead of a live asset) belongs with the [project generator](#project-generator).
- **A live camera environment.** Image-based lighting bakes from a fixed texture; a *live* environment would re-bake (throttled) from a `FrameSource` so 3D objects reflect the real world, AR-style: `environment(.feed(camera))` from the Mac webcam, or the iPhone camera over the `OllinPhone` link, the same way ARKit's environment probes light virtual objects with the surrounding scene. It connects image-based lighting to the vision and phone-capture stack already in place.

It's opt-in, so a 2D sketch never pays for a depth buffer or a perspective divide. The iPhone point cloud renders through it, and visionOS and AR build on it. See the [design notes](DESIGN-NOTES.md#3d-mode-partly-shipped).

## Photorealistic 3D

The high-end, well-curated realism tier, opt-in on the shipped PBR, IBL, ray-traced shadows and reflections, and SDF raymarching, so a 2D or stylized 3D sketch never pays. The techniques that separate a polished product render or film still from "CG," each Metal-native and written from the published technique (credited in the README's Techniques list):

- **Area lights and light shaping.** Rectangular, disk, and tube **area lights** (Linearly Transformed Cosines) for the soft, believable studio lighting a point light can't make, plus IES photometric profiles and light cookies / gobos for realistic falloff and textured light.
- **Real-time global illumination.** Indirect bounce light beyond the IBL ambient term: light probes / irradiance volumes, screen-space GI, or a dynamic-diffuse-GI scheme (DDGI). The single biggest "it looks real" lever after direct lighting.
- **Volumetrics and atmosphere.** Volumetric lighting (god rays / light shafts through participating media), height and distance fog, atmospheric / aerial-perspective scattering, and raymarched volumetric clouds over the procedural sky.
- **Advanced materials.** Glass and **transmission / refraction** (frosted, thin-film, the glTF `KHR_materials_transmission` / `_volume` set), **clearcoat** (car paint and lacquer's second specular lobe), real **subsurface scattering** (skin, wax, jade, beyond the stylized finish), **sheen** (fabric and velvet), and surface detail (parallax-occlusion and displacement, triplanar and detail maps, decals).
- **Image quality and motion.** **Temporal anti-aliasing** (and the temporal accumulation that also cleans SSAO / SSR / GI noise), **MetalFX** temporal upscaling for quality and headroom, **contact shadows** (short-range screen-space) to seat objects on surfaces, and per-object and camera **motion blur** via a velocity buffer for cinematic movement.

See the [design notes](DESIGN-NOTES.md#photorealistic-3d-not-started).

## Camera control and cinematic moves

**Near-term.** Two opt-in halves on the shipped 3D camera. The first is **interactive control at parity with `ofEasyCam` and p5's EasyCam**, with their ease of use as the bar: drag to orbit, scroll to dolly, modifier-drag to pan, damped so it feels good, mapped onto the existing `Camera3D.orbiting` pose so a sketch gets "look around the scene" in one call. The second is the part that's awkward to hand-roll and worth curating: **cinematic camera moves**, a small set of named, ready-to-use motions a sketch picks instead of keyframing by hand. A slow orbit, a push-in, a crane, an orbit-and-rise, a gentle handheld drift, each easing over a duration so the shot reads as composed. They ride a small reusable animation primitive (a value advanced over time by an easing curve) that also serves general property tweening and the eventual `@Param` keyframing. See the [design notes](DESIGN-NOTES.md#camera-control-and-cinematic-moves-not-started).

## Sound, synthesis, and spatial audio

The audio layer listens today (FFT, bands, beat detection) but can't make or place sound. Three additions turn it into an output channel: **synthesis** (oscillators with envelopes, filters, delay and reverb, a small patchable graph, so a sketch can voice itself), **spatial audio** (a drawn object emits sound from its position in the 3D scene, the camera as the listener), and **modal synthesis** (a shape rings at the frequencies its geometry implies, so form and timbre move together). On the note-generation side, an **algorithmic-composition** toolkit (Euclidean rhythms via Bjorklund's algorithm, scales and chords, Markov sequences, arpeggiators) turns the synthesis voices into generative music, locked to the [tempo sync](#tempo-sync) clock. **Sonification**, turning a data series or a field into sound, falls out of the same machinery. See the [design notes](DESIGN-NOTES.md#sound-synthesis-and-spatial-audio-not-started).

## Tempo sync

**Near-term.** Lock a sketch's motion to a live music setup, the way a VJ syncs visuals to a DJ. The clean first form rides the shipped MIDI transport: receive **MIDI clock** (plus start/stop/continue), derive tempo and beat phase, and expose `tempo` / `beat` / `phase` as values a sketch reads in `draw()` so animation falls on the beat, with the timeline primitive from [camera moves](#camera-control-and-cinematic-moves) able to run on musical time. The cross-app, cross-machine standard is **Ableton Link** (shared tempo and beat phase across apps and devices on a network); its own SDK is GPLv2 or a paid license, so it stays the inspiration-only tier (reimplement the protocol, never vendor it, the same posture as Hydra's AGPL). See the [design notes](DESIGN-NOTES.md#tempo-sync-not-started).

## New input sources

More of the platform's live signals, each a `FrameSource` or a simple value read in `draw()`:

- **Screen and window capture.** Any app's window or the whole screen as a live texture, processed like a video feed (the non-cooperative complement to Syphon, which needs the other app to publish).
- **Voice and sound events.** Speech recognition as drawable live captions, and sound-event classification (a clap, a genre, a bark) as a trigger, the audio analogue of the vision trackers.
- **Rich controllers.** Game controllers (gyro, triggers, touchpad), trackpad pressure, and, on the iOS leg, Apple Pencil tilt and azimuth.
- **Body and world data.** Heart rate from a paired Watch for biofeedback, and real-world ambient data (weather, location) as a slow live input.

Several overlap the [iPhone sensor array](#iphone-as-a-sensor-array); these are the Mac-side direct sources. See the [design notes](DESIGN-NOTES.md#new-input-sources-not-started).

## New output surfaces

Ways a sketch leaves the window:

- **Haptics.** A `draw()` that also emits a felt pattern synced to the visuals, on Force Touch trackpads and on the phone.
- **The OS as a canvas.** Wrap a sketch as a macOS screen saver, a dynamic wallpaper, a desktop widget, or a menu-bar piece, so the output lives in the system rather than a window.
- **Spatial export.** Export a 3D sketch as a USDZ (for AR Quick Look, sharing, and visionOS) or as spatial video, so the artifact stays three-dimensional instead of flattening to a frame.

See the [design notes](DESIGN-NOTES.md#new-output-surfaces-not-started).

## Rendering and color frontier

Deeper use of the Metal core and Apple displays, all opt-in so the 2D path stays untaxed:

- **Wide-gamut and HDR.** Composite and present through Display P3 (and Rec. 2020) end to end, and export true HDR video (HDR10 / Dolby Vision) from the float pipeline that already exists, for richer color than an 8-bit sRGB target can hold.
- **GPU-driven rendering.** Indirect command buffers and mesh shaders to scale past instancing: many more distinct, GPU-encoded or GPU-generated objects with the CPU out of the per-object loop.
- **Film-quality export.** An offline path-traced render path a sketch can switch to for gallery-grade stills and sequences, from the same scene tuned live (an extension of the ray-tracing direction noted under [3D mode](#3d-mode)).

See the [design notes](DESIGN-NOTES.md#rendering-and-color-frontier-not-started). (The most speculative items here, spectral rendering, AI frame interpolation, and optical-flow self-warp, sit under [Further out / exploratory](#further-out--exploratory).)

## Authoring and editor tooling

**Later.** Editing experiences the live-reload core makes possible, and where Ollin draws its line on AI. The public stance already holds (the README's "It's a tool for making art ... Ollin is not a generative-art model"), and it extends to any AI *feature*: **AI is a tool for operating the framework, never an author of sketches.** Helping wire a generator, suggest a filter, or move knobs toward a look is in scope; generating a whole sketch or its imagery from a prompt is deliberately out. Within that line:

- **A visual node editor** over the effect, SDF-combinator, and shader graphs, living in the live host and round-tripping to Swift source.
- **Direct manipulation.** Drag a shape in the running window and have the edit written back into the source, the way a SwiftUI preview manipulates a layout.
- **Record and replay.** Capture a run's input and parameter timeline and scrub it backward, a rewind for generative work.
- **AI at the controls.** Drive the knobs, wire and parameterize generators, and tune toward a described look, all as operations on the typed `@Param` and effect graph, with the artist composing the sketch.
- **On-device ML as a material.** Apple-silicon models a sketch invokes deliberately, like a noise function: semantic parameter control, neural style as a `Filter`, segmentation-driven generators. Image generation from a text prompt is the one to weigh most carefully against the stance above; if it ships, it is an optional material the artist composes with, never the framework making the piece.

See the [design notes](DESIGN-NOTES.md#authoring-and-editor-tooling-not-started).

## Collaboration and multi-device

Apple-native, low-ceremony ways several machines share one piece: **Multipeer** local networking so several Macs and iPhones form one canvas with no server, the **iPhone as a 6DoF wand** (extending the sensor stream the phone already sends). (A more speculative **SharePlay** co-creation idea sits under [Further out / exploratory](#further-out--exploratory).) See the [design notes](DESIGN-NOTES.md#collaboration-and-multi-device-not-started).

## Installation mode

The concerns of a piece that runs unattended for days in a gallery rather than for a session at a desk: checkpoint and restore of generative state, restart on failure, scheduled evolution, and graceful handling of display sleep and wake. A documented, supported way to run long rather than a hope. See the [design notes](DESIGN-NOTES.md#installation-mode-not-started).

## Learning: a user guide and tutorials

**Near-term.** The reference docs ([`Docs/`](Docs/)) answer "what does this function do"; what's missing is the narrative layer that answers "how do I think in Ollin" and "how do I build a piece," the way OPENRNDR ships a Guide beside its API reference and openFrameworks ships the ofBook and tutorials beside its documentation. Three pieces: a **narrative user guide** (concepts and workflows, read start to finish rather than looked up), a **"coming from p5.js" migration guide** (a side-by-side mapping for the audience: `circle()` to `drawCircle()`, `createCanvas` to `canvasSize`, `push()`/`pop()` to `withState { }`, what's the same and what's idiomatically different), and a **guided tutorial series** that builds a finished piece end to end. The shipped examples and the *Nature of Code* framing of the [technique catalog](#technique-and-algorithm-helpers) are the raw material. See the [design notes](DESIGN-NOTES.md#learning-a-user-guide-and-tutorials-not-started).

## A third-party extension ecosystem

**Near-term.** The framework grows past the core team only when other people can publish and find extensions, the contributed-addon ecosystems p5.js, openFrameworks (`ofx*`), and OPENRNDR (`orx-*`) all have. SwiftPM already makes the mechanics free (a package that depends on `Ollin`), so the work is *convention and discovery*: a naming convention (an `ollinx-*` prefix in the `ofx*` spirit), a documented set of stable extension points (the `SketchExtension` seam, custom `Filter` / `Generator` / `Sim` / `Shader` types, the `FrameSource` protocol, the satellite-package pattern), a starter template for a new extension, and a curated list so they are findable. Deciding the conventions early keeps the ecosystem consistent. See the [design notes](DESIGN-NOTES.md#a-third-party-extension-ecosystem-not-started).

## Performance profiling and GPU debugging

Ollin sits on a GPU core and pitches the rendering ceiling, but it doesn't yet help a sketch author see *their own* cost. The FPS and stats overlay is the seed; the gap is a real profiler: a per-frame breakdown (draw calls, vertices, tessellation, and SDF vs triangle vs fringe batches), an honest CPU-versus-GPU frame-time split so the CPU-tessellation cost is visible when it bites, and a hook into Metal's frame capture for the deep cases. A framework that's fast should make it easy to find out why a particular sketch isn't. See the [design notes](DESIGN-NOTES.md#performance-profiling-and-gpu-debugging-not-started).

## Accessibility and inclusive text

Making Ollin and the work people make with it more inclusive, on the platform's native support. For **authors**: colorblind-safe palette helpers and a color-vision *simulation* filter (preview a sketch as it reads under deuteranopia and friends), plus reduced-motion awareness for the motion-by-default model. For **viewers**: a describable-output path, the native counterpart to p5's `textOutput()`, so a generative piece can carry an accessible description. And **robust complex-script text**: verifying and surfacing Core Text's handling of CJK, right-to-left scripts, emoji, and combining marks, so the text system serves a global audience. See the [design notes](DESIGN-NOTES.md#accessibility-and-inclusive-text-not-started).

## Further out / exploratory

Lower-confidence ideas kept on record but deliberately not near-term: each is plausible on the platform, but speculative enough that it shouldn't crowd the planned work above. Distinct from [On the horizon](#on-the-horizon), which is the platform-gated later legs (iOS, visionOS, AR), not uncertainty.

- **Spectral rendering.** Composite in spectra rather than RGB, for physically-correct subtractive color mixing, thin-film iridescence, and diffraction. (Detail under [rendering and color frontier](DESIGN-NOTES.md#rendering-and-color-frontier-not-started).)
- **AI frame interpolation.** Render at a lower frame rate and ship smooth slow-motion via an on-device interpolation model.
- **Optical-flow self-warp.** Feed the sketch's own motion field, from the shipped Vision optical flow, back into its history for flow and glitch looks.
- **Text-to-image as a material.** On-device diffusion a sketch could invoke as an optional, labelled material. The one to weigh hardest against the AI boundary, since it sits closest to the contested use, so it lives here rather than in the planned [authoring tier](#authoring-and-editor-tooling); see the AI stance stated there.
- **SharePlay co-creation.** Two people tuning one sketch together over a FaceTime call (GroupActivities). The most speculative of the [collaboration](#collaboration-and-multi-device) ideas.

## On the horizon

Larger, later directions. 2D on macOS stays the focus; these don't change that.

- **Swift Playgrounds and iOS.** Swift Playgrounds App Projects are the closest Swift gets to the p5.js "open the editor and type, watch it move" experience, and the same work unlocks iPad sketching and embedding in any SwiftUI app. The view layer is already SwiftUI-embeddable; the main blocker is declaring an iOS target and making the view conditional across AppKit and UIKit. The Metal renderer is already portable. [Design notes.](DESIGN-NOTES.md#swift-playgrounds-and-ios-not-started)
- **visionOS.** Immersive rendering uses a different render loop (CompositorServices rather than `MTKView`), so the per-frame loop stays behind a seam that either a normal view or a visionOS layer renderer can drive. It builds on the [3D mode](#3d-mode) and the iOS target. [Design notes.](DESIGN-NOTES.md#3d-mode-partly-shipped)
- **AR mode and templates.** AR sketches on Apple platforms, with ready-made templates for face, world, and image tracking, so an AR sketch becomes "fill in the `draw()`, the tracking is handed to you". It's layered on the iOS and 3D work rather than a separate engine, and aims at the gap left by discontinued template-driven AR tools. [Design notes.](DESIGN-NOTES.md#ar-mode-and-templates-eventual-the-meta-spark-gap)

These three can't be verified in every environment; iOS, visionOS, and AR need the right SDKs, a simulator, or a device.
