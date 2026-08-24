#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Patterns</sup>

---

## Patterns

Generative patterns: grids, tessellations, and rule-based repetition. (Shape *primitives* and
shape *composition* (booleans and SDF combinators) live in [Shapes](../Shapes/).)

| Example | What it shows |
|---|---|
| [Anamorphosis](Anamorphosis/Sketch.swift) | a plate that says nothing until a mirrored cylinder reads it: a word wrapped around the glass, each point of it followed from the eye through the bounce down to the page, with a panel showing what that eye receives, read back off the finished plate (`Anamorphosis`) |
| [Apollonian](Apollonian/Sketch.swift) | an Apollonian gasket: every three-way gap between kissing circles filled by the one circle that touches all three, color sweeping through the generations so the filling order shows (`apollonianGasket`) |
| [Bifurcation](Bifurcation/Sketch.swift) | the logistic map's bifurcation diagram as an ink print, with the Lyapunov exponent traced beneath: the settled orbit forks, doubles into chaos, and opens its periodic windows as the growth rate sweeps; knobs zoom the window (`IteratedMap`, `drawBifurcation`, `makeBatch`) |
| [Billiards](Billiards/Sketch.swift) | one bouncing rule in four rooms: a circle wrapping a hole it can never enter, an ellipse sorting paths by the foci, and a stadium and a posted square that both fill with scribble, with a fan of balls showing which rooms keep a fan (`Billiard`) |
| [BlueNoise](BlueNoise/Sketch.swift) | blue-noise stippling: `poissonDisk` scatters points no two closer than a radius (Bridson's dart-throwing), the even-but-organic coverage that reads as natural texture |
| [Chladni](Chladni/Sketch.swift) | a ringing square plate stepping through its Chladni figures: sand gathers along the still nodal lines while the modes morph and the whole cycle loops (`chladni`) |
| [CirclePacking](CirclePacking/Sketch.swift) | grow-to-touch circle packing, both flavors: a self-seeding gap-filling pack, and a foam grown from a blue-noise scatter (`packCircles`) |
| [CliffordAttractor](CliffordAttractor/Sketch.swift) | a Clifford map iterated into an accumulating additive density field, bright filaments where the chaotic orbit returns again and again (`ChaoticMap.clifford`, `noClear`, `blendMode(.add)`) |
| [ContourMap](ContourMap/Sketch.swift) | a topographic map of a drifting fbm terrain traced by marching squares, every fifth level heavier like a cartographer's index contour (`isolines`, `fbm`) |
| [Cracks](Cracks/Sketch.swift) | crack growth: perpendicular cracks subdividing the plane into city-block cells, each dragging a translucent one-sided grain wash across the open space beside it (`CrackGrowth`, `noClear`) |
| [Dendrite](Dendrite/Sketch.swift) | diffusion-limited aggregation: random walkers freeze where they first touch the cluster, growing frost-like dendrites from a center seed, tinted by arrival time (`DiffusionLimitedAggregation`) |
| [DifferentialGrowth](DifferentialGrowth/Sketch.swift) | a closed ring relaxed under attraction, alignment, and repulsion with long edges splitting, folding live into brain-coral meanders (`DifferentialGrowth`) |
| [Meander](Meander/Sketch.swift) | a river migrating by curvature across a parchment plain, bends sliding downstream, oxbow lakes pinching off, the recorded scars ribboned beneath the water (`Meander`) |
| [DotGrid](DotGrid/Sketch.swift) | a grid of black/white dots woven by a modulo rule |
| [ElementaryCA](ElementaryCA/Sketch.swift) | 1D cellular automata stacked as rows, elementary and 3-color totalistic, the rule and code on knobs: one number flips the picture between order, fractals, and chaos (`elementaryCA`, `totalisticCA`) |
| [EnergyGrid](EnergyGrid/Sketch.swift) | columns sized by a moving "energy" share (`translate`, `drawRect`) |
| [Flocking](Flocking/Sketch.swift) | a few hundred boids, each steering only by its neighbors (separate, align, cohere), the flock swirling and regrouping with no leader (`Boids`) |
| [ForceGraph](ForceGraph/Sketch.swift) | a growing network laying itself out live: repulsion spreads the nodes, edges pull, hubs emerge from rich-get-richer growth, and any node drags with the web reflowing around it (`ForceLayout`) |
| [FractalFlame](FractalFlame/Sketch.swift) | a random fractal flame refining live: the chaos game with nonlinear variations, structural coloring, and the log-density display, accumulated slice by slice; click to reroll (`FractalFlame`, `FractalFlame.Renderer`) |
| [Buddhabrot](Buddhabrot/Sketch.swift) | the Mandelbrot set's escaping orbits exposed as a density plate, rising out of the noise live; click to switch the false-color and grayscale plates (`Buddhabrot`, `Buddhabrot.Renderer`) |
| [Percolation](Percolation/Sketch.swift) | site percolation breathing through the critical threshold: clusters tinted by size, the spanning cluster lighting up with its traced outline (`Percolation`) |
| [Girih](Girih/Sketch.swift) | Islamic star patterns by polygons-in-contact: a honeycomb's strapwork morphing as the contact angle sweeps, under a decagon-and-pentagons girih-tile medallion at the classic 54 degrees (`girihPattern`, `Girih.Tile`) |
| [Grid](Grid/Sketch.swift) | a 16×16 `Grid` showing both element kinds: `cells` outline the frames, `points` dot each center, with `padding` and `gutter` shaping the lattice |
| [HexGrid](HexGrid/Sketch.swift) | a honeycomb pulse radiating in perfect rings of hex distance, re-centered by picking the hexagon under the mouse (`hexGrid`, `distance(from:to:)`, `cell(at:)`) |
| [InversionFractal](InversionFractal/Sketch.swift) | the limit-set lace of a tangent circle ring, resampled every frame so it shimmers; click to change the ring (`inversionLimitSet`, `inverted`) |
| [IteratedFunctions](IteratedFunctions/Sketch.swift) | the chaos game condensing the fern, the triangle, and the carpet onto the accumulation surface, a few thousand visits per frame (`IFS`, `ifsPoints`, `fitted`) |
| [Kaleidoscope](Kaleidoscope/Sketch.swift) | one drawn arm replicated into a sixteen-fold mandala by `symmetry(8, mirrored: true)`, every draw call folding through the mirrors |
| [Kleinian](Kleinian/Sketch.swift) | Kleinian limit sets as one ordered closed curve, a bright head running the whole lap each loop; click for the next preset traces (`kleinianLimitSet`, `KleinianPreset`) |
| [LevyFlight](LevyFlight/Sketch.swift) | a Lévy flight: power-law step lengths make tight scribble clusters strung together by sudden long jumps, a comet retracing the journey out and back (`levyFlight`) |
| [LifeQuilt](LifeQuilt/Sketch.swift) | a four-layer Game of Life filling cells with triangular wedges, colored by a radial cosine palette (`drawTriangle`, SDF) |
| [LowDiscrepancy](LowDiscrepancy/Sketch.swift) | random, Poisson-disk, Halton, and Sobol scatter side by side while the count breathes: the sequences stay even at every count and only ever add points, never reshuffle (`haltonPoints`, `sobolPoints`) |
| [LSystem](LSystem/Sketch.swift) | the built-in L-system presets, one per cell: tiny rewriting grammars unfolded into fractal curves and branching plants (`LSystem`, `drawLSystem`) |
| [Marbling](Marbling/Sketch.swift) | paper marbling in closed form: bull's-eye drops feathered by combs, a stylus pull, and a stirred vortex, every ink a vector outline; click drops ink, a drag pulls the stylus (`Marbling`, `drawMarbling`) |
| [Maze](Maze/Sketch.swift) | a perfect maze's walls as clean merged line-work with its longest path tracing through, re-rolls cycling the carver because the algorithm is the texture (`maze`, `longestPath`) |
| [Penrose](Penrose/Sketch.swift) | a Penrose rhombus tiling with the matching-rule arcs stroked on top, every arc meeting a neighbor's across the shared edge, light breathing outward from the five-fold sun (`penroseTiling`) |
| [Phyllotaxis](Phyllotaxis/Sketch.swift) | a sunflower seed-head: `phyllotaxis(count:spacing:)` places seeds at the golden angle marching outward by `sqrt(i)`, sized by age and drawn with one `drawCircles` batch, spinning slowly while the count breathes |
| [RidgeLines](RidgeLines/Sketch.swift) | stacked mountain ridgelines from ridged fractal noise, each row's opaque panel occluding the range behind it; the looping field brings the terrain home every lap (`ridgedFbm`) |
| [Clothoid](Clothoid/Sketch.swift) | a closed route whose every corner is an easement, an arc, and an easement back out, driven at a steady speed with the bend combed off it and a steering wheel that reads it: pull `easement` to zero and the comb becomes a square step (`Clothoid`, `clothoidCorners`) |
| [Pursuit](Pursuit/Sketch.swift) | runners on the corners of a polygon, each running at the next: the ring shrinks and turns at once, the paths are logarithmic spirals, and the caption measures the distance run against the law that predicts it (`Pursuit`) |
| [Rivers](Rivers/Sketch.swift) | the drainage of a landscape, worked out rather than drawn: water runs to the steepest neighbor, the flow through a cell is everybody upstream of it, and the network above a threshold is stroked by Strahler order over the contour map it came from (`Drainage`) |
| [Roses](Roses/Sketch.swift) | the rose-curve chart over a `Grid`: columns raise `n`, rows raise `d` in `k = n/d`, odd `n` gives `n` petals and even `2n`, fractional `k` weaves stars, reduced duplicates inked in the accent; each rose spins one petal per lap (`rose`) |
| [Schottky](Schottky/Sketch.swift) | a Schottky group's circle orbit toured around the Apollonian gasket: circles nesting inside circles forever, leaning with the trace (`schottkyCircles`) |
| [SelfAvoidingWalk](SelfAvoidingWalk/Sketch.swift) | one unbroken lattice path that never crosses itself, backtracking out of dead ends to wind long and dense, colored along its length (`selfAvoidingWalk`) |
| [ShapePacking](ShapePacking/Sketch.swift) | geometry-aware packing, a few shapes added per frame, each grown against the outlines already placed so small shapes nestle into notches, riding `noClear` accumulation (`ContinuousPacking`) |
| [Spectre](Spectre/Sketch.swift) | the einstein: a spectre patch grown by substitution, every tile one shape and one handedness, the rare odd mystics glowing as a tide drifts across (`spectreTiling`) |
| [Spirograph](Spirograph/Sketch.swift) | the toy gear set: one gear pair stacked at several pen distances into a glowing rosette, the pen sliding in and out over the loop, spinning exactly one lobe per lap (`hypotrochoid`) |
| [Subdivision](Subdivision/Sketch.swift) | recursive subdivision, the grid-painting look: unequal panels from repeated splits, a few taking primary colors under heavy rules, re-rolled every few seconds (`subdivide`) |
| [Stippling](Stippling/Sketch.swift) | weighted-Voronoi stippling: a painted, lit sphere rebuilt from 5,200 dots whose packing density follows the picture's darkness (`stipple`) |
| [Streamlines](Streamlines/Sketch.swift) | evenly-spaced streamlines through a noise flow field, each line stopping when it nears one already drawn, fanning into smooth non-crossing currents (`FlowField.streamlines`) |
| [Topography](Topography/Sketch.swift) | a breathing blob inset inward over and over until the region pinches out, each surviving ring stroked: contour lines that crowd where the form narrows; pure line work that plots straight to SVG (`Shape.offset(by:join:)`) |
| [TriangleGrid](TriangleGrid/Sketch.swift) | a shimmer over alternating up and down triangles, the two orientations reading one noise field through two palettes (`triangleGrid`) |
| [TenPrint](TenPrint/Sketch.swift) | a maze of diagonals from one coin per cell, drawn as joined runs with a color each, the plain per-cell reading on mouse hold (`tenPrint`, `runs`, `lines`) |
| [UlamSpiral](UlamSpiral/Sketch.swift) | the primes written in a square spiral, the diagonals they fall on drifting as the count starts from somewhere else, the walk itself on mouse hold (`ulamSpiral`, `primePoints`, `path`) |
| [Truchet](Truchet/Sketch.swift) | one tile per grid cell at a seed-chosen spin: quarter-arcs meet across borders into meandering loops while a flow field sweeps hue along them (`truchet`) |
| [Turmites](Turmites/Sketch.swift) | tiny Turing machines painting a wrapped grid: Langton's ant and its highway, spiral builders, chaotic weavers, all on a preset knob (`Turmite`) |
| [Venation](Venation/Sketch.swift) | space colonization: veins grow live from a bottom root toward a blue-noise attractor scatter, branch weight from the pipe model (`SpaceColonization`, `poissonDisk`) |
| [Voronoi](Voronoi/Sketch.swift) | a field of noise-drifting sites partitioned into Voronoi cells, evened out with Lloyd relaxation and colored by a sweeping focal point; the cursor is a live site, so the cells crystallize around the mouse (`voronoi`/`lloyd`) |
| [TextureSynthesis](TextureSynthesis/Sketch.swift) | Wave Function Collapse's overlapping model: a small picture authored in the source teaches its own square patches, and a much larger texture is built so every overlap agrees (`OverlappingWFC`, `wfc(from:)`) |
| [WangTiles](WangTiles/Sketch.swift) | Wang tiles: edge colors that must agree turn independent seeded picks into one connected quilt, re-laid every few seconds, drawn as the classic edge triangles (`wangTiling`, `drawWangTiling`) |
| [WarpGrid](WarpGrid/Sketch.swift) | a checkerboard of rects warped under the mouse (`drawRect`) |
| [WaveFunctionCollapse](WaveFunctionCollapse/Sketch.swift) | a pipe network solved by Wave Function Collapse: min-entropy observation, weighted collapse, and constraint propagation over edge sockets until every neighbor connects legally (`wfc`, `drawWFC`) |

Run one with `swift run Example-Patterns-<Name>`, e.g. `swift run Example-Patterns-DotGrid`.
