#### <sup>[Ollin](../README.md) → Documentation</sup>

---

## Ollin API

Reference for Ollin's drawing surface and helpers. The bare calls you write in `draw()` forward to an internal `Drawer` (see [How it works](../README.md#how-it-works)), and everything here is callable bare inside a `Sketch`.

New to Swift? Start with the [Swift quick reference](./Swift.md), which covers just enough of the language to be productive in `draw()`. Coming from p5.js or Processing? [Appendix C of the Guide](../Guide/C-ComingFromP5.md) maps the API you already know onto Ollin.

### Core

- [`Sketch`](./Core/Sketch.md) - the lifecycle (`setup`/`draw`), temporal state (`time`, `frameCount`, …), and loop control
- [`Canvas`](./Core/Canvas.md) - `scale`, the `canvasSize` export presets, and the preview window (`windowMode`)
- [`Variations`](./Core/Variations.md) - `variation`, the seed a run grew from: step, roll, and jump through a sketch's variation space in the inspector, proof a range as a contact sheet (`--export-grid`), and re-render a keeper with `--seed`
- [`Replay`](./Core/Replay.md) - record a run's seed, clock, inputs, and knob moves as a take (`--record-take`), play it back exactly (`--replay`, with transport keys), scrub it, and re-render the performance through any export flag
- [`Automation`](./Core/Automation.md) - keyframed parameters: a knob's values written down over time (`automate`), carried by named or Bezier curves, looped and played at any speed, read from a file (`--automation`) and rendered exactly by any export

### Drawing

