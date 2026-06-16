#### <sup>[Ollin](../README.md) → Documentation</sup>

---

## Ollin API

Reference for Ollin's drawing surface and helpers. The bare calls you write in `draw()` forward to an internal `Drawer` (see [How it works](../README.md#how-it-works-one-paragraph)); everything here is callable bare inside a `Sketch`.

New to Swift, coming from p5.js or JavaScript? Start with the [Swift primer](./Swift.md) — just enough of the language to be productive in `draw()`.

### Core

- [`Sketch`](./Sketch.md) - the lifecycle (`setup`/`draw`), temporal state (`time`, `frameCount`, …), and loop control
- [`Canvas`](./Canvas.md) - `scale`, the `canvasSize` export presets, and the preview window (`windowMode`)

### Drawing

- [`Drawing`](./Drawing.md) - `background`, `fill`/`stroke`, the shapes, and the transform stack
- [`Accumulation`](./Accumulation.md) - `noClear` to keep the canvas across frames so drawing piles up (long exposures, paint-on-canvas, light accumulation)
- [`HDR & tone-mapping`](./HDR.md) - `toneMap` to roll bright, out-of-range light off the screen instead of clipping it (the linear-float pipeline behind every frame; the glow/bloom and sandpainting looks)
- [`Compute & GPU particles`](./Compute.md) - GPU compute over buffers and textures: `Particles` (a million updated and drawn on the GPU each frame — the "sandpainting" engine) and `Simulation` (reaction-diffusion, cellular automata, and other ping-pong texture sims), over the `ComputeKernel`/`ComputeBuffer`/`ComputeTexture` core
- [`Text`](./Text.md) - `drawText` with bitmap *and* outline (`.ttf`/`.otf`) fonts, plus `textToShapes` (text as geometry)
- [`Images`](./Images.md) - `loadImage`, `drawImage`, `tint`, and pixel access: load or author a raster image, draw it scaled or transformed, recolor it
- [`Color`](./Color.md) - the `Color` type, the OKLab family and mixing, `Ramp`s and `Palette`s, and perceptual `Colormap`s
- [`Geometry`](./Geometry.md) - the `Vector2`, `Rectangle`, `Shape`/`Contour`, and `Path` value types (including curved outlines, shape booleans, and offsetting)
- [`Voronoi & Delaunay`](./Voronoi.md) - tessellate points into vector geometry: Voronoi cells (the "crystallization" look) and the dual Delaunay triangle mesh, with Lloyd relaxation

### 3D

- [`3D`](./3D.md) - opt into a 3D camera and depth buffer: orbit a `Camera3D` (perspective or orthographic) and draw `PointCloud`s as instanced disc splats, including a live webcam depth cloud
- [`Record3D`](./Record3D.md) - `import OllinRecord3D` to turn an iPhone's color-plus-depth into a 3D point cloud — from a recorded `.r3d` file or a tethered phone's live USB stream
- [`RGBD`](./RGBD.md) - the source-agnostic `RGBDFrame` (color + depth + intrinsics) any depth source produces: unproject a point cloud, lift a single image point to metric 3D, or lift a 2D body pose into space (`Body.lifted(through:)`)
- [`Phone`](./Phone.md) - `import OllinPhone` to read a tethered iPhone's live on-device ARKit sensor stream from Ollin's own capture app: a 3D body skeleton, a face mesh with expression blendshapes, and device motion, over the USB cable

### Generators

- [`Random`](./Random.md) - `random`, `randomGaussian`, and the `randomVector`/`ring` scatter helpers
- [`Noise`](./Noise.md) - Perlin `noise`, `signedNoise`, and `curlNoise` flow fields

### Helpers

- [`Math`](./Math.md) - `map`, `dist`, and `lerp`
- [`Animation`](./Animation.md) - the `Easing` curves, `@Eased` (ease toward a target), and `@Smoothed` (smooth a noisy signal)
- [`Parameters`](./Parameters.md) - `@Param` tunable knobs: live sliders in the inspector, optional smoothing, and binding from OSC or MIDI
- [`Input`](./Input.md) - mouse and keyboard
- [`Audio`](./Audio.md) - `import OllinAudio` for microphone, file, and oscillator sources, analyzed into `amplitude`/`spectrum`/band values you read in `draw()`

### Simulation

- [`Physics`](./Physics.md) - `import OllinPhysics` for a `World` you step each frame so motion comes from simulation: a soft Verlet side (particles, springs, disk collisions) and a rigid side (bodies, colliders, joints, backed by Box2D)

### Integration

- [`OSC`](./OSC.md) - `import OllinOSC` to send and receive OSC messages over UDP (to and from TouchOSC, Max/MSP, TouchDesigner, …), read in `draw()` or bound to a `@Param`
- [`MIDI`](./MIDI.md) - `import OllinMIDI` to read from and send to MIDI controllers and keyboards over Core MIDI, read in `draw()` or bound to a `@Param`
- [`Syphon`](./Syphon.md) - `import OllinSyphon` to share live visuals with other Mac apps (openFrameworks, Resolume, MadMapper, VDMX, …): publish a sketch's frames as a Syphon source, and draw an incoming Syphon feed as an `Image`
- [`Virtual camera`](./VirtualCamera.md) - `import OllinCamera` to feed a sketch's frames to the Ollin Camera system camera, so webcam apps and browser tools (Zoom, OBS, Hydra via `getUserMedia`, …) read the sketch as a live camera

### Vision

- [`Vision`](./Vision.md) - `import OllinVision` for the Mac's camera (built-in, Continuity, or external) plus Apple's on-device perception — face tracking with landmarks, hand and body pose (joint skeletons), rectangle, barcode/QR, and text (OCR) detection, contour tracing (camera frame → vector `Shape`s), and object tracking (follow a patch you point at), surfaced as typed results you read in `draw()`

### Video

- [`Video`](./Video.md) - `import OllinVideo` to play a video file into a sketch as a live image: each decoded frame arrives as a GPU texture you draw with `drawImage`, plus a CPU `snapshot()` for pixel reads and analysis

### Output

- [`Export`](./Export.md) - save frames as raster (PNG, sequences), motion (video, animated GIF), or vector (SVG, for pen plotters)

Coordinates use a **top-left origin with y increasing downward**, the same as p5, Processing, and OPENRNDR.
