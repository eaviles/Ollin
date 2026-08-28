#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → Concepts</sup>

---

## Concepts

The ideas the rest of the reference assumes. Each page is one screen, answers one question, and ends with the reference pages and the guide chapter that carry it further.

Read one when a reference page tells you what a call does and you wanted to know why the call exists at all. They are reference material rather than a lesson: come back to them, in any order.

- [`The frame`](./Frame.md) - what a drawing call actually does, and what happens between `draw()` and the picture
- [`Where a point is`](./Coordinates.md) - the canvas coordinates and their units, and the other frames a sketch meets
- [`Layers`](./Layers.md) - what an off-screen layer is, what it costs, and when you need one
- [`What survives a frame`](./Persistence.md) - what Ollin keeps between frames and what it drops: state, the canvas, layers, batches, saved values
- [`Why a run repeats`](./Determinism.md) - the seed and the clock, and what makes a sketch draw the same picture twice
- [`Light and color`](./Light.md) - why color mixes in linear light, and what the last pass of a frame does
- [`Values and bare calls`](./Values.md) - the typed values under `drawCircle(x, y, r)`, and when to reach for them

The narrative layer is [the Guide](../../Guide/README.md), which teaches these ideas in order and at length. The rest of [`Docs/`](../README.md) is the call-by-call reference.
