#### <sup>[Ollin](../README.md) → Guide</sup>

---

# The Ollin Guide

*A practical introduction to creative coding.*

This guide teaches creative coding from zero, using [Ollin](../README.md). You write small programs called sketches that draw, move, and react, and along the way you pick up the techniques the field is built on: randomness, noise, forces, flocks, shaders, simulation, 3D. Each chapter teaches a few ideas through short runnable steps and ends with a finished piece you made yourself.

<img src="Images/01-HelloOllin/HelloMotion.jpg" alt="A ring of drifting, breathing circles: the [Chapter 1](01-HelloOllin.md) piece" width="560">

**Who it's for.** Anyone who can program a little, in any language. You don't need to know Swift (the guide teaches what you need as it comes up, and [Appendix A](A-JustEnoughSwift.md) is a primer), and you don't need a background in math, graphics, or shaders. If you can write a loop and a function, you can start.

**What you need.** A Mac running macOS 26 or newer, and this repository. That's it.

**Where this sits.** The guide is the narrative layer: read it start to finish and it teaches you to think in sketches. The [API reference](../Docs/README.md) answers "what does this call do", and [`Examples/`](../Examples/) is working code to browse. Chapters link into both as you go.

## Four promises

Guides like this tend to fail in known ways: a concept appears out of nowhere and you're stuck, the examples no longer compile, or the theory runs three chapters ahead of anything you can see. This guide is built around four promises:

1. **Nothing arrives unexplained.** Every concept is introduced before it's used, with a picture. When math shows up, it comes with a visual and a plain-words intuition, never notation alone. If a page loses you anyway, [Appendix B](B-JustEnoughMath.md) re-explains every math idea in the guide, visually.
2. **Every listing runs.** Each code listing is a real file under [`Figures/`](Figures/), compiled and rendered by a tool in this repository. If the framework changes underneath it, the build breaks before the guide can lie to you.
3. **Every image is made by the code next to it.** Figures and diagrams are rendered by Ollin itself from committed source. You can open any of them, run it, and mess with it.
4. **Practice first.** You see something on your canvas within the first page of every chapter, and everything a chapter teaches ends up in one finished piece.

Both kinds of image are already at work on this page: the piece above is [`Figures/01-HelloOllin/HelloMotion.swift`](Figures/01-HelloOllin/HelloMotion.swift) rendered at a fixed frame, and this [Chapter 1](01-HelloOllin.md) diagram is a sketch too ([`CoordinateSystem.swift`](Figures/01-HelloOllin/CoordinateSystem.swift)):

<img src="Images/01-HelloOllin/CoordinateSystem.jpg" alt="The canvas coordinate system, drawn by Ollin" width="680">

## How to read it

Read the chapters in order the first time; each builds only on the ones before it. They also grow as the subject deepens: Chapter 18 is several times the size of its neighbors, so budget for it. Anything needing hardware beyond the Mac always leads with the path every reader can follow. Work along in the live-reload host (`swift run OllinLive path/to/YourSketch.swift`), which recompiles on save so the window never closes while you experiment. [Chapter 1](01-HelloOllin.md) sets this up.

If you're coming from p5.js or Processing, [Appendix C](C-ComingFromP5.md) maps what you already know onto Ollin. If you're new to Swift, [Appendix A](A-JustEnoughSwift.md) and the [Swift quick reference](../Docs/Swift.md) cover just enough of the language to be productive.

## Contents

### Part I: Seeing something move

