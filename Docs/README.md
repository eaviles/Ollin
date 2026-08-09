#### <sup>[Ollin](../README.md) → Documentation</sup>

---

## Ollin API

Reference for Ollin's drawing surface and helpers. The bare calls you write in `draw()` forward to an internal `Drawer` (see [How it works](../README.md#how-it-works)), and everything here is callable bare inside a `Sketch`.

New to Swift? Start with the [Swift quick reference](./Swift.md), which covers just enough of the language to be productive in `draw()`. Coming from p5.js or Processing? [Appendix C of the Guide](../Guide/C-ComingFromP5.md) maps the API you already know onto Ollin.

### Core

- [`Sketch`](./Core/Sketch.md) - the lifecycle (`setup`/`draw`), temporal state (`time`, `frameCount`, …), and loop control
- [`Canvas`](./Core/Canvas.md) - `scale`, the `canvasSize` export presets, and the preview window (`windowMode`)
- [`Variations`](./Core/Variations.md) - `variation`, the seed a run grew from: step, roll, and jump through a sketch's variation space in the inspector, proof a range as a contact sheet (`--export-grid`), and re-render a keeper with `--seed`

### Drawing

- [`Drawing`](./Drawing/Drawing.md) - `background`, `fill`/`stroke`, the shapes, and the transform stack
- [`Accumulation`](./Drawing/Accumulation.md) - `noClear` to keep the canvas across frames so drawing piles up (long exposures, paint-on-canvas, light accumulation)
- [`HDR & tone-mapping`](./Drawing/HDR.md) - `toneMap` to roll bright, out-of-range light off the screen instead of clipping it (the linear-float pipeline behind every frame; the glow/bloom and sandpainting looks)
- [`Retained batches`](./Drawing/Batches.md) - `makeBatch`/`drawBatch` to record heavy static drawing once and replay it each frame from the GPU for (almost) nothing, the draw-time transform placing or stamping the whole recording
- [`Layered effects`](./Drawing/Effects.md) - `renderTarget`/`withTarget` to draw into off-screen layers, `filtered`/`postProcess` to run GPU filters (blur, bloom, color grade, gradient map, edges, halftone, …) over them, composited back with blend modes; `combined` to combine two layers (mask, displace, mix, depth-of-field defocus); `generate` for procedural pattern sources, `feedback` for trails and tunnels, and `compose { }` (with `aside` helper layers) to declare a stack of layers as one block
- [`Marks`](./Drawing/Marks.md) - `StrokeMark`/`drawMark` and `StrokeDynamics`: width and opacity driven by how a mark is being made (how fast the pointer moves, how hard it is pressed) rather than by where you are along the path
- [`Text`](./Drawing/Text.md) - `drawText` with bitmap, outline (`.ttf`/`.otf`), and stroke (single-line / plotter) fonts, plus `textToShapes` (text as geometry)
- [`Images`](./Drawing/Images.md) - `loadImage`, `drawImage`, `tint`, and pixel access: load or author a raster image, draw it scaled or transformed, recolor it
- [`Glyph mosaic`](./Drawing/GlyphMosaic.md) - `drawGlyphMosaic`, an image rebuilt as a grid of text glyphs, each cell's character chosen by its measured ink in the active font
- [`Halftone`](./Drawing/Halftone.md) - `drawHalftone`, an image rebuilt as the classic print dot screen: area-exact dots on a rotated grid, real circles for the plotter path
- [`Pixel sorting`](./Drawing/PixelSorting.md) - `Image.pixelSorted`, brightness-bounded runs of an image's own pixels reordered along rows or columns (the classic glitch melt)
- [`Color`](./Drawing/Color.md) - the `Color` type, the OKLab family and mixing, `Ramp`s and `Palette`s (loaded from a file or extracted from an image), dithering an image down to a palette, and perceptual `Colormap`s
- [`Geometry`](./Drawing/Geometry.md) - the `Vector2`, `Rectangle`, `Grid`, `Shape`/`Contour`, and `Path` value types (including the `Grid` layout helper, curved outlines, shape booleans, and offsetting)
- [`SVG import`](./Drawing/SVG.md) - `loadSVG`/`drawSVG` to read vector artwork into `Shape`s and `Contour`s (paths with curves and arcs, the basic shapes, groups and transforms, fills and strokes), ready for booleans, offsets, hatching, and re-export
- [`Fourier epicycles`](./Drawing/Epicycles.md) - `Epicycles` + `drawEpicycles`: rebuild any closed outline as a chain of spinning circles, with a term-count dial from soft phantom to exact trace
- [`Classic curves`](./Drawing/Curves.md) - the closed-form curve canon as geometry builders: `phyllotaxis`, `lissajous`, `rose`, `hypotrochoid`/`epitrochoid` (the spirograph gears), the damped-pendulum `Harmonograph`, and Chaikin `smoothed(iterations:)` corner cutting
- [`Shape morphing`](./Drawing/Morphing.md) - `ShapeMorph`: tween one `Shape` into another with every in-between a real vector shape (contour pairing, corner-keeping correspondence, holes that grow in and out); `Shape` is `Tweenable`, so a `Timeline` sequences geometry
- [`Voronoi & Delaunay`](./Drawing/Voronoi.md) - tessellate points into vector geometry: Voronoi cells (the "crystallization" look) and the dual Delaunay triangle mesh, with Lloyd relaxation
- [`Truchet tiling`](./Drawing/Truchet.md) - one tile per grid cell spun to a random orientation, so identical parts line up into flowing loops (`.arcs`) or a maze (`.diagonals`)
- [`Tiling & layout`](./Drawing/Tiling.md) - the other ways to divide a canvas: `HexGrid`/`TriangleGrid` (the hex and triangle tilings, with hex distance, neighbors, and exact picking), `subdivide` (recursive panels, binary or quadtree), `Maze` (three carving algorithms, walls as clean line-work, solution and longest paths), and `apollonianGasket` (the kissing-circles foam)
- [`Aperiodic tilings`](./Drawing/AperiodicTilings.md) - the tilings that never repeat: `penroseTiling` (kites and darts, rhombs, with the matching-rule arcs), `wangTiling` (edge-matching squares as one connected quilt), `girihPattern` (Islamic star patterns over any polygons, plus the five girih tiles), and `spectreTiling` (the einstein, straight or strictly chiral curved)
- [`Strange attractors`](./Drawing/Attractors.md) - chaotic systems as points: continuous 3D orbits (Lorenz, Rössler, Aizawa, …) integrated with Runge-Kutta and orbited through the camera, 2D iterated maps (Clifford, de Jong, Hénon) accumulated into density fields, and `AttractorFlow`, a million GPU particles riding one field at once
- [`SDF combinators`](./Drawing/Combinators.md) - compose signed-distance fields so shapes *merge* instead of stack: smooth union/subtract/intersect and morph, round/onion, and domain mirror/tile, via the `SDF` value type + `drawSDF` and a scoped `smoothUnion { }` block, in 2D and a raymarched 3D form (`SDF3D` + `drawSDF3D`)

