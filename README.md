# Ollin

**Motion-first creative coding for Swift, rendered with Metal.**

*Ollin* (OH-leen) is the Aztec glyph for **movement**, the 17th day sign of the calendar, and the name says what the framework is about: in Ollin, your sketches **move by default**. The draw loop runs continuously at the display's refresh rate from the very first line of code. Animation is on from the start, so you never reach for a `loop()` call to begin it. For the rare still image, `noLoop()` turns it off.

It draws inspiration from [OPENRNDR](https://openrndr.org) (the `Program` /
`drawer` lifecycle), [p5.js](https://p5js.org) (friendly, forgiving,
learn-it-in-an-afternoon API names), and [openFrameworks](https://openframeworks.cc)
(simple structure, immediate-mode primitives), while leaning into Swift idioms where
they improve on the originals.

- **Platform:** macOS 14+, Swift 5.9+
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
        circle(x: width / 2, y: height / 2, radius: 120)
    }
}

OllinApp.run(HelloCircle())
```

That draws a black circle outline about 3px wide, centered on white, and it's the whole program.

## Make it move

The loop is already animating underneath, so making the circle breathe takes a single line. `time` (seconds since start) is ready to use in any sketch, with no setup needed:

```swift
circle(x: width / 2, y: height / 2, radius: 120 + sin(time) * 40)
```

Every sketch gets temporal state out of the box:

| Property     | Type     | Meaning                          |
|--------------|----------|----------------------------------|
| `frameCount` | `Int`    | frames drawn so far              |
| `time`       | `Double` | seconds since the sketch started |
| `deltaTime`  | `Double` | seconds since the last frame     |
| `frameRate`  | `Double` | smoothed frames per second       |

Plus `width` and `height` (logical points, updated live on resize), and
`noLoop()` / `loop()` for still images.

## Run it

From the terminal, no Xcode required:

```sh
swift run Example-HelloCircle
```

That builds the package and opens an 800×800 window running the `HelloCircle` example. More runnable sketches live in [`Examples/`](Examples/); `swift run` with no argument lists every example target.

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
2. **Edit & re-run.** Tweak an example (or your own sketch) and re-run, e.g.
   `swift run Example-Breathing`. Incremental builds keep this snappy.
3. **Keep it open in Xcode.** `open Package.swift` (or just open the folder).
   Edit, ⌘R, repeat, with breakpoints and the debugger when you need them.
4. **Single-file scripts (planned).** `SwiftProcessing` popularized a
   [`swift-sh`](https://github.com/mxcl/swift-sh)-style flow where one `.swift`
   file is also a runnable script. We want the same here so you can dash off a
   sketch without a package; it's on the roadmap below.

## The drawing API (small on purpose)

One of p5's strengths is that you can learn its whole drawing surface in an afternoon. Ollin keeps its surface small and the names familiar:

```swift
background(_ color: Color)              // clear color for the frame
fill(_ color: Color) / noFill()         // filled interior, or not
stroke(_ color: Color) / noStroke()     // outline color, or not
strokeWeight(_ weight: Double)          // outline thickness in points
circle(x: Double, y: Double, radius: Double)
circle(center: Vector2, radius: Double)                 // same, via a Vector2 center
rect(x: Double, y: Double, width: Double, height: Double)
rect(corner: Vector2, width: Double, height: Double)    // same, via a Vector2 corner
rect(center: Vector2, width: Double, height: Double)    // center-anchored (p5 rectMode CENTER)
line(x1: Double, y1: Double, x2: Double, y2: Double)
polyline(_ points: [Vector2])           // connected open path, stroked
polygon(_ points: [Vector2])            // filled convex polygon (+ stroked outline)

translate(x: Double, y: Double)         // shift the origin
rotate(_ radians: Double)               // rotate (clockwise; y-down)
scale(_ amount: Double)                 // scale (also scale(x:y:))
isolated { … }                          // run a block with transform + style saved/restored
push() / pop()                          // manual save/restore (isolated is the scoped form)
```

`Color` is RGBA floats (`0...1`) with familiar constants: `.white`, `.black`, `.gray`, `.red`, `.green`, `.blue`, and `.clear`. `Vector2` is an `(x, y)` point in sketch points, the geometry type that primitives like `polyline` take. `Rectangle` (a `corner` plus `width`/`height`) is the typed form `rect` takes, with `rect(x:y:width:height:)` as sugar over it. Coordinates use a **top-left origin with y increasing downward**, the same as p5, Processing, and OPENRNDR.

## Math helpers

A small, growing set of the familiar creative-coding math functions, callable
bare in `draw()`:

```swift
map(_ value: Double, _ start1: Double, _ stop1: Double,
    _ start2: Double, _ stop2: Double, clamp: Bool = false) -> Double
