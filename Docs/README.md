#### <sup>[Ollin](../README.md) → Documentation</sup>

---

### Ollin API

Reference for Ollin's drawing surface and helpers. The bare calls you write in `draw()` forward to an internal `Drawer` (see [How it works](../README.md#how-it-works-one-paragraph)); everything here is callable bare inside a `Sketch`.

### Modules

- [`Sketch`](./Sketch.md) - the lifecycle (`setup`/`draw`), temporal state (`time`, `frameCount`, …), canvas size, and loop control
- [`Drawing`](./Drawing.md) - `background`, `fill`/`stroke`, the shapes, and the transform stack
- [`Color`](./Color.md) - the `Color` type, cosine-gradient `Palette`s, and perceptual `Colormap`s
- [`Geometry`](./Geometry.md) - the `Vector2` and `Rectangle` value types
- [`Randomness`](./Randomness.md) - `random`, `randomGaussian`, Perlin `noise`, `curlNoise`, and scatter helpers
- [`Math`](./Math.md) - `map` and `dist`
- [`Input`](./Input.md) - mouse position and clicks

Coordinates use a **top-left origin with y increasing downward**, the same as p5, Processing, and OPENRNDR.
