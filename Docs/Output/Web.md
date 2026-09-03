#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → Web page</sup>

---

## A sketch as a web page

`--export-web` records what a sketch draws over a duration and writes a page that plays it back in a browser. It is an export like video: the sketch runs on the Mac, and the page is a file you put wherever you like. The page draws with the framework's own shape shader, carried from Metal to GLSL. A frame on the page is the frame the Mac would have shown.

```sh
swift run --package-path Examples Example-Web-BreathingRing --export-web ring.html
```

The sketch keeps its source in Swift. The page holds a canvas, the shaders, and the recorded track, and nothing else: no source, no editor.

### Contents

- [Recording a page](#recording-a-page) - the flag, its length, `OllinApp.web` / `exportWeb`
- [What crosses](#what-crosses) - the analytic shapes, and what stops the export
- [The two forms](#the-two-forms) - one self-contained file, or a fragment for a page of your own
- [Playing back](#playing-back) - the handle on the canvas, interpolation, loops, reduced motion
- [What the page weighs](#what-the-page-weighs) - what is stored once, what streams

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

The page carries the closed analytic shapes: `drawCircle`, `drawEllipse`, `drawRect`, `drawArc`, `drawTriangle`, `drawPolygon` by count, `drawStar`, `drawRing`, `drawPoint` and the markers, and the rest of the [shape catalog](../Drawing/Drawing.md). Each crosses with its fill, its stroke, the stroke's weight and alignment, a hollow band, and the transform it was drawn under. Symmetry folds cross as the copies they are. A `Batch` recorded from those shapes replays under its draw-time transform. `background` is each frame's clear, and a sketch that accumulates (`noClear`) plays back frame on frame. The tone map and the exposure ride along, and the present pass on the page dithers and encodes the way the Mac's does.

Anything else stops the export before a file is written, and the message names the call and the frame it was met at:

```
Ollin: --export-web stopped: a stroked path (drawLine, drawPolyline, drawBezier, drawCurve, a drawShape outline), which goes through the stroke path does not cross to the web page yet (met at frame 2); export the sketch as video instead (--export-video).
```

That covers a stroked path or a filled polygon (the triangle path), text, and images. It covers a gradient fill or stroke, a layer or an effect, and clipping. It also covers a blend mode other than the default, `depth(at:)`, 3D, compute work, and wide-gamut or HDR output. A sketch that draws those is a video export today. The doors those calls wait on are listed in the [roadmap](../../ROADMAP.md#new-output-surfaces).

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

### What the page weighs

Each shape costs 28 numbers per frame, kept as the float32 the Mac used, so the page draws with the numbers the Mac had. Two things keep that small. A frame whose shapes are the previous frame's is stored once, so a still costs one frame however long it is recorded. When the cast is stable, the columns that never change (colors, a fixed transform, a stroke weight) are stored once as the base. Only the moving ones stream. A breathing circle streams its radius and nothing else. The ring of twenty-eight circles the site opens on streams about 560 bytes a frame. The exporter prints the file size when it finishes, with the count of distinct frames where some folded. Measured: the breathing circle for six seconds at 30 fps is 74 KB, most of it the shaders and the player. The ring's whole sixty-second lap is 521 KB at 10 fps and 1.4 MB at 30.

The rate is the other lever. The page interpolates, so a motion made of slow sines looks the same recorded at 10 fps as at 60. It weighs a sixth as much.
