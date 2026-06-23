# Ollin roadmap

Ollin is a creative-coding framework for Swift and Metal on Apple platforms, aiming for p5.js ergonomics on an OPENRNDR-grade core. This file is the running list of what's planned and what's being explored. If you'd like to help, it's a good place to start.

For how the framework works and the conventions behind it, see the guides in [`Docs/`](Docs/). For working code, browse [`Examples/`](Examples/).

## How to contribute

A few things worth knowing before you pick something up:

- Building and running needs macOS 26+ and a Metal-capable GPU. There's no way around the Swift toolchain and Metal, so changes are verified on a Mac.
- New drawing features are built on the typed core first (the `Drawer` and the value types), then given the bare p5-style call as sugar. Anything the bare API can do, the core should be able to do too, with more control.
- A feature isn't considered done until it has an example. Examples live in [`Examples/`](Examples/), one idea per sketch, and they're compile-tested in CI so they don't rot. Writing the example is also how the API gets a sanity check: if it's awkward to write, the API probably needs work.
- The items under [Up next](#up-next) are the most self-contained, so they tend to make the best first contributions.

If you're coming from p5.js or JavaScript, [`Docs/Swift.md`](Docs/Swift.md) covers just enough Swift to get productive.

## Up next

Near-term, fairly self-contained pieces, each small and well-scoped.

- **User-supplied shaders.** A way for a sketch to bring its own Metal shader functions, resolved ahead of the built-ins, with hot-reload through the runtime source compiler. The fluent mixing layer above this is [shader composition and live-coding](#shader-composition-and-live-coding).
- **Normalized `u, v` coordinates.** A 0…1 coordinate space across the canvas alongside points, so a sketch can place things without referring to `width`/`height`.
- **PDF export beside SVG.** The vector serializer already records every draw call as geometry; Core Graphics can write the same geometry to PDF for print.
- **Palette file import.** Load a `Palette` from a file — plain hex-per-line text first, Adobe `.ase` swatches as the stretch — so anyone can pull palettes they've collected (a COLOURlovers favorite, a Lospec export, design-tool swatches) into a sketch locally. This is the "ship the loader, not the data" rule the bitmap-font `.fnt` loader set: bundled palette *data* stays license-gated (ColorBrewer-style, verifiably permissive only), while the loader makes any palette a file away. The loading surface mirrors the font and image loaders (`path`/`data`/`resource:in:`, with the same caller-bundle gotcha).
- **Stroke as shape.** Offsetting an *open* path turns a stroked polyline into a closed outline region — a thick stroke that exports as a filled SVG region, hatches for the plotter, or feeds the shape booleans. The offsetting engine already does this for closed regions; the work is the open-path surface (end caps, and where the API lives).
- **Single-file sketches.** A zero-ceremony way to run one `.swift` file as a sketch, in the spirit of `swift-sh`, so dashing off an idea doesn't require setting up a package.
- **Retained geometry buffers.** Every frame currently re-uploads everything; keeping static geometry (a large point cloud, a fixed background) in a persistent buffer would drop its per-frame cost to zero.
- **More SDF shapes, when a good fit appears.** Any canonical form parameterized by a size and a ratio or two drops into the instanced-SDF path as four small touch-points (a shape tag, a builder, a distance function, and a fragment case).
- **More model examples over `ModelTracker`.** The custom-model tracker runs anything converted to Core ML; a well-known model can make a strong example, with the weights always fetched by `Scripts/fetch-models.sh` rather than committed. Candidates, licenses, and the surfaces involved are in the [design notes](DESIGN-NOTES.md#model-examples-and-modeltracker-surfaces-not-started).

## Layered effects and compositing

Building on the off-screen-layer + filter substrate (`renderTarget` / `withTarget` / `Filter` / `generate`, with a broad catalog of color, tone, stylize, and optical filters plus procedural pattern generators, previous-frame feedback for trails and tunnels, two-input combine ops — mask, displace, cross-dissolve, and a depth-map-driven depth-of-field defocus — with the `aside` helper layer that feeds them, and the declarative `compose { }` layer-stack DSL over it all), the work ahead is **ambient occlusion** (a screen-space depth-and-normal pass) and feeding the depth-of-field defocus the 3D scene's depth buffer directly. Shape, references, and the design are in the [design notes](DESIGN-NOTES.md#layered-effects-and-compositing-partly-shipped).

## Shader composition and live-coding

Two linked directions: a composable API for chaining and mixing shader-driven visuals fluently (in the spirit of Hydra's `osc().rotate().modulate(noise())`), and a separate live-coding performance app built on top of it. Both are distinct from `OllinLive`, which is edit-loop hot-reload, not a performance tool. See the [design notes](DESIGN-NOTES.md#shader-composition-and-live-coding-not-started).

## Generative geometry

A tier of classic generative-art building blocks that emit vector geometry — points, `Contour`s, `Shape`s — feeding the existing draw, shape-boolean, hatching, and SVG paths rather than the renderer: **circle and shape packing** (grow-to-touch and front relaxation), **L-systems** (grammar-driven recursive structure), and **differential growth** (organic line and curve accretion). They share the plotter-friendly, geometry-first shape the shape booleans set, all driven by the existing seedable `random`/`noise` so a run is reproducible, and each ships with an example — several are the natural implementation behind a [recreation](DESIGN-NOTES.md#examples-folder-maintained-ongoing) of the artist who pioneered them. See the [design notes](DESIGN-NOTES.md#generative-geometry-not-started).

## Project generator

An openFrameworks-style generator that scaffolds a ready-to-run sketch folder from a few questions (which capabilities, which canvas size), instead of hand-copying boilerplate. See the [design notes](DESIGN-NOTES.md#project-generator--sketch-scaffolding-not-started).

## Variation galleries and seed exploration

Ollin sketches are already reproducible (`seed()` makes a run deterministic) and tunable (`@Param`); the missing piece is *exploring the seed space* the way Art Blocks-style generators do. Navigate a sketch's variations — step through seeds, jump to one, randomize — and export a contact sheet of many seeds as a single image (the fixed-timestep frame driver behind `OllinApp.image(of:)` already renders any frame off-screen). Distinct from the [project generator](#project-generator), which scaffolds a *new* sketch; this explores the variation space of an existing one. See the [design notes](DESIGN-NOTES.md#variation-galleries-and-seed-exploration-not-started).

## iPhone as a sensor array

A Mac has no depth camera, inertial sensors, or spare Neural Engine for live perception; a tethered iPhone has all three. The idea: let the phone act as a sensor and on-device ML co-processor for a sketch that still renders on the Mac, capturing and perceiving (LiDAR point clouds, face and body tracking, segmentation, device motion, and more) and streaming typed results the sketch reads in `draw()`. Both a recorded RGBD clip and a tethered phone's live USB RGBD stream already reconstruct on the Mac as point clouds (see [`Docs/Record3D.md`](Docs/Record3D.md)), the kind of world-facing depth feed an Intel RealSense once gave openFrameworks, and a sweep of the phone's depth frames fuses by camera pose into one world cloud (see [`Docs/Phone.md`](Docs/Phone.md)). The work ahead grows that stream into the rest of the phone's senses — scene mesh, richer face and body data — over Ollin's own iPhone capture app, and drift-corrects a long sweep so its fused cloud stays registered. The wire protocol, the sensor catalog, and the build order are in the [design notes](DESIGN-NOTES.md#iphone-as-a-sensor-array-partly-shipped).

## 3D mode

2D stays the default, and 3D keeps building out on top of the shipped camera, depth buffer, transform stack, solid primitives, meshes loaded from file (with their own base-color material and texture), textured meshes, the directional/point/spot light & material model, curated lighting presets, the stylized material library (iridescent, velvet, jade, toon, gooch, …), matcap materials (view-normal sphere-texture shading), and directional, spot, and point cast shadows:

- **Scene import (`loadScene` beside `loadMesh`).** A loaded model collapses to one merged `Mesh` today, which is right when a sketch just wants the geometry to place itself. The complement preserves a file's *structure*: glTF and USD are scene formats (a node hierarchy with per-node transforms, plus cameras and lights), so `loadScene` would return a `Scene` of named nodes a sketch draws in place (`scene.draw()`), reaches individually to animate (`scene.node("lamp")`), and opens on the camera and lights the scene was authored with, handing back the same `Camera3D` and `Light` types the rest of 3D mode uses. It makes "compose a draft scene in a design tool, then bring it into a sketch" a first-class workflow, aligning with the glTF 2.0 standard every tool exports (Spline, Blender, three.js). A one-way *scene-to-source* variant (emitting an editable sketch instead of a live asset) belongs with the [project generator](#project-generator).
- **Softer shadows for the directional and spot casters** — contact-hardening (PCSS-style) penumbrae so a sun or spot shadow sharpens at contact and blurs as it falls away, via a blocker search + receiver-distance kernel on the 2D maps (or by routing those casters through the ray-traced shadow path the point caster uses).
- **Physically-based shading and environment lighting** — the later realism tier: a physically-based material model (energy-conserving, roughness and metalness) lit by image-based environment maps (a prefiltered HDRI or a procedural studio environment), which is how modern real-time 3D gets its photographic look. The bigger step beyond the analytic directional/point/spot model, pairing the material and lighting halves; it builds on the named-material and preset work rather than replacing it.

It's opt-in, so a 2D sketch never pays for a depth buffer or a perspective divide. The iPhone point cloud renders through it, and visionOS and AR build on it. See the [design notes](DESIGN-NOTES.md#3d-mode-partly-shipped).

## On the horizon

Larger, later directions. 2D on macOS stays the focus; these don't change that.

- **Swift Playgrounds and iOS.** Swift Playgrounds App Projects are the closest Swift gets to the p5.js "open the editor and type, watch it move" experience, and the same work unlocks iPad sketching and embedding in any SwiftUI app. The view layer is already SwiftUI-embeddable; the main blocker is declaring an iOS target and making the view conditional across AppKit and UIKit. The Metal renderer is already portable. [Design notes.](DESIGN-NOTES.md#swift-playgrounds-and-ios-not-started)
- **visionOS.** Immersive rendering uses a different render loop (CompositorServices rather than `MTKView`), so the per-frame loop stays behind a seam that either a normal view or a visionOS layer renderer can drive. It builds on the [3D mode](#3d-mode) and the iOS target. [Design notes.](DESIGN-NOTES.md#3d-mode-partly-shipped)
- **AR mode and templates.** AR sketches on Apple platforms, with ready-made templates for face, world, and image tracking, so an AR sketch becomes "fill in the `draw()`, the tracking is handed to you". It's layered on the iOS and 3D work rather than a separate engine, and aims at the gap left by discontinued template-driven AR tools. [Design notes.](DESIGN-NOTES.md#ar-mode-and-templates-eventual-the-meta-spark-gap)

These three can't be verified in every environment; iOS, visionOS, and AR need the right SDKs, a simulator, or a device.
