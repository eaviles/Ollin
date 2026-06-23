# Ollin

**Motion-first creative coding for Swift, rendered with Metal.**

*Ollin* (OH-leen) is the Aztec glyph for **movement**, the 17th day sign of the calendar, and the name says what the framework is about: in Ollin, your sketches **move by default**. The draw loop runs continuously at the display's refresh rate from the very first line of code. Animation is on from the start, so you never reach for a `loop()` call to begin it. For the rare still image, `noLoop()` turns it off.

It draws inspiration from [OPENRNDR](https://openrndr.org) (the `Program` / `drawer` lifecycle), [p5.js](https://p5js.org) (friendly, forgiving, learn-it-in-an-afternoon API names), and [openFrameworks](https://openframeworks.cc) (simple structure, immediate-mode primitives), while leaning into Swift idioms rather than porting any of them literally.

- **Platform:** macOS 26+, Swift 6+
- **Rendering:** Metal (`MTKView`, up to 8× MSAA), built on Foundation / SwiftUI / Metal / MetalKit / simd. It stays dependency-light (no package dependencies today; just a little vendored source, see [Bundled third-party code](#bundled-third-party-code)) and takes on a package only when one clearly earns its place
- **License:** MIT
- **Built with:** an AI coding assistant (Claude) under [@eaviles](https://github.com/eaviles)'s direction; see [Built with AI](#built-with-ai)

> **Status: alpha, pre-1.0, built in public.** Everything documented below runs today, but the project is young: names and APIs still change between commits, and there's no stability or support guarantee yet. See [Status & contributing](#status--contributing).

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

That's the whole program: a black circle outline, breathing on a white canvas. There's no call to start the animation, because the draw loop is already running at the display's refresh rate, and `time` (seconds since start) is ready to use in any sketch. Delete `+ sin(time) * 40` and you have a still circle.

Every sketch also gets temporal state out of the box (`frameCount`, `deltaTime`, `frameRate`), live `width`/`height`, a resolution-relative `scale`, and `noLoop()` / `loop()` for still images. The [`Sketch`](Docs/Sketch.md) reference covers them all.

## Run it

From the terminal, no Xcode required:

```sh
swift run Example-HelloCircle
```

That builds the package and opens a window with the breathing circle above (a 1080² canvas, fit to your screen). More runnable sketches live in [`Examples/`](Examples/); `swift run` with no argument lists every example target.

Or browse them all in one window: `swift run OllinExamples` opens a gallery with every example in a sidebar, and clicking one compiles and runs it on the right.

## Why Apple-only

p5.js, OPENRNDR, and openFrameworks run everywhere; Ollin only runs on Apple hardware, and that's the trade it makes on purpose. Sitting directly on Metal means the rendering ceiling is whatever the GPU can do, and staying native puts the rest of the platform in reach: vision on the Neural Engine and an iPhone's depth sensors feeding a sketch the Mac renders are already here (the docs below cover them); ARKit, visionOS, and AR are still ahead (the [roadmap](#roadmap) has them). The point is that the core is built to grow into those things rather than get retrofitted.

## Canvas size and resolution

The default canvas is **1080×1080**, the 1:1 size for square social and video posts. `canvasSize` sets the resolution a sketch renders and exports at (override it for a hi-res master or a different aspect), and `windowMode` sizes the preview window relative to it (`.auto` fits the screen, `.fixed(_)` pins a zoom, `.resizable` follows the window live).

Write sketches relative to the canvas so they hold up at any size: multiply feature sizes by `scale` and lay out with `width`/`height` fractions. The [`Canvas` reference](Docs/Canvas.md#resolution-independence) has the presets and the rest.

## Add Ollin to your own package (SPM)

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

## Iteration workflow

In creative coding, the speed of the edit-then-see cycle matters more than almost anything. Here are a few options, with the fastest feedback first:

1. **Live reload (`OllinLive`).** Run a sketch once and keep editing it. On each
   save, Ollin recompiles that one file and swaps it into the running window, so
   the window stays open and the change shows up right away:

   ```sh
   swift run OllinLive Examples/Basic/HelloCircle/Sketch.swift
   ```

   It takes a path to any sketch file, so there's no target to register first. Run it from the repo and it live-reloads the framework's shaders as well. Each reload starts the sketch fresh by default: `setup()` runs again and the clock resets. Pass `--keep-clock` to keep `time` and `frameCount` running across reloads, so an animation doesn't jump back to the start. There's an `onReload()` hook for work you want to run on each reload. If an edit doesn't compile, the error prints and the running sketch keeps going, so a typo won't close the window.

   For a heavy sketch, build the host in release so the drawing runs at full speed while you tweak; hot-reloads stay fast because only the sketch file recompiles. `Scripts/OllinLive` does this for you (it's `swift run -c release OllinLive`, with `--debug` to opt out):

   ```sh
   Scripts/OllinLive Examples/Motion/ArcField/Sketch.swift
   ```
2. **Edit & re-run.** Tweak an example (or your own sketch) and re-run, e.g.
   `swift run Example-Breathing`. Incremental builds keep this snappy.
3. **Keep it open in Xcode.** `open Package.swift` (or just open the folder).
   Edit, ⌘R, repeat, with breakpoints and the debugger when you need them.
4. **Single-file scripts (planned).** [`swift-sh`](https://github.com/mxcl/swift-sh)
   made one `.swift` file double as a runnable script, dependencies and all. We
   want the same here, so you can dash off a sketch without setting up a package.
   It's on the [roadmap](ROADMAP.md).

## Documentation

The names are familiar and the calls are short. The full API reference lives in [`Docs/`](Docs/). Most of this ships with the core `import Ollin` (the few satellite pieces show their own `import` in the bullet):

- [Sketch](Docs/Sketch.md) - the lifecycle (`setup`/`draw`), temporal state (`time`, `frameCount`, …), and loop control.
- [Canvas](Docs/Canvas.md) - `scale`, the `canvasSize` export presets, and the preview window.
- [Drawing](Docs/Drawing.md) - `background`, `fill`/`stroke`, the shapes (`drawCircle`, `drawRect`, `drawLine`, `drawShape`, and a full catalog of analytic SDF shapes; see the reference), and the transform stack (`translate`/`rotate`/`scale`, `withState`).
- [Accumulation](Docs/Accumulation.md) - `noClear` to keep the canvas across frames so drawing piles up: long exposures, paint-on-canvas, and light accumulation (paired with `blendMode(.add)`).
- [HDR & tone-mapping](Docs/HDR.md) - `toneMap` to roll bright, out-of-range light off the screen instead of clipping it, with an `exposure` dial, for the glow/bloom and light-accumulation looks, over a linear-float pipeline that also kills 8-bit gradient banding.
- [Layered effects](Docs/Effects.md) - `renderTarget` / `withTarget` to draw into off-screen layers, then `filtered` / `postProcess` to run GPU filters (blur, bloom, color grade, gradient map, edges, halftone, pixelate, and more) over them, composited back with blend modes; `combined` to combine two layers (mask, displace, cross-dissolve, depth-of-field defocus, ambient occlusion); plus `generate` for procedural pattern sources (checkers, grid, bars, noise) and `feedback` for layers that remember themselves across frames (trails, tunnels, video feedback); plus `compose { }` to declare a whole stack of layers (each with its own filters, blend, and `aside` helper layers) as one block, for glow, soft backdrops, color grading, and post-processing.
- [Compute & GPU particles](Docs/Compute.md) - GPU compute over buffers and textures, the per-element update written as a Metal snippet (inline or in its own `.metal` file): `Particles` runs a million particles updated and drawn on the GPU each frame, never touching the CPU (the "sandpainting" engine); `Simulation` runs reaction-diffusion, cellular automata, and other ping-pong texture sims, drawn as an `Image`. Over the `ComputeKernel`/`ComputeBuffer`/`ComputeTexture` core.
- [Text](Docs/Text.md) - `drawText` with bitmap, outline (`.ttf`/`.otf`), and single-line/plotter (Hershey) fonts (`textFont`/`textSize`/`textAlign`/`textWidth`, `BitmapFont`/`OutlineFont`/`StrokeFont`), `textToShapes` for text as geometry, and loading BDF, Playdate `.fnt`, and Hershey `.jhf` fonts.
- [Images](Docs/Images.md) - `loadImage` / `drawImage` for raster images (PNG, JPEG, HEIC, …), with `tint` recoloring and an `Image[x, y]` pixel subscript for sampling or authoring.
- [Color](Docs/Color.md) - the `Color` type, the OKLab family and mixing, `Ramp`s and `Palette`s, and perceptual `Colormap`s.
- [Geometry](Docs/Geometry.md) - the `Vector2`, `Rectangle`, `Shape`/`Contour`, and `Path` value types (including curved outlines, shape booleans, and offsetting).
- [Voronoi & Delaunay](Docs/Voronoi.md) - tessellate points into vector geometry: Voronoi cells and the dual Delaunay triangle mesh, with Lloyd relaxation.
- [3D](Docs/3D.md) - opt into a 3D camera and depth buffer: orbit a `Camera3D` (perspective or orthographic) and draw `PointCloud`s as instanced disc splats and a catalog of solid primitives (box, sphere, capsule, the Platonic solids, …) plus parametric and profile shapes (supershape, extrude, lathe), lit by directional, point, and spot lights with a Blinn-Phong material (shaded out of the box by an auto-lit default), give a surface a stylized finish from the material library (iridescent, velvet, jade, toon, gooch) or a matcap (a whole look baked into one sphere texture, sampled by the view normal, with 26 bundled looks plus a generator), wrap an image onto a surface (textured meshes), including a live webcam depth cloud (the Mac-side preview of the iPhone LiDAR cloud to come).
- [Depth compositing](Docs/DepthCompositing.md) - place 2D drawing *inside* a 3D scene so it occludes and is occluded by the geometry: `depth(at:)`, `project`, and `withBillboard` (a 2D label hidden when it swings behind the cloud), or against a live depth feed with `drawDepthScene`, including in true metric space (`Camera3D.fromIntrinsics`), so an object sits at a real distance inside a LiDAR feed.
- [Record3D](Docs/Record3D.md) - `import OllinRecord3D` to turn an iPhone's color-plus-depth into a 3D point cloud, from a recorded `.r3d` file or a tethered phone's live USB stream (the iPhone's depth camera, borrowed by the Mac in real time).
- [RGBD](Docs/RGBD.md) - the source-agnostic `RGBDFrame` (color + depth + intrinsics) any depth source produces: unproject a point cloud, lift a single image point to metric 3D, or lift a 2D body pose into space at its true distance (`Body.lifted(through:)`).
- [Phone](Docs/Phone.md) - `import OllinPhone` to read a tethered iPhone's live on-device ARKit sensor stream from Ollin's own capture app ([`Apps/OllinPhoneApp`](Apps/OllinPhoneApp/README.md)): a 3D body skeleton, a face mesh with its 52 expression blendshapes, a world-facing rear-LiDAR depth cloud (with the camera's 6DoF pose), a person-segmentation matte and cutout, and device motion over the USB cable, drawn in space as a `PointCloud`.
- [Random](Docs/Random.md) - `random`, `randomGaussian`, and the `randomVector`/`ring` scatter helpers.
- [Noise](Docs/Noise.md) - Perlin `noise`/`signedNoise` and `curlNoise` flow fields.
- [Math](Docs/Math.md) - `map`, `dist`, `lerp`.
- [Animation](Docs/Animation.md) - the `Easing` curves, the `@Eased` value that tweens toward a target, and `@Smoothed` for cleaning up a noisy signal.
- [Parameters](Docs/Parameters.md) - `@Param` tunable knobs: live sliders in the inspector, optional smoothing, and binding from OSC or MIDI.
- [Input](Docs/Input.md) - mouse and keyboard.
- [Export](Docs/Export.md) - save frames as raster (PNG, sequences) or vector (SVG, for pen plotters).

Ten satellite libraries live in the same package behind their own `import`, so a sketch only links what it uses (Record3D and Phone, grouped with the 3D docs above, are two of them):

- [Audio](Docs/Audio.md) - `import OllinAudio` for microphone, file, and oscillator sources, analyzed into `amplitude`, `spectrum`, and band values (`bass`/`mid`/`treble`) a sketch reads in `draw()`.
- [OSC](Docs/OSC.md) - `import OllinOSC` to send and receive OSC messages over UDP (TouchOSC, Max/MSP, TouchDesigner, …), read in `draw()` or bound to a `@Param`.
- [MIDI](Docs/MIDI.md) - `import OllinMIDI` to read from and send to MIDI controllers and keyboards over Core MIDI, read in `draw()` or bound to a `@Param`.
- [Physics](Docs/Physics.md) - `import OllinPhysics` for a `World` you step each frame, so motion comes from simulation instead of hand-tuned values: a soft Verlet side (particles, springs, disk collisions) and a rigid side (bodies, colliders, and joints, backed by Box2D).
- [Vision](Docs/Vision.md) - `import OllinVision` for the Mac's camera (built-in, Continuity, or external) plus Apple's on-device perception, surfaced as typed results a sketch reads in `draw()`: sixteen trackers spanning detection (rectangles, barcodes/QR, text/OCR, contours into vector `Shape`s), tracking (lock onto a patch, parabolic trajectories, dense optical flow), segmentation (person and subject mattes and cutouts as drawable `Image`s), pose (face landmarks and head pose, hand and body skeletons, the 3D body in meters from one webcam), classification, and saliency, plus any custom Core ML model run the same way. Trackers attach to any frame source: the live camera, a playing video, or a frame producer of your own.
- [Syphon](Docs/Syphon.md) - `import OllinSyphon` to share live visuals with other Mac apps (openFrameworks, Resolume, MadMapper, VDMX, …): publish a sketch's frames as a Syphon source, and draw an incoming Syphon feed as an `Image`.
- [Virtual camera](Docs/VirtualCamera.md) - `import OllinCamera` to feed a sketch's frames to the Ollin Camera system camera, so anything that takes a webcam (Zoom, OBS, QuickTime, and browser tools like Hydra through `getUserMedia`) reads the sketch as a live camera; the device itself installs once from [`Apps/OllinCameraApp`](Apps/OllinCameraApp/README.md).
- [Video](Docs/Video.md) - `import OllinVideo` to play a video file into a sketch as a live image: each decoded frame arrives as a GPU texture drawn with `drawImage`, riding the transform stack and `tint`, with a CPU `snapshot()` for pixel reads and vision trackers attaching directly to analyze the footage as it plays.

New to Swift, coming from p5.js or JavaScript? The [Swift primer](Docs/Swift.md) teaches just enough of the language to be productive in `draw()`.

Coordinates use a top-left origin with y increasing downward, the same as p5, Processing, and OPENRNDR.

## How it works (one paragraph)

`Sketch.draw()` calls the bare drawing functions, which forward to a `Drawer`
state machine. Most primitives (circles, ellipses, rectangles, lines, circular
arcs, and a broad catalog of analytic shapes) take a signed-distance-field path:
one quad each, with fill, stroke, and anti-aliasing computed analytically in the
fragment shader, so thousands of them stay cheap.
The rest (polygons, polylines, and elliptical arcs) are tessellated into
triangles in sketch-space points. The `Drawer` records both into call-ordered batches; once a frame,
`MetalRenderer` uploads them and issues a draw per batch (the triangle pipeline,
or the instanced-SDF one), so shapes composite in the order you drew them. A
vertex shader maps points to clip space (flipping Y), and MSAA (8× where the
GPU supports it) covers the triangle path. The renderer is heavily commented because you'll be extending it.

## Exporting frames

Any sketch can render a frame to a PNG **headlessly**, with no window. That's handy for grabbing a still to share, for checking a sketch on a machine without a display, and as the basis for PNG sequences you can stitch into video:

```sh
swift run Example-HelloCircle --export frame.png
swift run Example-Orbits --export frame.png --frame 120   # the 120th frame
```

It drives the sketch off-screen (`setup()`, then `draw()` advanced to the requested `--frame`) and writes a PNG at the sketch's `canvasSize` (1080×1080 by default), rendered with the same MSAA as the window. In code it's `OllinApp.export(sketch, to:frame:)`, or `OllinApp.image(of: sketch, frame:)` if you'd rather have the `CGImage` in memory than a file on disk. An extension can also grab each frame as it renders, through the `frameRendered` hook on the `extend(...)` seam. See [`Examples/Basic/Capture`](Examples/Basic/Capture/Sketch.swift).

For an animation, `--export-sequence` writes a numbered PNG sequence you can stitch into video:

```sh
swift run Example-Breathing --export-sequence frames/ --skip 5 --seconds 20 --fps 60
```

It advances the clock at a fixed timestep rather than wall-clock, so each frame renders the moment it should regardless of how long the render takes. A slow render still plays back smoothly. Pass `--seconds` for a duration instead of `--frames`, and `--skip` to run the sketch a while first without writing, so a sketch that needs to settle into motion is already going when capture starts. Frames are written as `frame-00001.png`, `frame-00002.png`, and so on, and the command prints an `ffmpeg` line to assemble them. In code it's `OllinApp.exportSequence(sketch, to:frames:fps:)` (plus optional `startFrame:` / `skipSeconds:`).

For a file you can share directly, `--export-video` encodes the same deterministic render straight to `.mp4` or `.mov` (H.264 by default; HEVC and ProRes via `--codec`, `--bitrate` as the file-size dial), and `--export-gif` writes a short looping GIF (`--gif-width` to shrink it). No external tool needed:

```sh
swift run Example-Breathing --export-video breathing.mp4 --seconds 6
swift run Example-Breathing --export-gif breathing.gif --seconds 4 --gif-width 540
```

In code they're `OllinApp.exportVideo(...)` and `OllinApp.exportGIF(...)`; codec choice, size and quality control, and the GIF timing details are in [`Docs/Export.md`](Docs/Export.md).

## Roadmap

The full roadmap lives in [`ROADMAP.md`](ROADMAP.md): what's planned, what's being explored, and the best first contributions, with the engineering thinking behind each item in [`DESIGN-NOTES.md`](DESIGN-NOTES.md). The short version of what's ahead: layered effects and compositing, shader composition and a live-coding mode, more of the iPhone sensor array and the 3D mode (scene import, softer shadows, environment lighting), a project generator, and eventually iOS, visionOS, and AR.

## Built with AI

Ollin is [@eaviles](https://github.com/eaviles)'s project. The motion-first idea, the decisions about what belongs in the framework, and the responsibility for it are his. The code is written with an AI coding assistant (Claude) that proposes APIs and implements them, which @eaviles reviews, reworks, or rejects. A fair description: Claude does much of the proposing and most of the typing, and @eaviles does the deciding.

It's worth saying plainly, because the creative-coding community has good reasons to be careful about AI. A few specifics about how Ollin uses it:

- **It's a tool for making art.** The AI helped build the framework's plumbing. It has no hand in the work you make with Ollin, and no scraped images, training data, or generated artwork go into it. Ollin is not a generative-art model.
- **Influences are credited, licenses respected.** Ollin borrows the feel and vocabulary of p5.js, OPENRNDR, and openFrameworks while writing its own implementation. Ported example sketches name their source, author, and license in the file. See [Influences & attribution](#influences--attribution).
- **A person is accountable.** Bugs, design mistakes, and licensing questions are @eaviles's to answer. Scrutiny is welcome, so please [open an issue](https://github.com/eaviles/Ollin/issues).

The work people make with it is the real test.

## Influences & attribution

Ollin builds on the ideas of three creative-coding frameworks and reimplements them in Swift. Because it does not copy their source code, none of their licenses attach to Ollin, which stays MIT:

| Project | License | What Ollin takes (influence only) |
|---|---|---|
| [p5.js](https://p5js.org) | LGPL-2.1 | Friendly, learn-it-in-an-afternoon API names and the `setup()` / `draw()` lifecycle |
| [OPENRNDR](https://openrndr.org) | BSD-2-Clause | The typed `Program` / `Drawer` core and composable geometry |
| [openFrameworks](https://openframeworks.cc) | MIT | Simple project structure and the per-example folder layout |

That `setup()` / `draw()` vocabulary started in [Processing](https://processing.org), the Java project p5.js grew out of. Ollin follows p5's spelling because that's the version most people coming to it already know.

"Inspired by" means borrowing ideas and API vocabulary, which is different from copying code; Ollin's implementation is written independently. Individual example sketches that are ported from a published source name that source, its author, and its license in the file header. Only sources whose licenses permit redistribution under MIT are used.

### Bundled third-party code

Ollin bundles a small amount of third-party source in the repo. This is different from the projects above: it ships as actual code and keeps its own license. Right now that's:

- **[libtess2](https://github.com/memononen/libtess2)** (SGI Free Software License B): the polygon triangulator behind concave and holed `Shape` fills, vendored under `External/CLibtess2/`.
- **[Box2D](https://github.com/erincatto/box2d)** by Erin Catto (MIT): the 2D rigid-body engine behind `OllinPhysics`' rigid `Body` side (rotation, polygon colliders, joints, stacking), vendored under `External/CBox2D/` and wrapped behind Ollin's own `World`/`Body` API.
- **[Clipper2](https://github.com/AngusJohnson/Clipper2)** by Angus Johnson (Boost Software License 1.0): the polygon clipping and offsetting engine behind `Shape`'s boolean set operations and `offset(by:join:)`, vendored under `External/CClipper2/` and wrapped behind Ollin's own `Shape` API.
- **[Syphon Framework](https://github.com/Syphon/Syphon-Framework)** by Tom Butterworth, Anton Marini, Maxime Touroute & Philippe Chaurand (BSD 2-Clause): the IOSurface-backed GPU frame-sharing engine behind `OllinSyphon`, vendored (Metal portion only) under `External/CSyphon/` and wrapped behind Ollin's own `SyphonServer`/`SyphonClient` API.
- **[Cozette](https://github.com/the-moonwitch/Cozette)** by Ines (MIT): the bundled bitmap font for `drawText` (`BitmapFont.builtin`), vendored as a BDF under `Sources/Ollin/Resources/`.
- **[Hershey fonts](https://paulbourke.net/dataformats/hershey/)** (public domain): "Hershey Sans" (`futural`), the bundled default stroke (single-line / plotter) font for `drawText`, vendored as a `.jhf` under `Sources/Ollin/Resources/`. Created by A. V. Hershey at the U.S. National Bureau of Standards.
- **[Marble Madness](https://github.com/idleberg/playdate-arcade-fonts)** (CC0 / public domain): a sample Playdate `.fnt` font used only by the `PlaydateFont` example to demonstrate the loader, bundled beside that sketch, not in the framework. Ollin ships the `.fnt` loader, not a library of fonts.
- **[El Fandanguito](https://commons.wikimedia.org/wiki/File:Viol%C3%ADn_SonHuasteco_ELFandanguito.ogg)** (CC BY-SA 4.0): a recording of a traditional Mexican *son huasteco* for violin (performed by Cynthia Molina), used only by the `FilePlayer` example to demonstrate `AudioPlayer`, bundled beside that sketch, not in the framework. Ollin bundles no audio of its own. As a ShareAlike work the clip stays under CC BY-SA; that applies to the audio file, not to Ollin's code.
- **[Voladores de Papantla México](https://commons.wikimedia.org/wiki/File:Voladores_de_Papantla_M%C3%A9xico.webm)** by José Millán (CC BY-SA 4.0): a recording of the *Danza de los Voladores*, the Totonac pole-flying ritual dance, used only by the `VideoPlayback` and `VideoTrace` examples to demonstrate `VideoPlayer` and vision over recorded footage, bundled (trimmed and re-encoded) beside those sketches, not in the framework. Ollin bundles no video of its own. As a ShareAlike work the clip stays under CC BY-SA; that applies to the video file, not to Ollin's code.

Everything bundled is listed in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md), with each component's license kept next to its source. Ollin's own code stays MIT; bundling a separately-licensed font, library, or example asset doesn't change that: each keeps its own license and the root [`LICENSE`](LICENSE) stays pure MIT.

### Swift + Metal references

The frameworks above shaped Ollin's API and ideas. Two more, written for the same Swift and Metal stack, are references for how the rendering layer is built:

| Project | License | What Ollin studies it for |
|---|---|---|
| [swifty-creatives](https://github.com/yukiny0811/swifty-creatives) | Apache-2.0 | A Processing-style, immediate-mode framework on the same stack; a reference for cross-platform view setup and snapshot-testing of rendered output |
| [AsyncGraphics](https://github.com/heestand-xyz/AsyncGraphics) | MIT | GPU image and video compositing; a reference for shader-library structure and a layered-effects model |

As with the others, this is reading for ideas and engineering approach, which is different from copying code; Ollin's implementation is its own. Thanks to their authors, [@yukiny0811](https://github.com/yukiny0811) and [@heestand-xyz](https://github.com/heestand-xyz), for building in the open.

The Ollin Camera virtual camera follows the same rule. Three projects were studied for the companion-app mechanism, where a system extension owns the camera device and a client app feeds it frames: [SinkCam](https://github.com/Halle/SinkCam) by Halle Winkler ([@Halle](https://github.com/Halle)), the reference for feeding a CMIO camera extension through its sink stream, along with her [write-ups on The Offcuts](https://theoffcuts.org/); [Celluloid](https://github.com/whyisjake/Celluloid) by Jake Spurlock ([@whyisjake](https://github.com/whyisjake)), a shipping virtual-camera app pushing Metal-processed frames the same way; and [ofxGL2Webcam](https://github.com/daitomanabe/ofxGL2Webcam) by Daito Manabe ([@daitomanabe](https://github.com/daitomanabe)), which published an openFrameworks texture to a virtual webcam in the earlier DAL era. Ollin Camera's implementation is its own. The idle test card is an original design in the genre of the classic broadcast test cards (the Philips PM5544 family by Finn Hendil), drawn from scratch rather than reproduced.

### Techniques

A few helpers lean on well-known public techniques, reimplemented in Ollin and credited here. They lean toward OPENRNDR-style ergonomics:

- The cosine-gradient `CosinePalette` uses [Inigo Quilez's palette formula](https://iquilezles.org/articles/palettes/).
- The built-in `Palette` sets carry the eight ColorBrewer qualitative palettes ([colorbrewer2.org](https://colorbrewer2.org), Cynthia Brewer, Mark Harrower, and The Pennsylvania State University; Apache-2.0), as data.
- The signed-distance fields behind Ollin's analytic shapes (circles, ellipses, rectangles, lines, arcs, triangles, n-gons and stars, quadratic Bézier curves, point markers, and the rest of the catalog) come from [Inigo Quilez's 2D distance functions](https://iquilezles.org/articles/distfunctions2d/), including the onion operator behind rings and the `hollow`/`solid` band mode. SVG export traces these same functions on the CPU (marching squares) to turn each curved shape into a vector outline.
- Stroked lines and curves (`drawLine`/`drawBezier`/`drawPolyline` and shape outlines) anti-alias by expanding each stroke into triangles with a feathered ~1px coverage fringe carried in the geometry, the edge-expansion approach of [Antigrain Geometry](https://agg.sourceforge.net/antigrain.com/index.html) (Maxim Shemanarev) and [NanoVG](https://github.com/memononen/nanovg) (Mikko Mononen), reimplemented independently.
- The 3D material finishes reimplement published shading techniques: the Blinn-Phong specular highlight (Jim Blinn, *Models of Light Reflection for Computer Synthesized Pictures*, SIGGRAPH 1977); the warm-to-cool **Gooch** model (Amy and Bruce Gooch, Peter Shirley, and Elaine Cohen, *A Non-Photorealistic Lighting Model for Automatic Technical Illustration*, SIGGRAPH 1998); and the Fresnel falloff behind the **rim** glow and the **iridescent** sheen (Christophe Schlick's approximation, *An Inexpensive BRDF Model for Physically-Based Rendering*, 1994), with the iridescent rainbow read from the same Inigo Quilez cosine palette above. The cel (toon) shading and the wrap-based subsurface glow are common real-time idioms.
- The SDF glyph atlas behind `textMode(.atlas)` follows Chris Green's signed-distance-field text method (Valve, ["Improved Alpha-Tested Magnification for Vector Textures and Special Effects"](https://steamcdn-a.akamaihd.net/apps/valve/2007/SIGGRAPH2007_AlphaTestedMagnification.pdf), SIGGRAPH 2007), with the distance fields generated by the exact separable Euclidean distance transform of [Felzenszwalb and Huttenlocher](https://cs.brown.edu/people/pfelzens/dt/) ("Distance Transforms of Sampled Functions", 2012).
- Rendering happens in linear light (blending and MSAA resolve in linear space, into sRGB-encoded targets) with a small triangular-PDF dither on the 8-bit output to ease gradient banding; the per-pixel dither value comes from Dave Hoskins' [Hash without Sine](https://www.shadertoy.com/view/4djSRW).
- `curlNoise` follows the curl-noise method for divergence-free flow (Robert Bridson and colleagues, "Curl-Noise for Procedural Fluid Flow", 2007).
- The GPU compute prelude (the hashing, value noise, `curlNoise`, and disc sampling a `ComputeKernel` gets for free) reimplements those same published techniques in Metal: Dave Hoskins' [Hash without Sine](https://www.shadertoy.com/view/4djSRW), the value-noise lattice from [The Book of Shaders](https://thebookofshaders.com/11/), and the curl-of-a-noise-potential construction, written independently.
- `randomGaussian` uses the Marsaglia polar method for normal-distributed samples.
- The named `Easing` curves are Robert Penner's easing equations, written from the formulas catalogued at [easings.net](https://easings.net) (Andrey Sitnik and Ivan Solovev).
- `@Smoothed` and `OneEuroFilter` implement the [1€ filter](https://gery.casiez.net/1euro/) for adaptive input smoothing (Géry Casiez, Nicolas Roussel, and Daniel Vogel, *1€ Filter: A Simple Speed-based Low-pass Filter for Noisy Input in Interactive Systems*, CHI 2012), written from the paper.
- The `Colormap` ramps carry the canonical public colormap data: `viridis`/`magma`/`inferno`/`plasma`/`cividis` from [matplotlib](https://matplotlib.org) (CC0), `turbo` from Google (Apache-2.0), and `rocket`/`mako` from [seaborn](https://seaborn.pydata.org) (BSD-3).
- `Color(kelvin:)` maps a blackbody color temperature to sRGB with [Tanner Helland's approximation of the Planckian locus](https://tannerhelland.com/2012/09/18/convert-temperature-rgb-algorithm-code.html), written from the published formula.
- The perceptual color spaces (`OKLab`/`OKLCH`/`OKHSL`, and the gamut mapping behind `Color.mix`) implement [Björn Ottosson's Oklab](https://bottosson.github.io/posts/oklab/) and its [Okhsl picker space](https://bottosson.github.io/posts/colorpicker/), with out-of-gamut colors brought back by chroma reduction at constant lightness and hue following his [sRGB gamut-clipping method](https://bottosson.github.io/posts/gamutclipping/) (reference code public domain/MIT), written from the published math.
- OSC (`OllinOSC`) implements the [OSC 1.0 wire format](https://opensoundcontrol.stanford.edu/spec-1_0.html) from the specification, over UDP on `Network.framework`. Its API takes after openFrameworks' `ofxOsc` and OPENRNDR's `orx-osc`, read for approach and written independently; no OSC library is vendored.
- MIDI (`OllinMIDI`) speaks the MIDI 1.0 message format, parsed and encoded from the specification, over Apple's Core MIDI. Its API takes after openFrameworks' `ofxMidi` and OPENRNDR's `orx-midi`, read for approach and written independently; no MIDI library is vendored.
- Syphon (`OllinSyphon`) shares live GPU frames with other Mac apps over the vendored [Syphon Framework](https://github.com/Syphon/Syphon-Framework) (Metal portion, see [Bundled third-party code](#bundled-third-party-code)), wrapped behind Ollin's own `SyphonServer`/`SyphonClient`. The API takes after openFrameworks' `ofxSyphon`.
- Physics (`OllinPhysics`) has two sides. The soft side (particles, springs, soft bodies) is a from-scratch Verlet solver with position-based constraint relaxation, following the approach in Thomas Jakobsen's ["Advanced Character Physics"](https://www.cs.cmu.edu/afs/cs/academic/class/15462-s13/www/lec_slides/Jakobsen.pdf) (GDC 2001). The rigid side (bodies with rotation, polygon colliders, joints, and stable stacking) is backed by the vendored [Box2D](https://github.com/erincatto/box2d) engine (see [Bundled third-party code](#bundled-third-party-code)), wrapped behind the same `World`. The API takes after openFrameworks' `ofxBox2d` and p5 / matter.js.
- Video playback (`OllinVideo`) plays files through Apple's [AVFoundation](https://developer.apple.com/documentation/avfoundation) (`AVPlayer` with a video output), with each decoded frame surfaced as a Metal texture through `CVMetalTextureCache`; no codec or media library is vendored. The sketch-facing shape (load, `play`, draw the current frame) takes after p5.js's video element and openFrameworks' `ofVideoPlayer`, written independently.
- Record3D RGBD (`OllinRecord3D`) brings an iPhone's color-plus-depth into a sketch as a 3D point cloud, both from recorded `.r3d` clips and from a tethered phone's live USB stream, captured by [Record3D](https://record3d.app) (Marek Šimoník), an ARKit color-plus-depth recorder. Both formats are read clean-room from their public structure with Apple-native frameworks only (`Compression` for LZFSE depth, ImageIO for JPEG color, a minimal ZIP read, and the standard `usbmuxd` device tunnel for the live stream); the `record3d` library that documents them is LGPL-2.1, so it's a product reference, never copied or vendored. The kind of world-facing depth feed an Intel RealSense once gave openFrameworks, by way of an iPhone.
- The depth-of-field accumulation (sandpainting) rendering (bokeh that *emerges* from scattering many faint additive samples by their distance from a focal plane, with chromatic fringes from shifting the colour channels apart) follows Anders Hoff's ([inconvergent](https://inconvergent.net/2019/depth-of-field/)) depth-of-field and colour-shift technique, written from the essays. [Blurry](https://github.com/Domenicobrz/Blurry) (Domenicobrz, MIT) is the reference implementation, read for approach and written independently.
- The depth-of-field effect filter (`.defocus`, blurring a layer by a depth map) is a circle-of-confusion bokeh gather with near/far field separation, combining two techniques: the **near/far split** (foreground accumulated with its own coverage and composited over the background, so a blurry foreground hides an in-focus subject behind it) from Catlike Coding's [Depth of Field](https://catlikecoding.com/unity/tutorials/advanced-rendering/depth-of-field/) tutorial, and the per-field **running-average golden-angle gather** (every tap counts, so overlapping bokeh blends without noise) from Dennis Gustafsson's [Bokeh depth of field in a single pass](http://blog.tuxedolabs.com/2018/05/04/bokeh-depth-of-field-in-single-pass.html) (Tuxedo Labs), studied through its expression in [LYGIA](https://lygia.xyz)'s `sample/dof` (Prosperity-licensed, read for the technique, reimplemented). James George's openFrameworks `ofxDOF` is further prior art (no license, concept only). Written independently.
- The ambient-occlusion combine (`.ambientOcclusion`, darkening a layer's crevices by a depth map) reconstructs view-space position and normal from the depth (the normal via the best-of-paired-neighbours method from [Wicked Engine](https://wickedengine.net/2019/09/improved-normal-reconstruction-from-depth/)'s "improved normal reconstruction from depth"), then estimates occlusion with a view-space hemisphere kernel (the canonical SSAO recipe: Crytek's original; [john-chapman](https://john-chapman-graphics.blogspot.com/2013/01/ssao-tutorial.html) / [LearnOpenGL](https://learnopengl.com/Advanced-Lighting/SSAO), with the standard depth range-check), using a **dense low-discrepancy (Fibonacci) kernel** so it needs no per-pixel rotation and stays temporally stable, finished with a depth-aware blur. Written from the techniques, independently.
- The image-`Filter` catalog (color, tone, blur, stylize, retro, and distortion passes) reimplements well-known image-processing techniques, each written from the published method: the **oil-paint** abstraction is the Kuwahara region filter (Kyprianidis et al., ["Anisotropic Kuwahara Filtering on the GPU", *GPU Pro*](https://www.kyprianidis.com/)); the **3×3 median** uses Morgan McGuire's [min/max sorting-network median](https://casual-effects.com/research/McGuire2008Median/); **vibrance** follows CeeJayDK's [SweetFX](https://github.com/CeeJayDK/SweetFX) formulation; **bilateral** smoothing, **emboss**, **Sobel** edges/**normalMap**, **CMYK halftone**, **solarize**, **levels**, **scanlines**/**glitch**/**CRT**, and the **kaleidoscope**/**swirl**/**bulge**/**wave**/**ripple**/**polar**/**perturb** uv warps are standard real-time idioms (the radial-lens warps after Inigo Quilez and the [LYGIA](https://lygia.xyz) `distort` catalog, read for technique). The branchless RGB↔HSV behind `colorama` is Sam Hocevar's. The full menu was cross-read against LYGIA, [ofxFX](https://github.com/patriciogonzalezvivo/ofxFX), OPENRNDR's [orx-fx](https://github.com/openrndr/orx), and [AsyncGraphics](https://github.com/heestand-xyz/AsyncGraphics) (which set the effect-object/compositing shape) for which effects exist and how they're approached, then written independently.
- The simulation fields (`SimField`/`Sim`, a layer that evolves on the GPU each frame) reimplement classic cellular models, written from the technique: **reaction-diffusion** is the Gray-Scott model (John E. Pearson, ["Complex Patterns in a Simple System"](https://www.science.org/doi/10.1126/science.261.5118.189), *Science* 1993), with the GPU discretization and the dividing-cell feed/kill defaults following Karl Sims' [reaction-diffusion tutorial](https://www.karlsims.com/rd.html); **Game of Life** is John Conway's cellular automaton (B3/S23). Both run as fragment passes over the persistent ping-pong layer, written independently.
- The **fluid** simulation (`.fluid`, a real-time incompressible flow that carries colour) reimplements the stable-fluids method, written from the technique: semi-Lagrangian advection and the Jacobi pressure-projection that keeps the flow divergence-free are Jos Stam's ["Stable Fluids"](https://www.dgp.toronto.edu/people/stam/reality/Research/pdf/ns.pdf) (1999), realized on the GPU after Mark Harris' ["Fast Fluid Dynamics Simulation on the GPU"](https://developer.nvidia.com/gpugems/gpugems/part-vi-beyond-triangles/chapter-38-fast-fluid-dynamics-simulation-gpu) (*GPU Gems* 38); the **vorticity confinement** that restores swirling detail is from Fedkiw, Stam & Jensen's ["Visual Simulation of Smoke"](https://web.stanford.edu/class/cs237d/smoke.pdf) (2001). The splat-driven real-time arrangement and parameter feel were studied from Pavel Dobryakov's [WebGL-Fluid-Simulation](https://github.com/PavelDoGreat/WebGL-Fluid-Simulation) (MIT). Written independently.
- Computer vision (`OllinVision`) runs on Apple's own on-device stack ([Vision](https://developer.apple.com/documentation/vision) and Core ML for the perception, [AVFoundation](https://developer.apple.com/documentation/avfoundation) for camera capture), hardware-accelerated on the Neural Engine where present. No computer-vision library is vendored; the framework calls the OS. Its sketch-facing ergonomics (results as typed values you read in `draw()`) take after openFrameworks' [`ofxCv`](https://github.com/kylemcdonald/ofxCv), read for approach and written independently.

### Directions ahead

These projects are inspirations for parts of Ollin that don't exist yet. Ollin studies how they work and reimplements the ideas rather than depending on them, the same as it treats the frameworks above. They're listed now so the influence is on record before the code lands.

| Project | License | What Ollin studies it for |
|---|---|---|
| [LYGIA](https://github.com/patriciogonzalezvivo/lygia) | Prosperity PL 3.0.0 (noncommercial) | A catalog of shader functions for well-known techniques like SDFs, noise, blends, and color conversions. Ollin reads it to learn the approach, then writes its own and credits the original technique. |
| [Hydra](https://github.com/ojack/hydra) | AGPL-3.0 | How a chainable, video-synth-style API makes mixing visuals feel easy. A direction for a future livecoding mode. |
| [Shader Park](https://github.com/shader-park) | MIT | How to compose and blend SDF shapes, and its livecoding environment. |
| [ofxFX](https://github.com/patriciogonzalezvivo/ofxFX) | MIT | How shader effects become chainable, mixable objects: filters, blends, LUT color grading, and generative passes over ping-pong buffers. A reference for the layered-effects work. |

Meta Spark, the AR studio Meta has since discontinued, is the reference for an eventual AR mode. There's no source to credit, just the idea of starting from templates.

## Status & contributing

Ollin is **alpha and pre-1.0**, developed in the open. Practically, that means:

- **The API will change.** Names, signatures, and structure can shift between commits; there's no tagged release or SemVer guarantee until 1.0.
- **No support guarantee.** This is built nights and weekends. Issues and discussions get read, but a response time isn't promised.
- **macOS 26+ and a Metal-capable GPU are required.** That's the trade described up top, not a gap to be filled later: no Linux or Windows path, by design.

That said, contributions and ideas are genuinely welcome. [`ROADMAP.md`](ROADMAP.md) is the best source of bite-size work; its [Up next](ROADMAP.md#up-next) section maps onto small, self-contained pull requests. For anything larger, please open an issue to discuss it before sending a big change.
