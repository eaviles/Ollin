#### <sup>[Ollin](../README.md) → Documentation</sup>

---

## Ollin API

Reference for Ollin's drawing surface and helpers. The bare calls you write in `draw()` forward to an internal `Drawer` (see [How it works](../README.md#how-it-works-one-paragraph)); everything here is callable bare inside a `Sketch`.

New to Swift, coming from p5.js or JavaScript? Start with the [Swift primer](./Swift.md) — just enough of the language to be productive in `draw()`.

### Core

- [`Sketch`](./Sketch.md) - the lifecycle (`setup`/`draw`), temporal state (`time`, `frameCount`, …), and loop control
- [`Canvas`](./Canvas.md) - `scale`, the `canvasSize` export presets, and the preview window (`windowMode`)

### Drawing

- [`Drawing`](./Drawing.md) - `background`, `fill`/`stroke`, the shapes, and the transform stack
- [`Text`](./Text.md) - `drawText` with bitmap *and* outline (`.ttf`/`.otf`) fonts, plus `textToShapes` (text as geometry)
- [`Images`](./Images.md) - `loadImage` and `drawImage` - load a raster image and draw it, scaled or transformed
- [`Color`](./Color.md) - the `Color` type, cosine-gradient `Palette`s, and perceptual `Colormap`s
- [`Geometry`](./Geometry.md) - the `Vector2`, `Rectangle`, `Shape`/`Contour`, and `Path` value types (including curved outlines)

### Generators

- [`Random`](./Random.md) - `random`, `randomGaussian`, and the `randomVector`/`ring` scatter helpers
- [`Noise`](./Noise.md) - Perlin `noise`, `signedNoise`, and `curlNoise` flow fields

### Helpers

- [`Math`](./Math.md) - `map`, `dist`, and `lerp`
- [`Animation`](./Animation.md) - the `Easing` curves, `@Eased`, and `@Smoothed` — easing toward a target, and smoothing a noisy signal
- [`Input`](./Input.md) - mouse and keyboard

Coordinates use a **top-left origin with y increasing downward**, the same as p5, Processing, and OPENRNDR.