dist(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double
```

`map` linearly re-maps a number from one range onto another. For example, `map(sin(time), -1, 1, 0, width)` turns the `-1...1` of `sin` into `0...width`. By default it extrapolates past the range; pass `clamp: true` to hold the result inside `start2...stop2`. `dist` is the Euclidean distance between two points.

## Randomness & noise

`random` and `noise` are seedable and live on the sketch (so two sketches never
share hidden global state). Call them bare in `draw()`, like the math helpers:

```swift
random()                  // Double in 0..<1
random(max)               // 0..<max
random(min, max)          // min..<max (order-independent)
randomGaussian()          // standard normal (mean 0, sd 1)
randomGaussian(mean:deviation:)  // normal with the given mean and spread
randomSeed(_ seed: Int)   // reproducible runs

noise(x)                  // 1D Perlin noise, in 0...1 (contrast-calibrated to fill the range)
noise(x, y)               // 2D
noise(x, y, z)            // 3D
signedNoise(x[, y[, z]])  // the same field in -1...1 (oF ofSignedNoise / OPENRNDR convention)
curlNoise(x, y)           // divergence-free 2D flow vector — flow fields
noiseSeed(_ seed: Int)
```

`randomGaussian` is normal-distributed, which reads as more natural scatter than the flat spread of `random`. `curlNoise` returns a divergence-free flow vector (the curl of the Perlin field), the usual basis for flow fields — `.normalized` gives just the direction. See the `Gaussian` and `FlowField` examples.

By default the seed is entropy-based, so an unseeded sketch differs each run; seed it for a reproducible image. These are Ollin's own implementations, so a seed reproduces Ollin's output rather than p5's. A port captures the aesthetic of the original, though not its exact pixels. The full-turn constant is available as `Double.tau` (2π).

## Palettes

`Palette` turns a single number into cycling color through a cosine-gradient formula. Reach for the built-in `.rainbow`, or build your own from four `(r, g, b)` coefficient triples (center, amplitude, frequency, phase):

```swift
Palette.rainbow.color(at: t)                   // t cycles over 0...1
let warm = Palette(a: (0.5, 0.5, 0.5), b: (0.5, 0.5, 0.5),
                   c: (1.0, 1.0, 1.0), d: (0.0, 0.10, 0.20))
warm.color(at: t)
```

The formula is Inigo Quilez's (see [Influences & attribution](#influences--attribution)). The `Palettes` example sweeps both across the canvas.

## Input

`mouseX` / `mouseY` track the cursor in sketch coordinates (points, top-left origin, y-down). They're seeded from the cursor's actual position when the sketch window opens, so a mouse-driven sketch is alive on the first frame instead of waiting for the first move. After that, they update as the pointer moves over the canvas:

```swift
let pct = map(dist(mouseX, mouseY, width / 2, height / 2), 0, 400, 1, 0, clamp: true)
```

Override `mousePressed()` to respond to a click; `mouseX`/`mouseY` hold the press location. It's handy for regenerating an otherwise-static sketch on demand.

## How it works (one paragraph)

`Sketch.draw()` calls the bare drawing functions, which forward to a `Drawer`
state machine. The `Drawer` tessellates each primitive into triangles in
sketch-space points (a circle outline becomes a triangle-strip annulus). Once a
frame, `MetalRenderer` uploads those triangles, clears to the background color,
and issues a single `drawPrimitives` call; a vertex shader maps points to clip
space (flipping Y) and 4× MSAA on the `MTKView` gives the anti-aliased edge.
The renderer is heavily commented because you'll be extending it.

## Exporting frames

Any sketch can render a frame to a PNG **headlessly**, with no window. That's handy for grabbing a still to share, for checking a sketch on a machine without a display, and as the basis for PNG sequences you can stitch into video:

```sh
swift run Example-HelloCircle --export frame.png
swift run Example-Orbits --export frame.png --frame 120   # the 120th frame
```

It drives the sketch off-screen (`setup()`, then `draw()` advanced to the requested `--frame`) and writes a PNG at the sketch's size, rendered with the same 4× MSAA as the window. In code it's `OllinApp.export(sketch, to:frame:)`.

## Roadmap

The first pass is deliberately just enough to draw and iterate. Next up:

- **More primitives:** `ellipse`, `point`, `triangle`.
- **Fills & color:** richer color (hex/HSB), gradients, blend modes. Cosine-gradient `Palette` has landed; perceptual colormaps (viridis, magma, …) are a natural next step.
- **Typography & images:** text, image loading and drawing.
- **Shaders:** user-supplied fragment/vertex shaders.
- **Vector & raster export:** single-frame PNG export has landed (`--export`); PNG *sequences*, SVG, and PDF are next.
- **Capture for sharing:** video and GIF recording of animated sketches, since motion is the whole reason Ollin exists.
- **Single-file `swift-sh` scripting** for zero-ceremony sketches.

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
- `curlNoise` follows the curl-noise method for divergence-free flow (Robert Bridson and colleagues, "Curl-Noise for Procedural Fluid Flow", 2007).
- `randomGaussian` uses the Marsaglia polar method for normal-distributed samples.

## Status & contributing

Ollin is **alpha and pre-1.0**, developed in the open. Practically, that means:

- **The API will change.** Names, signatures, and structure can shift between commits; there's no tagged release or SemVer guarantee until 1.0.
- **No support guarantee.** This is built nights and weekends. Issues and discussions get read, but a response time isn't promised.
- **macOS 14+ and a Metal-capable GPU are required**, by design. There's no Linux or Windows path.

That said, contributions and ideas are genuinely welcome. The [roadmap](#roadmap) above is the best source of bite-size work; the *more primitives* line (`rect`, `line`, `ellipse`, …) in particular maps onto small, self-contained pull requests. For anything larger, please open an issue to discuss it before sending a big change.
