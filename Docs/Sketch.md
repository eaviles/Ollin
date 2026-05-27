#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Sketch`</sup>

---

### Sketch

A sketch is a subclass of `Sketch`. Override `setup()` and `draw()`, call the bare drawing functions, and the loop runs `draw()` continuously at the display's refresh rate, so motion is the default. Useful temporal state (`time`, `frameCount`, …) is ready with no setup.

### Example

```swift
import Ollin

@main
final class HelloCircle: Sketch {
    override func draw() {
        background(.white)
        circle(x: width / 2, y: height / 2, radius: 120 + sin(time) * 40)
    }
}
```

### Contents

- [Lifecycle](#lifecycle) - `setup`, `draw`, `mousePressed`, `onReload`
- [Temporal state](#temporal-state) - `frameCount`, `time`, `deltaTime`, `frameRate`
- [Canvas](#canvas) - `width`, `height`, `scale`
- [Loop control](#loop-control) - `noLoop`, `loop`, `isLooping`
- [Configuration](#configuration) - `title`, `preferredSize`
- [Running a sketch](#running-a-sketch)

### Lifecycle

Override these on your subclass.

<a name="setup"></a>

### `setup()`

Called once, after the canvas size is known, before the first `draw()`. Optional.

<a name="draw"></a>

### `draw()`

Called every frame. Do your drawing here.

<a name="mousePressed"></a>

### `mousePressed()`

Called once each time a mouse button is pressed over the canvas. See [Input](./Input.md).

<a name="onReload"></a>

### `onReload()`

Called once after the live-reload host hot-swaps the sketch, right after its `setup()` (never on first launch). See the [iteration workflow](../README.md#iteration-workflow).

### Temporal state

Read-only, and ready in any sketch with no setup:

| Property | Type | Meaning |
|---|---|---|
| `frameCount` | `Int` | frames drawn so far (1 during the first `draw()`) |
| `time` | `Double` | seconds since the sketch started |
| `deltaTime` | `Double` | seconds since the previous frame |
| `frameRate` | `Double` | smoothed frames per second |

### Canvas

| Property | Type | Meaning |
|---|---|---|
| `width` / `height` | `Double` | canvas size in logical points; updates live on resize |
| `scale` | `Double` | `min(width, height) / 1000`; multiply sizes by it so a sketch holds its proportions at any canvas size |

### Loop control

<a name="noLoop"></a>

### `noLoop()` / `loop()`

Stop or resume the continuous draw loop; `isLooping` reads the current state. Motion is on by default, so `noLoop()` is the still-image escape hatch.

### Configuration

Override to customize the window.

<a name="title"></a>

### `title: String`

Window title. Defaults to `"Ollin - <SketchType>"` (e.g. "Ollin - HelloCircle").

<a name="preferredSize"></a>

### `preferredSize: CGSize`

Initial window size. Defaults to 800×800.

### Running a sketch

`OllinApp.run(MySketch())` boots a window. With `@main` on the subclass, the inherited `Sketch.main()` does that for you, so a single file is the whole program. To iterate with live reload, run it through the host instead: `swift run OllinLive path/to/Sketch.swift` (see the [iteration workflow](../README.md#iteration-workflow)). Any sketch can also render a frame headlessly with `--export` (see [exporting frames](../README.md#exporting-frames)).
