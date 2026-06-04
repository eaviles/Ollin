#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Export`</sup>

---

## Export

Save what a sketch draws — as raster (PNG frames and image sequences) or as **vector** (SVG, for pen plotters and any vector pipeline). Export runs the sketch *headlessly*: it calls `setup()`, advances the clock to the frame you ask for, runs `draw()`, and writes the result. No window opens, so the same call works from a script or a render farm.

Most exports are reached by a command-line flag on any example's executable; the same work is available as functions on `OllinApp` if you're driving it yourself.

### Contents

- [Raster: PNG and sequences](#raster-png-and-sequences) — `--export`, `--export-sequence`
- [Vector: SVG](#vector-svg) — `--export-svg`, `OllinApp.svg` / `exportSVG`
- [What SVG export records](#what-svg-export-records) — the shape mapping and the limits

---

### Raster: PNG and sequences

Write one frame to a PNG:

```sh
swift run Example-HelloCircle --export /tmp/frame.png            # frame 0
swift run Example-HelloCircle --export /tmp/frame.png --frame 90 # a later frame
```

Write a deterministic, fixed-timestep PNG sequence (ready for `ffmpeg`):

```sh
swift run Example-Breathing --export-sequence /tmp/out --seconds 5 --fps 60
```

Both render through Metal off-screen (MSAA, then resolve), so the pixels match the live window. The same capability is available as `OllinApp.image(of:frame:)` (returns a `CGImage`), `OllinApp.export(_:to:frame:)`, and `OllinApp.exportSequence(...)`. For a *reproducible* sequence, seed the sketch (`seed(…)` in `setup()`).

### Vector: SVG

Serialize one frame's geometry as an SVG document rather than pixels:

```sh
swift run Example-VectorExport --export-svg /tmp/shapes.svg            # frame 0
swift run Example-VectorExport --export-svg /tmp/shapes.svg --frame 30 # a later frame
```

Unlike raster export, SVG export records the draw calls on the **CPU** — it never touches the GPU, so it runs anywhere and is fully deterministic. The same is available as functions:

```swift
let document = OllinApp.svg(of: MySketch(), frame: 0)   // -> String
OllinApp.exportSVG(MySketch(), to: "/tmp/shapes.svg")   // writes the file
```

This is the path for **pen plotters** (an AxiDraw plots an SVG through its own tooling) and for any tool that consumes vector art. Stroke-based sketches map most naturally, since a plotter draws with a pen — the single-line [stroke fonts](./Text.md) and stroked geometry are exactly what it plots.

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
