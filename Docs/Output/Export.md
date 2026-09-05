#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → `Export`</sup>

---

## Export

Save what a sketch draws. The output comes in three families:

- **Raster**, meaning PNG frames and image sequences.
- **Motion**, meaning a video file or an animated GIF, encoded directly.
- **Vector**, meaning SVG for pen plotters and any vector pipeline, and PDF for print.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/31-SharingAndPerforming/ExportMap-dark.jpg">
  <img src="../../Guide/Images/31-SharingAndPerforming/ExportMap.jpg" alt="A diagram with a box labeled your sketch in the middle, arrows fanning left to five file outputs (still, sequence, video, GIF, SVG) and right to three live feeds (the window, Syphon, virtual camera)" width="680">
</picture>

Export runs the sketch *headlessly*. It calls `setup()`, advances the clock to the frame you ask for, runs `draw()`, and writes the result. No window opens, so the same call works from a script or a render farm.

Most exports are reached by a command-line flag on any example's executable. The same work is available as functions on `OllinApp` when you drive the export yourself. A loose sketch file has no target of its own, so you run it through the live host, `OllinLive`, which takes the same flags. `OllinLive` compiles the file and runs the export headlessly instead of opening a window:

```sh
swift run OllinLive MySketches/Loop.swift --export-gif loop.gif --seconds 4 --gif-width 540
swift run OllinLive MySketches/Loop.swift --export poster.png --frame 90
```

### Contents

