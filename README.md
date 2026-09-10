# <picture><source media="(prefers-color-scheme: dark)" srcset="Logo/ollin-mark-dark.svg"><img src="Logo/ollin-mark.svg" alt="" height="40" align="top"></picture> Ollin

**A Metal-rendered creative-coding framework for Swift on Apple platforms.**

![Platform: macOS 26+](https://img.shields.io/badge/platform-macOS_26%2B-blue) ![Swift 6.3+](https://img.shields.io/badge/Swift-6.3%2B-F05138?logo=swift&logoColor=white) [![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

[Guide](Guide/README.md) · [Docs](Docs/README.md) · [Examples](Examples/) · [Roadmap](ROADMAP.md) · [Architecture](ARCHITECTURE.md) · [Attribution](ATTRIBUTION.md) · [Contributing](CONTRIBUTING.md)

Ollin is for generative art, live visuals, and installations. The techniques are built in: Voronoi and L-systems, raymarched signed-distance fields, GPU fluids, on-device computer vision, and [the rest of the catalog](Docs/README.md#the-catalog). The renderer sits directly on Metal and composites in linear light. The tooling covers the work up to a finished piece: live reload while you edit, a typed parameter inspector for tuning, deterministic headless export for the final render.

<img src="https://media.ollin.art/heroes/readme-hero.jpg?v=d4678db0" alt="Thirty-two of the example sketches running at once, from every area of the framework" width="880">

The API borrows the friendly `setup()`/`draw()` feel of [p5.js](https://p5js.org), the typed core of [OPENRNDR](https://openrndr.org), and the simple structure of [openFrameworks](https://openframeworks.cc), reimplemented in Swift idioms rather than ported (see [Influences & attribution](#influences--attribution)). *Ollin* (OH-leen) is the Aztec glyph for movement, the seventeenth day sign of the calendar.

Coming from p5.js or Processing? [Appendix C of the Guide](Guide/C-ComingFromP5.md) maps the API you already know onto Ollin.

- **Platform:** macOS 26+ with a Metal-capable GPU, Swift 6.3+ (Xcode 26); a sketch also runs on iOS 26 as an app, [worked on from the Mac](Docs/Tools/OnThePhone.md); Apple platforms only, [by design](#why-apple-only)
- **Rendering:** Metal, built on Foundation / SwiftUI / MetalKit / simd; no package dependencies; the C/C++ libraries it does use (Box2D, Jolt, libtess2, Clipper2, Syphon, and a few smaller pieces) are vendored under `External/` with licenses intact and provenance recorded ([details](ATTRIBUTION.md#bundled-third-party-code))
- **License:** MIT
- **Built with:** an AI coding assistant (Claude) under [@eaviles](https://github.com/eaviles)'s direction; see [Built with AI](#built-with-ai)

> **Status: alpha, pre-1.0, built in public.** The rendering, the color, and the output are production-grade. The API is not frozen yet. Everything documented below runs today, but names and signatures still change between commits, and there's no stability or support guarantee. See [Status & contributing](#status--contributing).

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

That's the whole program: a black circle outline, breathing on a white canvas. `@main` boots the window for you, and the draw loop is already running, so there's no call to start the animation, and `time` (seconds since start) is ready to use. Delete `+ sin(time) * 40` and you have a still circle. Or change `width / 2, height / 2` to `mouseX, mouseY` and the circle follows the pointer: `mouseX`, `mouseY`, `mouseIsPressed`, and a `keyPressed()` override are [already on the sketch](Docs/Helpers/Input.md).

## Run it

From the terminal, no Xcode required:

```sh
git clone https://github.com/eaviles/Ollin.git
cd Ollin
swift run --package-path Examples Example-Basic-HelloCircle
```

That builds the package and opens a window with a breathing circle like the one above (the shipped file is the same sketch, drawn a little larger and with its sizes riding the built-in `scale` factor so they hold at any canvas size). The first build compiles the whole framework from source, so give it a few minutes; every build after that is incremental and quick. Nearly five hundred runnable sketches live in [`Examples/`](Examples/), grouped by topic; `swift run` inside `Examples/` with no argument lists every example target, and from the repo root `swift run OllinExamples` opens a gallery with all of them in a sidebar.

The canvas is 1080×1080 by default, previewed fit to your screen. `canvasSize` sets the resolution a sketch renders and exports at, and `windowMode` sizes the preview window. The [Canvas](Docs/Core/Canvas.md) page covers the presets and how to write resolution-independent sketches. Coordinates use a top-left origin with y increasing downward, the same as p5, Processing, and OPENRNDR; [Where a point is](Docs/Concepts/Coordinates.md) covers units and other frames.

## Install

To use Ollin from your own package:

```swift
// Package.swift
platforms: [
    .macOS("26.0")
],
dependencies: [
    // Pre-1.0: a breaking change bumps the minor, so stay on one minor.
    .package(url: "https://github.com/eaviles/Ollin.git", .upToNextMinor(from: "0.3.0"))
],
targets: [
    .executableTarget(
        name: "MySketch",
        dependencies: [.product(name: "Ollin", package: "Ollin")]
    )
]
```

The `platforms` entry matters: without it SwiftPM targets its oldest macOS default, and the build fails against Ollin's macOS 26 floor.

You can also skip the package entirely: a single loose `.swift` file runs on its own. See [Single-file sketches](Docs/Tools/SingleFile.md), or the [Live reload](#live-reload) section below for the `ollin` command that runs a loose file.

## Why Ollin exists

I make sketches in code, mostly for myself. Some months there are a lot of them and some months there are none. Along the way I collected the parts I kept needing: techniques I had read about and written out myself, shaders I copied from one sketch into the next, and small tools for starting a new sketch.

Those parts were spread across several tools. I drew in openFrameworks, shared each window through a browser so I could mix it live in Hydra, and wrote filters in OPENRNDR. In my setup I could only keep four sketches going at once, and what I could do live was whatever that chain allowed. Anything past drawing, a 3D camera for example, meant an add-on maintained on its own schedule, and sometimes I had to get it compiling before I could start. I liked how much of OPENRNDR felt organized and part of one thing.

I wanted that in one native framework: drawing that looks right at full resolution by default, Metal and compute shaders available directly, current Apple hardware supported, and the parts kept working together. I also wanted what p5 has in the browser, where a change shows on screen as soon as you save, instead of a rebuild and a wait. And I wanted to write it in Swift.

Working this way also brings the phone in. Its cameras and its lidar feed a sketch running on the Mac, so the room in front of it, a face, or a pair of hands can drive the drawing, and a sketch can also run on the phone itself.

Ollin is that collection, rewritten as a single framework. I built it for my own work first. It is public because most of what is in it is not specific to me, and because I would like other people drawn to creative coding to learn along with me, collecting examples, writing sketches, and adding to the framework.

## What's in it

All of it is one API with the same conventions throughout.

- **The output is production-grade.** Every frame composites in linear light with HDR tone mapping, dithered output, analytic anti-aliasing, and up to 8× MSAA. Color is OKLab with real gamut mapping, not HSB approximations. Exports are deterministic and carry a reproducibility recipe: the seed, the parameter values, the commit. Rendering is snapshot-tested against committed reference images.

- **The edit-to-see loop is instant.** `swift run OllinLive Sketch.swift` watches the file and hot-swaps each save into the running window, and a typo never closes it. `@Param` properties become typed inspector controls (sliders, steppers, toggles, menus, color wells, palette and gradient strips) in grouped cards, and they keep their values across reloads. It also reads out [what the frame cost](Docs/Tools/Profiling.md): CPU against GPU, draws, and passes. And a shape placed by plain numbers can be [handled with the pointer](Docs/Tools/DragToEdit.md): hold Command to move it, pull a corner to resize it, or take the knob above it to turn it, and those numbers change in your own file.

- **Live coding on stage.** `swift run OllinLiveCoding` is a performance instrument: the sketch fills the window, the code rides over it as translucent text, and ⌘↩ (Command-Return) recompiles the buffer mid-motion, with the clock and tuned parameters carrying across the swap. A typo shows as a strip at the bottom while the last good sketch keeps playing.

- **A Metal core you can extend.** Most shapes render as analytic signed-distance fields (one instanced quad each, so thousands of moving shapes stay cheap), strokes carry their own anti-aliasing fringe, frames composite through an [HDR float pipeline](Docs/Drawing/HDR.md), and when you outgrow the built-ins you write your own fragment shader or compute kernel without leaving the framework.

- **Motion is the default.** `draw()` runs at the display's refresh rate from the first line, so `120 + sin(time) * 40` is already an animation. Under that is a motion layer: frame-rate-independent easing and springs, keyframe timelines, [parameters on their own curves](Docs/Core/Automation.md), input smoothing, noise that closes exactly over a lap, perfect-loop export, and motion locked to MIDI clock.

- **Output that leaves the screen.** Headless PNG stills and deterministic sequences, MP4 and GIF straight from the CLI (and [slowed down](Docs/Output/Export.md#slow-motion) on the way out, by a finer clock or by frames the machine makes between the drawn ones), a [web page](Docs/Output/Web.md) that plays what the sketch drew back in a browser, vector SVG and PDF with optional hatched fills for pen plotters, [G-code programs](Docs/Output/GCode.md) that a pen plotter, laser cutter, or CNC router runs directly, [DXF drawings](Docs/Output/DXF.md) that a CAD program or a laser's software opens with each color on its own layer, [embroidery files](Docs/Output/Embroidery.md) that a sewing machine stitches, [print separations](Docs/Output/PrintSeparations.md) with a real ink model for riso and screen printing, [print color management](Docs/Output/PrintColor.md) that proofs the canvas against a press profile and splits it into process plates, [fabrication files](Docs/Output/Fabrication.md) (STL, OBJ, 3MF) so a generated mesh can be 3D-printed at a real size, and [spatial output](Docs/Output/Spatial.md): USDZ so a 3D piece opens in Quick Look, sends in a message, and stands on a real table through AR, or spatial video so its motion plays in depth on a headset.

- **Or running in the system.** `ollin new --kind mac-app` wraps a finished piece as a signed, double-clickable [Mac app](Docs/Output/App.md) that runs where the toolchain never was, with a frame of itself as its icon; `--kind screen-saver` wraps it as the machine's [screen saver](Docs/Output/ScreenSaver.md), so the work runs when nobody is at the desk; `--kind wallpaper` runs it as the [desktop wallpaper](Docs/Output/Wallpaper.md), behind the icons on every display; and `--kind menu-bar` puts a small live strip of it [in the menu bar](Docs/Output/MenuBar.md), beside the clock all day. One script builds, signs, and installs any of them; the sketch itself stays an ordinary sketch. A sketch also runs on a phone: `ollin phone` puts it on a paired [iPhone or iPad](Docs/Tools/OnThePhone.md), installed again on every save with its clock and parameters carried across, and `--kind ios-app` writes it as an [app of your own](Docs/Tools/OnThePhone.md#in-an-app-of-your-own) for the phone and the tablet.

- **Made to be left running.** A piece on a wall declares [installation mode](Docs/Output/Installation.md) in one line. The screen fills, the pointer is hidden, and the display stays awake with the screen saver held off. The clock survives a night of display sleep and a week of running, which is where a long run usually breaks. Mark the state `@Saved` and a relaunch picks the piece up where it was. A watch starts it again after a crash. A schedule gives it the building's hours. Command-K lines the picture up with the wall it is thrown onto, and two projectors can share one wall without a bright bar down the join. One machine can drive both of them, or spread one canvas over every display it has.

Everything above ships in this repository. [The catalog](Docs/README.md#the-catalog) lists all of it area by area, with the reference page for each: shapes and geometry, text and color, shapes that merge, sixty-six generative techniques, layered effects, your own shaders, GPU compute, simulation and physics, the opt-in 3D layer, perception, data as material, sound, control surfaces, and the rig it plays in.

## Live reload

In creative coding, you want to see the result of an edit as soon as you can. So you run a sketch once and keep editing it. On each save, Ollin recompiles that one file and swaps it into the running window:

```sh
swift run OllinLive Examples/Basic/HelloCircle/Sketch.swift
```

The window never closes. If an edit doesn't compile, the error prints and the old sketch keeps running.

Hold Command over the window, and Ollin outlines the shape under the pointer, names the line that drew it, and puts handles on it. You can then [drag the shape](Docs/Tools/DragToEdit.md) to move it, pull a corner to resize it, or turn the knob above it to rotate it. Each of those writes the new numbers into that line. `⌘]` or `⌘[` moves the line itself past its neighbor's line, so the shape draws in front of or behind that neighbor. Laying something out by eye is then no longer a matter of guessing at coordinates. The performance host has the same drag, and there it rewrites the code on the stage and evaluates it.

Each reload starts the sketch fresh by default. `--keep-clock` carries `time` and `frameCount` across the reload, so an animation doesn't jump back to the start. There is also a `reloaded()` hook.

The sketch file always compiles optimized, so a sketch that does heavy CPU work each frame runs at release speed under the live window. `--no-optimize` compiles it plain when you're debugging it, so asserts fire and a crash names every frame. For a heavy sketch, `Scripts/OllinLive` runs the host in release too. Saves stay fast either way, because only the sketch file recompiles.

The same engine also powers a performance instrument, [OllinLiveCoding](Docs/Tools/LiveCoding.md). It is a single window that can go fullscreen, and the code shows over the visuals for the audience. Pressing ⌘↩ evaluates the buffer in place, and the clock and the tuned `@Param` parameters carry across each swap. OllinLive is the development loop, with your own editor and a file watcher. OllinLiveCoding is the on-stage loop, with the editor in the window and evaluation on command.

A sketch doesn't need a package at all. `Scripts/ollin install` puts an `ollin` command on your PATH. After that, one `.swift` file anywhere on disk is a whole sketch:

```sh
ollin new dots.swift        # write a starter sketch
ollin dots.swift            # live window, hot-reload on save
./dots.swift                # the file is directly executable (hashbang + chmod +x)
ollin dots.swift --export-gif dots.gif --seconds 4
ollin dots.swift --installation   # put it up: its own window, left running
```

See [Single-file sketches](Docs/Tools/SingleFile.md) for assets, for the extra `import`s (audio, MIDI, physics, and the rest), and for growing a file into a package.

When a piece outgrows one file, the [project generator](Docs/Tools/ProjectGenerator.md) makes the folder for you, already wired for what you're about to use:

```sh
ollin new MyPiece --template shader --with audio   # a folder that builds and runs
ollin generate                                     # the same, in a window
```

`ollin generate` shows each starting point by *running* it, so you pick a template by watching it rather than by reading its name.

The same `ollin` command also reads the documentation and the examples out of your own checkout, so you can look something up without a browser:

```sh
ollin docs color            # the page, in the terminal
ollin docs --search "long exposure"   # every place the reference says it
ollin examples ocean        # what it shows, and how to run it
```

See [The reference offline](Docs/Tools/Reference.md) for sections, filters, and reading an example's source. `ollin site` writes the same pages out as a website.

The same command also starts a library that other people's sketches can import, with the layout every extension shares. See [Writing an extension](Docs/Tools/Extensions.md) for the `ollinx-` naming convention and for the seams a third party can build on.

```sh
ollin new Halftone --kind extension --seam filter
```

There are other ways to iterate. You can tweak and re-run an example with `swift run --package-path Examples Example-Basic-HelloCircle`, and incremental builds keep that quick. Or you can open the examples package in Xcode with `open Examples/Package.swift`, which gives you ⌘R (Command-R), breakpoints, and the debugger.

## Export

Any sketch renders headlessly, with no window needed. Stills, deterministic PNG sequences, video, GIF, a web page, and vector SVG and PDF all come from the same run command:

```sh
swift run --package-path Examples Example-Basic-HelloCircle --export frame.png --frame 120
swift run --package-path Examples Example-Basic-HelloCircle --export-sequence frames/ --seconds 20 --fps 60
swift run --package-path Examples Example-Basic-HelloCircle --export-video breathing.mp4 --seconds 6
swift run --package-path Examples Example-Basic-HelloCircle --export-gif breathing.gif --seconds 4
swift run --package-path Examples Example-Web-BreathingRing --export-web ring.html          # a page that plays it in a browser
swift run --package-path Examples Example-Basic-HelloCircle --export-svg still.svg   # vector, for pen plotters
swift run --package-path Examples Example-Basic-HelloCircle --export-pdf still.pdf   # vector, for print (paper-size presets)
swift run OllinLive MySketches/Loop.swift --export-gif loop.gif --seconds 4   # a loose file, same flags
```

Sequence, video, and GIF exports advance the clock at a fixed timestep rather than by wall-clock time, so a slow render still plays back smoothly. In code these are `OllinApp.export`, `exportSequence`, `exportVideo`, and `exportGIF`. Codec and quality settings, the `--skip` warmup, GIF sizing, `--slow-motion`, and the `--hatch` fills for pen plotters are all in [`Docs/Output/Export.md`](Docs/Output/Export.md).

A web page is the same kind of export. `--export-web` records what the sketch drew over a duration and writes a page that plays it back. The framework's own shape shader is translated to GLSL for that page. The page is one self-contained file or a fragment for a page of your own ([`Docs/Output/Web.md`](Docs/Output/Web.md)).

A 3D scene can also render its export by tracing light paths instead of rasterizing. `--path-traced` spends seconds per frame on shadows that soften as they would in the physical world, color bleed, mirror-in-mirror reflections, and a lens model. It renders from the same sketch the window tunes live ([`Docs/Output/PathTraced.md`](Docs/Output/PathTraced.md)).

An export reproduces a sketch, and a recording keeps a performance. You start a recording with `startRecording()` in a sketch, with ⌘⇧R (Command-Shift-R) in the live hosts, or with `--record` on OllinLive. It writes the run as it happens: the picture and the sketch's own sound (or the room's sound) in one movie, in real time. In the live-coding host, an evaluate does not interrupt the movie. See [`Docs/Output/Recording.md`](Docs/Output/Recording.md).

A recording keeps the pixels, and a *take* keeps the performance itself. `--record-take take.json` writes a run's seed, clock, inputs, and parameter moves as one small JSON file. `--replay take.json` plays it back exactly, in the window or through any export flag above. In the window, the keyboard becomes a transport: pause, step, scrub. Through an export flag, a session of live tweaking re-renders offline frame for frame, even path-traced. `--seed` beside `--replay` plays the same gestures onto a different variation. See [`Docs/Core/Replay.md`](Docs/Core/Replay.md).

A take keeps what you did, and an *automation* writes down what should happen. `automate($radius) { ... }` puts a parameter on a curve, with one value placed at each moment. Every frame, the parameter is where the curve says it is. Numbers, colors, and points blend from one value to the next, and a switch steps. The tracks read the sketch clock, so `--export-video` renders the piece exactly as it plays, and `--automation file.json` drives the same parameters from a file. In OllinLive, the [timeline panel](Docs/Tools/Timeline.md) lets you author those tracks by hand: scrub the playhead, set the parameter, then click the diamond in its row. See [`Docs/Core/Automation.md`](Docs/Core/Automation.md).

A curve says where a parameter is at a few moments, and a *formula* says what it is at every moment. `drive($radius, "190 + sin(time * tau / 6) * 80")` reads the rule from text rather than from Swift source. So the rule can come from a file, from a typed field, or from a parameter worked out from another one. It is the same kind of track, so it loops, plays at any speed, and renders frame for frame. A parameter that holds more than one number takes one rule for each part. A part you leave out stays free for you to move. See [`Docs/Helpers/Formula.md`](Docs/Helpers/Formula.md).

A seeded sketch is a generator, so Ollin names the seed of each run ([`variation`](Docs/Core/Variations.md)). It also gives you tools to explore the space of seeds. You can step, roll, or jump through seeds from the inspector's Variation card. You can proof a whole range as a labeled contact sheet, then re-render the one you keep at full size.

```sh
swift run --package-path Examples Example-Randomness-Variations --export-grid sheet.png --seeds 25  # proof 25 variations
swift run --package-path Examples Example-Randomness-Variations --export keeper.png --seed 10       # render the one you liked
```

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

## How it works

`Sketch.draw()` calls the bare drawing functions, and they forward to a `Drawer` state machine. Most primitives take a signed-distance-field path: each one is a single quad, with its fill, stroke, and anti-aliasing computed analytically in the fragment shader. The rest tessellate into triangles. The `Drawer` records both kinds into call-ordered batches. Once a frame, `MetalRenderer` uploads those batches and issues one draw per batch, so shapes composite in the order you drew them.

The renderer is heavily commented, because you will be extending it. For how the larger systems work inside (the frame lifecycle, the screen-space effects, the SDF combinators, and more), see [`ARCHITECTURE.md`](ARCHITECTURE.md).

## Why Apple-only

p5.js, OPENRNDR, and openFrameworks run everywhere. Ollin runs only on Apple hardware, and that is a trade it makes on purpose.

Ollin sits directly on Metal, so the rendering limit is whatever the GPU can do. It stays native, so the rest of the platform is within reach. Vision on the Neural Engine is already here, and so are an iPhone's depth sensors feeding a sketch that the Mac renders. Meanwhile, visionOS and AR are still ahead. The core is built to grow into those things rather than be retrofitted for them.

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

- **The output is production-grade.** It has linear-light rendering, analytic anti-aliasing, OKLab color, deterministic and reproducible export, and snapshot-tested rendering. Work made with Ollin is meant to be finished and shown.
- **The API is not.** Names, signatures, and structure still change. Releases follow semantic versioning at major zero: a breaking change or a new feature bumps the minor, and a fix bumps the patch. Pin `.upToNextMinor` and read the [changelog](CHANGELOG.md) when you move up. Deprecation shims and a settled surface arrive at 1.0.

Beyond that:

- **No support guarantee.** This is built nights and weekends. Issues and [discussions](https://github.com/eaviles/Ollin/discussions) get read, but a response time isn't promised.
- **macOS 26+ and a Metal-capable GPU are required.** That is the trade described above, not a gap to be filled later. So there is no Linux or Windows path, by design. A sketch also runs on iOS 26 as an app built from the Mac, and [the sketch on the phone](Docs/Tools/OnThePhone.md) says how.

Even so, contributions and ideas are welcome. The practical details are in [`CONTRIBUTING.md`](CONTRIBUTING.md). The best source of small pieces of work is [`ROADMAP.md`](ROADMAP.md), and its [Up next](ROADMAP.md#up-next) section maps onto small, self-contained pull requests. For anything larger, please open an issue to discuss it before sending a big change. Three documents give you your bearings before you touch one of the bigger systems. Everything shipped has one bullet in [`CAPABILITIES.md`](CAPABILITIES.md), with pointers to its example, tests, and docs. How the larger systems work inside is in [`ARCHITECTURE.md`](ARCHITECTURE.md). The intent behind what's still planned is in [`DESIGN-NOTES.md`](DESIGN-NOTES.md). The [code of conduct](CODE_OF_CONDUCT.md) applies to all of it.
