#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Core](./README.md) → `Canvas`</sup>

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
- [The performance panel](#stats-overlay)
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

#### scale

```swift
scale: Double
```

A read-only factor that grows and shrinks with the canvas; multiply sizes by it so a sketch holds its proportions at any size. (Distinct from the `scale(_:)` transform in [Drawing](../Drawing/Drawing.md), which scales the coordinate system.)

```swift
drawCircle(width / 2, height / 2, 120 * scale)
strokeWeight(2 * scale)
```

<a name="canvasSize"></a>

### Export size

`canvasSize` is the resolution a sketch renders and exports at, in whole pixels (a canvas is an integer grid). Its type is `CanvasSize`, and it defaults to `.square1080` (1080×1080), a 1:1 square. Override it on a subclass with one of the named presets below (`override var canvasSize: CanvasSize { .uhd4K }`):

| Constant | Pixels | Aspect | Good for |
|---|---|---|---|
| `.square1080` | 1080 × 1080 | 1:1 | the default; square social and feed posts |
| `.square1440` | 1440 × 1440 | 1:1 | a larger square |
| `.square2160` | 2160 × 2160 | 1:1 | a 4K-class square master |
| `.hd720` | 1280 × 720 | 16:9 | 720p / HD |
| `.fhd1080` | 1920 × 1080 | 16:9 | 1080p / Full HD |
| `.qhd1440` | 2560 × 1440 | 16:9 | 1440p / QHD |
| `.uhd4K` | 3840 × 2160 | 16:9 | 4K / UHD, the usual "4K video" deliverable |
| `.dci4K` | 4096 × 2160 | ~17:9 | cinema 4K (DCI), for film delivery |
| `.vertical1080` | 1080 × 1920 | 9:16 | full-screen vertical: stories, reels, TikTok, Shorts |
| `.portrait1080` | 1080 × 1350 | 4:5 | the portrait feed crop (for example Instagram) |
| `.usLetter` | 612 × 792 | 8.5:11 | US Letter paper (8.5×11 in), for PDF export |
| `.usLegal` | 612 × 1008 | 8.5:14 | US Legal paper (8.5×14 in), for PDF export |
| `.a3` | 842 × 1191 | 1:√2 | ISO A3 paper (297×420 mm), for PDF export |
| `.a4` | 595 × 842 | 1:√2 | ISO A4 paper (210×297 mm), for PDF export |
| `.a5` | 420 × 595 | 1:√2 | ISO A5 paper (148×210 mm), for PDF export |

The paper presets are sized in PDF points (72 per inch) and come portrait like the physical sheet: [PDF export](../Output/Export.md#vector-pdf) maps one canvas pixel to one point, so a sketch on `.a4` exports as a true A4 page, and the vector geometry prints sharp at any resolution. When the *raster* export needs print resolution too, add `.dpi(_:)`: `.a4.dpi(300)` renders and `--export`s at 2479×3508 pixels (300 dots per inch) while `--export-pdf` still writes the page at exactly A4, the pixel geometry scaled back onto it. It works on any size (the size it's called on is taken as the 72-dpi page), and `.dpi(72)` is the identity.

Use `.portrait` / `.landscape` to flip any preset's orientation, so `.uhd4K.portrait` is 2160×3840 and `.a4.landscape` is 842×595; the flips compose with `.dpi(_:)` in either order. Headless `--export` always renders at `canvasSize`, so a sketch produces the same pixels on any machine; `--export-sequence <dir> --frames N` renders a deterministic numbered PNG sequence (fixed timestep, so it's reproducible and assembles into a smooth video; see [Sketch ▸ Running a sketch](../Core/Sketch.md#running-a-sketch)).

For a custom size, override `canvasSize` with `.square(_)` (a square) or `.size(_, _)` (any rectangle):

```swift
final class MySketch: Sketch {
    override var canvasSize: CanvasSize { .square(1000) }    // a 1000×1000 canvas
    // override var canvasSize: CanvasSize { .size(1000, 600) }   // or any rectangle

    override func draw() {
        background(.white)
        drawCircle(width / 2, height / 2, 300)
    }
}
```

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

<a name="stats-overlay"></a>

### The performance panel

When a sketch feels slow, **View ▸ Show Inspector** (⌘/) opens a floating panel beside the sketch window: frame rate, the CPU time spent building a frame, the geometry the frame emitted (vertices, SDF shapes, point-cloud splats, and GPU particles), the clock, and the canvas size, with a slider for each of the sketch's `@Param` knobs below. Toggle it back off the same way.

It's a separate utility window, not in-canvas drawing, so it never appears in an exported frame — `--export` renders only the canvas. The CPU time is the cost of building a frame on the draw thread, the first thing to climb when a sketch gets heavy, and it reads far lower in a release build (`swift run -c release`) than the default debug build.

The live host (`OllinLive`) shows the same readout in its own inspector sidebar, so there it's built into the window.

<a name="retina"></a>

### Retina and pixel density

The preview is crisp on Retina displays with nothing to switch on: it renders at the screen's native pixel density. Export renders directly at `canvasSize`, so a 1080² export is exactly 1080×1080 pixels.

<a name="planned-uv"></a>

### Planned: normalized `u, v` coordinates

A later addition may offer normalized `u, v` positions (0…1 across the canvas) alongside points, so a sketch can place things without referring to `width`/`height`. Until then, `scale` and `width`/`height` fractions are the way to stay resolution-independent.
