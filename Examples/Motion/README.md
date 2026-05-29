#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Motion</sup>

---

## Motion

Animation driven by `time`, with the draw loop running continuously by default.

| Example | What it shows |
|---|---|
| [ArcField](ArcField/Sketch.swift) | EllipseField's cousin: chord-closed `drawArc` crescents whose start and sweep also ride `signedNoise` |
| [Breathing](Breathing/Sketch.swift) | the same circle, animated via `time` |
| [EllipseField](EllipseField/Sketch.swift) | rows of `drawEllipse` outlines in two columns, drifting and squashing via `signedNoise` |
| [FlowField](FlowField/Sketch.swift) | a `curlNoise` flow field: short lines follow the divergence-free curl, drifting with `time` |
| [Myriad](Myriad/Sketch.swift) | 8,100 noise-driven circles on the SDF path — thousands of shapes at full speed |
| [Orbits](Orbits/Sketch.swift) | ten circles orbiting the center at rising speeds |
| [SineSweep](SineSweep/Sketch.swift) | a circle swept across the canvas by `sin(time)` |
| [Trail](Trail/Sketch.swift) | a Lissajous point traced by a 600-segment polyline |

Run one with `swift run Example-<Name>`, e.g. `swift run Example-Breathing`.
