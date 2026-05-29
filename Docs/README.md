#### <sup>[Ollin](../README.md) → Documentation</sup>

---

## Ollin API

Reference for Ollin's drawing surface and helpers. The bare calls you write in `draw()` forward to an internal `Drawer` (see [How it works](../README.md#how-it-works-one-paragraph)); everything here is callable bare inside a `Sketch`.

### Core

- [`Sketch`](./Sketch.md) - the lifecycle (`setup`/`draw`), temporal state (`time`, `frameCount`, …), and loop control
- [`Canvas`](./Canvas.md) - `scale`, the `canvasSize` export presets, and the preview window (`windowMode`)

### Drawing

- [`Drawing`](./Drawing.md) - `background`, `fill`/`stroke`, the shapes, and the transform stack
- [`Color`](./Color.md) - the `Color` type, cosine-gradient `Palette`s, and perceptual `Colormap`s
- [`Geometry`](./Geometry.md) - the `Vector2` and `Rectangle` value types

### Generators

- [`Random`](./Random.md) - `random`, `randomGaussian`, and the `randomVector`/`ring` scatter helpers
- [`Noise`](./Noise.md) - Perlin `noise`, `signedNoise`, and `curlNoise` flow fields

### Helpers

- [`Math`](./Math.md) - `map` and `dist`
- [`Input`](./Input.md) - mouse position and clicks

Coordinates use a **top-left origin with y increasing downward**, the same as p5, Processing, and OPENRNDR.
