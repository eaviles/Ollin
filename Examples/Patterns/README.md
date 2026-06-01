#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Patterns</sup>

---

## Patterns

Grids and rule-based repetition.

| Example | What it shows |
|---|---|
| [DotGrid](DotGrid/Sketch.swift) | a grid of black/white dots woven by a modulo rule |
| [EnergyGrid](EnergyGrid/Sketch.swift) | columns sized by a moving "energy" share (`translate`, `drawRect`) |
| [LifeQuilt](LifeQuilt/Sketch.swift) | a four-layer Game of Life filling cells with triangular wedges, colored by a radial cosine palette (`drawTriangle`, SDF) |
| [Markers](Markers/Sketch.swift) | the five `drawPoint` markers, one per row, swept across sizes (`pointMarker`, SDF) |
| [WarpGrid](WarpGrid/Sketch.swift) | a checkerboard of rects warped under the mouse (`drawRect`) |

Run one with `swift run Example-<Name>`, e.g. `swift run Example-DotGrid`.