### Shaders

Writing GPU code yourself: fragment shaders run through the effect graph, compute kernels over buffers and textures, and the helper library both draw from.

- [`Shaders`](./Shaders/Shaders.md) - write your own fragment shader (`Shader` + a `shade(uv, info)` function) and run it through the effect graph as a generator, filter, or combine, with a built-in shader library and line-accurate compile errors
- [`Visuals`](./Shaders/Visuals.md) - compose animated imagery by chaining (`Visual`): sources (oscillator, noise, voronoi, shape) through warps, color moves, blends, and modulations, the whole chain compiling into a single GPU pass with every number animatable for free
- [`Shader library`](./Shaders/ShaderLibrary.md) - reference for the helper functions a fragment shader or compute kernel can call: color/OKLab, hashes, value/gradient/curl noise, the 2D signed-distance catalog (`smin`, `sdEllipse`, `sdHeart`, …), and the repeat/mirror/polar domain operators
- [`Compute & GPU particles`](./Shaders/Compute.md) - GPU compute over buffers and textures: `Particles` (a million updated and drawn on the GPU each frame, the "sandpainting" engine) and `Simulation` (reaction-diffusion, cellular automata, and other ping-pong texture sims), over the `ComputeKernel`/`ComputeBuffer`/`ComputeTexture` core (with the shared shader library spliced into every kernel)

### 3D

