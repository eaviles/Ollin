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

If you're coming from p5.js or Processing, [the Guide's Appendix C](Guide/C-ComingFromP5.md) maps the API you already know onto Ollin, and [`Docs/Swift.md`](Docs/Swift.md) covers just enough Swift to get productive.

## Up next

Near-term, fairly self-contained pieces, each small and well-scoped.

- **Normalized `u, v` coordinates.** A 0…1 coordinate space across the canvas alongside points, so a sketch can place things without referring to `width`/`height`.
- **PDF export beside SVG.** The vector serializer already records every draw call as geometry; Core Graphics can write the same geometry to PDF for print.
- **Palette file import.** Load a `Palette` from a file (plain hex-per-line text first, Adobe `.ase` swatches as the stretch) so anyone can pull palettes they've collected (a COLOURlovers favorite, a Lospec export, design-tool swatches) into a sketch locally. This is the "ship the loader, not the data" rule the bitmap-font `.fnt` loader set: bundled palette *data* stays license-gated (ColorBrewer-style, verifiably permissive only), while the loader makes any palette a file away. The loading surface mirrors the font and image loaders (`path`/`data`/`resource:in:`, with the same caller-bundle gotcha).
- **Single-file sketches.** A zero-ceremony way to run one `.swift` file as a sketch, in the spirit of `swift-sh`, so dashing off an idea doesn't require setting up a package.
- **Retained geometry buffers.** Every frame currently re-uploads everything; keeping static geometry (a large point cloud, a fixed background) in a persistent buffer would drop its per-frame cost to zero.
- **More SDF shapes, when a good fit appears.** Any canonical form parameterized by a size and a ratio or two drops into the instanced-SDF path as four small touch-points (a shape tag, a builder, a distance function, and a fragment case).
- **More model examples over `ModelTracker`.** The custom-model tracker runs anything converted to Core ML; a well-known model can make a strong example, with the weights always fetched by `Scripts/fetch-models.sh` rather than committed. Candidates, licenses, and the surfaces involved are in the [design notes](DESIGN-NOTES.md#model-examples-and-modeltracker-surfaces).
- **SVG import.** The import half of the vector story: `loadShape("file.svg")` reads vector artwork into `Shape`s and `Contour`s (paths, the basic shapes, groups and transforms first), feeding the shape booleans, hatching, and SVG re-export, and giving recreations that start from a traced form a way in. CPU-only work over the existing `Path`/`Shape` types, mapping SVG's fill rules onto `FillWinding`.
- **Clipping as drawing state.** `withClip(shape) { }` confines drawing to a region mid-frame, scoped like `withState { }`. Layer-level masking exists (`.masked(by:)`), but a stencil-based geometric clip is the cheaper, more direct tool for "keep this pattern inside that region", and it's a standard part of the drawing-state model elsewhere.
- **Perfect-loop export.** An `--export-loop` that renders exactly one period of a sketch's loop, so a seamless GIF or video doesn't depend on hand-matching `--seconds` to the loop length. A small addition to the export flag surface with outsized visibility.
- **Reproducibility metadata in exports.** Embed the seed, the `@Param` values, and the sketch's git hash in every export (PNG text chunks, SVG comments, video metadata), so an artifact carries the recipe to regenerate itself. Pairs with [variation galleries](#variation-galleries-and-seed-exploration): a contact sheet where every tile knows its seed.
- **Kaleidoscope symmetry.** N-fold rotational and mirror replication of ordinary draw calls (`symmetry(8)`, scoped like the rest of the drawing state), the mandala mode. The SDF combinators already fold their fields radially; this covers the rest of the drawing surface.
- **Shape morphing.** Tween one `Shape` into another: contour correspondence plus interpolation, extending `Tweenable` beyond scalars and vectors so a `Timeline` can animate geometry. Plotter-friendly, since every in-between frame is a real vector shape.

## Generative geometry

A tier of classic generative-art building blocks that emit vector geometry (points, `Contour`s, `Shape`s) feeding the existing draw, shape-boolean, hatching, and SVG paths rather than the renderer. They share the plotter-friendly, geometry-first shape the shape booleans set, all driven by the existing seedable `random`/`noise` so a run is reproducible, each ships with an example, and several are the natural implementation behind a [recreation](DESIGN-NOTES.md#examples-folder) of the artist who pioneered them. The refinements still ahead (parametric L-systems, Wave Function Collapse from an example image) are in the [design notes](DESIGN-NOTES.md#generative-geometry); the broader algorithm catalog is the [technique and algorithm helpers](#technique-and-algorithm-helpers) tier.

## Technique and algorithm helpers

**Near-term.** A standing, growing catalog of classic creative-coding techniques and algorithms as first-class helpers, the way the SDF shapes, the effect `Filter`s, and the [generative-geometry](#generative-geometry) builders are catalogs that keep growing. Each one lands wherever it fits the existing core (a geometry emitter beside the shape builders, a GPU `Generator` or shader for an escape-time or field technique, a simulation beside the compute and `SimField` paths), ships with an example, runs off the seedable `random`/`noise` so a result reproduces, and is implemented from the published technique (credited in `ATTRIBUTION.md`'s Techniques list). Many map onto the *Nature of Code* canon (vectors, forces, particles, autonomous agents, cellular automata, fractals, evolution), so the catalog doubles as a familiar on-ramp from that world, and the geometry-emitting recipes are flagged plotter-friendly for the pen-plotter path. The families worth working through, none considered yet:

- **Chaotic 1D maps and bifurcation.** The one-dimensional entry point to the attractor family: the logistic map and its bifurcation diagram (sweep the growth rate, plot the settling values), beside more chaotic systems and alternate renderings of an orbit (a density field, a traced polyline) as they're wanted.
- **Fractals.** Iterated function systems and fractal flames; circle-inversion fractals and Kleinian limit sets.
- **Agents and steering.** Scaling the steering behaviors onto the GPU compute path (a million seekers and wanderers). Plus physarum slime-mold agents, a general cellular-automata helper (Wolfram and totalistic rules beyond the existing Game of Life, Langton's ant and turmites, and continuous-state Lenia), and **genetic / evolutionary** form-finding, all on the compute path the particle and `SimField` systems already use.
- **Particle-interaction and artificial life.** Simple per-particle rules that produce lifelike emergence on the GPU: **Particle Life** (a few particle types with an attraction/repulsion matrix, Ventrella's *Clusters*), **Primordial Particle Systems**, **GPU soft-bodies** (particles joined by spring bonds), and **SPH** particle fluids, all sharing a **GPU spatial-hash neighbor search** as the enabler. Pushed toward self-replication, mutation, and selection, this is the open-ended-evolution territory the ALIEN environment (chrxh/alien) explores, studied as *techniques* and reimplemented in Metal compute (inspiration, not a port, credited in `ATTRIBUTION.md`).
- **Growth and morphogenesis.** Multi-scale Turing patterns, the Abelian sandpile, and the 3D forms of the 2D growth systems (differential growth and reaction-diffusion over a mesh surface, the coral genre) once the meshing work below is in.
- **Waves and terrain.** A 2D wave-equation ripple simulation, Chladni figures (closed-form standing-wave nodal patterns, a natural join to the audio analysis), and terrain: fbm / diamond-square heightfields with hydraulic and thermal erosion, emitting meshes for [3D mode](#3d-mode).
- **Articulated and chaotic motion.** Inverse-kinematics chains (FABRIK / CCD) for tentacles, limbs, and procedural creatures; the double pendulum and gravitational n-body (Barnes-Hut) beside the existing strange attractors; and critically damped spring motion as a first-class helper beside the existing easing and smoothing.
- **Classic curves and distributions.** Phyllotaxis (the golden-angle spiral), Lissajous and rose curves and the harmonograph (their damped sibling), spirograph (hypotrochoids and epicycloids), Fourier epicycles (rebuild any closed contour from rotating circles, a natural showcase for the SVG import), and the space-filling curves (Hilbert, Peano, Gosper, dragon) that are a gift for the plotter. Low-discrepancy sampling (Halton, Sobol) and weighted-Voronoi stippling for even, organic point sets, the random-walk family (Lévy flights, self-avoiding walks), and Chaikin corner-cutting to smooth a polyline into a flowing curve.
- **Tiling and layout.** Hexagonal and triangular grids (extending `Grid`), recursive subdivision (quadtree / BSP, the Mondrian look), the Apollonian gasket, aperiodic tilings (Penrose, Wang, Islamic / girih star patterns), maze generation (recursive backtracker, Kruskal's, Wilson's) with the 10 PRINT diagonal maze as its one-liner cousin, and force-directed graph layout, beside the Wave Function Collapse and Truchet builders in [generative geometry](#generative-geometry).
- **Meshing and surfaces.** Marching cubes (turn a scalar field, metaballs, or a point cloud into a mesh), metaballs and implicit surfaces, and subdivision-surface smoothing (Catmull-Clark / Loop); these route to [3D mode](#3d-mode).
- **Computational geometry.** Alpha shapes / concave hulls and the medial axis / straight skeleton, each feeding the shape booleans, hatching, and plotter paths.
- **Image as input.** Turn a source image into generative output: pixel sorting, image-to-stipple and image-to-single-line (TSP) renderings, k-means palette extraction, the dithering family (Floyd-Steinberg, ordered / Bayer, blue-noise), halftoning by dot-size modulation (the screening step the [print separations](#new-output-surfaces) reuse), ASCII / glyph-mosaic rendering over the glyph atlas, the luminance melt (an image's brightness steering a warped field while the field's displacement liquifies the image), and slit-scan time displacement over a video or camera frame history, over the pixel access the `Image` type already exposes.
- **Painterly marks.** Generative watercolor (recursive polygon deformation under layered translucency, the recipe the [brush tier](#expressive-brushes-and-strokes) deliberately leaves to this catalog) and mathematical paper marbling (closed-form drop and tine-line transforms, pure contour deformation, so it stays vector and plotter-clean).
- **Noise toolkit.** Round out the existing value and curl noise: domain warping (the iq marble and cloud basis), Worley / cellular noise, simplex / OpenSimplex, and ridged / turbulence fbm, surfaced both as shader-library functions and as `Generator` growth (a warp knob on `.noise`, a cellular source).
- **Plotter line art.** TSP and minimum-spanning-tree single-line renderings of an image, and contour extraction via marching squares (already used internally for SDF outlines, worth surfacing).

See the [design notes](DESIGN-NOTES.md#technique-and-algorithm-helpers).

## Expressive brushes and strokes

Every stroke today is a uniform-width line; the hand-drawn, mark-making axis is missing. The foundation is variable-width strokes on the stroke renderer (a width per vertex instead of per path), and the rest layers on top: tapered ends, pressure and velocity response (the payoff for the trackpad-pressure and Pencil inputs planned under [new input sources](#new-input-sources), which otherwise have nothing to drive), calligraphic nibs, and stamped or scattered brushes that repeat a shape or texture along the path. Painterly simulation (the generative-watercolor family) stays a [technique-catalog](#technique-and-algorithm-helpers) recipe rather than a brush-engine feature. See the [design notes](DESIGN-NOTES.md#expressive-brushes-and-strokes).

## Project generator

An openFrameworks-style generator that scaffolds a ready-to-run sketch folder from a few questions (which capabilities, which canvas size), instead of hand-copying boilerplate. Beyond a blank scaffold, it could also emit a sketch *from an existing artifact*: a 3D scene file (glTF/USD) as placed `drawMesh`/`camera`/light calls, or a Shadertoy URL/GLSL shader translated into an Ollin sketch plus shader code. See the [design notes](DESIGN-NOTES.md#project-generator--sketch-scaffolding).

## Variation galleries and seed exploration

**Near-term.** Ollin sketches are already reproducible (`seed()` makes a run deterministic) and tunable (`@Param`); the missing piece is *exploring the seed space* the way Art Blocks-style generators do. Navigate a sketch's variations (step through seeds, jump to one, randomize) and export a contact sheet of many seeds as a single image (the fixed-timestep frame driver behind `OllinApp.image(of:)` already renders any frame off-screen). Distinct from the [project generator](#project-generator), which scaffolds a *new* sketch; this explores the variation space of an existing one. See the [design notes](DESIGN-NOTES.md#variation-galleries-and-seed-exploration).

## iPhone as a sensor array

A Mac has no depth camera, inertial sensors, or spare Neural Engine for live perception; a tethered iPhone has all three. The idea: let the phone act as a sensor and on-device ML co-processor for a sketch that still renders on the Mac, capturing and perceiving (LiDAR point clouds, face and body tracking, segmentation, device motion, and more) and streaming typed results the sketch reads in `draw()`. Both a recorded RGBD clip and a tethered phone's live USB RGBD stream already reconstruct on the Mac as point clouds (see [`Docs/3D/Record3D.md`](Docs/3D/Record3D.md)), the kind of world-facing depth feed an Intel RealSense once gave openFrameworks, and a sweep of the phone's depth frames fuses by camera pose into one world cloud (see [`Docs/3D/Phone.md`](Docs/3D/Phone.md)). The work ahead grows that stream into the rest of the phone's senses (scene mesh, richer face and body data) over Ollin's own iPhone capture app, and drift-corrects a long sweep so its fused cloud stays registered. The wire protocol, the sensor catalog, and the build order are in the [design notes](DESIGN-NOTES.md#iphone-as-a-sensor-array).

## 3D mode

2D stays the default, and 3D keeps building out on top of the existing camera, depth buffer, transform stack, solid primitives, meshes loaded from file (with their own base-color material and texture), textured meshes, the directional/point/spot light & material model, curated lighting presets, the stylized material library (iridescent, velvet, jade, toon, gooch, …), the physically-based metallic-roughness material, image-based lighting from bundled, downloaded, or loaded HDRI environments (with a skybox backdrop), matcap materials (view-normal sphere-texture shading), and directional, spot, and point cast shadows:

- **Scene import (`loadScene` beside `loadMesh`).** A loaded model collapses to one merged `Mesh` today, which is right when a sketch just wants the geometry to place itself. The complement preserves a file's *structure*: glTF and USD are scene formats (a node hierarchy with per-node transforms, plus cameras and lights), so `loadScene` would return a `Scene` of named nodes a sketch draws in place (`scene.draw()`), reaches individually to animate (`scene.node("lamp")`), and opens on the camera and lights the scene was authored with, handing back the same `Camera3D` and `Light` types the rest of 3D mode uses. It makes "compose a draft scene in a design tool, then bring it into a sketch" a first-class workflow, aligning with the glTF 2.0 standard every tool exports (Spline, Blender, three.js). A one-way *scene-to-source* variant (emitting an editable sketch instead of a live asset) belongs with the [project generator](#project-generator).
- **A live camera environment.** Image-based lighting bakes from a fixed texture; a *live* environment would re-bake (throttled) from a `FrameSource` so 3D objects reflect the real world, AR-style: `environment(.feed(camera))` from the Mac webcam, or the iPhone camera over the `OllinPhone` link, the same way ARKit's environment probes light virtual objects with the surrounding scene. It connects image-based lighting to the vision and phone-capture stack already in place.
- **Rigid-body dynamics in 3D.** The 2D physics world is hybrid soft-Verlet and vendored Box2D; a 3D scene rich enough to stack, tumble, and swing wants the same third leg. Vendoring Jolt (MIT) follows the Box2D pattern exactly (wrapped behind Ollin's own API, off the public surface), and it pairs with the meshing techniques ahead (marching cubes, metaballs) for simulated forms.

It's opt-in, so a 2D sketch never pays for a depth buffer or a perspective divide. The iPhone point cloud renders through it, and visionOS and AR build on it. See the [design notes](DESIGN-NOTES.md#3d-mode).

## Photorealistic 3D

The high-end, well-curated realism tier, opt-in on the existing PBR, IBL, ray-traced shadows and reflections, and SDF raymarching, so a 2D or stylized 3D sketch never pays. The techniques that separate a polished product render or film still from "CG," each Metal-native and written from the published technique (credited in `ATTRIBUTION.md`'s Techniques list):

- **Area lights and light shaping.** Rectangular, disk, and tube **area lights** (Linearly Transformed Cosines) for the soft, believable studio lighting a point light can't make, plus IES photometric profiles and light cookies / gobos for realistic falloff and textured light.
- **Real-time global illumination.** Indirect bounce light beyond the IBL ambient term: light probes / irradiance volumes, screen-space GI, or a dynamic-diffuse-GI scheme (DDGI). The single biggest "it looks real" lever after direct lighting.
- **Volumetrics and atmosphere.** Volumetric lighting (god rays / light shafts through participating media), height and distance fog, atmospheric / aerial-perspective scattering, and raymarched volumetric clouds over the procedural sky.
- **Advanced materials.** Glass and **transmission / refraction** (frosted, thin-film, the glTF `KHR_materials_transmission` / `_volume` set), **clearcoat** (car paint and lacquer's second specular lobe), real **subsurface scattering** (skin, wax, jade, beyond the stylized finish), **sheen** (fabric and velvet), and surface detail (parallax-occlusion and displacement, triplanar and detail maps, decals).
- **Image quality and motion.** **Temporal anti-aliasing** (and the temporal accumulation that also cleans SSAO / SSR / GI noise), **MetalFX** temporal upscaling for quality and headroom, **contact shadows** (short-range screen-space) to seat objects on surfaces, and per-object and camera **motion blur** via a velocity buffer for cinematic movement.

See the [design notes](DESIGN-NOTES.md#photorealistic-3d).

## Sound, synthesis, and spatial audio

The audio layer listens today (FFT, bands, beat detection) but can't make or place sound. Three additions turn it into an output channel: **synthesis** (oscillators with envelopes, filters, delay and reverb, Karplus-Strong plucked strings, a small patchable graph, so a sketch can voice itself), **spatial audio** (a drawn object emits sound from its position in the 3D scene, the camera as the listener), and **modal synthesis** (a shape rings at the frequencies its geometry implies, so form and timbre move together). On the note-generation side, an **algorithmic-composition** toolkit (Euclidean rhythms via Bjorklund's algorithm, scales and chords, Markov sequences, arpeggiators) turns the synthesis voices into generative music, locked to the [tempo sync](#tempo-sync) clock. **Sonification**, turning a data series or a field into sound, falls out of the same machinery. See the [design notes](DESIGN-NOTES.md#sound-synthesis-and-spatial-audio).

## Tempo sync

**Near-term.** Lock a sketch's motion to a live music setup, the way a VJ syncs visuals to a DJ. The clean first form rides the existing MIDI transport: receive **MIDI clock** (plus start/stop/continue), derive tempo and beat phase, and expose `tempo` / `beat` / `phase` as values a sketch reads in `draw()` so animation falls on the beat, with the existing `Timeline` primitive able to run on musical time. The cross-app, cross-machine standard is **Ableton Link** (shared tempo and beat phase across apps and devices on a network); its own SDK is GPLv2 or a paid license, so it stays the inspiration-only tier (reimplement the protocol, never vendor it, the same posture as Hydra's AGPL). See the [design notes](DESIGN-NOTES.md#tempo-sync).

## Live rigs: physical computing, lighting, and network video

The integration tier reaches other software (Syphon, OSC, MIDI, the virtual camera); this tier reaches the hardware and the network around the machine, the physical-computing heritage of the lineage Ollin comes from:

- **Serial and Bluetooth LE.** A `SerialPort` for USB microcontrollers (sensors in, servos and LEDs out) and Bluetooth LE peripheral reads, each surfaced the way OSC and MIDI already read: a latest-value cache, a message drain, `@Param` binding.
- **DMX lighting over Art-Net / sACN.** Drive stage lights and dimmers from `draw()`; both protocols are published UDP wire specs, so this is the written-from-spec posture OSC set. **LED mapping** rides on it: sample canvas regions onto addressable LED strips and matrices, so a sketch's pixels leave the screen.
- **NDI.** The network sibling of Syphon: send and receive live video between machines, the standard in VJ and broadcast rigs. Its SDK is binary-only under its own license, so unlike the source-vendored tier it needs a licensing review before any code; that review decides whether and how it ships.

All of it is the interop posture: play in someone's existing rig, not replace it. See the [design notes](DESIGN-NOTES.md#live-rigs-physical-computing-lighting-and-network-video).

## New input sources

More of the platform's live signals, each a `FrameSource` or a simple value read in `draw()`:

- **Screen and window capture.** Any app's window or the whole screen as a live texture, processed like a video feed (the non-cooperative complement to Syphon, which needs the other app to publish).
- **Voice and sound events.** Speech recognition as drawable live captions, and sound-event classification (a clap, a genre, a bark) as a trigger, the audio analogue of the vision trackers.
- **Rich controllers.** Game controllers (gyro, triggers, touchpad), trackpad pressure, and, on the iOS leg, Apple Pencil tilt and azimuth.
- **Body and world data.** Heart rate from a paired Watch for biofeedback, and real-world ambient data (weather, location) as a slow live input.

Several overlap the [iPhone sensor array](#iphone-as-a-sensor-array); these are the Mac-side direct sources. See the [design notes](DESIGN-NOTES.md#new-input-sources).

## New output surfaces

Ways a sketch leaves the window:

- **Haptics.** A `draw()` that also emits a felt pattern synced to the visuals, on Force Touch trackpads and on the phone.
- **The OS as a canvas.** Wrap a sketch as a macOS screen saver, a dynamic wallpaper, a desktop widget, or a menu-bar piece, so the output lives in the system rather than a window.
- **Spatial export.** Export a 3D sketch as a USDZ (for AR Quick Look, sharing, and visionOS) or as spatial video, so the artifact stays three-dimensional instead of flattening to a frame.
- **Fabrication export.** Write a `Mesh` to STL / 3MF / OBJ so generative sculpture can be 3D-printed, the fabrication counterpart of the plotter path. Distinct from the viewing-oriented USDZ above: printing brings its own requirements (watertight geometry, real-world units and scale).
- **Print separations.** Split a sketch into spot-color layers for risograph and screen printing: map its colors onto a chosen ink set, halftone or dither each layer, and export per-layer files with registration marks. Sits beside the dithering family planned in the [technique catalog](#technique-and-algorithm-helpers), and serves the same physical-output audience as the plotter path.
- **Performance capture.** Real-time recording of a live session with audio, since the offline exporters re-render on a fixed clock and can't capture an improvised run. The OllinLiveCoding performance host and VJ sets are the obvious customers.

See the [design notes](DESIGN-NOTES.md#new-output-surfaces).

## Rendering and color frontier

Deeper use of the Metal core and Apple displays, all opt-in so the 2D path stays untaxed:

- **Wide-gamut and HDR.** Composite and present through Display P3 (and Rec. 2020) end to end, and export true HDR video (HDR10 / Dolby Vision) from the float pipeline that already exists, for richer color than an 8-bit sRGB target can hold.
- **GPU-driven rendering.** Indirect command buffers and mesh shaders to scale past instancing: many more distinct, GPU-encoded or GPU-generated objects with the CPU out of the per-object loop.
- **Film-quality export.** An offline path-traced render path a sketch can switch to for gallery-grade stills and sequences, from the same scene tuned live (an extension of the ray-tracing direction noted under [3D mode](#3d-mode)).

See the [design notes](DESIGN-NOTES.md#rendering-and-color-frontier). (The most speculative items here, spectral rendering, AI frame interpolation, and optical-flow self-warp, sit under [Further out / exploratory](#further-out--exploratory).)

## Authoring and editor tooling

**Later.** Editing experiences the live-reload core makes possible, and where Ollin draws its line on AI. The public stance already holds (the README's "It's a tool for making art ... Ollin is not a generative-art model"), and it extends to any AI *feature*: **AI is a tool for operating the framework, never an author of sketches.** Helping wire a generator, suggest a filter, or move knobs toward a look is in scope; generating a whole sketch or its imagery from a prompt is deliberately out. Within that line:

- **A visual node editor** over the effect, SDF-combinator, and shader graphs, living in the live host and round-tripping to Swift source.
- **Deeper live-coding evaluation.** Per-block evaluation and sub-second turnaround on small edits for the OllinLiveCoding performance host, refining its evaluate-on-command loop, plus MIDI/OSC mapping of the host's own performance surface.
- **Direct manipulation.** Drag a shape in the running window and have the edit written back into the source, the way a SwiftUI preview manipulates a layout.
- **Record and replay.** Capture a run's input and parameter timeline and scrub it backward, a rewind for generative work.
- **AI at the controls.** Drive the knobs, wire and parameterize generators, and tune toward a described look, all as operations on the typed `@Param` and effect graph, with the artist composing the sketch.
- **On-device ML as a material.** Apple-silicon models a sketch invokes deliberately, like a noise function: semantic parameter control, neural style as a `Filter`, segmentation-driven generators. Image generation from a text prompt is the one to weigh most carefully against the stance above; if it ships, it is an optional material the artist composes with, never the framework making the piece.

See the [design notes](DESIGN-NOTES.md#authoring-and-editor-tooling).

## Collaboration and multi-device

Apple-native, low-ceremony ways several machines share one piece: **Multipeer** local networking so several Macs and iPhones form one canvas with no server, the **iPhone as a 6DoF wand** (extending the sensor stream the phone already sends). (A more speculative **SharePlay** co-creation idea sits under [Further out / exploratory](#further-out--exploratory).) See the [design notes](DESIGN-NOTES.md#collaboration-and-multi-device).

## Installation mode

The concerns of a piece that runs unattended for days in a gallery rather than for a session at a desk: checkpoint and restore of generative state, restart on failure, scheduled evolution, and graceful handling of display sleep and wake. The other half is getting the piece onto the wall: projection mapping (a corner-pin / homography warp on the presented frame, with edge blending across projectors) and fullscreen output spanning several displays. A documented, supported way to run long rather than a hope. See the [design notes](DESIGN-NOTES.md#installation-mode).

## Learning: the Guide

**Near-term.** The reference docs ([`Docs/`](Docs/)) answer "what does this function do"; the [Guide](Guide/README.md) is the narrative layer that answers "how do I think in sketches": a practical, book-length introduction to creative coding taught through Ollin, written for an engineer with no math, graphics, or Swift background. The queue, the briefs, and the feature-coverage plan live in [`Guide/PLAN.md`](Guide/PLAN.md), and the writing rules (every concept explained before use, every listing a compiled figure, every image rendered from committed source) in [`Guide/AUTHORING.md`](Guide/AUTHORING.md). Ahead: the appendices, each a well-scoped, self-contained pickup. Appendix A is the narrative Swift primer for the Guide's audience, Appendix B re-explains every math idea in the guide visually, and Appendix D is the complete-toolbox index generated from the feature-coverage matrix.

## A third-party extension ecosystem

**Near-term.** The framework grows past the core team only when other people can publish and find extensions, the contributed-addon ecosystems p5.js, openFrameworks (`ofx*`), and OPENRNDR (`orx-*`) all have. SwiftPM already makes the mechanics free (a package that depends on `Ollin`), so the work is *convention and discovery*: a naming convention (an `ollinx-*` prefix in the `ofx*` spirit), a documented set of stable extension points (the `SketchExtension` seam, custom `Filter` / `Generator` / `Sim` / `Shader` types, the `FrameSource` protocol, the satellite-package pattern), a starter template for a new extension, and a curated list so they are findable. Deciding the conventions early keeps the ecosystem consistent. The same discovery concern applies to Ollin itself: publishing the API reference as a DocC catalog and listing the package on the Swift Package Index puts the framework behind the Swift community's default front doors. See the [design notes](DESIGN-NOTES.md#a-third-party-extension-ecosystem).

## Performance profiling and GPU debugging

Ollin sits on a GPU core and pitches the rendering ceiling, but it doesn't yet help a sketch author see *their own* cost. The FPS and stats overlay is the seed; the gap is a real profiler: a per-frame breakdown (draw calls, vertices, tessellation, and SDF vs triangle vs fringe batches), an honest CPU-versus-GPU frame-time split so the CPU-tessellation cost is visible when it bites, and a hook into Metal's frame capture for the deep cases. A framework that's fast should make it easy to find out why a particular sketch isn't. See the [design notes](DESIGN-NOTES.md#performance-profiling-and-gpu-debugging).

## Accessibility and inclusive text

Making Ollin and the work people make with it more inclusive, on the platform's native support. For **authors**: colorblind-safe palette helpers and a color-vision *simulation* filter (preview a sketch as it reads under deuteranopia and friends), plus reduced-motion awareness for the motion-by-default model. For **viewers**: a describable-output path, the native counterpart to p5's `textOutput()`, so a generative piece can carry an accessible description. And **robust complex-script text**: verifying and surfacing Core Text's handling of CJK, right-to-left scripts, emoji, and combining marks, so the text system serves a global audience. See the [design notes](DESIGN-NOTES.md#accessibility-and-inclusive-text).

## Further out / exploratory

Lower-confidence ideas kept on record but deliberately not near-term: each is plausible on the platform, but speculative enough that it shouldn't crowd the planned work above. Distinct from [On the horizon](#on-the-horizon), which is the platform-gated later legs (iOS, visionOS, AR), not uncertainty.

- **Spectral rendering.** Composite in spectra rather than RGB, for physically-correct subtractive color mixing, thin-film iridescence, and diffraction. (Detail under [rendering and color frontier](DESIGN-NOTES.md#rendering-and-color-frontier).)
- **AI frame interpolation.** Render at a lower frame rate and ship smooth slow-motion via an on-device interpolation model.
- **Optical-flow self-warp.** Feed the sketch's own motion field, from the existing Vision optical flow, back into its history for flow and glitch looks.
- **Text-to-image as a material.** On-device diffusion a sketch could invoke as an optional, labelled material. The one to weigh hardest against the AI boundary, since it sits closest to the contested use, so it lives here rather than in the planned [authoring tier](#authoring-and-editor-tooling); see the AI stance stated there.
- **SharePlay co-creation.** Two people tuning one sketch together over a FaceTime call (GroupActivities). The most speculative of the [collaboration](#collaboration-and-multi-device) ideas.

## On the horizon

Larger, later directions. 2D on macOS stays the focus; these don't change that.

- **Swift Playgrounds and iOS.** Swift Playgrounds App Projects are the closest Swift gets to the p5.js "open the editor and type, watch it move" experience, and the same work unlocks iPad sketching and embedding in any SwiftUI app. The view layer is already SwiftUI-embeddable; the main blocker is declaring an iOS target and making the view conditional across AppKit and UIKit. The Metal renderer is already portable. [Design notes.](DESIGN-NOTES.md#swift-playgrounds-and-ios)
- **visionOS.** Immersive rendering uses a different render loop (CompositorServices rather than `MTKView`), so the per-frame loop stays behind a seam that either a normal view or a visionOS layer renderer can drive. It builds on the [3D mode](#3d-mode) and the iOS target. [Design notes.](DESIGN-NOTES.md#3d-mode)
- **AR mode and templates.** AR sketches on Apple platforms, with ready-made templates for face, world, and image tracking, so an AR sketch becomes "fill in the `draw()`, the tracking is handed to you". It's layered on the iOS and 3D work rather than a separate engine, and aims at the gap left by discontinued template-driven AR tools. [Design notes.](DESIGN-NOTES.md#ar-mode-and-templates-the-meta-spark-gap)

These three can't be verified in every environment; iOS, visionOS, and AR need the right SDKs, a simulator, or a device.
