#### <sup>[Ollin](../README.md) → Guide</sup>

---

# The Ollin Guide

*A practical introduction to creative coding.*

This guide teaches creative coding from zero, using [Ollin](../README.md). You write small programs called sketches that draw, move, and react. Along the way you learn the techniques the field is built on: randomness, noise, forces, flocks, shaders, simulation, and 3D. Each chapter teaches a few ideas through short runnable steps, and it ends with a finished piece you made yourself.

<img src="https://media.ollin.art/heroes/guide-hero.jpg?v=08c6ada7" alt="The sketch each of the guide's thirty-two chapters builds, one per cell, in chapter order" width="880">

**Who it's for.** Anyone who can program a little, in any language. You don't need to know Swift, because the guide teaches what you need as it comes up, and [Appendix A](A-JustEnoughSwift.md) is a primer. You don't need a background in math, graphics, or shaders either. If you can write a loop and a function, you can start.

**What you need.** A Mac running macOS 26 or newer, and this repository. That's it.

**Where this sits.** The guide is the narrative layer. Read it from start to finish and it teaches you to think in sketches. The [API reference](../Docs/README.md) answers the question "what does this call do", and [`Examples/`](../Examples/) is working code to browse. Chapters link into both as you go.

## Four promises

Guides like this tend to fail in known ways. A concept appears out of nowhere and you're stuck. The examples no longer compile. The theory runs three chapters ahead of anything you can see. So this guide is built around four promises:

1. **Nothing arrives unexplained.** Every concept is introduced before it's used, with a picture. When math shows up, it comes with a visual and a plain-words intuition, never notation alone. If you still get lost on a page, [Appendix B](B-JustEnoughMath.md) explains every math idea in the guide again, with a picture for each.
2. **Every listing runs.** Each code listing is a real file under [`Figures/`](Figures/), compiled and rendered by a tool in this repository. If the framework changes underneath a listing, the build breaks, so the guide cannot show you code that no longer runs.
3. **Every image is made by the code next to it.** Ollin itself renders every figure and diagram from committed source. You can open any of them, run it, and change it.
4. **Practice first.** You see something on your canvas within the first page of every chapter. Everything a chapter teaches ends up in one finished piece.

Both kinds of image are already on this page. The piece above is [`Figures/01-HelloOllin/HelloMotion.swift`](Figures/01-HelloOllin/HelloMotion.swift) rendered at a fixed frame. The [Chapter 1](01-HelloOllin.md) diagram below is a sketch too, [`CoordinateSystem.swift`](Figures/01-HelloOllin/CoordinateSystem.swift):

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/01-HelloOllin/CoordinateSystem-dark.jpg">
  <img src="Images/01-HelloOllin/CoordinateSystem.jpg" alt="The canvas coordinate system, drawn by Ollin" width="680">
</picture>

## How to read it

Read the chapters in order the first time, because each one builds only on the ones before it. It also helps to know roughly what each part is going to ask of you.

- **Part I, chapters 1 to 9.** Around 120 pages. It is the base everything else stands on, so it is the one part you cannot skip.
- **Part II, chapters 10 to 15.** Around 90 pages. The rest of the guide depends on chapter 10 more than on any other chapter, so do not skim it.
- **Part III, chapters 16 to 20.** Around 80 pages, the shortest part. Chapter 17 is its gate, because chapters 18, 19 and 20 all assume you can read a shader.
- **Part IV, chapters 21 to 26.** Around 135 pages, the longest part. Chapter 21 is its gate, and chapter 24 also wants the physics from chapter 11.
- **Part V, chapters 27 to 32.** Around 125 pages, and the loosest part. Its chapters barely depend on each other, so read the ones you need in any order.

