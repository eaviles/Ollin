#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → `Export`</sup>

---

## Export

Save what a sketch draws — as raster (PNG frames and image sequences), as **motion** (a video file or an animated GIF, encoded directly), or as **vector** (SVG, for pen plotters and any vector pipeline). Export runs the sketch *headlessly*: it calls `setup()`, advances the clock to the frame you ask for, runs `draw()`, and writes the result. No window opens, so the same call works from a script or a render farm.

Most exports are reached by a command-line flag on any example's executable; the same work is available as functions on `OllinApp` if you're driving it yourself. A loose sketch file (one you run through the live host, no target of its own) gets the identical flag surface through `OllinLive`, which compiles the file and runs the export headlessly instead of opening a window:

```sh
swift run OllinLive MySketches/Loop.swift --export-gif loop.gif --seconds 4 --gif-width 540
swift run OllinLive MySketches/Loop.swift --export poster.png --frame 90
```

### Contents

- [Raster: PNG and sequences](#raster-png-and-sequences) — `--export`, `--export-sequence`
- [Render quality](#render-quality) — `--render-quality`, the live vs. export default
- [Video](#video) — `--export-video`, `OllinApp.exportVideo`
- [Animated GIF](#animated-gif) — `--export-gif`, `OllinApp.exportGIF`
- [Vector: SVG](#vector-svg) — `--export-svg`, `OllinApp.svg` / `exportSVG`
- [What SVG export records](#what-svg-export-records) — the shape mapping and the limits
- [Hatching: solid fills for a pen plotter](#hatching-solid-fills-for-a-pen-plotter) — `--hatch`, `Hatching`

---

### Raster: PNG and sequences

Write one frame to a PNG:

```sh
swift run Example-Basic-HelloCircle --export /tmp/frame.png            # frame 0
swift run Example-Basic-HelloCircle --export /tmp/frame.png --frame 90 # a later frame
```

Write a deterministic, fixed-timestep PNG sequence (ready for `ffmpeg`):

```sh
swift run Example-Motion-Breathing --export-sequence /tmp/out --seconds 5 --fps 60
```

Both render through Metal off-screen (MSAA, then resolve), so the pixels match the live window. The same capability is available as `OllinApp.image(of:frame:)` (returns a `CGImage`), `OllinApp.export(_:to:frame:)`, and `OllinApp.exportSequence(...)`. For a *reproducible* sequence, seed the sketch (`seed(…)` in `setup()`).

The sequence is the raw-material path: it keeps every frame as a lossless PNG for an external encoder or an edit. When the goal is just a file to share, the next two sections encode directly and skip the stitching step.

### Render quality

A few features trade visual fidelity for frame rate through the shared `RenderQuality` dial: soft shadows, depth of field, ambient occlusion, and the raymarched-3D-SDF render resolution (`drawSDF3D`). The tiers are `.performance`, `.default`, and `.detail`. **Export and the live window pick a different default**, because they have different constraints:

- **Live window** defaults to `.default`, the frame-rate-safe tier (for example the raymarcher runs at half resolution so a busy field stays smooth).
- **Export / headless** (`--export`, `--export-sequence`, `--export-video`, `--export-gif`, `OllinApp.image(of:)`) defaults to **`.detail`**, the best quality. There's no frame-rate pressure when writing a file, and you never want exported art downscaled, so an export is full resolution with the richest samples by default.

Override the export default with `--render-quality`:

```sh
swift run Example-3D-Raymarching-RaymarchedSDF --export field.png                              # .detail (default, full quality)
swift run Example-3D-Raymarching-RaymarchedSDF --export field.png --render-quality performance # fast/low: quarter-res raymarch, fewer samples
swift run Example-Effects-Defocus      --export-video dof.mp4 --seconds 6 --render-quality default
```

It takes `performance`, `default`, or `detail` (aliases: `fast` / `balanced` / `high`) and applies to every raster/video/GIF export. It is **distinct from `--quality`**, which is the video *encoding* quality (0…1) for `--export-video`.

**A quality the sketch sets itself always wins.** `--render-quality` (and the automatic live/export defaults) only fill in features the sketch left alone. If a sketch dials a feature explicitly (`raymarchQuality(.performance)`, `shadowQuality(.detail)`, `.defocus(…, quality: .performance)`), that choice is honoured on every path, live and export alike. In code the same control is the `quality:` argument on `OllinApp.image(of:frame:fps:quality:)` / `export` / `exportSequence` (and `renderQuality:` on `exportVideo` / `exportGIF`), defaulting to `.detail`.

### Video

Encode an animated sketch straight to a `.mp4` or `.mov` — one command from a sketch to a file you can post, no external tool:

```sh
swift run Example-Motion-Breathing --export-video breathing.mp4 --seconds 6
swift run Example-Motion-Orbits --export-video orbits.mov --seconds 10 --codec hevc --bitrate 8
```

It runs on the same deterministic fixed-timestep drive as `--export-sequence` (`--seconds`/`--frames`, `--fps`, and `--skip` work the same way), so a render that takes ten minutes still plays back smooth at the requested rate. In code it's `OllinApp.exportVideo(_:to:frames:fps:codec:bitsPerSecond:quality:skipSeconds:)`.

The flags:

| Flag | Effect |
|---|---|
| `--codec h264` \| `hevc` \| `prores422` \| `prores4444` | the encoder (default `h264`) |
| `--bitrate MBPS` | average bitrate in Mbit/s — the file-size dial |
| `--quality 0..1` | constant-quality rate control instead of a bitrate (Apple silicon only) |

**Picking a codec.** `h264` plays everywhere and is the safe default for posting. `hevc` is clearly better quality per byte (and encodes 10-bit, which keeps smooth gradients smoother) — a good first switch when a file needs to be smaller — at a small compatibility cost on older players. The two ProRes profiles are mastering codecs: visually lossless, an order of magnitude larger, meant for an edit timeline or a later re-encode rather than for sharing, and they need a `.mov` path.

**Size and quality.** Without `--bitrate` the encoder picks its own (generous) rate. With it, the file size is predictable: a clip's size is roughly `bitrate × seconds`. As a starting point, a 1080×1080 clip at 60 fps looks clean around 10 to 15 Mbit/s in `h264` and 6 to 9 in `hevc`; halve those for slow, flat-color motion, raise them for full-frame noise or grain. On Apple silicon, `--quality` (0…1) targets a constant quality and lets the rate float instead — closer to how `crf` works in `ffmpeg`. The encoders are the hardware ones (fast, power-efficient); if you want a specific software encoder or two-pass tuning, `--export-sequence` still hands you lossless frames and prints the `ffmpeg` line.

Exported tracks are tagged Rec. 709, so what players show matches what the canvas rendered.

### Animated GIF

Write a short, infinitely looping GIF:

```sh
swift run Example-Motion-Breathing --export-gif breathing.gif --seconds 4 --gif-width 540
```

In code it's `OllinApp.exportGIF(_:to:frames:fps:width:skipSeconds:)`. GIF is palette-limited (256 colors a frame) and heavy per second next to video, so the format wants **short loops at modest sizes** — `--gif-width` downscales the output (height follows the canvas aspect), which is usually the difference between a few hundred kilobytes and many megabytes. For anything long or subtle, `--export-video` is the better tool.

Watch out for **full-frame churn**: a piece where every pixel moves every frame (a drifting field, a full-canvas texture) defeats GIF's frame-to-frame compression entirely, so even a modest width can land in the tens of megabytes. Lowering `--fps` cuts such a file roughly in proportion, and sparse motion over a stable background compresses far better.

One timing quirk is inherent to the format: GIF stores each frame's delay in whole centiseconds, so the achievable rates are 50, 33.3, 25, 20, … fps. The requested `--fps` (default 25, which is exact) is quantized to the closest achievable rate, and the sketch's clock runs at *that* rate, so motion always plays back at true speed and the clip keeps its requested duration.

### Vector: SVG

Serialize one frame's geometry as an SVG document rather than pixels:

```sh
swift run Example-Export-VectorExport --export-svg /tmp/shapes.svg            # frame 0
swift run Example-Export-VectorExport --export-svg /tmp/shapes.svg --frame 30 # a later frame
```

Unlike raster export, SVG export records the draw calls on the **CPU** — it never touches the GPU, so it runs anywhere and is fully deterministic. The same is available as functions:

```swift
let document = OllinApp.svg(of: MySketch(), frame: 0)   // -> String
OllinApp.exportSVG(MySketch(), to: "/tmp/shapes.svg")   // writes the file
```

The output is **standard, general-purpose SVG** — native `<circle>`/`<ellipse>`/`<rect>`, `<polygon>`, and `<path>` with fills, opacity, and transforms preserved — so it opens cleanly in a browser, Inkscape, or Illustrator, and works as scalable vector art in its own right. A **pen plotter** is a common consumer (an AxiDraw plots an SVG through its own tooling), and stroke-based sketches map most naturally there since a pen has no fill — the single-line [stroke fonts](../Drawing/Text.md) and stroked geometry are exactly what it plots — but the export isn't limited to plotting.

### What SVG export records

The exporter captures each draw call at its semantic level — before tessellation — so the output is clean vector primitives, not a mesh of triangles:

| You draw | SVG element |
|---|---|
| `drawCircle` / `drawEllipse` | `<circle>` / `<ellipse>` |
| `drawRect` (with `cornerRadius`) | `<rect>` (with `rx`) |
| `drawLine`, `drawBezier` | `<line>`, `<path>` (round-capped) |
| `drawPolyline` / `drawPolygon` | `<polyline>` / `<polygon>` |
| `drawShape`, `drawCurve`, curve-builder, **outline text** | `<path>` (with `fill-rule`) |
| `drawTriangle` / `drawNgon` / `drawStar` and the polygonal shapes | `<polygon>` |
| the curved analytic shapes (heart, egg, moon, vesica, …) | `<path>` (traced to a fine outline) |
| `drawArc` (open / chord / pie) | `<polyline>` / `<polygon>` |
| **bitmap text** | a grid of `<rect>` |
| **stroke text** | `<polyline>` per glyph |

The current transform rides as each element's `transform="matrix(…)"`, fills and strokes become `fill`/`stroke` (with `*-opacity` for alpha), and the background is a full-canvas `<rect>`. Coordinates use the same top-left, y-down system as the canvas, so positions match what you see on screen.

A few things the vector format can't express exactly, and how they're handled:

- **Images** are skipped — raster pixels have no place in a vector file (the omission is noted as a comment in the output).
- **`strokeAlign(.inside` / `.outside)`** falls back to a centered stroke (SVG strokes are always centered on the path).
- **`hollow(_:)`** band fills are approximated by a centered stroke of the band width.
- Curves and the analytic SDF-only shapes are emitted as fine polyline/path **approximations** of their outline (visually identical at print scale).

### Hatching: solid fills for a pen plotter

A pen plotter draws with a pen, so it has no fill — a solid shape would plot as a bare outline. **Hatching** turns each fill into line work: parallel (or cross-hatch) lines clipped to the shape's outline, spaced by the fill's tone, so the plotter shades it. Add `--hatch` to the SVG export:

```sh
swift run Example-Export-Hatching --export-svg /tmp/hatched.svg --hatch
swift run Example-Export-Hatching --export-svg /tmp/hatched.svg --cross-hatch --hatch-angle 30
```

The flags:

| Flag | Effect |
|---|---|
| `--hatch` | turn fills into hatch lines (defaults: 4 pt spacing, 45°) |
| `--cross-hatch` | add a second, perpendicular set of lines |
| `--hatch-spacing N` | line spacing in canvas points for a solid black fill |
| `--hatch-angle DEG` | hatch direction in degrees |

Darker, more opaque fills hatch **densely**; lighter ones **sparsely**; a near-white fill drops out. Each shape keeps its outline as a stroke so the border stays clean. Stroke-only geometry (lines, curves, stroke fonts) passes through unchanged — it's already what a plotter draws.

The same thing is available as a value:

```swift
OllinApp.exportSVG(MySketch(), to: "/tmp/hatched.svg",
                   hatching: Hatching(spacing: 6, angle: .pi / 4, crossHatch: true))
```

And because hatching is a transform over geometry, not a render trick, a sketch can ask for the lines directly and draw them on the canvas (or feed them anywhere):

```swift
for line in Hatching(spacing: 8).lines(filling: someShape) {
    drawPolyline(line)
}
```

`lines(filling:)` takes a `Shape`, `Rectangle`, or `Circle` and returns the hatch lines as open polylines in that shape's coordinates; the shape's `winding` rule decides which regions are interior, so holes and concavities are respected. The [Hatching example](../../Examples/Export/Hatching/Sketch.swift) draws this live.
