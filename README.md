# <picture><source media="(prefers-color-scheme: dark)" srcset="Logo/ollin-mark-dark.svg"><img src="Logo/ollin-mark.svg" alt="" height="40" align="top"></picture> Ollin

**A Metal-rendered creative-coding framework for Swift on Apple platforms.**

![Platform: macOS 26+](https://img.shields.io/badge/platform-macOS_26%2B-blue) ![Swift 6.3+](https://img.shields.io/badge/Swift-6.3%2B-F05138?logo=swift&logoColor=white) [![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

[Guide](Guide/README.md) · [Docs](Docs/README.md) · [Examples](Examples/) · [Roadmap](ROADMAP.md) · [Architecture](ARCHITECTURE.md) · [Attribution](ATTRIBUTION.md) · [Contributing](CONTRIBUTING.md)

Ollin is for generative art, live visuals, and installations. A sketch runs on the Mac and on iPhone, written and worked on from the Mac. The techniques are built in: Voronoi and L-systems, raymarched signed-distance fields, GPU fluids, on-device computer vision, and [the rest of the catalog](Docs/README.md#the-catalog). The renderer sits directly on Metal and composites in linear light. The tooling covers the work up to a finished piece: live reload while you edit, a typed parameter inspector for tuning, deterministic headless export for the final render, as a still, a video, a vector file, or a web page.

<img src="https://media.ollin.art/heroes/readme-hero.jpg?v=d4678db0" alt="Thirty-two of the example sketches running at once, from every area of the framework" width="880">

The API borrows the friendly `setup()`/`draw()` feel of [p5.js](https://p5js.org), the typed core of [OPENRNDR](https://openrndr.org), and the simple structure of [openFrameworks](https://openframeworks.cc), reimplemented in Swift idioms rather than ported (see [Influences & attribution](#influences--attribution)). *Ollin* (OH-leen) is the Aztec glyph for movement, the seventeenth day sign of the calendar.

Coming from p5.js or Processing? [Appendix C of the Guide](Guide/C-ComingFromP5.md) maps the API you already know onto Ollin.

- **Platform:** macOS 26+ and Swift 6.3+ (Xcode 26), on any Mac that runs them. Apple platforms only, [by design](#why-apple-only)
- **Rendering:** Metal, built on Foundation / SwiftUI / MetalKit / simd; no package dependencies; the C/C++ libraries it does use (Box2D, Jolt, libtess2, Clipper2, Syphon, and a few smaller pieces) are vendored under `External/` with licenses intact and provenance recorded ([details](ATTRIBUTION.md#bundled-third-party-code))
- **License:** MIT
- **Built with:** an AI coding assistant (Claude) under [@eaviles](https://github.com/eaviles)'s direction; see [Built with AI](#built-with-ai)

> **Status: alpha, pre-1.0, built in public.** The rendering, the color, and the output are production-grade. The API is not frozen yet: names and signatures still change, and there's no stability or support guarantee. [Choose a release or pin a minor version](#install), and read the [changelog](CHANGELOG.md) before upgrading. See [Status & contributing](#status--contributing) for what to expect.

## Hello, circle

```swift
import Ollin

@main
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
```

That's the whole program: a black circle outline, breathing on a white canvas. `@main` boots the window for you, and the draw loop is already running, so there's no call to start the animation, and `time` (seconds since start) is ready to use. Delete `+ sin(time) * 40` and you have a still circle. Or change `width / 2, height / 2` to `mouseX, mouseY` and the circle follows the pointer: `mouseX`, `mouseY`, `mouseIsPressed`, and a `keyPressed()` override are [already on the sketch](Docs/Helpers/Input.md). The shipped `Basic/HelloCircle` is this same sketch, drawn a little larger, with its sizes riding the built-in `scale` factor so they hold at any canvas size.

## Run it

**Before you start:** macOS 26 or later, and Xcode 26 installed for its Swift 6.3+ toolchain. You never have to open Xcode itself. Any Mac that runs macOS 26 has the graphics support Ollin needs. Check the compiler with `swift --version`. The first build compiles the framework from source and may take several minutes; later builds are incremental.

Then, in a terminal:

```sh
git clone https://github.com/eaviles/Ollin.git
cd Ollin
swift run --package-path Examples Example-Basic-HelloCircle
```

You should see a black circle outline breathing on a white canvas. **Try one edit:** close the window, open [`Examples/Basic/HelloCircle/Sketch.swift`](Examples/Basic/HelloCircle/Sketch.swift), change `stroke(.black)` to `stroke(.red)`, and run the last command again. The circle now breathes in red.

More than five hundred runnable sketches live in [`Examples/`](Examples/README.md), grouped by topic. From the repo root, `swift run OllinExamples` opens a gallery with all of them in a sidebar. The [examples' running guide](Examples/README.md#running) covers individual targets and browsing from the terminal.

The canvas is 1080×1080 by default, previewed fit to your screen. `canvasSize` sets the resolution a sketch renders and exports at, and `windowMode` sizes the preview window. The [Canvas](Docs/Core/Canvas.md) page covers the presets and how to write resolution-independent sketches. Coordinates use a top-left origin with y increasing downward, the same as p5, Processing, and OPENRNDR; [Where a point is](Docs/Concepts/Coordinates.md) covers units and other frames.

## Install

### For a standalone sketch

From the clone created above, install the command:

```sh
Scripts/ollin install
```

Follow any `PATH` instruction it prints. Then, in the folder where you keep sketches:

```sh
ollin new dots.swift        # write a starter sketch
ollin dots.swift            # open a live window; edit the file and save to reload
```

Keep the clone: `ollin` links to it and uses its framework version. Its first run builds a release host, so allow a few minutes even if you already ran Hello Circle. To stay on a release rather than the tip, check out the newest tag in that clone, and read the [changelog](CHANGELOG.md) before moving to a later one. [Single-file sketches](Docs/Tools/SingleFile.md) covers assets, extra imports, directly executable files, and growing into a package.

### In an existing Swift package

Add these entries to your `Package.swift`, then put a sketch like [Hello, circle](#hello-circle) in `Sources/MySketch/Sketch.swift` and run `swift run MySketch`:

```swift
// Package.swift
platforms: [
    .macOS("26.0")
],
dependencies: [
    // Pre-1.0: a breaking change bumps the minor, so stay on one minor.
    .package(url: "https://github.com/eaviles/Ollin.git", .upToNextMinor(from: "0.4.0"))
],
targets: [
    .executableTarget(
        name: "MySketch",
        dependencies: [.product(name: "Ollin", package: "Ollin")]
    )
]
```

The `platforms` entry matters: without it SwiftPM targets its oldest macOS default, and the build fails against Ollin's macOS 26 floor. `.upToNextMinor(from: "0.4.0")` accepts 0.4.x fixes and keeps out 0.5.0, where APIs may change. Read the [changelog](CHANGELOG.md) before raising that bound.

## Why Ollin exists

I make sketches in code, mostly for myself. Some months there are a lot of them and some months there are none. Along the way I collected the parts I kept needing: techniques I had read about and written out myself, shaders I copied from one sketch into the next, and small tools for starting a new sketch.

Those parts were spread across several tools. I drew in openFrameworks, shared each window through a browser so I could mix it live in Hydra, and wrote filters in OPENRNDR. In my setup I could only keep four sketches going at once, and what I could do live was whatever that chain allowed. Anything past drawing, a 3D camera for example, meant an add-on maintained on its own schedule, and sometimes I had to get it compiling before I could start. I liked how much of OPENRNDR felt organized and part of one thing.

I wanted that in one native framework: drawing that looks right at full resolution by default, Metal and compute shaders available directly, current Apple hardware supported, and the parts kept working together. I also wanted what p5 has in the browser, where a change shows on screen as soon as you save, instead of a rebuild and a wait. And I wanted to write it in Swift.

Working this way also brings the phone in. Its cameras and its lidar feed a sketch running on the Mac, so the room in front of it, a face, or a pair of hands can drive the drawing, and a sketch can also run on the phone itself.

Ollin is that collection, rewritten as a single framework. I built it for my own work first. It is public because most of what is in it is not specific to me, and because I would like other people drawn to creative coding to learn along with me, collecting examples, writing sketches, and adding to the framework.

## What's in it

All of it is one API with the same conventions throughout.

- **The output is production-grade.** Every frame composites in linear light with HDR tone mapping, dithered output, analytic anti-aliasing, and up to 8× MSAA. Color is OKLab with real gamut mapping, not HSB approximations. Exports are deterministic and carry a reproducibility recipe: the seed, the parameter values, the commit. Rendering is snapshot-tested against committed reference images.

- **Edit, save, see it change.** [Live reload](#live-reload) recompiles just the sketch and swaps it into the running window. Typed `@Param` controls keep their values across reloads, and [dragging a shape](Docs/Tools/DragToEdit.md) changes the numbers in your own source. The inspector also shows [what the frame cost](Docs/Tools/Profiling.md): CPU against GPU, draws, and passes.

- **Live coding on stage.** [OllinLiveCoding](Docs/Tools/LiveCoding.md) puts the code over the visuals for the audience. Evaluate on command, mid-motion, with the clock and tuned parameters carrying across the swap. A typo leaves the last good sketch playing.

- **A Metal core you can extend.** Most shapes render as analytic signed-distance fields (one instanced quad each, so thousands of moving shapes stay cheap), strokes carry their own anti-aliasing fringe, and frames composite through an [HDR float pipeline](Docs/Drawing/HDR.md). When you outgrow the built-ins, write your own [fragment shader](Docs/Shaders/Shaders.md) or [compute kernel](Docs/Shaders/Compute.md) without leaving the framework.

- **Motion is the default.** `draw()` runs at the display's refresh rate from the first line, so `120 + sin(time) * 40` is already an animation. Under that is a motion layer: frame-rate-independent easing and springs, keyframe timelines, [parameters on their own curves](Docs/Core/Automation.md), input smoothing, noise that closes exactly over a lap, perfect-loop export, and motion locked to MIDI clock.

- **Output that leaves the screen.** [Export](#export) stills, sequences, video, GIF, recorded web pages, or vector SVG and PDF. Physical work has its own formats: [G-code](Docs/Output/GCode.md), [DXF](Docs/Output/DXF.md), [embroidery](Docs/Output/Embroidery.md), [print separations](Docs/Output/PrintSeparations.md) with a real ink model, [press proofing](Docs/Output/PrintColor.md), and [STL, OBJ, and 3MF](Docs/Output/Fabrication.md) at a real size. [Spatial output](Docs/Output/Spatial.md) carries a piece into Quick Look and AR as USDZ, or onto a headset as spatial video.

- **Or running in the system.** The project generator wraps a sketch as a signed [Mac app](Docs/Output/App.md), [screen saver](Docs/Output/ScreenSaver.md), [desktop wallpaper](Docs/Output/Wallpaper.md), or [menu-bar piece](Docs/Output/MenuBar.md). Each comes with a script to build, sign, and install it; the sketch stays ordinary Swift. `ollin phone` runs it on a paired [iPhone or iPad](Docs/Tools/OnThePhone.md), reinstalling on save with its clock and parameters carried across. You can also generate an [iOS app of your own](Docs/Tools/OnThePhone.md#in-an-app-of-your-own).

- **Made to be left running.** [Installation mode](Docs/Output/Installation.md) fills the screen, hides the pointer, and keeps the display awake. The clock survives display sleep and long runs; `@Saved` state survives a relaunch. A watch restarts a crashed piece, a schedule gives it the building's hours, and projection calibration and edge blending fit one canvas across displays or projectors.

Everything above ships in this repository. [The catalog](Docs/README.md#the-catalog) is the full capability map, with a reference page for each area. Beyond drawing and shaders, browse [sixty-six generative techniques](Docs/Generators/README.md), [simulation and physics](Docs/Simulation/README.md), the [opt-in 3D layer](Docs/3D/README.md), [on-device perception](Docs/Vision/Vision.md), [data](Docs/Helpers/Data.md), [sound](Docs/Helpers/Audio.md), and [control surfaces and rig integration](Docs/Integration/README.md).

## Live reload

To keep a window open while you edit, run a sketch through OllinLive from the repo root:

```sh
swift run OllinLive Examples/Basic/HelloCircle/Sketch.swift
```

Save an edit in your editor and Ollin recompiles just that file, then swaps it into the running window. If it doesn't compile, the error shows and the old sketch keeps running. A standalone file started with `ollin dots.swift` uses this same host.

[`@Param` properties](Docs/Helpers/Parameters.md) become typed inspector controls: sliders, steppers, toggles, menus, color wells, palette and gradient strips. They keep their tuned values across reloads. Hold Command over a shape drawn with plain numbers to [move, resize, or rotate it](Docs/Tools/DragToEdit.md); the handles write the new numbers into your source.

Each reload starts the sketch fresh by default. `--keep-clock` carries `time` and `frameCount` across the reload, so an animation doesn't jump back to the start. There is also a `reloaded()` hook. The sketch compiles optimized; `--no-optimize` enables assertions and clearer backtraces for debugging. For a heavy sketch, `Scripts/OllinLive` runs the host in release too.

For a live performance, `swift run OllinLiveCoding` opens the editor over the visuals in one fullscreen-capable window. Press ⌘↩ (Command-Return) to evaluate the buffer, carrying the clock and parameters across the swap. [Live coding](Docs/Tools/LiveCoding.md) covers the stage controls, recovery, and how evaluation differs from saving a file.

When a piece outgrows one file, the [project generator](Docs/Tools/ProjectGenerator.md) makes a folder already wired for what you're about to use:

```sh
ollin new MyPiece --template shader --with audio   # a folder that builds and runs
ollin generate                                     # the same, in a window
```

`ollin generate` shows each starting point by *running* it, so you pick a template by watching it. If you prefer Xcode, open `Examples/Package.swift` for ⌘R (Command-R), breakpoints, and the debugger.

## Export

Any sketch renders headlessly, with no window needed. From the repo root, render a still or a movie of Hello Circle:

```sh
swift run --package-path Examples Example-Basic-HelloCircle --export frame.png --frame 120
swift run --package-path Examples Example-Basic-HelloCircle --export-video breathing.mp4 --seconds 6
```

The same flags work on a standalone sketch created with `ollin new dots.swift`:

```sh
ollin dots.swift --export-gif dots.gif --seconds 4
```

[Export](Docs/Output/Export.md) covers PNG sequences (`--export-sequence`), vector SVG and PDF (`--export-svg`, `--export-pdf`), codecs, quality, warmup, slow motion, and hatched fills for pen plotters. Sequence, video, and GIF exports advance the clock at a fixed timestep, so a slow render still plays back smoothly. In code these are `OllinApp.export`, `exportSequence`, `exportVideo`, and `exportGIF`.

For a [web page](Docs/Output/Web.md), `--export-web` records what the sketch draws and writes a self-contained page or an inline fragment. Shapes and supported shaders play back in WebGL2, with Metal translated to GLSL. This is a recorded export, so a drawing call it cannot carry stops it, and the exporter names that call. A ready-made example:

```sh
swift run --package-path Examples Example-Web-BreathingRing --export-web ring.html
```

A 3D scene can also [trace light paths](Docs/Output/PathTraced.md) for its export. `--path-traced` spends seconds per frame on soft shadows, color bleed, mirror-in-mirror reflections, and a lens model, from the same sketch you tune live.

To keep or direct a performance:

- **Record a movie.** ⌘⇧R (Command-Shift-R) in the live hosts, `--record` on OllinLive, or `startRecording()` in a sketch captures the picture and the sketch's or room's sound in real time. Evaluating in the live-coding host does not interrupt it. See [Recording](Docs/Output/Recording.md).
- **Keep a take.** `--record-take take.json` saves the seed, clock, inputs, and parameter moves. `--replay take.json` plays them back with pause, step, and scrub controls, or re-renders them offline through an export flag, even path-traced. Add `--seed` to try the same gestures on another variation. See [Record & replay](Docs/Core/Replay.md).
- **Compose the parameter moves.** [Automation](Docs/Core/Automation.md) puts parameters on keyframed curves, authored in code, in JSON, or in the [timeline panel](Docs/Tools/Timeline.md). A [formula](Docs/Helpers/Formula.md) sets a parameter from a rule such as `190 + sin(time * tau / 6) * 80`. Both read the sketch clock and render frame for frame.

To explore a seeded sketch, the inspector's [Variation card](Docs/Core/Variations.md) steps, rolls, or jumps through seeds. Or proof a range as a contact sheet, then render the one you keep at full size:

```sh
swift run --package-path Examples Example-Randomness-Variations --export-grid sheet.png --seeds 25
swift run --package-path Examples Example-Randomness-Variations --export keeper.png --seed 10
```

To hand over a piece that keeps running, follow [Sharing and performing](Guide/31-SharingAndPerforming.md) for app bundles and other output surfaces, or [Installations](Guide/32-Installations.md) for work left on a wall. A loose file runs in installation mode with `ollin dots.swift --installation`; that gives it its own window and runs the code it started with, without reloading on save.

## Documentation

[The Guide](Guide/README.md) is a practical, book-length introduction for anyone new to creative coding or to Ollin. It is taught through Ollin and written for programmers with no math or graphics background. Start at [Chapter 1: Hello, Ollin](Guide/01-HelloOllin.md).

The full API reference lives in [`Docs/`](Docs/), with one page per topic, and **[`Docs/README.md`](Docs/README.md) is the annotated index**: [the catalog](Docs/README.md#the-catalog) by capability first, then every page by area with one line on each. Most of the API ships with the core `import Ollin`. The satellite libraries live in the same package behind their own `import`, shown on each page, so a sketch links only what it uses.

Between the guide and the reference sits a short set of [concept pages](Docs/Concepts/README.md). Each is one screen long, for when you want the idea rather than the signature. They are [the frame](Docs/Concepts/Frame.md) (what a drawing call actually does), [where a point is](Docs/Concepts/Coordinates.md), [layers](Docs/Concepts/Layers.md), [what survives a frame](Docs/Concepts/Persistence.md), [why a run repeats](Docs/Concepts/Determinism.md), [light and color](Docs/Concepts/Light.md), and [values and bare calls](Docs/Concepts/Values.md).

Good places to start:

- [Sketch](Docs/Core/Sketch.md) and [Canvas](Docs/Core/Canvas.md), the lifecycle and the drawing surface
- [Drawing](Docs/Drawing/Drawing.md) and [Color](Docs/Drawing/Color.md), the day-to-day API
- [Input](Docs/Helpers/Input.md) and [Math](Docs/Helpers/Math.md), mouse and keys, and the helpers you'll use all the time
- [Parameters](Docs/Helpers/Parameters.md), the `@Param` inspector controls, and [Cues](Docs/Helpers/Cues.md), the looks you saved and call back
- [Data](Docs/Helpers/Data.md), reading a CSV or JSON file to draw from
- [Animation](Docs/Helpers/Animation.md) and [Noise](Docs/Generators/Noise.md), the motion and texture layers
- [Layered effects](Docs/Drawing/Effects.md) and [Shaders](Docs/Shaders/Shaders.md), when you go to the GPU
- [3D](Docs/3D/3D.md), the opt-in third dimension
- [Export](Docs/Output/Export.md), getting work out of the window

If you are new to Swift, the [Swift quick reference](Docs/Swift.md) teaches just enough of the language to be productive in `draw()`. The Guide's [Appendix A](Guide/A-JustEnoughSwift.md) covers the same ground more slowly, as narrative.

You can also read the reference and examples from your checkout without a browser:

```sh
ollin docs color                     # read a reference page
ollin docs --search "long exposure"  # search the reference
ollin examples ocean                 # find an example and its run command
```

[The reference offline](Docs/Tools/Reference.md) covers sections, filters, and reading source. `ollin site` writes the same pages out as a website.

## How it works

`Sketch.draw()` calls the bare drawing functions, and they forward to a `Drawer` state machine. Most primitives take a signed-distance-field path: each one is a single quad, with its fill, stroke, and anti-aliasing computed analytically in the fragment shader. The rest tessellate into triangles. The `Drawer` records both kinds into call-ordered batches. Once a frame, `MetalRenderer` uploads those batches and issues one draw per batch, so shapes composite in the order you drew them.

The renderer is heavily commented, because you will be extending it. For how the larger systems work inside (the frame lifecycle, the screen-space effects, the SDF combinators, and more), see [`ARCHITECTURE.md`](ARCHITECTURE.md).

## Why Apple-only

p5.js, OPENRNDR, and openFrameworks run everywhere. Ollin runs only on Apple hardware, and that is a trade it makes on purpose.

Ollin sits directly on Metal, so the rendering limit is whatever the GPU can do. It stays native, so the rest of the platform is within reach. Vision on the Neural Engine is already here, and so are an iPhone's depth sensors feeding a sketch that the Mac renders. Meanwhile, visionOS and AR are still ahead. The core is built to grow into those things rather than be retrofitted for them.

Every hardware feature is asked for at run time and steps down when it is missing, so an M1 runs everything, tracing rays in software where an M3 and later have dedicated units. A sketch also runs on iOS 26 as an app, [worked on from the Mac](Docs/Tools/OnThePhone.md). There is no Linux or Windows path, by design.

The same trade rules out a browser version. The web has no Metal, so a web build would need a second, lesser renderer on WebGPU. You share a piece by exporting it, not by running Ollin in a tab. The formats are video, GIF, USDZ, SVG, PDF, and a recorded web page.

## Roadmap

The full roadmap lives in [`ROADMAP.md`](ROADMAP.md). It lists what's planned, what's being explored, and the best first contributions. The engineering thinking behind each item is in [`DESIGN-NOTES.md`](DESIGN-NOTES.md). Releases are tagged from 0.1.0 on. The next milestone is version 1.0.0, where the API settles, and the roadmap's [Toward 1.0](ROADMAP.md#toward-10) section tracks what it waits on. Further ahead: more of the iPhone sensor array, more of the 3D mode, more generative geometry, and more of the sound layer. Then new input and output surfaces, editor tooling, learning materials, a third-party extension ecosystem, and a sketch you can write in Swift Playgrounds. Eventually visionOS and AR.

## Built with AI

Ollin is [@eaviles](https://github.com/eaviles)'s project. The motion-first idea, the decisions about what belongs in the framework, and the responsibility for it are his. The code is written with an AI coding assistant (Claude). Claude proposes APIs and implements them, and @eaviles reviews, reworks, or rejects the result. A fair description is that Claude does much of the proposing and most of the typing, and @eaviles does the deciding.

This is worth saying plainly, because the creative-coding community has good reasons to be careful about AI. Here is how Ollin uses it:

- **It's a tool for making art.** The AI helped build the framework itself. It plays no part in the work you make with Ollin. That includes the controls: no model writes a sketch, moves a parameter, or picks a color for you. No AI-generated artwork ships in Ollin, and every bundled asset is credited, licensed human work. The vision examples that use published ML models download them from their own sources, and each model is named and credited in [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md). Ollin is not a generative-art model.
- **Influences are credited, licenses respected.** Ollin borrows the feel and vocabulary of p5.js, OPENRNDR, and openFrameworks, and writes its own implementation. See [Influences & attribution](#influences--attribution).
- **A person is accountable.** Bugs, design mistakes, and licensing questions are @eaviles's to answer. Scrutiny is welcome, so please [open an issue](https://github.com/eaviles/Ollin/issues).

What people make with it is the test that matters. When you make something, show it in [Show and tell](https://github.com/eaviles/Ollin/discussions/categories/show-and-tell).

## Influences & attribution

Ollin is inspired by [p5.js](https://p5js.org) (LGPL-2.1), [OPENRNDR](https://openrndr.org) (BSD-2-Clause), and [openFrameworks](https://openframeworks.cc) (MIT). It borrows their ideas and API vocabulary and writes its own implementation, so none of their licenses attach and Ollin stays MIT. The same rule applies to everything else it learns from. Each published technique that a helper reimplements (Quilez's distance fields, Reynolds' boids, Stam's fluids, and many more) is credited to its source. Ported example sketches name their source, author, and license in the file header.

The full record lives in [`ATTRIBUTION.md`](ATTRIBUTION.md): the framework influences, the Swift + Metal engineering references, the technique behind each helper, and the vendored third-party source. Every bundled component's license is also collected in [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md), and Ollin's own code stays MIT.

## Status & contributing

Ollin is **alpha and pre-1.0**, developed in the open. That means two different things:

- **The output is production-grade.** Work made with Ollin is meant to be finished and shown; rendering is snapshot-tested and exports are reproducible.
- **The API is not frozen.** Names, signatures, and structure still change. Releases follow semantic versioning at major zero: a breaking change or a new feature bumps the minor, and a fix bumps the patch. [Pin `.upToNextMinor` in a package or keep the CLI's checkout on a release tag](#install), and read the [changelog](CHANGELOG.md) when you move up. Deprecation shims and a settled surface are the 1.0 milestone.

This is built nights and weekends, with **no support guarantee**. Issues and [discussions](https://github.com/eaviles/Ollin/discussions) get read, but a response time isn't promised. Report vulnerabilities privately through the process in [`SECURITY.md`](SECURITY.md).

Contributions and ideas are welcome. Start with [`CONTRIBUTING.md`](CONTRIBUTING.md) and the roadmap's [Up next](ROADMAP.md#up-next) section for small, self-contained pull requests. For a larger change, open an issue to discuss it first. The [code of conduct](CODE_OF_CONDUCT.md) applies to all project spaces.

Before changing a larger system, read [`CAPABILITIES.md`](CAPABILITIES.md) for what's shipped and the invariants it must keep, [`ARCHITECTURE.md`](ARCHITECTURE.md) for how it works inside, and [`DESIGN-NOTES.md`](DESIGN-NOTES.md) for the intent behind planned work. To build a library other people's sketches can import, see [Writing an extension](Docs/Tools/Extensions.md) for the `ollinx-` convention and generator starters.
