#### <sup>[Ollin](../README.md) → Documentation</sup>

---

## Ollin API

This is the reference for Ollin's drawing surface and helpers. The bare calls you write in `draw()` forward to an internal `Drawer` (see [How it works](../README.md#how-it-works)). Everything on these pages is callable bare inside a `Sketch`.

If you are new to Swift, start with the [Swift quick reference](./Swift.md). It covers just enough of the language to be productive in `draw()`. If you come from p5.js or Processing, [Appendix C of the Guide](../Guide/C-ComingFromP5.md) maps the API you already know onto Ollin.

### Concepts

Each concept page is one screen on an idea that the reference pages below assume. Read one when you want the reason behind an API rather than its signature.

- [`The frame`](./Concepts/Frame.md) - what a drawing call does, and what happens between `draw()` and the picture
- [`Where a point is`](./Concepts/Coordinates.md) - the canvas coordinates and their units, and the other coordinate frames a sketch meets
- [`Layers`](./Concepts/Layers.md) - what an off-screen layer is, what it costs, and when you need one
- [`What survives a frame`](./Concepts/Persistence.md) - what Ollin keeps between frames and what it drops: state, the canvas, layers, batches, saved values
- [`Why a run repeats`](./Concepts/Determinism.md) - the seed and the clock, and what makes a sketch draw the same picture twice
- [`Light and color`](./Concepts/Light.md) - why color mixes in linear light, and what the last pass of a frame does
- [`Values and bare calls`](./Concepts/Values.md) - the typed values under `drawCircle(x, y, r)`, and when to use them

### Core

- [`Sketch`](./Core/Sketch.md) - the lifecycle (`setup`/`draw`), the clock values (`time`, `frameCount`, …), and loop control
- [`Canvas`](./Core/Canvas.md) - `scale`, the `canvasSize` export presets, and the preview window (`windowMode`)
- [`Variations`](./Core/Variations.md) - `variation`, the seed a run starts from. Step, roll, and jump through a sketch's variation space in the inspector. Proof a range as a contact sheet (`--export-grid`), and render the one you want to keep again with `--seed`.
- [`Replay`](./Core/Replay.md) - record a run's seed, clock, inputs, and parameter changes as a take (`--record-take`). Play it back exactly (`--replay`, with transport keys), scrub through it, and render the performance again through any export flag.
- [`Automation`](./Core/Automation.md) - keyframed parameters. A parameter's values are written down over time (`automate`) and joined by named or Bezier curves. The result loops, plays at any speed, reads from a file (`--automation`), and renders exactly in any export.

### Drawing

