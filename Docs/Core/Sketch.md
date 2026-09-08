#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Core](./README.md) → `Sketch`</sup>

---

## Sketch

A sketch is a subclass of `Sketch`. You override `setup()` and `draw()`, then call the bare drawing functions inside them. The loop runs `draw()` continuously at the display's refresh rate, so motion is the default. Temporal state such as `time` and `frameCount` is ready to read with no setup.

### Example

```swift
import Ollin

@main
final class HelloCircle: Sketch {
    override func draw() {
        background(.white)
        drawCircle(width / 2, height / 2, 120 + sin(time) * 40)
    }
}
```

### Contents

- [Lifecycle](#lifecycle) - `setup`, `draw`, `mousePressed`/`mouseReleased`, `keyPressed`/`keyReleased`, `filesDropped`, `reloaded`
- [Temporal state](#temporal-state) - `frameCount`, `time`, `deltaTime`, `frameRate`
- [Canvas](#canvas) - `width`, `height`, `canvasOnScreen`, `screenFrame`
- [Loop control](#loop-control) - `noLoop`, `loop`, `isLooping`
- [Extensions](#extensions) - `extend`, and writing a `SketchExtension`
- [Configuration](#configuration) - `title`, `canvasSize`, `windowMode`, `loopDuration`, `installation`
- [Running a sketch](#running-a-sketch)

Canvas sizing, `scale`, export resolution, and the preview window have their own page, [Canvas](../Core/Canvas.md).

<a name="lifecycle"></a>

### Lifecycle

Override these on your subclass.

<a name="setup"></a>

#### setup

```swift
setup()
```

Ollin calls this once, after the canvas size is known and before the first `draw()`. Overriding it is optional.

```swift
override func setup() {
    noLoop()   // render a single still frame
}
```

<a name="draw"></a>

#### draw

```swift
draw()
```

Ollin calls this every frame. Do your drawing here.

```swift
override func draw() {
    background(.white)
    drawCircle(width / 2, height / 2, 100)
}
```

<a name="mousePressed"></a>

#### mousePressed / mouseReleased

```swift
mousePressed()
mouseReleased()
```

Ollin calls these once each time a mouse button is pressed or released over the canvas. To respond continuously while the button is *held*, poll `mouseIsPressed` in `draw()` instead. See [Input](../Helpers/Input.md).

```swift
override func mousePressed() {
    randomSeed(frameCount)   // re-roll on click
}
```

<a name="keyPressed"></a>

#### keyPressed / keyReleased

```swift
keyPressed()
keyReleased()
```

Ollin calls these once each time a key is pressed or released. `key` and `keyCode` hold the key. To keep something moving while a key is *held*, poll `isKeyDown(_:)` in `draw()` instead. See [Input](../Helpers/Input.md).

```swift
override func keyPressed() {
    if key == " " { noLoop() }   // space pauses
}
```

<a name="filesDropped"></a>

#### filesDropped

```swift
filesDropped()
```

Ollin calls this once each time files are dropped on the window. `droppedFiles()` holds their paths and `mouseX`/`mouseY` where they landed. To pick them up later instead, poll `droppedFiles()` in `draw()`. See [Input](../Helpers/Input.md#droppedFiles).

```swift
override func filesDropped() {
    for path in droppedFiles() { photo = loadImage(path) ?? photo }
}
```

<a name="reloaded"></a>

#### reloaded

```swift
reloaded()
```

Ollin calls this once after the live-reload host hot-swaps the sketch, right after the new sketch's `setup()`. It never runs on first launch. See [live reload](../../README.md#live-reload).

<a name="temporal-state"></a>

### Temporal state

These properties are read-only, and they are ready in any sketch with no setup:

| Property | Type | Meaning |
|---|---|---|
| `deltaTime` | `Double` | seconds since the previous frame |
| `frameCount` | `Int` | frames drawn so far (1 during the first `draw()`) |
| `frameRate` | `Double` | smoothed frames per second |
| `time` | `Double` | seconds since the sketch started |

```swift
let r = 120 + sin(time) * 40            // animate against the clock
drawCircle(width / 2, height / 2, r)
```

When a frame takes longer than one display refresh, Ollin drops the refreshes it
cannot serve rather than queueing them. It does not call `draw()` for a dropped
refresh, so `frameCount` counts only the frames drawn, and `deltaTime` reports
the real gap between them. The window keeps answering the mouse while the
picture runs slow, and motion scaled by `deltaTime` still runs at the right
speed.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/03-MotionAndTime/DeltaTime-dark.jpg">
  <img src="../../Guide/Images/03-MotionAndTime/DeltaTime.jpg" alt="Three dotted strips comparing one second of motion: a fixed per-frame step at 60 fps, the same step at 120 fps reaching twice as far, and a deltaTime-scaled step landing back in line" width="680">
</picture>

For repeating motion on a fixed period, [`loopProgress(over:)` and `pingPong(over:)`](../Helpers/Animation.md#loop) wrap the clock into looping `0...1` progress.

Beside the clock, the `Int` property `variation` names the seed this run's randomness came from. Ollin rolls it fresh unless the sketch calls `seed(_:)`. It is also the value the inspector's Variation card steps through, and the value every export's recipe records. See [Variations](./Variations.md).

<a name="canvas"></a>

### Canvas

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/01-HelloOllin/CoordinateSystem-dark.jpg">
  <img src="../../Guide/Images/01-HelloOllin/CoordinateSystem.jpg" alt="The canvas coordinate system: origin at the top left, x right, y down, with the point (380, 240) marked" width="680">
</picture>

| Property | Type | Meaning |
|---|---|---|
| `width` / `height` | `Double` | canvas size in logical points, updated live on resize |
| `canvasOnScreen` | `Rectangle?` | where this canvas sits on the desk, in screen points, or `nil` with no window |
| `screenFrame` | `Rectangle?` | the screen it sits on, in the same coordinates |

```swift
drawCircle(width / 2, height / 2, min(width, height) / 4)   // centered, proportional
```

`canvasOnScreen` is measured the same way the canvas is. The origin is the top-left corner of the main screen, and y grows downward. Every window on the desk reports its place in those same numbers, so several windows can show one shared world.

The rectangle covers the canvas alone, so a title bar or a sidebar falls outside it. It follows the window, which means a drag shows up in the next frame. An export has no window, so both properties read `nil` there. The `Installation/ManyWindows` example is built on these two properties.

To keep a sketch looking the same at every canvas size, write it relative to the canvas with `scale` and fractions of `width` and `height`. The [Canvas](../Core/Canvas.md) page covers that, along with the `canvasSize` export presets and the preview window. For how this coordinate frame compares with the others a sketch meets, see [Where a point is](../Concepts/Coordinates.md).

<a name="loop-control"></a>

### Loop control

<a name="noLoop"></a>

#### noLoop / loop

```swift
noLoop()
loop()
```

`noLoop()` stops the continuous draw loop and `loop()` resumes it. `isLooping` reads the current state. Motion is on by default, so call `noLoop()` when you want a still image.

```swift
override func setup() {
    noLoop()   // one frame, then hold
}
```

<a name="extensions"></a>

### Extensions

`extend(_:)` registers a `SketchExtension`. That is a reusable object whose hooks the loop calls around each frame. Behavior that spans a whole sketch, such as overlays, guides, and recorders, then lives outside `draw()`. Every hook is optional:

| Hook | When | For |
|---|---|---|
| `setup(_:)` | once, after the sketch's `setup()` | one-time prep |
| `beforeDraw(_:)` | each frame, before `draw()` | set up per-frame state |
| `afterDraw(_:)` | each frame, after `draw()`, before the render | draw *over* the sketch through the bare API |
| `afterFrame(_:_:)` | each frame, after the render, with `FrameInfo` timing | observe (fps, frame time, geometry counts) without drawing |
| `frameRendered(_:_:)` | each frame, after the render, with the rendered `CGImage` | grab the rendered pixels to save, record, or snapshot |

```swift
final class Guides: SketchExtension {
    func afterDraw(_ sketch: Sketch) {
        sketch.withState {
            sketch.stroke(Color(white: 0, alpha: 0.25))
            sketch.drawLine(sketch.width / 2, 0, sketch.width / 2, sketch.height)
        }
    }
}

final class MySketch: Sketch {
    override func setup() { extend(Guides()) }
}
```

Extensions belong to one sketch instance, so register them in `setup()`. A fresh instance starts with none, and each live-reload swap makes a fresh instance. `Examples/Basic/Guides` is a worked example.

`frameRendered(_:_:)` hands over the rendered frame as a `CGImage`. Reading those pixels back from the GPU to the CPU costs time, so the hook stays off by default. An extension opts in by returning `true` from `wantsRenderedFrame`. Ollin reads that property every frame, so an extension can arm and disarm capture while the sketch runs. `Examples/Export/Capture` uses it to save a frame to a PNG on a keypress. For a one-off capture without a window, `OllinApp.image(of: sketch, frame:)` renders a sketch headlessly and returns the `CGImage` directly. That is the same capture `--export` writes to disk, and the one the render-correctness snapshot tests compare against committed references.

<a name="configuration"></a>

### Configuration

Override these on your subclass to change the window and the size.

<a name="title"></a>

#### title

```swift
title: String
```

The window title. It defaults to `"Ollin - <SketchType>"`, for example "Ollin - HelloCircle".

```swift
override var title: String { "Flow field" }
```

<a name="canvasSize"></a>
<a name="windowMode"></a>

#### canvasSize / windowMode

```swift
canvasSize: CanvasSize
windowMode: WindowMode
```

`canvasSize` sets the resolution used to render and to export, and `windowMode` sets how the preview window behaves. The [Canvas](../Core/Canvas.md) page documents both, with the presets and the modes.

```swift
override var canvasSize: CanvasSize { .uhd4K }        // 4K master
override var canvasSize: CanvasSize { .square(1000) } // a custom square
override var windowMode: WindowMode { .fixed(0.5) }   // preview at half size
```

<a name="loopDuration"></a>

#### loopDuration

```swift
loopDuration: Double?
```

The length of the sketch's loop in seconds. The default is `nil`, which means the sketch declares no loop. If the motion repeats exactly, declare its period here, and `--export-loop` then renders exactly one lap for a seamless GIF or video. See [perfect loops](../Output/Export.md#perfect-loops).

```swift
override var loopDuration: Double? { 6 }   // repeats every 6 seconds
```

<a name="installation"></a>

#### installation

```swift
installation: Installation
```

What the piece needs to run by itself for days. The default is `.off`, which suits a sketch you run at a desk. `.on` fills the screen, hides the pointer, and keeps the display awake. Add `checkpoint:` and Ollin writes down every `@Saved` property, so a relaunch resumes where the run left off. Add `restarts:` and Ollin starts the run again if it crashes or stops answering. Add `schedule:` to set the hours the piece is on screen, and the sketch reads back the parts of the day with `scheduledPeriod`. Add `displays:` and one canvas spans every display the machine drives. See [running unattended](../Output/Installation.md).

```swift
override var installation: Installation { .on }
```

<a name="running-a-sketch"></a>

### Running a sketch

`OllinApp.run(MySketch())` opens a window and runs the sketch. With `@main` on the subclass, the inherited `Sketch.main()` does that for you, so a single file is the whole program. To iterate with live reload, run the sketch through the host instead with `swift run OllinLive path/to/Sketch.swift`, described under [live reload](../../README.md#live-reload).

Any sketch can also render headlessly. `--export` writes a single frame. `--export-sequence <dir> (--frames N | --seconds D) [--fps F] [--skip S]` writes a deterministic numbered PNG sequence that assembles into a video, rendered at a fixed timestep. `--skip S` runs the sketch for a while first, so a stateful sketch settles before capture. See [export](../../README.md#export).

The same flags work on a loose watched file through the live host, as in `swift run OllinLive path/to/Sketch.swift --export-gif loop.gif --seconds 4`. That command compiles the file and exports instead of opening a window. The full flag set covers video, GIF, perfect loops, SVG, and render quality, and it is listed in [Export](../Output/Export.md).
