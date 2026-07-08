#### <sup>[Ollin](../README.md) → [Guide](README.md) → Appendix D</sup>

---

# D. The complete toolbox

Everything Ollin can do, one line each. The guide teaches by building pieces, which means some capabilities get a chapter and others only a sentence; this appendix is the guarantee that nothing shipped goes unmentioned. Each row says what a capability is in plain words, where the guide works with it, and where its full reference lives in [`Docs/`](../Docs/README.md).

Use it two ways: as an index ("I remember the guide showing blur somewhere"), and as a map of what you haven't tried yet. If something you want isn't in these tables, it isn't in the framework yet; the [roadmap](../ROADMAP.md) is the list of what's ahead.

**Contents:** [The sketch and its window](#the-sketch-and-its-window) · [Drawing](#drawing) · [Color](#color) · [Text and images](#text-and-images) · [Geometry you can hold](#geometry-you-can-hold) · [Motion, math, and randomness](#motion-math-and-randomness) · [Generative systems](#generative-systems) · [Physics](#physics) · [Layers and effects](#layers-and-effects) · [Shaders and compute](#shaders-and-compute) · [3D](#3d) · [Sculpting with fields](#sculpting-with-fields) · [Depth and the phone](#depth-and-the-phone) · [Sound and control](#sound-and-control) · [Seeing and video](#seeing-and-video) · [Sharing and performing](#sharing-and-performing)

## The sketch and its window

| Capability | What it is | Guide | Reference |
|---|---|---|---|
| The sketch lifecycle | `setup()` once, `draw()` every frame, at the display's rate | [Ch 1](01-HelloOllin.md) | [Sketch](../Docs/Core/Sketch.md) |
| The clock | `time`, `deltaTime`, `frameCount`, `frameRate`; `noLoop()` for stills | [Ch 1](01-HelloOllin.md), [Ch 3](03-MotionAndTime.md) | [Sketch](../Docs/Core/Sketch.md) |
| Canvas and window | `canvasSize` presets, `windowMode` (auto, fixed, resizable) | [Ch 1](01-HelloOllin.md) | [Canvas](../Docs/Core/Canvas.md) |
| Mouse | `mouseX`/`mouseY`, pressed state, press and release hooks | [Ch 1](01-HelloOllin.md) | [Input](../Docs/Helpers/Input.md) |
| Keyboard | `key`, typed `KeyCode`, `isKeyDown(_:)`, press and release hooks | [Ch 1](01-HelloOllin.md) | [Input](../Docs/Helpers/Input.md) |
| `@Param` knobs | Properties as live inspector controls, typed per value (slider, color well, pad, …) | [Ch 1](01-HelloOllin.md), [Ch 20](20-SoundAndControl.md) | [Parameters](../Docs/Helpers/Parameters.md) |
| Live reload | `swift run OllinLive Sketch.swift`: save the file, the window swaps the change in | [Ch 1](01-HelloOllin.md) | [Sketch](../Docs/Core/Sketch.md) |
| The examples gallery | `swift run OllinExamples`: every example, browsable, with knobs | [Ch 1](01-HelloOllin.md) | [`Examples/`](../Examples/README.md) |
| Swift itself | The language at sketch speed | [Appendix A](A-JustEnoughSwift.md) | [Swift quick reference](../Docs/Swift.md) |

## Drawing

| Capability | What it is | Guide | Reference |
|---|---|---|---|
| The shape catalog | Circles, rects, lines, arcs, stars, rings, hearts, n-gons, and a few dozen more | [Ch 1](01-HelloOllin.md) | [Drawing](../Docs/Drawing/Drawing.md) |
| Ink state | `fill`, `stroke`, `strokeWeight`, caps and joins, `hollow` band mode, stroke alignment | [Ch 1](01-HelloOllin.md) | [Drawing](../Docs/Drawing/Drawing.md) |
| Transforms and the state stack | `translate`/`rotate`/`scale`, scoped with `withState { }` | [Ch 6](06-GridsAndRepetition.md) | [Drawing](../Docs/Drawing/Drawing.md) |
| Blend modes | Add, subtract, multiply, screen, lightest, darkest, as drawing state | [Ch 14](14-LayersAndEffects.md) | [Drawing](../Docs/Drawing/Drawing.md) |
| Accumulation | `noClear()`: a persistent canvas that piles up across frames | [Ch 14](14-LayersAndEffects.md), [Ch 16](16-Simulations.md) | [Accumulation](../Docs/Drawing/Accumulation.md) |
| HDR and tone mapping | Light past full brightness, brought back by `toneMap` (clamp, Reinhard, ACES) | [Ch 14](14-LayersAndEffects.md) | [HDR](../Docs/Drawing/HDR.md) |
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
| Drawing text | `drawText` with size, alignment, metrics, wrapping, and on-path layout | [Ch 7](07-WordsAndPictures.md) | [Text](../Docs/Drawing/Text.md) |
| Three font kinds | Outline (any installed font), bitmap, and plotter stroke fonts | [Ch 7](07-WordsAndPictures.md) | [Text](../Docs/Drawing/Text.md) |
| Text as geometry | `textToShapes`: letters become `Shape`s you can warp, resample, and rebuild | [Ch 7](07-WordsAndPictures.md) | [Text](../Docs/Drawing/Text.md) |
| Atlas text | `textMode(.atlas)` for fast, crisp text when there's a lot of it | [Ch 7](07-WordsAndPictures.md) | [Text](../Docs/Drawing/Text.md) |
| Images | Load PNG/JPEG/HEIC and friends, draw, tint, and scale them | [Ch 7](07-WordsAndPictures.md) | [Images](../Docs/Drawing/Images.md) |
| Pixels | Read and write any pixel with `image[x, y]`; build images from scratch | [Ch 7](07-WordsAndPictures.md) | [Images](../Docs/Drawing/Images.md) |

## Geometry you can hold

| Capability | What it is | Guide | Reference |
|---|---|---|---|
| Vectors | `Vector2`/`Vector3` with real operators, length, normalize, lerp, rotate | [Ch 8](08-Vectors.md), [Ch 17](17-3DGently.md) | [Geometry](../Docs/Drawing/Geometry.md) |
| Rectangles and circles | Typed regions with fitting, insetting, and hit testing | [Ch 8](08-Vectors.md) | [Geometry](../Docs/Drawing/Geometry.md) |
| `Grid` | Rows, columns, padding, and gutters without nested-loop boilerplate | [Ch 6](06-GridsAndRepetition.md) | [Geometry](../Docs/Drawing/Geometry.md) |
| Paths, shapes, and contours | Curved outlines you build, hold, edit, and respace with `resampled` | [Ch 13](13-ShapesAsMaterial.md) | [Geometry](../Docs/Drawing/Geometry.md) |
| Shape booleans and offsets | Union, intersect, subtract, xor; grow and shrink regions | [Ch 13](13-ShapesAsMaterial.md) | [Geometry](../Docs/Drawing/Geometry.md) |
| Stroke as shape | Turn any stroked line into a filled region for booleans and plotting | [Ch 13](13-ShapesAsMaterial.md) | [Geometry](../Docs/Drawing/Geometry.md) |
| SVG import | Vector artwork read into shapes: draw it as authored, or mine it as geometry | [Ch 13](13-ShapesAsMaterial.md) | [SVG](../Docs/Drawing/SVG.md) |
| Convex hull | The rubber band around a point set | [Ch 13](13-ShapesAsMaterial.md) | [Geometry](../Docs/Drawing/Geometry.md) |
| Voronoi and Delaunay | Territories and neighbor networks from points, with Lloyd relaxation | [Ch 13](13-ShapesAsMaterial.md) | [Voronoi](../Docs/Drawing/Voronoi.md) |

## Motion, math, and randomness

| Capability | What it is | Guide | Reference |
|---|---|---|---|
| Everyday math | `map`, `lerp`, `dist`, `clamp`, `fract`, `step`, `smoothstep`, `.tau` | [Ch 3](03-MotionAndTime.md) | [Math](../Docs/Helpers/Math.md) |
| Loop phases | `loopProgress` and `pingPong`: the sketch clock as a 0…1 cycle | [Ch 3](03-MotionAndTime.md) | [Math](../Docs/Helpers/Math.md) |
| Easing | The curve catalog, plus `@Eased` values that glide to what you assign | [Ch 3](03-MotionAndTime.md) | [Animation](../Docs/Helpers/Animation.md) |
| Smoothing | `@Smoothed` calms jittery inputs (mouse, sensors, knobs) as they arrive | [Ch 3](03-MotionAndTime.md) | [Animation](../Docs/Helpers/Animation.md) |
| `Timeline` | Keyframes with per-segment easing, for choreographed sequences | [Ch 3](03-MotionAndTime.md) | [Animation](../Docs/Helpers/Animation.md) |
| Random | Seeded `random`, Gaussian, choices (plain and weighted), shuffles | [Ch 4](04-Randomness.md) | [Random](../Docs/Generators/Random.md) |
| Noise | `noise`, `signedNoise`, seamless `loop:` variants, layered `fbm`, `curlNoise` | [Ch 5](05-Noise.md), [Ch 12](12-FieldsAndFlow.md) | [Noise](../Docs/Generators/Noise.md) |

## Generative systems

| Capability | What it is | Guide | Reference |
|---|---|---|---|
| Blue noise | Poisson-disk scatter: random but even | [Ch 13](13-ShapesAsMaterial.md) | [BlueNoise](../Docs/Generators/BlueNoise.md) |
| Circle packing | Grow-to-touch packings, seeded and reproducible | [Ch 13](13-ShapesAsMaterial.md) | [Packing](../Docs/Generators/Packing.md) |
| Shape packing | Packing that nestles arbitrary outlines into notches and gaps | [Ch 13](13-ShapesAsMaterial.md) | [ShapePacking](../Docs/Generators/ShapePacking.md) |
| Truchet tiles | One tile per cell at random spins; loops and mazes emerge | [Ch 6](06-GridsAndRepetition.md) | [Truchet](../Docs/Drawing/Truchet.md) |
| L-systems | Grammar rewriting walked by a turtle: ferns, trees, lichens | [Ch 11](11-GrowingThings.md) | [LSystem](../Docs/Generators/LSystem.md) |
| Wave Function Collapse | Socketed tiles solved by constraint propagation | [Ch 11](11-GrowingThings.md) | [WaveFunctionCollapse](../Docs/Generators/WaveFunctionCollapse.md) |
| Flow fields | Direction fields, streamlines (free and evenly spaced), advection | [Ch 12](12-FieldsAndFlow.md) | [FlowField](../Docs/Generators/FlowField.md) |
| Flocking | Boids from separation, alignment, and cohesion, with field joins | [Ch 10](10-FlocksAndSwarms.md) | [Boids](../Docs/Generators/Boids.md) |
| Steering vehicles | Seek, flee, arrive, pursue, wander, follow, contain: composable forces | [Ch 10](10-FlocksAndSwarms.md) | [Steering](../Docs/Generators/Steering.md) |
| Differential growth | A line that folds into coral as it grows | [Ch 10](10-FlocksAndSwarms.md) | [DifferentialGrowth](../Docs/Generators/DifferentialGrowth.md) |
| Space colonization | Branching growth toward attraction points: veins and venation | [Ch 11](11-GrowingThings.md) | [SpaceColonization](../Docs/Generators/SpaceColonization.md) |
| Diffusion-limited aggregation | Walkers that freeze on contact into dendrites and frost | [Ch 11](11-GrowingThings.md) | [DiffusionLimitedAggregation](../Docs/Generators/DiffusionLimitedAggregation.md) |
| Strange attractors | Lorenz, Clifford, de Jong, and friends, as orbits you draw | [Ch 12](12-FieldsAndFlow.md) | [Attractors](../Docs/Drawing/Attractors.md) |

## Physics

| Capability | What it is | Guide | Reference |
|---|---|---|---|
| Soft physics | Verlet particles and springs: cloth, blobs, ropes, with disk collisions | [Ch 9](09-ForcesAndPhysics.md) | [Physics](../Docs/Simulation/Physics.md) |
| Rigid physics | Bodies, colliders, and joints in the same `World`: stacks, chains, machines | [Ch 9](09-ForcesAndPhysics.md) | [Physics](../Docs/Simulation/Physics.md) |
| Grabbing | `grab`: pick up any rigid body with the mouse | [Ch 9](09-ForcesAndPhysics.md) | [Physics](../Docs/Simulation/Physics.md) |

## Layers and effects

| Capability | What it is | Guide | Reference |
|---|---|---|---|
| Render targets | Off-screen layers: draw into them with `withTarget`, composite back | [Ch 14](14-LayersAndEffects.md) | [Effects](../Docs/Drawing/Effects.md) |
| The filter catalog | ~55 GPU filters: blurs, glows, color, stylize, retro, distortion, design | [Ch 14](14-LayersAndEffects.md) | [Effects](../Docs/Drawing/Effects.md) |
| Generator fills | Procedural patterns into layers: design patterns, pattern fields, fractals | [Ch 14](14-LayersAndEffects.md), [Ch 16](16-Simulations.md) | [Effects](../Docs/Drawing/Effects.md) |
| The compose DSL | `compose { layer { } … }`: a stack of layers, filters, and blends in one block | [Ch 14](14-LayersAndEffects.md) | [Effects](../Docs/Drawing/Effects.md) |
| Combines | Two-layer ops: mask, displace, mix, depth-of-field, SSAO, reflections | [Ch 14](14-LayersAndEffects.md), [Ch 17](17-3DGently.md) | [Effects](../Docs/Drawing/Effects.md) |
| Feedback | A layer that remembers last frame: trails, tunnels, video feedback | [Ch 14](14-LayersAndEffects.md) | [Effects](../Docs/Drawing/Effects.md) |
| Simulation fields | Game of Life, Gray-Scott reaction-diffusion, and real-time fluid you seed by drawing | [Ch 16](16-Simulations.md) | [Effects](../Docs/Drawing/Effects.md) |

## Shaders and compute

| Capability | What it is | Guide | Reference |
|---|---|---|---|
| User shaders | Write `shade(uv, info)`; run it as a generator, filter, or two-input combine | [Ch 15](15-YourFirstShader.md) | [Shaders](../Docs/Shaders/Shaders.md) |
| The shader library | Hashing, noise, SDFs, palettes, OKLab, spliced into every shader and kernel | [Ch 15](15-YourFirstShader.md) | [ShaderLibrary](../Docs/Shaders/ShaderLibrary.md) |
| Visual chains | Fluent per-pixel composition: oscillators, warps, blends, modulation, one pass | [Ch 15](15-YourFirstShader.md) | [Visuals](../Docs/Shaders/Visuals.md) |
| Compute kernels | Your own GPU code over buffers and textures, hot-reloadable | [Ch 16](16-Simulations.md) | [Compute](../Docs/Shaders/Compute.md) |
| GPU particles | A million particles updated and drawn without touching the CPU | [Ch 16](16-Simulations.md) | [Compute](../Docs/Shaders/Compute.md) |
| GPU simulations | Ping-pong texture simulations drawn as images | [Ch 16](16-Simulations.md) | [Compute](../Docs/Shaders/Compute.md) |

## 3D

| Capability | What it is | Guide | Reference |
|---|---|---|---|
| The camera | `camera()`, `perspective`, `ortho`; 2D sketches never pay for it | [Ch 17](17-3DGently.md) | [3D](../Docs/3D/3D.md) |
| Solid primitives | Box, sphere, torus, knots, Platonic solids, lathes, extrusions, and more | [Ch 17](17-3DGently.md) | [3D](../Docs/3D/3D.md) |
| Meshes from file | OBJ, glTF, USDZ, STL, PLY, with materials and textures | [Ch 17](17-3DGently.md) | [3D](../Docs/3D/3D.md) |
| Lights | Directional, point, spot, ambient, plus curated lighting presets | [Ch 17](17-3DGently.md) | [3D](../Docs/3D/3D.md) |
| Materials | Stylized finishes (toon, iridescent, velvet, sparkle) and physically based metal and gloss | [Ch 17](17-3DGently.md), [Ch 18](18-SculptingWithFields.md) | [3D](../Docs/3D/3D.md) |
| Matcaps | Sphere-texture shading: chrome, clay, car paint, in one call | [Ch 17](17-3DGently.md) | [3D](../Docs/3D/3D.md) |
| Environments | HDRI image-based lighting, bundled and downloadable, plus a procedural sky | [Ch 18](18-SculptingWithFields.md) | [3D](../Docs/3D/3D.md) |
| Shadows | Cast shadows with a softness dial, ray-traced for point lights on capable GPUs | [Ch 17](17-3DGently.md) | [3D](../Docs/3D/3D.md) |
| Ray-traced reflections | Metals that reflect the actual scene, off-screen parts included | [Ch 18](18-SculptingWithFields.md) | [3D](../Docs/3D/3D.md) |
| Wireframe and textures | Any mesh as line work; any mesh wrapped in an image | [Ch 17](17-3DGently.md) | [3D](../Docs/3D/3D.md) |
| Point clouds | Instanced splats by the hundred thousand, camera-facing | [Ch 19](19-DepthAndThePhone.md) | [3D](../Docs/3D/3D.md) |
| Camera control and moves | Viewer orbiting, cinematic `CameraMove`s, the self-driving showcase, snap views | [Ch 17](17-3DGently.md) | [Camera](../Docs/3D/Camera.md) |
| Scene chrome | The axis widget and ground grid, live-only, never exported | [Ch 17](17-3DGently.md) | [Camera](../Docs/3D/Camera.md) |
| Depth compositing | 2D drawing placed *inside* the 3D depth buffer; billboards; depth feeds | [Ch 19](19-DepthAndThePhone.md) | [DepthCompositing](../Docs/3D/DepthCompositing.md) |
| What stacks with what | The compatibility map across the 3D features | [Ch 17](17-3DGently.md), [Ch 18](18-SculptingWithFields.md) | [Combining](../Docs/3D/Combining.md) |

## Sculpting with fields

| Capability | What it is | Guide | Reference |
|---|---|---|---|
| 2D SDF combinators | Shapes as distance fields that merge, melt, morph, and repeat | [Ch 18](18-SculptingWithFields.md) | [Combinators](../Docs/Drawing/Combinators.md) |
| The `sculpt { }` block | Add, carve, and blend region shapes with stateful verbs, built for live coding | [Ch 18](18-SculptingWithFields.md) | [Combinators](../Docs/Drawing/Combinators.md) |
| Raymarched 3D fields | `SDF3D` sphere-traced through the camera, depth-composited with meshes | [Ch 18](18-SculptingWithFields.md) | [Combinators](../Docs/Drawing/Combinators.md) |

## Depth and the phone

| Capability | What it is | Guide | Reference |
|---|---|---|---|
| RGBD frames | Color plus depth plus intrinsics; unproject any pixel to a metric point | [Ch 19](19-DepthAndThePhone.md) | [RGBD](../Docs/3D/RGBD.md) |
| Recorded captures | Open `.r3d` depth recordings as point clouds with true intrinsics | [Ch 19](19-DepthAndThePhone.md) | [Record3D](../Docs/3D/Record3D.md) |
| Live USB depth | A tethered phone's RGBD stream, frame by frame | [Ch 19](19-DepthAndThePhone.md) | [Record3D](../Docs/3D/Record3D.md) |
| The capture app | Ollin's own iPhone app streams body, face, LiDAR depth, segmentation, and motion | [Ch 19](19-DepthAndThePhone.md) | [Phone](../Docs/3D/Phone.md) |
| World fusion | Sweep the phone; frames fuse into one fixed world cloud by pose | [Ch 19](19-DepthAndThePhone.md) | [Phone](../Docs/3D/Phone.md) |

## Sound and control

| Capability | What it is | Guide | Reference |
|---|---|---|---|
| Audio analysis | Amplitude, spectrum, waveform, log-spaced bands ready to draw | [Ch 20](20-SoundAndControl.md) | [Audio](../Docs/Helpers/Audio.md) |
| Beat detection | Onsets as events: `beat`, `beatCount`, `timeSinceBeat` | [Ch 20](20-SoundAndControl.md) | [Audio](../Docs/Helpers/Audio.md) |
| Audio sources | Microphone, audio files (export-reproducible), test tones, a video's soundtrack | [Ch 20](20-SoundAndControl.md), [Ch 21](21-Seeing.md) | [Audio](../Docs/Helpers/Audio.md) |
| MIDI | Knobs, notes, and messages from hardware controllers, in and out | [Ch 20](20-SoundAndControl.md) | [MIDI](../Docs/Integration/MIDI.md) |
| OSC | Network control messages from tablets, DAWs, and other machines | [Ch 20](20-SoundAndControl.md) | [OSC](../Docs/Integration/OSC.md) |
| Parameter binding | One `@Param` driven by MIDI, OSC, and the inspector alike, with smoothing | [Ch 20](20-SoundAndControl.md) | [Parameters](../Docs/Helpers/Parameters.md) |

## Seeing and video

| Capability | What it is | Guide | Reference |
|---|---|---|---|
| Camera feeds | The webcam (or any frame source) drawn and analyzed live | [Ch 21](21-Seeing.md) | [Vision](../Docs/Vision/Vision.md) |
| People trackers | Faces with landmarks, hands, 2D and 3D body poses, person segmentation | [Ch 21](21-Seeing.md) | [Vision](../Docs/Vision/Vision.md) |
| Scene trackers | Contours, rectangles, barcodes, text (OCR), saliency, classification, subject lift | [Ch 21](21-Seeing.md) | [Vision](../Docs/Vision/Vision.md) |
| Motion trackers | Object tracking, thrown-object trajectories, dense optical flow | [Ch 21](21-Seeing.md) | [Vision](../Docs/Vision/Vision.md) |
| `ModelTracker` | Bring any Core ML model: classifiers, detectors, segmenters | [Ch 21](21-Seeing.md) | [Vision](../Docs/Vision/Vision.md) |
| Still analysis | Every tracker also runs one-shot on an `Image` | [Ch 21](21-Seeing.md) | [Vision](../Docs/Vision/Vision.md) |
| Video playback | Files as live textures: play, seek, loop, analyze, all export-reproducible | [Ch 21](21-Seeing.md) | [Video](../Docs/Video/Video.md) |

## Sharing and performing

| Capability | What it is | Guide | Reference |
|---|---|---|---|
| Stills and sequences | `--export` a frame, `--export-sequence` a folder of them | [Ch 22](22-SharingAndPerforming.md) | [Export](../Docs/Output/Export.md) |
| Video and GIF | `--export-video` (H.264, HEVC, ProRes) and `--export-gif`, deterministic | [Ch 3](03-MotionAndTime.md), [Ch 22](22-SharingAndPerforming.md) | [Export](../Docs/Output/Export.md) |
| Perfect loops | Declare `loopDuration` and `--export-loop` renders exactly one seamless lap | [Ch 3](03-MotionAndTime.md) | [Export](../Docs/Output/Export.md) |
| SVG for plotters | `--export-svg` true vectors, with `--hatch` turning fills into line work | [Ch 13](13-ShapesAsMaterial.md), [Ch 22](22-SharingAndPerforming.md) | [Export](../Docs/Output/Export.md) |
| Headless capture | Render any sketch to an image in code, no window | [Ch 22](22-SharingAndPerforming.md) | [Export](../Docs/Output/Export.md) |
| Syphon | Publish frames to (and read frames from) other Mac apps, GPU to GPU | [Ch 22](22-SharingAndPerforming.md) | [Syphon](../Docs/Integration/Syphon.md) |
| Virtual camera | Your sketch as a system-wide webcam every video app can pick | [Ch 22](22-SharingAndPerforming.md) | [VirtualCamera](../Docs/Integration/VirtualCamera.md) |
| Live coding | `swift run OllinLiveCoding`: code over visuals, evaluate mid-motion, perform | [Ch 22](22-SharingAndPerforming.md) | [LiveCoding](../Docs/Tools/LiveCoding.md) |
| Extensions | `Sketch.extend`: hooks before, during, and after each frame, for recorders and chrome | here | [Sketch](../Docs/Core/Sketch.md#extensions) |

---

[Contents](README.md#contents)