- [`3D`](./3D/3D.md) - opt into a 3D camera and depth buffer: orbit a `Camera3D` (perspective or orthographic) and draw `PointCloud`s as instanced disc splats and a catalog of solid primitives (box, sphere, capsule, the Platonic solids, …) plus parametric and profile shapes (supershape, extrude, lathe), meshes loaded from file (`.obj`, `.usdz`/`.stl`/`.ply`, `.gltf`/`.glb`), textured surfaces, and a live webcam depth cloud
- [`Scenes`](./3D/Scenes.md) - `loadScene` keeps a glTF or USD file's *structure* instead of merging it: a tree of named nodes drawn in place with `drawScene`, reached by name to animate (`scene["lamp"]`), opening on the authored camera and punctual lights as ready `Camera3D`/`Light` values, and playing the file's authored keyframe animations on the sketch clock (`apply(_:at:)`)
- [`Combining 3D features`](./3D/Combining.md) - the practical map of what stacks with what: which geometry takes lights, materials, matcaps, and environment light; who casts, receives, and appears in shadows and reflections; when to reach for screen-space versus ray-traced reflections; and a step-by-step recipe for the most realistic scene
- [`Camera control`](./3D/Camera.md) - move the camera by hand (`cameraControl()`: drag to orbit, scroll to dolly, right or modifier-drag to pan, damped) or play a ready-made cinematic move (`cameraMove(_:)`: turntable, push-in, tilt, orbit-and-rise, reveal, handheld), both opt-in over the orbit pose
- [`Atmosphere`](./3D/Atmosphere.md) - give the air a presence: `fog` fades surfaces with distance and pools low with a height falloff (exact closed-form transmittance), and `volumetricLight` marches the air so spot cones, cookies, IES profiles, and cast shadows become visible beams and crepuscular shafts
- [`Depth compositing`](./3D/DepthCompositing.md) - place 2D drawing *inside* a 3D scene so it occludes and is occluded by the geometry: `depth(at:)`, `project`, and `withBillboard` (a 2D label hidden when it swings behind the cloud)
- [`Record3D`](./3D/Record3D.md) - `import OllinRecord3D` to turn an iPhone's color-plus-depth into a 3D point cloud, from a recorded `.r3d` file or a tethered phone's live USB stream
- [`RGBD`](./3D/RGBD.md) - the source-agnostic `RGBDFrame` (color + depth + intrinsics) any depth source produces: unproject a point cloud, lift a single image point to metric 3D, or lift a 2D body pose into space (`Body.lifted(through:)`)
- [`Phone`](./3D/Phone.md) - `import OllinPhone` to read a tethered iPhone's live on-device ARKit sensor stream from Ollin's own capture app: a 3D body skeleton, a face mesh with expression blendshapes, world-facing rear-LiDAR depth (a metric point cloud with the camera's 6DoF pose), and device motion, over the USB cable

### Generators

- [`Random`](./Generators/Random.md) - `random`, `randomGaussian`, and the `randomVector`/`ring` scatter helpers
- [`Noise`](./Generators/Noise.md) - Perlin `noise` / `signedNoise`, seamlessly looping `noise(loop:)`, layered `fbm`, and `curlNoise` flow fields
- [`Blue noise`](./Generators/BlueNoise.md) - `poissonDisk`, an even-but-organic scatter with no clumps or gaps (Poisson-disk sampling)
- [`Low-discrepancy sampling`](./Generators/LowDiscrepancy.md) - `haltonPoints` / `sobolPoints`, even coverage as an ordered stream: growing the count only adds points, never moves them
- [`Stippling`](./Generators/Stippling.md) - `stipple`, dots packed to reproduce an image's tone (weighted-Voronoi stippling), or any density function
- [`Fractals`](./Generators/Fractals.md) - `IFS` chaos games, `FractalFlame` renders, circle-inversion limit sets, and Kleinian limit-set curves, plus the `fitted` placement helper
- [`Chaotic maps & bifurcation`](./Generators/Bifurcation.md) - `IteratedMap`, the one-dimensional route to chaos: logistic, sine, tent, and Gauss families, orbits and cobweb staircases, the bifurcation diagram as dots or a density image, and Lyapunov exponents
- [`Single line`](./Generators/SingleLine.md) - `singleLine`, one continuous tour through an image's stipple (TSP art), a plotter-friendly `Contour`
- [`Spanning tree`](./Generators/SpanningTree.md) - `spanningTree`, the minimum spanning tree of an image's stipple: the branching, vein-like sibling of the single line
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
- [`Terrain`](./Generators/Terrain.md) - `Heightfield`, landscapes from noise or `diamondSquare`, weathered by droplet hydraulic and thermal erosion, emitted as terrain meshes, heightmaps, and contours
- [`Random walks`](./Generators/Walks.md) - `randomWalk` / `levyFlight` / `selfAvoidingWalk`, paths built one random step at a time: the local tangle, the cluster-and-leap, and the never-crossing single stroke
- [`Circle packing`](./Generators/Packing.md) - `packCircles` and `relaxCircles`, filling a region with non-overlapping circles that grow until they touch
- [`L-systems`](./Generators/LSystem.md) - `drawLSystem` and a preset catalog: a rewriting grammar walked by a turtle into fractal curves and branching plants
- [`Differential growth`](./Generators/DifferentialGrowth.md) - `DifferentialGrowth`, a line of nodes that grows and folds into organic, brain-coral structure (a stateful stepper)
- [`Wave Function Collapse`](./Generators/WaveFunctionCollapse.md) - `wfc`, filling a grid from a tileset so every neighbor is legal (constraint-solved tile layouts)
- [`Cellular automata`](./Generators/CellularAutomata.md) - `elementaryCA`/`totalisticCA` rule-by-number row stacks, and `Turmite` walkers (Langton's ant and friends) painting a wrapped grid
- [`Shape packing`](./Generators/ShapePacking.md) - `packShapes` and `ContinuousPacking`, filling a region with non-overlapping shapes grown against each other's outlines
- [`Flow fields`](./Generators/FlowField.md) - `FlowField`, tracing streamlines through a direction field (the flow-field look) and advecting particles along it
- [`Flocking`](./Generators/Boids.md) - `Boids`, a flock steering by separation/alignment/cohesion into emergent flocking motion
- [`Steering`](./Generators/Steering.md) - `Vehicle`, a creature moved by composable steering forces (seek, flee, arrive, pursue, wander, follow a path or flow field)
- [`Space colonization`](./Generators/SpaceColonization.md) - `SpaceColonization`, branching growth (veins, roots, trees) toward scattered attraction points (a stateful stepper)
- [`Diffusion-limited aggregation`](./Generators/DiffusionLimitedAggregation.md) - `DiffusionLimitedAggregation`, dendritic clusters frozen out of random walkers (frost and coral, a stateful stepper)

### Helpers

- [`Math`](./Helpers/Math.md) - `map`, `dist`, `lerp`, the shaping scalars (`clamp`/`fract`/`step`/`smoothstep`), and `Double.tau`
- [`Animation`](./Helpers/Animation.md) - looping progress (`loopProgress`/`pingPong`), the `Easing` curves, `@Eased` (ease toward a target), `@Smoothed` (smooth a noisy signal), `@Sprung` (spring toward a target with momentum), and the `Timeline` keyframe sequencer
- [`Parameters`](./Helpers/Parameters.md) - `@Param` tunable knobs: typed inspector controls (from sliders and toggles to menus, color wells, text, and geometry fields) in grouped cards, value scrubbing, optional smoothing, and binding from OSC or MIDI
- [`Input`](./Helpers/Input.md) - mouse and keyboard
- [`Data`](./Helpers/Data.md) - `loadTable` for CSV and TSV files (typed reads by column name) and `loadJSON` for documents you reach through by name and index
- [`Audio`](./Helpers/Audio.md) - `import OllinAudio` for microphone, file, and oscillator sources, analyzed into `amplitude`/`spectrum`/band values you read in `draw()`
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
- [`Syphon`](./Integration/Syphon.md) - `import OllinSyphon` to share live visuals with other Mac apps (openFrameworks, Resolume, MadMapper, VDMX, …): publish a sketch's frames as a Syphon source, and draw an incoming Syphon feed as an `Image`
- [`Virtual camera`](./Integration/VirtualCamera.md) - `import OllinCamera` to feed a sketch's frames to the Ollin Camera system camera, so webcam apps and browser tools (Zoom, OBS, Hydra via `getUserMedia`, …) read the sketch as a live camera
- [`Screen capture`](./Integration/ScreenCapture.md) - `import OllinScreen` to take any display, app, or window on the Mac as a live GPU-textured frame source, drawn and filtered like any image and read by the vision trackers; the non-cooperative counterpart to Syphon, including the feedback tunnel when a sketch captures the screen it is drawn on

### Vision

- [`Vision`](./Vision/Vision.md) - `import OllinVision` for the Mac's camera (built-in, Continuity, or external) plus Apple's on-device perception, surfaced as typed results you read in `draw()`: sixteen trackers spanning detection (rectangles, barcodes/QR, text/OCR, contours into vector `Shape`s), tracking (a patch you point at, parabolic trajectories, dense optical flow), segmentation (person and subject mattes and cutouts), pose (face landmarks, hand and body skeletons, the 3D body in meters), classification, and saliency, plus any custom Core ML model

### Video

- [`Video`](./Video/Video.md) - `import OllinVideo` to play a video file into a sketch as a live image: each decoded frame arrives as a GPU texture you draw with `drawImage`, plus a CPU `snapshot()` for pixel reads and analysis
- [`Slit scan`](./Video/SlitScan.md) - `SlitScan`, a rolling frame history read back through a per-pixel time delay: the classic scan, time ripples, displacement maps

### Output

- [`Export`](./Output/Export.md) - save frames as raster (PNG, sequences), motion (video, animated GIF), or vector (SVG for pen plotters, PDF for print)
- [`Fabrication`](./Output/Fabrication.md) - write a `Mesh` as STL, OBJ, or 3MF for 3D printing, with real units and a printability check
- [`Print separations`](./Output/PrintSeparations.md) - split a sketch into per-ink grayscale masters for risograph and screen printing, with an overprint preview and registration marks

### Tools

- [`Single-file sketches`](./Tools/SingleFile.md) - the `ollin` command: run one `.swift` file as a sketch from anywhere, no package needed
- [`Live coding`](./Tools/LiveCoding.md) - the OllinLiveCoding performance host: write and evaluate sketch code live, with the code shown over the visuals

Coordinates use a **top-left origin with y increasing downward**, the same as p5, Processing, and OPENRNDR.
