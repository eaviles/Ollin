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
- [`Text`](./Text.md) - `drawText` with bitmap *and* outline (`.ttf`/`.otf`) fonts, plus `textToShapes` (text as geometry)
- [`Images`](./Images.md) - `loadImage`, `drawImage`, `tint`, and pixel access: load or author a raster image, draw it scaled or transformed, recolor it
- [`Color`](./Color.md) - the `Color` type, cosine-gradient `Palette`s, and perceptual `Colormap`s
- [`Geometry`](./Geometry.md) - the `Vector2`, `Rectangle`, `Shape`/`Contour`, and `Path` value types (including curved outlines)

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

### Vision

- [`Vision`](./Vision.md) - `import OllinVision` for the Mac's camera (built-in, Continuity, or external) plus Apple's on-device perception — face tracking with landmarks, hand and body pose (joint skeletons), rectangle, barcode/QR, and text (OCR) detection, contour tracing (camera frame → vector `Shape`s), and object tracking (follow a patch you point at), surfaced as typed results you read in `draw()`

### Output

- [`Export`](./Export.md) - save frames as raster (PNG, sequences), motion (video, animated GIF), or vector (SVG, for pen plotters)

Coordinates use a **top-left origin with y increasing downward**, the same as p5, Processing, and OPENRNDR.
