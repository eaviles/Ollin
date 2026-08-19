#### <sup>[Ollin](../README.md) → [Guide](README.md) → Appendix D</sup>

---

# D. The complete toolbox

Everything Ollin can do, one line each. The guide teaches by building pieces, so some capabilities get a whole chapter and others get a sentence. This appendix is the guarantee that nothing shipped goes unmentioned. Each row says what a capability is in plain words. It also says where the guide works with it, and where its full reference lives in [`Docs/`](../Docs/README.md).

Use it two ways. It is an index for the moment you remember the guide showing blur somewhere and want it again. It is also a map of what you haven't tried yet. If something you want isn't in these tables, it isn't in the framework yet. The [roadmap](../ROADMAP.md) is the list of what's ahead.

**Contents:** [The sketch and its window](#the-sketch-and-its-window) · [Drawing](#drawing) · [Color](#color) · [Text and images](#text-and-images) · [Geometry you can hold](#geometry-you-can-hold) · [Motion, math, and randomness](#motion-math-and-randomness) · [Generative systems](#generative-systems) · [Physics and simulation](#physics-and-simulation) · [Layers and effects](#layers-and-effects) · [Shaders and compute](#shaders-and-compute) · [3D](#3d) · [Sculpting with fields](#sculpting-with-fields) · [Depth and the phone](#depth-and-the-phone) · [Sound and control](#sound-and-control) · [Seeing and video](#seeing-and-video) · [Sharing and performing](#sharing-and-performing)

## The sketch and its window

| Capability | What it is | Guide | Reference |
|---|---|---|---|
| The sketch lifecycle | `setup()` once, `draw()` every frame, at the display's rate | [Ch 1](01-HelloOllin.md) | [Sketch](../Docs/Core/Sketch.md) |
| The clock | `time`, `deltaTime`, `frameCount`, `frameRate`; `noLoop()` for stills | [Ch 1](01-HelloOllin.md), [Ch 3](03-MotionAndTime.md) | [Sketch](../Docs/Core/Sketch.md) |
| Canvas and window | `canvasSize` presets, `windowMode` (auto, fixed, resizable) | [Ch 1](01-HelloOllin.md) | [Canvas](../Docs/Core/Canvas.md) |
| Normalized coordinates | `uv(u, v)`: the canvas point at 0…1 fractions, layout without `width`/`height` | [Ch 1](01-HelloOllin.md) | [Canvas](../Docs/Core/Canvas.md#uv) |
| Variations | `variation`: the seed a run grew from, stepped and rolled from the inspector's Variation card | [Ch 4](04-Randomness.md) | [Variations](../Docs/Core/Variations.md) |
| Mouse | `mouseX`/`mouseY`, pressed state, press and release hooks | [Ch 1](01-HelloOllin.md) | [Input](../Docs/Helpers/Input.md) |
| Keyboard | `key`, typed `KeyCode`, `isKeyDown(_:)`, press and release hooks | [Ch 1](01-HelloOllin.md) | [Input](../Docs/Helpers/Input.md) |
| `@Param` knobs | Properties as live inspector controls, typed per value (slider, color well, pad, …) | [Ch 1](01-HelloOllin.md), [Ch 21](21-SoundAndControl.md) | [Parameters](../Docs/Helpers/Parameters.md) |
| Live reload | `swift run OllinLive Sketch.swift`: save the file, the window swaps the change in | [Ch 1](01-HelloOllin.md) | [Sketch](../Docs/Core/Sketch.md) |
| Single-file sketches | `ollin new` and `ollin <file>.swift`: one loose file is a whole sketch, runnable from anywhere | [Ch 1](01-HelloOllin.md) | [SingleFile](../Docs/Tools/SingleFile.md) |
| Project generator | `ollin new <Name>` and `ollin generate`: a ready-to-run folder from a template you can watch running first | [Ch 1](01-HelloOllin.md) | [ProjectGenerator](../Docs/Tools/ProjectGenerator.md) |
| Bringing a shader over | `ollin new --from-shader`: a GLSL fragment shader translated into Metal, with a project written around it | [Ch 16](16-YourFirstShader.md) | [ShaderImport](../Docs/Tools/ShaderImport.md) |
| Bringing a scene over | `ollin new --from-scene`: a glTF or USD scene written out as the camera, light and placement calls that draw it | [Ch 18](18-3DGently.md) | [SceneImport](../Docs/Tools/SceneImport.md) |
| The examples gallery | `swift run OllinExamples`: every example browsable in a tree, running, with its knobs beside it | [Ch 1](01-HelloOllin.md) | [`Examples/`](../Examples/README.md) |
| Swift itself | The language at sketch speed | [Appendix A](A-JustEnoughSwift.md) | [Swift quick reference](../Docs/Swift.md) |

## Drawing

| Capability | What it is | Guide | Reference |
|---|---|---|---|
| The shape catalog | Circles, rects, lines, arcs, stars, rings, hearts, n-gons, and a few dozen more | [Ch 1](01-HelloOllin.md) | [Drawing](../Docs/Drawing/Drawing.md) |
| Ink state | `fill`, `stroke`, `strokeWeight`, caps and joins, `hollow` band mode, stroke alignment | [Ch 1](01-HelloOllin.md) | [Drawing](../Docs/Drawing/Drawing.md) |
| Transforms and the state stack | `translate`/`rotate`/`scale`, scoped with `withState { }` | [Ch 6](06-GridsAndRepetition.md) | [Drawing](../Docs/Drawing/Drawing.md) |
| Kaleidoscope symmetry | `symmetry(n, mirrored:)`: every draw call folds around a center; one wedge becomes a mandala | [Ch 6](06-GridsAndRepetition.md) | [Drawing](../Docs/Drawing/Drawing.md#symmetry) |
| Clipping | `withClip(shape) { }`: drawing inside the block lands only within the region; nesting intersects | [Ch 6](06-GridsAndRepetition.md) | [Drawing](../Docs/Drawing/Drawing.md#clip) |
| Blend modes | Add, subtract, multiply, screen, lightest, darkest, as drawing state | [Ch 15](15-LayersAndEffects.md) | [Drawing](../Docs/Drawing/Drawing.md) |
| Accumulation | `noClear()`: a persistent canvas that piles up across frames | [Ch 15](15-LayersAndEffects.md), [Ch 17](17-Simulations.md) | [Accumulation](../Docs/Drawing/Accumulation.md) |
| Stroke dynamics | `StrokeMark`/`drawMark`: width and opacity driven by how fast and how hard a mark is being made, rather than where you are along it; `pressure` reads a Force Touch trackpad or tablet | [Ch 14](14-ShapesAsMaterial.md) | [Marks](../Docs/Drawing/Marks.md) |
| Retained batches | `makeBatch { }` records heavy static drawing once into a `Batch`; `drawBatch` replays it each frame for (almost) nothing, placed or stamped by the transform in force | [Ch 14](14-ShapesAsMaterial.md) | [Retained batches](../Docs/Drawing/Batches.md) |
| HDR and tone mapping | Light past full brightness, brought back by `toneMap` (clamp, Reinhard, ACES) | [Ch 15](15-LayersAndEffects.md) | [HDR](../Docs/Drawing/HDR.md) |
| Wide gamut and HDR output | `colorOutput`: Display P3 on screen, highlights brighter than white, HDR10 video; `Color(displayP3:)` for colors outside sRGB | [Ch 15](15-LayersAndEffects.md) | [Wide gamut & HDR output](../Docs/Drawing/ColorOutput.md) |
| Gradient paint | Linear, radial, and along-path gradients on any shape's fill or stroke | [Ch 2](02-Color.md) | [Color](../Docs/Drawing/Color.md) |

## Color

| Capability | What it is | Guide | Reference |
|---|---|---|---|
| Color values | Named colors, hex, RGB, HSB, alpha, blackbody `Color(kelvin:)` | [Ch 2](02-Color.md) | [Color](../Docs/Drawing/Color.md) |
| Perceptual color | The OKLab family and `Color.mix` that trusts your eye | [Ch 2](02-Color.md) | [Color](../Docs/Drawing/Color.md) |
| Palettes and ramps | ColorBrewer sets, harmony builders, smooth ramps, cosine palettes | [Ch 2](02-Color.md) | [Color](../Docs/Drawing/Color.md) |
| Colormaps | Viridis, magma, turbo: perceptually even data-to-color ramps | [Ch 2](02-Color.md) | [Color](../Docs/Drawing/Color.md) |

## Text and images

| Capability | What it is | Guide | Reference |
|---|---|---|---|
| Drawing text | `drawText` with size, alignment, metrics, wrapping, and on-path layout | [Ch 8](08-WordsAndPictures.md) | [Text](../Docs/Drawing/Text.md) |
| Three font kinds | Outline (any installed font), bitmap, and plotter stroke fonts | [Ch 8](08-WordsAndPictures.md) | [Text](../Docs/Drawing/Text.md) |
| Text as geometry | `textToShapes`: letters become `Shape`s you can warp, resample, and rebuild | [Ch 8](08-WordsAndPictures.md) | [Text](../Docs/Drawing/Text.md) |
| Atlas text | `textMode(.atlas)` for fast, crisp text when there's a lot of it | [Ch 8](08-WordsAndPictures.md) | [Text](../Docs/Drawing/Text.md) |
| Images | Load PNG/JPEG/HEIC and friends, draw, tint, and scale them | [Ch 8](08-WordsAndPictures.md) | [Images](../Docs/Drawing/Images.md) |
| Pixels | Read and write any pixel with `image[x, y]`; build images from scratch | [Ch 8](08-WordsAndPictures.md) | [Images](../Docs/Drawing/Images.md) |
| Glyph mosaic | A picture rebuilt as a grid of characters, each chosen by its measured ink in the active font | [Ch 8](08-WordsAndPictures.md) | [GlyphMosaic](../Docs/Drawing/GlyphMosaic.md) |
| Pixel sorting | Brightness-bounded runs of a picture's own pixels reordered into streaks, the classic glitch melt | [Ch 8](08-WordsAndPictures.md) | [PixelSorting](../Docs/Drawing/PixelSorting.md) |
| Halftone | A picture as the classic print dot screen: area-exact dots on a rotated grid, real circles for the plotter | [Ch 8](08-WordsAndPictures.md) | [Halftone](../Docs/Drawing/Halftone.md) |
| Tables and JSON | `loadTable` reads a CSV or TSV with typed reads by column name; `loadJSON` reads a document by name and index | [Ch 8](08-WordsAndPictures.md) | [Data](../Docs/Helpers/Data.md) |
| Luminance melt | A picture liquified by a warped noise field and poured through a palette, the `.melt` filter | [Ch 15](15-LayersAndEffects.md) | [Effects](../Docs/Drawing/Effects.md) |

## Geometry you can hold

| Capability | What it is | Guide | Reference |
|---|---|---|---|
| Vectors | `Vector2`/`Vector3` with real operators, length, normalize, lerp, rotate | [Ch 9](09-Vectors.md), [Ch 18](18-3DGently.md) | [Geometry](../Docs/Drawing/Geometry.md) |
| Rectangles and circles | Typed regions with fitting, insetting, and hit testing | [Ch 9](09-Vectors.md) | [Geometry](../Docs/Drawing/Geometry.md) |
| `Grid` | Rows, columns, padding, and gutters without nested-loop boilerplate | [Ch 6](06-GridsAndRepetition.md) | [Geometry](../Docs/Drawing/Geometry.md) |
| Paths, shapes, and contours | Curved outlines you build, hold, edit, and respace with `resampled` | [Ch 14](14-ShapesAsMaterial.md) | [Geometry](../Docs/Drawing/Geometry.md) |
| Shape booleans and offsets | Union, intersect, subtract, xor; grow and shrink regions | [Ch 14](14-ShapesAsMaterial.md) | [Geometry](../Docs/Drawing/Geometry.md) |
| Stroke as shape | Turn any stroked line into a filled region for booleans and plotting | [Ch 14](14-ShapesAsMaterial.md) | [Geometry](../Docs/Drawing/Geometry.md) |
| SVG import | Vector artwork read into shapes: draw it as authored, or mine it as geometry | [Ch 14](14-ShapesAsMaterial.md) | [SVG](../Docs/Drawing/SVG.md) |
| Fourier epicycles | Rebuild any closed outline as a chain of spinning circles, term count as the detail dial | [Ch 14](14-ShapesAsMaterial.md) | [Epicycles](../Docs/Drawing/Epicycles.md) |
| Classic curves | Phyllotaxis, Lissajous figures, roses, superellipses, supershapes, the spirograph gears, guilloche rosettes, the harmonograph, and Chaikin corner-cut smoothing, all closed forms with no randomness | [Ch 14](14-ShapesAsMaterial.md) | [Classic curves](../Docs/Drawing/Curves.md) |
| Shape morphing | Tween one shape into another; holes grow in and out, and every in-between is real geometry | [Ch 14](14-ShapesAsMaterial.md) | [Morphing](../Docs/Drawing/Morphing.md) |
| Paper marbling | Ink floated on a bath and raked: drops, tines, combs, and vortices, all exact transforms of vector outlines | [Ch 14](14-ShapesAsMaterial.md) | [Marbling](../Docs/Generators/Marbling.md) |
| Watercolor | Pigment from one polygon deformed and stacked at low opacity: dense cores, uneven blooming edges | [Ch 14](14-ShapesAsMaterial.md) | [Watercolor](../Docs/Generators/Watercolor.md) |
| Convex hull | The rubber band around a point set | [Ch 14](14-ShapesAsMaterial.md) | [Geometry](../Docs/Drawing/Geometry.md) |
| Voronoi and Delaunay | Territories and neighbor networks from points, with Lloyd relaxation | [Ch 14](14-ShapesAsMaterial.md) | [Voronoi](../Docs/Drawing/Voronoi.md) |

## Motion, math, and randomness

| Capability | What it is | Guide | Reference |
|---|---|---|---|
| Everyday math | `map`, `lerp`, `dist`, `clamp`, `fract`, `step`, `smoothstep`, `.tau` | [Ch 3](03-MotionAndTime.md) | [Math](../Docs/Helpers/Math.md) |
| Loop phases | `loopProgress` and `pingPong`: the sketch clock as a 0…1 cycle | [Ch 3](03-MotionAndTime.md) | [Math](../Docs/Helpers/Math.md) |
| Easing | The curve catalog, plus `@Eased` values that glide to what you assign | [Ch 3](03-MotionAndTime.md) | [Animation](../Docs/Helpers/Animation.md) |
| Smoothing | `@Smoothed` calms jittery inputs (mouse, sensors, knobs) as they arrive | [Ch 3](03-MotionAndTime.md) | [Animation](../Docs/Helpers/Animation.md) |
| `Timeline` | Keyframes with per-segment easing, for choreographed sequences | [Ch 3](03-MotionAndTime.md) | [Animation](../Docs/Helpers/Animation.md) |
| Random | Seeded `random`, Gaussian, choices (plain and weighted), shuffles | [Ch 4](04-Randomness.md) | [Random](../Docs/Generators/Random.md) |
| Noise | `noise`, `signedNoise`, seamless `loop:` variants, layered `fbm`, `curlNoise` | [Ch 5](05-Noise.md), [Ch 13](13-FieldsAndFlow.md) | [Noise](../Docs/Generators/Noise.md) |
| The noise family | `simplexNoise`, cellular `worley` (nearest / second / border readings), `ridgedFbm`, `turbulence`, `warpedFbm`, all seeded together | [Ch 5](05-Noise.md) | [Noise](../Docs/Generators/Noise.md) |

## Generative systems

| Capability | What it is | Guide | Reference |
|---|---|---|---|
| Blue noise | Poisson-disk scatter: random but even | [Ch 14](14-ShapesAsMaterial.md) | [BlueNoise](../Docs/Generators/BlueNoise.md) |
| Low-discrepancy sampling | Halton and Sobol point streams: even at every count, growing the count never moves a point | [Ch 14](14-ShapesAsMaterial.md) | [LowDiscrepancy](../Docs/Generators/LowDiscrepancy.md) |
| Stippling | Dots packed to reproduce an image's tone (weighted-Voronoi) | [Ch 8](08-WordsAndPictures.md) | [Stippling](../Docs/Generators/Stippling.md) |
| Single-line drawing | One unbroken tour through a stipple: the picture as a single closed line (TSP art) | [Ch 8](08-WordsAndPictures.md) | [SingleLine](../Docs/Generators/SingleLine.md) |
| Spanning-tree drawing | The same stipple joined by the minimum spanning tree: the picture as branching veins | [Ch 8](08-WordsAndPictures.md) | [SpanningTree](../Docs/Generators/SpanningTree.md) |
| String art | One continuous thread over rim pins, each chord wound toward the darkness that remains | [Ch 8](08-WordsAndPictures.md) | [StringArt](../Docs/Generators/StringArt.md) |
| Percolation | A grid of coin flips whose clusters snap into one span at the critical probability | [Ch 4](04-Randomness.md) | [Percolation](../Docs/Generators/Percolation.md) |
| Isolines | Level curves of any field or an image's tone (marching squares): metaball outlines, contour maps | [Ch 13](13-FieldsAndFlow.md) | [Isolines](../Docs/Generators/Isolines.md) |
| Isosurfaces and metaballs | The surface where a field over space crosses a level, marched into a `Mesh` (marching cubes): soft spheres that fuse, noise volumes, gyroids | [Ch 19](19-SculptingWithFields.md) | [Isosurfaces](../Docs/Generators/Isosurface.md) |
| Subdivision surfaces | `mesh.subdivided`: a low-poly control cage refined into a smooth solid (Catmull-Clark or Loop), welding and open edges handled for you | [Ch 18](18-3DGently.md) | [Subdivision surfaces](../Docs/Generators/SubdivisionSurfaces.md) |
| Mesh growth | `MeshGrowth`: a surface that grows more area than it has room for and folds, driven evenly, by curvature, by your own field, or by a reaction-diffusion pattern in the surface | [Ch 18](18-3DGently.md) | [Mesh growth](../Docs/Generators/MeshGrowth.md) |
| Surface reconstruction | `reconstructSurface` / `particleSurface`: a scanned or generated point cloud back to a `Mesh`, data holes kept honest; particle sets skinned as one blended body | [Ch 20](20-DepthAndThePhone.md) | [Surface reconstruction](../Docs/Generators/SurfaceReconstruction.md) |
| Hulls | The tighter wraps around a scatter: the concave hull (one gulf-hugging simple polygon) and the alpha shape (islands and holes) | [Ch 14](14-ShapesAsMaterial.md) | [Hulls](../Docs/Generators/Hulls.md) |
| Medial axis | A shape reduced to its skeleton, every point carrying its inscribed-disk radius | [Ch 14](14-ShapesAsMaterial.md) | [MedialAxis](../Docs/Generators/MedialAxis.md) |
| Straight skeleton | The shrinking-boundary ridge network, with exact mitered insets cut from one build | [Ch 14](14-ShapesAsMaterial.md) | [StraightSkeleton](../Docs/Generators/StraightSkeleton.md) |
| Random walks | The walk family: the local tangle, the Lévy cluster-and-leap, the self-avoiding single stroke | [Ch 4](04-Randomness.md) | [Walks](../Docs/Generators/Walks.md) |
| Circle packing | Grow-to-touch packings, seeded and reproducible | [Ch 14](14-ShapesAsMaterial.md) | [Packing](../Docs/Generators/Packing.md) |
| Shape packing | Packing measured against real outlines, so small shapes settle into a star's notches; one-shot or filled in over time | [Ch 14](14-ShapesAsMaterial.md) | [ShapePacking](../Docs/Generators/ShapePacking.md) |
| Truchet tiles | One tile per cell at random spins; loops and mazes emerge | [Ch 7](07-Tiles.md) | [Truchet](../Docs/Drawing/Truchet.md) |
| Hitomezashi stitching | One bit per grid line phases its dashes; stitches and a two-tone cloth emerge | [Ch 7](07-Tiles.md) | [Hitomezashi](../Docs/Drawing/Hitomezashi.md) |
| Hex and triangle grids | The other regular tilings, with hex distance, neighbors, and exact picking | [Ch 6](06-GridsAndRepetition.md) | [Tiling](../Docs/Drawing/Tiling.md) |
| Recursive subdivision | Uneven panels by aspect-aware splitting, binary or quadtree | [Ch 6](06-GridsAndRepetition.md) | [Tiling](../Docs/Drawing/Tiling.md) |
| Mazes | Perfect labyrinths (three carving textures), walls as clean line-work | [Ch 6](06-GridsAndRepetition.md) | [Tiling](../Docs/Drawing/Tiling.md) |
| Apollonian gasket | A circle filled with an endless foam of kissing circles | [Ch 6](06-GridsAndRepetition.md) | [Tiling](../Docs/Drawing/Tiling.md) |
| Aperiodic tilings | Penrose kites/darts and rhombs with matching-rule arcs, Wang edge-matching quilts, girih star patterns over any polygons, and the spectre (the einstein) | [Ch 7](07-Tiles.md) | [Aperiodic tilings](../Docs/Drawing/AperiodicTilings.md) |
| Hyperbolic tiling | Any {p,q} tessellation of the Poincaré disk, with a parity checkerboard, depth rings, and a panning viewpoint | [Ch 7](07-Tiles.md) | [Hyperbolic tiling](../Docs/Drawing/HyperbolicTiling.md) |
| Fractals | IFS chaos games, fractal flames, the Buddhabrot density plate, circle-inversion lace, and Kleinian limit-set curves | [Ch 12](12-GrowingThings.md) | [Fractals](../Docs/Generators/Fractals.md) |
| L-systems | Grammar rewriting walked by a turtle: ferns, trees, lichens | [Ch 12](12-GrowingThings.md) | [LSystem](../Docs/Generators/LSystem.md) |
| Wave Function Collapse | Socketed tiles solved by constraint propagation | [Ch 12](12-GrowingThings.md) | [WaveFunctionCollapse](../Docs/Generators/WaveFunctionCollapse.md) |
| Flow fields | Direction fields, streamlines (free and evenly spaced), advection | [Ch 13](13-FieldsAndFlow.md) | [FlowField](../Docs/Generators/FlowField.md) |
| Flocking | Boids from separation, alignment, and cohesion, with field joins | [Ch 11](11-FlocksAndSwarms.md) | [Boids](../Docs/Generators/Boids.md) |
| Steering vehicles | Seek, flee, arrive, pursue, wander, follow, contain: composable forces | [Ch 11](11-FlocksAndSwarms.md) | [Steering](../Docs/Generators/Steering.md) |
| Differential growth | A line that folds into coral as it grows | [Ch 11](11-FlocksAndSwarms.md) | [DifferentialGrowth](../Docs/Generators/DifferentialGrowth.md) |
| Space colonization | Branching growth toward attraction points: veins and venation | [Ch 12](12-GrowingThings.md) | [SpaceColonization](../Docs/Generators/SpaceColonization.md) |
| Diffusion-limited aggregation | Walkers that freeze on contact into dendrites and frost | [Ch 12](12-GrowingThings.md) | [DiffusionLimitedAggregation](../Docs/Generators/DiffusionLimitedAggregation.md) |
| Dielectric breakdown | Lightning grown where the solved field is strongest, eta picking bush or bolt | [Ch 12](12-GrowingThings.md) | [DielectricBreakdown](../Docs/Generators/DielectricBreakdown.md) |
| Crack growth | Perpendicular cracks subdividing the plane into city blocks, with a watercolor wash | [Ch 12](12-GrowingThings.md) | [CrackGrowth](../Docs/Generators/CrackGrowth.md) |
| Meander | A river migrating by curvature, cutting off oxbow lakes and leaving scars | [Ch 12](12-GrowingThings.md) | [Meander](../Docs/Generators/Meander.md) |
| Strange attractors | Lorenz, Clifford, de Jong, and friends, as orbits you draw | [Ch 13](13-FieldsAndFlow.md) | [Attractors](../Docs/Drawing/Attractors.md) |
| Chaotic maps & bifurcation | The logistic route to chaos: bifurcation diagrams, cobweb staircases, Lyapunov exponents | [Ch 13](13-FieldsAndFlow.md) | [Bifurcation](../Docs/Generators/Bifurcation.md) |
| Cellular automata | `elementaryCA` / `totalisticCA` rules and `Turmite` ants: tiny rules, long runs | [Ch 17](17-Simulations.md) | [Cellular automata](../Docs/Generators/CellularAutomata.md) |
| Lenia | `.lenia`: the continuous Game of Life, smooth mass that grows colonies and creatures | [Ch 17](17-Simulations.md) | [Effects](../Docs/Drawing/Effects.md#simfield) |

## Physics and simulation

| Capability | What it is | Guide | Reference |
|---|---|---|---|
| Soft physics | Verlet particles and springs: cloth, blobs, ropes, with disk collisions | [Ch 10](10-ForcesAndPhysics.md) | [Physics](../Docs/Simulation/Physics.md) |
| Rigid physics | Bodies, colliders, and joints in the same `World`: stacks, chains, machines | [Ch 10](10-ForcesAndPhysics.md) | [Physics](../Docs/Simulation/Physics.md) |
| Grabbing | `grab`: pick up any rigid body with the mouse | [Ch 10](10-ForcesAndPhysics.md) | [Physics](../Docs/Simulation/Physics.md) |
| 3D physics | `World3D`: rigid bodies that stack, tumble, and swing inside the 3D scene, with joints and camera grabbing | [Ch 18](18-3DGently.md) | [Physics3D](../Docs/Simulation/Physics3D.md) |
| Inverse kinematics | `IKChain`: a segmented limb that reaches for a target, or a rope dragged by its tip | [Ch 10](10-ForcesAndPhysics.md) | [Motion](../Docs/Simulation/Motion.md) |
| Double pendulum | `DoublePendulum`: the classic chaos machine, deterministic and wildly sensitive | [Ch 10](10-ForcesAndPhysics.md) | [Motion](../Docs/Simulation/Motion.md) |
| Gravity at scale | `NBody`: thousands of bodies pulling on each other, with seeded disk and cluster scenes | [Ch 10](10-ForcesAndPhysics.md) | [Motion](../Docs/Simulation/Motion.md) |
| Force-directed layout | `ForceLayout`: a graph untangling itself into an even web you can grow, pin, and drag | [Ch 10](10-ForcesAndPhysics.md) | [ForceLayout](../Docs/Generators/ForceLayout.md) |
| Artificial life | `ParticleLife`, `PPS`, `Physarum`, `ParticleLenia`, `SwarmChemistry` on the public `SpatialHash` neighbor search | [Ch 17](17-Simulations.md) | [Artificial life](../Docs/Simulation/ArtificialLife.md) |
| Ant colony | A pheromone-trail colony condensing a web of possibilities onto a short tour | [Ch 17](17-Simulations.md) | [AntColony](../Docs/Generators/AntColony.md) |
| Steering at scale | `Swarm`: separation, alignment, cohesion, seek, flee, arrive, wander, and flow as weights over tens of thousands of agents | [Ch 17](17-Simulations.md) | [Swarm](../Docs/Simulation/Swarm.md) |
| Evolution | `Evolution`: GPU populations bred toward a target past obstacles by tournament selection; `Population` + `Genome`: a handful of genomes bred from the ones you pick by eye | [Ch 17](17-Simulations.md) | [Evolution](../Docs/Simulation/Evolution.md) |
| Particle fluids | `ParticleFluid`: SPH liquid with a free surface, splashes, and grabbing | [Ch 17](17-Simulations.md) | [Fluids](../Docs/Simulation/Fluids.md) |
| Soft bodies | `SoftBodies`: shape-matched jellies that squash and pile | [Ch 17](17-Simulations.md) | [Fluids](../Docs/Simulation/Fluids.md) |

## Layers and effects

| Capability | What it is | Guide | Reference |
|---|---|---|---|
| Render targets | Off-screen layers: draw into them with `withTarget`, composite back | [Ch 15](15-LayersAndEffects.md) | [Effects](../Docs/Drawing/Effects.md) |
| The filter catalog | ~55 GPU filters: blurs, glows, color, stylize, retro, distortion, design | [Ch 15](15-LayersAndEffects.md) | [Effects](../Docs/Drawing/Effects.md) |
| Generator fills | Procedural patterns into a layer: checkers, gradients, noise, cellular | [Ch 15](15-LayersAndEffects.md) | [Effects](../Docs/Drawing/Effects.md) |
| Design patterns | Composed graphic sources: mesh gradients, god rays, spirals, orbiting dots, grain gradients, pulsing borders | [Ch 15](15-LayersAndEffects.md) | [Effects](../Docs/Drawing/Effects.md) |
| Design filters | Fluted glass, water, and paper that transform a picture; liquid metal, heatmap, and gem smoke that read a shape's silhouette | [Ch 15](15-LayersAndEffects.md) | [Effects](../Docs/Drawing/Effects.md) |
| Pattern fields | Closed-form animated fields: quasicrystal, moire, gyroid, phyllotaxis, hex pulse, Chladni | [Ch 16](16-YourFirstShader.md) | [Effects](../Docs/Drawing/Effects.md) |
| Escape-time fractals | The Mandelbrot set and Julia sets, colored by how fast each point escapes, zoomable; orbit traps color by the closest pass to a shape instead | [Ch 17](17-Simulations.md) | [Effects](../Docs/Drawing/Effects.md) |
| The compose DSL | `compose { layer { } … }`: a stack of layers, filters, and blends in one block | [Ch 15](15-LayersAndEffects.md) | [Effects](../Docs/Drawing/Effects.md) |
| Combines | Two-layer ops: mask, displace, mix, depth-of-field, SSAO, reflections | [Ch 15](15-LayersAndEffects.md), [Ch 18](18-3DGently.md) | [Effects](../Docs/Drawing/Effects.md) |
| Feedback | A layer that remembers last frame: trails, tunnels, video feedback | [Ch 15](15-LayersAndEffects.md) | [Effects](../Docs/Drawing/Effects.md) |
| Simulation fields | Game of Life, Gray-Scott reaction-diffusion, Lenia, the ripple pool, and real-time fluid, all seeded by drawing into them | [Ch 17](17-Simulations.md) | [Effects](../Docs/Drawing/Effects.md) |
| Ripple pool | `.ripples`: the wave equation as an interactive water surface; drawn marks add height, rings spread and reflect | [Ch 17](17-Simulations.md) | [Effects](../Docs/Drawing/Effects.md#simfield) |
| Watercolor wash | `watercolor(pigments:)`: wet paint on rough paper, with real pigment behavior, darkened edges, backruns, dry-brush, and optical glazing | [Ch 17](17-Simulations.md) | [Watercolor](../Docs/Simulation/Watercolor.md) |
| Chladni figures | The standing-wave patterns of a driven plate in closed form, as a field, a generator, or nodal contours | [Ch 17](17-Simulations.md) | [Chladni](../Docs/Generators/Chladni.md) |

## Shaders and compute

| Capability | What it is | Guide | Reference |
|---|---|---|---|
| User shaders | Write `shade(uv, info)`; run it as a generator, filter, or two-input combine | [Ch 16](16-YourFirstShader.md) | [Shaders](../Docs/Shaders/Shaders.md) |
| The shader library | Hashing, noise, SDFs, palettes, OKLab, spliced into every shader and kernel | [Ch 16](16-YourFirstShader.md) | [ShaderLibrary](../Docs/Shaders/ShaderLibrary.md) |
| Visual chains | Fluent per-pixel composition: oscillators, warps, blends, modulation, one pass | [Ch 16](16-YourFirstShader.md) | [Visuals](../Docs/Shaders/Visuals.md) |
| Compute kernels | Your own GPU code over buffers and textures, hot-reloadable | [Ch 17](17-Simulations.md) | [Compute](../Docs/Shaders/Compute.md) |
| GPU particles | A million particles updated and drawn without touching the CPU | [Ch 17](17-Simulations.md) | [Compute](../Docs/Shaders/Compute.md) |
| GPU simulations | Ping-pong texture simulations drawn as images | [Ch 17](17-Simulations.md) | [Compute](../Docs/Shaders/Compute.md) |

## 3D

| Capability | What it is | Guide | Reference |
|---|---|---|---|
| The camera | `camera()`, `perspective`, `ortho`; 2D sketches never pay for it | [Ch 18](18-3DGently.md) | [3D](../Docs/3D/3D.md) |
| Solid primitives | Box, sphere, torus, knots, Platonic solids, lathes, extrusions, and more | [Ch 18](18-3DGently.md) | [3D](../Docs/3D/3D.md) |
| Terrain | `Heightfield`: landscapes grown from noise or diamond-square, weathered by simulated rain and gravity, read out as a mesh, an image, or samples | [Ch 18](18-3DGently.md) | [Terrain](../Docs/Generators/Terrain.md) |
| Meshes from file | OBJ, glTF, USDZ, STL, PLY, with materials and textures; `normalized(scale:)` recenters and fits whatever arrives | [Ch 18](18-3DGently.md) | [3D](../Docs/3D/3D.md) |
| Scenes from file | `loadScene` keeps a glTF's structure: named nodes drawn in place with `drawScene`, the authored camera and lights as ready values, one node reached by name to animate | [Ch 18](18-3DGently.md) | [Scenes](../Docs/3D/Scenes.md) |
| Lights | Directional, point, spot, ambient, glowing panels, disks, and tubes, plus curated lighting presets | [Ch 18](18-3DGently.md) | [3D](../Docs/3D/3D.md) |
| Light shaping | A real fixture's measured throw on a light (IES files), and an image projected through a spot (a cookie, the stage gobo) | [Ch 18](18-3DGently.md) | [3D](../Docs/3D/3D.md#light-shaping-ies-profiles-and-cookies) |
| Atmosphere | Fog that fades surfaces with distance and pools low with a height falloff, aerial perspective that veils far geometry blue toward the sky's own sun, and volumetric light that turns spot cones, cookies, and cast shadows into visible beams and shafts | [Ch 18](18-3DGently.md) | [Atmosphere](../Docs/3D/Atmosphere.md) |
| Caustics | The light glass and polished metal focus, photon-traced: a lens's bright spot inside its own shadow, a chrome ring's folded fan, prism rainbows via dispersion | [Ch 19](19-SculptingWithFields.md) | [Caustics](../Docs/3D/Caustics.md) |
| Materials | Stylized finishes (toon, iridescent, velvet, sparkle), and physically based metal and gloss from just metalness and roughness | [Ch 18](18-3DGently.md), [Ch 19](19-SculptingWithFields.md) | [3D](../Docs/3D/3D.md) |
| Matcaps | Shading read from a picture of a lit sphere: chrome, clay, car paint, in one call and no lights | [Ch 18](18-3DGently.md) | [3D](../Docs/3D/3D.md#matcap-materials) |
| Environments | HDRI image-based lighting (eight bundled, twelve downloading) plus a zero-asset procedural sky; the surroundings become the light | [Ch 19](19-SculptingWithFields.md) | [3D](../Docs/3D/3D.md#environment-lighting) |
| Shadows | Contact-hardening cast shadows with a softness dial, ray-traced for point lights on capable GPUs | [Ch 18](18-3DGently.md) | [3D](../Docs/3D/3D.md#shadows) |
| Ray-traced reflections | Metals that reflect the actual scene, off-screen parts included | [Ch 19](19-SculptingWithFields.md) | [3D](../Docs/3D/3D.md) |
| Wireframe and textures | Any mesh as its triangle edges (which do not light); any mesh wrapped in an image through its UVs, or with no UVs at all through a triplanar projection | [Ch 18](18-3DGently.md) | [3D](../Docs/3D/3D.md#textures) |
| Point clouds | Instanced splats by the hundred thousand, camera-facing | [Ch 20](20-DepthAndThePhone.md) | [3D](../Docs/3D/3D.md) |
| Camera control and moves | Viewer orbiting, cinematic `CameraMove`s, the self-driving showcase, snap views | [Ch 18](18-3DGently.md) | [Camera](../Docs/3D/Camera.md) |
| Scene chrome | The axis widget and ground grid, live-only, never exported | [Ch 18](18-3DGently.md) | [Camera](../Docs/3D/Camera.md) |
| Instanced meshes | One mesh drawn thousands of times in one call: `MeshInstance` placements the GPU applies per copy, or a compute-written buffer | [Ch 18](18-3DGently.md) | [Instancing](../Docs/3D/Instancing.md) |
| Mesh fields | A retained world of placed meshes drawn by one call, GPU-culled per copy against the camera (`MeshField`/`drawMeshField`) | [Ch 18](18-3DGently.md) | [Instancing](../Docs/3D/Instancing.md) |
| Strand fields | Grass grown inside the draw call: bending, swaying blades with no geometry buffers, camera-culled and distance-graded (`StrandField`/`drawStrands`) | [Ch 18](18-3DGently.md) | [Strands](../Docs/3D/Strands.md) |
| Depth compositing | Flat 2D drawing placed *inside* the 3D depth buffer, so the scene occludes it: `depth(at:)`, `project`, billboards, depth feeds | [Ch 20](20-DepthAndThePhone.md) | [DepthCompositing](../Docs/3D/DepthCompositing.md) |
| What stacks with what | The compatibility map across the 3D features | [Ch 18](18-3DGently.md), [Ch 19](19-SculptingWithFields.md) | [Combining](../Docs/3D/Combining.md) |

## Sculpting with fields

| Capability | What it is | Guide | Reference |
|---|---|---|---|
| 2D SDF combinators | Shapes as distance fields that merge, melt, morph, and repeat | [Ch 19](19-SculptingWithFields.md) | [Combinators](../Docs/Drawing/Combinators.md) |
| The `sculpt { }` block | Add, carve, and blend region shapes with stateful verbs, built for live coding | [Ch 19](19-SculptingWithFields.md) | [Combinators](../Docs/Drawing/Combinators.md) |
| Raymarched 3D fields | `SDF3D` sphere-traced through the camera, depth-composited with meshes | [Ch 19](19-SculptingWithFields.md) | [Combinators](../Docs/Drawing/Combinators.md) |

## Depth and the phone

| Capability | What it is | Guide | Reference |
|---|---|---|---|
| RGBD frames | Color plus depth plus intrinsics; unproject any pixel to a metric point | [Ch 20](20-DepthAndThePhone.md) | [RGBD](../Docs/3D/RGBD.md) |
| Recorded captures | Open `.r3d` depth recordings as point clouds with true intrinsics | [Ch 20](20-DepthAndThePhone.md) | [Record3D](../Docs/3D/Record3D.md) |
| Live USB depth | A tethered phone's RGBD stream, frame by frame | [Ch 20](20-DepthAndThePhone.md) | [Record3D](../Docs/3D/Record3D.md) |
| The capture app | Ollin's own iPhone app streams body, face, LiDAR depth, segmentation, and motion | [Ch 20](20-DepthAndThePhone.md) | [Phone](../Docs/3D/Phone.md) |
| World fusion | Sweep the phone; frames fuse into one fixed world cloud by pose | [Ch 20](20-DepthAndThePhone.md) | [Phone](../Docs/3D/Phone.md) |

## Sound and control

| Capability | What it is | Guide | Reference |
|---|---|---|---|
| Audio analysis | Amplitude, spectrum, waveform, log-spaced bands ready to draw | [Ch 21](21-SoundAndControl.md) | [Audio](../Docs/Helpers/Audio.md) |
| Beat detection | Onsets as events: `beat`, `beatCount`, `timeSinceBeat` | [Ch 21](21-SoundAndControl.md) | [Audio](../Docs/Helpers/Audio.md) |
| Audio sources | Microphone, audio files (export-reproducible), test tones, a video's soundtrack | [Ch 21](21-SoundAndControl.md), [Ch 22](22-Seeing.md) | [Audio](../Docs/Helpers/Audio.md) |
| Listening | Speech as a caption that corrects itself and phrases you can trigger from, plus 300-odd everyday sounds named as they happen | [Ch 21](21-SoundAndControl.md) | [Listening](../Docs/Helpers/Listening.md) |
| Synthesis | A `Synth` the sketch plays: notes by name or number, voice presets, envelopes, filters, delay and reverb, two physical models (a plucked string and a struck shape), sound placed in the 3D scene, and a soundtrack in an export | [Ch 21](21-SoundAndControl.md) | [Synthesis](../Docs/Helpers/Synthesis.md) |
| Composition | Working out what to play: Euclidean rhythms, scales and chords, arpeggios, Markov sequences, all on a step number | [Ch 21](21-SoundAndControl.md) | [Composition](../Docs/Helpers/Composition.md) |
| Sonification | Numbers read out as notes: a table column, a terrain profile, or a picture row spread over a range of pitch and snapped to a scale | [Ch 21](21-SoundAndControl.md) | [Sonification](../Docs/Helpers/Sonification.md) |
| MIDI | Knobs, notes, and messages from hardware controllers, in and out | [Ch 21](21-SoundAndControl.md) | [MIDI](../Docs/Integration/MIDI.md) |
| OSC | Network control messages from tablets, DAWs, and other machines | [Ch 21](21-SoundAndControl.md) | [OSC](../Docs/Integration/OSC.md) |
| Game controllers | Sticks, triggers, and buttons read in `draw()`, plus motion and a touchpad on hardware that has them, with several players at once and a null read when nothing is plugged in | [Ch 21](21-SoundAndControl.md) | [Controller](../Docs/Integration/Controller.md) |
| Parameter binding | One `@Param` driven by MIDI, OSC, and the inspector alike, with smoothing | [Ch 21](21-SoundAndControl.md) | [Parameters](../Docs/Helpers/Parameters.md) |

## Seeing and video

| Capability | What it is | Guide | Reference |
|---|---|---|---|
| Camera feeds | The webcam (or any frame source) drawn and analyzed live | [Ch 22](22-Seeing.md) | [Vision](../Docs/Vision/Vision.md) |
| People trackers | Faces with landmarks, hands, 2D and 3D body poses, person segmentation | [Ch 22](22-Seeing.md) | [Vision](../Docs/Vision/Vision.md) |
| Scene trackers | Contours, rectangles, barcodes, text (OCR), saliency, classification, subject lift, point-prompted lift | [Ch 22](22-Seeing.md) | [Vision](../Docs/Vision/Vision.md) |
| Motion trackers | Object tracking, thrown-object trajectories, dense optical flow | [Ch 22](22-Seeing.md) | [Vision](../Docs/Vision/Vision.md) |
| `ModelTracker` | Bring any Core ML model: classifiers, detectors, image-to-image maps, segmenters | [Ch 22](22-Seeing.md) | [Vision](../Docs/Vision/Vision.md) |
| Still analysis | Every tracker also runs one-shot on an `Image` | [Ch 22](22-Seeing.md) | [Vision](../Docs/Vision/Vision.md) |
| Video playback | Files as live textures: play, seek, loop, analyze, all export-reproducible | [Ch 22](22-Seeing.md) | [Video](../Docs/Video/Video.md) |
| Slit scan | A rolling frame history read back through a per-pixel time delay: time as a spatial dimension | [Ch 22](22-Seeing.md) | [SlitScan](../Docs/Video/SlitScan.md) |

## Sharing and performing

| Capability | What it is | Guide | Reference |
|---|---|---|---|
| Stills and sequences | `--export` a frame, `--export-sequence` a folder of them | [Ch 23](23-SharingAndPerforming.md) | [Export](../Docs/Output/Export.md) |
| Path-traced export | `--path-traced` renders the 3D scene by tracing light: soft shadows, bounce color, mirror in mirror, real glass, glowing meshes as lights, textures in the bounces, a real lens | [Ch 23](23-SharingAndPerforming.md) | [Path-traced export](../Docs/Output/PathTraced.md) |
| Video and GIF | `--export-video` (H.264, HEVC, ProRes) and `--export-gif`, deterministic | [Ch 3](03-MotionAndTime.md), [Ch 23](23-SharingAndPerforming.md) | [Export](../Docs/Output/Export.md) |
| Live recording | `startRecording()` or ⌘⇧R keeps a run as it happens, sound included, through evaluations | [Ch 23](23-SharingAndPerforming.md) | [Recording](../Docs/Output/Recording.md) |
| Record & replay | `--record-take` writes a run's seed, clock, inputs, and knobs down; `--replay` plays it back exactly, scrubs it, and re-renders it through any export | [Ch 23](23-SharingAndPerforming.md) | [Replay](../Docs/Core/Replay.md) |
| Perfect loops | Declare `loopDuration` and `--export-loop` renders exactly one seamless lap | [Ch 3](03-MotionAndTime.md) | [Export](../Docs/Output/Export.md) |
| SVG for plotters | `--export-svg` true vectors, with `--hatch` turning fills into line work | [Ch 14](14-ShapesAsMaterial.md), [Ch 23](23-SharingAndPerforming.md) | [Export](../Docs/Output/Export.md) |
| Print separations | `--export-separations`: one grayscale master per spot ink, screened, with an overprint preview | [Ch 23](23-SharingAndPerforming.md) | [PrintSeparations](../Docs/Output/PrintSeparations.md) |
| 3D printing | `mesh.write(to:)` as STL, OBJ, or 3MF at a real size, with `printCheck()` reporting whether the surface is a solid | [Ch 23](23-SharingAndPerforming.md) | [Fabrication](../Docs/Output/Fabrication.md) |
| Spatial models | `--export-usdz` writes a 3D frame (or any `Scene`) as USDZ: opens in Quick Look, sends in a message, stands on a table in AR | [Ch 23](23-SharingAndPerforming.md) | [Spatial](../Docs/Output/Spatial.md) |
| Spatial video | `--export-spatial` writes the motion as a stereo pair per frame (MV-HEVC), with `stereoGeometry` naming how far apart the eyes stand and how far away they agree | [Ch 23](23-SharingAndPerforming.md) | [Spatial](../Docs/Output/Spatial.md#spatial-video) |
| Headless capture | `OllinApp.image(of:frame:)` renders any sketch to a `CGImage` in code, no window; the export flags are wrappers around it, and this guide's figures are made with it | [Ch 23](23-SharingAndPerforming.md) | [Export](../Docs/Output/Export.md) |
| Reproducibility metadata | Every PNG/SVG/PDF/video embeds its recipe: seed, `@Param` values, git commit, frame | [Ch 23](23-SharingAndPerforming.md) | [Export](../Docs/Output/Export.md#reproducibility-metadata) |
| Contact sheets | `--export-grid` tiles one frame per seed into a labeled proof sheet; `--seed` re-renders a keeper | [Ch 4](04-Randomness.md) | [Variations](../Docs/Core/Variations.md) |
| Syphon | Publish frames to (and read frames from) other Mac apps, GPU to GPU | [Ch 23](23-SharingAndPerforming.md) | [Syphon](../Docs/Integration/Syphon.md) |
| Virtual camera | Your sketch as a system-wide webcam every video app can pick, including the browser, which Syphon cannot reach | [Ch 23](23-SharingAndPerforming.md) | [VirtualCamera](../Docs/Integration/VirtualCamera.md) |
| DMX lighting | Real lights driven from `draw()` over Art-Net or sACN: a 512-channel universe filled through named fixtures and sent every frame, and a lighting console driving the sketch back | [Ch 23](23-SharingAndPerforming.md) | [DMX](../Docs/Integration/DMX.md) |
| Screen capture | Any display, app, or window on the Mac as a live frame source, whether or not it cooperates the way Syphon needs; a tracker reads it like a camera, and leaving your own window in gives you the feedback tunnel | [Ch 22](22-Seeing.md) | [ScreenCapture](../Docs/Integration/ScreenCapture.md) |
| Live coding | `swift run OllinLiveCoding`: code over visuals, evaluate mid-motion, perform | [Ch 23](23-SharingAndPerforming.md) | [LiveCoding](../Docs/Tools/LiveCoding.md) |
| Extensions | `Sketch.extend`: hooks before, during, and after each frame, for recorders and chrome | [Ch 23](23-SharingAndPerforming.md) | [Sketch](../Docs/Core/Sketch.md#extensions) |
| Running unattended | `installation` puts a piece on a wall: full screen, no pointer, the display kept awake, and a clock that survives a gap in the frames and a week of running | [Ch 23](23-SharingAndPerforming.md) | [Installation](../Docs/Output/Installation.md) |
| Resuming after a stop | `@Saved` properties and a checkpoint cadence write the run down, so a relaunch picks the piece up where it was rather than starting it over | [Ch 23](23-SharingAndPerforming.md) | [Installation](../Docs/Output/Installation.md) |
| Profiling | The inspector's cost row: CPU against GPU on one frame's scale, the draw, pass and batch counts, and a frame handed to Xcode | [Ch 23](23-SharingAndPerforming.md) | [Profiling](../Docs/Tools/Profiling.md) |
| Writing an extension | `ollin new --kind extension`: a library other sketches import, the `ollinx-` naming convention, and the four seams to build on | [Ch 23](23-SharingAndPerforming.md) | [Extensions](../Docs/Tools/Extensions.md) |
| Accessibility | See your colors through the three kinds of color vision, check whether a palette holds apart, and read the reduce-motion setting | [Ch 2](02-Color.md), [Ch 3](03-MotionAndTime.md) | [Accessibility](../Docs/Helpers/Accessibility.md) |

---

[Contents](README.md#contents) · Previous: [Appendix C, Coming from p5.js and Processing](C-ComingFromP5.md)
