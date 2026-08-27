#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Concepts](./README.md) → `What survives a frame`</sup>

---

## What survives a frame

Ollin throws most of a frame away and starts the next one clean (see [the frame](./Frame.md)). Knowing what it keeps clears up a class of surprise. A transform starts over each frame and a fill color does not. A batch ignores the number you just changed. A knob survives a reload.

### Dropped every frame

- **The geometry.** Every shape you recorded. The next frame records its own.
- **The transform.** `translate`, `rotate`, and `scale` start from the identity again, so a rotation applied each frame turns by the same angle rather than winding up.
- **The camera, the lights, and the 3D settings.** Set them in `draw()` each time, beside the geometry they act on.
- **Layers.** A `renderTarget()` belongs to the frame that made it.

### Kept between frames

- **The ink state.** `fill`, `stroke`, `strokeWeight`, the blend mode and their neighbors carry into the next frame, so a color set in `setup()` still applies. Most sketches set them each frame anyway, and that is the habit worth having.
- **The canvas, if you ask for it.** `noClear()` stops the per-frame wipe, so drawing piles up and `background(_:)` becomes the reset. This is how long exposures and paint-on-canvas sketches work; see [accumulation](../Drawing/Accumulation.md).
- **A feedback or simulation layer's pixels.** Those are the layers built to read their own last frame.
- **Your own properties.** An ordinary Swift property on the sketch lives as long as the sketch does, which is where a particle array or a growing path belongs.

### What a batch keeps

`makeBatch { }` records drawing once and hands back a handle you draw each frame for almost nothing. What it holds is the drawing *as recorded*: the geometry, its colors, and the per-shape state each call ran under. What it cannot hold is anything that changes per frame, because none of the code inside runs again. A transform at draw time still places or stamps the whole recording, so a fixed field of marks can move as one piece. A live layer or a video frame recorded into a batch freezes as it stood.

### Kept across a live reload

A reload builds a fresh sketch: properties start over and `setup()` runs again. Two things carry across. Every `@Param` value stays, so a knob you tuned stays tuned. The clock carries too when the host is asked for it (`--keep-clock`), so an animation keeps its phase instead of jumping. `onReload()` runs once after the swap, and never on the first launch.

### Kept across runs

`@Saved` writes a property to disk on the cadence set by `checkpoint:`, along with the seed, the clock, and the knob values. A piece that has run on a wall for a week picks up where it stopped rather than starting over. See [running unattended](../Output/Installation.md).

### Read next

- [The frame](./Frame.md) - what a drawing call does, and what happens after `draw()` returns.
- [`Accumulation`](../Drawing/Accumulation.md) - the canvas kept on purpose.
- [`Retained batches`](../Drawing/Batches.md) - the full surface, including what a recording refuses to hold.
- [`Sketch`](../Core/Sketch.md) - the lifecycle, `onReload()`, and the clock.
- [`Installation`](../Output/Installation.md) - `@Saved`, checkpoints, and a run measured in days.
