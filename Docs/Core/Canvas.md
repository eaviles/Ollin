#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Core](./README.md) → `Canvas`</sup>

---

## Canvas, size, and export

You draw a sketch once, but it is seen at more than one size. There is a preview window that fits your screen, and there is a fixed-resolution export. If you write the sketch relative to the canvas, it holds up at either size. This page covers `scale`, the `canvasSize` export presets, and the preview window.

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
- [shortSide / longSide](#shortSide)
- [Export size](#canvasSize)
- [The preview window](#windowMode)
- [The performance panel](#stats-overlay)
- [Retina and pixel density](#retina)
- [Normalized coordinates: uv](#uv)

<a name="resolution-independence"></a>

### Resolution independence

Coordinates are in **logical points**. The origin is the top-left corner and y increases downward, the same as in p5, Processing, and OPENRNDR. Inside `draw()`, `width` and `height` are the canvas size in those points.

To keep a piece looking the same at every size, write it relative to the canvas instead of in fixed pixels. Two tools cover that:

- **`scale`** grows and shrinks with the canvas, so a size multiplied by it keeps its proportion at any canvas size. Pick the size you would want on a canvas of about 1000 points, then multiply: a `12 * scale` dot, a `375 * scale` radius.
- **`width` / `height` fractions** suit layout, such as `width * 0.8` for a centered block, `height / 8` for a wave's amplitude, and [`shortSide`](#shortSide)` * 0.125` for an inset. For *positions*, [`uv(u, v)`](#uv) states the same fractions as a single point, so you write `uv(0.5, 0.75)` instead of `Vector2(width * 0.5, height * 0.75)`.

A bare `drawCircle(400, 400, 150)` ties the sketch to one canvas size, because the same call lands somewhere else once the canvas changes. Use `scale` and fractions instead.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/01-HelloOllin/NormalizedPlacement-dark.jpg">
  <img src="../../Guide/Images/01-HelloOllin/NormalizedPlacement.jpg" alt="Two rows of three canvases each, square, wide, and tall. In the top row, marks placed at fixed pixel positions fall off the edges of the wide and tall canvases; in the bottom row, the same marks placed as fractions sit correctly in all three" width="680">
</picture>

<a name="scale"></a>

#### scale

```swift
scale: Double
```

A read-only factor that grows and shrinks with the canvas. Multiply your sizes by it so a sketch holds its proportions at any size. This is not the `scale(_:)` transform in [Drawing](../Drawing/Drawing.md), which scales the coordinate system.

```swift
drawCircle(width / 2, height / 2, 120 * scale)
strokeWeight(2 * scale)
```

<a name="shortSide"></a>

#### shortSide / longSide

```swift
shortSide: Double
longSide: Double
```

These are the two canvas edges by length. `shortSide` is `min(width, height)`,
and `longSide` is the other one. The short side decides how big something can
be and still fit whichever way the canvas turns, so `shortSide * 0.4` sizes a
centerpiece the same on a square, a wide, and a tall canvas.

```swift
drawCircle(center: center, radius: shortSide * 0.4)
let margin = shortSide * 0.08
```

`scale` above is the same quantity divided by 1000, and you use it to hold a
size's proportion. Use `shortSide` when you want to state the fraction
directly.

<a name="canvasSize"></a>

### Export size

`canvasSize` is the resolution a sketch renders and exports at, in whole pixels, because a canvas is an integer grid. Its type is `CanvasSize`, and it defaults to `.square1080`, a 1:1 square of 1080×1080. Override it on a subclass with one of the named presets below, as in `override var canvasSize: CanvasSize { .uhd4K }`:

| Constant | Pixels | Aspect | Good for |
|---|---|---|---|
| `.square1080` | 1080 × 1080 | 1:1 | the default, for square social and feed posts |
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

The paper presets are sized in PDF points, 72 per inch, and they come portrait like the physical sheet. The [PDF export](../Output/Export.md#vector-pdf) maps one canvas pixel to one point, so a sketch on `.a4` exports as a true A4 page. The vector geometry then prints sharp at any resolution. When the *raster* export needs print resolution too, add `.dpi(_:)`. Writing `.a4.dpi(300)` renders and `--export`s at 2479×3508 pixels, which is 300 dots per inch. With that in place, `--export-pdf` still writes the page at exactly A4, and the pixel geometry is scaled back onto it. It works on any size, and the size it is called on is taken as the 72-dpi page. Calling `.dpi(72)` changes nothing.

Use `.portrait` and `.landscape` to flip any preset's orientation, so `.uhd4K.portrait` is 2160×3840 and `.a4.landscape` is 842×595. The flips compose with `.dpi(_:)` in either order. Headless `--export` always renders at `canvasSize`, so a sketch produces the same pixels on any machine. The `--export-sequence <dir> --frames N` flags render a deterministic numbered PNG sequence at a fixed timestep, so it is reproducible and assembles into a smooth video. See [Sketch ▸ Running a sketch](../Core/Sketch.md#running-a-sketch).

For a custom size, override `canvasSize` with `.square(_)` for a square or `.size(_, _)` for any rectangle:

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

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/01-HelloOllin/CanvasVsWindow-dark.jpg">
  <img src="../../Guide/Images/01-HelloOllin/CanvasVsWindow.jpg" alt="A large dark square labeled as the canvas at 1080 by 1080 pixels, with its corners marked as (0,0) and (1080,1080), and a smaller window containing exactly the same picture scaled down, joined by lines labeled scaled to fit" width="680">
</picture>

The on-screen window does not have to match `canvasSize`, because a 1080² or 4K sketch would overflow a laptop screen. `windowMode` sets the window size relative to `canvasSize`:

- **`.auto`** is the default. It opens at 1:1 when the screen has room for the full `canvasSize`. Otherwise it steps down to the largest clean fraction that fits (¾, ½, …), so the window always fits. A 1080² sketch opens at 1080 on a large or external display, and at ¾ (810pt) on a 14"/16" laptop.
- **`.fixed(_)`** pins an explicit fraction of `canvasSize` and ignores the screen, so `.fixed(0.5)` is always half size and `.fixed(1)` is always 1:1.
- **`.resizable`** opens a freely resizable window at the auto-fit size, and the canvas follows it live. Use it for sketches made for the screen rather than for a fixed export. Draw with `scale`, `width`, and `height`, and the piece adapts as you drag the window.

```swift
override var windowMode: WindowMode { .fixed(0.5) }   // always half of canvasSize
```

`.auto` and `.fixed` lock the window, and `.resizable` does not. Resizing applies to the standalone `swift run` window. The examples gallery and the live host show the sketch at the auto-fit size with a collapsible sidebar.

In either mode, a sketch written with `scale` composes the same at the preview size and at the export size. What you see while you work therefore matches the exported frame, so the export stays dependable for video and for Instagram.

<a name="stats-overlay"></a>

### The performance panel

When a sketch feels slow, choose **View ▸ Show Inspector** (⌘/). That opens a floating panel beside the sketch window. It reports the frame rate, the CPU time spent building a frame, the clock, and the canvas size. It also counts the geometry the frame emitted: vertices, SDF shapes, point-cloud splats, and GPU particles. Below those, it shows a slider for each of the sketch's `@Param` parameters. Choose the same command again to hide the panel.

The panel is a separate utility window, not drawing inside the canvas, so it never appears in an exported frame. That is because `--export` renders only the canvas. The CPU time is the cost of building a frame on the draw thread. It is the first number to climb when a sketch gets heavy. It reads far lower in a release build (`swift run -c release`) than in the default debug build.

The live host (`OllinLive`) shows the same readout in its own inspector sidebar, so there the readout is built into the window.

<a name="retina"></a>

### Retina and pixel density

The preview is crisp on Retina displays and there is nothing to switch on, because it renders at the screen's native pixel density. Export renders directly at `canvasSize`, so a 1080² export is exactly 1080×1080 pixels.

<a name="uv"></a>

### Normalized coordinates: uv

```swift
func uv(_ u: Double, _ v: Double) -> Vector2
```

This returns the canvas point at normalized coordinates. `uv(0, 0)` is the top-left corner, `uv(1, 1)` the bottom-right, and `uv(0.5, 0.5)` the center. A layout stated as proportions never reads `width` or `height`, and it uses the same 0…1 top-left space that per-pixel shader code sees. Values outside 0…1 land off the canvas in proportion, so nothing clamps.

```swift
drawCircle(center: uv(0.5, 0.25), radius: 40 * scale)      // top-center
drawPolygon([uv(0, 0.66), uv(1, 0.66), uv(1, 1), uv(0, 1)]) // the lower third
```

The same mapping exists on any [`Rectangle`](../Drawing/Geometry.md) as `point(u:v:)`, and `uv(of:)` is its inverse. Reading `bounds.uv(of: Vector2(mouseX, mouseY))` gives you the mouse position as canvas fractions. The [`Basic/NormalizedCoordinates`](../../Examples/Basic/NormalizedCoordinates/Sketch.swift) example composes a whole scene this way.
