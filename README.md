# Ollin

**A comprehensive creative-coding framework for Swift, rendered with Metal.**

[Guide](Guide/README.md) · [Docs](Docs/README.md) · [Examples](Examples/) · [Roadmap](ROADMAP.md) · [Architecture](ARCHITECTURE.md)

Ollin is the whole creative-coding toolkit as one typed Swift API. The techniques you reach for are already in it, from Voronoi and L-systems to raymarched signed-distance fields, GPU fluids, and on-device computer vision. The renderer sits directly on Metal and composites in linear light. The tooling around it, live reload and a typed parameter inspector and deterministic headless export, is built for finishing work rather than demoing it.

The API borrows the friendly `setup()`/`draw()` feel of [p5.js](https://p5js.org), the typed core of [OPENRNDR](https://openrndr.org), and the simple structure of [openFrameworks](https://openframeworks.cc), reimplemented in Swift idioms rather than ported (see [Influences & attribution](#influences--attribution)). *Ollin* (OH-leen) is the Aztec glyph for movement, the seventeenth day sign of the calendar.

- **Platform:** macOS 26+, Swift 6+; Apple platforms only, [by design](#why-apple-only)
- **Rendering:** Metal, built on Foundation / SwiftUI / MetalKit / simd; no package dependencies, just a little vendored source ([details](ATTRIBUTION.md#bundled-third-party-code))
- **License:** MIT
- **Built with:** an AI coding assistant (Claude) under [@eaviles](https://github.com/eaviles)'s direction; see [Built with AI](#built-with-ai)

> **Status: alpha, pre-1.0, built in public.** The rendering, the color, and the output are production-grade. The API is not frozen yet. Everything documented below runs today, but names and signatures still change between commits, and there's no stability or support guarantee. See [Status & contributing](#status--contributing).

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

That builds the package and opens a window with the breathing circle above. More runnable sketches live in [`Examples/`](Examples/), where `swift run` with no argument lists every example target and `swift run OllinExamples` opens a gallery with all of them in a sidebar.

The canvas is 1080×1080 by default, previewed fit to your screen. `canvasSize` sets the resolution a sketch renders and exports at, and `windowMode` sizes the preview window. The [Canvas](Docs/Core/Canvas.md) page covers the presets and how to write resolution-independent sketches.

### Install

To use Ollin from your own package:

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

A sketch doesn't need a package at all, though. One loose `.swift` file is a whole sketch: see [Single-file sketches](Docs/Tools/SingleFile.md), or the [Live reload](#live-reload) section below.

## Why Ollin exists

<!--
  PLACEHOLDER: @eaviles to write. Target 150-250 words, three short paragraphs.
  Delete the visible placeholder line below when this is filled in.

  Prompts to answer:
    - What were you making when you hit the wall, and what actually stopped you?
    - Was there a specific moment? A piece you couldn't finish, an export you lost,
      a set that broke mid-performance.
    - What did you get tired of rebuilding?
    - Why Swift, when you already had a working practice somewhere else?
    - Who else do you picture using this?

  Decisions already in the repo that this section can point at, since each one
  only gets made by someone solving a real problem:
    - plotter SVG with hatching, riso separations, true-to-size PDF
        -> the work is meant to end up on paper
    - Syphon both directions, a virtual camera, MIDI clock sync, the live-coding host
        -> the work gets performed, inside a rig other people already run
    - seeds recorded in every export, contact sheets, reproducibility recipes
        -> a good result is worthless if you can't get it back
    - the sheer breadth of the technique catalog
        -> tired of reimplementing the same things before starting
    - sixteen vision trackers and a custom iPhone capture app
        -> the room belongs in the work

  Voice: written as the one first-person section on the page (everything else is
  third person). End it with a short signed line so the shift reads as deliberate.
  If you'd rather keep the whole page third person, rewrite as "@eaviles built..."
  and drop the signature.
-->

> **[Placeholder: the origin story goes here.]**

## What's in it

Coverage is the point. Whatever you reach for is already here, in one typed API, with the same conventions throughout.

- **Built to finish work.** Every frame composites in linear light with HDR tone-mapping, dithered output, analytic anti-aliasing, and up to 8× MSAA. Color is OKLab with real gamut mapping, not HSB approximations. Exports are deterministic and carry a reproducibility recipe: the seed, the parameter values, the commit. Rendering is snapshot-tested against committed reference images.
- **The edit-to-see loop is instant.** `swift run OllinLive Sketch.swift` watches the file and hot-swaps each save into the running window, and a typo never closes it. `@Param` properties become typed inspector controls (sliders, steppers, toggles, menus, color wells) in grouped cards, and they keep their values across reloads.
- **Live coding on stage.** `swift run OllinLiveCoding` is a performance instrument: the sketch fills the window, the code rides over it as translucent text, and ⌘↩ recompiles the buffer mid-motion, with the clock and tuned knobs carrying across the swap. A typo shows as a strip at the bottom while the last good sketch keeps playing.
- **A Metal core with no ceiling.** Most shapes render as analytic signed-distance fields (one instanced quad each, so thousands of moving shapes stay cheap), strokes carry their own anti-aliasing fringe, frames composite through an [HDR float pipeline](Docs/Drawing/HDR.md), and when you outgrow the built-ins you write your own fragment shader or compute kernel without leaving the framework.
- **Motion is the default, and it's handled.** `draw()` runs at the display's refresh rate from the first line, so `120 + sin(time) * 40` is already an animation. Underneath that sits a real motion layer: frame-rate-independent easing and springs, keyframe timelines, input smoothing, noise that closes exactly over a lap, perfect-loop export, and motion locked to MIDI clock.
- **Output that leaves the screen.** Headless PNG stills and deterministic sequences, MP4 and GIF straight from the CLI, vector SVG and PDF with optional hatched fills for pen plotters, and [print separations](Docs/Output/PrintSeparations.md) with a real ink model for riso and screen printing.

### The catalog

Everything below ships in this repository, first-party, with consistent conventions. Each row links to its reference page.

| Area | What's in it |
| --- | --- |
| [**Shapes & geometry**](Docs/Drawing/Drawing.md) | Some thirty analytic shapes from circles to stars to hearts, curved paths, concave and holed fills, variable-width strokes that taper and turn like a nib, [marks](Docs/Drawing/Marks.md) whose width and opacity follow how fast and how hard you drew them, [booleans and offsets](Docs/Drawing/Geometry.md), [gradient paint](Docs/Drawing/Geometry.md) on everything, blend modes, clipping, [SVG import](Docs/Drawing/SVG.md), `noClear()` [accumulation](Docs/Drawing/Accumulation.md) for long-exposure looks, and [retained batches](Docs/Drawing/Batches.md) when static content gets heavy |
| [**Shapes that merge**](Docs/Drawing/Combinators.md) | SDF combinators: smooth union, subtract, morph, machined joints, carpentry detailing, domain mirror/tile/radial, via `drawSDF`, a scoped `smoothUnion { }` block, or the clay-like `sculpt { }` block. In 2D and in raymarched 3D, where the same fields twist, bend, and take surface displacement |
| [**Generative technique**](Docs/README.md) | [Voronoi and Delaunay](Docs/Drawing/Voronoi.md), [Poisson-disk scatter](Docs/Generators/BlueNoise.md), [low-discrepancy sampling](Docs/Generators/LowDiscrepancy.md), [circle](Docs/Generators/Packing.md) and [shape packing](Docs/Generators/ShapePacking.md), [stippling](Docs/Generators/Stippling.md), [L-systems](Docs/Generators/LSystem.md), [differential growth](Docs/Generators/DifferentialGrowth.md), [space colonization](Docs/Generators/SpaceColonization.md), [diffusion-limited aggregation](Docs/Generators/DiffusionLimitedAggregation.md), [Wave Function Collapse](Docs/Generators/WaveFunctionCollapse.md), [flow fields](Docs/Generators/FlowField.md), [boids](Docs/Generators/Boids.md) and [steering](Docs/Generators/Steering.md), [force-directed graph layout](Docs/Generators/ForceLayout.md), [random walks](Docs/Generators/Walks.md), [Truchet](Docs/Drawing/Truchet.md), [hex and triangle grids](Docs/Drawing/Tiling.md), subdivision, mazes, the Apollonian gasket, [aperiodic tilings](Docs/Drawing/AperiodicTilings.md) (Penrose, Wang, girih star patterns, the spectre), [strange attractors](Docs/Drawing/Attractors.md), [chaotic maps and bifurcation diagrams](Docs/Generators/Bifurcation.md), [fractals](Docs/Generators/Fractals.md) (IFS, flames, inversion and Kleinian limit sets), [cellular automata](Docs/Generators/CellularAutomata.md), [classic curves](Docs/Drawing/Curves.md), [Fourier epicycles](Docs/Drawing/Epicycles.md), [shape morphing](Docs/Drawing/Morphing.md), [single-line TSP renderings](Docs/Generators/SingleLine.md), [spanning-tree renderings](Docs/Generators/SpanningTree.md), [isolines](Docs/Generators/Isolines.md) (marching squares), [isosurfaces and metaballs](Docs/Generators/Isosurface.md) (marching cubes), [subdivision surfaces](Docs/Generators/SubdivisionSurfaces.md) (Catmull-Clark and Loop), [concave hulls and alpha shapes](Docs/Generators/Hulls.md), [medial-axis skeletons](Docs/Generators/MedialAxis.md), [straight skeletons and mitered insets](Docs/Generators/StraightSkeleton.md), [paper marbling](Docs/Generators/Marbling.md), [generative watercolor](Docs/Generators/Watercolor.md), [Chladni figures](Docs/Generators/Chladni.md), [terrain and erosion](Docs/Generators/Terrain.md), and seedable [randomness](Docs/Generators/Random.md) |
| [**Layered effects**](Docs/Drawing/Effects.md) | Off-screen layers with fifty-plus GPU filters, two-layer combines (mask, displace, depth of field, ambient occlusion, screen-space reflections), feedback layers, and GPU simulation fields, all declarable as one `compose { }` block |
| [**Your own shaders**](Docs/Shaders/Shaders.md) | Write a `shade(uv, info)` fragment function inline or in a hot-reloading `.metal` file, with compile errors reported at your own line numbers and a [built-in helper library](Docs/Shaders/ShaderLibrary.md) spliced in. Or skip the Metal and chain: [`Visual`](Docs/Shaders/Visuals.md) composes oscillators, noise, shapes, and layers through warps, blends, and modulations, in one GPU pass however deep it grows |
| [**GPU compute**](Docs/Shaders/Compute.md) | A million particles updated and drawn each frame without touching the CPU, a cooperative neighbor-search primitive underneath [artificial life](Docs/Simulation/ArtificialLife.md) and SPH fluids, and ping-pong texture simulations drawn as images |
| [**3D**](Docs/3D/3D.md) (opt-in) | Orbit and [cinematic cameras](Docs/3D/Camera.md), a solid-primitive catalog plus meshes from file (OBJ, glTF, USDZ), point clouds, stylized and physically based materials, image-based lighting from bundled HDRIs or a procedural sky, soft shadows, and ray-traced reflections on RT GPUs. 2D drawing sits inside the depth buffer via [depth compositing](Docs/3D/DepthCompositing.md), and [Combining 3D features](Docs/3D/Combining.md) covers how the pieces stack. A 2D sketch never pays for any of it |
| [**Simulation & physics**](Docs/Simulation/Physics.md) | A stepped `World` with Verlet particles and springs on the soft side, Box2D bodies and joints on the rigid side, plus [SPH fluids and soft bodies](Docs/Simulation/Fluids.md), reaction-diffusion, Lenia, Game of Life, water-surface ripples, multi-scale Turing patterns, the Abelian sandpile, and real-time fluid on the GPU, and [articulated and chaotic motion](Docs/Simulation/Motion.md) for IK chains, pendulums, and n-body gravity |
| [**Perception**](Docs/Vision/Vision.md) | Sixteen on-device trackers over the Mac's camera or any [video](Docs/Video/Video.md): face, hand, and body pose in 2D and 3D, segmentation, contours, optical flow, OCR, saliency, and custom Core ML models. An [iPhone](Docs/3D/Phone.md) extends that with LiDAR depth clouds, ARKit body and face capture, and device motion over USB, live or from [recorded clips](Docs/3D/Record3D.md), all as metric [RGBD frames](Docs/3D/RGBD.md) |
| [**Sound & control**](Docs/Helpers/Audio.md) | FFT analysis with band and beat detection, [MIDI](Docs/Integration/MIDI.md) and [OSC](Docs/Integration/OSC.md) in and out (bindable to `@Param` knobs), and tempo sync so a set runs on the DJ's clock |
| [**Text & color**](Docs/Drawing/Text.md) | Bitmap, outline, and single-line plotter fonts through one `drawText`, text as vector `Shape`s, [OKLab mixing](Docs/Drawing/Color.md), palette import and extraction, colormaps, gradients, and [images](Docs/Drawing/Images.md) with pixel access, dithering, [pixel sorting](Docs/Drawing/PixelSorting.md), [halftone screens](Docs/Drawing/Halftone.md), and [glyph mosaics](Docs/Drawing/GlyphMosaic.md) |
| **Plays in your rig** | [Syphon](Docs/Integration/Syphon.md) out and in, a system-wide [virtual camera](Docs/Integration/VirtualCamera.md) any webcam app can read, [video playback](Docs/Video/Video.md) as live GPU textures, and [slit-scan time displacement](Docs/Video/SlitScan.md) over any frame history |

## Live reload

In creative coding, the speed of the edit-then-see cycle matters more than almost anything. Run a sketch once and keep editing it, and on each save Ollin recompiles that one file and swaps it into the running window:

```sh
swift run OllinLive Examples/Basic/HelloCircle/Sketch.swift
```

The window never closes. If an edit doesn't compile, the error prints and the old sketch keeps running. Each reload starts the sketch fresh by default, so pass `--keep-clock` to carry `time` and `frameCount` across so an animation doesn't jump back to the start (there's also an `onReload()` hook). For a heavy sketch, `Scripts/OllinLive` runs the host in release while saves stay fast, since only the sketch file recompiles.

The same engine also powers a performance instrument, [OllinLiveCoding](Docs/Tools/LiveCoding.md), a single fullscreen-able window where the code shows over the visuals for the audience and ⌘↩ evaluates the buffer in place, with the clock and tuned `@Param` knobs carrying across each swap. Where OllinLive is the development loop (your editor, a file watcher), OllinLiveCoding is the on-stage one (the editor in the window, evaluate on command).

A sketch doesn't need a package at all. `Scripts/ollin install` puts an `ollin` command on your PATH, and after that one `.swift` file anywhere on disk is a whole sketch:

```sh
ollin new dots.swift        # write a starter sketch
ollin dots.swift            # live window, hot-reload on save
./dots.swift                # the file is directly executable (hashbang + chmod +x)
ollin dots.swift --export-gif dots.gif --seconds 4
```

See [Single-file sketches](Docs/Tools/SingleFile.md) for assets, satellite imports, and growing a file into a package.

There are other ways to iterate. Tweak and re-run an example (`swift run Example-Motion-Breathing`, where incremental builds keep it snappy), or open the package in Xcode (`open Package.swift`) for ⌘R, breakpoints, and the debugger.

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

A seeded sketch is a generator, so Ollin names the seed each run grew from ([`variation`](Docs/Core/Variations.md)) and gives you the tools to explore the space it indexes: step, roll, or jump through seeds from the inspector's Variation card, proof a whole range as a labeled contact sheet, then re-render the keeper at full size.

```sh
swift run Example-Randomness-Variations --export-grid sheet.png --seeds 25  # proof 25 variations
swift run Example-Randomness-Variations --export keeper.png --seed 10       # render the one you liked
```

## Documentation

New to creative coding, or to Ollin? [The Guide](Guide/README.md) is a practical, book-length introduction taught through Ollin, written for programmers with no math or graphics background. Start at [Chapter 1: Hello, Ollin](Guide/01-HelloOllin.md).

The full API reference lives in [`Docs/`](Docs/), one page per topic, and **[`Docs/README.md`](Docs/README.md) is the annotated index**. Most of it ships with the core `import Ollin`, while ten satellite libraries live in the same package behind their own `import` (shown on each page), so a sketch links only what it uses.

Good places to start:

- [Sketch](Docs/Core/Sketch.md) and [Canvas](Docs/Core/Canvas.md), the lifecycle and the drawing surface
- [Drawing](Docs/Drawing/Drawing.md) and [Color](Docs/Drawing/Color.md), the day-to-day API
- [Input](Docs/Helpers/Input.md) and [Math](Docs/Helpers/Math.md), mouse and keys, and the helpers you'll reach for constantly
- [Parameters](Docs/Helpers/Parameters.md), the `@Param` inspector controls
- [Animation](Docs/Helpers/Animation.md) and [Noise](Docs/Generators/Noise.md), the motion and texture layers
- [Layered effects](Docs/Drawing/Effects.md) and [Shaders](Docs/Shaders/Shaders.md), when you go to the GPU
- [3D](Docs/3D/3D.md), the opt-in third dimension
- [Export](Docs/Output/Export.md), getting work out of the window

New to Swift? The [Swift quick reference](Docs/Swift.md) teaches just enough of the language to be productive in `draw()`, and the Guide's [Appendix A](Guide/A-JustEnoughSwift.md) is its slower, narrative companion. Coming from p5.js or Processing? [Appendix C of the Guide](Guide/C-ComingFromP5.md) maps the API you already know onto Ollin.

Coordinates use a top-left origin with y increasing downward, the same as p5, Processing, and OPENRNDR.

## How it works

`Sketch.draw()` calls the bare drawing functions, which forward to a `Drawer` state machine. Most primitives take a signed-distance-field path, one quad each with fill, stroke, and anti-aliasing computed analytically in the fragment shader; the rest tessellate into triangles. The `Drawer` records both into call-ordered batches, and once a frame `MetalRenderer` uploads them and issues a draw per batch, so shapes composite in the order you drew them.

The renderer is heavily commented, because you'll be extending it. For how the larger systems work inside (the frame lifecycle, the screen-space effects, the SDF combinators, and more), see [`ARCHITECTURE.md`](ARCHITECTURE.md).

## Why Apple-only

p5.js, OPENRNDR, and openFrameworks run everywhere, while Ollin only runs on Apple hardware, and that's the trade it makes on purpose.

Sitting directly on Metal means the rendering ceiling is whatever the GPU can do. Staying native puts the rest of the platform in reach: vision on the Neural Engine and an iPhone's depth sensors feeding a sketch the Mac renders are already here, while ARKit, visionOS, and AR are still ahead. The point is that the core is built to grow into those things rather than get retrofitted.

The same trade rules out a browser version, because the web has no Metal, so a web build would mean a second, lesser renderer on WebGPU. Sharing a piece happens by exporting it (video, GIF, USDZ, SVG, PDF), not by running Ollin in a tab.

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

Ollin is inspired by [p5.js](https://p5js.org) (LGPL-2.1), [OPENRNDR](https://openrndr.org) (BSD-2-Clause), and [openFrameworks](https://openframeworks.cc) (MIT), in that it borrows their ideas and API vocabulary and writes its own implementation, so none of their licenses attach and Ollin stays MIT. The same rule runs through everything else it learns from: each published technique a helper reimplements (Quilez's distance fields, Reynolds' boids, Stam's fluids, and many more) is credited to its source, and ported example sketches name their source, author, and license in the file header.

The full record lives in [`ATTRIBUTION.md`](ATTRIBUTION.md): the framework influences, the Swift + Metal engineering references, the technique behind each helper, and the small amount of vendored third-party source. Every bundled component's license is also collected in [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md), and Ollin's own code stays MIT.

## Status & contributing

Ollin is **alpha and pre-1.0**, developed in the open. Two different things are meant by that, and they're worth separating:

- **The output is production-grade.** Linear-light rendering, real anti-aliasing, OKLab color, deterministic and reproducible export, snapshot-tested rendering. Work made with Ollin is meant to be finished and shown.
- **The API is not.** Names, signatures, and structure can shift between commits, and there's no tagged release or SemVer guarantee until 1.0.

Beyond that:

- **No support guarantee.** This is built nights and weekends. Issues and discussions get read, but a response time isn't promised.
- **macOS 26+ and a Metal-capable GPU are required.** That's the trade described up top rather than a gap to be filled later, so there's no Linux or Windows path, by design.

That said, contributions and ideas are genuinely welcome. [`ROADMAP.md`](ROADMAP.md) is the best source of bite-size work, and its [Up next](ROADMAP.md#up-next) section maps onto small, self-contained pull requests. For anything larger, please open an issue to discuss it before sending a big change. To get your bearings before touching one of the bigger systems, [`ARCHITECTURE.md`](ARCHITECTURE.md) explains how they work inside (and [`DESIGN-NOTES.md`](DESIGN-NOTES.md) covers the intent behind what's still planned).
