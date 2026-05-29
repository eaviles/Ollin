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
        drawCircle(width / 2, height / 2, 120 + sin(time) * 40)
    }
}
```

### Contents

- [Lifecycle](#lifecycle) - `setup`, `draw`, `mousePressed`, `onReload`
- [Temporal state](#temporal-state) - `frameCount`, `time`, `deltaTime`, `frameRate`
- [Canvas](#canvas) - `width`, `height`, `scale`
- [Size and resolution independence](#size-and-resolution-independence) - `canvasSize`, the preview window, writing with `scale`
- [Loop control](#loop-control) - `noLoop`, `loop`, `isLooping`
- [Configuration](#configuration) - `title`, `canvasSize`, `windowMode`
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
| `scale` | `Double` | a factor that grows and shrinks with the canvas; multiply sizes by it so a sketch holds its proportions at any size |

### Size and resolution independence

Coordinates are in **logical points**, with a top-left origin and y increasing downward (the same as p5, Processing, and OPENRNDR). Inside `draw()`, `width` and `height` are the canvas size in those points.

A sketch is drawn once but seen at more than one size: a preview window that fits your screen, and a fixed-resolution export. To keep a piece looking the same at every size, write it relative to the canvas instead of in fixed pixels. Two tools cover that:

- **`scale`** grows and shrinks with the canvas, so multiplying a feature size by it holds that size's proportion at any canvas size. Pick the size you'd want on a roughly 1000-point canvas and multiply: a `12 * scale` dot, a `375 * scale` radius.
- **`width` / `height` fractions** suit layout: `width * 0.8` for a centered block, `height / 8` for a wave's amplitude, `min(width, height) * 0.125` for an inset.

```swift
override func draw() {
    background(.black)
    // Same composition at any canvas size.
    fill(.white)
    drawCircle(width / 2, height / 2, 300 * scale)
}
```

A bare `drawCircle(400, 400, 150)` ties the sketch to one canvas size, and the same call lands somewhere else once the canvas changes. Reach for `scale` and fractions instead.

<a name="export-size"></a>

#### Export size

`canvasSize` is the resolution a sketch renders and exports at, in pixels. It defaults to `.square1080` (1080×1080), a 1:1 square. Override it on a subclass with one of the named presets, or any `CGSize`:

```swift
override var canvasSize: CGSize { .uhd4K }            // 4K landscape master (3840×2160)
override var canvasSize: CGSize { .uhd4K.portrait }   // 4K vertical (2160×3840)
override var canvasSize: CGSize { .portrait1080 }     // 4:5 portrait (1080×1350)
```

The presets cover square (`square1080` / `square1440` / `square2160`), 16:9 (`hd720` / `fhd1080` / `qhd1440` / `uhd4K`, plus cinema `dci4K`), vertical 9:16 (`vertical1080`), and 4:5 (`portrait1080`). Use `.portrait` / `.landscape` to flip orientation. For social posts: square → `.square1080`, story or reel → `.vertical1080`, portrait feed → `.portrait1080`. Headless `--export` always renders at `canvasSize`, so a sketch produces the same pixels on any machine.

<a name="the-preview-window"></a>

#### The preview window

The on-screen window does not have to match `canvasSize`; a 1080² (or 4K) sketch would overflow a laptop. `windowMode` controls the window, relative to `canvasSize`:

- **`.auto`** (the default) opens at 1:1 when the screen has room for the full `canvasSize`, and steps down to the largest clean fraction (¾, ½, …) that fits otherwise, so it always fits. A 1080² sketch opens at 1080 on a roomy or external display, and at ¾ (810pt) on a 14"/16" laptop.
- **`.fixed(_)`** pins an explicit fraction of `canvasSize` and ignores the screen: `.fixed(0.5)` is always half size, `.fixed(1)` always 1:1.
- **`.resizable`** opens a freely resizable window (at the auto-fit size) and lets the canvas follow it live, for sketches designed for the screen rather than a fixed export. Draw with `scale` / `width` / `height` and the piece adapts as you drag the window.

`.auto` and `.fixed` lock the window; `.resizable` does not. (Resizing applies to the standalone `swift run` window today; the examples gallery and live host show the sketch at the auto-fit size with a collapsible sidebar.)

Either way, a sketch written with `scale` composes the same at the preview size and the export size, so what you see while iterating matches the exported frame. That is what keeps the export dependable for video and Instagram.

#### Retina and pixel density

The preview is crisp on Retina displays with nothing to switch on: it renders at the screen's native pixel density. Export renders directly at `canvasSize`, so a 1080² export is exactly 1080×1080 pixels.

#### Planned: normalized `u, v` coordinates

A later addition may offer normalized `u, v` positions (0…1 across the canvas) alongside points, so a sketch can place things without referring to `width`/`height`. Until then, `scale` and `width`/`height` fractions are the way to stay resolution-independent.

### Loop control

<a name="noLoop"></a>

### `noLoop()` / `loop()`

Stop or resume the continuous draw loop; `isLooping` reads the current state. Motion is on by default, so `noLoop()` is the still-image escape hatch.

### Configuration

Override on your subclass to customize size and window.

<a name="title"></a>

### `title: String`

Window title. Defaults to `"Ollin - <SketchType>"` (e.g. "Ollin - HelloCircle").

<a name="canvasSize"></a>

### `canvasSize: CGSize`

The render and PNG-export resolution, in pixels. Defaults to `Sketch.defaultSize` (1080×1080). Override for a higher-resolution master (1440²/2160²/2880²) or a non-square aspect (e.g. 1080×1350). See [Export size](#export-size).

<a name="windowMode"></a>

### `windowMode: WindowMode`

How the preview window behaves, relative to `canvasSize`: `.auto` (default) fits the screen, `.fixed(_)` pins a zoom (e.g. `.fixed(0.5)`), `.resizable` opens a freely resizable window whose canvas follows it. See [the preview window](#the-preview-window).

### Running a sketch

`OllinApp.run(MySketch())` boots a window. With `@main` on the subclass, the inherited `Sketch.main()` does that for you, so a single file is the whole program. To iterate with live reload, run it through the host instead: `swift run OllinLive path/to/Sketch.swift` (see the [iteration workflow](../README.md#iteration-workflow)). Any sketch can also render a frame headlessly with `--export` (see [exporting frames](../README.md#exporting-frames)).
