# Changelog

Notable changes to Ollin, newest first. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Version numbers follow semantic versioning at major zero: a breaking change or a new feature bumps the minor, and a fix bumps the patch. Each release names its breaking renames here, so pin `.upToNextMinor` and read the entry before you move up.

## [Unreleased]

### Added

- **The website.** `ollin site` writes the README, the Guide, the reference, and every example with its source out as a static website, the pages rendered from the same files `ollin docs` reads, with a workflow that publishes it to GitHub Pages. [The reference offline](Docs/Tools/Reference.md#in-a-browser).

## [0.1.0] - 2026-09-02

The first tagged release. Ollin grew in one repository from May 2026 to this tag, and that history is not itemized here. This entry says what the release contains, area by area, with a link to the reference for each. The [README](README.md#whats-in-it) carries the fuller catalog, and the [Guide](Guide/README.md) teaches it in order. Read this entry as a table of contents rather than a list of changes.

### The framework

- **Drawing.** A p5-style API over a Metal core: `setup()` and `draw()`, and bare calls like `drawCircle` and `background`. `draw()` runs at the display's refresh rate from the first line, so motion is the default. Some thirty analytic shapes, curved paths, concave and holed fills, variable-width strokes, marks that follow the hand, shape booleans and offsets, gradients, blend modes, clipping, accumulation, and retained batches. Every frame composites in linear light with HDR tone mapping and analytic anti-aliasing. [Drawing](Docs/Drawing/Drawing.md).
- **Text and color.** Bitmap, outline, and single-line plotter fonts through one `drawText`, in any script, in columns, justified, along a path, or as vector shapes. OKLab mixing, spectral paint mixing, palettes and colormaps, color vision simulation, and wide-gamut and HDR output. [Text](Docs/Drawing/Text.md), [Color](Docs/Drawing/Color.md).
- **Shapes that merge.** SDF combinators in 2D and in raymarched 3D: smooth union, subtraction, morphing, domain mirror, tile, and radial repeat, and a clay-like `sculpt { }` block. [Combinators](Docs/Drawing/Combinators.md).
- **Generative technique.** Sixty-six classic techniques as first-class helpers, from Poisson-disk scatter and L-systems to Wave Function Collapse, strange attractors, marching cubes, paper marbling, and terrain erosion. [Generators](Docs/Generators/README.md).
- **Layers, effects, and shaders.** Off-screen layers with fifty-plus GPU filters, two-layer combines, feedback, simulation fields, and a compose DSL. Measured distance fields, light with shadows in a flat sketch, the frequency domain, and summed-area averages. Your own `shade(uv, info)` fragment function, inline or in a hot-reloading `.metal` file, with errors reported at your own line numbers. Chainable `Visual`s when you would rather skip the Metal. [Effects](Docs/Drawing/Effects.md), [Shaders](Docs/Shaders/Shaders.md).
- **Motion and parameters.** Frame-rate-independent easing and springs, keyframe timelines, seeded variations, and record and replay. `@Param` properties become typed inspector controls, persist across reloads, and can follow a curve or a formula. [Sketch](Docs/Core/Sketch.md), [Automation](Docs/Core/Automation.md), [Variations](Docs/Core/Variations.md).
- **GPU compute and simulation.** Compute kernels with a million particles a frame, and a neighbor-search primitive under artificial life and SPH fluids. Ping-pong texture simulations, steering crowds at GPU scale, populations that evolve, and chaotic systems. [Compute](Docs/Shaders/Compute.md), [Simulation](Docs/Simulation/README.md).
- **Physics.** A stepped `World` with Verlet particles and springs, Box2D bodies and joints in 2D, and Jolt-backed 3D bodies, joints, characters, vehicles, ragdolls, cloth, ropes, and water. [Physics](Docs/Simulation/Physics.md), [Physics in 3D](Docs/Simulation/Physics3D.md).
- **3D, opt-in.** Cameras and imported scenes (OBJ, glTF, USD), instanced meshes and GPU-culled worlds, grass and an ocean, physically based materials with the full map set, glass with dispersion, area lights, image-based lighting and a procedural sky. Shadows, ray-traced reflections, caustics, global illumination, atmosphere, temporal anti-aliasing, motion blur, and lens flare. A 2D sketch never pays for any of it. [3D](Docs/3D/README.md).
- **The world as input.** Nineteen on-device Vision trackers over the camera or any video, depth from a video model, screen and window capture, and video playback. CSV, JSON, and SVG import, live and pushed data feeds, game controllers, and an iPhone over USB as a LiDAR, motion, body, face, and hand sensor. [Vision](Docs/Vision/Vision.md), [Data](Docs/Helpers/Data.md), [The phone](Docs/3D/Phone.md).
- **Sound.** FFT analysis with beat detection, listening for words and named sounds, and a synthesizer the sketch plays. Voice presets, physical models, sampled instruments, wavetables, a patchable graph, effects chains, a place in the 3D scene, and algorithmic composition, all carried into an exported video. [Audio](Docs/Helpers/Audio.md), [Synthesis](Docs/Helpers/Synthesis.md).
- **Integration.** MIDI, OSC, a network tempo session, serial, Bluetooth Low Energy, DMX and LED mapping, and show lasers. Syphon out and in, a virtual camera, haptics, a remote surface for a phone, and a room several machines join to draw one piece on one clock. [Integration](Docs/Integration/README.md).
- **Output.** Headless stills and deterministic sequences, MP4 and GIF with slow motion, SVG and PDF with hatched fills, G-code, and print separations with press proofing. STL, OBJ, and 3MF for printing, USDZ and spatial video, a path-traced export, live recording with sound, and an accessibility layer for color vision and motion. [Export](Docs/Output/Export.md).
- **Running in the system.** A finished piece as a signed Mac app, a screen saver, the desktop wallpaper, a menu-bar strip, or an installation that stays up for a week. [A sketch as an app](Docs/Output/App.md), [Installation](Docs/Output/Installation.md).

### The tools

- **The `ollin` command.** One loose `.swift` file is a whole sketch, run from any directory. `ollin new` writes a starter, `ollin install` puts the command on PATH, and `ollin check` compiles a shader on this machine's GPU. `ollin docs` and `ollin examples` read the reference and the examples in the terminal. [Single-file sketches](Docs/Tools/SingleFile.md), [The reference offline](Docs/Tools/Reference.md).
- **OllinLive.** Save the file and the running window hot-swaps the sketch, with the clock carried across. `@Param` properties appear as typed inspector controls, a timeline records their automation, and Command-drag moves, resizes, or turns a shape by editing the source. `⌘]` and `⌘[` put it in front of or behind its neighbor. [The parameter timeline](Docs/Tools/Timeline.md), [Dragging a shape](Docs/Tools/DragToEdit.md).
- **OllinLiveCoding.** The performance host: the sketch fills the window, the code rides over it as translucent text, and Command-Return recompiles the buffer mid-motion. [Live coding](Docs/Tools/LiveCoding.md).
- **The project generator.** `ollin new` and `ollin generate` write a ready-to-run project from ten templates or from any example. They also bring a GLSL fragment shader or a glTF or USD scene over as source, and scaffold an extension library other sketches import. [Project generator](Docs/Tools/ProjectGenerator.md).
- **The examples.** 494 example sketches in their own package, browsable in one gallery window, including twelve recreations after eight artists. [Examples](Examples/README.md).

### The documentation

- The reference under [Docs/](Docs/README.md), about two hundred pages, with a short concept page for each idea the reference assumes.
- The [Guide](Guide/README.md), thirty-two chapters and four appendices: a practical introduction to creative coding taught through Ollin.
- For contributors, [CAPABILITIES.md](CAPABILITIES.md) inventories every capability's invariants, [ARCHITECTURE.md](ARCHITECTURE.md) explains the internals, and [ATTRIBUTION.md](ATTRIBUTION.md) credits the influences and the techniques.

### Requirements

- macOS 26 or later, a Metal-capable GPU, and a Swift 6 toolchain. Apple platforms only, by design: iOS and visionOS are future targets, and Linux, Windows, and the web are out of scope.

### Versioning from here

- Tags begin at 0.1.0. A breaking change or a new feature bumps the minor, a fix bumps the patch, and each release names its breaking renames in this file. Deprecation shims and a settled surface arrive at 1.0. Until then, pin `.upToNextMinor(from: "0.1.0")`.

[Unreleased]: https://github.com/eaviles/Ollin/compare/0.1.0...HEAD
[0.1.0]: https://github.com/eaviles/Ollin/releases/tag/0.1.0
