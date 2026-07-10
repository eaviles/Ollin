# Ollin

**Motion-first creative coding for Swift, rendered with Metal.**

*Ollin* (OH-leen) is the Aztec glyph for **movement**, the 17th day sign of the calendar, and the name says what the framework is about: in Ollin, sketches **move by default**. The draw loop runs continuously at the display's refresh rate from the very first line of code, so animation is never something you switch on; `noLoop()` is the rare still-image escape hatch. The API borrows the friendly `setup()`/`draw()` feel of [p5.js](https://p5js.org), the typed core of [OPENRNDR](https://openrndr.org), and the simple structure of [openFrameworks](https://openframeworks.cc), reimplemented in Swift idioms rather than ported (see [Influences & attribution](#influences--attribution)).

- **Platform:** macOS 26+, Swift 6+; Apple platforms only, [by design](#why-apple-only)
- **Rendering:** Metal, built on Foundation / SwiftUI / MetalKit / simd; no package dependencies, just a little vendored source ([details](ATTRIBUTION.md#bundled-third-party-code))
- **License:** MIT
- **Built with:** an AI coding assistant (Claude) under [@eaviles](https://github.com/eaviles)'s direction; see [Built with AI](#built-with-ai)

> **Status: alpha, pre-1.0, built in public.** Everything documented below runs today, but the project is young: names and APIs still change between commits, and there's no stability or support guarantee yet. See [Status & contributing](#status--contributing).

## Features

- **Motion by default.** `draw()` runs at the display's refresh rate from the first line, so `120 + sin(time) * 40` is already an animation, and `time`, `frameCount`, and `deltaTime` are ready in every sketch.
- **Live reload.** `swift run OllinLive Sketch.swift` watches the file and hot-swaps each save into the running window; a typo never closes it. `@Param` properties become typed inspector controls (sliders, steppers, toggles, menus, color wells) in grouped cards, and they keep their values across reloads.
- **Live coding on stage.** `swift run OllinLiveCoding` is a performance instrument: the sketch fills the window, the code rides over it as translucent text, and ⌘↩ recompiles the buffer mid-motion, with the clock and tuned knobs carrying across the swap. A typo shows as a strip at the bottom while the last good sketch keeps playing.
- **A Metal core.** Most shapes render as analytic signed-distance fields (one instanced quad each, so thousands of moving shapes stay cheap), strokes carry their own anti-aliasing fringe, and every frame composites in linear light with HDR tone-mapping, dithered output, and up to 8× MSAA.
- **A deep 2D catalog.** Some thirty shapes from circles to stars to hearts, curved paths, concave and holed fills, shape booleans and offsets, gradient paint on everything, blend modes, and `noClear()` accumulation for long-exposure looks.
- **Shapes that merge.** SDF combinators: smooth union, subtract, morph, machined joints and carpentry detailing (chamfer, stairs, columns, engrave/groove/tongue), and domain mirror/tile/radial via `drawSDF`, a scoped `smoothUnion { }` block, or the clay-like `sculpt { }` block (`add()`/`carve()`/`blend()` as live state), in 2D and in raymarched 3D with shadows; the 3D side sculpts too, with twist, bend, surface displacement, and free-point armature strokes.
- **Generative geometry.** Voronoi and Delaunay, Poisson-disk scatter, circle and shape packing, L-systems, differential growth, Wave Function Collapse, flow-field streamlines, boids flocking, Truchet tiles, and strange attractors.
- **Layered effects.** Off-screen layers with fifty-plus GPU filters (bloom, halftone, glitch, oil paint, …), two-layer combines (mask, displace, depth-of-field, ambient occlusion, screen-space reflections), feedback layers, and GPU simulation fields (reaction-diffusion, Game of Life, real-time fluid), all declarable as one `compose { }` block.
- **Your own shaders.** Write a `shade(uv, info)` fragment function, inline or in a hot-reloading `.metal` file, and run it as a generator, filter, or blend, with a built-in helper library and compile errors reported at your own line numbers. Or skip the Metal and *chain*: `Visual` composes oscillators, noise, shapes, and layers through warps, blends, and modulations, one GPU pass however deep the chain grows.
- **GPU compute.** A million particles updated and drawn each frame without touching the CPU, plus ping-pong texture simulations drawn as images.
- **Opt-in 3D.** Orbit and cinematic cameras, a solid-primitive catalog plus meshes from file (OBJ, glTF, USDZ, …), point clouds, stylized and physically-based materials, image-based lighting from bundled HDRIs or a procedural sky, soft shadows, and ray-traced reflections and shadows on RT GPUs. A 2D sketch never pays for any of it.
- **Text and color.** Bitmap, outline, and single-line plotter fonts through one `drawText`, text as vector `Shape`s, OKLab color mixing, palettes, colormaps, and gradients.
- **Computer vision.** Sixteen on-device trackers over the Mac's camera or any video: face, hand, and body pose (2D and 3D), segmentation, contours, optical flow, OCR, saliency, and custom Core ML models.
- **An iPhone as a sensor array.** LiDAR depth clouds, ARKit body and face capture, person segmentation, and device motion, streamed to the Mac over USB by Ollin's own capture app.
- **Sound and control.** FFT audio analysis with band and beat detection, MIDI and OSC in and out (all bindable to `@Param` knobs), and motion locked to MIDI clock so a set runs on the DJ's tempo.
- **Physics.** A stepped `World` with Verlet particles and springs on the soft side, and Box2D bodies, colliders, and joints on the rigid side.
- **Plays in your rig.** Syphon out and in, a system-wide virtual camera any webcam app can read, and video playback as live GPU textures.
- **Export everything.** Headless PNG stills and deterministic sequences, MP4 and GIF straight from the CLI, and vector SVG and PDF (with optional hatched fills) for pen plotters and true-to-size print.

## Hello, circle

```swift
import Ollin

final class HelloCircle: Sketch {
    override func setup() {
        // optional one-time setup
    }

    override func draw() {
        background(.white)
        noFill()
        stroke(.black)
        strokeWeight(3)
        drawCircle(width / 2, height / 2, 120 + sin(time) * 40)
    }
}

OllinApp.run(HelloCircle())
```

That's the whole program: a black circle outline, breathing on a white canvas. There's no call to start the animation, because the draw loop is already running, and `time` (seconds since start) is ready to use. Delete `+ sin(time) * 40` and you have a still circle.

## Run it

From the terminal, no Xcode required:

```sh
swift run Example-Basic-HelloCircle
```

That builds the package and opens a window with the breathing circle above. More runnable sketches live in [`Examples/`](Examples/); `swift run` with no argument lists every example target, and `swift run OllinExamples` opens a gallery with all of them in a sidebar.

The canvas is 1080×1080 by default, previewed fit to your screen. `canvasSize` sets the resolution a sketch renders and exports at, and `windowMode` sizes the preview window; the [Canvas](Docs/Core/Canvas.md) page covers the presets and how to write resolution-independent sketches.

## Install

Add Ollin to your own package:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/eaviles/Ollin.git", branch: "main")
],
targets: [
    .executableTarget(
        name: "MySketch",
        dependencies: [.product(name: "Ollin", package: "Ollin")]
    )
]
```

## Live reload

In creative coding, the speed of the edit-then-see cycle matters more than almost anything. Run a sketch once and keep editing it; on each save, Ollin recompiles that one file and swaps it into the running window:

```sh
swift run OllinLive Examples/Basic/HelloCircle/Sketch.swift
```

The window never closes: if an edit doesn't compile, the error prints and the old sketch keeps running. Each reload starts the sketch fresh by default; pass `--keep-clock` to carry `time` and `frameCount` across so an animation doesn't jump back to the start (there's also an `onReload()` hook). For a heavy sketch, `Scripts/OllinLive` runs the host in release while saves stay fast, since only the sketch file recompiles.

The same engine also powers a performance instrument, [OllinLiveCoding](Docs/Tools/LiveCoding.md): one fullscreen-able window where the code shows over the visuals for the audience and ⌘↩ evaluates the buffer in place, with the clock and tuned `@Param` knobs carrying across each swap. Where OllinLive is the development loop (your editor, a file watcher), OllinLiveCoding is the on-stage one (the editor in the window, evaluate on command).

Other ways to iterate: tweak and re-run an example (`swift run Example-Motion-Breathing`; incremental builds keep it snappy), or open the package in Xcode (`open Package.swift`) for ⌘R, breakpoints, and the debugger. Single-file scripts, so one `.swift` file doubles as a runnable sketch, are on the [roadmap](ROADMAP.md).

## Export

Any sketch renders headlessly, no window needed. Stills, deterministic PNG sequences, video, GIF, and vector SVG and PDF all hang off the same run command:

```sh
swift run Example-Basic-HelloCircle --export frame.png --frame 120
swift run Example-Motion-Breathing --export-sequence frames/ --seconds 20 --fps 60
swift run Example-Motion-Breathing --export-video breathing.mp4 --seconds 6
swift run Example-Motion-Breathing --export-gif breathing.gif --seconds 4
swift run Example-Basic-HelloCircle --export-svg still.svg   # vector, for pen plotters
swift run Example-Basic-HelloCircle --export-pdf still.pdf   # vector, for print (paper-size presets)
swift run OllinLive MySketches/Loop.swift --export-gif loop.gif --seconds 4   # a loose file, same flags
```

Sequence, video, and GIF exports advance the clock at a fixed timestep rather than wall-clock, so a slow render still plays back smoothly. In code they're `OllinApp.export`, `exportSequence`, `exportVideo`, and `exportGIF`. Codec and quality dials, the `--skip` warmup, GIF sizing, and the plotter-oriented `--hatch` fills are all in [`Docs/Output/Export.md`](Docs/Output/Export.md).

A seeded sketch is a generator, so Ollin names the seed each run grew from (`variation`) and gives you the tools to explore the space it indexes: step, roll, or jump through seeds from the inspector's Variation card, proof a whole range as a labeled contact sheet, then re-render the keeper at full size.

```sh
swift run Example-Randomness-Variations --export-grid sheet.png --seeds 25  # proof 25 variations
swift run Example-Randomness-Variations --export keeper.png --seed 10       # render the one you liked
```

## Documentation

New to creative coding, or to Ollin? [The Guide](Guide/README.md) is a practical, book-length introduction taught through Ollin, written for programmers with no math or graphics background and filled in chapter by chapter. Start at [Chapter 1: Hello, Ollin](Guide/01-HelloOllin.md).

The full API reference lives in [`Docs/`](Docs/), one page per topic; [`Docs/README.md`](Docs/README.md) is the annotated index. Most of it ships with the core `import Ollin`; ten satellite libraries live in the same package behind their own `import` (shown on each page), so a sketch links only what it uses.

- **Core** - [Sketch](Docs/Core/Sketch.md), [Canvas](Docs/Core/Canvas.md), [Variations](Docs/Core/Variations.md), [Input](Docs/Helpers/Input.md), [Parameters](Docs/Helpers/Parameters.md), [Math](Docs/Helpers/Math.md), [Animation](Docs/Helpers/Animation.md)
- **Drawing** - [Drawing](Docs/Drawing/Drawing.md), [Color](Docs/Drawing/Color.md), [Geometry](Docs/Drawing/Geometry.md), [SVG import](Docs/Drawing/SVG.md), [Fourier epicycles](Docs/Drawing/Epicycles.md), [Shape morphing](Docs/Drawing/Morphing.md), [Images](Docs/Drawing/Images.md), [Text](Docs/Drawing/Text.md), [Accumulation](Docs/Drawing/Accumulation.md), [HDR & tone-mapping](Docs/Drawing/HDR.md), [Layered effects](Docs/Drawing/Effects.md), [SDF combinators](Docs/Drawing/Combinators.md), [Voronoi & Delaunay](Docs/Drawing/Voronoi.md), [Truchet tiling](Docs/Drawing/Truchet.md), [Strange attractors](Docs/Drawing/Attractors.md)
- **Shaders & compute** - [Shaders](Docs/Shaders/Shaders.md), [Visual chains](Docs/Shaders/Visuals.md), [Shader library](Docs/Shaders/ShaderLibrary.md), [Compute & GPU particles](Docs/Shaders/Compute.md)
- **Generators** - [Random](Docs/Generators/Random.md), [Noise](Docs/Generators/Noise.md), [Blue noise](Docs/Generators/BlueNoise.md), [Circle packing](Docs/Generators/Packing.md), [Shape packing](Docs/Generators/ShapePacking.md), [L-systems](Docs/Generators/LSystem.md), [Differential growth](Docs/Generators/DifferentialGrowth.md), [Wave Function Collapse](Docs/Generators/WaveFunctionCollapse.md), [Flow fields](Docs/Generators/FlowField.md), [Flocking](Docs/Generators/Boids.md), [Steering](Docs/Generators/Steering.md), [Space colonization](Docs/Generators/SpaceColonization.md), [Diffusion-limited aggregation](Docs/Generators/DiffusionLimitedAggregation.md)
- **3D** - [3D](Docs/3D/3D.md), [Combining 3D features](Docs/3D/Combining.md), [Camera control](Docs/3D/Camera.md), [Depth compositing](Docs/3D/DepthCompositing.md), [Record3D](Docs/3D/Record3D.md), [RGBD](Docs/3D/RGBD.md), [Phone](Docs/3D/Phone.md)
- **Sound & simulation** - [Audio](Docs/Helpers/Audio.md), [Physics](Docs/Simulation/Physics.md)
- **Vision & video** - [Vision](Docs/Vision/Vision.md), [Video](Docs/Video/Video.md)
- **Integration** - [OSC](Docs/Integration/OSC.md), [MIDI](Docs/Integration/MIDI.md), [Syphon](Docs/Integration/Syphon.md), [Virtual camera](Docs/Integration/VirtualCamera.md)
- **Output** - [Export](Docs/Output/Export.md), [Print separations](Docs/Output/PrintSeparations.md)
- **Tools** - [Live coding](Docs/Tools/LiveCoding.md)

New to Swift? The [Swift quick reference](Docs/Swift.md) teaches just enough of the language to be productive in `draw()`, and the Guide's [Appendix A](Guide/A-JustEnoughSwift.md) is its slower, narrative companion. Coming from p5.js or Processing? [Appendix C of the Guide](Guide/C-ComingFromP5.md) maps the API you already know onto Ollin.

Coordinates use a top-left origin with y increasing downward, the same as p5, Processing, and OPENRNDR.

## How it works

`Sketch.draw()` calls the bare drawing functions, which forward to a `Drawer`
state machine. Most primitives (circles, ellipses, rectangles, lines, circular
arcs, and a broad catalog of analytic shapes) take a signed-distance-field path:
one quad each, with fill, stroke, and anti-aliasing computed analytically in the
fragment shader, so thousands of them stay cheap.
The rest (polygons, polylines, and elliptical arcs) are tessellated into
triangles in sketch-space points. The `Drawer` records both into call-ordered batches; once a frame,
`MetalRenderer` uploads them and issues a draw per batch (the triangle pipeline,
or the instanced-SDF one), so shapes composite in the order you drew them. A
vertex shader maps points to clip space (flipping Y), and MSAA (8× where the
GPU supports it) covers the triangle path. The renderer is heavily commented because you'll be extending it.

For how the larger systems work inside (the frame lifecycle, the screen-space effects, the SDF combinators, and more as they're written up), see [`ARCHITECTURE.md`](ARCHITECTURE.md).

## Why Apple-only

p5.js, OPENRNDR, and openFrameworks run everywhere; Ollin only runs on Apple hardware, and that's the trade it makes on purpose. Sitting directly on Metal means the rendering ceiling is whatever the GPU can do, and staying native puts the rest of the platform in reach: vision on the Neural Engine and an iPhone's depth sensors feeding a sketch the Mac renders are already here (the docs above cover them); ARKit, visionOS, and AR are still ahead (the [roadmap](#roadmap) has them). The point is that the core is built to grow into those things rather than get retrofitted. The same trade rules out a browser version: the web has no Metal, so a web build would mean a second, lesser renderer on WebGPU; sharing a piece happens by exporting it (video, GIF, USDZ, SVG, PDF), not by running Ollin in a tab.

## Roadmap

The full roadmap lives in [`ROADMAP.md`](ROADMAP.md): what's planned, what's being explored, and the best first contributions, with the engineering thinking behind each item in [`DESIGN-NOTES.md`](DESIGN-NOTES.md). The short version of what's ahead: more of the iPhone sensor array and the 3D mode (scene import, a photorealism tier), generative geometry and a growing catalog of creative-coding technique helpers (fractals, agent simulations), a richer audio and synthesis layer, new input and output surfaces (screen capture, haptics, screen-saver and wallpaper export), GPU-driven rendering and wider-gamut color, editor tooling, a project generator, learning materials and a third-party extension ecosystem, and eventually iOS, visionOS, and AR.

## Built with AI

Ollin is [@eaviles](https://github.com/eaviles)'s project. The motion-first idea, the decisions about what belongs in the framework, and the responsibility for it are his. The code is written with an AI coding assistant (Claude) that proposes APIs and implements them, which @eaviles reviews, reworks, or rejects. A fair description: Claude does much of the proposing and most of the typing, and @eaviles does the deciding.

It's worth saying plainly, because the creative-coding community has good reasons to be careful about AI. A few specifics about how Ollin uses it:

- **It's a tool for making art.** The AI helped build the framework's plumbing. It has no hand in the work you make with Ollin, and no scraped images, training data, or generated artwork go into it. Ollin is not a generative-art model.
- **Influences are credited, licenses respected.** Ollin borrows the feel and vocabulary of p5.js, OPENRNDR, and openFrameworks while writing its own implementation. Ported example sketches name their source, author, and license in the file. See [Influences & attribution](#influences--attribution).
- **A person is accountable.** Bugs, design mistakes, and licensing questions are @eaviles's to answer. Scrutiny is welcome, so please [open an issue](https://github.com/eaviles/Ollin/issues).

The work people make with it is the real test.

## Influences & attribution

Ollin is inspired by [p5.js](https://p5js.org) (LGPL-2.1), [OPENRNDR](https://openrndr.org) (BSD-2-Clause), and [openFrameworks](https://openframeworks.cc) (MIT): it borrows their ideas and API vocabulary and writes its own implementation, so none of their licenses attach and Ollin stays MIT. The same rule runs through everything else it learns from: each published technique a helper reimplements (Quilez's distance fields, Reynolds' boids, Stam's fluids, and many more) is credited to its source, and ported example sketches name their source, author, and license in the file header.

The full record lives in [`ATTRIBUTION.md`](ATTRIBUTION.md): the framework influences, the Swift + Metal engineering references, the technique behind each helper, and the small amount of vendored third-party source. Every bundled component's license is also collected in [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md); Ollin's own code stays MIT.

## Status & contributing

Ollin is **alpha and pre-1.0**, developed in the open. Practically, that means:

- **The API will change.** Names, signatures, and structure can shift between commits; there's no tagged release or SemVer guarantee until 1.0.
- **No support guarantee.** This is built nights and weekends. Issues and discussions get read, but a response time isn't promised.
- **macOS 26+ and a Metal-capable GPU are required.** That's the trade described up top, not a gap to be filled later: no Linux or Windows path, by design.

That said, contributions and ideas are genuinely welcome. [`ROADMAP.md`](ROADMAP.md) is the best source of bite-size work; its [Up next](ROADMAP.md#up-next) section maps onto small, self-contained pull requests. For anything larger, please open an issue to discuss it before sending a big change. To get your bearings before touching one of the bigger systems, [`ARCHITECTURE.md`](ARCHITECTURE.md) explains how they work inside (and [`DESIGN-NOTES.md`](DESIGN-NOTES.md) covers the intent behind what's still planned).
