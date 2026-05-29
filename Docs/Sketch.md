#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Sketch`</sup>

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

- [Lifecycle](#lifecycle) - `setup`, `draw`, `mousePressed`, `onReload`
- [Temporal state](#temporal-state) - `frameCount`, `time`, `deltaTime`, `frameRate`
- [Canvas](#canvas) - `width`, `height`
- [Loop control](#loop-control) - `noLoop`, `loop`, `isLooping`
- [Configuration](#configuration) - `title`, `canvasSize`, `windowMode`
- [Running a sketch](#running-a-sketch)

Canvas sizing, `scale`, export resolution, and the preview window have their own page: [Canvas](./Canvas.md).

<a name="lifecycle"></a>

### Lifecycle

Override these on your subclass.

<a name="setup"></a>

#### `setup()`

Called once, after the canvas size is known, before the first `draw()`. Optional.

```swift
override func setup() {
    noLoop()   // render a single still frame
}
```

<a name="draw"></a>

#### `draw()`

Called every frame. Do your drawing here.

```swift
override func draw() {
    background(.white)
    drawCircle(width / 2, height / 2, 100)
}
```

<a name="mousePressed"></a>

#### `mousePressed()`

Called once each time a mouse button is pressed over the canvas. See [Input](./Input.md).

```swift
override func mousePressed() {
    randomSeed(frameCount)   // re-roll on click
}
```

<a name="onReload"></a>

#### `onReload()`

Called once after the live-reload host hot-swaps the sketch, right after its `setup()` (never on first launch). See the [iteration workflow](../README.md#iteration-workflow).

<a name="temporal-state"></a>

### Temporal state

Read-only, and ready in any sketch with no setup:

| Property | Type | Meaning |
|---|---|---|
| `frameCount` | `Int` | frames drawn so far (1 during the first `draw()`) |
| `time` | `Double` | seconds since the sketch started |
| `deltaTime` | `Double` | seconds since the previous frame |
| `frameRate` | `Double` | smoothed frames per second |

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

To keep a sketch looking the same at every canvas size, write it relative to the canvas with `scale` and `width`/`height` fractions. That, the `canvasSize` export presets, and the preview window are all on the [Canvas](./Canvas.md) page.

<a name="loop-control"></a>

### Loop control

<a name="noLoop"></a>

#### `noLoop()` / `loop()`

Stop or resume the continuous draw loop; `isLooping` reads the current state. Motion is on by default, so `noLoop()` is the still-image escape hatch.

```swift
override func setup() {
    noLoop()   // one frame, then hold
}
```

<a name="configuration"></a>

### Configuration

Override on your subclass to customize the window and size.

<a name="title"></a>

#### `title: String`

Window title. Defaults to `"Ollin - <SketchType>"` (e.g. "Ollin - HelloCircle").

```swift
override var title: String { "Flow field" }
```

<a name="canvasSize"></a>
<a name="windowMode"></a>

#### `canvasSize: CGSize` / `windowMode: WindowMode`

The render/export resolution and how the preview window behaves. Both are documented, with the presets and modes, on the [Canvas](./Canvas.md) page.

```swift
override var canvasSize: CGSize { .uhd4K }            // 4K master
override var windowMode: WindowMode { .fixed(0.5) }   // preview at half size
```

<a name="running-a-sketch"></a>

### Running a sketch

`OllinApp.run(MySketch())` boots a window. With `@main` on the subclass, the inherited `Sketch.main()` does that for you, so a single file is the whole program. To iterate with live reload, run it through the host instead: `swift run OllinLive path/to/Sketch.swift` (see the [iteration workflow](../README.md#iteration-workflow)). Any sketch can also render a frame headlessly with `--export` (see [exporting frames](../README.md#exporting-frames)).
