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

Near-term, fairly self-contained pieces. Each is small and well-scoped, which is what makes them good first contributions.

- **Blend modes.** Compositing modes beyond source-over, additive first — it's what light-accumulation sketches want (see [depth-of-field particle rendering](#depth-of-field-particle-rendering-sandpainting)). Blend mode wants to land as a parameter in the pipeline descriptor rather than a separate renderer path (see the [layered effects notes](DESIGN-NOTES.md#layered-effects-and-compositing-not-started)).
- **Accumulation canvas.** A render target the frame *doesn't* clear, so drawing piles up across frames — progressive refinement, long-exposure stills, classic paint-on-canvas sketches. Pulled forward from [layered effects](#layered-effects-and-compositing) as its own small feature because [depth-of-field particle rendering](#depth-of-field-particle-rendering-sandpainting) needs exactly this slice; with additive blending it already makes an 8-bit prototype playable before the float pipeline lands.
- **User-supplied shaders.** A way for a sketch to bring its own Metal shader functions, resolved ahead of the built-ins, with hot-reload through the runtime source compiler. The fluent mixing layer above this is [shader composition and live-coding](#shader-composition-and-live-coding).
- **Normalized `u, v` coordinates.** A 0…1 coordinate space across the canvas alongside points, so a sketch can place things without referring to `width`/`height`.
- **Sub-pixel region outlines.** Disks and lines already fade by area below ~1px instead of vanishing; the stroke band on region shapes (rect, star, triangle) doesn't yet. Closing that gap would make every outline honor sizes from 0 up. See the [render-scale notes](DESIGN-NOTES.md#supersampled-render-scale--the-crispness-dial-not-started).
- **PDF export beside SVG.** The vector serializer already records every draw call as geometry; Core Graphics can write the same geometry to PDF for print.
- **Palette file import.** Load a `Palette` from a file — plain hex-per-line text first, Adobe `.ase` swatches as the stretch — so anyone can pull palettes they've collected (a COLOURlovers favorite, a Lospec export, design-tool swatches) into a sketch locally. This is the "ship the loader, not the data" rule the bitmap-font `.fnt` loader set: bundled palette *data* stays license-gated (ColorBrewer-style, verifiably permissive only), while the loader makes any palette a file away. The loading surface mirrors the font and image loaders (`path`/`data`/`resource:in:`, with the same caller-bundle gotcha).
- **Stroke as shape.** Offsetting an *open* path turns a stroked polyline into a closed outline region — a thick stroke that exports as a filled SVG region, hatches for the plotter, or feeds the shape booleans. The offsetting engine already does this for closed regions; the work is the open-path surface (end caps, and where the API lives).
- **Single-file sketches.** A zero-ceremony way to run one `.swift` file as a sketch, in the spirit of `swift-sh`, so dashing off an idea doesn't require setting up a package.
- **Retained geometry buffers.** Every frame currently re-uploads everything; keeping static geometry (a large point cloud, a fixed background) in a persistent buffer would drop its per-frame cost to zero.
- **More SDF shapes, when a good fit appears.** Any canonical form parameterized by a size and a ratio or two drops into the instanced-SDF path as four small touch-points (a shape tag, a builder, a distance function, and a fragment case).
- **More model examples over `ModelTracker`.** The custom-model tracker runs anything converted to Core ML; a well-known model can make a strong example, with the weights always fetched by `Scripts/fetch-models.sh` rather than committed. Candidates, licenses, and the surfaces involved are in the [design notes](DESIGN-NOTES.md#model-examples-and-modeltracker-surfaces-not-started).

## Depth-of-field particle rendering (sandpainting)

**The priority track: the renderer work ahead is sequenced to make this kind of sketch possible.** A target experience that several roadmap items add up to: sketches in the style of Anders Hoff's depth-of-field and colour-shift work and the Blurry library — millions of faint particles, each displaced at random by its distance from a focal plane and accumulated as light, so depth of field *emerges* from the scatter instead of a post-process blur, with chromatic fringes from shifting the color channels apart. No single big feature; the pieces, in build order: **additive blending** and the **accumulation canvas** (both in [Up next](#up-next) — together they make a playable 8-bit prototype), the **[float/HDR pipeline](#rendering-precision-hdrfloat-pipeline)** (thousands of dim samples quantize to nothing in 8 bits, and colors above 1.0 are the point), and **scale** ([compute shaders](#compute-shaders) generating and jittering samples GPU-side). It doesn't wait for 3D: the displacement needs only a per-particle depth the sketch invents, so the prototype rides the instanced point path that already handles sub-pixel marks. See the [design notes](DESIGN-NOTES.md#depth-of-field-particle-rendering-sandpainting-not-started).

## Rendering precision (HDR/float pipeline)

Render into a 16-bit float (`rgba16Float`), linear-light intermediate, then tone-map and encode to the screen in a final pass. Two payoffs: smooth gradients with no 8-bit banding (a float buffer carries precision a fixed 8-bit target can't), and color values above 1.0, which bloom, glow, and HDR-style effects rely on. It's also the precise substrate the [layered effects](#layered-effects-and-compositing) graph wants — off-screen targets a sketch draws into and samples — so the natural order is precision first, the effect graph on top. See the [design notes](DESIGN-NOTES.md#rendering-precision-hdrfloat-pipeline-not-started).

## Layered effects and compositing

OPENRNDR-style effects that compose in layers: draw into off-screen targets, run filters (blur, bloom, feedback, color grades) over them, and composite with blend modes. The natural home for post-processing, building on the off-screen render path the exporter already uses. Shape, references, and the design are in the [design notes](DESIGN-NOTES.md#layered-effects-and-compositing-not-started).

## Shader composition and live-coding

Two linked directions: a composable API for chaining and mixing shader-driven visuals fluently (in the spirit of Hydra's `osc().rotate().modulate(noise())`), and a separate live-coding performance app built on top of it. Both are distinct from `OllinLive`, which is edit-loop hot-reload, not a performance tool. See the [design notes](DESIGN-NOTES.md#shader-composition-and-live-coding-not-started).

## Compute shaders

General-purpose GPU work as a first-class capability: kernels a sketch dispatches over buffers and textures each frame — particle and agent simulations in the hundreds of thousands (flocking, physarum, attractors), reaction-diffusion, cellular automata — with the results feeding the instanced render path or arriving as textures, never touching the CPU. Metal makes this native on every Mac Ollin supports, closing a long-standing platform gap: compute shaders arrived in OpenGL 4.3 and Apple's OpenGL stops at 4.1, so the GL-based frameworks never had them on a Mac. See the [design notes](DESIGN-NOTES.md#compute-shaders-not-started).

## Project generator

An openFrameworks-style generator that scaffolds a ready-to-run sketch folder from a few questions (which capabilities, which canvas size), instead of hand-copying boilerplate. See the [design notes](DESIGN-NOTES.md#project-generator--sketch-scaffolding-not-started).

## iPhone as a sensor array

A Mac has no depth camera, inertial sensors, or spare Neural Engine for live perception; a tethered iPhone has all three. The idea: let the phone act as a sensor and on-device ML co-processor for a sketch that still renders on the Mac, capturing and perceiving (LiDAR point clouds, face and body tracking, segmentation, device motion, and more) and streaming typed results the sketch reads in `draw()`. The first slice is a live RGBD point cloud, the kind an Intel RealSense once fed openFrameworks. The wire protocol, the sensor catalog, and the build order are in the [design notes](DESIGN-NOTES.md#iphone-as-a-sensor-array-not-started).

## 3D mode

2D stays the default, and a real 3D mode is part of the plan: a perspective or orthographic camera, a depth buffer, `Vector3` and the transform stack generalized to 4×4, 3D primitives (box, sphere, cylinder, plane, torus), meshes built in code or loaded from file, and a simple light and material model. It's opt-in, so a 2D sketch never pays for a depth buffer or a perspective divide. The iPhone point cloud renders through it, and visionOS and AR build on it. See the [design notes](DESIGN-NOTES.md#3d-mode-not-started).

## On the horizon

Larger, later directions. 2D on macOS stays the focus; these don't change that.

- **Swift Playgrounds and iOS.** Swift Playgrounds App Projects are the closest Swift gets to the p5.js "open the editor and type, watch it move" experience, and the same work unlocks iPad sketching and embedding in any SwiftUI app. The view layer is already SwiftUI-embeddable; the main blocker is declaring an iOS target and making the view conditional across AppKit and UIKit. The Metal renderer is already portable. [Design notes.](DESIGN-NOTES.md#swift-playgrounds-and-ios-not-started)
- **visionOS.** Immersive rendering uses a different render loop (CompositorServices rather than `MTKView`), so the per-frame loop stays behind a seam that either a normal view or a visionOS layer renderer can drive. It builds on the [3D mode](#3d-mode) and the iOS target. [Design notes.](DESIGN-NOTES.md#3d-mode-not-started)
- **AR mode and templates.** AR sketches on Apple platforms, with ready-made templates for face, world, and image tracking, so an AR sketch becomes "fill in the `draw()`, the tracking is handed to you". It's layered on the iOS and 3D work rather than a separate engine, and aims at the gap left by discontinued template-driven AR tools. [Design notes.](DESIGN-NOTES.md#ar-mode-and-templates-eventual-the-meta-spark-gap)

These three can't be verified in every environment; iOS, visionOS, and AR need the right SDKs, a simulator, or a device.
