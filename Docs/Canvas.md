#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Canvas`</sup>

---

## Canvas, size, and export

A sketch is drawn once but seen at more than one size: a preview window that fits your screen, and a fixed-resolution export. Write a sketch relative to the canvas and it holds up at any size. This page covers `scale`, the `canvasSize` export presets, and the preview window.

### Example

```swift
override func draw() {
    background(.black)
    // The same composition at any canvas size.
    fill(.white)
    drawCircle(width / 2, height / 2, 300 * scale)
}
```

### Contents

- [Resolution independence](#resolution-independence)
- [scale](#scale)
- [Export size](#canvasSize)
- [The preview window](#windowMode)
- [Retina and pixel density](#retina)
- [Planned: normalized u, v](#planned-uv)

<a name="resolution-independence"></a>

### Resolution independence

Coordinates are in **logical points**, with a top-left origin and y increasing downward (the same as p5, Processing, and OPENRNDR). Inside `draw()`, `width` and `height` are the canvas size in those points.

To keep a piece looking the same at every size, write it relative to the canvas instead of in fixed pixels. Two tools cover that:

- **`scale`** grows and shrinks with the canvas, so multiplying a feature size by it holds that size's proportion at any canvas size. Pick the size you'd want on a roughly 1000-point canvas and multiply: a `12 * scale` dot, a `375 * scale` radius.
- **`width` / `height` fractions** suit layout: `width * 0.8` for a centered block, `height / 8` for a wave's amplitude, `min(width, height) * 0.125` for an inset.

A bare `drawCircle(400, 400, 150)` ties the sketch to one canvas size, and the same call lands somewhere else once the canvas changes. Reach for `scale` and fractions instead.

<a name="scale"></a>

#### `scale: Double`

A read-only factor that grows and shrinks with the canvas; multiply sizes by it so a sketch holds its proportions at any size. (Distinct from the `scale(_:)` transform in [Drawing](./Drawing.md), which scales the coordinate system.)

```swift
drawCircle(width / 2, height / 2, 120 * scale)
strokeWeight(2 * scale)
```

<a name="canvasSize"></a>

### Export size

`canvasSize` is the resolution a sketch renders and exports at, in pixels. It defaults to `.square1080` (1080×1080), a 1:1 square. Override it on a subclass with one of the named presets, or any `CGSize`:

```swift
override var canvasSize: CGSize { .uhd4K }            // 4K landscape master (3840×2160)
override var canvasSize: CGSize { .uhd4K.portrait }   // 4K vertical (2160×3840)
override var canvasSize: CGSize { .portrait1080 }     // 4:5 portrait (1080×1350)
```

The presets cover square (`square1080` / `square1440` / `square2160`), 16:9 (`hd720` / `fhd1080` / `qhd1440` / `uhd4K`, plus cinema `dci4K`), vertical 9:16 (`vertical1080`), and 4:5 (`portrait1080`). Use `.portrait` / `.landscape` to flip orientation. For social posts: square → `.square1080`, story or reel → `.vertical1080`, portrait feed → `.portrait1080`. Headless `--export` always renders at `canvasSize`, so a sketch produces the same pixels on any machine.

<a name="windowMode"></a>

### The preview window

The on-screen window does not have to match `canvasSize`; a 1080² (or 4K) sketch would overflow a laptop. `windowMode` controls the window, relative to `canvasSize`:

- **`.auto`** (the default) opens at 1:1 when the screen has room for the full `canvasSize`, and steps down to the largest clean fraction (¾, ½, …) that fits otherwise, so it always fits. A 1080² sketch opens at 1080 on a roomy or external display, and at ¾ (810pt) on a 14"/16" laptop.
- **`.fixed(_)`** pins an explicit fraction of `canvasSize` and ignores the screen: `.fixed(0.5)` is always half size, `.fixed(1)` always 1:1.
- **`.resizable`** opens a freely resizable window (at the auto-fit size) and lets the canvas follow it live, for sketches designed for the screen rather than a fixed export. Draw with `scale` / `width` / `height` and the piece adapts as you drag the window.

```swift
override var windowMode: WindowMode { .fixed(0.5) }   // always half of canvasSize
```

`.auto` and `.fixed` lock the window; `.resizable` does not. (Resizing applies to the standalone `swift run` window today; the examples gallery and live host show the sketch at the auto-fit size with a collapsible sidebar.)

Either way, a sketch written with `scale` composes the same at the preview size and the export size, so what you see while iterating matches the exported frame. That is what keeps the export dependable for video and Instagram.

<a name="retina"></a>

### Retina and pixel density

The preview is crisp on Retina displays with nothing to switch on: it renders at the screen's native pixel density. Export renders directly at `canvasSize`, so a 1080² export is exactly 1080×1080 pixels.

<a name="planned-uv"></a>

### Planned: normalized `u, v` coordinates

A later addition may offer normalized `u, v` positions (0…1 across the canvas) alongside points, so a sketch can place things without referring to `width`/`height`. Until then, `scale` and `width`/`height` fractions are the way to stay resolution-independent.
