# Ollin

**Motion-first creative coding for Swift, rendered with Metal.**

*Ollin* (OH-leen) is the Aztec glyph for **movement**, the 17th day sign of the calendar, and the name says what the framework is about: in Ollin, your sketches **move by default**. The draw loop runs continuously at the display's refresh rate from the very first line of code. Animation is on from the start, so you never reach for a `loop()` call to begin it. For the rare still image, `noLoop()` turns it off.

It draws inspiration from [OPENRNDR](https://openrndr.org) (the `Program` /
`drawer` lifecycle), [p5.js](https://p5js.org) (friendly, forgiving,
learn-it-in-an-afternoon API names), and [openFrameworks](https://openframeworks.cc)
(simple structure, immediate-mode primitives), while leaning into Swift idioms where
they improve on the originals.

Where those three are cross-platform, Ollin isn't, and that's on purpose. Betting on one family of hardware is what buys the depth: the same p5 feel and typed core sit straight on Metal, not WebGL or the JVM, so the rendering ceiling is whatever the GPU can do. Staying native is also what keeps the harder things in reach later, like vision on the Neural Engine, ARKit and visionOS, or an iPhone's depth sensors feeding a sketch the Mac renders. A tool that runs everywhere has to leave those on the table. Most of that is still ahead (the [roadmap](#roadmap) has it); for now the point is that the core is built to grow into them rather than get retrofitted.

- **Platform:** macOS 14+, Swift 6+
- **Rendering:** Metal (`MTKView`, 4× MSAA), built on Foundation / SwiftUI / Metal / MetalKit / simd. It stays dependency-light (no package dependencies today; just a little vendored source, see [Bundled third-party code](#bundled-third-party-code)) and takes on a package only when one clearly earns its place
- **License:** MIT
- **Built with:** an AI coding assistant (Claude) under [@eaviles](https://github.com/eaviles)'s direction; see [Built with AI](#built-with-ai)

> **Status: alpha, pre-1.0, built in public.** Right now the goal is modest: run `swift run`, see a black circle outline on white, and notice the continuous draw loop already humming underneath. From there it grows. Expect the API to change between commits, and don't count on stability or support guarantees yet. See [Status & contributing](#status--contributing).

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
        drawCircle(width / 2, height / 2, 120)
    }
}

OllinApp.run(HelloCircle())
```

That draws a black circle outline about 3px wide, centered on white, and it's the whole program.

## Make it move

The loop is already animating underneath, so making the circle breathe takes a single line. `time` (seconds since start) is ready to use in any sketch, with no setup needed:

```swift
drawCircle(width / 2, height / 2, 120 + sin(time) * 40)
```

Every sketch also gets temporal state out of the box (`frameCount`, `time`, `deltaTime`, `frameRate`), live `width`/`height`, a resolution-relative `scale`, and `noLoop()` / `loop()` for still images. The [`Sketch`](Docs/Sketch.md) reference covers them all.

## Run it

From the terminal, no Xcode required:

```sh
swift run Example-HelloCircle
```

That builds the package and opens a window running the `HelloCircle` example (a 1080² canvas, fit to your screen). More runnable sketches live in [`Examples/`](Examples/); `swift run` with no argument lists every example target.

Or browse them all in one window: `swift run OllinExamples` opens a gallery with every example in a sidebar, and clicking one compiles and runs it on the right.

## Canvas size and resolution

The default canvas is **1080×1080**, the 1:1 size for square social and video posts. `canvasSize` sets the resolution a sketch renders and exports at (override it for a hi-res master or a different aspect), and `windowMode` sizes the preview window relative to it (`.auto` fits the screen, `.fixed(_)` pins a zoom, `.resizable` follows the window live).

Write sketches relative to the canvas so they hold up at any size: multiply feature sizes by `scale` and lay out with `width`/`height` fractions. The [`Canvas` reference](Docs/Canvas.md#resolution-independence) has the presets and the rest.

## Add Ollin to your own package (SPM)

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

## Iteration workflow

In creative coding, the speed of the edit-then-see cycle matters more than almost anything. Here are a few options, with the fastest feedback first:

1. **Live reload (`OllinLive`).** Run a sketch once and keep editing it. On each
   save, Ollin recompiles that one file and swaps it into the running window, so
   the window stays open and the change shows up right away:

   ```sh
   swift run OllinLive Examples/Basic/HelloCircle/Sketch.swift
   ```

   It takes a path to any sketch file, so there's no target to register first. Run it from the repo and it live-reloads `Shaders.metal` as well. Each reload starts the sketch fresh by default: `setup()` runs again and the clock resets. Pass `--keep-clock` to keep `time` and `frameCount` running across reloads, so an animation doesn't jump back to the start. There's an `onReload()` hook for work you want to run on each reload. If an edit doesn't compile, the error prints and the running sketch keeps going, so a typo won't close the window.

   For a heavy sketch, build the host in release so the drawing runs at full speed while you tweak; hot-reloads stay fast because only the sketch file recompiles. `Scripts/OllinLive` does this for you (it's `swift run -c release OllinLive`, with `--debug` to opt out):

   ```sh
   Scripts/OllinLive Examples/Motion/ArcField/Sketch.swift
   ```
2. **Edit & re-run.** Tweak an example (or your own sketch) and re-run, e.g.
   `swift run Example-Breathing`. Incremental builds keep this snappy.
3. **Keep it open in Xcode.** `open Package.swift` (or just open the folder).
   Edit, ⌘R, repeat, with breakpoints and the debugger when you need them.
4. **Single-file scripts (planned).** [`swift-sh`](https://github.com/mxcl/swift-sh)
   made one `.swift` file double as a runnable script, dependencies and all. We
   want the same here, so you can dash off a sketch without setting up a package.
   It's on the roadmap below.

## Documentation

The drawing surface is small and the names familiar. The full API reference lives in [`Docs/`](Docs/):

- [Sketch](Docs/Sketch.md) - the lifecycle (`setup`/`draw`), temporal state (`time`, `frameCount`, …), and loop control.
- [Canvas](Docs/Canvas.md) - `scale`, the `canvasSize` export presets, and the preview window.
- [Drawing](Docs/Drawing.md) - `background`, `fill`/`stroke`, the shapes (`drawCircle`, `drawRect`, `drawLine`, `drawShape`, and a full catalog of analytic SDF shapes — see the reference), and the transform stack (`translate`/`rotate`/`scale`, `withState`).
- [Text](Docs/Text.md) - `drawText` with bitmap, outline (`.ttf`/`.otf`), and single-line/plotter (Hershey) fonts (`textFont`/`textSize`/`textAlign`/`textWidth`, `BitmapFont`/`OutlineFont`/`StrokeFont`), `textToShapes` for text as geometry, and loading BDF, Playdate `.fnt`, and Hershey `.jhf` fonts.
- [Images](Docs/Images.md) - `loadImage` / `drawImage` for raster images (PNG, JPEG, HEIC, …), with `tint` recoloring and an `Image[x, y]` pixel subscript for sampling or authoring.
- [Color](Docs/Color.md) - the `Color` type, cosine-gradient `Palette` presets, and perceptual `Colormap`s.
- [Geometry](Docs/Geometry.md) - the `Vector2`, `Rectangle`, `Shape`/`Contour`, and `Path` value types (including curved outlines).
- [Random](Docs/Random.md) - `random`, `randomGaussian`, and the `randomVector`/`ring` scatter helpers.
- [Noise](Docs/Noise.md) - Perlin `noise`/`signedNoise` and `curlNoise` flow fields.
- [Math](Docs/Math.md) - `map`, `dist`, `lerp`.
- [Animation](Docs/Animation.md) - the `Easing` curves, the `@Eased` value that tweens toward a target, and `@Smoothed` for cleaning up a noisy signal.
- [Input](Docs/Input.md) - mouse and keyboard.
- [Audio](Docs/Audio.md) - `import OllinAudio` for microphone, file, and oscillator sources, analyzed into `amplitude`, `spectrum`, and band values (`bass`/`mid`/`treble`) a sketch reads in `draw()`.
- [Export](Docs/Export.md) - save frames as raster (PNG, sequences) or vector (SVG, for pen plotters).

New to Swift, coming from p5.js or JavaScript? The [Swift primer](Docs/Swift.md) teaches just enough of the language to be productive in `draw()`.

Coordinates use a top-left origin with y increasing downward, the same as p5, Processing, and OPENRNDR.

## How it works (one paragraph)

`Sketch.draw()` calls the bare drawing functions, which forward to a `Drawer`
state machine. Most primitives (circles, ellipses, rectangles, lines, circular
arcs, and a broad catalog of analytic shapes) take a signed-distance-field path:
one quad each, with fill, stroke, and anti-aliasing computed analytically in the
fragment shader, so thousands of them stay cheap.
The rest (polygons, polylines, and elliptical arcs) are tessellated into
triangles in sketch-space points. The `Drawer` records both into call-ordered batches; once a frame,
`MetalRenderer` uploads them and issues a draw per batch (the triangle pipeline,
or the instanced-SDF one), so shapes composite in the order you drew them. A
vertex shader maps points to clip space (flipping Y), and 4× MSAA covers the
triangle path. The renderer is heavily commented because you'll be extending it.

## Exporting frames

Any sketch can render a frame to a PNG **headlessly**, with no window. That's handy for grabbing a still to share, for checking a sketch on a machine without a display, and as the basis for PNG sequences you can stitch into video:

```sh
swift run Example-HelloCircle --export frame.png
swift run Example-Orbits --export frame.png --frame 120   # the 120th frame
```

It drives the sketch off-screen (`setup()`, then `draw()` advanced to the requested `--frame`) and writes a PNG at the sketch's `canvasSize` (1080×1080 by default), rendered with the same 4× MSAA as the window. In code it's `OllinApp.export(sketch, to:frame:)`, or `OllinApp.image(of: sketch, frame:)` if you'd rather have the `CGImage` in memory than a file on disk. An extension can also grab each frame as it renders, through the `frameRendered` hook on the `extend(...)` seam — see [`Examples/Basic/Capture`](Examples/Basic/Capture/Sketch.swift).

For an animation, `--export-sequence` writes a numbered PNG sequence you can stitch into video:

```sh
swift run Example-Breathing --export-sequence frames/ --skip 5 --seconds 20 --fps 60
```

It advances the clock at a fixed timestep rather than wall-clock, so each frame renders the moment it should regardless of how long the render takes. A slow render still plays back smoothly. Pass `--seconds` for a duration instead of `--frames`, and `--skip` to run the sketch a while first without writing, so a sketch that needs to settle into motion is already going when capture starts. Frames are written as `frame-00001.png`, `frame-00002.png`, and so on, and the command prints an `ffmpeg` line to assemble them. In code it's `OllinApp.exportSequence(sketch, to:frames:fps:skipSeconds:)`.

## Roadmap

The first pass is deliberately just enough to draw and iterate. Next up:

- **More primitives:** a broad catalog of SDF shapes has landed (points, triangles, n-gons, stars, rings, Bézier curves, an outline-only band mode, and more), and it keeps growing.
- **Fills & color:** richer color (hex/HSB), gradients, blend modes. Cosine-gradient `Palette` and perceptual `Colormap`s have landed.
- **Images:** loading, drawing, `tint`, and pixel get/set have landed. Text too (bitmap, outline, and single-line/plotter fonts).
- **Shaders:** user-supplied fragment/vertex shaders.
- **Vector & raster export:** single-frame and PNG-*sequence* export have landed (`--export` / `--export-sequence`); SVG and PDF are next.
- **Capture for sharing:** video and GIF recording of animated sketches, since motion is the whole reason Ollin exists.
- **Single-file `swift-sh` scripting** for zero-ceremony sketches.
- **Normalized `u, v` coordinates** (0…1 across the canvas) alongside points, so a sketch can place things without referring to `width`/`height`.

## Built with AI

Ollin is [@eaviles](https://github.com/eaviles)'s project. The motion-first idea, the decisions about what belongs in the framework, and the responsibility for it are his. The code is written with an AI coding assistant (Claude) that proposes APIs and implements them, which @eaviles reviews, reworks, or rejects. A fair description: Claude does much of the proposing and most of the typing, and @eaviles does the deciding.

It's worth saying plainly, because the creative-coding community has good reasons to be careful about AI. A few specifics about how Ollin uses it:

- **It's a tool for making art.** The AI helped build the framework's plumbing. It has no hand in the work you make with Ollin, and no scraped images, training data, or generated artwork go into it. Ollin is not a generative-art model.
- **Influences are credited, licenses respected.** Ollin borrows the feel and vocabulary of p5.js, OPENRNDR, and openFrameworks while writing its own implementation. Ported example sketches name their source, author, and license in the file. See [Influences & attribution](#influences--attribution).
- **A person is accountable.** Bugs, design mistakes, and licensing questions are @eaviles's to answer. Scrutiny is welcome, so please [open an issue](https://github.com/eaviles/Ollin/issues).

The work people make with it is the real test.

## Influences & attribution

Ollin builds on the ideas of three creative-coding frameworks and reimplements them in Swift. Because it does not copy their source code, none of their licenses attach to Ollin, which stays MIT:

| Project | License | What Ollin takes (influence only) |
|---|---|---|
| [p5.js](https://p5js.org) | LGPL-2.1 | Friendly, learn-it-in-an-afternoon API names and the `setup()` / `draw()` lifecycle |
| [OPENRNDR](https://openrndr.org) | BSD-2-Clause | The typed `Program` / `Drawer` core and composable geometry |
| [openFrameworks](https://openframeworks.cc) | MIT | Simple project structure and the per-example folder layout |

That `setup()` / `draw()` vocabulary started in [Processing](https://processing.org), the Java project p5.js grew out of. Ollin follows p5's spelling because that's the version most people coming to it already know.

*"Inspired by" means borrowing ideas and API vocabulary, which is different from copying code; Ollin's implementation is written independently.* Individual example sketches that are ported from a published source name that source, its author, and its license in the file header. Only sources whose licenses permit redistribution under MIT are used.

### Bundled third-party code

Ollin bundles a small amount of third-party source in the repo. This is different from the projects above: it ships as actual code and keeps its own license. Right now that's:

- **[libtess2](https://github.com/memononen/libtess2)** (SGI Free Software License B): the polygon triangulator behind concave and holed `Shape` fills, vendored under `External/CLibtess2/`.
- **[Cozette](https://github.com/the-moonwitch/Cozette)** by Ines (MIT): the bundled default bitmap font for `drawText`, vendored as a BDF under `Sources/Ollin/Resources/`.
- **[Hershey fonts](https://paulbourke.net/dataformats/hershey/)** (public domain): "Hershey Sans" (`futural`), the bundled default stroke (single-line / plotter) font for `drawText`, vendored as a `.jhf` under `Sources/Ollin/Resources/`. Created by A. V. Hershey at the U.S. National Bureau of Standards.
- **[Marble Madness](https://github.com/idleberg/playdate-arcade-fonts)** (CC0 / public domain): a sample Playdate `.fnt` font used only by the `PlaydateFont` example to demonstrate the loader, bundled beside that sketch — not in the framework. Ollin ships the `.fnt` loader, not a library of fonts.

Everything bundled is listed in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md), with each library's license kept next to its source. Ollin's own code stays MIT; bundling a permissively licensed library doesn't change that.

### Swift + Metal references

The frameworks above shaped Ollin's API and ideas. Two more, written for the same Swift and Metal stack, are references for how the rendering layer is built:

| Project | License | What Ollin studies it for |
|---|---|---|
| [swifty-creatives](https://github.com/yukiny0811/swifty-creatives) | Apache-2.0 | A Processing-style, immediate-mode framework on the same stack; a reference for cross-platform view setup and snapshot-testing of rendered output |
| [AsyncGraphics](https://github.com/heestand-xyz/AsyncGraphics) | MIT | GPU image and video compositing; a reference for shader-library structure and a layered-effects model |

As with the others, this is reading for ideas and engineering approach, which is different from copying code; Ollin's implementation is its own. Thanks to their authors, [@yukiny0811](https://github.com/yukiny0811) and [@heestand-xyz](https://github.com/heestand-xyz), for building in the open.

### Techniques

A few helpers lean on well-known public techniques, reimplemented in Ollin and credited here. They lean toward OPENRNDR-style ergonomics:

- The cosine-gradient `Palette` uses [Inigo Quilez's palette formula](https://iquilezles.org/articles/palettes/).
- The signed-distance fields behind Ollin's analytic shapes (circles, ellipses, rectangles, lines, arcs, triangles, n-gons and stars, quadratic Bézier curves, point markers, and the rest of the catalog) come from [Inigo Quilez's 2D distance functions](https://iquilezles.org/articles/distfunctions2d/), including the onion operator behind rings and the `hollow`/`solid` band mode. SVG export traces these same functions on the CPU (marching squares) to turn each curved shape into a vector outline.
- Rendering happens in linear light (blending and MSAA resolve in linear space, into sRGB-encoded targets) with a small triangular-PDF dither on the 8-bit output to ease gradient banding; the per-pixel dither value comes from Dave Hoskins' [Hash without Sine](https://www.shadertoy.com/view/4djSRW).
- `curlNoise` follows the curl-noise method for divergence-free flow (Robert Bridson and colleagues, "Curl-Noise for Procedural Fluid Flow", 2007).
- `randomGaussian` uses the Marsaglia polar method for normal-distributed samples.
- The named `Easing` curves are Robert Penner's easing equations, written from the formulas catalogued at [easings.net](https://easings.net) (Andrey Sitnik and Ivan Solovev).
- `@Smoothed` and `OneEuroFilter` implement the [1€ filter](https://gery.casiez.net/1euro/) for adaptive input smoothing (Géry Casiez, Nicolas Roussel, and Daniel Vogel, *1€ Filter: A Simple Speed-based Low-pass Filter for Noisy Input in Interactive Systems*, CHI 2012), written from the paper.
- The `Colormap` ramps carry the canonical public colormap data: `viridis`/`magma`/`inferno`/`plasma`/`cividis` from [matplotlib](https://matplotlib.org) (CC0), `turbo` from Google (Apache-2.0), and `rocket`/`mako` from [seaborn](https://seaborn.pydata.org) (BSD-3).

### Directions ahead

These projects are inspirations for parts of Ollin that don't exist yet. Ollin studies how they work and reimplements the ideas rather than depending on them, the same as it treats the frameworks above. They're listed now so the influence is on record before the code lands.

| Project | License | What Ollin studies it for |
|---|---|---|
| [LYGIA](https://github.com/patriciogonzalezvivo/lygia) | Prosperity PL 3.0.0 (noncommercial) | A catalog of shader functions for well-known techniques like SDFs, noise, blends, and color conversions. Ollin reads it to learn the approach, then writes its own and credits the original technique. |
| [Hydra](https://github.com/ojack/hydra) | AGPL-3.0 | How a chainable, video-synth-style API makes mixing visuals feel easy. A direction for a future livecoding mode. |
| [Shader Park](https://github.com/shader-park) | MIT | How to compose and blend SDF shapes, and its livecoding environment. |

Meta Spark, the AR studio Meta has since discontinued, is the reference for an eventual AR mode. There's no source to credit, just the idea of starting from templates.

## Status & contributing

Ollin is **alpha and pre-1.0**, developed in the open. Practically, that means:

- **The API will change.** Names, signatures, and structure can shift between commits; there's no tagged release or SemVer guarantee until 1.0.
- **No support guarantee.** This is built nights and weekends. Issues and discussions get read, but a response time isn't promised.
- **macOS 14+ and a Metal-capable GPU are required.** That's the trade described up top, not a gap to be filled later: no Linux or Windows path, by design.

That said, contributions and ideas are genuinely welcome. The [roadmap](#roadmap) above is the best source of bite-size work; the *more primitives* line in particular maps onto small, self-contained pull requests. For anything larger, please open an issue to discuss it before sending a big change.
