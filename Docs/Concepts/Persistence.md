#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Concepts](./README.md) → `What survives a frame`</sup>

---

## What survives a frame

Ollin discards most of a frame and starts the next one clean (see [the frame](./Frame.md)). A few things carry over, and knowing which ones explains a common set of surprises. A transform starts over each frame, but a fill color does not. A batch ignores a number you just changed. A parameter survives a reload.

### Dropped every frame

- **The geometry.** Every shape you recorded goes away, and the next frame records its own.
- **The transform.** `translate`, `rotate`, and `scale` start from the identity again. A rotation applied each frame turns by the same angle, so the angle never winds up.
- **The camera, the lights, and the 3D settings.** Set them in `draw()` each time, beside the geometry they act on.
- **Layers.** A `makeRenderTarget()` belongs to the frame that made it.

### Kept between frames

- **The ink state.** `fill`, `stroke`, `strokeWeight`, the blend mode, and the settings beside them carry into the next frame. A color set in `setup()` still applies. Most sketches set them each frame anyway, and that is the habit worth having.
- **The canvas, if you ask for it.** `noClear()` stops the per-frame wipe, so drawing builds up and `background(_:)` becomes the way to reset. Long exposures and paint-on-canvas sketches work this way. See [accumulation](../Drawing/Accumulation.md).
- **A feedback or simulation layer's pixels.** These layers are built to read their own last frame.
- **Your own properties.** An ordinary Swift property on the sketch lives as long as the sketch does. Put a particle array or a growing path there.

### What a batch keeps

`makeBatch { }` records drawing once and hands back a handle. You draw that handle each frame at almost no cost. A batch holds the drawing *as recorded*: the geometry, its colors, and the per-shape state each call ran under. It cannot hold anything that changes per frame, because none of the code inside runs again. The transform in force at draw time still places or stamps the whole recording, so a fixed field of marks can move as one piece. A live layer or a video frame recorded into a batch freezes as it stood.

### Kept across a live reload

A reload builds a fresh sketch, so properties start over and `setup()` runs again. Two things carry across. Every `@Param` value stays, so a parameter you tuned stays tuned. The clock also carries when you ask the host for it with `--keep-clock`, so an animation keeps its phase instead of jumping. `reloaded()` runs once after the swap, and never on the first launch.

### Kept across runs

`@Saved` writes a property to disk at the interval set by `checkpoint:`, along with the seed, the clock, and the parameter values. A piece that has run on a wall for a week then picks up where it stopped instead of starting over. See [running unattended](../Output/Installation.md).

### Read next

- [The frame](./Frame.md) - what a drawing call does, and what happens after `draw()` returns.
- [`Accumulation`](../Drawing/Accumulation.md) - the canvas kept on purpose.
- [`Retained batches`](../Drawing/Batches.md) - the full surface, including what a recording cannot hold.
- [`Sketch`](../Core/Sketch.md) - the lifecycle, `reloaded()`, and the clock.
- [`Installation`](../Output/Installation.md) - `@Saved`, checkpoints, and a run measured in days.
