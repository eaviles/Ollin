# Ollin

**Motion-first creative coding for Swift, rendered with Metal.**

*Ollin* (OH-leen) is the Aztec glyph for **movement** — the 17th day sign of the
calendar. The name is the thesis: in Ollin, your sketches **move by default**.
The draw loop runs continuously at the display's refresh rate from the very
first line of code. You don't opt in to animation with a `loop()` call; you opt
*out* with `noLoop()` for the rare still image.

It draws inspiration from [OPENRNDR](https://openrndr.org) (the `Program` /
`drawer` lifecycle), [p5.js](https://p5js.org) (friendly, forgiving,
learn-it-in-an-afternoon API names), and [openFrameworks](https://openframeworks.cc)
(simple structure, immediate-mode primitives) — leaning into Swift idioms where
they improve on the originals.

- **Platform:** macOS 14+, Swift 5.9+
- **Rendering:** Metal (`MTKView`, 4× MSAA), built on Foundation / SwiftUI / Metal / MetalKit / simd — dependency-light (none today), adding a third-party package only when it clearly earns its place
- **License:** MIT

> **Status: alpha — pre-1.0, built in public.** The win right now is "I can `swift run` and see a black circle outline on white, with a continuous draw loop already humming underneath." Then we iterate. Expect the API to change between commits, and no stability or support guarantees yet — see [Status & contributing](#status--contributing).

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

A black circle outline, ~3px, centered on white. That's the whole program.

## Make it move

It's already animating underneath — so making the circle breathe is a one-liner.
`time` (seconds since start) is ready to use in any sketch, no setup required:

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

Creative coding lives or dies by how fast you can edit → see. A few options,
fastest feedback first:

1. **Edit & re-run.** Tweak an example (or your own sketch) and re-run, e.g.
   `swift run Example-Breathing`. Incremental builds keep this snappy. This is the
   recommended default loop.
2. **Keep it open in Xcode.** `open Package.swift` (or just open the folder).
   Edit, ⌘R, repeat — with breakpoints and the debugger when you need them.
3. **Single-file scripts (planned).** `SwiftProcessing` popularized a
   [`swift-sh`](https://github.com/mxcl/swift-sh)-style flow where one `.swift`
   file is also a runnable script. We want the same here so you can dash off a
   sketch without a package; it's on the roadmap below.

## The drawing API (small on purpose)

p5's superpower is that you can learn the whole drawing surface in an afternoon.
Ollin keeps the surface tiny and the names familiar:

```swift
background(_ color: Color)              // clear color for the frame
fill(_ color: Color) / noFill()         // filled interior, or not
stroke(_ color: Color) / noStroke()     // outline color, or not
strokeWeight(_ weight: Double)          // outline thickness in points
circle(x: Double, y: Double, radius: Double)
```

`Color` is RGBA floats (`0...1`) with familiar constants: `.white`, `.black`,
`.gray`, `.red`, `.green`, `.blue`, `.clear`. Coordinates use a **top-left
origin with y increasing downward**, matching p5 / Processing / OPENRNDR.

## Math helpers

A small, growing set of the familiar creative-coding math functions, callable
bare in `draw()`:

```swift
map(_ value: Double, _ start1: Double, _ stop1: Double,
    _ start2: Double, _ stop2: Double, clamp: Bool = false) -> Double
dist(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double
```

`map` linearly re-maps a number from one range onto another — e.g.
`map(sin(time), -1, 1, 0, width)` turns the `-1...1` of `sin` into `0...width`.
By default it extrapolates past the range; pass `clamp: true` to hold the result
inside `start2...stop2`. `dist` is the Euclidean distance between two points.

## Input

`mouseX` / `mouseY` track the cursor in sketch coordinates (points, top-left
origin, y-down), updated as the pointer moves over the canvas — `0` until the
first movement:

```swift
let pct = map(dist(mouseX, mouseY, width / 2, height / 2), 0, 400, 1, 0, clamp: true)
```

## How it works (one paragraph)

`Sketch.draw()` calls the bare drawing functions, which forward to a `Drawer`
state machine. The `Drawer` tessellates each primitive into triangles in
sketch-space points (a circle outline becomes a triangle-strip annulus). Once a
frame, `MetalRenderer` uploads those triangles, clears to the background color,
and issues a single `drawPrimitives` call; a vertex shader maps points to clip
space (flipping Y) and 4× MSAA on the `MTKView` gives the anti-aliased edge.
The renderer is heavily commented because you'll be extending it.

## Roadmap

The first pass is deliberately just enough to draw and iterate. Next up:

- **More primitives:** `rect`, `line`, `ellipse`, `point`, `triangle`, polylines.
- **Fills & color:** richer color (hex/HSB), gradients, blend modes.
- **Transforms:** `push()`/`pop()`, `translate()`, `rotate()`, `scale()` (matrix stack).
- **Typography & images:** text, image loading and drawing.
- **Shaders:** user-supplied fragment/vertex shaders.
- **Vector & raster export:** save frames to PNG / SVG / PDF.
- **Capture for sharing:** video / GIF recording of animated sketches — because
  the whole point of Ollin is that things move.
- **Single-file `swift-sh` scripting** for zero-ceremony sketches.

## Status & contributing

Ollin is **alpha and pre-1.0**, developed in the open. Practically, that means:

- **The API will change.** Names, signatures, and structure can shift between commits; there's no tagged release or SemVer guarantee until 1.0.
- **No support guarantee.** This is built nights-and-weekends — issues and discussions are read, but a response time isn't promised.
- **macOS 14+ and a Metal-capable GPU are required**, by design. There's no Linux or Windows path.

That said, contributions and ideas are genuinely welcome. The [roadmap](#roadmap) above is the best source of bite-size work — the *more primitives* line (`rect`, `line`, `ellipse`, …) in particular maps onto small, self-contained pull requests. For anything larger, please open an issue to discuss it before sending a big change.
