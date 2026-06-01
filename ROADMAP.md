# Ollin roadmap

Ollin is a creative-coding framework for Swift and Metal on Apple platforms, aiming for p5.js ergonomics on an OPENRNDR-grade core. This file is the running list of what's planned and what's being explored. If you'd like to help, it's a good place to start.

For how the framework works and the conventions behind it, see the guides in [`Docs/`](Docs/). For working code, browse [`Examples/`](Examples/).

## How to contribute

A few things worth knowing before you pick something up:

- Building and running needs macOS 14+ and a Metal-capable GPU. There's no way around the Swift toolchain and Metal, so changes are verified on a Mac.
- New drawing features are built on the typed core first (the `Drawer` and the value types), then given the bare p5-style call as sugar. Anything the bare API can do, the core should be able to do too, with more control.
- A feature isn't considered done until it has an example. Examples live in [`Examples/`](Examples/), one idea per sketch, and they're compile-tested in CI so they don't rot. Writing the example is also how the API gets a sanity check: if it's awkward to write, the API probably needs work.
- The items under [Up next](#up-next) are the most self-contained, so they tend to make the best first contributions.

If you're coming from p5.js or JavaScript, [`Docs/Swift.md`](Docs/Swift.md) covers just enough Swift to get productive.

## Up next

Near-term, fairly self-contained pieces. Each is small and well-scoped, which is what makes them good first contributions.

- **More 2D primitives and the SDF shape catalog.** `drawTriangle`, then a run of analytic shapes that drop into the existing instanced-SDF path at near-zero per-shape cost: regular n-gon, star, point markers, rhombus, vesica, moon, cross, ring, trapezoid, egg, heart, and more. Each is a small, well-scoped addition (a shape tag, a builder, a distance function, and a fragment case), so they're a good way in.
- **Configurable stroke joins and caps.** Mitered joins already work for the polyline family. What's left is round and bevel joins, plus round and square caps for open ends.
- **Easing and animation helpers.** A small set of easing curves, and a property wrapper that eases a value toward a target each frame.
- **`size()` from `setup()`.** Today a custom canvas size means overriding a property. An imperative `size(width, height)` callable from `setup()` would read closer to p5's `createCanvas`, while keeping the declarative form too. The constraint is preserving deterministic headless export.
- **One source of truth for the CPU/GPU structs.** A few structs are shared between Swift and the Metal shaders and kept in sync by hand. Moving them into a shared C header removes a class of silent memory bugs, and it unblocks two analytic shapes (a Bézier stroke and a general triangle) that need a larger instance struct.
- **Bézier and curved contours, and a `beginShape`/`vertex` builder.** Built on the existing vector `Shape`/`Contour` type.
- **The extension and lifecycle seam.** A before/after-draw and frame-grab hook. This one unlocks several things at once: snapshot tests, an FPS overlay, layered effects, and frame-sequence export.
- **Render-correctness snapshot tests.** Compile-testing proves an example builds; snapshot tests prove it still renders the same. The off-screen render path already exists, so this mostly needs the frame-grab hook above.

## Core batteries

The table-stakes capabilities p5.js, openFrameworks, and OPENRNDR all ship and Ollin doesn't yet: **keyboard input** (the smallest, and a good first contribution), **text and typography**, **image loading**, and **audio** (lowest priority, mostly for audio-reactive visuals). A sketcher reaches for these early, so they matter more than their size suggests; all four are Apple-native and stay sugar over the typed core. Engines, APIs, and ordering are in the [design notes](DESIGN-NOTES.md#core-batteries-text-image-audio-keyboard-not-started).

## Integration and performance I/O

Wiring a sketch into an installation or performance rig: **OSC** (Open Sound Control) for networked messages to and from TouchDesigner, Max/MSP, Ableton, Resolume, and lighting desks, built on `Network.framework` since OSC is just UDP or TCP; and **MIDI** through Core MIDI, for control surfaces and knobs driving parameters, clock and notes in, messages out, pairing naturally with the `@Param` knobs. Both are Apple-native at the transport layer and stay sugar over the typed core. See the [design notes](DESIGN-NOTES.md#integration-and-performance-io-osc-and-midi-not-started).

## Physics

Lightweight 2D physics so motion can come from simulation instead of hand-tuned values: particles, springs, Verlet integration, and simple rigid bodies. No clean Apple-native substrate fits (SpriteKit is a retained-mode scene graph, too heavy to build on), so it's either a small from-scratch particle and Verlet system or a vendored permissively-licensed 2D engine. See the [design notes](DESIGN-NOTES.md#physics-not-started).

## Layered effects and compositing

OPENRNDR-style effects that compose in layers: draw into off-screen targets, run filters (blur, bloom, feedback, color grades) over them, and composite with blend modes. The natural home for post-processing, building on the off-screen render path the exporter already uses. Shape, references, and the design are in the [design notes](DESIGN-NOTES.md#layered-effects-and-compositing-not-started).

## Shader composition and live-coding

Two linked directions: a composable API for chaining and mixing shader-driven visuals fluently (in the spirit of Hydra's `osc().rotate().modulate(noise())`), and a separate live-coding performance app built on top of it. Both are distinct from `OllinLive`, which is edit-loop hot-reload, not a performance tool. See the [design notes](DESIGN-NOTES.md#shader-composition-and-live-coding-not-started).

## Offline frame-sequence export

Render an animated sketch to a numbered PNG sequence (then assemble to video). The key idea is to advance the clock at a fixed timestep instead of wall-clock, so each frame renders deterministically no matter how long it takes; export is offline by design. See the [design notes](DESIGN-NOTES.md#offline-frame-sequence-export-not-started).

## Project generator

An openFrameworks-style generator that scaffolds a ready-to-run sketch folder from a few questions (which capabilities, which canvas size), instead of hand-copying boilerplate. See the [design notes](DESIGN-NOTES.md#project-generator--sketch-scaffolding-not-started).

## Computer vision

Image understanding on the Mac itself: grab the webcam (or a Continuity Camera) and run face, body, and hand tracking, person and subject segmentation, optical flow, contour and rectangle detection, OCR, and object tracking, hardware-accelerated on the Neural Engine. A first-class Mac capability with no phone required, built on Vision, Core ML, Core Image, vImage and Accelerate, and AVFoundation. The one thing the Mac can't do is depth and AR sensing (LiDAR, TrueDepth face mesh, ARKit world tracking); that is the [iPhone as a sensor array](#iphone-as-a-sensor-array) section, the depth and AR superset over the same models. See the [design notes](DESIGN-NOTES.md#computer-vision-not-started).

## iPhone as a sensor array

A Mac has no depth camera, inertial sensors, or spare Neural Engine for live perception; a tethered iPhone has all three. The idea: let the phone act as a sensor and on-device ML co-processor for a sketch that still renders on the Mac, capturing and perceiving (LiDAR point clouds, face and body tracking, segmentation, device motion, and more) and streaming typed results the sketch reads in `draw()`. The first slice is a live RGBD point cloud, the kind an Intel RealSense once fed openFrameworks. The wire protocol, the sensor catalog, and the build order are in the [design notes](DESIGN-NOTES.md#iphone-as-a-sensor-array-not-started).

## On the horizon

Larger, later directions. 2D on macOS stays the focus; these don't change that.

- **Swift Playgrounds and iOS.** Swift Playgrounds App Projects are the closest Swift gets to the p5.js "open the editor and type, watch it move" experience, and the same work unlocks iPad sketching and embedding in any SwiftUI app. The view layer is already SwiftUI-embeddable; the main blocker is declaring an iOS target and making the view conditional across AppKit and UIKit. The Metal renderer is already portable. [Design notes.](DESIGN-NOTES.md#swift-playgrounds-and-ios-not-started)
- **3D mode and visionOS.** 2D stays the default, but the back end is kept from foreclosing 3D: a camera, a depth buffer, the transform stack generalized to 4x4, a `Vector3`, and 3D primitives. visionOS uses a different, immersive render loop, so the per-frame loop is kept behind a seam that either a normal view or a visionOS layer renderer can drive. [Design notes.](DESIGN-NOTES.md#3d-mode-and-visionos-eventual-2d-stays-primary)
- **AR mode and templates.** AR sketches on Apple platforms, with ready-made templates for face, world, and image tracking, so an AR sketch becomes "fill in the `draw()`, the tracking is handed to you". It's layered on the iOS and 3D work rather than a separate engine, and aims at the gap left by discontinued template-driven AR tools. [Design notes.](DESIGN-NOTES.md#ar-mode-and-templates-eventual-the-meta-spark-gap)

These three can't be verified in every environment; iOS, visionOS, and AR need the right SDKs, a simulator, or a device.
