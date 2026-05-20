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
- **Rendering:** Metal (`MTKView`, 4× MSAA), Foundation / SwiftUI / Metal / MetalKit / simd only — **no third-party dependencies**
- **License:** MIT

> Status: early. The win right now is "I can `swift run` and see a black circle
> outline on white, with a continuous draw loop already humming underneath."
> Then we iterate.

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
swift run OllinSketch
```

That builds the package and opens an 800×800 window running `HelloCircle`.

## Add Ollin to your own package (SPM)

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/eaviles/ollin.git", branch: "main")
],
targets: [
    .executableTarget(
        name: "MySketch",
        dependencies: [.product(name: "Ollin", package: "ollin")]
    )
]
```

## Iteration workflow

Creative coding lives or dies by how fast you can edit → see. A few options,
fastest feedback first:

1. **Edit & re-run.** Tweak a sketch and run `swift run OllinSketch`. Incremental
   builds keep this snappy. This is the recommended default loop.
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

Contributions and ideas welcome.
