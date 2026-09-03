#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → Web page</sup>

---

## A sketch as a web page

`--export-web` records what a sketch draws over a duration and writes a page that plays it back in a browser. It is an export like video: the sketch runs on the Mac, and the page is a file you put wherever you like. The page draws with the framework's own shaders, carried from Metal to GLSL: the shape shader, the stroke and fill pipelines, and the fragment behind every effect the sketch used. A frame on the page is the frame the Mac would have shown.

```sh
swift run --package-path Examples Example-Web-BreathingRing --export-web ring.html
```

The sketch keeps its source in Swift. The page holds a canvas, the shaders, and the recorded track, and nothing else: no source, no editor.

### Contents

- [Recording a page](#recording-a-page) - the flag, its length, `OllinApp.web` / `exportWeb`
- [What crosses](#what-crosses) - the analytic shapes, strokes and fills, text, the layered effects, and what stops the export
- [Strokes and fills on the page](#strokes-and-fills-on-the-page) - the vertices the Mac would have drawn, and a fill's edge through the same four samples
- [Layers and shaders on the page](#layers-and-shaders-on-the-page) - the pass graph beside the shapes, the framework's fragments rewritten, a shader of yours live
- [The two forms](#the-two-forms) - one self-contained file, or a fragment for a page of your own
- [Playing back](#playing-back) - the handle on the canvas, interpolation, loops, reduced motion
- [Motion that stays live](#motion-that-stays-live) - a parameter driven by a formula crosses as the formula
- [What the page weighs](#what-the-page-weighs) - what is worked out, what is fitted, what streams

---

### Recording a page

The exporter runs the sketch frame by frame at a fixed rate, the way the video export does. Each frame, it writes down what the renderer received. Nothing is rendered on the Mac while it records, so the page holds nothing GPU-specific.

```sh
swift run --package-path Examples Example-Basic-HelloCircle --export-web hello.html --seconds 6
swift run --package-path Examples Example-Basic-HelloCircle --export-web hello.html --frames 90 --fps 15
swift run OllinLive MySketches/Ring.swift --export-web ring.html --inline
```

| Flag | Meaning |
|---|---|
| `--frames N` or `--seconds S` | how long to record. With neither, a sketch that declares `loopDuration` records exactly one lap, which the page wraps without a seam. |
| `--fps F` | the recorded frames per second of the sketch's own time, 30 by default. The page interpolates between them, so a slow, smooth motion records well at 10 or 15. |
| `--skip S` | run the sketch for `S` seconds before the first recorded frame. |
| `--inline` | write the fragment for a page of your own instead of a whole file (see [the two forms](#the-two-forms)). |

`--seed`, `--param`, `--replay`, and `--automation` apply as on every export. In code, `OllinApp.web(of:frames:fps:skipSeconds:form:)` returns the page as a string, and `OllinApp.exportWeb(_:to:frames:fps:skipSeconds:form:)` writes it and reports the size.

### What crosses

The page carries the closed analytic shapes: `drawCircle`, `drawEllipse`, `drawRect`, `drawArc`, `drawTriangle`, `drawPolygon` by count, `drawStar`, `drawRing`, `drawPoint` and the markers, and the rest of the [shape catalog](../Drawing/Drawing.md). Each crosses with its fill, its stroke, the stroke's weight and alignment, a hollow band, and the transform it was drawn under. Symmetry folds cross as the copies they are. Every stroke crosses too: `drawLine`, `drawPolyline`, `drawBezier`, `drawCurve`, a `drawShape` outline, and an elliptical or full-turn `drawArc`. A stroke keeps its weight, joins, and caps, a gradient along it, and a width that varies. So does every fill the triangle path tessellates: `drawPolygon` from points, `drawShape` with its holes, `drawCurve` closed, and text in the default outline mode. A caption no longer stops a sketch. A `blendMode` applies to shapes, strokes, and fills with the factors the Mac's pipelines use. A `Batch` recorded from those shapes, strokes, and fills replays under its draw-time transform. `background` is each frame's clear, and a sketch that accumulates (`noClear`) plays back frame on frame. The tone map and the exposure ride along, and the present pass on the page dithers and encodes the way the Mac's does.

The page carries the [layered effects](../Drawing/Effects.md) too, and runs their shaders live. A layer drawn with `withTarget` crosses as a surface of its own, at its own resolution when it was made with a `scale`. It comes back onto the canvas or into another layer as the quad `drawImage(layer.image)` drew, under its `blendMode` and `tint`. Every `Generator` crosses. So does every `Filter` and `Combine` that is one shader pass on the Mac: the color and tone grades, the stylize and optical set, the distortions, the design filters that read the picture, `.mask`, `.displace`, `.mix`, `.paintMix`, `.disperse`, and the line integral convolution. The lookup filters `.gradientMap` and `.fieldMap` cross with their strips. `.gaussianBlur` and `.bloom` cross as passes of the page's own, a separable Gaussian measured against the Mac's kernel. A user [`Shader`](../Shaders/Shaders.md) crosses as a generator, a filter, or a combine. Its `shade(uv, info)` is carried to GLSL by the same rewriter and runs on the page's own clock and pointer, so `info.time` and `info.mouse` stay live. A compiled [`Visual`](../Shaders/Visuals.md) chain is a user shader and crosses the same way. `postProcess` filters run after the canvas as they do on the Mac. A `Feedback` layer and a single-field `SimField` keep their state on the page and step there. That is reaction-diffusion, Life, Lenia, the ripples, the cellular automata, the sandpile, and the falling sand. A track that holds one plays every frame in order from the first.

Anything else stops the export before a file is written, and the message names the call and the frame it was met at:

```
Ollin: --export-web stopped: withClip does not cross to the web page yet (met at frame 2); export the sketch as video instead (--export-video).
```

That covers text through the glyph atlas (`textMode(.atlas)`) and a picture drawn with `drawImage`. It covers a gradient on an analytic shape, clipping, `depth(at:)`, 3D, compute work, and wide-gamut or HDR output. A gradient on a stroke or a tessellated fill crosses, baked into its vertices as it is on the Mac. Among the effects it covers the passes that are a solve or a ladder on the Mac: `.diffuse`, `.distanceField`, `.boxBlur`, `.adaptiveThreshold`, `.fourier`, `.softProof`, `.liquidMetal`, `.heatmap`, `.gemSmoke`, `.seamlessClone`, `.defocus`, `.ambientOcclusion`, `.light`, and `.screenSpaceReflections`. It covers the simulations with a pipeline of their own: `.fluid`, `.watercolor`, `.selfWarp`, and `.multiScaleTuring`. A sketch that draws those is a video export today. The doors those calls wait on are listed in the [roadmap](../../ROADMAP.md#new-output-surfaces).

### Strokes and fills on the page

On the Mac, a stroke is expanded into bands of triangles, with an anti-aliasing coverage riding each vertex. A polygon, a shape with holes, or a glyph outline is triangulated the same way. The recorder writes those vertices down as they are, seven numbers each: the position, the coverage, and the color with its alpha. The page draws them with the two fragments the Mac uses, carried to GLSL. A fill's color is linearized and its edge left to the raster. A stroke's coverage is remapped to perceptual alpha, so a thin dark line reads as dark on the page as on the Mac.

A fill's edge has no analytic coverage of its own. So a page that draws one rasterizes every drawn surface through a four-sample multisampled buffer, as the Mac does, and resolves it after. The picture is rasterized upright in the GPU's own texture space, where the sample pattern is fixed. A mirrored picture would meet it mirrored. Measured against the Mac, a polygon's edge then agrees to within a level or two. A canvas that accumulates keeps its samples from frame to frame.

### Layers and shaders on the page

Each frame, the recorder writes down the graph the renderer received beside the shape records: the layers in the order the Mac fills them, what each was filled from (drawn into, generated, filtered from another, combined from two, run by a shader of yours, carried over by a feedback layer or a field), what the canvas drew, and the whole-frame filters. A filter's numbers travel as parameter rows the way a shape's do, so a generator's `phase` fed `time` fits to its sines on a lap and samples otherwise, and a graph that stays the same from frame to frame travels once.

The page's shaders are the framework's own. The fragment behind each filter, generator, combine, and simulation step is cut out of the Metal source with every helper it reaches and rewritten to GLSL ES 3.00, then compiled by the browser; only the fragments the recording runs are on the page. A shader of yours is rewritten the same way, with the `ShaderInfo` and the `sample` readers the framework gives it written for the page. A layer on the page is a half-float texture in linear light like the Mac's, sampled the same way.

The clock a shader reads on the page is the track's own, so a shader that moves on `info.time` moves on the page at the recorded rate, and a shader that reads `info.mouse` follows the pointer over the canvas. What Swift computed each frame and handed to a shader, a filter's angle or a `Shader`'s `params`, is a recorded column.

### The two forms

The standalone form is one self-contained HTML file: open it, host it, or put it in an `iframe`. It centers the canvas on a page the color of the sketch's own background and scales it to fit.

The inline form (`--inline`) is the same canvas and the same script block, with no page around them, for a page you already have:

```html
<canvas class="ollin-sketch" width="1080" height="1080" role="img" aria-label="..."></canvas>
<script>
...
</script>
```

Paste the two elements together, wherever the picture belongs, and style the canvas as you would any other. The script finds the canvas just ahead of it, so several pictures can share a page. The canvas's `aria-label` is what the sketch [said about itself](../Helpers/Accessibility.md), or its name.

### Playing back

The page starts playing on load and wraps at the end of the track. A sketch that declared `loopDuration` and recorded one lap wraps without a seam. Any other track wraps with whatever jump its first and last frames make. When every frame draws the same cast of shapes (the ordinary animation), the page interpolates between the recorded frames. The motion then stays smooth at any refresh rate and at any recorded rate. When the cast changes from frame to frame, the page steps.

A reader whose system asks for less motion (`prefers-reduced-motion`) sees the first frame, still. A hidden tab pauses and picks up where it left off.

The script leaves a handle on the canvas, `canvas.ollin` (and `window.ollin` for the last one on the page):

| Member | What it does |
|---|---|
| `play()`, `pause()` | run or hold the track |
| `seek(seconds)` | show the picture at a time on the sketch's clock |
| `showFrame(i)` | show one recorded frame exactly, with no interpolation |
| `frames`, `rate`, `duration`, `loops` | what was recorded |
| `playing`, `time` | where it is |

The page needs WebGL2, which every current browser has. It composites in linear light like the Mac, in a half-float intermediate where the browser renders to one. The present pass encodes to the canvas with the same dither.

### Motion that stays live

A parameter driven by a [formula](../Helpers/Formula.md) crosses as the formula, not as its values:

```swift
@Param(0 ... 300) var radius = 100.0

override func setup() {
    drive($radius, "150 + sin(time * tau / 6) * 40")
}

override func draw() {
    background(.white)
    noFill()
    stroke(.black)
    drawCircle(width / 2, height / 2, radius)
}
```

The recorder keeps the formula's value at every frame beside the shapes. A shape column that turns out to be a straight function of it (the radius here, or a position that adds an offset to it) is wired to the formula instead of being stored. The page carries the formula as JavaScript and works those columns out every frame from its own clock and pointer. So `time`, `frame`, `width`, `height`, `mouseX`, and `mouseY` mean on the page what they mean in the sketch, and a formula that reads the pointer follows it live. The parameter's range and step apply on the page as they do on the Mac. A formula that reads another driven parameter is evaluated after it, as on the Mac. One that reads a noise field stays a recorded value, since the page has no copy of the field.

A column the sketch computes in Swift from the parameter in some other way (squared, say) is not wired, and travels as the next section describes.

### What the page weighs

Each shape is 28 numbers per frame, and four things keep that small. A frame whose shapes are the previous frame's is stored once, so a still costs one frame however long it is recorded. When the cast is stable, the columns that never change (colors, a fixed transform, a stroke weight) are stored once as the base, in float32. Only the moving ones travel. A moving column wired to a formula travels as nothing at all. A moving column of a lap (a track recorded from `loopDuration`) is fitted to the sines it is made of. A motion written as sines with whole cycle counts per lap, the ordinary looping sketch, fits exactly in as many terms as it has sines. The page evaluates those at any time, so the motion between the recorded frames is the true one rather than a straight line. What fits nothing short travels as 16-bit samples, each within one part in 65,535 of its column's range, interpolated between frames.

A stroke or a fill weighs its vertices, seven numbers each. A stroke's bands run to a few dozen vertices a segment, so a dense line drawing is where a page gets heavy. The vertices of a still, or of what never moves in a drawing, travel once: each position exact, the coverage and color as 16-bit samples. Only the vertices that move travel as columns, fitted or sampled like a shape's. Measured on the sixty-one pattern examples that draw strokes and fills: a third are under 1 MB, the median is about 3 MB, and a dense line drawing runs to tens or hundreds of megabytes (a guilloche of 3.4 million vertices is 325 MB), about 36 times what the same frame weighs as SVG. A page that heavy is what the [weight budget](../../ROADMAP.md#new-output-surfaces) ahead is for; until it lands, a dense drawing is a video export.

When it finishes, the exporter prints the file size, what stayed live, what fitted, what sampled, and the fullest frame's vertex count. Measured on the ring of twenty-eight circles the site opens on: its sixty-second lap fits whole, every moving column to a few sines, and the page is 83 KB whether recorded at 10 fps or at 30. Most of that is the shaders and the player. The breathing circle for six seconds at 30 fps, not a lap, samples its radius: 75 KB. The effects examples run 98 to 165 KB for the same reason: a page carries only the fragments its frames run, and a filter's numbers add a few floats a frame. The rate still matters for a track that samples. The page interpolates, so a slow motion looks the same recorded at 10 fps as at 60 and weighs a sixth as much. A host serves the page compressed, and the encoding is shaped for that.
