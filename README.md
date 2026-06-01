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
- **Rendering:** Metal (`MTKView`, 4× MSAA), built on Foundation / SwiftUI / Metal / MetalKit / simd. It stays dependency-light (none today), and takes on a third-party package only when one clearly earns its place
- **License:** MIT

> **Built with AI.** Ollin's code is designed and written by an AI coding assistant (Claude) working under the direction of [@eaviles](https://github.com/eaviles), who guides what belongs in the framework and is accountable for it, while Claude proposes the API and implements it. Ollin is a tool for making art rather than a generative-art model, and it credits its influences without copying their source. See [Built with AI](#built-with-ai) and [Influences & attribution](#influences--attribution).

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

   For a heavy sketch, build the host in release so the drawing runs at full speed while you tweak — hot-reloads stay fast because only the sketch file recompiles. `Scripts/OllinLive` does this for you (it's `swift run -c release OllinLive`, with `--debug` to opt out):

   ```sh
   Scripts/OllinLive Examples/Motion/ArcField/Sketch.swift
   ```
2. **Edit & re-run.** Tweak an example (or your own sketch) and re-run, e.g.
   `swift run Example-Breathing`. Incremental builds keep this snappy.
3. **Keep it open in Xcode.** `open Package.swift` (or just open the folder).
   Edit, ⌘R, repeat, with breakpoints and the debugger when you need them.
4. **Single-file scripts (planned).** `SwiftProcessing` popularized a
   [`swift-sh`](https://github.com/mxcl/swift-sh)-style flow where one `.swift`
   file is also a runnable script. We want the same here so you can dash off a
   sketch without a package; it's on the roadmap below.

## Documentation

The drawing surface is small and the names familiar. The full API reference lives in [`Docs/`](Docs/):

- [Sketch](Docs/Sketch.md) - the lifecycle (`setup`/`draw`), temporal state (`time`, `frameCount`, …), and loop control.
- [Canvas](Docs/Canvas.md) - `scale`, the `canvasSize` export presets, and the preview window.
- [Drawing](Docs/Drawing.md) - `background`, `fill`/`stroke`, the shapes (`drawCircle`, `drawEllipse`, `drawArc`, `drawRect`, `drawLine`, `drawPolyline`, `drawPolygon`), and the transform stack (`translate`/`rotate`/`scale`, `withState`).
- [Color](Docs/Color.md) - the `Color` type, cosine-gradient `Palette` presets, and perceptual `Colormap`s.
- [Geometry](Docs/Geometry.md) - the `Vector2` and `Rectangle` value types.
- [Random](Docs/Random.md) - `random`, `randomGaussian`, and the `randomVector`/`ring` scatter helpers.
- [Noise](Docs/Noise.md) - Perlin `noise`/`signedNoise` and `curlNoise` flow fields.
- [Math](Docs/Math.md) - `map`, `dist`.
- [Input](Docs/Input.md) - mouse position and clicks.

New to Swift, coming from p5.js or JavaScript? The [Swift primer](Docs/Swift.md) teaches just enough of the language to be productive in `draw()`.

Coordinates use a top-left origin with y increasing downward, the same as p5, Processing, and OPENRNDR.

## How it works (one paragraph)

`Sketch.draw()` calls the bare drawing functions, which forward to a `Drawer`
state machine. Circles, ellipses, rectangles, lines, and circular arcs take a
signed-distance-field path: one quad each, with fill, stroke, and anti-aliasing
computed analytically in the fragment shader, so thousands of them stay cheap.
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

It drives the sketch off-screen (`setup()`, then `draw()` advanced to the requested `--frame`) and writes a PNG at the sketch's `canvasSize` (1080×1080 by default), rendered with the same 4× MSAA as the window. In code it's `OllinApp.export(sketch, to:frame:)`.

## Roadmap

The first pass is deliberately just enough to draw and iterate. Next up:

- **More primitives:** `drawEllipse` has landed; `drawPoint`, `drawTriangle` are next.
- **Fills & color:** richer color (hex/HSB), gradients, blend modes. Cosine-gradient `Palette` and perceptual `Colormap`s have landed.
- **Typography & images:** text, image loading and drawing.
- **Shaders:** user-supplied fragment/vertex shaders.
- **Vector & raster export:** single-frame PNG export has landed (`--export`); PNG *sequences*, SVG, and PDF are next.
- **Capture for sharing:** video and GIF recording of animated sketches, since motion is the whole reason Ollin exists.
- **Single-file `swift-sh` scripting** for zero-ceremony sketches.
- **Normalized `u, v` coordinates** (0…1 across the canvas) alongside points, so a sketch can place things without referring to `width`/`height`.

## Built with AI

Ollin's code is designed and written by an AI coding assistant (Claude), working under the direction of [@eaviles](https://github.com/eaviles). The motion-first idea and the calls about what belongs in the framework come from @eaviles, who steers, approves, or reworks Claude's proposals for the API and the design. So this isn't a case of a human designing it and the AI typing it up. It's closer to Claude proposing and building, with @eaviles guiding and editing along the way.

@eaviles wants to be up front about this, because the creative-coding community is rightly wary of AI, and that wariness deserves a clear answer:

- **It's a tool for making art, not a generative-art model.** The AI wrote the framework's plumbing, but it doesn't make the work you create with it. No scraped images, training datasets, or generated artwork go into it.
- **Sources are credited and licenses are respected.** Ollin is inspired by p5.js, OPENRNDR, and openFrameworks. It borrows their feel and vocabulary while writing its own implementation rather than copying their source. Where an example is ported from a specific sketch, that sketch and its author are named in the file. See [Influences & attribution](#influences--attribution).
- **A human is accountable.** Bugs, design mistakes, and licensing questions are for @eaviles to answer. Scrutiny is welcome, so please [open an issue](https://github.com/eaviles/Ollin/issues).

## Influences & attribution

Ollin builds on the ideas of three creative-coding frameworks and reimplements them in Swift. Because it does not copy their source code, none of their licenses attach to Ollin, which stays MIT:

| Project | License | What Ollin takes (influence only) |
|---|---|---|
| [p5.js](https://p5js.org) | LGPL-2.1 | Friendly, learn-it-in-an-afternoon API names and the `setup()` / `draw()` lifecycle |
| [OPENRNDR](https://openrndr.org) | BSD-2-Clause | The typed `Program` / `Drawer` core and composable geometry |
| [openFrameworks](https://openframeworks.cc) | MIT | Simple project structure and the per-example folder layout |

*"Inspired by" means borrowing ideas and API vocabulary, which is different from copying code; Ollin's implementation is written independently.* Individual example sketches that are ported from a published source name that source, its author, and its license in the file header. Only sources whose licenses permit redistribution under MIT are used.

### Bundled third-party code

Ollin bundles a small amount of third-party source in the repo. This is different from the projects above: it ships as actual code and keeps its own license. Right now that's one library:

- **[libtess2](https://github.com/memononen/libtess2)** (SGI Free Software License B): the polygon triangulator behind concave and holed `Shape` fills, vendored under `External/CLibtess2/`.

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
- The signed-distance fields behind circles, ellipses, rectangles, lines, circular arcs, triangles, regular polygons and stars, and point markers (box, capsule, pie, arc, isosceles triangle, star, rhombus, and cross) come from [Inigo Quilez's 2D distance functions](https://iquilezles.org/articles/distfunctions2d/).
- `curlNoise` follows the curl-noise method for divergence-free flow (Robert Bridson and colleagues, "Curl-Noise for Procedural Fluid Flow", 2007).
- `randomGaussian` uses the Marsaglia polar method for normal-distributed samples.
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

That said, contributions and ideas are genuinely welcome. The [roadmap](#roadmap) above is the best source of bite-size work; the *more primitives* line (`drawPoint`, `drawTriangle`, …) in particular maps onto small, self-contained pull requests. For anything larger, please open an issue to discuss it before sending a big change.