- [`Drawing`](./Drawing/Drawing.md) - `background`, `fill`/`stroke`, the shapes, the transform stack, and the views over it (`withClip`, `withViewBox`, `viewControl`)
- [`Accumulation`](./Drawing/Accumulation.md) - `noClear` keeps the canvas across frames, so drawing builds up (long exposures, paint on canvas). `Accumulator` is a layer that keeps the running mean, so a picture built from faint samples converges.
- [`Depth of field from light`](./Drawing/DepthOfField.md) - `LineSpray` and `Bokeh`. Lines are drawn as millions of scattered points through a lens and added into a running mean until bokeh appears. The `.light` particle style and the `develop` print filter are the parts underneath.
- [`HDR & tone mapping`](./Drawing/HDR.md) - `toneMap` rolls bright, out-of-range light off instead of clipping it. The page also covers the linear-float pipeline behind every frame, and the glow/bloom and sandpainting looks built on it.
- [`Wide gamut & HDR output`](./Drawing/ColorOutput.md) - `colorOutput` to present through Display P3 and keep highlights brighter than white, `Color(displayP3:)` for colors outside sRGB, and HDR10 video export
- [`Retained batches`](./Drawing/Batches.md) - `makeBatch` records heavy static drawing once, and `drawBatch` replays it each frame from the GPU at almost no cost. The transform in force at draw time places or stamps the whole recording.
- [`Layered effects`](./Drawing/Effects.md) - `renderTarget`/`withTarget` draw into off-screen layers. `filtered`/`postProcess` run GPU filters over them (blur, bloom, color grade, gradient map, edges, halftone, …), and the result composites back with blend modes. `combined` joins two layers (mask, displace, mix, depth-of-field defocus). `generate` makes procedural pattern sources, `feedback` makes trails and tunnels, and `simField` runs the stateful sims (reaction-diffusion, Game of Life, fluid, the self-warp motion feedback, …). `compose { }` (with `aside` helper layers) declares a stack of layers as one block.
- [`Marks`](./Drawing/Marks.md) - `StrokeMark`/`drawMark` and `StrokeDynamics`. Width and opacity follow how a mark is being made, rather than where you are along the path. That means how fast the pointer moves and how hard it is pressed.
- [`Text`](./Drawing/Text.md) - `drawText` with bitmap, outline (`.ttf`/`.otf`), and stroke (single-line / plotter) fonts, plus `textToShapes` (text as geometry) and text in any script (right-to-left, Devanagari, Thai, Japanese, emoji)
- [`Images`](./Drawing/Images.md) - `loadImage`, `drawImage`, `tint`, and pixel access. Load or build a raster image, draw it scaled or transformed, and recolor it.
- [`Glyph mosaic`](./Drawing/GlyphMosaic.md) - `drawGlyphMosaic` rebuilds an image as a grid of text glyphs. Each cell's character is chosen by its measured ink in the active font.
- [`Halftone`](./Drawing/Halftone.md) - `drawHalftone` rebuilds an image as the classic print dot screen: area-exact dots on a rotated grid, drawn as real circles for the plotter path.
- [`Autostereogram`](./Drawing/Autostereogram.md) - `Image.autostereogram` hides a depth map in a repeating pattern. When the eyes pair the repeats, a surface that was never drawn stands out of the page.
- [`Photo mosaic`](./Drawing/PhotoMosaic.md) - `Image.mosaic` + `averageColor` + `drawMosaic` rebuild a picture out of many smaller pictures. Each cell takes the picture whose average color is nearest, measured in linear light.
- [`Pixel sorting`](./Drawing/PixelSorting.md) - `Image.pixelSorted` reorders runs of an image's own pixels along rows or columns, with each run bounded by brightness (the classic glitch melt).
- [`Seam carving`](./Drawing/SeamCarving.md) - `Image.seamCarved` and `SeamMap` resize a picture by removing the paths through it that matter least, so what matters keeps its shape. Masks can hold something still or remove it.
- [`Color`](./Drawing/Color.md) - the `Color` type, the OKLab family and mixing, `Ramp`s and `Palette`s (loaded from a file or extracted from an image), dithering an image down to a palette, and perceptual `Colormap`s
- [`Spectral color`](./Drawing/Spectrum.md) - `Spectrum`, the reflectance curve behind a color. It covers `.paint` mixing (Kubelka-Munk, with pigments meeting in green), filtering light by multiplication, `Color(wavelength:)` and blackbody glow, and the spectral GPU effects (`.thinFilm`, `.diffraction`, `.paintMix`).
- [`Geometry`](./Drawing/Geometry.md) - the `Vector2`, `Vector3`, `Rotation3D`, `Ray3`, `Rectangle`, `Grid`, `Shape`/`Contour`, and `Path` value types (including the `Grid` layout helper, curved outlines, shape booleans, and offsetting)
- [`SVG import`](./Drawing/SVG.md) - `loadSVG`/`drawSVG` read vector artwork into `Shape`s and `Contour`s: paths with curves and arcs, the basic shapes, groups and transforms, fills and strokes. The result is ready for booleans, offsets, hatching, and re-export.
- [`Fourier epicycles`](./Drawing/Epicycles.md) - `Epicycles` + `drawEpicycles` rebuild any closed outline as a chain of spinning circles. A term-count dial runs from a soft approximation to an exact trace.
- [`Envelopes & caustics`](./Drawing/Envelopes.md) - `envelope` + `caustic`. An envelope is the curve a family of lines is tangent to, and a caustic is the bright curve where reflected or bent light gathers.
- [`Classic curves`](./Drawing/Curves.md) - the classic closed-form curves as geometry builders: `phyllotaxis`, `lissajous`, `rose`, `superellipse`, `supershape`, `hypotrochoid`/`epitrochoid` (the spirograph gears), `guilloche` (the twisted, cam-shaped rings of a rose engine), the damped-pendulum `Harmonograph`, `spirolateral` (a walk of growing steps repeated until it returns to its start), and Chaikin `smoothed(iterations:)` corner cutting
- [`Anamorphosis`](./Drawing/Anamorphosis.md) - `Anamorphosis`, a plate that reads correctly only in a mirrored cylinder standing on the page, seen from one viewing spot. It covers the wrap at true size, the map for points, contours, and shapes, the part of a cylinder an eye can see, and the search that reads a plate back.
- [`Clothoid`](./Drawing/Clothoid.md) - the curve whose bend grows at a steady rate (the Euler or Cornu spiral). It gives the easement that joins a straight run to a turn with no kink, and the single curve that fits two points and two headings. It also gives a smooth path through waypoints, and polyline corners a vehicle could drive.
- [`Shape morphing`](./Drawing/Morphing.md) - `ShapeMorph` tweens one `Shape` into another, and every in-between is a real vector shape (contour pairing, corner-keeping correspondence, holes that grow in and out). `Shape` is `Tweenable`, so a `Timeline` can sequence geometry.
- [`Voronoi & Delaunay`](./Drawing/Voronoi.md) - tessellate points into vector geometry: Voronoi cells (the "crystallization" look) and the dual Delaunay triangle mesh, with Lloyd relaxation and weighted power diagrams
- [`Spatial index`](./Drawing/SpatialIndex.md) - `SpatialIndex`, the structure that answers what is near a point without reading every point. It finds the nearest point, the k nearest, everything within a radius, and everything inside a box, over a uniform grid or a k-d tree.
- [`Fitting`](./Drawing/Fitting.md) - `RadialBasis`, a smooth field of numbers, vectors, or colors fitted through values you know at a few scattered places (a field of vectors also works as a warp). `Fit.minimize` walks a few parameters downhill against a cost function you write.
- [`Truchet tiling`](./Drawing/Truchet.md) - one tile per grid cell, turned to a random orientation, so identical parts join into flowing loops (`.arcs`) or a maze (`.diagonals`)
- [`Hitomezashi stitching`](./Drawing/Hitomezashi.md) - one bit per grid line sets the phase of its dashes, and the shifted lines weave into staircases, loops, and a two-tone cloth
- [`Ten print`](./Drawing/TenPrint.md) - `tenPrint`, one of two diagonals per cell chosen by a coin flip, joined into the long connected paths the picture is known for
- [`Kolam and sona`](./Drawing/Kolam.md) - one line launched between a field of dots and bounced off the edges until it closes. The result is gcd(rows, columns) loops, and walls can steer the line.
- [`Celtic knotwork`](./Drawing/Knotwork.md) - the same line given width and an alternating over-under rule, returned already broken where each cord passes under another
- [`Crease patterns`](./Drawing/CreasePattern.md) - the flat sheet a folded or cut object comes from: the Miura fold with its rigid folding in three dimensions, rotating-squares kirigami, and Kawasaki's and Maekawa's laws, which say whether a sheet can fold flat
- [`Tiling & layout`](./Drawing/Tiling.md) - the other ways to divide a canvas: `HexGrid`/`TriangleGrid` (the hex and triangle tilings, with hex distance, neighbors, and exact picking), `subdivide` (recursive panels, binary or quadtree), `Maze` (three carving algorithms, walls as clean line work, solution and longest paths), and `apollonianGasket` (the packing of kissing circles, each touching its neighbors)
- [`Aperiodic tilings`](./Drawing/AperiodicTilings.md) - the tilings that never repeat: `penroseTiling` (kites and darts, rhombs, with the matching-rule arcs), `wangTiling` (edge-matching squares as one connected quilt), `girihPattern` (Islamic star patterns over any polygons, plus the five girih tiles), and `spectreTiling` (the einstein tile, straight or strictly chiral curved)
- [`Parquet deformations`](./Drawing/ParquetDeformation.md) - `parquetDeformation` draws a tiling whose tile changes shape as you read across it. The geometry lives on the lattice's shared edges, so a square becomes an interlocking key with nothing coming apart on the way.
- [`Hyperbolic tiling`](./Drawing/HyperbolicTiling.md) - regular tilings of the hyperbolic plane in the Poincaré disk. `hyperbolicTiling` takes any {p,q} with (p-2)(q-2) > 4 and returns typed tiles with depth and a two-coloring parity, and a `viewpoint` pans across the endless tiling.
- [`Strange attractors`](./Drawing/Attractors.md) - chaotic systems as points. Continuous 3D orbits (Lorenz, Rössler, Aizawa, …) are integrated with Runge-Kutta and orbited by the camera. Iterated 2D maps (Clifford, de Jong, Hénon, Gumowski-Mira, Ikeda, hopalong) accumulate into density fields, and `AttractorFlow` moves a million GPU particles through one field at once.
- [`SDF combinators`](./Drawing/Combinators.md) - compose signed-distance fields so shapes *merge* instead of stacking: smooth union/subtract/intersect and morph, round/onion, and domain mirror/tile. The `SDF` value type + `drawSDF` and a scoped `smoothUnion { }` block do this in 2D, and `SDF3D` + `drawSDF3D` do it in a raymarched 3D form.
- [`Measured distance fields`](./Drawing/DistanceFields.md) - measure a distance field back out of a drawn layer with `Filter.distanceField`: how far every pixel is from the nearest edge, and in which direction. `Filter.fieldMap` reads it back as contours, grown and shrunk shapes, and outlines, or a shader reads it as a Voronoi keyed to the picture.
- [`The frequency domain`](./Drawing/Fourier.md) - a picture read as a sum of waves instead of a grid of pixels. `Filter.fourier` writes the spectrum on the GPU and `.inverseFourier` reads it back. Filtering by *scale* is then a shape drawn over the spectrum, and a field can be built from nothing but a description of its energy.
- [`Light in a flat sketch`](./Drawing/Light.md) - `Combine.light` computes the light that reaches every pixel of a flat scene. Draw the scene in one layer and the lights in another. One measurement (radiance cascades) then gives you shadows that soften with distance, falloff, light through a gap, and the color a lit wall gives back.
- [`Local averages`](./Drawing/LocalAverages.md) - the average of the neighborhood around every pixel at a fixed cost, over a summed-area table. `Filter.boxBlur` costs the same at any radius, and `Filter.adaptiveThreshold` cuts a picture to two tones against each pixel's own surroundings, so uneven light no longer matters.