- [Raster: PNG and sequences](#raster-png-and-sequences) - `--export` (PNG, or HEIC to keep highlights), `--export-sequence`
- [Render quality](#render-quality) - `--render-quality`, the live vs. export default
- [Render scale](#render-scale) - `--render-scale`, drawing a frame more finely than it is saved
- [Path-traced render](PathTraced.md) - `--path-traced`, the offline light-tracing mode for 3D scenes (its own page)
- [Sound](#sound) - a sketch's own music, in the file
- [Video](#video) - `--export-video`, `OllinApp.exportVideo`
- [Spatial video](Spatial.md#spatial-video) - `--export-spatial`, a stereo pair per frame for a headset (its own page)
- [Web page](Web.md) - `--export-web`, a page that plays what the sketch drew back in a browser, standalone or inline (its own page)
- [Animated GIF](#animated-gif) - `--export-gif`, `OllinApp.exportGIF`
- [Perfect loops](#perfect-loops) - `--export-loop`, `Sketch.loopDuration`
- [Slow motion](#slow-motion) - `--slow-motion`, `--made-frames`, a file that plays slower than the sketch ran
- [Settled frames](#settled-frames) - `--settle`, each written frame drawn several times with the clock held, for a picture that converges
- [Vector: SVG](#vector-svg) - `--export-svg`, `OllinApp.svg` / `exportSVG`
- [Vector: PDF](#vector-pdf) - `--export-pdf`, `OllinApp.pdf` / `exportPDF`, paper sizes
- [What SVG export records](#what-svg-export-records) - the shape mapping and the limits
- [Hatching: solid fills for a pen plotter](#hatching-solid-fills-for-a-pen-plotter) - `--hatch`, `Hatching`
- [Reproducibility metadata](#reproducibility-metadata) - the regeneration recipe every export carries
- [Captures that know their source](#captures-that-know-their-source) - `--capture-source`, keeping the exact code a file came from
- [Rendering a chosen variation](#rendering-a-chosen-variation) - `--seed`, on every export path
- [Setting a parameter for the run](#setting-a-parameter-for-the-run) - `--param name=value`, a declared `@Param` set from the command line
- [Driving the parameters from a file](#driving-the-parameters-from-a-file) - `--automation`, keyframed parameters on every export path
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
swift run --package-path Examples Example-Basic-HelloCircle --export-sequence /tmp/out --seconds 5 --fps 60
```

Both render through Metal off-screen, with MSAA and then a resolve, so the pixels match the live window. The same capability is available in code as `OllinApp.image(of:frame:)`, `OllinApp.export(_:to:frame:)`, and `OllinApp.exportSequence(...)`. The first of these returns a `CGImage`. For a *reproducible* sequence, seed the sketch with `seed(…)` in `setup()`. Sources that follow the export clock stay reproducible too. A [`VideoPlayer`](../Video/Video.md) decodes by the sketch clock, so frame `k` shows the clip at `k / fps`. An [`AudioPlayer`](../Helpers/Audio.md#audioplayer) feeds its analyzer the same slice of its file each frame. So an audio-reactive piece exports with its beats in the same places every run.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/31-SharingAndPerforming/HeadlessCapture-dark.jpg">
  <img src="../../Guide/Images/31-SharingAndPerforming/HeadlessCapture.jpg" alt="Four dark square tiles in a row, each showing the same cluster of green-to-orange circles in a different arrangement, labeled frame 0, frame 30, frame 60, and frame 90, above the caption OllinApp.image(of: Pulse(), frame:), four renders, no window" width="680">
</picture>

Use the sequence when you want raw material. It keeps every frame as a lossless PNG for an external encoder or an edit. When the goal is only a file to share, the next two sections encode a file directly and skip the stitching step.

The file name picks the format for a single frame. A `.heic` (or `.heif`) path writes HEIC instead of PNG:

```sh
swift run --package-path Examples Example-Rendering-ColorOutput --export /tmp/frame.heic
```

For an ordinary sketch, that is the same picture in a smaller file. For a sketch that declared [`colorOutput`](../Drawing/ColorOutput.md) `.extended`, HEIC is the only still format that keeps brightness above white. HEIC stores that brightness in a gain map beside the picture, and PNG has nowhere to put it.

### Render quality

A few features trade visual quality for frame rate through the shared `RenderQuality` setting. They are soft shadows, depth of field, ambient occlusion, and the render resolution of the raymarched 3D SDF (`drawSDF3D`). The tiers are `.performance`, `.default`, and `.detail`. **Export and the live window pick a different default**, because they work under different constraints:

- The **live window** defaults to `.default`, the tier that protects the frame rate. For example, the raymarcher runs at half resolution there, so a busy field stays smooth.
- **Export and headless** rendering (`--export`, `--export-sequence`, `--export-video`, `--export-gif`, `OllinApp.image(of:)`) default to **`.detail`**, the best quality. There is no frame-rate pressure when writing a file, and exported art should never be downscaled. So an export is full resolution with the richest samples by default.

Override the export default with `--render-quality`:

```sh
swift run --package-path Examples Example-3D-Raymarching-RaymarchedSDF --export field.png                              # .detail (default, full quality)
swift run --package-path Examples Example-3D-Raymarching-RaymarchedSDF --export field.png --render-quality performance # fast/low: quarter-res raymarch, fewer samples
swift run --package-path Examples Example-Effects-Defocus      --export-video dof.mp4 --seconds 6 --render-quality default
```

The flag takes `performance`, `default`, or `detail` (or the aliases `fast`, `balanced`, and `high`) and applies to every raster, video, and GIF export. It is **distinct from `--quality`**, which sets the video *encoding* quality (0…1) for `--export-video`.

**The sketch's own quality setting always takes precedence.** `--render-quality` and the automatic live and export defaults only fill in the features the sketch left alone. If a sketch sets a feature's quality explicitly (`raymarchQuality(.performance)`, `shadowQuality(.detail)`, `.defocus(…, quality: .performance)`), that choice holds on every path, live and export alike. In code the same control is the `quality:` argument on `OllinApp.image(of:frame:fps:quality:)`, `export`, and `exportSequence`. On `exportVideo` and `exportGIF` it is `renderQuality:`. In both places it defaults to `.detail`.

### Render scale

`--render-scale N` draws each exported frame at N times the canvas resolution in each direction. It then averages every block of N by N samples back into one pixel. The picture keeps its canvas size. What changes is how finely it was sampled:

```sh
swift run --package-path Examples Example-Text-TypeAsGeometry --export poster.png --render-scale 2
swift run --package-path Examples Example-Shapes-Polygons --export poster.png --render-scale 4
```

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/31-SharingAndPerforming/SamplingFiner-dark.png">
  <img src="../../Guide/Images/31-SharingAndPerforming/SamplingFiner.png" alt="Two magnified pixel grids side by side showing the same fan of blue rays meeting at a point, labeled render scale 1 with one sample per pixel and render scale 4 with sixteen averaged; the second fan has softer, more graded edges and a cleaner center" width="680">
</picture>

It is the quality-over-speed control for a frame that has no frame-rate deadline. The work grows with the square of the number: four times the pixels at 2, sixteen at 4. That is why the live window never uses it, and why 4 is the ceiling. If you ask for more, the export renders at the ceiling and prints a line saying so.

**What it sharpens.** It sharpens filled shapes and polygons, the glyph outlines that text is made of, and fine dense detail. Those are the things that reach the screen as triangles. It leaves the analytic shapes (circles, rectangles, arcs, the marker catalog), every stroked path, and atlas text (`textMode(.atlas)`) as they were. Each of those carries its own coverage, so it is already crisp at 1.

**What it does not change.** Everything that treats the finished frame as a picture runs at canvas size at every scale. That is motion blur, the lens flare, `postProcess` filters, and the tone map. So a `.gaussianBlur(radius: 12)` is twelve canvas pixels wide whatever the scale is. Two other things stay at 1 as well. A layer built with `renderTarget` keeps the size it was made at. A piling canvas (`noClear`) carries one surface across frames, so it renders at 1 and prints a line saying so.

In code the same control is `OllinApp.exportRenderScale`, set before the export call:

```swift
OllinApp.exportRenderScale = 2
OllinApp.export(sketch, to: "poster.png")
```

### Video

Encode an animated sketch straight to a `.mp4` or `.mov`. One command takes a sketch to a file you can post, with no external tool:

```sh
swift run --package-path Examples Example-Basic-HelloCircle --export-video breathing.mp4 --seconds 6
swift run --package-path Examples Example-Motion-Orbits --export-video orbits.mov --seconds 10 --codec hevc --bitrate 8
```

It runs on the same deterministic fixed-timestep drive as `--export-sequence`, so `--seconds` or `--frames`, `--fps`, and `--skip` work the same way. A render that takes ten minutes still writes a file that plays smoothly at the requested rate. In code it is `OllinApp.exportVideo(_:to:frames:fps:codec:bitsPerSecond:quality:skipSeconds:)`.

The flags:

| Flag | Effect |
|---|---|
| `--codec h264` \| `hevc` \| `proRes422` \| `proRes4444` | the encoder (default `h264`) |
| `--bitrate MBPS` | average bitrate in Mbit/s, the file-size control |
| `--quality 0..1` | constant-quality rate control instead of a bitrate (Apple silicon only) |

**Picking a codec.** `h264` plays everywhere and is the safe default for posting. `hevc` gives better quality per byte, and it encodes 10-bit, which keeps smooth gradients smoother. So it is a good first switch when a file needs to be smaller, at a small compatibility cost on older players. The two ProRes profiles are mastering codecs. They are visually lossless and an order of magnitude larger. They are meant for an edit timeline or a later re-encode rather than for sharing, and they need a `.mov` path.

**Size and quality.** Without `--bitrate` the encoder picks its own generous rate. With it, the file size is predictable, because a clip's size is roughly `bitrate × seconds`. As a starting point, a 1080×1080 clip at 60 fps looks clean at about 10 to 15 Mbit/s in `h264`. In `hevc` it is 6 to 9. Halve those for slow, flat-color motion, and raise them for full-frame noise or grain. On Apple silicon, `--quality` (0…1) targets a constant quality and lets the rate float instead, which is closer to how `crf` works in `ffmpeg`. The encoders are the hardware ones, which are fast and power-efficient. If you want a specific software encoder or two-pass tuning, `--export-sequence` still gives you lossless frames and prints the `ffmpeg` line.

Exported tracks are tagged Rec. 709, so what players show matches what the canvas rendered.

**HDR.** A sketch that declares [`colorOutput`](../Drawing/ColorOutput.md) `.extended` is written as **HDR10** instead, with no extra flag to pass. That means Rec. 2020 primaries, the PQ transfer, 10-bit HEVC, and the mastering-display and content-light metadata the format expects. If the codec was left at the `h264` default, it is forced to `hevc`, because eight bits cannot carry HDR. A `.wide` sketch's track is tagged P3-D65, which is the same standard range through wider primaries.

**Spatial video.** A 3D sketch can be exported as [spatial video](Spatial.md#spatial-video) instead. It uses the same fixed-clock drive, but each frame is rendered from two eyes. The two views are muxed into the stereo format that Apple's platforms play with real depth.

### Sound

A sketch that plays sound carries that sound into the video. Nothing needs to be switched on. If the sketch holds an instrument and plays it, `--export-video` and `--export-loop` write an audio track beside the picture. A sketch that holds no instrument writes exactly the file it always wrote, with no audio track.

The sound reproduces the way the picture does. The exporters drive the sketch on a fixed clock with nothing playing aloud, and the notes are written down as the frames are drawn. Then the soundtrack is rendered through the same code that would have fed the speakers. Export twice, and the audio comes back identical sample for sample.

A sound the sketch [placed in the scene](../Helpers/Synthesis.md#placing-a-sound) is placed in the file as well. The position of each instrument, and the position it was heard from, are written down alongside the notes. So something that moves past you on screen also moves past you in the audio.

GIF has no way to hold sound. The details, and what stays out of the file, are on the [Synthesis](../Helpers/Synthesis.md#sound-in-an-export) page.

---

### Animated GIF

Write a short, infinitely looping GIF:

```sh
swift run --package-path Examples Example-Basic-HelloCircle --export-gif breathing.gif --seconds 4 --gif-width 540
```

In code it is `OllinApp.exportGIF(_:to:frames:fps:width:skipSeconds:)`. GIF is limited to a palette of 256 colors a frame, and it is heavy per second next to video. So the format suits **short loops at modest sizes**. `--gif-width` downscales the output, and the height follows the canvas aspect. Downscaling is usually the difference between a few hundred kilobytes and many megabytes. For anything long or subtle, `--export-video` is the better tool.

Watch out for **full-frame motion**. A piece where every pixel moves every frame, such as a drifting field or a full-canvas texture, defeats GIF's frame-to-frame compression. Even at a modest width, such a file can reach tens of megabytes. Lowering `--fps` cuts the file roughly in proportion, and sparse motion over a stable background compresses better.

One timing limit comes from the format itself. GIF stores each frame's delay in whole centiseconds, so the achievable rates are 50, 33.3, 25, 20, … fps. The requested `--fps` (default 25, which is exact) is rounded to the closest achievable rate, and the sketch's clock runs at *that* rate. So motion always plays back at true speed, and the clip keeps its requested duration.

### Perfect loops

A sketch whose motion repeats exactly can declare its period. The export can then render exactly one period. You no longer need to match `--seconds` to the loop length by hand, or trim the seam by eye. Declare the period once:

```swift
override var loopDuration: Double? { 6 }   // this sketch repeats every 6 seconds
```

and export one seamless lap:

```sh
swift run --package-path Examples Example-Motion-PerfectLoop --export-loop loop.gif
swift run --package-path Examples Example-Motion-PerfectLoop --export-loop loop.mp4 --fps 30
```

The frame count is `loopDuration × fps`. The output format follows the file extension. A `.gif` takes the GIF options, which means `--gif-width`. Any other extension encodes video with `--codec`, `--bitrate`, and `--quality`. `--fps` (default 25 for GIF, 60 for video), `--skip`, and `--render-quality` work as they do everywhere else. For a GIF, the lap is computed against the centisecond-rounded rate the format can actually play (see the timing note above). So the loop stays exact at that rate. If `loopDuration × fps` is not a whole number of frames, the export warns and rounds, so pick a rate that divides the loop.

To make a sketch loop cleanly, drive every moving part from a phase that repeats over the period. That means `loopProgress(over:)` or `pingPong(over:)`, [looping noise](../Generators/Noise.md) with `noise(loop:)` or `signedNoise(loop:)`, or an angle built as `phase * .tau`. One term of plain `time`, or a `sin(time * k)` whose period does not divide the loop, breaks the seam. The [`Motion/PerfectLoop`](../../Examples/Motion/PerfectLoop/Sketch.swift) example is the worked reference. It declares `loopDuration`, and the frame one period after frame zero renders pixel-identical to it.

There is no separate entry point in code. In Swift, derive the frame count yourself and call the encoder: `OllinApp.exportGIF(sketch, to: path, frames: Int(duration * fps), fps: fps)`.

### Slow motion

An export writes the frames a sketch drew, at the rate it drew them, so a video plays at the speed you watched. `--slow-motion` is the one place where those two rates separate:

```sh
swift run --package-path Examples Example-Basic-HelloCircle --export-video slow.mp4 --seconds 4 --slow-motion 4
```

That renders four seconds of the sketch's own time and writes sixteen seconds of video. The file keeps its `--fps`. The run is covered by four times as many frames, so the motion takes four times as long to play. The flag works on `--export-sequence`, `--export-video`, `--export-gif`, and `--export-loop`. For a loop, one lap still closes, but it takes longer to watch.

Two numbers are easy to confuse, and the export prints both:

- `--seconds` counts the **sketch's** own time, as it always has. Four seconds at factor 4 is a sixteen-second file.
- `--frames` counts the frames written to the **file**. Ninety-six frames at 30 fps is 3.2 seconds of video whatever the factor is.

By default every one of those frames is drawn. The clock steps `factor` times finer, `deltaTime` shrinks to match, and the sketch is asked to draw each moment in between. That is exact and it works for any sketch, but it costs the factor's worth of render time.

**Motion measured in seconds slows down. Motion measured in frames does not.** A radius built from `sin(time)`, or a position advanced by `speed * deltaTime`, is a function of the clock. So a finer clock slows it down. A position advanced by a fixed step once per `draw()`, with no `deltaTime` in it, is not a function of the clock. It moves the same amount per frame however fast the clock runs. A finer clock hands that sketch more frames, so it arrives at the same place at the same time. Made frames are the answer for that sketch.

#### Frames the GPU makes

`--made-frames` draws only the frames it would have drawn anyway. It then asks the GPU to build each frame between them out of the pair on either side:

```sh
swift run --package-path Examples Example-3D-Effects-FrameInterpolation --export-video half.mp4 --seconds 4 --slow-motion 2 --made-frames
```

It uses the same platform interpolator that [`frameInterpolation()`](../3D/3D.md) puts on the live window, pointed at a file instead. It exists for two reasons. First, drawing half the pictures costs less than half the render time. Second, it is the only form of slow motion that slows a sketch whose motion is measured in frames.

It writes pictures the sketch never drew, so you have to ask for it by name. It also records that fact twice: on the console while it runs, and in the [reproduction recipe](#reproducibility-metadata) the file carries, as `"madeFrames":true`.

What it needs, and what it costs:

| | Drawn (the default) | Made (`--made-frames`) |
|---|---|---|
| Works on | any sketch | a 3D scene under a perspective camera |
| Factors | any number above 1 | 2, since the platform fills one frame per gap |
| Every frame is | drawn by the sketch | half drawn, half built from the pair around it |
| Cost | the factor's worth of render time | measured at 1.9 s where drawing every frame took 2.4 s |

The saving grows with the cost of drawing a frame. On a busy 3D scene at 1080 square, a made frame took about 11 ms against 20 ms for a drawn one. At nine times the sampling (`--render-scale 3`), the same clip took 3.3 seconds against 5.1.

Know three limits before you use it:

- **The first gap of a clip repeats.** The interpolator needs history, and one pair of frames is not enough to build a frame from. So the start of a made clip holds one picture twice. The live window does the same thing when it starts.
- **Flat marks over the scene can smear.** The interpolator reads the depth buffer. A caption or a HUD drawn in 2D has no depth, so it can be warped where the scene behind it moves. You notice it first on text.
- **A sketch with no 3D camera is refused** before anything is written, and the message says why. Drop the flag, and every frame is drawn instead, which costs more time and is never worse.

#### What else moves with it

The **recipe** each file carries records `"slowMotion"`. Its `"fps"` is the rate the *clock* ran at, not the rate the file plays at. So a still re-renders from the recipe unchanged, and `--export --frame N --fps F` lands on the same moment.

The **sound** a sketch makes is laid on the file's own timeline. So a slow-motion clip has sound across its full length rather than falling silent early, and each note arrives with the picture it belongs to.

A **take** cannot be replayed in slow motion. A take carries one frame of recorded input per drawn frame, so a finer clock has nothing to read between them. `--replay` beside `--slow-motion` is therefore refused rather than played wrong.

In code it is one argument, `slowMotion:`, on `exportSequence`, `exportVideo`, and `exportGIF`:

```swift
OllinApp.exportVideo(sketch, to: "slow.mp4", frames: 480, fps: 60, slowMotion: .drawn(4))
OllinApp.exportSequence(sketch, to: "frames", frames: 240, fps: 30, slowMotion: .made(2))
```

### Settled frames

Some pictures are not finished by one draw. A `LineSpray`, or anything drawn into an `Accumulator`, is a running mean. It starts grainy, settles as passes accumulate, and starts over whenever the camera moves. In a live window that is fine, because the camera rests and the picture catches up. In a video of a turning scene, every frame has a new camera, so every frame is the grainy first one. `--settle N` draws each written frame N times with the clock held and writes the last draw:

```sh
swift run --package-path Examples Example-Rendering-LineSpray --export-video turn.mp4 --seconds 10 --settle 40
swift run --package-path Examples Example-Rendering-LineSpray --export still.png --frame 0 --settle 120
```

The first draw of a frame advances the sketch's clock as always. The next N−1 draws repeat the same moment: `time` does not move, `deltaTime` is zero, and only `frameCount` counts on. So a camera or a motion written against the clock holds still while the layers underneath keep stepping. The mean converges, the frame is written, and the clock moves to the next frame. It costs N times a plain export. At 40 draws the picture is 200 passes of the ring sphere and looks clean. At 120 it is the still the reference page shows.

It applies to `--export`, `--export-sequence`, `--export-video`, `--export-gif`, and `--export-loop`, and the recipe each file carries records `"settle"`. Three things do not work with it. A **take** cannot be replayed or recorded, because a take carries one frame of input per drawn frame. You cannot ask for **made frames**, because they are built from the motion between two drawn frames, and a held clock has no motion. A **piling canvas** (`noClear`) keeps adding through the held draws, so it brightens N times faster instead of settling. A pile has no mean to converge to.

In code the same control is `OllinApp.exportSettle`, set before the export call:

```swift
OllinApp.exportSettle = 40
OllinApp.exportVideo(sketch, to: "turn.mp4", frames: 300, fps: 30)
```

### Vector: SVG

Write one frame's geometry as an SVG document instead of pixels:

```sh
swift run --package-path Examples Example-Export-VectorExport --export-svg /tmp/shapes.svg            # frame 0
swift run --package-path Examples Example-Export-VectorExport --export-svg /tmp/shapes.svg --frame 30 # a later frame
```

Unlike raster export, SVG export records the draw calls on the **CPU**. So it never touches the GPU, runs anywhere, and is deterministic. The same export is available as functions:

```swift
let document = OllinApp.svg(of: MySketch(), frame: 0)   // -> String
OllinApp.exportSVG(MySketch(), to: "/tmp/shapes.svg")   // writes the file
```

The output is **standard, general-purpose SVG**. Native `<circle>`, `<ellipse>`, `<rect>`, `<polygon>`, and `<path>` elements keep their fills, opacity, and transforms. So the file opens cleanly in a browser, Inkscape, or Illustrator, and works as scalable vector art in its own right. A **pen plotter** is one common destination for the file, and an AxiDraw plots an SVG through its own tooling. Stroke-based sketches map most naturally to a plotter, because a pen has no fill. The single-line [stroke fonts](../Drawing/Text.md) and stroked geometry are exactly what a plotter draws, though the export is not limited to plotting.

### Vector: PDF

Write the same frame as a single-page PDF, the print-ready form of the vector output:

```sh
swift run --package-path Examples Example-Export-VectorExport --export-pdf /tmp/shapes.pdf            # frame 0
swift run --package-path Examples Example-Export-VectorExport --export-pdf /tmp/shapes.pdf --frame 30 # a later frame
```

In code it is `OllinApp.pdf(of:frame:)`, which returns `Data`, and `OllinApp.exportPDF(_:to:frame:)`. PDF export replays the **same recorded geometry** as the SVG export, so the two documents of a frame always agree. Everything under [What SVG export records](#what-svg-export-records), including the limits, applies equally, and `--hatch` works the same way. Both flags can be given in one invocation (`--export-svg a.svg --export-pdf b.pdf`). Like the SVG path, it runs on the CPU with no GPU. Gradients, clipping, transforms, and alpha all come through as native PDF constructs.

**Paper sizes.** One canvas pixel maps to one PDF point, at 72 per inch. So the paper presets on [`CanvasSize`](../Core/Canvas.md) produce true-to-size pages. A sketch on `.a4` (595×842) exports as an actual A4 page, ready to print with no scaling. `.usLetter`, `.usLegal`, `.a3`, `.a4`, and `.a5` are built in. Each is portrait, like the physical sheet, and `.landscape` turns one on its side:

```swift
override var canvasSize: CanvasSize { .usLetter }            // 8.5×11 in, portrait
override var canvasSize: CanvasSize { .a4.landscape }        // 297×210 mm
```

Any other canvas exports at its pixel size in points. Because the geometry is vector, it prints sharp at any scale either way. When the *raster* export should be print resolution too, add `.dpi(_:)` to the preset. `.usLetter.dpi(300)` renders and `--export`s at 2550×3300 pixels, and `--export-pdf` still writes a true 8.5×11 in page, with the geometry scaled back onto it.

### What SVG export records

The exporter captures each draw call at its semantic level, before tessellation. So the output is clean vector primitives rather than a mesh of triangles. The PDF export replays the same recording, so this table and its limits describe both formats. Each SVG element maps to the equivalent PDF path:

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

The current transform is written as each element's `transform="matrix(…)"`. Fills and strokes become `fill` and `stroke`, with `*-opacity` for alpha, and the background is a full-canvas `<rect>`. Coordinates use the same top-left, y-down system as the canvas, so positions match what you see on screen.

The vector format cannot express a few things exactly. This is how each one is handled:

- **Images** are skipped, because raster pixels have no place in a vector file. The omission is noted as a comment in the output.
- **`strokeAlign(.inside` / `.outside)`** falls back to a centered stroke, because SVG strokes are always centered on the path.
- **`hollow(_:)`** band fills are approximated by a centered stroke of the band width.
- Curves and the analytic SDF-only shapes are written as fine polyline or path **approximations** of their outline, which look identical at print scale. A traced boundary with more than one loop exports as a single even-odd path, with its holes intact. A moon whose cut disk sits fully inside is one such boundary. The Cool S's interior lines are exported as stroke line work.

### Hatching: solid fills for a pen plotter

A pen plotter draws with a pen, so it has no fill. A solid shape would plot as a bare outline. To fix that, **hatching** turns each fill into line work. The lines are parallel, or cross-hatched, and they are clipped to the shape's outline and spaced by the fill's tone. The plotter then shades the shape with those lines. Add `--hatch` to the SVG export (the PDF export takes the same flags):

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

Darker, more opaque fills hatch **densely**, lighter ones hatch **sparsely**, and a near-white fill gets no hatch lines at all. Each shape keeps its outline as a stroke, so the border stays clean. Stroke-only geometry (lines, curves, stroke fonts) passes through unchanged, because it is already what a plotter draws.

The same control is available in code as a value:

```swift
OllinApp.exportSVG(MySketch(), to: "/tmp/hatched.svg",
                   hatching: Hatching(spacing: 6, angle: .pi / 4, crossHatches: true))
```

Hatching transforms geometry rather than the rendered picture, so a sketch can ask for the lines directly. You can draw them on the canvas or feed them anywhere else:

```swift
for line in Hatching(spacing: 8).lines(filling: someShape) {
    drawPolyline(line)
}
```

`lines(filling:)` takes a `Shape`, `Rectangle`, or `Circle`. It returns the hatch lines as open polylines in that shape's coordinates. The shape's `winding` rule decides which regions are interior, so holes and concavities are respected. The [Hatching example](../../Examples/Export/Hatching/Sketch.swift) draws these lines live.

### Reproducibility metadata

Every export carries the recipe to regenerate itself, embedded as one compact JSON line:

```json
{"tool":"Ollin","seed":42,"params":{"radius":120},"git":"8167de3","frame":0,"fps":60}
```

The fields are:

- the sketch's [`variation`](../Core/Variations.md), the seed both generators started from,
- every `@Param`'s value at export time,
- the short git commit of the directory the export ran in,
- and the frame and fps that produced the file.

When `randomSeed` and `noiseSeed` were set individually, they appear as separate fields instead. A `-dirty` suffix marks uncommitted changes, and the commit field is absent outside a repository. Every sketch starts from a seed, so even an unseeded run records the number that reproduces it. Each format keeps the recipe in a different place:

| Format | Where |
|---|---|
| PNG (`--export`, `--export-sequence`) | the `Description` text chunk (`Software` reads "Ollin") |
| SVG | a comment right after the opening tag |
| PDF | the document's Subject field |
| Video | a description metadata item (`ffprobe` or any tag inspector shows it) |

GIF is the one format without a writable slot. For a quick look at a PNG, run `exiftool frame.png` or `strings frame.png | grep tool`. A file found months later names its own seed and parameter values, so the same sketch source plus `--seed` and `--frame` regenerates it exactly. Seeding is covered in [Random](../Generators/Random.md).

---

### Captures that know their source

The recipe names the commit, and marks it `-dirty` when the tree carried uncommitted edits. That marker is accurate, but you cannot recover the edits from it, because they are gone. `--capture-source` saves them instead. Add the flag beside any export flag:

```sh
swift run --package-path Examples Example-Randomness-Variations --export keeper.png --capture-source
```

```
Ollin: source captured as 93ae989, uncommitted work included. Read it with: git show 93ae989
Ollin: exported frame 0 → keeper-93ae989.png (1080×1080)
```

Three things happen. First, the working tree is written into the repository as a commit, tracked edits and new files alike. Then the exported file is named after that commit. Finally, the recipe gains a `capture` field holding the same hash, so the name and the metadata agree.

Nothing of yours moves. Your index, your working tree, `HEAD`, and every branch stay exactly as they were. The capture sits on no branch. It is reachable only through a ref under `refs/ollin/captures/`, and that ref is what keeps `git gc` from collecting it.

To get the code back, you need only the file name:

```sh
git show 93ae989:Sketch.swift      # read one file as it was
git checkout 93ae989               # stand the whole tree up, detached
git diff HEAD 93ae989              # see what was uncommitted at the time
```

A clean tree needs no capture, because the commit is already `HEAD`. In that case the flag only names the file after `HEAD` and says which commit that is.

Know the rest before you rely on it:

- **Ignored files stay out.** The capture honors `.gitignore`, so build products never travel with it. Exports are not ignored by default, so write them outside the repository or add them to `.gitignore`. Otherwise a capture carries your last render as well.
- **The same tree captures once.** The tree identifies the source. So a second export of unchanged files reuses the first commit instead of writing a near twin.
- **The name suffix travels.** A directory takes it too, so `--export-sequence frames` writes into `frames-93ae989`. For print separations, the file stem takes the suffix before the ink names.
- **Listing and clearing.** `git for-each-ref refs/ollin/captures` lists the captures. To drop them all, run `git for-each-ref --format='%(refname)' refs/ollin/captures | xargs -n1 git update-ref -d`.
- **Outside a repository** the flag prints a note, and the files keep the names you gave.

---

### Rendering a chosen variation

`--seed N` reseeds the sketch before its `setup()` on **every** export path above. A variation you found in the inspector or on a contact sheet comes back exactly:

```sh
swift run --package-path Examples Example-Randomness-Variations --export keeper.png --seed 10
swift run --package-path Examples Example-Randomness-Variations --export-video keeper.mp4 --seconds 6 --seed 10
```

The same seed always renders the same pixels. A sketch that sets its own seed in `setup()` ignores the flag, just as it ignores every other way of setting a seed.

---

### Setting a parameter for the run

`--param <name>=<value>` sets one declared [`@Param`](../Helpers/Parameters.md) for this run, on **every** export path above. It works on a standalone window too, where it is a launch value, and the inspector keeps whatever you change it to afterwards. The flag can be repeated, so a run carries as many parameters as it needs:

```sh
swift run --package-path Examples Example-Live-Parameters --export keeper.png --param radius=40 --param rings=2
swift run --package-path Examples Example-Live-Parameters --export dark.png --param paper=#101018 --param style=dots
```

The [recipe](#reproducibility-metadata) and `--param` work as a pair. Every export writes the parameter values it rendered with into the file, and `--param` puts those values back. A frame re-renders from its own recipe, with the sketch untouched.

The value is read against the parameter's own kind:

| Kind | Written as |
|---|---|
| `Double`, `Int` | `radius=40`, `rings=2` |
| `Bool` | `breathe=true` (`yes`, `no`, `on`, `off`, `1` and `0` read too) |
| a menu choice | `style=dots`, matched loosely, so `easeOut`, `ease-out` and `"Ease Out"` all land on the same one |
| `Color` | `paper=#101018` (`#RGB`, `#RGBA`, `#RRGGBB` and `#RRGGBBAA`), or `paper=0,0.5,1` in numbers from 0 to 1 |
| `Vector2`, `Vector3` | `anchor=100,900`, `pull=1,-2,3` |
| `Rectangle` | `plate=10,20,30,40`, as x, y, width, height |
| `Insets` | `margin=12` for every edge, or `margin=12,8,12,8` as top, right, bottom, left |
| `ClosedRange<Double>` | `band=0.25...0.75`, or `band=0.25,0.75` |
| `String` | `"caption=a longer line"`, quoted for the shell when it holds a space |
| `Palette`, `Ramp` | `inks=#000,#FFF,#F06`, spread evenly, or `#000@0,#F06@0.75` to place a stop |

The value lands after `setup()` and before the first frame. It goes through the same restore path the live hosts use across a reload. So it clamps to the declared range the way dragging the row does. It also overrides a value the sketch set for itself in `setup()`, and the recipe then names what the frame was drawn with. Beside a `--replay`, it overrides the take's recorded parameters, the way `--seed` overrides the take's seed. So the same gestures land on a different setting. A parameter named twice ends on the last value given. A name the sketch does not have, or a value its kind cannot read, stops the run. The error says what value it expected, so the run never renders something you did not ask for.

---

### Driving the parameters from a file

`--automation <file>` attaches [keyframed parameters](../Core/Automation.md) to the run, on **every** export path above and on a standalone window as well:

```sh
swift run --package-path Examples Example-Motion-Automation --automation slow.json --export-video out.mp4 --seconds 12
```

Every export drives the clock at a fixed step, so the curves land on the same frames every time. The file is applied before `setup()`, so a sketch that writes its own track for the same parameter takes precedence.

---

### Contact sheets: proofing a variation space

`--export-grid` renders one frame at each seed in a run of seeds and tiles them into a single labeled proof sheet. A photographer contact-prints a roll the same way before choosing an enlargement:

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

Each tile is a fresh instance of the sketch, seeded before `setup()` runs. So a stateful sketch, one with accumulation, feedback, or a growing simulation, cannot leak from one tile into the next. One renderer serves the whole sheet, so a 25-seed sheet costs about what 25 `--export` calls would, minus the startup. The sheet's PNG carries the seed list in its own recipe.

From code:

```swift
OllinApp.exportContactSheet({ MySketch() }, to: "sheet.png", seeds: Array(1...25))
let sheet: CGImage? = OllinApp.contactSheet(of: { MySketch() }, seeds: [3, 17, 92], columns: 3)
```

Pick a tile you like, then render it at full size with `--export … --seed N`. The whole loop, including the live inspector half of it, is in [Variations](../Core/Variations.md).

`--export-sweep` is the same sheet used as a tuning tool. Instead of stepping through the sketch's seeds, it steps through one of its [`@Param`](../Helpers/Parameters.md) parameters. Name the parameter and a range, or explicit values. Every tile renders at the same seed with only that parameter changing, which is what makes the sheet a fair comparison. A seed is still what a piece reproduces from. Use a sweep to choose a parameter's value before you commit to it:

```sh
swift run --package-path Examples Example-Live-Parameters --export-sweep sweep.png --sweep-param radius --from 40 --to 360 --steps 9
swift run --package-path Examples Example-Live-Parameters --export-sweep sweep.png --sweep-param rings --values "2,3,5,8" --seed 7
```

| Flag | Meaning |
|---|---|
| `--export-sweep <path.png>` | the sheet to write |
| `--sweep-param <name>` | the `@Param` property to sweep, by its Swift name (`radius`, not `Radius`) |
| `--from A --to B` | the range, spread evenly over `--steps` (default 9) |
| `--values "a,b,c"` | explicit values instead of a range |
| `--seed N` | the seed every tile is pinned to (one is rolled and recorded if omitted) |
| `--columns`, `--tile`, `--frame`, `--fps` | as on `--export-grid` |

The swept parameter is named with `--sweep-param` rather than `--param`, because `--param` sets a value on every tile alike. That is how the rest of the sketch is held still while one parameter moves. Naming the same parameter both ways asks for both at once, so the run stops. Values apply through the same restore path the live hosts use to carry parameters across reloads. So a tile matches what dragging the parameter to that value would show. Only numeric parameters (`Double`, `Int`) can be swept. An unknown name stops the run, and the error lists the parameters the sketch has. The sheet's PNG records the parameter, its values, and the pinned seed.

From code:

```swift
OllinApp.exportContactSheet({ MySketch() }, to: "sweep.png",
                            sweeping: "radius", values: [40, 120, 360], seed: 7)
// Or name the parameter by its own handle, which the compiler checks:
OllinApp.exportContactSheet({ MySketch() }, to: "sweep.png",
                            sweeping: \.$radius, values: [40, 120, 360], seed: 7)
```

`\.$radius` is the key path to the parameter itself, the projected value of a `@Param`. So a typo is a build error rather than an empty sheet. An `Int` parameter takes whole values the same way.
