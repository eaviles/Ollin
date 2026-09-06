#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → Core</sup>

---

## Core

- [`Sketch`](./Sketch.md) - the lifecycle (`setup`/`draw`), the temporal state (`time`, `frameCount`, …), and loop control
- [`Canvas`](./Canvas.md) - `scale`, the `canvasSize` export presets, and the preview window (`windowMode`)
- [`Variations`](./Variations.md) - `variation`, the seed a run starts from. In the inspector you can step, roll, and jump through a sketch's variation space. You can also preview a range as a contact sheet (`--export-grid`), then re-render the one you want to keep with `--seed`
- [`Replay`](./Replay.md) - record a run's seed, clock, inputs, and parameter changes as a take (`--record-take`). Then play it back exactly (`--replay`, with transport keys), scrub through it, and re-render the performance through any export flag
- [`Automation`](./Automation.md) - keyframed parameters. Write a parameter's values down over time (`automate`) and shape them with named or Bezier curves. You can then loop them, play them at any speed, read them from a file (`--automation`), and render them exactly in any export
