#### <sup>[Ollin](../README.md) → Guide</sup>

---

# The Ollin Guide

*A practical introduction to creative coding.*

This guide teaches creative coding from zero, using [Ollin](../README.md). You write small programs called sketches that draw, move, and react, and along the way you pick up the techniques the field is built on: randomness, noise, forces, flocks, shaders, simulation, 3D. Each chapter teaches a few ideas through short runnable steps and ends with a finished piece you made yourself.

<img src="Images/01-HelloOllin/HelloMotion.jpg" alt="A ring of drifting, breathing circles: the Chapter 1 piece" width="560">

**Who it's for.** Anyone who can program a little, in any language. You don't need to know Swift (the guide teaches what you need as it comes up, and [Appendix A](A-JustEnoughSwift.md) is a primer), and you don't need a background in math, graphics, or shaders. If you can write a loop and a function, you can start.

**What you need.** A Mac running macOS 26 or newer, and this repository. That's it.

**Where this sits.** The guide is the narrative layer: read it start to finish and it teaches you to think in sketches. The [API reference](../Docs/README.md) answers "what does this call do", and [`Examples/`](../Examples/) is working code to browse. Chapters link into both as you go.

## Four promises

Guides like this tend to fail in known ways: a concept appears out of nowhere and you're stuck, the examples no longer compile, or the theory runs three chapters ahead of anything you can see. This guide is built around four promises:

1. **Nothing arrives unexplained.** Every concept is introduced before it's used, with a picture. When math shows up, it comes with a visual and a plain-words intuition, never notation alone. If a page loses you anyway, [Appendix B](B-JustEnoughMath.md) re-explains every math idea in the guide, visually.
2. **Every listing runs.** Each code listing is a real file under [`Figures/`](Figures/), compiled and rendered by a tool in this repository. If the framework changes underneath it, the build breaks before the guide can lie to you.
3. **Every image is made by the code next to it.** Figures and diagrams are rendered by Ollin itself from committed source. You can open any of them, run it, and mess with it.
4. **Practice first.** You see something on your canvas within the first page of every chapter, and everything a chapter teaches ends up in one finished piece.

Both kinds of image are already at work on this page: the piece above is [`Figures/01-HelloOllin/HelloMotion.swift`](Figures/01-HelloOllin/HelloMotion.swift) rendered at a fixed frame, and this Chapter 1 diagram is a sketch too ([`CoordinateSystem.swift`](Figures/01-HelloOllin/CoordinateSystem.swift)):

<img src="Images/01-HelloOllin/CoordinateSystem.jpg" alt="The canvas coordinate system, drawn by Ollin" width="680">

## How to read it

Read the chapters in order the first time; each builds only on the ones before it. Work along in the live-reload host (`swift run OllinLive path/to/YourSketch.swift`), which recompiles on save so the window never closes while you experiment. Chapter 1 sets this up.

If you're coming from p5.js or Processing, [Appendix C](C-ComingFromP5.md) maps what you already know onto Ollin. If you're new to Swift, [Appendix A](A-JustEnoughSwift.md) and the [Swift quick reference](../Docs/Swift.md) cover just enough of the language to be productive.

## Contents

### Part I: Seeing something move

1. **[Hello, Ollin](01-HelloOllin.md).** Your first sketch, the draw loop, coordinates, shapes, and motion by default. Plus the workflow the rest of the guide uses: live reload and tunable knobs.
2. **[Color that works](02-Color.md).** Naming colors, thinking in hue, mixing that trusts your eye, palettes and ramps, gradients as paint.
3. **[Motion and time](03-MotionAndTime.md).** Time, shaping functions as curves you can see (map, lerp, smoothstep, easing), sine and cosine without fear, timelines.
4. **[Randomness](04-Randomness.md).** Random values, seeds, choices, distributions, and why reproducibility matters.
5. **[Noise](05-Noise.md).** What Perlin noise is, what it's for, and how to drive motion and form with it.
6. **[Grids and repetition](06-GridsAndRepetition.md).** The grid helper, moving the paper with transforms, symmetry by repetition, and Truchet tiles.
7. **[Words and pictures](07-WordsAndPictures.md).** Drawing text, the three font kinds, text as geometry, images as material, reading pixels.

### Part II: Systems that come alive

8. **[Vectors, gently](08-Vectors.md).** Vectors as arrows; position, velocity, acceleration; steering toward a target.
9. **[Forces and physics](09-ForcesAndPhysics.md).** Forces by hand, then a physics world: springs and particles, rigid bodies and joints, grabbing with the mouse.
10. **[Flocks and swarms](10-FlocksAndSwarms.md).** One creature that steers (seek, arrive, wander), then flocking from three local rules, then a line that grows into coral.
11. **[Growing things](11-GrowingThings.md).** A recursive tree, L-system grammars, growth that claims space, frost from frozen walkers, and tiles that must agree.
12. **[Fields and flow](12-FieldsAndFlow.md).** A direction at every point: streamlines, evenly spaced flow, riding particles, and attractors found in formulas.
13. **[Shapes as material](13-ShapesAsMaterial.md).** Geometry you hold and edit: booleans, offsets, strokes as regions, Voronoi mosaics, packing, and hatching for pen plotters.

### Part III: Pixels and light

14. **[Layers and effects](14-LayersAndEffects.md).** Off-screen layers, GPU filters, compositing, feedback, accumulation, HDR.
15. **[Your first shader](15-YourFirstShader.md).** Per-pixel thinking, uv space, writing a `shade` function, chaining visuals.
16. **[Simulations](16-Simulations.md).** Game of Life, reaction-diffusion, fluid, and a million particles on the GPU.

### Part IV: The third dimension

17. **[3D, gently](17-3DGently.md).** A camera, solid shapes, lights and materials, and moving through a scene.
18. **[Sculpting with fields](18-SculptingWithFields.md).** Distance fields that merge and blend, in 2D and raymarched 3D.
19. **[Depth and the iPhone as a sensor](19-DepthAndThePhone.md).** Point clouds, recorded and live RGBD, and scanning the room you're in.

### Part V: Out into the world

20. **[Sound and control](20-SoundAndControl.md).** Hearing loudness, spectrum, and beats; MIDI knobs and OSC faders; one parameter played from anywhere.
21. **[Seeing](21-Seeing.md).** The webcam as input; faces, hands, bodies, edges, and motion as typed values; video as material.
22. **[Sharing and performing](22-SharingAndPerforming.md).** Stills, video, GIF, SVG for plotters, feeding other apps, and live coding on stage.

### Appendices

- **[A. Just enough Swift](A-JustEnoughSwift.md).** The language, for people arriving from other languages.
- **[B. Just enough math, visually](B-JustEnoughMath.md).** Every math idea in the guide, each with a picture.
- **[C. Coming from p5.js and Processing](C-ComingFromP5.md).** A side-by-side translation.
- **[D. The complete toolbox](D-CompleteToolbox.md).** Everything Ollin can do, one line each, with where it's taught and where it's documented.

---

Found something confusing, or got stuck anywhere? That's a bug in the guide, not in you. Please [open an issue](https://github.com/eaviles/Ollin/issues).
