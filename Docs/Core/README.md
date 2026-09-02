#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → Core</sup>

---

## Core

- [`Sketch`](./Sketch.md) - the lifecycle (`setup`/`draw`), temporal state (`time`, `frameCount`, …), and loop control
- [`Canvas`](./Canvas.md) - `scale`, the `canvasSize` export presets, and the preview window (`windowMode`)
- [`Variations`](./Variations.md) - `variation`, the seed a run grew from: step, roll, and jump through a sketch's variation space in the inspector, proof a range as a contact sheet (`--export-grid`), and re-render a keeper with `--seed`
- [`Replay`](./Replay.md) - record a run's seed, clock, inputs, and parameter moves as a take (`--record-take`), play it back exactly (`--replay`, with transport keys), scrub it, and re-render the performance through any export flag
- [`Automation`](./Automation.md) - keyframed parameters: a parameter's values written down over time (`automate`), carried by named or Bezier curves, looped and played at any speed, read from a file (`--automation`) and rendered exactly by any export