Four chapters are better with hardware beyond the Mac, and every one of them starts with what you can do on the Mac alone. For [Chapter 27](27-DepthAndThePhone.md) you want an iPhone with a LiDAR sensor, and for [Chapter 28](28-SoundAndControl.md) a microphone and later a MIDI controller. For [Chapter 30](30-Seeing.md) you want a webcam, and for [Chapter 32](32-Installations.md) a lighting node or a projector. You can skip any of them, and nothing later in the guide breaks.

Work along in the live-reload host, `swift run OllinLive path/to/YourSketch.swift`. It recompiles your sketch on save, so the window never closes while you experiment. [Chapter 1](01-HelloOllin.md) sets this up.

If you're coming from p5.js or Processing, [Appendix C](C-ComingFromP5.md) maps what you already know onto Ollin. If you're new to Swift, [Appendix A](A-JustEnoughSwift.md) and the [Swift quick reference](../Docs/Swift.md) cover just enough of the language to be productive.

## Contents

### Part I: Seeing something move

1. **[Hello, Ollin](01-HelloOllin.md).** Your first sketch, the draw loop, coordinates, shapes, and motion by default. It also sets up the workflow the rest of the guide uses: live reload and tunable parameters.
2. **[Color that works](02-Color.md).** Naming colors, thinking in hue, mixing that matches what your eye expects, palettes and ramps, and gradients used as paint.
3. **[Motion and time](03-MotionAndTime.md).** Time, shaping functions drawn as curves (map, lerp, smoothstep, easing), sine and cosine explained simply, and timelines.
4. **[Randomness](04-Randomness.md).** Random values, seeds, choices, distributions, and why reproducibility matters.
5. **[Noise](05-Noise.md).** What Perlin noise is, what it's for, and how to drive motion and form with it.
6. **[Grids and repetition](06-GridsAndRepetition.md).** The grid helper, transforms that move the paper, symmetry and the kaleidoscope fold, clipping, and divisions that aren't square: hex, triangle, recursive panels, mazes, and circle foam.
7. **[Tiles that cover the plane](07-Tiles.md).** Tiles that agree at their edges: Truchet, hitomezashi, the sets that never repeat (Penrose, Wang, girih, and the single-shape spectre), and hyperbolic tiling on the Poincaré disk.
8. **[Words](08-Words.md).** Drawing text, the three kinds of font, per-glyph motion, letters as geometry you can warp and respace, and typesetting in any script: vertical, justified, and with hanging punctuation.
9. **[Pictures and data](09-Pictures.md).** Reading a picture as data instead of displaying it: marks, stipple, one unbroken line, thread between pins, halftone, sorted pixels, and numbers from CSV and JSON.

### Part II: Systems that come alive

10. **[Vectors, gently](10-Vectors.md).** Vectors as arrows, then position, velocity, and acceleration, then steering toward a target.
11. **[Forces and physics](11-ForcesAndPhysics.md).** Forces by hand, then a physics world: springs and particles, rigid bodies and joints, grabbing with the mouse.
12. **[Flocks and swarms](12-FlocksAndSwarms.md).** One creature that steers (seek, arrive, wander), then flocking from three local rules, then a line that grows into coral.
13. **[Growing things](13-GrowingThings.md).** A recursive tree, L-system grammars, the chaos game and the fractals related to it, growth that fills empty space, frost from frozen walkers, and tiles that must agree.
14. **[Fields and flow](14-FieldsAndFlow.md).** A direction at every point: streamlines, evenly spaced flow, particles carried by the field, and attractors found in formulas.
15. **[Shapes as material](15-ShapesAsMaterial.md).** Geometry you keep and edit as data: booleans, offsets, strokes as regions, Voronoi mosaics, packing, and hatching for pen plotters.

### Part III: Pixels and light