- [`Drawing`](./Drawing/Drawing.md) - `background`, `fill`/`stroke`, the shapes, the transform stack, and the views over it (`withClip`, `withViewBox`, `viewControl`)
- [`Accumulation`](./Drawing/Accumulation.md) - `noClear` to keep the canvas across frames so drawing piles up (long exposures, paint-on-canvas, light accumulation)
- [`HDR & tone-mapping`](./Drawing/HDR.md) - `toneMap` to roll bright, out-of-range light off the screen instead of clipping it (the linear-float pipeline behind every frame; the glow/bloom and sandpainting looks)
- [`Wide gamut & HDR output`](./Drawing/ColorOutput.md) - `colorOutput` to present through Display P3 and keep highlights brighter than white, `Color(displayP3:)` for colors outside sRGB, and HDR10 video export
- [`Retained batches`](./Drawing/Batches.md) - `makeBatch`/`drawBatch` to record heavy static drawing once and replay it each frame from the GPU for (almost) nothing, the draw-time transform placing or stamping the whole recording
- [`Layered effects`](./Drawing/Effects.md) - `renderTarget`/`withTarget` to draw into off-screen layers, `filtered`/`postProcess` to run GPU filters (blur, bloom, color grade, gradient map, edges, halftone, …) over them, composited back with blend modes; `combined` to combine two layers (mask, displace, mix, depth-of-field defocus); `generate` for procedural pattern sources, `feedback` for trails and tunnels, and `compose { }` (with `aside` helper layers) to declare a stack of layers as one block
- [`Marks`](./Drawing/Marks.md) - `StrokeMark`/`drawMark` and `StrokeDynamics`: width and opacity driven by how a mark is being made (how fast the pointer moves, how hard it is pressed) rather than by where you are along the path
- [`Text`](./Drawing/Text.md) - `drawText` with bitmap, outline (`.ttf`/`.otf`), and stroke (single-line / plotter) fonts, plus `textToShapes` (text as geometry) and text in any script (right-to-left, Devanagari, Thai, Japanese, emoji)
- [`Images`](./Drawing/Images.md) - `loadImage`, `drawImage`, `tint`, and pixel access: load or author a raster image, draw it scaled or transformed, recolor it
- [`Glyph mosaic`](./Drawing/GlyphMosaic.md) - `drawGlyphMosaic`, an image rebuilt as a grid of text glyphs, each cell's character chosen by its measured ink in the active font
- [`Halftone`](./Drawing/Halftone.md) - `drawHalftone`, an image rebuilt as the classic print dot screen: area-exact dots on a rotated grid, real circles for the plotter path
- [`Pixel sorting`](./Drawing/PixelSorting.md) - `Image.pixelSorted`, brightness-bounded runs of an image's own pixels reordered along rows or columns (the classic glitch melt)
- [`Seam carving`](./Drawing/SeamCarving.md) - `Image.seamCarved` and `SeamMap`, resizing a picture by taking away the paths that carry the least, so what matters keeps its shape (plus the masks that hold something still or take it out)
- [`Color`](./Drawing/Color.md) - the `Color` type, the OKLab family and mixing, `Ramp`s and `Palette`s (loaded from a file or extracted from an image), dithering an image down to a palette, and perceptual `Colormap`s
- [`Geometry`](./Drawing/Geometry.md) - the `Vector2`, `Rectangle`, `Grid`, `Shape`/`Contour`, and `Path` value types (including the `Grid` layout helper, curved outlines, shape booleans, and offsetting)
- [`SVG import`](./Drawing/SVG.md) - `loadSVG`/`drawSVG` to read vector artwork into `Shape`s and `Contour`s (paths with curves and arcs, the basic shapes, groups and transforms, fills and strokes), ready for booleans, offsets, hatching, and re-export
- [`Fourier epicycles`](./Drawing/Epicycles.md) - `Epicycles` + `drawEpicycles`: rebuild any closed outline as a chain of spinning circles, with a term-count dial from soft phantom to exact trace
- [`Classic curves`](./Drawing/Curves.md) - the closed-form curve canon as geometry builders: `phyllotaxis`, `lissajous`, `rose`, `superellipse`, `supershape`, `hypotrochoid`/`epitrochoid` (the spirograph gears), `guilloche` (the rose engine's twisted, cam-shaped rings), the damped-pendulum `Harmonograph`, `spirolateral` (a walk of growing steps repeated until it comes home), and Chaikin `smoothed(iterations:)` corner cutting
- [`Anamorphosis`](./Drawing/Anamorphosis.md) - `Anamorphosis`: a plate that reads only in a mirrored cylinder standing on the page, from one viewing spot; the wrap at true size, the map for points, contours and shapes, what an eye can see of a cylinder, and the search that reads a plate back
- [`Clothoid`](./Drawing/Clothoid.md) - the curve whose bend grows at a steady rate (the Euler or Cornu spiral): the easement that joins a straight run to a turn with no kink, the single curve that fits two points and two headings, a smooth path through waypoints, and polyline corners a vehicle could take
- [`Shape morphing`](./Drawing/Morphing.md) - `ShapeMorph`: tween one `Shape` into another with every in-between a real vector shape (contour pairing, corner-keeping correspondence, holes that grow in and out); `Shape` is `Tweenable`, so a `Timeline` sequences geometry
- [`Voronoi & Delaunay`](./Drawing/Voronoi.md) - tessellate points into vector geometry: Voronoi cells (the "crystallization" look) and the dual Delaunay triangle mesh, with Lloyd relaxation
- [`Spatial index`](./Drawing/SpatialIndex.md) - `SpatialIndex`, the structure that answers what is near a point without reading every point: nearest, k nearest, everything within a radius, everything inside a box, over a uniform grid or a k-d tree
- [`Fitting`](./Drawing/Fitting.md) - `RadialBasis`, a smooth field of numbers, vectors, or colors fitted through values you know at a handful of scattered places (and the warp a field of vectors makes), plus `Fit.minimize`, which walks a handful of knobs downhill against a cost you write
- [`Truchet tiling`](./Drawing/Truchet.md) - one tile per grid cell spun to a random orientation, so identical parts line up into flowing loops (`.arcs`) or a maze (`.diagonals`)
- [`Hitomezashi stitching`](./Drawing/Hitomezashi.md) - one bit per grid line phases its dashes, and the shifted lines weave into staircases, loops, and a two-tone cloth
- [`Ten print`](./Drawing/TenPrint.md) - `tenPrint`, one of two diagonals per cell by a coin flip, joined into the long connected paths that made the picture famous
- [`Kolam and sona`](./Drawing/Kolam.md) - one line launched between a field of dots and bounced off the edges until it closes, in gcd(rows, columns) loops, with walls to steer it
- [`Celtic knotwork`](./Drawing/Knotwork.md) - the same line given width and an over-under rule that alternates, handed back already broken where each cord dives
- [`Crease patterns`](./Drawing/CreasePattern.md) - the flat sheet a folded or cut thing comes from: the Miura fold with its rigid folding in three dimensions, rotating-squares kirigami, and Kawasaki's and Maekawa's laws that say whether a sheet can fold flat
- [`Tiling & layout`](./Drawing/Tiling.md) - the other ways to divide a canvas: `HexGrid`/`TriangleGrid` (the hex and triangle tilings, with hex distance, neighbors, and exact picking), `subdivide` (recursive panels, binary or quadtree), `Maze` (three carving algorithms, walls as clean line-work, solution and longest paths), and `apollonianGasket` (the kissing-circles foam)
- [`Aperiodic tilings`](./Drawing/AperiodicTilings.md) - the tilings that never repeat: `penroseTiling` (kites and darts, rhombs, with the matching-rule arcs), `wangTiling` (edge-matching squares as one connected quilt), `girihPattern` (Islamic star patterns over any polygons, plus the five girih tiles), and `spectreTiling` (the einstein, straight or strictly chiral curved)
- [`Hyperbolic tiling`](./Drawing/HyperbolicTiling.md) - regular tilings of the hyperbolic plane in the Poincaré disk: `hyperbolicTiling` (any {p,q} with (p-2)(q-2) > 4, typed tiles with depth and a two-coloring parity, and a `viewpoint` that pans across the endless tiling)
- [`Strange attractors`](./Drawing/Attractors.md) - chaotic systems as points: continuous 3D orbits (Lorenz, Rössler, Aizawa, …) integrated with Runge-Kutta and orbited through the camera, 2D iterated maps (Clifford, de Jong, Hénon, Gumowski-Mira, Ikeda, hopalong) accumulated into density fields, and `AttractorFlow`, a million GPU particles riding one field at once
- [`SDF combinators`](./Drawing/Combinators.md) - compose signed-distance fields so shapes *merge* instead of stack: smooth union/subtract/intersect and morph, round/onion, and domain mirror/tile, via the `SDF` value type + `drawSDF` and a scoped `smoothUnion { }` block, in 2D and a raymarched 3D form (`SDF3D` + `drawSDF3D`)
- [`Measured distance fields`](./Drawing/DistanceFields.md) - measure a distance field back out of a drawn layer with `Filter.distanceField`: how far every pixel is from the nearest edge and which way it lies, read back through `Filter.fieldMap` as contours, grown and shrunk shapes, and outlines, or in a shader as a Voronoi keyed to the picture
- [`Local averages`](./Drawing/LocalAverages.md) - the average of the neighborhood around every pixel for a flat price, over a summed-area table: `Filter.boxBlur`, whose cost does not grow with its radius, and `Filter.adaptiveThreshold`, which cuts a picture to two tones against each pixel's own surroundings so uneven light stops mattering

### Shaders

Writing GPU code yourself: fragment shaders run through the effect graph, compute kernels over buffers and textures, and the helper library both draw from.

- [`Shaders`](./Shaders/Shaders.md) - write your own fragment shader (`Shader` + a `shade(uv, info)` function) and run it through the effect graph as a generator, filter, or combine, with a built-in shader library and line-accurate compile errors
- [`Visuals`](./Shaders/Visuals.md) - compose animated imagery by chaining (`Visual`): sources (oscillator, noise, voronoi, shape) through warps, color moves, blends, and modulations, the whole chain compiling into a single GPU pass with every number animatable for free
- [`Shader library`](./Shaders/ShaderLibrary.md) - reference for the helper functions a fragment shader or compute kernel can call: color/OKLab, hashes, value/gradient/curl noise, the 2D signed-distance catalog (`smin`, `sdEllipse`, `sdHeart`, …), and the repeat/mirror/polar domain operators
- [`Compute & GPU particles`](./Shaders/Compute.md) - GPU compute over buffers and textures: `Particles` (a million updated and drawn on the GPU each frame, the "sandpainting" engine) and `Simulation` (reaction-diffusion, cellular automata, and other ping-pong texture sims), over the `ComputeKernel`/`ComputeBuffer`/`ComputeTexture` core (with the shared shader library spliced into every kernel)

### 3D

- [`3D`](./3D/3D.md) - opt into a 3D camera and depth buffer: orbit a `Camera3D` (perspective or orthographic) and draw `PointCloud`s as instanced disc splats and a catalog of solid primitives (box, sphere, capsule, the Platonic solids, …) plus parametric and profile shapes (supershape, extrude, lathe), meshes loaded from file (`.obj`, `.usdz`/`.stl`/`.ply`, `.gltf`/`.glb`), textured and surface-mapped meshes (normal, metallic-roughness, occlusion, emissive, and height maps: parallax occlusion plus real displacement; triplanar projection for meshes with no uvs; detail maps for close-up texture), projected decals stamped across whatever surfaces a box touches, and a live webcam depth cloud
- [`Scenes`](./3D/Scenes.md) - `loadScene` keeps a glTF or USD file's *structure* instead of merging it: a tree of named nodes drawn in place with `drawScene`, reached by name to animate (`scene["lamp"]`), opening on the authored camera and punctual lights as ready `Camera3D`/`Light` values, and playing the file's authored keyframe animations on the sketch clock (`apply(_:at:)`)
- [`Instanced meshes`](./3D/Instancing.md) - draw one mesh thousands of times in one call: `drawMesh(_:instances:)` takes a list of `MeshInstance` placements (position, rotation, scale, tint) the GPU applies per copy, or a `ComputeBuffer` a kernel writes so a simulation moves the copies without the CPU; copies shade like solid meshes and cast into the shadow maps; a retained `MeshField` scales it to a whole world drawn by one call, GPU-culled per copy against the camera
- [`The Hopf fibration`](./3D/HopfFibration.md) - a sphere's worth of circles, no two of which meet and every two of which are linked exactly once: `hopfFibers` hands them back as `[Vector3]` paths for `drawTube`, with `hopfBases` supplying the structured base sets (rings of latitude, or a spiral) that make the linking legible
- [`Strand fields`](./3D/Strands.md) - grass a mesh pipeline grows inside the draw call itself: `StrandField` + `drawStrands`, half a million bending, swaying blades with no vertex or instance buffer anywhere, tile-culled by the camera and detail-graded by distance, shaded and shadow-receiving on the solid lit path
- [`Combining 3D features`](./3D/Combining.md) - the practical map of what stacks with what: which geometry takes lights, materials, matcaps, and environment light; who casts, receives, and appears in shadows and reflections; when to reach for screen-space versus ray-traced reflections; and a step-by-step recipe for the most realistic scene
- [`Camera control`](./3D/Camera.md) - move the camera by hand (`cameraControl()`: drag to orbit, scroll to dolly, right or modifier-drag to pan, damped) or play a ready-made cinematic move (`cameraMove(_:)`: turntable, push-in, tilt, orbit-and-rise, reveal, handheld), both opt-in over the orbit pose
- [`Caustics`](./3D/Caustics.md) - the light glass and metal focus: `caustics()` photon-traces the caster light through every transmissive and mirror-polished surface and draws where it lands, so a glass sphere throws its bright spot into its own shadow, a chrome ring folds light beside itself, and `dispersion:` fans a prism's rainbow (ray-tracing GPUs)
- [`Lens flare`](./3D/LensFlare.md) - the light the camera adds by itself: `lensFlare()` works out the ghosts a real lens prescription makes of each bright source, placed, sized, shaped by the iris blades, and colored by the anti-reflective coating, plus the star on the source itself, whose arms count those same blades, all of it fading as something covers the source rather than switching off
- [`Atmosphere`](./3D/Atmosphere.md) - give the air a presence: `fog` fades surfaces with distance and pools low with a height falloff (exact closed-form transmittance), `aerialPerspective` splits the fade by wavelength and lights it with the sun so far ridges veil blue and melt into the sky, and `volumetricLight` marches the air so spot cones, cookies, IES profiles, and cast shadows become visible beams and crepuscular shafts
- [`Depth compositing`](./3D/DepthCompositing.md) - place 2D drawing *inside* a 3D scene so it occludes and is occluded by the geometry: `depth(at:)`, `project`, and `withBillboard` (a 2D label hidden when it swings behind the cloud)
- [`Record3D`](./3D/Record3D.md) - `import OllinRecord3D` to turn an iPhone's color-plus-depth into a 3D point cloud, from a recorded `.r3d` file or a tethered phone's live USB stream
- [`RGBD`](./3D/RGBD.md) - the source-agnostic `RGBDFrame` (color + depth + intrinsics) any depth source produces: unproject a point cloud, lift a single image point to metric 3D, or lift a 2D body pose into space (`Body.lifted(through:)`)
- [`Phone`](./3D/Phone.md) - `import OllinPhone` to read a tethered iPhone's live on-device ARKit sensor stream from Ollin's own capture app: a 3D body skeleton, a face mesh with expression blendshapes, the hands in view as 21-joint skeletons lifted to metric 3D, the recognized text lines with their corners lifted to 3D, world-facing rear-LiDAR depth (a metric point cloud with the camera's 6DoF pose), the reconstructed room as a labeled surface, a person matte, and device motion, over the USB cable

### Generators

- [`Random`](./Generators/Random.md) - `random`, `randomGaussian`, and the `randomVector`/`ring` scatter helpers
- [`Noise`](./Generators/Noise.md) - Perlin `noise` / `signedNoise`, seamlessly looping `noise(loop:)`, layered `fbm`, and `curlNoise` flow fields
- [`Blue noise`](./Generators/BlueNoise.md) - `poissonDisk`, an even-but-organic scatter with no clumps or gaps (Poisson-disk sampling)
- [`Low-discrepancy sampling`](./Generators/LowDiscrepancy.md) - `haltonPoints` / `sobolPoints`, even coverage as an ordered stream: growing the count only adds points, never moves them
- [`Points on a surface`](./Generators/SurfaceSampling.md) - `surfacePoints`, points scattered over a mesh's skin rather than its vertex list, evenly spaced by default, each carrying the normal, texture coordinate, and triangle it landed on
- [`Stippling`](./Generators/Stippling.md) - `stipple`, dots packed to reproduce an image's tone (weighted-Voronoi stippling), or any density function
- [`Ford circles`](./Generators/FordCircles.md) - `fordCircles`, a circle for every fraction that touches its neighbors and overlaps nothing, over `fareySequence` and the exact `Fraction` type
- [`Ulam spiral`](./Generators/UlamSpiral.md) - `ulamSpiral`, the whole numbers written in a square spiral so a test on them becomes a picture, with the primes falling on diagonals
- [`Fractals`](./Generators/Fractals.md) - `IFS` chaos games, `FractalFlame` renders, circle-inversion limit sets, and Kleinian limit-set curves, plus the `fitted` placement helper
- [`Chaotic maps & bifurcation`](./Generators/Bifurcation.md) - `IteratedMap`, the one-dimensional route to chaos: logistic, sine, tent, and Gauss families, orbits and cobweb staircases, the bifurcation diagram as dots or a density image, and Lyapunov exponents
- [`Single line`](./Generators/SingleLine.md) - `singleLine`, one continuous tour through an image's stipple (TSP art), a plotter-friendly `Contour`
- [`Ant colony`](./Generators/AntColony.md) - `AntColony`, a pheromone-trail colony condensing a web of possibilities onto a short tour, the search itself the picture
- [`Spanning tree`](./Generators/SpanningTree.md) - `spanningTree`, the minimum spanning tree of an image's stipple: the branching, vein-like sibling of the single line
- [`String art`](./Generators/StringArt.md) - `StringArt`, one continuous thread wound over rim pins until the crossings reproduce a picture (a stateful stepper)
- [`Percolation`](./Generators/Percolation.md) - `Percolation`, site-percolation clusters over a seeded grid: largest-first labeling, the spanning cluster, cell rectangles and traced boundary loops
- [`Isolines`](./Generators/Isolines.md) - `isolines`, level curves of any scalar field or an image's tone by marching squares, from metaball outlines to contour maps
- [`Isosurfaces`](./Generators/Isosurface.md) - `isosurface` / `Metaballs`, the surface where a field over space crosses a level, marched into a `Mesh`: soft spheres that fuse, noise volumes, gyroids
- [`Subdivision surfaces`](./Generators/SubdivisionSurfaces.md) - `mesh.subdivided`, a low-poly control cage refined into a smooth solid by the Catmull-Clark or Loop rules, with welding and open-edge handling built in
- [`Mesh growth`](./Generators/MeshGrowth.md) - `MeshGrowth` / `MeshReactionDiffusion`, a surface that grows more area than it has room for and folds: brain coral, branching coral, a ruffled leaf margin
- [`Surface reconstruction`](./Generators/SurfaceReconstruction.md) - `reconstructSurface` / `particleSurface`, from points back to a `Mesh`: rebuild a scanned room or object holes-and-all, or skin a particle set as one blended body
- [`Hulls`](./Generators/Hulls.md) - `concaveHull` / `alphaShape`, the tighter answers to "what shape are these points?": one gulf-hugging simple polygon, or the scatter's true footprint with islands and holes
- [`Medial axis`](./Generators/MedialAxis.md) - `medialAxis`, a shape reduced to its skeleton, every point carrying its inscribed-disk radius
- [`Straight skeleton`](./Generators/StraightSkeleton.md) - `straightSkeleton`, the shrinking-boundary ridge network with faces and exact mitered insets (`inset(by:)`), the topographic-contour ladder from one build
- [`Force-directed layout`](./Generators/ForceLayout.md) - `ForceLayout`, a graph untangling itself: repulsion between all nodes, attraction along edges, cooling to an even web you can grow, pin, and drag
- [`Marbling`](./Generators/Marbling.md) - `Marbling` / `drawMarbling`, paper marbling in closed form: drops, tines, combs, and swirls raking vector ink outlines into feathered papers
- [`Watercolor`](./Generators/Watercolor.md) - `Watercolor` / `drawWatercolor`, watercolor pigment from recursively deformed polygons stacked as translucent layers
- [`Chladni figures`](./Generators/Chladni.md) - `chladni`, a ringing plate's standing-wave field in closed form, plus the `.chladni` generator's sand and wave readings and the mode-by-pitch audio join
- [`Billiards`](./Generators/Billiards.md) - `Billiard`: a ball bouncing forever in a circle, an ellipse, a polygon, or a stadium, with posts standing in it; the path comes back as geometry, and the room decides whether it draws a pattern or fills the floor
- [`Drainage`](./Generators/Drainage.md) - `Drainage`: rivers worked out from a `Heightfield` rather than drawn, with hollows filled so water always has a way out, flow per cell, the network above a threshold as strokable reaches, Strahler ordering, and basins
- [`Terrain`](./Generators/Terrain.md) - `Heightfield`, landscapes from noise or `diamondSquare`, weathered by droplet hydraulic and thermal erosion, emitted as terrain meshes, heightmaps, and contours
- [`Random walks`](./Generators/Walks.md) - `randomWalk` / `levyFlight` / `selfAvoidingWalk`, paths built one random step at a time: the local tangle, the cluster-and-leap, and the never-crossing single stroke
- [`Circle packing`](./Generators/Packing.md) - `packCircles` and `relaxCircles`, filling a region with non-overlapping circles that grow until they touch
- [`Shape grammars`](./Generators/ShapeGrammar.md) - `ShapeGrammar`, a design written as rules over labeled shapes: the balanced cut behind the ice-ray lattices, splits for a building front, insets that become bars, and nested turned copies
- [`L-systems`](./Generators/LSystem.md) - `drawLSystem` and a preset catalog: a rewriting grammar walked by a turtle into fractal curves and branching plants, symbolic or parametric (symbols carrying numbers, for fractional lengths, delays, and tapering width)
- [`Differential growth`](./Generators/DifferentialGrowth.md) - `DifferentialGrowth`, a line of nodes that grows and folds into organic, brain-coral structure (a stateful stepper)
- [`Meander`](./Generators/Meander.md) - `Meander`, a river centerline that migrates by curvature, cutting off oxbow lakes and recording scars (a stateful stepper)
- [`Wave Function Collapse`](./Generators/WaveFunctionCollapse.md) - `wfc`, filling a grid so every neighbor is legal, from a tileset you declare or from the patches of an example picture (constraint-solved tile layouts, texture synthesis)
- [`Cellular automata`](./Generators/CellularAutomata.md) - `elementaryCA`/`totalisticCA` rule-by-number row stacks, and `Turmite` walkers (Langton's ant and friends) painting a wrapped grid
- [`Shape packing`](./Generators/ShapePacking.md) - `packShapes` and `ContinuousPacking`, filling a region with non-overlapping shapes grown against each other's outlines
- [`Flow fields`](./Generators/FlowField.md) - `FlowField`, tracing streamlines through a direction field (the flow-field look) and advecting particles along it
- [`Flocking`](./Generators/Boids.md) - `Boids`, a flock steering by separation/alignment/cohesion into emergent flocking motion
- [`Pursuit`](./Generators/Pursuit.md) - `Pursuit`, runners that head straight at each other and leave logarithmic spirals: the ring of mice, and a quarry that runs straight (a stateful stepper)
- [`Steering`](./Generators/Steering.md) - `Vehicle`, a creature moved by composable steering forces (seek, flee, arrive, pursue, wander, follow a path or flow field)
- [`Space colonization`](./Generators/SpaceColonization.md) - `SpaceColonization`, branching growth (veins, roots, trees) toward scattered attraction points (a stateful stepper)
- [`Diffusion-limited aggregation`](./Generators/DiffusionLimitedAggregation.md) - `DiffusionLimitedAggregation`, dendritic clusters frozen out of random walkers (frost and coral, a stateful stepper)
- [`Dielectric breakdown`](./Generators/DielectricBreakdown.md) - `DielectricBreakdown`, lightning grown where the solved electric field is strongest, the `eta` exponent sweeping furry bush to sparse Lichtenberg arc
- [`Crack growth`](./Generators/CrackGrowth.md) - `CrackGrowth`, perpendicular cracks subdividing the plane into city-block cells, each dragging a one-sided watercolor wash (a stateful stepper)

### Helpers

- [`Math`](./Helpers/Math.md) - `map`, `dist`, `lerp`, the shaping scalars (`clamp`/`fract`/`step`/`smoothstep`), and `Double.tau`
- [`Animation`](./Helpers/Animation.md) - looping progress (`loopProgress`/`pingPong`), the timers (`every`/`after`/`everyFrames`), `sway` (a value that travels between two ends and back, over five shapes), the `Easing` curves, `@Eased` (ease toward a target), `@Smoothed` (smooth a noisy signal), `@Sprung` (spring toward a target with momentum), and the `Timeline` keyframe sequencer
- [`Formula`](./Helpers/Formula.md) - a number written as a rule and read from text: `drive($radius, "190 + sin(time) * 80")`, the arithmetic vocabulary it speaks, the clock, canvas, pointer, and other knobs it can name, and the errors it reports rather than throws
- [`Parameters`](./Helpers/Parameters.md) - `@Param` tunable knobs: typed inspector controls (from sliders and toggles to menus, color wells, text, and geometry fields) in grouped cards, value scrubbing, optional smoothing, and binding from OSC or MIDI
- [`Input`](./Helpers/Input.md) - mouse and keyboard
- [`Accessibility`](./Helpers/Accessibility.md) - seeing your colors as the three kinds of color vision do, checking whether a palette holds apart, and reading the system's reduce-motion setting
- [`Data`](./Helpers/Data.md) - `loadTable` for CSV and TSV files (typed reads by column name) and `loadJSON` for documents you reach through by name and index
- [`LiveData`](./Helpers/LiveData.md) - `DataFeed`, one address read over and over on a background queue, so a sketch draws what is true now; conditional polling, backoff, and one fixed answer in an export
- [`Audio`](./Helpers/Audio.md) - `import OllinAudio` for microphone, file, and oscillator sources, analyzed into `amplitude`/`spectrum`/band values you read in `draw()`
- [`Listening`](./Helpers/Listening.md) - speech as a caption you can draw and phrases you can act on, plus 300-odd everyday sounds named as they happen, over any audio source
- [`Synthesis`](./Helpers/Synthesis.md) - `Synth`, the instrument a sketch plays: notes by name or number, `Voice` presets over a shaped and filtered oscillator, delay and reverb
- [`Composition`](./Helpers/Composition.md) - working out what to play: Euclidean rhythms, scales and chords, arpeggios, and Markov sequences, as pure values on a step number
- [`Sonification`](./Helpers/Sonification.md) - numbers read out as notes: a table column, a terrain profile, or a picture row spread over a range of pitch and snapped to a scale

### Simulation

- [`Physics`](./Simulation/Physics.md) - `import OllinPhysics` for a `World` you step each frame so motion comes from simulation: a soft Verlet side (particles, springs, disk collisions) and a rigid side (bodies, colliders, joints, backed by Box2D)
- [`Physics3D`](./Simulation/Physics3D.md) - rigid bodies inside the 3D scene: a `World3D` of stacking, tumbling, swinging `Body3D`s (backed by Jolt) with joints, contacts and sensors, walking characters, driveable vehicles, ragdolls built from a skinned `Scene`, cloth and ropes, mouse grabbing through the camera, and `withBody` drawing
- [`Swarm`](./Simulation/Swarm.md) - the steering behaviors at GPU scale: separation, alignment, cohesion, seek, flee, arrive, wander, and flow following as weights over tens or hundreds of thousands of agents
- [`Artificial life`](./Simulation/ArtificialLife.md) - three emergent-behavior systems on the GPU: `ParticleLife`, the `PPS` turning rule, and `Physarum` slime mold, the first two over a GPU `SpatialHash` neighbor search you can also build your own sims on
- [`Evolution`](./Simulation/Evolution.md) - populations that get better at something: `Evolution` breeds tens of thousands of GPU flights toward a target past obstacles by tournament selection, and `Population` breeds a handful of genomes a person picks by eye
- [`Fluids & soft bodies`](./Simulation/Fluids.md) - GPU particle dynamics: `ParticleFluid` (smoothed-particle hydrodynamics) and `SoftBodies` (shape-matched jelly blobs), both in a walled box you can splash and knead with the mouse
- [`Watercolor`](./Simulation/Watercolor.md) - wet paint on rough paper: the three-layer wash simulation (`watercolor(pigments:)`) with real pigment behavior and Kubelka-Munk glazing; paint with any drawing call, `dry()` between washes, `blot()` for backrun blooms
- [`Articulated & chaotic motion`](./Simulation/Motion.md) - CPU motion systems you step each frame: `IKChain` (inverse-kinematics tentacles and limbs), `DoublePendulum` (the classic chaos machine), and `NBody` (quadtree gravity for orbits, galaxies, and collisions)

### Integration

- [`OSC`](./Integration/OSC.md) - `import OllinOSC` to send and receive OSC messages over UDP (to and from TouchOSC, Max/MSP, TouchDesigner, …), read in `draw()` or bound to a `@Param`
- [`MIDI`](./Integration/MIDI.md) - `import OllinMIDI` to read from and send to MIDI controllers and keyboards over Core MIDI, read in `draw()` or bound to a `@Param`
- [`DMX`](./Integration/DMX.md) - `import OllinDMX` to drive stage lights and dimmers from `draw()` over Art-Net or sACN (a `DMXUniverse` of 512 channels with named-fixture sugar), to send the canvas's own pixels to LED strips and matrices (`LEDMap`, sampled on the GPU each frame), and to let a lighting console drive a sketch, channels read in `draw()` or bound to a `@Param`
- [`Syphon`](./Integration/Syphon.md) - `import OllinSyphon` to share live visuals with other Mac apps (openFrameworks, Resolume, MadMapper, VDMX, …): publish a sketch's frames as a Syphon source, and draw an incoming Syphon feed as an `Image`
- [`Virtual camera`](./Integration/VirtualCamera.md) - `import OllinCamera` to feed a sketch's frames to the Ollin Camera system camera, so webcam apps and browser tools (Zoom, OBS, Hydra via `getUserMedia`, …) read the sketch as a live camera
- [`Game controllers`](./Integration/Controller.md) - `import OllinController` to read a game controller in `draw()`: sticks, triggers and buttons on any pad, plus motion and a touchpad on hardware that has them, with several players at once
- [`Screen capture`](./Integration/ScreenCapture.md) - `import OllinScreen` to take any display, app, or window on the Mac as a live GPU-textured frame source, drawn and filtered like any image and read by the vision trackers; the non-cooperative counterpart to Syphon, including the feedback tunnel when a sketch captures the screen it is drawn on

### Vision

- [`Vision`](./Vision/Vision.md) - `import OllinVision` for the Mac's camera (built-in, Continuity, or external) plus Apple's on-device perception, surfaced as typed results you read in `draw()`: eighteen trackers spanning detection (rectangles, barcodes/QR, text/OCR, contours into vector `Shape`s), tracking (a patch you point at, parabolic trajectories, dense optical flow), segmentation (person, subject, and point-prompted mattes and cutouts), pose (face landmarks, hand and body skeletons, the 3D body in meters), classification, saliency, and typed phrases scored against the picture, plus any custom Core ML model

### Video

- [`Video`](./Video/Video.md) - `import OllinVideo` to play a video file into a sketch as a live image: each decoded frame arrives as a GPU texture you draw with `drawImage`, plus a CPU `snapshot()` for pixel reads and analysis
- [`Slit scan`](./Video/SlitScan.md) - `SlitScan`, a rolling frame history read back through a per-pixel time delay: the classic scan, time ripples, displacement maps

### Output

- [`Export`](./Output/Export.md) - save frames as raster (PNG, sequences), motion (video, animated GIF), or vector (SVG for pen plotters, PDF for print)
- [`Path-traced export`](./Output/PathTraced.md) - `--path-traced`: render the same 3D scene offline by tracing light paths, for soft shadows, color bleed, mirror-in-mirror reflections, and a real lens
- [`Recording`](./Output/Recording.md) - record a live run as it happens, picture and the sketch's own sound (or the room) in one movie, in real time
- [`Fabrication`](./Output/Fabrication.md) - write a `Mesh` as STL, OBJ, or 3MF for 3D printing, with real units and a printability check
- [`Installation`](./Output/Installation.md) - leave a piece running for days: full screen, no pointer, a clock that survives a week, a watch that starts it again, and the building's hours
- [`Screen saver`](./Output/ScreenSaver.md) - wrap a sketch as the machine's screen saver: one command writes the project, one script installs it, and the sketch stays an ordinary sketch
- [`Print separations`](./Output/PrintSeparations.md) - split a sketch into per-ink grayscale masters for risograph and screen printing, with an overprint preview and registration marks
- [`Spatial`](./Output/Spatial.md) - write a 3D frame or a `Scene` as USDZ, so a piece opens in Quick Look, sends in a message, and stands on a real table through AR; and write the motion as spatial video, a stereo pair per frame for a headset

### Tools

- [`Project generator`](./Tools/ProjectGenerator.md) - `ollin new` and `ollin generate`: a ready-to-run sketch folder from a few questions, with templates you can watch running before you pick one
- [`Single-file sketches`](./Tools/SingleFile.md) - the `ollin` command: run one `.swift` file as a sketch from anywhere, no package needed
- [`Live coding`](./Tools/LiveCoding.md) - the OllinLiveCoding performance host: write and evaluate sketch code live, with the code shown over the visuals
- [`Bringing a shader over`](./Tools/ShaderImport.md) - `ollin new --from-shader`: translate a GLSL fragment shader into Metal and get a project around it
- [`Bringing a scene over`](./Tools/SceneImport.md) - `ollin new --from-scene`: a glTF or USD scene written out as the camera, lights and placement calls that draw it
- [`Writing an extension`](./Tools/Extensions.md) - `ollin new --kind extension`: a library other sketches import, the `ollinx-` naming convention, and the seams to build on
- [`Profiling`](./Tools/Profiling.md) - the inspector's cost row: CPU against GPU on one scale, the draw and pass counts, and a frame handed to Xcode

Coordinates use a **top-left origin with y increasing downward**, the same as p5, Processing, and OPENRNDR.
