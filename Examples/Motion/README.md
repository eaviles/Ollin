#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Motion</sup>

---

## Motion

Animation driven by `time`, with the draw loop running continuously by default.

| Example | What it shows |
|---|---|
| [Breathing](Breathing/Sketch.swift) | the same circle, animated via `time` |
| [SineSweep](SineSweep/Sketch.swift) | a circle swept across the canvas by `sin(time)` |
| [Orbits](Orbits/Sketch.swift) | ten circles orbiting the center at rising speeds |
| [Trail](Trail/Sketch.swift) | a Lissajous point traced by a 600-segment polyline |
| [FlowField](FlowField/Sketch.swift) | a `curlNoise` flow field: short lines follow the divergence-free curl, drifting with `time` |

Run one with `swift run Example-<Name>`, e.g. `swift run Example-Breathing`.
