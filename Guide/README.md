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

Read the chapters in order the first time. Each builds only on the ones before it, and it helps to know roughly what each part is going to ask of you.

- **Part I, chapters 1 to 9.** Around 120 pages. The base everything else stands on, and the one part with no way around it.
- **Part II, chapters 10 to 15.** Around 90 pages. Chapter 10 is the one the rest of the guide leans on hardest, so do not skim it.
- **Part III, chapters 16 to 20.** Around 80 pages, the shortest part. Chapter 17 is its gate, since 18, 19 and 20 all assume you can read a shader.
- **Part IV, chapters 21 to 26.** Around 135 pages, the longest. Chapter 21 is its gate, and chapter 24 also wants the physics from chapter 11.
- **Part V, chapters 27 to 32.** Around 125 pages, and the loosest. Its chapters barely depend on each other, so read the ones you need in whatever order you like.

Four chapters are better with hardware beyond the Mac, and every one of them leads with the path that needs none. [Chapter 27](27-DepthAndThePhone.md) wants an iPhone with a LiDAR sensor, [Chapter 28](28-SoundAndControl.md) a microphone and later a MIDI controller, [Chapter 30](30-Seeing.md) a webcam, and [Chapter 32](32-Installations.md) a lighting node or a projector. Skip any of them and nothing later in the guide breaks.

Work along in the live-reload host (`swift run OllinLive path/to/YourSketch.swift`), which recompiles on save so the window never closes while you experiment. [Chapter 1](01-HelloOllin.md) sets this up.

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
8. **[Words](08-Words.md).** Drawing text, the three kinds of font, per-glyph motion, letters as geometry you can warp and respace, and typesetting in any script: vertical, justified, and with punctuation that hangs.
9. **[Pictures and data](09-Pictures.md).** A picture as something to read rather than display: marks, stipple, one unbroken line, thread between pins, halftone, sorted pixels, and numbers from CSV and JSON.

### Part II: Systems that come alive

10. **[Vectors, gently](10-Vectors.md).** Vectors as arrows; position, velocity, acceleration; steering toward a target.
11. **[Forces and physics](11-ForcesAndPhysics.md).** Forces by hand, then a physics world: springs and particles, rigid bodies and joints, grabbing with the mouse.
12. **[Flocks and swarms](12-FlocksAndSwarms.md).** One creature that steers (seek, arrive, wander), then flocking from three local rules, then a line that grows into coral.
13. **[Growing things](13-GrowingThings.md).** A recursive tree, L-system grammars, the chaos game and its fractal cousins, growth that claims space, frost from frozen walkers, and tiles that must agree.
14. **[Fields and flow](14-FieldsAndFlow.md).** A direction at every point: streamlines, evenly spaced flow, riding particles, and attractors found in formulas.
15. **[Shapes as material](15-ShapesAsMaterial.md).** Geometry you hold and edit: booleans, offsets, strokes as regions, Voronoi mosaics, packing, and hatching for pen plotters.

### Part III: Pixels and light

16. **[Layers and effects](16-LayersAndEffects.md).** Off-screen layers, GPU filters, compositing, feedback, accumulation, HDR.
17. **[Your first shader](17-YourFirstShader.md).** Per-pixel thinking, uv space, writing a `shade` function, chaining visuals.
18. **[Iterated forms](18-IteratedForms.md).** Pictures that are the density of an orbit rather than a drawn shape: the chaos game, fractal flames, the Buddhabrot, circles used as mirrors, Kleinian and Schottky groups, chaotic maps, the bifurcation diagram, and escape-time fractals.
19. **[Simulations on a grid](19-GridSimulations.md).** Fields that carry their own state on the GPU: cellular automata, sand, reaction-diffusion, multi-scale Turing, fluid, ripples, and watercolor.
20. **[Simulations made of particles](20-ParticleSimulations.md).** A buffer of individuals updated by one small program: a million grains, slime mold, ant colonies, Particle Life, crowds at scale, SPH fluid and jellies, and evolution.

### Part IV: The third dimension

21. **[3D, gently](21-3DGently.md).** A camera, solids, lights and materials, air you can see, meshes and their maps, and the depth buffer's own effects.
22. **[Meshes, maps, and materials](22-Meshes.md).** Meshes from a file and from other meshes, pictures that decide what a surface is texel by texel, and the finishes you set with numbers: metal and dielectric, environments as the light, glass, coated paint, cloth, and skin.
23. **[Landscapes and multitudes](23-Landscapes.md).** Ground grown from noise and weathered by rain, then the four ways to draw more copies of something than you could ever place: a field of particles, instanced meshes, a world the camera trims, and grass that is never built.
24. **[Worlds with weight](24-WorldsWithWeight.md).** Rigid bodies in the 3D scene: stacking and contact, asking what a body would hit, collision groups, degrees of freedom, machines made out of joints, and snapshots of a settled world.
25. **[Characters, vehicles, and cloth](25-CharactersAndCloth.md).** The three things a rigid body models badly: a figure that walks, a vehicle on sprung wheels, and cloth, ropes, ragdolls and water.
26. **[Sculpting with fields](26-SculptingWithFields.md).** Distance fields that merge and blend, in 2D and raymarched 3D, then the finish: measured materials, environments, glass, and light that bounces.

### Part V: Out into the world

27. **[Depth and the iPhone as a sensor](27-DepthAndThePhone.md).** Point clouds, recorded and live RGBD, the phone's body, hand, and gaze streams, and scanning the room you're in.
28. **[Sound and control](28-SoundAndControl.md).** Hearing loudness, spectrum, beats, speech and sound events, then the hands on the other side: MIDI, OSC, and game controllers, all bound to the same knobs.
29. **[Making sound](29-MakingSound.md).** A sketch that plays: synths and the voices inside them, instruments built by patching or recorded, the modelled string, struck shape, bow and tube, then rhythms, scales, chords and tunings, sonification, and sound placed in a room.
30. **[Seeing](30-Seeing.md).** The webcam as input; faces, hands, bodies, edges, and motion as typed values; video as material.
31. **[Sharing and performing](31-SharingAndPerforming.md).** Stills, video, GIF, SVG for plotters, prints and 3D prints, USDZ and spatial video, reproducibility, describable output, feeding other apps, handing the work over, and live coding on stage.
32. **[Installations](32-Installations.md).** A piece that stays where it is: light instead of pixels through DMX and LED maps, the cost row when it gets slow, and everything a room does to a sketch left running for weeks.

### Appendices

- **[A. Just enough Swift](A-JustEnoughSwift.md).** The language, for people arriving from other languages.
- **[B. Just enough math, visually](B-JustEnoughMath.md).** Every math idea in the guide, each with a picture.
- **[C. Coming from p5.js and Processing](C-ComingFromP5.md).** A side-by-side translation.
- **[D. The complete toolbox](D-CompleteToolbox.md).** Everything Ollin can do, one line each, with where it's taught and where it's documented.

---

Found something confusing, or got stuck anywhere? That's a bug in the guide, not in you. Please [open an issue](https://github.com/eaviles/Ollin/issues).
