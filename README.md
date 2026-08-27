# Ollin

**A comprehensive creative-coding framework for Swift, rendered with Metal.**

[Guide](Guide/README.md) · [Docs](Docs/README.md) · [Examples](Examples/) · [Roadmap](ROADMAP.md) · [Architecture](ARCHITECTURE.md)

Ollin is the whole creative-coding toolkit as one typed Swift API. The techniques you reach for are already in it, from Voronoi and L-systems to raymarched signed-distance fields, GPU fluids, and on-device computer vision. The renderer sits directly on Metal and composites in linear light. The tooling around it, live reload and a typed parameter inspector and deterministic headless export, is built for finishing work rather than demoing it.

The API borrows the friendly `setup()`/`draw()` feel of [p5.js](https://p5js.org), the typed core of [OPENRNDR](https://openrndr.org), and the simple structure of [openFrameworks](https://openframeworks.cc), reimplemented in Swift idioms rather than ported (see [Influences & attribution](#influences--attribution)). *Ollin* (OH-leen) is the Aztec glyph for movement, the seventeenth day sign of the calendar.

- **Platform:** macOS 26+, Swift 6+; Apple platforms only, [by design](#why-apple-only)
- **Rendering:** Metal, built on Foundation / SwiftUI / MetalKit / simd; no package dependencies, just a little vendored source ([details](ATTRIBUTION.md#bundled-third-party-code))
- **License:** MIT
- **Built with:** an AI coding assistant (Claude) under [@eaviles](https://github.com/eaviles)'s direction; see [Built with AI](#built-with-ai)

> **Status: alpha, pre-1.0, built in public.** The rendering, the color, and the output are production-grade. The API is not frozen yet. Everything documented below runs today, but names and signatures still change between commits, and there's no stability or support guarantee. See [Status & contributing](#status--contributing).

## Hello, circle

```swift
import Ollin

final class HelloCircle: Sketch {
    override func setup() {
        // optional one-time setup
    }

    override func draw() {
        background(.white)
        noFill()
        stroke(.black)
        strokeWeight(3)
        drawCircle(width / 2, height / 2, 120 + sin(time) * 40)
    }
}

OllinApp.run(HelloCircle())
```

That's the whole program: a black circle outline, breathing on a white canvas. There's no call to start the animation, because the draw loop is already running, and `time` (seconds since start) is ready to use. Delete `+ sin(time) * 40` and you have a still circle.

## Run it

From the terminal, no Xcode required:

```sh
swift run --package-path Examples Example-Basic-HelloCircle
```

That builds the package and opens a window with the breathing circle above. More runnable sketches live in [`Examples/`](Examples/), where `swift run` with no argument lists every example target and `swift run OllinExamples` opens a gallery with all of them in a sidebar.

The canvas is 1080×1080 by default, previewed fit to your screen. `canvasSize` sets the resolution a sketch renders and exports at, and `windowMode` sizes the preview window. The [Canvas](Docs/Core/Canvas.md) page covers the presets and how to write resolution-independent sketches.

### Install

To use Ollin from your own package:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/eaviles/Ollin.git", branch: "main")
],
targets: [
    .executableTarget(
        name: "MySketch",
        dependencies: [.product(name: "Ollin", package: "Ollin")]
    )
]
```

A sketch doesn't need a package at all, though. One loose `.swift` file is a whole sketch: see [Single-file sketches](Docs/Tools/SingleFile.md), or the [Live reload](#live-reload) section below.

## Why Ollin exists

<!--
  PLACEHOLDER: @eaviles to write. Target 150-250 words, three short paragraphs.
  Delete the visible placeholder line below when this is filled in.

  Prompts to answer:
    - What were you making when you hit the wall, and what actually stopped you?
    - Was there a specific moment? A piece you couldn't finish, an export you lost,
      a set that broke mid-performance.
    - What did you get tired of rebuilding?
    - Why Swift, when you already had a working practice somewhere else?
    - Who else do you picture using this?

  Decisions already in the repo that this section can point at, since each one
  only gets made by someone solving a real problem:
    - plotter SVG with hatching, riso separations, true-to-size PDF
        -> the work is meant to end up on paper
    - Syphon both directions, a virtual camera, MIDI clock sync, the live-coding host
        -> the work gets performed, inside a rig other people already run
    - seeds recorded in every export, contact sheets, reproducibility recipes
        -> a good result is worthless if you can't get it back
    - the sheer breadth of the technique catalog
        -> tired of reimplementing the same things before starting
    - sixteen vision trackers and a custom iPhone capture app
        -> the room belongs in the work

  Voice: written as the one first-person section on the page (everything else is
  third person). End it with a short signed line so the shift reads as deliberate.
  If you'd rather keep the whole page third person, rewrite as "@eaviles built..."
  and drop the signature.
-->

> **[Placeholder: the origin story goes here.]**

## What's in it

Coverage is the point. Whatever you reach for is already here, in one typed API, with the same conventions throughout.

- **Built to finish work.** Every frame composites in linear light with HDR tone-mapping, dithered output, analytic anti-aliasing, and up to 8× MSAA. Color is OKLab with real gamut mapping, not HSB approximations. Exports are deterministic and carry a reproducibility recipe: the seed, the parameter values, the commit. Rendering is snapshot-tested against committed reference images.
- **The edit-to-see loop is instant.** `swift run OllinLive Sketch.swift` watches the file and hot-swaps each save into the running window, and a typo never closes it. `@Param` properties become typed inspector controls (sliders, steppers, toggles, menus, color wells, palette and gradient strips) in grouped cards, and they keep their values across reloads. It also reads out [what the frame cost](Docs/Tools/Profiling.md): CPU against GPU, draws, and passes.
- **Live coding on stage.** `swift run OllinLiveCoding` is a performance instrument: the sketch fills the window, the code rides over it as translucent text, and ⌘↩ recompiles the buffer mid-motion, with the clock and tuned knobs carrying across the swap. A typo shows as a strip at the bottom while the last good sketch keeps playing.
- **A Metal core with no ceiling.** Most shapes render as analytic signed-distance fields (one instanced quad each, so thousands of moving shapes stay cheap), strokes carry their own anti-aliasing fringe, frames composite through an [HDR float pipeline](Docs/Drawing/HDR.md), and when you outgrow the built-ins you write your own fragment shader or compute kernel without leaving the framework.
- **Motion is the default, and it's handled.** `draw()` runs at the display's refresh rate from the first line, so `120 + sin(time) * 40` is already an animation. Underneath that sits a real motion layer: frame-rate-independent easing and springs, keyframe timelines, [knobs on their own curves](Docs/Core/Automation.md), input smoothing, noise that closes exactly over a lap, perfect-loop export, and motion locked to MIDI clock.
- **Output that leaves the screen.** Headless PNG stills and deterministic sequences, MP4 and GIF straight from the CLI, vector SVG and PDF with optional hatched fills for pen plotters, [G-code programs](Docs/Output/GCode.md) a pen plotter, laser cutter, or CNC router runs directly, [print separations](Docs/Output/PrintSeparations.md) with a real ink model for riso and screen printing, [print color management](Docs/Output/PrintColor.md) that proofs the canvas against a press profile and splits it into process plates, [fabrication files](Docs/Output/Fabrication.md) (STL, OBJ, 3MF) so a generated mesh can be 3D-printed at a real size, and [spatial output](Docs/Output/Spatial.md): USDZ so a 3D piece opens in Quick Look, sends in a message, and stands on a real table through AR, or spatial video so its motion plays in depth on a headset.

- **Or living in the system.** `ollin new --kind mac-app` wraps a finished piece as a signed, double-clickable [Mac app](Docs/Output/App.md) that runs where the toolchain never was, wearing a frame of itself as its icon; `--kind screen-saver` wraps it as the machine's [screen saver](Docs/Output/ScreenSaver.md), so the work runs when nobody is at the desk; `--kind wallpaper` runs it as the [desktop wallpaper](Docs/Output/Wallpaper.md), behind the icons on every display; and `--kind menu-bar` puts a small live strip of it [in the menu bar](Docs/Output/MenuBar.md), beside the clock all day. One script builds, signs, and installs any of them; the sketch itself stays an ordinary sketch.

- **Made to be left running.** A piece on a wall declares [installation mode](Docs/Output/Installation.md) in one line. The screen fills, the pointer goes, and the display stays awake with the screen saver held off. The clock survives a night of display sleep and a week of running, which is where a long run usually breaks. Mark the state `@Saved` and a relaunch picks the piece up where it was. A watch starts it again after a crash. A schedule gives it the building's hours. Command-K lines the picture up with the wall it is thrown onto, and two projectors can share one wall without a bright bar down the join. One machine can drive both of them, or spread one canvas over every display it has.

### The catalog

Everything below ships in this repository, first-party, with consistent conventions. Each row links to its reference page.

| Area | What's in it |
| --- | --- |
| [**Shapes & geometry**](Docs/Drawing/Drawing.md) | Some thirty analytic shapes from circles to stars to hearts, curved paths, concave and holed fills, variable-width strokes that taper and turn like a nib, [marks](Docs/Drawing/Marks.md) whose width and opacity follow how fast and how hard you drew them, [booleans and offsets](Docs/Drawing/Geometry.md), [spatial queries](Docs/Drawing/SpatialIndex.md) over a point set (what is nearest, what is within reach, what is inside a box), [fitting](Docs/Drawing/Fitting.md) a smooth field through values known at a few scattered places (and the warp that makes) or a handful of knobs to a target, [gradient paint](Docs/Drawing/Geometry.md) on everything, blend modes, clipping, [SVG import](Docs/Drawing/SVG.md), `noClear()` [accumulation](Docs/Drawing/Accumulation.md) for long-exposure looks, and [retained batches](Docs/Drawing/Batches.md) when static content gets heavy |
| [**Shapes that merge**](Docs/Drawing/Combinators.md) | SDF combinators: smooth union, subtract, morph, machined joints, carpentry detailing, domain mirror/tile/radial, via `drawSDF`, a scoped `smoothUnion { }` block, or the clay-like `sculpt { }` block. In 2D and in raymarched 3D, where the same fields twist, bend, and take surface displacement |
| [**Fields you measure**](Docs/Drawing/DistanceFields.md) | Measure a distance field back out of any drawn layer: how far each pixel is from the nearest edge and which way it lies, read back as contour bands, shapes grown or shrunk by a distance, outlines at any offset, or a Voronoi keyed to the picture itself |
| [**Local averages**](Docs/Drawing/LocalAverages.md) | The average of the square around every pixel for a flat price, over a summed-area table: a box blur whose cost does not grow with its radius, and an adaptive threshold that cuts a picture to two tones against each pixel's own surroundings, so a page lit from one side still reads |
| [**Generative technique**](Docs/README.md) | [Voronoi and Delaunay](Docs/Drawing/Voronoi.md) (plus weighted power diagrams), [Poisson-disk scatter](Docs/Generators/BlueNoise.md), [low-discrepancy sampling](Docs/Generators/LowDiscrepancy.md), [points scattered over a mesh surface](Docs/Generators/SurfaceSampling.md), [circle](Docs/Generators/Packing.md) and [shape packing](Docs/Generators/ShapePacking.md), [stippling](Docs/Generators/Stippling.md), [L-systems](Docs/Generators/LSystem.md) (symbolic and parametric), [shape grammars](Docs/Generators/ShapeGrammar.md) (ice-ray lattices, building fronts, nested figures), [differential growth](Docs/Generators/DifferentialGrowth.md), [space colonization](Docs/Generators/SpaceColonization.md), [diffusion-limited aggregation](Docs/Generators/DiffusionLimitedAggregation.md), [dielectric breakdown](Docs/Generators/DielectricBreakdown.md), [crack growth](Docs/Generators/CrackGrowth.md), [meander migration](Docs/Generators/Meander.md), [Wave Function Collapse](Docs/Generators/WaveFunctionCollapse.md) (from declared tiles or learned from an example picture), [flow fields](Docs/Generators/FlowField.md), [boids](Docs/Generators/Boids.md) and [steering](Docs/Generators/Steering.md), [pursuit curves](Docs/Generators/Pursuit.md), [force-directed graph layout](Docs/Generators/ForceLayout.md), [random walks](Docs/Generators/Walks.md), [Truchet](Docs/Drawing/Truchet.md), [hitomezashi stitching](Docs/Drawing/Hitomezashi.md), [mazes of diagonals](Docs/Drawing/TenPrint.md), [the Ulam spiral](Docs/Generators/UlamSpiral.md), [Ford circles](Docs/Generators/FordCircles.md), [de Bruijn sequences](Docs/Generators/DeBruijn.md), [kolam and sona](Docs/Drawing/Kolam.md), [Celtic knotwork](Docs/Drawing/Knotwork.md), [crease patterns](Docs/Drawing/CreasePattern.md) (the Miura fold and rotating-squares kirigami), [polyominoes](Docs/Generators/Polyominoes.md) (the pentomino set and an exact-cover fit), [hex and triangle grids](Docs/Drawing/Tiling.md), subdivision, mazes, the Apollonian gasket, [aperiodic tilings](Docs/Drawing/AperiodicTilings.md) (Penrose, Wang, girih star patterns, the spectre), [hyperbolic tilings](Docs/Drawing/HyperbolicTiling.md) (any {p,q} in the Poincaré disk), [strange attractors](Docs/Drawing/Attractors.md), [billiards](Docs/Generators/Billiards.md) (a ball bouncing in a circle, ellipse, polygon, or stadium), [chaotic maps and bifurcation diagrams](Docs/Generators/Bifurcation.md), [fractals](Docs/Generators/Fractals.md) (IFS, flames, inversion and Kleinian limit sets), [cellular automata](Docs/Generators/CellularAutomata.md), [classic curves](Docs/Drawing/Curves.md) (including spirolaterals), [envelopes and caustics](Docs/Drawing/Envelopes.md), [clothoids](Docs/Drawing/Clothoid.md) (the Euler spiral, easements, and corners a vehicle could take), [anamorphosis](Docs/Drawing/Anamorphosis.md) (a plate that reads only in a mirrored cylinder), [Fourier epicycles](Docs/Drawing/Epicycles.md), [shape morphing](Docs/Drawing/Morphing.md), [single-line TSP renderings](Docs/Generators/SingleLine.md), [ant-colony tours](Docs/Generators/AntColony.md), [spanning-tree renderings](Docs/Generators/SpanningTree.md), [string-art windings](Docs/Generators/StringArt.md), [percolation clusters](Docs/Generators/Percolation.md), [isolines](Docs/Generators/Isolines.md) (marching squares), [isosurfaces and metaballs](Docs/Generators/Isosurface.md) (marching cubes), [shadow art](Docs/Generators/ShadowArt.md), [subdivision surfaces](Docs/Generators/SubdivisionSurfaces.md) (Catmull-Clark and Loop), [mesh growth](Docs/Generators/MeshGrowth.md) (differential growth and reaction-diffusion over a surface), [surface reconstruction](Docs/Generators/SurfaceReconstruction.md) (a point cloud or scan back to a mesh, and particle skinning), [concave hulls and alpha shapes](Docs/Generators/Hulls.md), [medial-axis skeletons](Docs/Generators/MedialAxis.md), [straight skeletons and mitered insets](Docs/Generators/StraightSkeleton.md), [paper marbling](Docs/Generators/Marbling.md), [generative watercolor](Docs/Generators/Watercolor.md), [Chladni figures](Docs/Generators/Chladni.md), [terrain and erosion](Docs/Generators/Terrain.md), [river networks and basins](Docs/Generators/Drainage.md), and seedable [randomness](Docs/Generators/Random.md) |
| [**Layered effects**](Docs/Drawing/Effects.md) | Off-screen layers with fifty-plus GPU filters, two-layer combines (mask, displace, seamless clone, depth of field, ambient occlusion, screen-space reflections), diffusion curves, feedback layers, and GPU simulation fields, all declarable as one `compose { }` block |
| [**Your own shaders**](Docs/Shaders/Shaders.md) | Write a `shade(uv, info)` fragment function inline or in a hot-reloading `.metal` file, with compile errors reported at your own line numbers and a [built-in helper library](Docs/Shaders/ShaderLibrary.md) spliced in. Or skip the Metal and chain: [`Visual`](Docs/Shaders/Visuals.md) composes oscillators, noise, shapes, and layers through warps, blends, and modulations, in one GPU pass however deep it grows. Already have a GLSL shader? [`ollin new --from-shader`](Docs/Tools/ShaderImport.md) translates it to Metal and writes the project around it |
| [**GPU compute**](Docs/Shaders/Compute.md) | A million particles updated and drawn each frame without touching the CPU, a cooperative neighbor-search primitive underneath [artificial life](Docs/Simulation/ArtificialLife.md) and SPH fluids, and ping-pong texture simulations drawn as images |
| [**3D**](Docs/3D/3D.md) (opt-in) | Orbit and [cinematic cameras](Docs/3D/Camera.md), a solid-primitive catalog plus meshes from file (OBJ, glTF, USDZ) or [whole scenes](Docs/3D/Scenes.md) (glTF, USD) imported with their named nodes, authored cameras, lights, and keyframe animations played on the sketch's clock (or, with [`ollin new --from-scene`](Docs/Tools/SceneImport.md), written out as the placement calls that draw them), point clouds, [instanced meshes and GPU-culled fields](Docs/3D/Instancing.md) (one mesh drawn thousands of times in one call, placed per copy on the GPU, even from a compute kernel; a retained `MeshField` draws a whole world with one call and culls it per copy against the camera), [strand fields](Docs/3D/Strands.md) (grass grown inside the draw call itself: half a million bending blades with no geometry buffers, camera-culled and distance-graded), stylized and physically based materials including [glass](Docs/3D/3D.md#glass) (transmission, refraction, absorption), the full texture-map set through [projected decals](Docs/3D/3D.md#decals) (pictures stamped across whatever surfaces a box touches) and [detail maps](Docs/3D/3D.md#detail-maps) (texture that survives a close look), area lights (glowing panels, disks, and tubes), light shaping with IES photometric profiles and projected cookies, image-based lighting from bundled HDRIs, a procedural sky (which can carry raymarched volumetric cloudscapes), or [a live camera feed](Docs/3D/3D.md#live-environment) (the room lights the scene, AR-style), soft shadows, ray-traced reflections (spread by a surface's own roughness, so satin shows a blurred room rather than a blurred sky) and refractions, [caustics](Docs/3D/Caustics.md) (photon-traced light focused through glass and off polished metal, with prism dispersion), and [real-time global illumination](Docs/3D/3D.md#global-illumination) (bounce light through a live-retraced probe field) on RT GPUs, [temporal anti-aliasing](Docs/3D/3D.md#temporal-antialiasing) (jittered accumulation refining edges past MSAA, on any GPU), cinematic [motion blur](Docs/3D/3D.md#motion-blur) (per-object and camera streaks with a photographic shutter dial, deterministic in exports), [lens flare](Docs/3D/LensFlare.md) (the ghosts a real lens prescription throws from a bright source, plus the star on the source itself, both shaped by the iris blades and fading as something covers the source), and [atmosphere](Docs/3D/Atmosphere.md): height fog, aerial perspective (far geometry veiling blue toward the sky's own sun), and volumetric light beams. [The Hopf fibration](Docs/3D/HopfFibration.md) draws a sphere's worth of interlocking circles, no two of which meet. 2D drawing sits inside the depth buffer via [depth compositing](Docs/3D/DepthCompositing.md), and [Combining 3D features](Docs/3D/Combining.md) covers how the pieces stack. A 2D sketch never pays for any of it |
| [**Simulation & physics**](Docs/Simulation/Physics.md) | A stepped `World` with Verlet particles and springs on the soft side, Box2D bodies and joints on the rigid side, [3D rigid bodies](Docs/Simulation/Physics3D.md) that stack, tumble, and swing inside the 3D scene (Jolt-backed, with compound bodies, heightfield-terrain and `Scene` colliders, motored and limited joints, contacts and sensors, walking characters, driveable vehicles, ragdolls built from a skinned figure, soft-body cloth and pressurized shapes, ropes whose every segment carries an orientation, buoyancy and swell, ray/sweep/overlap queries, collision groups, and mouse grabbing), plus [SPH fluids and soft bodies](Docs/Simulation/Fluids.md), [steering crowds at GPU scale](Docs/Simulation/Swarm.md), [a million particles riding a strange attractor](Docs/Drawing/Attractors.md#flow), [populations that evolve](Docs/Simulation/Evolution.md) toward a target or by your eye, [matter that organizes itself and rules that spread by contact](Docs/Simulation/ArtificialLife.md), reaction-diffusion, Lenia, Game of Life, water-surface ripples, multi-scale Turing patterns, the Abelian sandpile, real-time fluid, and a [wet-paint watercolor wash](Docs/Simulation/Watercolor.md) with real pigments and optical glazing on the GPU, and [articulated and chaotic motion](Docs/Simulation/Motion.md) for IK chains, pendulums, and n-body gravity |
| [**Perception**](Docs/Vision/Vision.md) | Eighteen on-device trackers over the Mac's camera or any [video](Docs/Video/Video.md): face, hand, and body pose in 2D and 3D, segmentation (automatic or from a click), contours, optical flow, OCR, saliency, typed phrases scored against the picture, and custom Core ML models. An [iPhone](Docs/3D/Phone.md) extends that with LiDAR depth clouds, the reconstructed room as a labeled surface with the flat planes in it, the room's own light, ARKit body and face capture, hand skeletons and readable text lifted to metric 3D, and device motion over USB, live or from [recorded clips](Docs/3D/Record3D.md), all as metric [RGBD frames](Docs/3D/RGBD.md) |
| [**Sound & control**](Docs/Helpers/Audio.md) | FFT analysis with band and beat detection, [listening](Docs/Helpers/Listening.md) for words and for named sounds (speech as a live caption, a clap or a bark as a trigger), a [synthesizer](Docs/Helpers/Synthesis.md) the sketch itself plays (voice presets over a shaped and filtered oscillator, delay and reverb), [algorithmic composition](Docs/Helpers/Composition.md) that works out what to play (Euclidean rhythms, scales and chords, arpeggios, Markov sequences), [sonification](Docs/Helpers/Sonification.md) that reads a table column or a terrain profile out as notes, [MIDI](Docs/Integration/MIDI.md) and [OSC](Docs/Integration/OSC.md) in and out (bindable to `@Param` knobs), [game controllers](Docs/Integration/Controller.md) read in `draw()` (sticks, triggers, buttons, and motion and a touchpad where the hardware has them, several players at once), a [serial port](Docs/Integration/Serial.md) for the classic microcontroller loop (sensor lines read in `draw()` or bound to knobs, lines written back to drive servos and LEDs, reconnection built in), a [remote surface](Docs/Integration/Remote.md) that serves the sketch's `@Param` knobs to a phone on the same Wi-Fi as touch controls, and tempo sync so a set runs on the DJ's clock |
| [**Data as material**](Docs/Helpers/Data.md) | `loadTable` reads a CSV or TSV with typed reads by column name, `loadJSON` reads a document you reach through by name and index, [SVG import](Docs/Drawing/SVG.md) brings in vector artwork, and a [live feed](Docs/Helpers/LiveData.md) reads one address over and over in the background so a piece can draw what is true now, so a drawing can be driven by a file or by the world instead of hard-coded numbers |
| [**Text & color**](Docs/Drawing/Text.md) | Bitmap, outline, and single-line plotter fonts through one `drawText`, text in [any script](Docs/Drawing/Text.md#scripts) (right-to-left, Devanagari, Thai, Japanese, emoji), text as vector `Shape`s, [OKLab mixing](Docs/Drawing/Color.md), [spectral color and paint mixing](Docs/Drawing/Spectrum.md) (pigments that meet in green, thin-film and diffraction filters), palette import and extraction, colormaps, gradients, [color vision simulation](Docs/Helpers/Accessibility.md) so you can see a palette as somebody colorblind does, `describe` so a piece can say what it shows to a screen reader, [wide-gamut and HDR output](Docs/Drawing/ColorOutput.md) (Display P3 on screen, highlights brighter than white, HDR10 video, and stills that keep those highlights in a gain map), and [images](Docs/Drawing/Images.md) with pixel access, dithering, [pixel sorting](Docs/Drawing/PixelSorting.md), [seam carving](Docs/Drawing/SeamCarving.md), [halftone screens](Docs/Drawing/Halftone.md), and [glyph mosaics](Docs/Drawing/GlyphMosaic.md), [photo mosaics](Docs/Drawing/PhotoMosaic.md), [autostereograms](Docs/Drawing/Autostereogram.md) |
| **Plays in your rig** | [Syphon](Docs/Integration/Syphon.md) out and in, a system-wide [virtual camera](Docs/Integration/VirtualCamera.md) any webcam app can read, [screen and window capture](Docs/Integration/ScreenCapture.md) that takes any app on the Mac as live material whether or not it cooperates, [DMX lighting](Docs/Integration/DMX.md) driven from `draw()` over Art-Net or sACN (and a console driving the sketch back), [LED strips and matrices](Docs/Integration/DMX.md#ledmap) lit from the canvas's own pixels sampled on the GPU each frame, [show lasers](Docs/Integration/Laser.md) drawn from `draw()` as an optimized point stream over a network DAC or an ILDA file, [video playback](Docs/Video/Video.md) as live GPU textures, and [slit-scan time displacement](Docs/Video/SlitScan.md) over any frame history |

## Live reload

In creative coding, the speed of the edit-then-see cycle matters more than almost anything. Run a sketch once and keep editing it, and on each save Ollin recompiles that one file and swaps it into the running window:

```sh
swift run OllinLive Examples/Basic/HelloCircle/Sketch.swift
```

The window never closes. If an edit doesn't compile, the error prints and the old sketch keeps running. Each reload starts the sketch fresh by default, so pass `--keep-clock` to carry `time` and `frameCount` across so an animation doesn't jump back to the start (there's also an `onReload()` hook). For a heavy sketch, `Scripts/OllinLive` runs the host in release while saves stay fast, since only the sketch file recompiles.

The same engine also powers a performance instrument, [OllinLiveCoding](Docs/Tools/LiveCoding.md), a single fullscreen-able window where the code shows over the visuals for the audience and ⌘↩ evaluates the buffer in place, with the clock and tuned `@Param` knobs carrying across each swap. Where OllinLive is the development loop (your editor, a file watcher), OllinLiveCoding is the on-stage one (the editor in the window, evaluate on command).

A sketch doesn't need a package at all. `Scripts/ollin install` puts an `ollin` command on your PATH, and after that one `.swift` file anywhere on disk is a whole sketch:

```sh
ollin new dots.swift        # write a starter sketch
ollin dots.swift            # live window, hot-reload on save
./dots.swift                # the file is directly executable (hashbang + chmod +x)
ollin dots.swift --export-gif dots.gif --seconds 4
ollin dots.swift --installation   # put it up: its own window, left running
```

See [Single-file sketches](Docs/Tools/SingleFile.md) for assets, satellite imports, and growing a file into a package.

When a piece outgrows one file, the [project generator](Docs/Tools/ProjectGenerator.md) makes the folder for you, wired for what you're about to use:

```sh
ollin new MyPiece --template shader --with audio   # a folder that builds and runs
ollin generate                                     # the same, in a window
```

`ollin generate` shows each starting point by *running* it, so you pick a template by watching it rather than by reading its name.

The same command starts a library other people's sketches import, laid out the shared way. See [Writing an extension](Docs/Tools/Extensions.md) for the `ollinx-` naming convention and the seams a third party can build on.

```sh
ollin new Halftone --kind extension --seam filter
```

There are other ways to iterate. Tweak and re-run an example (`swift run --package-path Examples Example-Motion-Breathing`, where incremental builds keep it snappy), or open the package in Xcode (`open Package.swift`) for ⌘R, breakpoints, and the debugger.

## Export

Any sketch renders headlessly, no window needed. Stills, deterministic PNG sequences, video, GIF, and vector SVG and PDF all hang off the same run command:

```sh
swift run --package-path Examples Example-Basic-HelloCircle --export frame.png --frame 120
swift run --package-path Examples Example-Motion-Breathing --export-sequence frames/ --seconds 20 --fps 60
swift run --package-path Examples Example-Motion-Breathing --export-video breathing.mp4 --seconds 6
swift run --package-path Examples Example-Motion-Breathing --export-gif breathing.gif --seconds 4
swift run --package-path Examples Example-Basic-HelloCircle --export-svg still.svg   # vector, for pen plotters
swift run --package-path Examples Example-Basic-HelloCircle --export-pdf still.pdf   # vector, for print (paper-size presets)
swift run OllinLive MySketches/Loop.swift --export-gif loop.gif --seconds 4   # a loose file, same flags
```

Sequence, video, and GIF exports advance the clock at a fixed timestep rather than wall-clock, so a slow render still plays back smoothly. In code they're `OllinApp.export`, `exportSequence`, `exportVideo`, and `exportGIF`. Codec and quality dials, the `--skip` warmup, GIF sizing, and the plotter-oriented `--hatch` fills are all in [`Docs/Output/Export.md`](Docs/Output/Export.md). A 3D scene can also render its export by tracing light paths instead of rasterizing: `--path-traced` spends seconds per frame on physically soft shadows, color bleed, mirror-in-mirror reflections, and a real lens, from the same sketch the window tunes live ([`Docs/Output/PathTraced.md`](Docs/Output/PathTraced.md)).

An export reproduces a sketch; a recording keeps a performance. `startRecording()` in a sketch, ⌘⇧R in the live hosts, or `--record` on OllinLive writes the run as it happens, picture and the sketch's own sound (or the room's) in one movie in real time, and in the live-coding host a take plays straight through an evaluate. See [`Docs/Output/Recording.md`](Docs/Output/Recording.md).

A recording keeps the pixels; a *take* keeps the performance itself. `--record-take take.json` writes a run's seed, clock, inputs, and knob moves down as one small JSON file, and `--replay take.json` plays it back exactly, in the window (where the keyboard becomes a transport: pause, step, scrub) or through any export flag above, so a session of live tweaking re-renders offline frame for frame, even path-traced. `--seed` beside `--replay` plays the same gestures onto a different variation. See [`Docs/Core/Replay.md`](Docs/Core/Replay.md).

A take keeps what you did; an *automation* writes down what should happen. `automate($radius) { ... }` puts a knob on a curve, one value placed at each moment, and every frame the knob is where the curve says. Numbers, colors, and points travel; a switch steps. The tracks read the sketch clock, so `--export-video` renders the piece exactly as it plays, and `--automation file.json` drives the same knobs from a file. See [`Docs/Core/Automation.md`](Docs/Core/Automation.md).

A curve says where a knob is at a few moments; a *formula* says what it is at every moment. `drive($radius, "190 + sin(time * tau / 6) * 80")` reads the rule from text rather than from Swift source, so it can arrive from a file, from a typed field, or from a knob worked out from another one. It is the same track, so it loops, plays at any speed, and renders frame for frame. A knob that holds more than one number takes one rule for each part, and the part you leave out stays yours to move. See [`Docs/Helpers/Formula.md`](Docs/Helpers/Formula.md).

A seeded sketch is a generator, so Ollin names the seed each run grew from ([`variation`](Docs/Core/Variations.md)) and gives you the tools to explore the space it indexes: step, roll, or jump through seeds from the inspector's Variation card, proof a whole range as a labeled contact sheet, then re-render the keeper at full size.

```sh
swift run --package-path Examples Example-Randomness-Variations --export-grid sheet.png --seeds 25  # proof 25 variations
swift run --package-path Examples Example-Randomness-Variations --export keeper.png --seed 10       # render the one you liked
```

## Documentation

New to creative coding, or to Ollin? [The Guide](Guide/README.md) is a practical, book-length introduction taught through Ollin, written for programmers with no math or graphics background. Start at [Chapter 1: Hello, Ollin](Guide/01-HelloOllin.md).

The full API reference lives in [`Docs/`](Docs/), one page per topic, and **[`Docs/README.md`](Docs/README.md) is the annotated index**. Most of it ships with the core `import Ollin`, while the satellite libraries live in the same package behind their own `import` (shown on each page), so a sketch links only what it uses.

Good places to start:

- [Sketch](Docs/Core/Sketch.md) and [Canvas](Docs/Core/Canvas.md), the lifecycle and the drawing surface
- [Drawing](Docs/Drawing/Drawing.md) and [Color](Docs/Drawing/Color.md), the day-to-day API
- [Input](Docs/Helpers/Input.md) and [Math](Docs/Helpers/Math.md), mouse and keys, and the helpers you'll reach for constantly
- [Parameters](Docs/Helpers/Parameters.md), the `@Param` inspector controls
- [Data](Docs/Helpers/Data.md), reading a CSV or JSON file to draw from
- [Animation](Docs/Helpers/Animation.md) and [Noise](Docs/Generators/Noise.md), the motion and texture layers
- [Layered effects](Docs/Drawing/Effects.md) and [Shaders](Docs/Shaders/Shaders.md), when you go to the GPU
- [3D](Docs/3D/3D.md), the opt-in third dimension
- [Export](Docs/Output/Export.md), getting work out of the window

New to Swift? The [Swift quick reference](Docs/Swift.md) teaches just enough of the language to be productive in `draw()`, and the Guide's [Appendix A](Guide/A-JustEnoughSwift.md) is its slower, narrative companion. Coming from p5.js or Processing? [Appendix C of the Guide](Guide/C-ComingFromP5.md) maps the API you already know onto Ollin.

Coordinates use a top-left origin with y increasing downward, the same as p5, Processing, and OPENRNDR.

## How it works

`Sketch.draw()` calls the bare drawing functions, which forward to a `Drawer` state machine. Most primitives take a signed-distance-field path, one quad each with fill, stroke, and anti-aliasing computed analytically in the fragment shader; the rest tessellate into triangles. The `Drawer` records both into call-ordered batches, and once a frame `MetalRenderer` uploads them and issues a draw per batch, so shapes composite in the order you drew them.

The renderer is heavily commented, because you'll be extending it. For how the larger systems work inside (the frame lifecycle, the screen-space effects, the SDF combinators, and more), see [`ARCHITECTURE.md`](ARCHITECTURE.md).

## Why Apple-only

p5.js, OPENRNDR, and openFrameworks run everywhere, while Ollin only runs on Apple hardware, and that's the trade it makes on purpose.

Sitting directly on Metal means the rendering ceiling is whatever the GPU can do. Staying native puts the rest of the platform in reach: vision on the Neural Engine and an iPhone's depth sensors feeding a sketch the Mac renders are already here, while ARKit, visionOS, and AR are still ahead. The point is that the core is built to grow into those things rather than get retrofitted.

The same trade rules out a browser version, because the web has no Metal, so a web build would mean a second, lesser renderer on WebGPU. Sharing a piece happens by exporting it (video, GIF, USDZ, SVG, PDF), not by running Ollin in a tab.

## Roadmap

The full roadmap lives in [`ROADMAP.md`](ROADMAP.md): what's planned, what's being explored, and the best first contributions, with the engineering thinking behind each item in [`DESIGN-NOTES.md`](DESIGN-NOTES.md). The next milestone is version 1.0.0, the first public release; the roadmap's [Toward 1.0](ROADMAP.md#toward-10) section tracks what it waits on. The short version of what's further ahead: more of the iPhone sensor array and the 3D mode (cloth that meets itself), generative geometry and a growing catalog of creative-coding technique helpers, more of the sound layer, new input and output surfaces (haptics, a desktop widget), editor tooling, learning materials and a third-party extension ecosystem, and eventually iOS, visionOS, and AR.

## Built with AI

Ollin is [@eaviles](https://github.com/eaviles)'s project. The motion-first idea, the decisions about what belongs in the framework, and the responsibility for it are his. The code is written with an AI coding assistant (Claude) that proposes APIs and implements them, which @eaviles reviews, reworks, or rejects. A fair description: Claude does much of the proposing and most of the typing, and @eaviles does the deciding.

It's worth saying plainly, because the creative-coding community has good reasons to be careful about AI. A few specifics about how Ollin uses it:

- **It's a tool for making art.** The AI helped build the framework's plumbing. It has no hand in the work you make with Ollin, and no scraped images, training data, or generated artwork go into it. Ollin is not a generative-art model.
- **Influences are credited, licenses respected.** Ollin borrows the feel and vocabulary of p5.js, OPENRNDR, and openFrameworks while writing its own implementation. Ported example sketches name their source, author, and license in the file. See [Influences & attribution](#influences--attribution).
- **A person is accountable.** Bugs, design mistakes, and licensing questions are @eaviles's to answer. Scrutiny is welcome, so please [open an issue](https://github.com/eaviles/Ollin/issues).

The work people make with it is the real test.

## Influences & attribution

Ollin is inspired by [p5.js](https://p5js.org) (LGPL-2.1), [OPENRNDR](https://openrndr.org) (BSD-2-Clause), and [openFrameworks](https://openframeworks.cc) (MIT), in that it borrows their ideas and API vocabulary and writes its own implementation, so none of their licenses attach and Ollin stays MIT. The same rule runs through everything else it learns from: each published technique a helper reimplements (Quilez's distance fields, Reynolds' boids, Stam's fluids, and many more) is credited to its source, and ported example sketches name their source, author, and license in the file header.

The full record lives in [`ATTRIBUTION.md`](ATTRIBUTION.md): the framework influences, the Swift + Metal engineering references, the technique behind each helper, and the small amount of vendored third-party source. Every bundled component's license is also collected in [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md), and Ollin's own code stays MIT.

## Status & contributing

Ollin is **alpha and pre-1.0**, developed in the open. Two different things are meant by that, and they're worth separating:

- **The output is production-grade.** Linear-light rendering, real anti-aliasing, OKLab color, deterministic and reproducible export, snapshot-tested rendering. Work made with Ollin is meant to be finished and shown.
- **The API is not.** Names, signatures, and structure can shift between commits, and there's no tagged release or SemVer guarantee until 1.0.

Beyond that:

- **No support guarantee.** This is built nights and weekends. Issues and discussions get read, but a response time isn't promised.
- **macOS 26+ and a Metal-capable GPU are required.** That's the trade described up top rather than a gap to be filled later, so there's no Linux or Windows path, by design.

That said, contributions and ideas are genuinely welcome. [`ROADMAP.md`](ROADMAP.md) is the best source of bite-size work, and its [Up next](ROADMAP.md#up-next) section maps onto small, self-contained pull requests. For anything larger, please open an issue to discuss it before sending a big change. To get your bearings before touching one of the bigger systems, [`ARCHITECTURE.md`](ARCHITECTURE.md) explains how they work inside (and [`DESIGN-NOTES.md`](DESIGN-NOTES.md) covers the intent behind what's still planned).
