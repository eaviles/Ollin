#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Patterns</sup>

---

## Patterns

Generative patterns: grids, tessellations, and rule-based repetition. (Shape *primitives* and
shape *composition* (booleans and SDF combinators) live in [Shapes](../Shapes/).)

| Example | What it shows |
|---|---|
| [Dendrite](Dendrite/Sketch.swift) | diffusion-limited aggregation: random walkers freeze where they first touch the cluster, growing frost-like dendrites from a center seed, tinted by arrival time (`DiffusionLimitedAggregation`) |
| [CliffordAttractor](CliffordAttractor/Sketch.swift) | a Clifford map iterated into an accumulating additive density field, bright filaments where the chaotic orbit returns again and again (`ChaoticMap.clifford`, `noClear`, `blendMode(.add)`) |
| [DotGrid](DotGrid/Sketch.swift) | a grid of black/white dots woven by a modulo rule |
| [EnergyGrid](EnergyGrid/Sketch.swift) | columns sized by a moving "energy" share (`translate`, `drawRect`) |
| [LifeQuilt](LifeQuilt/Sketch.swift) | a four-layer Game of Life filling cells with triangular wedges, colored by a radial cosine palette (`drawTriangle`, SDF) |
| [Phyllotaxis](Phyllotaxis/Sketch.swift) | a sunflower seed-head — points at the golden angle marching outward by `sqrt(i)` — built into a `Circle` array and drawn with a single batch call, spinning slowly while the count breathes (`drawCircles`) |
| [Topography](Topography/Sketch.swift) | a breathing blob inset inward over and over until the region pinches out, each surviving ring stroked — contour lines that crowd where the form narrows; pure line work that plots straight to SVG (`Shape.offset(by:join:)`) |
| [Venation](Venation/Sketch.swift) | space colonization: veins grow live from a bottom root toward a blue-noise attractor scatter, branch weight from the pipe model (`SpaceColonization`, `poissonDisk`) |
| [Voronoi](Voronoi/Sketch.swift) | a field of noise-drifting sites partitioned into Voronoi cells, evened out with Lloyd relaxation and colored by a sweeping focal point — the cursor is a live site, so the cells crystallize around the mouse (`voronoi`/`lloyd`) |
| [WarpGrid](WarpGrid/Sketch.swift) | a checkerboard of rects warped under the mouse (`drawRect`) |

Run one with `swift run Example-Patterns-<Name>`, e.g. `swift run Example-Patterns-DotGrid`.
