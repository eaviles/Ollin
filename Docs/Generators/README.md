#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → Generators</sup>

---

## Generators

- [`Random`](./Random.md) - `random`, `randomGaussian`, and the `randomVector`/`ring` scatter helpers
- [`Noise`](./Noise.md) - Perlin `noise`, `signedNoise`, and `curlNoise` flow fields
- [`Blue noise`](./BlueNoise.md) - `poissonDisk`, an even-but-organic scatter with no clumps or gaps (Poisson-disk sampling)
- [`Low-discrepancy sampling`](./LowDiscrepancy.md) - `haltonPoints` / `sobolPoints`, even coverage as an ordered stream: growing the count only adds points, never moves them
- [`Stippling`](./Stippling.md) - `stipple`, dots packed to reproduce an image's tone (weighted-Voronoi stippling), or any density function
- [`Single line`](./SingleLine.md) - `singleLine`, one continuous tour through an image's stipple (TSP art), a plotter-friendly `Contour`
- [`Random walks`](./Walks.md) - `randomWalk` / `levyFlight` / `selfAvoidingWalk`, paths built one random step at a time: the local tangle, the cluster-and-leap, and the never-crossing single stroke
- [`Circle packing`](./Packing.md) - `packCircles` and `relaxCircles`, filling a region with non-overlapping circles that grow until they touch
- [`L-systems`](./LSystem.md) - `drawLSystem` and a preset catalog: a rewriting grammar walked by a turtle into fractal curves and branching plants
- [`Differential growth`](./DifferentialGrowth.md) - `DifferentialGrowth`, a line of nodes that grows and folds into organic, brain-coral structure (a stateful stepper)
- [`Wave Function Collapse`](./WaveFunctionCollapse.md) - `wfc`, filling a grid from a tileset so every neighbor is legal (constraint-solved tile layouts)
- [`Cellular automata`](./CellularAutomata.md) - `elementaryCA`/`totalisticCA` rule-by-number row stacks, and `Turmite` walkers (Langton's ant and friends) painting a wrapped grid
- [`Shape packing`](./ShapePacking.md) - `packShapes` and `ContinuousPacking`, filling a region with non-overlapping shapes grown against each other's outlines
- [`Flow fields`](./FlowField.md) - `FlowField`, tracing streamlines through a direction field (the flow-field look) and advecting particles along it
- [`Flocking`](./Boids.md) - `Boids`, a flock steering by separation/alignment/cohesion into emergent flocking motion
- [`Steering`](./Steering.md) - `Vehicle`, a creature moved by composable steering forces (seek, flee, arrive, pursue, wander, follow a path or flow field)
- [`Space colonization`](./SpaceColonization.md) - `SpaceColonization`, branching growth (veins, roots, trees) toward scattered attraction points (a stateful stepper)
- [`Diffusion-limited aggregation`](./DiffusionLimitedAggregation.md) - `DiffusionLimitedAggregation`, dendritic clusters frozen out of random walkers (frost and coral, a stateful stepper)