### Shaders

These pages cover writing GPU code yourself. They describe fragment shaders that run through the effect graph, compute kernels over buffers and textures, and the helper library that both draw from.

- [`Shaders`](./Shaders/Shaders.md) - write your own fragment shader (`Shader` + a `shade(uv, info)` function) and run it through the effect graph as a generator, filter, or combine. A built-in shader library and line-accurate compile errors come with it.
- [`Visuals`](./Shaders/Visuals.md) - compose animated imagery by chaining a `Visual`: sources (oscillator, noise, voronoi, shape) pass through warps, color moves, blends, and modulations. The whole chain compiles into a single GPU pass, and every number in it can animate at no extra cost.
- [`Shader library`](./Shaders/ShaderLibrary.md) - reference for the helper functions a fragment shader or compute kernel can call: color/OKLab, hashes, value/gradient/curl noise, the 2D signed-distance catalog (`smin`, `sdEllipse`, `sdHeart`, …), and the repeat/mirror/polar domain operators
- [`Compute & GPU particles`](./Shaders/Compute.md) - GPU compute over buffers and textures. `Particles` updates and draws a million particles on the GPU each frame (the "sandpainting" engine), and `Simulation` runs reaction-diffusion, cellular automata, and other ping-pong texture sims. Both sit over the `ComputeKernel`/`ComputeBuffer`/`ComputeTexture` core, and the shared shader library is spliced into every kernel.

### 3D