1. **[Hello, Ollin](01-HelloOllin.md).** Your first sketch, the draw loop, coordinates, shapes, and motion by default. Plus the workflow the rest of the guide uses: live reload and tunable knobs.
2. **[Color that works](02-Color.md).** Naming colors, thinking in hue, mixing that trusts your eye, palettes and ramps, gradients as paint.
3. **[Motion and time](03-MotionAndTime.md).** Time, shaping functions as curves you can see (map, lerp, smoothstep, easing), sine and cosine without fear, timelines.
4. **[Randomness](04-Randomness.md).** Random values, seeds, choices, distributions, and why reproducibility matters.
5. **[Noise](05-Noise.md).** What Perlin noise is, what it's for, and how to drive motion and form with it.
6. **[Grids and repetition](06-GridsAndRepetition.md).** The grid helper, moving the paper with transforms, symmetry and the kaleidoscope fold, clipping, and the divisions that aren't square: hex, triangle, recursive panels, mazes, and circle foam.
7. **[Tiles that cover the plane](07-Tiles.md).** Tiles that agree at their edges: Truchet, hitomezashi, the never-repeating sets (Penrose, Wang, girih, and the single-shape spectre), and hyperbolic tiling on the Poincaré disk.
8. **[Words and pictures](08-WordsAndPictures.md).** Drawing text, the three font kinds, text as geometry, typesetting in any script, pictures reduced to marks, and numbers from CSV and JSON.

### Part II: Systems that come alive

9. **[Vectors, gently](09-Vectors.md).** Vectors as arrows; position, velocity, acceleration; steering toward a target.
10. **[Forces and physics](10-ForcesAndPhysics.md).** Forces by hand, then a physics world: springs and particles, rigid bodies and joints, grabbing with the mouse.
11. **[Flocks and swarms](11-FlocksAndSwarms.md).** One creature that steers (seek, arrive, wander), then flocking from three local rules, then a line that grows into coral.
12. **[Growing things](12-GrowingThings.md).** A recursive tree, L-system grammars, the chaos game and its fractal cousins, growth that claims space, frost from frozen walkers, and tiles that must agree.
13. **[Fields and flow](13-FieldsAndFlow.md).** A direction at every point: streamlines, evenly spaced flow, riding particles, and attractors found in formulas.
14. **[Shapes as material](14-ShapesAsMaterial.md).** Geometry you hold and edit: booleans, offsets, strokes as regions, Voronoi mosaics, packing, and hatching for pen plotters.

### Part III: Pixels and light

15. **[Layers and effects](15-LayersAndEffects.md).** Off-screen layers, GPU filters, compositing, feedback, accumulation, HDR.
16. **[Your first shader](16-YourFirstShader.md).** Per-pixel thinking, uv space, writing a `shade` function, chaining visuals.
17. **[Simulations](17-Simulations.md).** Cellular automata, sand, reaction-diffusion, fluids and waves, a million particles, crowds that organize themselves, and evolution, nearly all of it on the GPU.

### Part IV: The third dimension

18. **[3D, gently](18-3DGently.md).** A camera, solids, lights and materials, meshes and their maps, terrain, instancing at scale, and a physics world with vehicles, characters, cloth, and water. By far the guide's biggest chapter.
19. **[Sculpting with fields](19-SculptingWithFields.md).** Distance fields that merge and blend, in 2D and raymarched 3D, then the finish: measured materials, environments, glass, and light that bounces.
20. **[Depth and the iPhone as a sensor](20-DepthAndThePhone.md).** Point clouds, recorded and live RGBD, the phone's body, hand, and gaze streams, and scanning the room you're in.

### Part V: Out into the world

21. **[Sound and control](21-SoundAndControl.md).** Hearing loudness, spectrum, beats, and speech; making sound with synths, physical models, and music the sketch composes; MIDI, OSC, and game controllers.
22. **[Seeing](22-Seeing.md).** The webcam as input; faces, hands, bodies, edges, and motion as typed values; video as material.
23. **[Sharing and performing](23-SharingAndPerforming.md).** Stills, video, GIF, SVG for plotters, prints and 3D prints, feeding other apps, lighting rigs, pieces that run on a wall for weeks, and live coding on stage.

### Appendices

- **[A. Just enough Swift](A-JustEnoughSwift.md).** The language, for people arriving from other languages.
- **[B. Just enough math, visually](B-JustEnoughMath.md).** Every math idea in the guide, each with a picture.
- **[C. Coming from p5.js and Processing](C-ComingFromP5.md).** A side-by-side translation.
- **[D. The complete toolbox](D-CompleteToolbox.md).** Everything Ollin can do, one line each, with where it's taught and where it's documented.

---

Found something confusing, or got stuck anywhere? That's a bug in the guide, not in you. Please [open an issue](https://github.com/eaviles/Ollin/issues).
