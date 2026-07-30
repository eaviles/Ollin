#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Patterns</sup>

---

## Patterns

Generative patterns: grids, tessellations, and rule-based repetition. (Shape *primitives* and
shape *composition* (booleans and SDF combinators) live in [Shapes](../Shapes/).)

| Example | What it shows |
|---|---|
| [BlueNoise](BlueNoise/Sketch.swift) | blue-noise stippling: `poissonDisk` scatters points no two closer than a radius (Bridson's dart-throwing), the even-but-organic coverage that reads as natural texture |
| [CirclePacking](CirclePacking/Sketch.swift) | grow-to-touch circle packing, both flavors: a self-seeding gap-filling pack, and a foam grown from a blue-noise scatter (`packCircles`) |
| [CliffordAttractor](CliffordAttractor/Sketch.swift) | a Clifford map iterated into an accumulating additive density field, bright filaments where the chaotic orbit returns again and again (`ChaoticMap.clifford`, `noClear`, `blendMode(.add)`) |
| [Dendrite](Dendrite/Sketch.swift) | diffusion-limited aggregation: random walkers freeze where they first touch the cluster, growing frost-like dendrites from a center seed, tinted by arrival time (`DiffusionLimitedAggregation`) |
| [DifferentialGrowth](DifferentialGrowth/Sketch.swift) | a closed ring relaxed under attraction, alignment, and repulsion with long edges splitting, folding live into brain-coral meanders (`DifferentialGrowth`) |
| [DotGrid](DotGrid/Sketch.swift) | a grid of black/white dots woven by a modulo rule |
| [ElementaryCA](ElementaryCA/Sketch.swift) | 1D cellular automata stacked as rows, elementary and 3-color totalistic, the rule and code on knobs: one number flips the picture between order, fractals, and chaos (`elementaryCA`, `totalisticCA`) |
| [EnergyGrid](EnergyGrid/Sketch.swift) | columns sized by a moving "energy" share (`translate`, `drawRect`) |
| [Flocking](Flocking/Sketch.swift) | a few hundred boids, each steering only by its neighbors (separate, align, cohere), the flock swirling and regrouping with no leader (`Boids`) |
| [FractalFlame](FractalFlame/Sketch.swift) | a random fractal flame refining live: the chaos game with nonlinear variations, structural coloring, and the log-density display, accumulated slice by slice; click to reroll (`FractalFlame`, `FractalFlame.Renderer`) |
| [Grid](Grid/Sketch.swift) | a 16×16 `Grid` showing both element kinds: `cells` outline the frames, `points` dot each center, with `padding` and `gutter` shaping the lattice |
| [InversionFractal](InversionFractal/Sketch.swift) | the limit-set lace of a tangent circle ring, resampled every frame so it shimmers; click to change the ring (`inversionLimitSet`, `inverted`) |
| [IteratedFunctions](IteratedFunctions/Sketch.swift) | the chaos game condensing the fern, the triangle, and the carpet onto the accumulation surface, a few thousand visits per frame (`IFS`, `ifsPoints`, `fitted`) |
| [Kaleidoscope](Kaleidoscope/Sketch.swift) | one drawn arm replicated into a sixteen-fold mandala by `symmetry(8, mirrored: true)`, every draw call folding through the mirrors |
| [Kleinian](Kleinian/Sketch.swift) | Kleinian limit sets as one ordered closed curve, a bright head running the whole lap each loop; click for the next preset traces (`kleinianLimitSet`, `KleinianPreset`) |
| [LevyFlight](LevyFlight/Sketch.swift) | a Lévy flight: power-law step lengths make tight scribble clusters strung together by sudden long jumps, a comet retracing the journey out and back (`levyFlight`) |
| [LifeQuilt](LifeQuilt/Sketch.swift) | a four-layer Game of Life filling cells with triangular wedges, colored by a radial cosine palette (`drawTriangle`, SDF) |
| [LowDiscrepancy](LowDiscrepancy/Sketch.swift) | random, Poisson-disk, Halton, and Sobol scatter side by side while the count breathes: the sequences stay even at every count and only ever add points, never reshuffle (`haltonPoints`, `sobolPoints`) |
| [LSystem](LSystem/Sketch.swift) | the built-in L-system presets, one per cell: tiny rewriting grammars unfolded into fractal curves and branching plants (`LSystem`, `drawLSystem`) |
| [Phyllotaxis](Phyllotaxis/Sketch.swift) | a sunflower seed-head: `phyllotaxis(count:spacing:)` places seeds at the golden angle marching outward by `sqrt(i)`, sized by age and drawn with one `drawCircles` batch, spinning slowly while the count breathes |
| [RidgeLines](RidgeLines/Sketch.swift) | stacked mountain ridgelines from ridged fractal noise, each row's opaque panel occluding the range behind it; the looping field brings the terrain home every lap (`ridgedFbm`) |
| [Roses](Roses/Sketch.swift) | the rose-curve chart over a `Grid`: columns raise `n`, rows raise `d` in `k = n/d`, odd `n` gives `n` petals and even `2n`, fractional `k` weaves stars, reduced duplicates inked in the accent; each rose spins one petal per lap (`rose`) |
| [SelfAvoidingWalk](SelfAvoidingWalk/Sketch.swift) | one unbroken lattice path that never crosses itself, backtracking out of dead ends to wind long and dense, colored along its length (`selfAvoidingWalk`) |
| [ShapePacking](ShapePacking/Sketch.swift) | geometry-aware packing, a few shapes added per frame, each grown against the outlines already placed so small shapes nestle into notches, riding `noClear` accumulation (`ContinuousPacking`) |
| [Spirograph](Spirograph/Sketch.swift) | the toy gear set: one gear pair stacked at several pen distances into a glowing rosette, the pen sliding in and out over the loop, spinning exactly one lobe per lap (`hypotrochoid`) |
| [Stippling](Stippling/Sketch.swift) | weighted-Voronoi stippling: a painted, lit sphere rebuilt from 5,200 dots whose packing density follows the picture's darkness (`stipple`) |
| [Streamlines](Streamlines/Sketch.swift) | evenly-spaced streamlines through a noise flow field, each line stopping when it nears one already drawn, fanning into smooth non-crossing currents (`FlowField.streamlines`) |
| [Topography](Topography/Sketch.swift) | a breathing blob inset inward over and over until the region pinches out, each surviving ring stroked: contour lines that crowd where the form narrows; pure line work that plots straight to SVG (`Shape.offset(by:join:)`) |
| [Truchet](Truchet/Sketch.swift) | one tile per grid cell at a seed-chosen spin: quarter-arcs meet across borders into meandering loops while a flow field sweeps hue along them (`truchet`) |
| [Turmites](Turmites/Sketch.swift) | tiny Turing machines painting a wrapped grid: Langton's ant and its highway, spiral builders, chaotic weavers, all on a preset knob (`Turmite`) |
| [Venation](Venation/Sketch.swift) | space colonization: veins grow live from a bottom root toward a blue-noise attractor scatter, branch weight from the pipe model (`SpaceColonization`, `poissonDisk`) |
| [Voronoi](Voronoi/Sketch.swift) | a field of noise-drifting sites partitioned into Voronoi cells, evened out with Lloyd relaxation and colored by a sweeping focal point; the cursor is a live site, so the cells crystallize around the mouse (`voronoi`/`lloyd`) |
| [WarpGrid](WarpGrid/Sketch.swift) | a checkerboard of rects warped under the mouse (`drawRect`) |
| [WaveFunctionCollapse](WaveFunctionCollapse/Sketch.swift) | a pipe network solved by Wave Function Collapse: min-entropy observation, weighted collapse, and constraint propagation over edge sockets until every neighbor connects legally (`wfc`, `drawWFC`) |

Run one with `swift run Example-Patterns-<Name>`, e.g. `swift run Example-Patterns-DotGrid`.