- [`3D`](./3D/3D.md) - opt into a 3D camera and depth buffer. Orbit a `Camera3D` (perspective or orthographic) and draw `PointCloud`s as instanced disc splats. There is a catalog of solid primitives (box, sphere, capsule, the Platonic solids, …), plus parametric and profile shapes (supershape, extrude, lathe). Meshes load from file (`.obj`, `.usdz`/`.stl`/`.ply`, `.gltf`/`.glb`). They can be textured and surface-mapped with normal, metallic-roughness, occlusion, emissive, and height maps. A height map gives parallax occlusion and real displacement. Triplanar projection covers meshes with no uvs, and detail maps add close-up texture. Projected decals stamp across every surface a box touches, and a live webcam depth cloud is included.
- [`Scenes`](./3D/Scenes.md) - `loadScene` keeps a glTF or USD file's *structure* instead of merging it. You get a tree of named nodes, drawn in place with `drawScene` and reached by name to animate (`scene["lamp"]`). The file's authored camera and punctual lights come out as ready `Camera3D`/`Light` values, and `apply(_:at:)` plays the file's authored keyframe animations on the sketch clock.
- [`Instanced meshes`](./3D/Instancing.md) - draw one mesh thousands of times in one call. `drawMesh(_:instances:)` takes a list of `MeshInstance` placements (position, rotation, scale, tint) that the GPU applies per copy. It can also take a `ComputeBuffer` that a kernel writes, so a simulation moves the copies without the CPU. Copies shade like solid meshes and cast into the shadow maps. A retained `MeshField` scales this to a whole world drawn by one call, with each copy GPU-culled against the camera.
- [`The Hopf fibration`](./3D/HopfFibration.md) - a sphere's worth of circles, where no two circles meet and every two are linked exactly once. `hopfFibers` returns them as `[Vector3]` paths for `drawTube`, and `hopfBases` supplies the structured base sets (rings of latitude, or a spiral) that make the linking easy to see.
- [`Strand fields`](./3D/Strands.md) - grass that a mesh pipeline grows inside the draw call itself. `StrandField` + `drawStrands` draw half a million bending, swaying blades with no vertex or instance buffer anywhere. The blades are tile-culled by the camera, detail-graded by distance, and shaded and shadow-receiving on the solid lit path.
- [`The ocean`](./3D/Ocean.md) - a sea built the way the ocean is measured. `oceanField` writes a wave spectrum, and one inverse Fourier transform turns it into the moving surface. `drawOcean` draws it as water with no geometry anywhere, and `waveHeight` is a measurement in world units rather than a dial.
- [`Combining 3D features`](./3D/Combining.md) - the practical map of what works with what: which geometry takes lights, materials, matcaps, and environment light; what casts, receives, and appears in shadows and reflections; when to use screen-space reflections and when ray-traced ones; and a step-by-step recipe for the most realistic scene
- [`Camera control`](./3D/Camera.md) - move the camera by hand (`cameraControl()`: drag to orbit, scroll to dolly, right-drag or modifier-drag to pan, all damped) or play a ready-made cinematic move (`cameraMove(_:)`: turntable, push-in, tilt, orbit-and-rise, reveal, handheld). Both are opt-in over the orbit pose.
- [`Caustics`](./3D/Caustics.md) - the light that glass and metal focus. `caustics()` photon-traces the caster light through every transmissive and mirror-polished surface and draws where it lands. As a result, a glass sphere throws its bright spot into its own shadow, a chrome ring folds light beside itself, and `dispersion:` fans out a prism's rainbow. It needs a ray-tracing GPU.
- [`Lens flare`](./3D/LensFlare.md) - the light the camera itself adds to a picture. `lensFlare()` works out the ghosts a real lens prescription makes of each bright source. It places and sizes them, shapes them by the iris blades, and colors them by the anti-reflective coating. The star on the source itself has as many arms as those blades. All of it fades as something covers the source, rather than switching off.
- [`Atmosphere`](./3D/Atmosphere.md) - the air between the camera and the scene. `fog` fades surfaces with distance and pools low with a height falloff (exact closed-form transmittance). `aerialPerspective` splits the fade by wavelength and lights it with the sun, so far ridges turn blue and fade into the sky. `volumetricLight` marches the air, so spot cones, cookies, IES profiles, and cast shadows become visible beams and crepuscular shafts.
- [`Depth compositing`](./3D/DepthCompositing.md) - place 2D drawing *inside* a 3D scene, so it occludes the geometry and is occluded by it: `depth(at:)`, `project`, and `withBillboard` (a 2D label hidden when it swings behind the cloud)
- [`Record3D`](./3D/Record3D.md) - `import OllinRecord3D` turns an iPhone's color-plus-depth into a 3D point cloud, from a recorded `.r3d` file or a tethered phone's live USB stream
- [`RGBD`](./3D/RGBD.md) - the one `RGBDFrame` (color + depth + intrinsics) that any depth source produces. Unproject it to a point cloud, lift a single image point to metric 3D, or lift a 2D body pose into space (`Body.lifted(through:)`).
- [`Phone`](./3D/Phone.md) - `import OllinPhone` reads a tethered iPhone's live on-device ARKit sensor stream from Ollin's own capture app, over the USB cable. The stream carries a 3D body skeleton, a face mesh with expression blendshapes, and the hands in view as 21-joint skeletons lifted to metric 3D. It also carries the recognized text lines with their corners lifted to 3D, world-facing rear-LiDAR depth (a metric point cloud with the camera's 6DoF pose), the reconstructed room as a labeled surface, a person matte, and device motion.

### Generators

- [`Random`](./Generators/Random.md) - `random`, `randomGaussian`, and the `randomVector`/`ring` scatter helpers
- [`Noise`](./Generators/Noise.md) - Perlin `noise` / `signedNoise`, seamlessly looping `noise(loop:)`, layered `fbm`, and `curlNoise` flow fields
- [`Blue noise`](./Generators/BlueNoise.md) - `poissonDisk`, an even but organic scatter with no clumps or gaps (Poisson-disk sampling)
- [`Low-discrepancy sampling`](./Generators/LowDiscrepancy.md) - `haltonPoints` / `sobolPoints`, even coverage as an ordered stream: growing the count only adds points and never moves them
- [`Points on a surface`](./Generators/SurfaceSampling.md) - `surfacePoints`, points scattered over a mesh's surface rather than its vertex list. They are evenly spaced by default, and each carries the normal, texture coordinate, and triangle it landed on.
- [`Stippling`](./Generators/Stippling.md) - `stipple`, dots packed to reproduce an image's tone (weighted-Voronoi stippling) or any density function
- [`De Bruijn sequences`](./Generators/DeBruijn.md) - `deBruijnSequence` + `DeBruijnCode`, a cyclic sequence that holds every window of a given length exactly once, so a glimpse of a few symbols tells you where it came from
- [`Ford circles`](./Generators/FordCircles.md) - `fordCircles`, a circle for every fraction, each touching its neighbors and overlapping nothing, built over `fareySequence` and the exact `Fraction` type
- [`Shadow art`](./Generators/ShadowArt.md) - `shadowArt`, a solid carved so that it throws the silhouettes you ask for, with the shadows it really casts so you can compare them
- [`Polyominoes`](./Generators/Polyominoes.md) - `Polyomino` + `tilePolyominoes`, the twelve pentominoes and an exact-cover search that fits a bag of pieces into a region, or reports that no fit exists
- [`Ulam spiral`](./Generators/UlamSpiral.md) - `ulamSpiral`, the whole numbers written in a square spiral, so a test on them becomes a picture. The primes fall on diagonals.
- [`Fractals`](./Generators/Fractals.md) - `IFS` chaos games, `FractalFlame` renders, circle-inversion limit sets, and Kleinian limit-set curves, plus the `fitted` placement helper
- [`Chaotic maps & bifurcation`](./Generators/Bifurcation.md) - `IteratedMap`, the one-dimensional route to chaos: the logistic, sine, tent, and Gauss families, orbits and cobweb staircases, the bifurcation diagram as dots or a density image, and Lyapunov exponents
- [`Single line`](./Generators/SingleLine.md) - `singleLine`, one continuous tour through an image's stipple (TSP art), returned as a plotter-friendly `Contour`
- [`Ant colony`](./Generators/AntColony.md) - `AntColony`, a colony that lays pheromone trails and narrows a web of possible routes down to a short tour. The search itself is what you draw.
- [`Spanning tree`](./Generators/SpanningTree.md) - `spanningTree`, the minimum spanning tree of an image's stipple: the branching, vein-like relative of the single line
- [`String art`](./Generators/StringArt.md) - `StringArt`, one continuous thread wound over rim pins until the crossings reproduce a picture (a stateful stepper)
- [`Percolation`](./Generators/Percolation.md) - `Percolation`, site-percolation clusters over a seeded grid: largest-first labeling, the spanning cluster, cell rectangles, and traced boundary loops
- [`Isolines`](./Generators/Isolines.md) - `isolines`, level curves of any scalar field or of an image's tone, by marching squares: from metaball outlines to contour maps
- [`Isosurfaces`](./Generators/Isosurface.md) - `isosurface` / `Metaballs`, the surface where a field over space crosses a level, marched into a `Mesh`: soft spheres that fuse, noise volumes, gyroids
- [`Subdivision surfaces`](./Generators/SubdivisionSurfaces.md) - `mesh.subdivided`, a low-poly control cage refined into a smooth solid by the Catmull-Clark or Loop rules, with welding and open-edge handling built in
- [`Mesh growth`](./Generators/MeshGrowth.md) - `MeshGrowth` / `MeshReactionDiffusion`, a surface that grows more area than it has room for and folds: brain coral, branching coral, a ruffled leaf margin
- [`Surface reconstruction`](./Generators/SurfaceReconstruction.md) - `reconstructSurface` / `particleSurface`, from points back to a `Mesh`. Rebuild a scanned room or object with its holes kept, or skin a particle set as one blended body.
- [`Hulls`](./Generators/Hulls.md) - `concaveHull` / `alphaShape`, two tighter answers to "what shape are these points?": one simple polygon that follows the gulfs, or the scatter's true footprint with islands and holes
- [`Medial axis`](./Generators/MedialAxis.md) - `medialAxis`, a shape reduced to its skeleton, with every point carrying its inscribed-disk radius
- [`Straight skeleton`](./Generators/StraightSkeleton.md) - `straightSkeleton`, the ridge network a shrinking boundary traces, with faces and exact mitered insets (`inset(by:)`). One build gives every topographic contour at once.
- [`Force-directed layout`](./Generators/ForceLayout.md) - `ForceLayout`, a graph that untangles itself: repulsion between all nodes, attraction along edges, and cooling into an even web you can grow, pin, and drag
- [`Marbling`](./Generators/Marbling.md) - `Marbling` / `drawMarbling`, paper marbling in closed form: drops, tines, combs, and swirls rake vector ink outlines into feathered papers
- [`Watercolor shapes`](./Generators/Watercolor.md) - `Watercolor` / `drawWatercolor`, watercolor pigment from recursively deformed polygons stacked as translucent layers
- [`Chladni figures`](./Generators/Chladni.md) - `chladni`, a ringing plate's standing-wave field in closed form, plus the `.chladni` generator's sand and wave readings and the mode-by-pitch join to audio
- [`Billiards`](./Generators/Billiards.md) - `Billiard`, a ball that bounces forever in a circle, an ellipse, a polygon, or a stadium, with posts standing in it. The path comes back as geometry, and the shape of the room decides whether it draws a pattern or fills the floor.
- [`Drainage`](./Generators/Drainage.md) - `Drainage`, rivers computed from a `Heightfield` rather than drawn. Hollows are filled so water always has a way out, and you get flow per cell, the network above a threshold as strokable reaches, Strahler ordering, and basins.
- [`Terrain`](./Generators/Terrain.md) - `Heightfield`, landscapes from noise or `diamondSquare`, weathered by droplet hydraulic and thermal erosion, and emitted as terrain meshes, heightmaps, and contours
- [`Random walks`](./Generators/Walks.md) - `randomWalk` / `levyFlight` / `selfAvoidingWalk`, paths built one random step at a time: the local tangle, the cluster-and-leap, and the single stroke that never crosses itself
- [`Circle packing`](./Generators/Packing.md) - `packCircles` and `relaxCircles`, filling a region with non-overlapping circles that grow until they touch
- [`Shape grammars`](./Generators/ShapeGrammar.md) - `ShapeGrammar`, a design written as rules over labeled shapes: the balanced cut behind the ice-ray lattices, splits for a building front, insets that become bars, and nested turned copies
- [`L-systems`](./Generators/LSystem.md) - `drawLSystem` and a preset catalog: a rewriting grammar that a turtle walks into fractal curves and branching plants, symbolic or parametric (symbols carry numbers, for fractional lengths, delays, and tapering width)
- [`Differential growth`](./Generators/DifferentialGrowth.md) - `DifferentialGrowth`, a line of nodes that grows and folds into an organic, brain-coral structure (a stateful stepper)
- [`Meander`](./Generators/Meander.md) - `Meander`, a river centerline that migrates by curvature, cutting off oxbow lakes and recording scars (a stateful stepper)
- [`Wave Function Collapse`](./Generators/WaveFunctionCollapse.md) - `wfc` fills a grid so every neighbor is legal, from a tileset you declare or from the patches of an example picture (constraint-solved tile layouts, texture synthesis)
- [`Cellular automata`](./Generators/CellularAutomata.md) - `elementaryCA`/`totalisticCA` row stacks chosen by rule number, and `Turmite` walkers (Langton's ant and its relatives) painting a wrapped grid
- [`Shape packing`](./Generators/ShapePacking.md) - `packShapes` and `ContinuousPacking`, filling a region with non-overlapping shapes grown against each other's outlines
- [`Flow fields`](./Generators/FlowField.md) - `FlowField`, streamlines traced through a direction field (the flow-field look) and particles advected along it
- [`Flocking`](./Generators/Boids.md) - `Boids`, a flock that steers by separation, alignment, and cohesion into emergent flocking motion
- [`Pursuit`](./Generators/Pursuit.md) - `Pursuit`, runners that head straight at each other and leave logarithmic spirals: the ring of mice, and a quarry that runs straight (a stateful stepper)
- [`Steering`](./Generators/Steering.md) - `Vehicle`, a creature moved by composable steering forces (seek, flee, arrive, pursue, wander, follow a path or flow field)
- [`Space colonization`](./Generators/SpaceColonization.md) - `SpaceColonization`, branching growth (veins, roots, trees) toward scattered attraction points (a stateful stepper)
- [`Diffusion-limited aggregation`](./Generators/DiffusionLimitedAggregation.md) - `DiffusionLimitedAggregation`, branching clusters frozen out of random walkers (frost and coral; a stateful stepper)
- [`Dielectric breakdown`](./Generators/DielectricBreakdown.md) - `DielectricBreakdown`, lightning grown where the solved electric field is strongest. The `eta` exponent sweeps the result from a furry bush to a sparse Lichtenberg arc.
- [`Crack growth`](./Generators/CrackGrowth.md) - `CrackGrowth`, perpendicular cracks that subdivide the plane into city-block cells, each dragging a one-sided watercolor wash (a stateful stepper)

### Helpers

- [`Math`](./Helpers/Math.md) - `map`, `dist`, `lerp`, the shaping scalars (`clamp`/`fract`/`step`/`smoothstep`), and `Double.tau`
- [`Animation`](./Helpers/Animation.md) - looping progress (`loopProgress`/`pingPong`), the timers (`every`/`after`/`everyFrames`), `sway` (a value that travels between two ends and back, over five shapes), the `Easing` curves, `@Eased` (ease toward a target), `@Smoothed` (smooth a noisy signal), `@Sprung` (spring toward a target with momentum), and the `Timeline` keyframe sequencer
- [`Formula`](./Helpers/Formula.md) - a number written as a rule and read from text: `drive($radius, "190 + sin(time) * 80")`. The page covers the arithmetic a formula understands, the clock, canvas, pointer, and other parameters it can name, and the errors it reports rather than throws.
- [`Parameters`](./Helpers/Parameters.md) - `@Param` tunable parameters: typed inspector controls (from sliders and toggles to menus, color wells, text, and geometry fields) in grouped cards (with `.folded` sections that start closed), value scrubbing, optional smoothing, and binding from OSC or MIDI
- [`Input`](./Helpers/Input.md) - mouse and keyboard
- [`Accessibility`](./Helpers/Accessibility.md) - see your colors as the three kinds of color vision see them, check whether a palette's colors stay apart, and read the system's reduce-motion setting
- [`Data`](./Helpers/Data.md) - `loadTable` for CSV and TSV files (typed reads by column name) and `loadJSON` for documents you reach into by name and index
- [`LiveData`](./Helpers/LiveData.md) - `DataFeed`, one address read over and over on a background queue, so a sketch draws what is true now. It covers conditional polling, backoff, and one fixed answer in an export.
- [`Weather`](./Helpers/Weather.md) - `Weather`, the sky over a place or a name as plain readings (temperature, clouds, wind, rain, the condition in a word), and `Place.sun(at:)` for where the sun is, with no network
- [`Audio`](./Helpers/Audio.md) - `import OllinAudio` for microphone, file, and oscillator sources, analyzed into `amplitude`/`spectrum`/band values you read in `draw()`
- [`Listening`](./Helpers/Listening.md) - speech as a caption you can draw and phrases you can act on, plus about 300 everyday sounds named as they happen, over any audio source
- [`Synthesis`](./Helpers/Synthesis.md) - `Synth`, the instrument a sketch plays: notes by name or number, `Voice` presets over a shaped and filtered oscillator, a wavetable read by position, and delay and reverb
- [`Composition`](./Helpers/Composition.md) - working out what to play: Euclidean rhythms, scales and chords, arpeggios, and Markov sequences, as pure values of a step number
- [`Sonification`](./Helpers/Sonification.md) - numbers played as notes: a table column, a terrain profile, or a picture row, spread over a range of pitch and snapped to a scale

### Simulation

- [`Physics`](./Simulation/Physics.md) - `import OllinPhysics` for a `World` you step each frame, so motion comes from simulation. It has a soft Verlet side (particles, springs, disk collisions) and a rigid side (bodies, colliders, joints, backed by Box2D).
- [`Physics3D`](./Simulation/Physics3D.md) - rigid bodies inside the 3D scene. A `World3D` holds stacking, tumbling, swinging `Body3D`s (backed by Jolt), with joints, contacts and sensors, walking characters, driveable vehicles, ragdolls built from a skinned `Scene`, cloth and ropes, mouse grabbing through the camera, and `withBody` drawing.
- [`Swarm`](./Simulation/Swarm.md) - the steering behaviors at GPU scale: separation, alignment, cohesion, seek, flee, arrive, wander, and flow following, as weights over tens or hundreds of thousands of agents
- [`Artificial life`](./Simulation/ArtificialLife.md) - three emergent-behavior systems on the GPU: `ParticleLife`, the `PPS` turning rule, and `Physarum` slime mold. The first two run over a GPU `SpatialHash` neighbor search, which you can also build your own sims on.
- [`Evolution`](./Simulation/Evolution.md) - populations that get better at something. `Evolution` breeds tens of thousands of GPU flights toward a target past obstacles by tournament selection, and `Population` breeds a handful of genomes that a person picks by eye.
- [`Fluids & soft bodies`](./Simulation/Fluids.md) - GPU particle dynamics: `ParticleFluid` (smoothed-particle hydrodynamics) and `SoftBodies` (shape-matched jelly blobs), both in a walled box you can splash and knead with the mouse
- [`Watercolor simulation`](./Simulation/Watercolor.md) - wet paint on rough paper: a three-layer wash simulation (`watercolor(pigments:)`) with real pigment behavior and Kubelka-Munk glazing. Paint with any drawing call, call `dry()` between washes, and call `blot()` for backrun blooms.
- [`Articulated & chaotic motion`](./Simulation/Motion.md) - CPU motion systems you step each frame: `IKChain` (inverse-kinematics tentacles and limbs), `DoublePendulum` (the classic chaos machine), and `NBody` (quadtree gravity for orbits, galaxies, and collisions)

### Integration

- [`OSC`](./Integration/OSC.md) - `import OllinOSC` to send and receive OSC messages over UDP (to and from TouchOSC, Max/MSP, TouchDesigner, …), read in `draw()` or bound to a `@Param`
- [`MIDI`](./Integration/MIDI.md) - `import OllinMIDI` to read from and send to MIDI controllers and keyboards over Core MIDI, read in `draw()` or bound to a `@Param`
- [`Link`](./Integration/Link.md) - `import OllinLink` to join the local network's shared tempo-and-phase session (the Link protocol most music apps support). A sketch then moves on the same beat and lands on the same downbeat as the whole rig, with no cabling or setup.
- [`Serial`](./Integration/Serial.md) - `import OllinSerial` to read a USB microcontroller's sensor lines in `draw()` (or bound to a `@Param`) and write lines back to drive servos and LEDs. It covers IOKit discovery, automatic reconnection, and the classic physical-computing loop.
- [`Bluetooth`](./Integration/Bluetooth.md) - `import OllinBluetooth` to read a Bluetooth Low Energy sensor in `draw()` (or bound to a `@Param`) and write back to it. It covers the devices in range, a connection that waits and returns by itself, the standard's own values already named, and the permission the first run has to get past.
- [`Remote`](./Integration/Remote.md) - `import OllinRemote` to serve the sketch's `@Param` parameters to a phone or a second machine on the local network: a touch surface in any browser, live in both directions, for tuning an installation from in front of it
- [`Room`](./Integration/Room.md) - `import OllinRoom` to let several machines on one network draw one piece. They find each other by the room's name, with no server, and trade values and `@Param` parameters. They agree on one clock so motion stays in step, and each takes a seat when the piece is split across screens.
- [`DMX`](./Integration/DMX.md) - `import OllinDMX` to drive stage lights and dimmers from `draw()` over Art-Net or sACN (a `DMXUniverse` of 512 channels, with a named-fixture shorthand). It also sends the canvas's own pixels to LED strips and matrices (`LEDMap`, sampled on the GPU each frame). A lighting console can drive a sketch too, with channels read in `draw()` or bound to a `@Param`.
- [`Laser`](./Integration/Laser.md) - `import OllinLaser` to draw with a show laser from `draw()`. Line work is optimized into the point stream a projector scans (spacing, corner and blanking dwell, path order, the point budget). An arm gate and a stopped-beam rule guard the output, which is streamed to a network DAC or written as an ILDA file.
- [`Syphon`](./Integration/Syphon.md) - `import OllinSyphon` to share live visuals with other Mac apps (openFrameworks, Resolume, MadMapper, VDMX, …): publish a sketch's frames as a Syphon source, and draw an incoming Syphon feed as an `Image`
- [`Virtual camera`](./Integration/VirtualCamera.md) - `import OllinCamera` to feed a sketch's frames to the Ollin Camera system camera, so webcam apps and browser tools (Zoom, OBS, Hydra via `getUserMedia`, …) read the sketch as a live camera
- [`Game controllers`](./Integration/Controller.md) - `import OllinController` to read a game controller in `draw()`: sticks, triggers, and buttons on any pad, plus motion and a touchpad on hardware that has them, with several players at once
- [`Haptics`](./Integration/Haptics.md) - `import OllinHaptics` to add touch feedback beside the picture. A pattern of taps and hums is composed like a phrase and played from `draw()`. It is translated for the trackpad's three feelings and one strength, and played as written where a full haptic engine exists.
- [`Screen capture`](./Integration/ScreenCapture.md) - `import OllinScreen` to take any display, app, or window on the Mac as a live GPU-textured frame source, drawn and filtered like any image and read by the vision trackers. It is the counterpart to Syphon for apps that do not publish their frames. It also includes the feedback tunnel you get when a sketch captures the screen it is drawn on.

### Vision

- [`Vision`](./Vision/Vision.md) - `import OllinVision` for the Mac's camera (built-in, Continuity, or external) plus Apple's on-device perception, returned as typed results you read in `draw()`. Nineteen trackers cover detection (rectangles, barcodes/QR, text/OCR, contours into vector `Shape`s), tracking (a patch you point at, parabolic trajectories, dense optical flow), and segmentation (person, subject, and point-prompted mattes and cutouts). They also cover pose (face landmarks, hand and body skeletons, the 3D body in meters), classification, saliency, typed phrases scored against the picture, and depth that holds still from a video model, plus any custom Core ML model.

### Video

- [`Video`](./Video/Video.md) - `import OllinVideo` to play a video file into a sketch as a live image. Each decoded frame arrives as a GPU texture you draw with `drawImage`, and a CPU `snapshot()` gives you pixel reads and analysis.
- [`Slit scan`](./Video/SlitScan.md) - `SlitScan`, a rolling frame history read back through a per-pixel time delay: the classic scan, time ripples, displacement maps

### Output

- [`Export`](./Output/Export.md) - save frames as raster (PNG, sequences), motion (video, animated GIF), or vector (SVG for pen plotters, PDF for print)
- [`Web page`](./Output/Web.md) - `--export-web` records what a sketch draws and writes a page that plays it back in a browser, as one self-contained file or as a fragment for a page of your own
- [`Path-traced export`](./Output/PathTraced.md) - `--path-traced` renders the same 3D scene offline by tracing light paths, for soft shadows, color bleed, mirror-in-mirror reflections, and a real lens
- [`Recording`](./Output/Recording.md) - record a live run as it happens, with the picture and the sketch's own sound (or the room's sound) in one movie, in real time
- [`Fabrication`](./Output/Fabrication.md) - write a `Mesh` as STL, OBJ, or 3MF for 3D printing, with real units and a printability check
- [`G-code`](./Output/GCode.md) - write a frame's line work as a program that a pen plotter, laser cutter, or CNC router runs directly
- [`Installation`](./Output/Installation.md) - leave a piece running for days: full screen, no pointer, a clock that survives a week, a watch that restarts it, and the building's hours
- [`A sketch as an app`](./Output/App.md) - wrap a finished piece as a signed, double-clickable Mac app that runs without the toolchain, with a frame of itself as its icon
- [`Screen saver`](./Output/ScreenSaver.md) - wrap a sketch as the machine's screen saver: one command writes the project, one script installs it, and the sketch stays an ordinary sketch
- [`Wallpaper`](./Output/Wallpaper.md) - run a sketch as the desktop wallpaper: one window per display at desktop level, behind the icons, with a menu-bar item to quit it
- [`Menu bar`](./Output/MenuBar.md) - run a sketch as a small live strip among the menu bar's status items, drawn at a rate an all-day surface can afford
- [`Print separations`](./Output/PrintSeparations.md) - split a sketch into per-ink grayscale masters for risograph and screen printing, with an overprint preview and registration marks
- [`Print color`](./Output/PrintColor.md) - soft-proof a canvas against a press profile, flag the colors ink cannot reach, and split it into process-color plates with their total-ink figures
- [`Spatial`](./Output/Spatial.md) - write a 3D frame or a `Scene` as USDZ, so a piece opens in Quick Look, sends in a message, and stands on a real table through AR. Write the motion as spatial video, a stereo pair per frame, for a headset.

### Tools

- [`Project generator`](./Tools/ProjectGenerator.md) - `ollin new` and `ollin generate`: a ready-to-run sketch folder from a few questions, with templates you can watch running before you pick one
- [`Single-file sketches`](./Tools/SingleFile.md) - the `ollin` command: run one `.swift` file as a sketch from anywhere, no package needed
- [`The sketch on the phone`](./Tools/OnThePhone.md) - `ollin phone`: the sketch on a paired iPhone or iPad. It is installed again on every save, with its clock and parameters carried across, and the parameters stay live on the Mac.
- [`Live coding`](./Tools/LiveCoding.md) - the OllinLiveCoding performance host: write and evaluate sketch code live, with the code shown over the visuals
- [`Bringing a shader over`](./Tools/ShaderImport.md) - `ollin new --from-shader`: translate a GLSL fragment shader into Metal and get a project around it
- [`Checking a shader`](./Tools/ShaderCheck.md) - `ollin check`: compile a `.metal` file on this machine's GPU and see the errors at your own line numbers, what kind of shader it is, and the parameters it reads
- [`Bringing a scene over`](./Tools/SceneImport.md) - `ollin new --from-scene`: a glTF or USD scene written out as the camera, lights and placement calls that draw it
- [`Writing an extension`](./Tools/Extensions.md) - `ollin new --kind extension`: a library other sketches import, the `ollinx-` naming convention, and the seams to build on
- [`Dragging a shape`](./Tools/DragToEdit.md) - Command-drag a shape in the live window to move it, drag a corner to resize it, or drag the knob above it to turn it. The numbers in your own file change, with your spacing and comments untouched.
- [`The parameter timeline`](./Tools/Timeline.md) - OllinLive's timeline panel: a lane per automated parameter, keys placed from the inspector's diamonds and dragged by hand, a playhead over the sketch clock, and a round trip to the automation file
- [`The reference offline`](./Tools/Reference.md) - `ollin docs`, `ollin examples`, and `ollin site`: these pages and every example sketch, read in the terminal or written out as a website. They come from the checkout you build against, and a search covers the whole reference
- [`Profiling`](./Tools/Profiling.md) - the inspector's cost row: CPU against GPU on one scale, the draw and pass counts, and a frame handed to Xcode

Coordinates use a **top-left origin with y increasing downward**, the same as p5, Processing, and OPENRNDR. The [Where a point is](./Concepts/Coordinates.md) page covers this in one screen, including the units.
