#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → `Export`</sup>

---

## Export

Save what a sketch draws. The output comes in three families:

- **Raster**, meaning PNG frames and image sequences.
- **Motion**, meaning a video file or an animated GIF, encoded directly.
- **Vector**, meaning SVG for pen plotters and any vector pipeline, and PDF for print.

Export runs the sketch *headlessly*, so it calls `setup()`, advances the clock to the frame you ask for, runs `draw()`, and writes the result. No window opens, so the same call works from a script or a render farm.

Most exports are reached by a command-line flag on any example's executable. The same work is available as functions on `OllinApp` if you're driving it yourself. A loose sketch file gets the identical flag surface through `OllinLive`. That is one you run through the live host, with no target of its own. `OllinLive` compiles the file and runs the export headlessly, instead of opening a window:

```sh
swift run OllinLive MySketches/Loop.swift --export-gif loop.gif --seconds 4 --gif-width 540
swift run OllinLive MySketches/Loop.swift --export poster.png --frame 90
```

### Contents

- [Raster: PNG and sequences](#raster-png-and-sequences) - `--export` (PNG, or HEIC to keep highlights), `--export-sequence`
- [Render quality](#render-quality) - `--render-quality`, the live vs. export default
- [Path-traced render](PathTraced.md) - `--path-traced`, the offline light-tracing mode for 3D scenes (its own page)
- [Sound](#sound) - a sketch's own music, in the file
- [Video](#video) - `--export-video`, `OllinApp.exportVideo`
- [Spatial video](Spatial.md#spatial-video) - `--export-spatial`, a stereo pair per frame for a headset (its own page)
- [Animated GIF](#animated-gif) - `--export-gif`, `OllinApp.exportGIF`
- [Perfect loops](#perfect-loops) - `--export-loop`, `Sketch.loopDuration`
- [Vector: SVG](#vector-svg) - `--export-svg`, `OllinApp.svg` / `exportSVG`
- [Vector: PDF](#vector-pdf) - `--export-pdf`, `OllinApp.pdf` / `exportPDF`, paper sizes
- [What SVG export records](#what-svg-export-records) - the shape mapping and the limits
- [Hatching: solid fills for a pen plotter](#hatching-solid-fills-for-a-pen-plotter) - `--hatch`, `Hatching`
- [Reproducibility metadata](#reproducibility-metadata) - the regeneration recipe every export carries
- [Rendering a chosen variation](#rendering-a-chosen-variation) - `--seed`, on every export path
- [Contact sheets](#contact-sheets-proofing-a-variation-space) - `--export-grid` (seeds) and `--export-sweep` (a `@Param`), `OllinApp.contactSheet` / `exportContactSheet`
- [Print separations](PrintSeparations.md) - `--export-separations`, per-ink masters for risograph and screen printing (its own page)
- [Recording](Recording.md) - keep a *live* run instead of re-rendering one: real-time capture with sound (its own page)

---

### Raster: PNG and sequences

Write one frame to a PNG:

```sh
swift run --package-path Examples Example-Basic-HelloCircle --export /tmp/frame.png            # frame 0
swift run --package-path Examples Example-Basic-HelloCircle --export /tmp/frame.png --frame 90 # a later frame
```

Write a deterministic, fixed-timestep PNG sequence (ready for `ffmpeg`):

```sh
swift run --package-path Examples Example-Motion-Breathing --export-sequence /tmp/out --seconds 5 --fps 60
```

Both render through Metal off-screen, with MSAA and then a resolve, so the pixels match the live window. The same capability is available as `OllinApp.image(of:frame:)`, `OllinApp.export(_:to:frame:)`, and `OllinApp.exportSequence(...)`. The first returns a `CGImage`. For a *reproducible* sequence, seed the sketch with `seed(…)` in `setup()`. Sources that follow the export clock stay reproducible too. A [`VideoPlayer`](../Video/Video.md) decodes by the sketch clock, so frame `k` shows the clip at `k / fps`. An [`AudioPlayer`](../Helpers/Audio.md#audioplayer) feeds its analyzer the same slice of its file each frame. An audio-reactive piece therefore exports with its beats in the same places every run.

The sequence is the raw-material path, keeping every frame as a lossless PNG for an external encoder or an edit. When the goal is just a file to share, the next two sections encode directly and skip the stitching step.

The file name picks the format for a single frame. A `.heic` (or `.heif`) path writes HEIC instead of PNG:

```sh
swift run --package-path Examples Example-Rendering-ColorOutput --export /tmp/frame.heic
```

For an ordinary sketch that is the same picture in a smaller file. For a sketch that declared [`colorOutput`](../Drawing/ColorOutput.md) `.extended`, HEIC is the only still format that keeps brightness above white. It stores it in a gain map beside the picture, and PNG has nowhere to put it.

### Render quality

A few features trade visual fidelity for frame rate through the shared `RenderQuality` dial. They are soft shadows, depth of field, ambient occlusion, and the raymarched-3D-SDF render resolution (`drawSDF3D`). The tiers are `.performance`, `.default`, and `.detail`. **Export and the live window pick a different default**, because they have different constraints:

- **Live window** defaults to `.default`, the frame-rate-safe tier (for example the raymarcher runs at half resolution so a busy field stays smooth).
- **Export / headless** (`--export`, `--export-sequence`, `--export-video`, `--export-gif`, `OllinApp.image(of:)`) defaults to **`.detail`**, the best quality. There's no frame-rate pressure when writing a file, and you never want exported art downscaled. So an export is full resolution with the richest samples by default.

Override the export default with `--render-quality`:

```sh
swift run --package-path Examples Example-3D-Raymarching-RaymarchedSDF --export field.png                              # .detail (default, full quality)
swift run --package-path Examples Example-3D-Raymarching-RaymarchedSDF --export field.png --render-quality performance # fast/low: quarter-res raymarch, fewer samples
swift run --package-path Examples Example-Effects-Defocus      --export-video dof.mp4 --seconds 6 --render-quality default
```

It takes `performance`, `default`, or `detail` (aliases: `fast` / `balanced` / `high`) and applies to every raster/video/GIF export. It is **distinct from `--quality`**, which is the video *encoding* quality (0…1) for `--export-video`.

**A quality the sketch sets itself always wins.** `--render-quality` (and the automatic live/export defaults) only fill in features the sketch left alone. If a sketch dials a feature explicitly (`raymarchQuality(.performance)`, `shadowQuality(.detail)`, `.defocus(…, quality: .performance)`), that choice is honored on every path, live and export alike. In code the same control is the `quality:` argument on `OllinApp.image(of:frame:fps:quality:)`, `export`, and `exportSequence`. It is `renderQuality:` on `exportVideo` and `exportGIF`, and it defaults to `.detail`.

### Video

Encode an animated sketch straight to a `.mp4` or `.mov`, one command from a sketch to a file you can post, with no external tool:

```sh
swift run --package-path Examples Example-Motion-Breathing --export-video breathing.mp4 --seconds 6
swift run --package-path Examples Example-Motion-Orbits --export-video orbits.mov --seconds 10 --codec hevc --bitrate 8
```

It runs on the same deterministic fixed-timestep drive as `--export-sequence`, where `--seconds`/`--frames`, `--fps`, and `--skip` work the same way. A render that takes ten minutes still plays back smooth at the requested rate. In code it's `OllinApp.exportVideo(_:to:frames:fps:codec:bitsPerSecond:quality:skipSeconds:)`.

The flags:

| Flag | Effect |
|---|---|
| `--codec h264` \| `hevc` \| `prores422` \| `prores4444` | the encoder (default `h264`) |
| `--bitrate MBPS` | average bitrate in Mbit/s, the file-size dial |
| `--quality 0..1` | constant-quality rate control instead of a bitrate (Apple silicon only) |

**Picking a codec.** `h264` plays everywhere and is the safe default for posting. `hevc` is clearly better quality per byte, and it encodes 10-bit, which keeps smooth gradients smoother. It is a good first switch when a file needs to be smaller, at a small compatibility cost on older players. The two ProRes profiles are mastering codecs, visually lossless and an order of magnitude larger. They are meant for an edit timeline or a later re-encode rather than for sharing, and they need a `.mov` path.

**Size and quality.** Without `--bitrate` the encoder picks its own (generous) rate. With it, the file size is predictable, since a clip's size is roughly `bitrate × seconds`. As a starting point, a 1080×1080 clip at 60 fps looks clean around 10 to 15 Mbit/s in `h264`. In `hevc` it is 6 to 9. Halve those for slow, flat-color motion, and raise them for full-frame noise or grain. On Apple silicon, `--quality` (0…1) targets a constant quality and lets the rate float instead, closer to how `crf` works in `ffmpeg`. The encoders are the hardware ones, which are fast and power-efficient. If you want a specific software encoder or two-pass tuning, `--export-sequence` still hands you lossless frames and prints the `ffmpeg` line.

Exported tracks are tagged Rec. 709, so what players show matches what the canvas rendered.

**HDR.** A sketch that declares [`colorOutput`](../Drawing/ColorOutput.md) `.extended` is written as **HDR10** instead, with nothing else to pass. That means Rec. 2020 primaries, the PQ transfer, 10-bit HEVC, and the mastering-display and content-light metadata the format expects. The codec is forced to `hevc` if it was left at the h264 default, since eight bits cannot carry it. A `.wide` sketch's track is tagged P3-D65, the same standard range through wider primaries.

**In depth.** A 3D sketch can leave as [spatial video](Spatial.md#spatial-video) instead. It is the same fixed-clock drive, but each frame is rendered from two eyes. The two views are muxed into the stereo format Apple's platforms play with real depth.

### Sound

A sketch that plays carries its sound into the video. Nothing is switched on. If the sketch holds an instrument and plays it, `--export-video` and `--export-loop` write an audio track beside the picture. A sketch that holds none writes exactly the file it wrote before.

It reproduces the way the picture does. The exporters drive the sketch on a fixed clock with nothing playing. The notes are written down as the frames are drawn. The soundtrack is rendered through the same code that would have fed the speakers. Export twice and the audio comes back sample for sample identical.

A sound the sketch [placed in the scene](../Helpers/Synthesis.md#placing-a-sound) is placed in the file as well. Where each instrument was and where it was heard from are written down alongside the notes. Something that walks past you on screen walks past you in the audio.

GIF has no way to hold sound. The details, and what stays out, are on the [Synthesis](../Helpers/Synthesis.md#sound-in-an-export) page.

---

### Animated GIF

Write a short, infinitely looping GIF:

```sh
swift run --package-path Examples Example-Motion-Breathing --export-gif breathing.gif --seconds 4 --gif-width 540
```

In code it's `OllinApp.exportGIF(_:to:frames:fps:width:skipSeconds:)`. GIF is palette-limited (256 colors a frame) and heavy per second next to video, so the format wants **short loops at modest sizes**. `--gif-width` downscales the output (height follows the canvas aspect), which is usually the difference between a few hundred kilobytes and many megabytes. For anything long or subtle, `--export-video` is the better tool.

Watch out for **full-frame churn**. A piece where every pixel moves every frame defeats GIF's frame-to-frame compression entirely. Even a modest width can land in the tens of megabytes. A drifting field or a full-canvas texture is that kind of piece. Lowering `--fps` cuts such a file roughly in proportion, and sparse motion over a stable background compresses far better.

One timing quirk is inherent to the format. GIF stores each frame's delay in whole centiseconds, so the achievable rates are 50, 33.3, 25, 20, … fps. The requested `--fps` (default 25, which is exact) is quantized to the closest achievable rate, and the sketch's clock runs at *that* rate. Motion always plays back at true speed, and the clip keeps its requested duration.

### Perfect loops

A sketch whose motion repeats exactly can say so. The export machinery can then render exactly one period. There is no more hand-matching `--seconds` to the loop length, and no more trimming the seam by eye. Declare the period once:

```swift
override var loopDuration: Double? { 6 }   // this sketch repeats every 6 seconds
```

and export one seamless lap:

```sh
swift run --package-path Examples Example-Motion-PerfectLoop --export-loop loop.gif
swift run --package-path Examples Example-Motion-PerfectLoop --export-loop loop.mp4 --fps 30
```

The frame count is derived as `loopDuration × fps`. The output format follows the file extension. So `.gif` takes the GIF options, meaning `--gif-width`. Anything else encodes video with `--codec`, `--bitrate`, and `--quality`. `--fps` (default 25 for GIF, 60 for video), `--skip`, and `--render-quality` work as everywhere else. For a GIF, the lap is computed against the centisecond-quantized rate the format can actually play (see the timing note above). The loop therefore stays exact at that rate. If `loopDuration × fps` isn't a whole number of frames, the export warns and rounds, so pick a rate that divides the loop.

To make a sketch loop-clean, drive every moving part from a phase that repeats over the period. That means `loopProgress(over:)` / `pingPong(over:)`, [looping noise](../Generators/Noise.md) with `noise(loop:)` / `signedNoise(loop:)`, or an angle built as `phase * .tau`. One term of plain `time`, or a `sin(time * k)` whose period doesn't divide the loop, breaks the seam. The [`Motion/PerfectLoop`](../../Examples/Motion/PerfectLoop/Sketch.swift) example is the worked reference. It declares `loopDuration`, and its frame one period later renders pixel-identical to frame zero.

There's no separate code entry point. In Swift, derive the count yourself and call the encoder, as `OllinApp.exportGIF(sketch, to: path, frames: Int(duration * fps), fps: fps)`.

### Vector: SVG

Serialize one frame's geometry as an SVG document rather than pixels:

```sh
swift run --package-path Examples Example-Export-VectorExport --export-svg /tmp/shapes.svg            # frame 0
swift run --package-path Examples Example-Export-VectorExport --export-svg /tmp/shapes.svg --frame 30 # a later frame
```

Unlike raster export, SVG export records the draw calls on the **CPU**, so it never touches the GPU, runs anywhere, and is fully deterministic. The same is available as functions:

```swift
let document = OllinApp.svg(of: MySketch(), frame: 0)   // -> String
OllinApp.exportSVG(MySketch(), to: "/tmp/shapes.svg")   // writes the file
```

The output is **standard, general-purpose SVG**. Native `<circle>`/`<ellipse>`/`<rect>`, `<polygon>`, and `<path>` keep their fills, opacity, and transforms. So it opens cleanly in a browser, Inkscape, or Illustrator, and works as scalable vector art in its own right. A **pen plotter** is a common consumer, and an AxiDraw plots an SVG through its own tooling. Stroke-based sketches map most naturally there, since a pen has no fill. The single-line [stroke fonts](../Drawing/Text.md) and stroked geometry are exactly what it plots, though the export isn't limited to plotting.

### Vector: PDF

Write the same frame as a single-page PDF, the print-ready form of the vector output:

```sh
swift run --package-path Examples Example-Export-VectorExport --export-pdf /tmp/shapes.pdf            # frame 0
swift run --package-path Examples Example-Export-VectorExport --export-pdf /tmp/shapes.pdf --frame 30 # a later frame
```

In code it's `OllinApp.pdf(of:frame:)` (returns `Data`) and `OllinApp.exportPDF(_:to:frame:)`. PDF export replays the **same recorded geometry** as the SVG export, so the two documents of a frame always agree. Everything under [What SVG export records](#what-svg-export-records), including the limits, applies equally, and `--hatch` works the same way. Both flags can even ride one invocation (`--export-svg a.svg --export-pdf b.pdf`). Like the SVG path it runs on the CPU with no GPU, and gradients, clipping, transforms, and alpha all come through as native PDF constructs.

**Paper sizes.** One canvas pixel maps to one PDF point, 72 per inch. The paper presets on [`CanvasSize`](../Core/Canvas.md) therefore produce true-to-size pages. A sketch on `.a4` (595×842) exports as an actual A4 page, ready to print with no scaling. `.usLetter`, `.usLegal`, `.a3`, `.a4`, and `.a5` are built in, portrait like the physical sheet, and `.landscape` flips one:

```swift
override var canvasSize: CanvasSize { .usLetter }            // 8.5×11 in, portrait
override var canvasSize: CanvasSize { .a4.landscape }        // 297×210 mm
```

Any other canvas exports at its pixel size in points, and since the geometry is vector it prints sharp at any scale regardless. When the *raster* export should be print resolution too, add `.dpi(_:)` to the preset. `.usLetter.dpi(300)` renders and `--export`s at 2550×3300 pixels. `--export-pdf` still writes a true 8.5×11 in page, with the geometry scaled back onto it.

### What SVG export records

The exporter captures each draw call at its semantic level, before tessellation, so the output is clean vector primitives, not a mesh of triangles. The PDF export replays the same recording, so this table and its limits describe both formats (each SVG element maps to the equivalent PDF path):

| You draw | SVG element |
|---|---|
| `drawCircle` / `drawEllipse` | `<circle>` / `<ellipse>` |
| `drawRect` (with `cornerRadius`) | `<rect>` (with `rx`) |
| `drawLine`, `drawBezier` | `<line>`, `<path>` |
| `drawPolyline` / `drawPolygon` | `<polyline>` / `<polygon>` |
| `drawShape`, `drawCurve`, curve-builder, **outline text** | `<path>` (with `fill-rule`) |
| `drawTriangle` / `drawNgon` / `drawStar` and the polygonal shapes | `<polygon>` |
| the curved analytic shapes (heart, egg, moon, vesica, …) | `<path>` (traced to a fine outline) |
| `drawArc` (open / chord / pie) | `<polyline>` / `<polygon>` |
| **bitmap text** | a grid of `<rect>` |
| **stroke text** | `<polyline>` per glyph |

The current transform rides as each element's `transform="matrix(…)"`. Fills and strokes become `fill`/`stroke`, with `*-opacity` for alpha, and the background is a full-canvas `<rect>`. Coordinates use the same top-left, y-down system as the canvas, so positions match what you see on screen.

A few things the vector format can't express exactly, and how they're handled:

- **Images** are skipped, because raster pixels have no place in a vector file (the omission is noted as a comment in the output).
- **`strokeAlign(.inside` / `.outside)`** falls back to a centered stroke (SVG strokes are always centered on the path).
- **`hollow(_:)`** band fills are approximated by a centered stroke of the band width.
- Curves and the analytic SDF-only shapes are emitted as fine polyline/path **approximations** of their outline (visually identical at print scale). A traced boundary with more than one loop exports as a single even-odd path, holes intact. A moon whose cut disk sits fully inside is one such boundary. The Cool S's interior lines ride along as stroke line work.

### Hatching: solid fills for a pen plotter

A pen plotter draws with a pen, so it has no fill, and a solid shape would plot as a bare outline. **Hatching** turns each fill into line work. The lines are parallel, or cross-hatch, clipped to the shape's outline and spaced by the fill's tone. The plotter then shades it. Add `--hatch` to the SVG export (the PDF export takes the same flags):

```sh
swift run --package-path Examples Example-Export-Hatching --export-svg /tmp/hatched.svg --hatch
swift run --package-path Examples Example-Export-Hatching --export-svg /tmp/hatched.svg --cross-hatch --hatch-angle 30
```

The flags:

| Flag | Effect |
|---|---|
| `--hatch` | turn fills into hatch lines (defaults: 4 pt spacing, 45°) |
| `--cross-hatch` | add a second, perpendicular set of lines |
| `--hatch-spacing N` | line spacing in canvas points for a solid black fill |
| `--hatch-angle DEG` | hatch direction in degrees |

Darker, more opaque fills hatch **densely**, lighter ones **sparsely**, and a near-white fill drops out. Each shape keeps its outline as a stroke so the border stays clean. Stroke-only geometry (lines, curves, stroke fonts) passes through unchanged, since it's already what a plotter draws.

The same thing is available as a value:

```swift
OllinApp.exportSVG(MySketch(), to: "/tmp/hatched.svg",
                   hatching: Hatching(spacing: 6, angle: .pi / 4, crossHatch: true))
```

And because hatching is a transform over geometry, not a render trick, a sketch can ask for the lines directly. Draw them on the canvas, or feed them anywhere:

```swift
for line in Hatching(spacing: 8).lines(filling: someShape) {
    drawPolyline(line)
}
```

`lines(filling:)` takes a `Shape`, `Rectangle`, or `Circle`. It returns the hatch lines as open polylines in that shape's coordinates. The shape's `winding` rule decides which regions are interior, so holes and concavities are respected. The [Hatching example](../../Examples/Export/Hatching/Sketch.swift) draws this live.

### Reproducibility metadata

Every export carries the recipe to regenerate itself, embedded as one compact JSON line:

```json
{"tool":"Ollin","seed":42,"params":{"radius":120},"git":"8167de3","frame":0,"fps":60}
```

The fields are:

- the sketch's [`variation`](../Core/Variations.md), the seed both generators grew from,
- every `@Param`'s value at export time,
- the short git commit of the directory the export ran in,
- and the frame and fps that produced the file.

When `randomSeed`/`noiseSeed` were set individually they appear as separate fields instead. A `-dirty` suffix marks uncommitted changes, and the commit is absent outside a repository. Every sketch is born on a seed, so even an unseeded run records the number that reproduces it. Where each format keeps it:

| Format | Where |
|---|---|
| PNG (`--export`, `--export-sequence`) | the `Description` text chunk (`Software` reads "Ollin") |
| SVG | a comment right after the opening tag |
| PDF | the document's Subject field |
| Video | a description metadata item (`ffprobe` or any tag inspector shows it) |

GIF is the one format without a writable slot. For a quick look at a PNG, run `exiftool frame.png`, or `strings frame.png | grep tool`. An artifact found months later names its own seed and knob settings, so the same sketch source plus `--seed` and `--frame` regenerates it exactly. Seeding is covered in [Random](../Generators/Random.md).

---

### Rendering a chosen variation

`--seed N` reseeds the sketch before its `setup()` on **every** export path above. A variation you found in the inspector or on a contact sheet comes back exactly:

```sh
swift run --package-path Examples Example-Randomness-Variations --export keeper.png --seed 10
swift run --package-path Examples Example-Randomness-Variations --export-video keeper.mp4 --seconds 6 --seed 10
```

The same seed always renders the same pixels. A sketch that pins its own seed in `setup()` ignores the flag, as it ignores every other way of setting a seed.

---

### Contact sheets: proofing a variation space

`--export-grid` renders one frame at each of a run of seeds and tiles them into a single labeled proof sheet. A photographer contact-prints a roll the same way, before choosing an enlargement:

```sh
swift run --package-path Examples Example-Randomness-Variations --export-grid sheet.png --seeds 25
swift run --package-path Examples Example-Randomness-Variations --export-grid sheet.png --seeds 12 --columns 4 --tile 400
```

| Flag | Meaning |
|---|---|
| `--export-grid <path.png>` | the sheet to write |
| `--seeds N` | how many variations (default 16) |
| `--seed FIRST` | the first seed (default 1), with seeds running consecutively |
| `--columns C` | grid columns (default: the squarest fit) |
| `--tile PX` | each thumbnail's width, floored at 64 (default 320) |
| `--frame N` | which frame of the sketch to render (default 0) |
| `--fps F` | the clock rate that frame is timed against |

Each tile is a fresh instance of the sketch, seeded before `setup()` runs. A stateful sketch, with accumulation, feedback, or a growing simulation, can't leak from one tile into the next. One renderer serves the whole sheet, so a 25-seed sheet costs about what 25 `--export` calls would, minus the startup. The sheet's PNG carries the seed list in its own recipe.

From code:

```swift
OllinApp.exportContactSheet({ MySketch() }, to: "sheet.png", seeds: Array(1...25))
let sheet: CGImage? = OllinApp.contactSheet(of: { MySketch() }, seeds: [3, 17, 92], columns: 3)
```

Pick a tile you like, then render it big with `--export … --seed N`. The whole loop, and the live inspector half of it, is in [Variations](../Core/Variations.md).

`--export-sweep` is the same sheet as a tuning tool. Instead of walking the sketch's chance, it walks one of its [`@Param`](../Helpers/Parameters.md) knobs. Name the parameter and a range, or explicit values. Every tile renders at the same seed with only that parameter changing, which is what makes the sheet a fair comparison. Seeds remain the identity a piece reproduces from. A sweep is for choosing the knob's value before you commit to it:

```sh
swift run --package-path Examples Example-Live-Parameters --export-sweep sweep.png --param radius --from 40 --to 360 --steps 9
swift run --package-path Examples Example-Live-Parameters --export-sweep sweep.png --param rings --values "2,3,5,8" --seed 7
```

| Flag | Meaning |
|---|---|
| `--export-sweep <path.png>` | the sheet to write |
| `--param <name>` | the `@Param` property to sweep, by its Swift name (`radius`, not `Radius`) |
| `--from A --to B` | the range, spread evenly over `--steps` (default 9) |
| `--values "a,b,c"` | explicit values instead of a range |
| `--seed N` | the seed every tile is pinned to (one is rolled and recorded if omitted) |
| `--columns`, `--tile`, `--frame`, `--fps` | as on `--export-grid` |

Values apply through the same restore path the live hosts use to carry knobs across reloads. A tile matches what dragging the knob there would show. Numeric parameters (`Double`, `Int`) sweep; an unknown name fails with the sketch's actual parameter list. The sheet's PNG records the knob, its values, and the pinned seed.

From code:

```swift
OllinApp.exportContactSheet({ MySketch() }, to: "sweep.png",
                            sweeping: "radius", values: [40, 120, 360], seed: 7)
```