16. **[Layers and effects](16-LayersAndEffects.md).** Off-screen layers, GPU filters, compositing, feedback, accumulation, HDR.
17. **[Your first shader](17-YourFirstShader.md).** Per-pixel thinking, uv space, writing a `shade` function, chaining visuals.
18. **[Iterated forms](18-IteratedForms.md).** Pictures made from the density of an orbit rather than from a drawn shape: the chaos game, fractal flames, the Buddhabrot, circles used as mirrors, Kleinian and Schottky groups, chaotic maps, the bifurcation diagram, and escape-time fractals.
19. **[Simulations on a grid](19-GridSimulations.md).** Fields that carry their own state on the GPU: cellular automata, sand, reaction-diffusion, multi-scale Turing, fluid, ripples, and watercolor.
20. **[Simulations made of particles](20-ParticleSimulations.md).** A buffer of individuals updated by one small program: a million grains, slime mold, ant colonies, Particle Life, crowds at scale, SPH fluid and jellies, and evolution.

### Part IV: The third dimension

21. **[3D, gently](21-3DGently.md).** A camera, solids, lights and materials, air you can see, meshes and their maps, and the depth buffer's own effects.
22. **[Meshes, maps, and materials](22-Meshes.md).** Meshes loaded from a file and built from other meshes, pictures that set what a surface is, texel by texel, and finishes you set with numbers: metal and dielectric, environments as the light source, glass, coated paint, cloth, and skin.
23. **[Landscapes and multitudes](23-Landscapes.md).** Ground grown from noise and weathered by rain, then the four ways to draw more copies of something than you could place by hand: a field of particles, instanced meshes, a world cut down to what the camera sees, and grass that is drawn without ever being built.
24. **[Worlds with weight](24-WorldsWithWeight.md).** Rigid bodies in the 3D scene: stacking and contact, asking what a body would hit, collision groups, degrees of freedom, machines made out of joints, structures that stand on their own cables, and snapshots of a settled world.
25. **[Characters, vehicles, and cloth](25-CharactersAndCloth.md).** The three things a rigid body models badly: a figure that walks, a vehicle on sprung wheels, and cloth, ropes, ragdolls and water.
26. **[Sculpting with fields](26-SculptingWithFields.md).** Distance fields that merge and blend, in 2D and raymarched 3D, then the finish: measured materials, environments, glass, and light that bounces.

### Part V: Out into the world

27. **[Depth and the iPhone as a sensor](27-DepthAndThePhone.md).** Point clouds, recorded and live RGBD, the phone's body, hand, and gaze streams, and scanning the room you're in.
28. **[Sound and control](28-SoundAndControl.md).** Hearing loudness, spectrum, beats, speech and sound events, then the controls in your hands: MIDI, OSC, and game controllers, all bound to the same parameters.
29. **[Making sound](29-MakingSound.md).** A sketch that plays sound: synths and the voices inside them, instruments built by patching or from recordings, physical models of a string, a struck shape, a bow and a tube, then rhythms, scales, chords and tunings, sonification, and sound placed in a room.
30. **[Seeing](30-Seeing.md).** The webcam as input, then faces, hands, bodies, edges, and motion as typed values, then video as material.
31. **[Sharing and performing](31-SharingAndPerforming.md).** Stills, video, GIF, SVG for plotters, prints and 3D prints, USDZ and spatial video, reproducibility, describable output, feeding other apps, handing the work over, and live coding on stage.
32. **[Installations](32-Installations.md).** A piece that stays installed in one place: light instead of pixels through DMX and LED maps, the cost row for when it gets slow, and everything a room does to a sketch left running for weeks.

### Appendices

- **[A. Just enough Swift](A-JustEnoughSwift.md).** The language, for people coming from other languages.
- **[B. Just enough math, visually](B-JustEnoughMath.md).** Every math idea in the guide, each with a picture.
- **[C. Coming from p5.js and Processing](C-ComingFromP5.md).** A side-by-side translation.
- **[D. The complete toolbox](D-CompleteToolbox.md).** Everything Ollin can do, one line each, with where it's taught and where it's documented.

---

If something is confusing, or you get stuck anywhere, that is a bug in the guide, not in you. Please [open an issue](https://github.com/eaviles/Ollin/issues).
