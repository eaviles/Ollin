#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → Concepts</sup>

---

## Concepts

These pages explain the ideas that the rest of the reference assumes. Each page fits on one screen and answers one question. Each page ends with links to the reference pages and to the Guide chapter that cover the idea in more depth.

Read one when a reference page tells you what a call does, but you want to know why the call exists. These pages are reference material, not a lesson, so you can come back to them at any time and in any order.

- [`The frame`](./Frame.md) - what a drawing call does, and what happens between `draw()` and the picture
- [`Where a point is`](./Coordinates.md) - the canvas coordinates and their units, and the other coordinate frames a sketch works with
- [`Layers`](./Layers.md) - what an off-screen layer is, what it costs, and when you need one
- [`What survives a frame`](./Persistence.md) - what Ollin keeps between frames and what it drops: state, the canvas, layers, batches, saved values
- [`Why a run repeats`](./Determinism.md) - the seed and the clock, and what makes a sketch draw the same picture twice
- [`Light and color`](./Light.md) - why color mixes in linear light, and what the last pass of a frame does
- [`Values and bare calls`](./Values.md) - the typed values under `drawCircle(x, y, r)`, and when to use them

The narrative version of these ideas is [the Guide](../../Guide/README.md), which teaches them in order and at length. The rest of [`Docs/`](../README.md) is the call-by-call reference.
