#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → Generators</sup>

---

## Generators

- [`Random`](./Random.md) - `random`, `randomGaussian`, and the `randomVector`/`ring` scatter helpers
- [`Noise`](./Noise.md) - Perlin `noise`, `signedNoise`, and `curlNoise` flow fields
- [`Blue noise`](./BlueNoise.md) - `poissonDisk`, an even-but-organic scatter with no clumps or gaps (Poisson-disk sampling)
- [`Low-discrepancy sampling`](./LowDiscrepancy.md) - `haltonPoints` / `sobolPoints`, even coverage as an ordered stream: growing the count only adds points, never moves them
- [`Stippling`](./Stippling.md) - `stipple`, dots packed to reproduce an image's tone (weighted-Voronoi stippling), or any density function
- [`Fractals`](./Fractals.md) - `IFS` chaos games, `FractalFlame` renders, circle-inversion limit sets, and Kleinian limit-set curves, plus the `fitted` placement helper
- [`Chaotic maps & bifurcation`](./Bifurcation.md) - `IteratedMap`, the one-dimensional route to chaos: logistic, sine, tent, and Gauss families, orbits and cobweb staircases, the bifurcation diagram as dots or a density image, and Lyapunov exponents
- [`Single line`](./SingleLine.md) - `singleLine`, one continuous tour through an image's stipple (TSP art), a plotter-friendly `Contour`
- [`Spanning tree`](./SpanningTree.md) - `spanningTree`, the minimum spanning tree of an image's stipple: the branching, vein-like sibling of the single line
- [`Isolines`](./Isolines.md) - `isolines`, level curves of any scalar field or an image's tone by marching squares, from metaball outlines to contour maps
- [`Isosurfaces`](./Isosurface.md) - `isosurface` / `Metaballs`, the surface where a field over space crosses a level, marched into a `Mesh`: soft spheres that fuse, noise volumes, gyroids
- [`Hulls`](./Hulls.md) - `concaveHull` / `alphaShape`, the tighter answers to "what shape are these points?": one gulf-hugging simple polygon, or the scatter's true footprint with islands and holes
- [`Medial axis`](./MedialAxis.md) - `medialAxis`, a shape reduced to its skeleton, every point carrying its inscribed-disk radius
- [`Straight skeleton`](./StraightSkeleton.md) - `straightSkeleton`, the shrinking-boundary ridge network with faces and exact mitered insets (`inset(by:)`)
- [`Marbling`](./Marbling.md) - `Marbling` / `drawMarbling`, paper marbling in closed form: drops, tines, combs, and swirls raking vector ink outlines into feathered papers
- [`Watercolor`](./Watercolor.md) - `Watercolor` / `drawWatercolor`, watercolor pigment from recursively deformed polygons stacked as translucent layers
- [`Chladni figures`](./Chladni.md) - `chladni`, a ringing plate's standing-wave field in closed form, plus the `.chladni` generator's sand and wave readings and the mode-by-pitch audio join
- [`Terrain`](./Terrain.md) - `Heightfield`, landscapes from noise or `diamondSquare`, weathered by droplet hydraulic and thermal erosion, emitted as terrain meshes, heightmaps, and contours
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
