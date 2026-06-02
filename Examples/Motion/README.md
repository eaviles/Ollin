#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Motion</sup>

---

## Motion

Animation driven by `time`, with the draw loop running continuously by default.

| Example | What it shows |
|---|---|
| [ArcField](ArcField/Sketch.swift) | EllipseField's cousin: chord-closed `drawArc` crescents whose start and sweep also ride `signedNoise` |
| [ArcModes](ArcModes/Sketch.swift) | the three `drawArc` closing modes — open, chord, pie — side by side under an animated sweep |
| [Breathing](Breathing/Sketch.swift) | the same circle, animated via `time` |
| [Easing](Easing/Sketch.swift) | four dots race one target flip on different `@Eased` curves — linear, ease-in, ease-out, ease-in-out — pulling apart in flight |
| [EllipseField](EllipseField/Sketch.swift) | rows of `drawEllipse` outlines in two columns, drifting and squashing via `signedNoise` |
| [FlowField](FlowField/Sketch.swift) | a `curlNoise` flow field: short lines follow the divergence-free curl, drifting with `time` |
| [Mandala](Mandala/Sketch.swift) | nested, counter-rotating `hollow` shapes — each a framed band in one call — sliding into a moiré (`hollow`, SDF) |
| [Myriad](Myriad/Sketch.swift) | 8,100 noise-driven circles on the SDF path — thousands of shapes at full speed |
| [Orbits](Orbits/Sketch.swift) | ten circles orbiting the center at rising speeds |
| [Polygons](Polygons/Sketch.swift) | regular `drawNgon` (3–8 sides) and a five-point `drawStar` relaxing from spiky to round as its inner radius grows, both turning (SDF) |
| [RectField](RectField/Sketch.swift) | Myriad's cousin: thousands of rounded rects, corner radius sweeping square→pill, each rotated on the SDF box path |
| [SineSweep](SineSweep/Sketch.swift) | a circle swept across the canvas by `sin(time)` |
| [Spokes](Spokes/Sketch.swift) | a sunburst of fat, round-capped `drawLine` spokes pulsing with `time` (capsule SDF) |
| [Star](Star/Sketch.swift) | a concave star with a hole, filled via `drawShape` and the vector `Shape` type (a triangulated fill `drawPolygon` can't do) |
| [Trail](Trail/Sketch.swift) | a Lissajous point traced by a 600-segment polyline |
| [Triangles](Triangles/Sketch.swift) | the two `drawTriangle` forms side by side — equilateral pivoting on its center, isosceles wedge pivoting on its apex (SDF) |

Run one with `swift run Example-<Name>`, e.g. `swift run Example-Breathing`.
