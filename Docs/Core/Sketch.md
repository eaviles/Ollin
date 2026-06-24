#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Core](./README.md) → `Sketch`</sup>

---

## Sketch

A sketch is a subclass of `Sketch`. Override `setup()` and `draw()`, call the bare drawing functions, and the loop runs `draw()` continuously at the display's refresh rate, so motion is the default. Useful temporal state (`time`, `frameCount`, …) is ready with no setup.

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

- [Lifecycle](#lifecycle) - `setup`, `draw`, `mousePressed`/`mouseReleased`, `keyPressed`/`keyReleased`, `onReload`
- [Temporal state](#temporal-state) - `frameCount`, `time`, `deltaTime`, `frameRate`
- [Canvas](#canvas) - `width`, `height`
- [Loop control](#loop-control) - `noLoop`, `loop`, `isLooping`
- [Extensions](#extensions) - `extend`, and writing a `SketchExtension`
- [Configuration](#configuration) - `title`, `canvasSize`, `windowMode`
- [Running a sketch](#running-a-sketch)

Canvas sizing, `scale`, export resolution, and the preview window have their own page: [Canvas](../Core/Canvas.md).

<a name="lifecycle"></a>

### Lifecycle

Override these on your subclass.

<a name="setup"></a>

#### setup

```swift
setup()
```

Called once, after the canvas size is known, before the first `draw()`. Optional.

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

Called every frame. Do your drawing here.

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

Called once each time a mouse button is pressed or released over the canvas. For continuous response while the button is *held*, poll `mouseIsPressed` in `draw()` instead. See [Input](../Helpers/Input.md).

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

Called once each time a key is pressed or released; `key`/`keyCode` hold the key. For movement while a key is *held*, poll `isKeyDown(_:)` in `draw()` instead. See [Input](../Helpers/Input.md).

```swift
override func keyPressed() {
    if key == " " { noLoop() }   // space pauses
}
```

<a name="onReload"></a>

#### onReload

```swift
onReload()
```

Called once after the live-reload host hot-swaps the sketch, right after its `setup()` (never on first launch). See the [iteration workflow](../../README.md#iteration-workflow).

<a name="temporal-state"></a>

### Temporal state

Read-only, and ready in any sketch with no setup:

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

<a name="canvas"></a>

### Canvas

| Property | Type | Meaning |
|---|---|---|
| `width` / `height` | `Double` | canvas size in logical points; updates live on resize |

```swift
drawCircle(width / 2, height / 2, min(width, height) / 4)   // centered, proportional
```

To keep a sketch looking the same at every canvas size, write it relative to the canvas with `scale` and `width`/`height` fractions. That, the `canvasSize` export presets, and the preview window are all on the [Canvas](../Core/Canvas.md) page.

<a name="loop-control"></a>

### Loop control

<a name="noLoop"></a>

#### noLoop / loop

```swift
noLoop()
loop()
```

Stop or resume the continuous draw loop; `isLooping` reads the current state. Motion is on by default, so `noLoop()` is the still-image escape hatch.

```swift
override func setup() {
    noLoop()   // one frame, then hold
}
```

<a name="extensions"></a>

### Extensions

`extend(_:)` registers a `SketchExtension` — a reusable object whose hooks the loop calls around each frame, so cross-cutting behavior (overlays, guides, recorders) lives outside `draw()`. Every hook is optional:

| Hook | When | For |
|---|---|---|
| `setup(_:)` | once, after the sketch's `setup()` | one-time prep |
| `beforeDraw(_:)` | each frame, before `draw()` | set up per-frame state |
| `afterDraw(_:)` | each frame, after `draw()`, before the render | draw *over* the sketch through the bare API |
| `afterFrame(_:_:)` | each frame, after the render, with `FrameInfo` timing | observe (fps, frame time, geometry counts) without drawing |
| `frameRendered(_:_:)` | each frame, after the render, with the rendered `CGImage` | grab the rendered pixels — save, record, or snapshot |

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

Extensions are per-instance, so register them in `setup()` — a fresh instance (including each live-reload swap) starts with none. A worked example is `Examples/Basic/Guides`.

`frameRendered(_:_:)` hands over the rendered frame as a `CGImage`. Grabbing it costs a GPU→CPU readback, so it's off until an extension opts in by returning `true` from `wantsRenderedFrame` (read every frame, so capture can be armed and disarmed on the fly). `Examples/Export/Capture` saves a frame to a PNG on a keypress this way. For a one-off without a window, `OllinApp.image(of: sketch, frame:)` renders a sketch headlessly and returns the `CGImage` directly — the same capture `--export` writes to disk, and what the render-correctness snapshot tests compare against committed references.

<a name="configuration"></a>

### Configuration

Override on your subclass to customize the window and size.

<a name="title"></a>

#### title

```swift
title: String
```

Window title. Defaults to `"Ollin - <SketchType>"` (e.g. "Ollin - HelloCircle").

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

The render/export resolution and how the preview window behaves. Both are documented, with the presets and modes, on the [Canvas](../Core/Canvas.md) page.

```swift
override var canvasSize: CanvasSize { .uhd4K }        // 4K master
override var canvasSize: CanvasSize { .square(1000) } // a custom square
override var windowMode: WindowMode { .fixed(0.5) }   // preview at half size
```

<a name="running-a-sketch"></a>

### Running a sketch

`OllinApp.run(MySketch())` boots a window. With `@main` on the subclass, the inherited `Sketch.main()` does that for you, so a single file is the whole program. To iterate with live reload, run it through the host instead: `swift run OllinLive path/to/Sketch.swift` (see the [iteration workflow](../../README.md#iteration-workflow)). Any sketch can also render headlessly: a single frame with `--export`, or a deterministic numbered PNG sequence with `--export-sequence <dir> (--frames N | --seconds D) [--fps F] [--skip S]` (a fixed-timestep render that assembles into a video; `--skip` runs the sketch a while first so a stateful sketch settles before capture — see [exporting frames](../../README.md#exporting-frames)).
